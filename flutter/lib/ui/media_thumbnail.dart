import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../core/async_value_cache.dart';
import '../core/gateway.dart';
import '../core/models.dart';
import 'media_duration_loader.dart';
import 'media_preview_work.dart';
import 'paced_progress_indicator.dart';
import 'video_frame_loader.dart';
import 'video_metadata_loader.dart';

// Encoded image bytes need their own budget: Flutter's decoded image cache
// does not account for byte arrays retained by our completed Futures.
final _assetImageJobs = AsyncValueCache<Uint8List>(
  maximumWeight: 32 * 1024 * 1024,
  weightOf: (bytes) => bytes.buffer.lengthInBytes,
);
final _videoThumbnailJobs = AsyncValueCache<Uint8List?>(
  maximumWeight: 8 * 1024 * 1024,
  weightOf: (bytes) => bytes?.buffer.lengthInBytes ?? 0,
);
final _videoMetadataJobs = AsyncValueCache<VideoSourceMetadata?>(
  maximumWeight: 240,
  weightOf: (_) => 1,
);
final _mediaDurationJobs = AsyncValueCache<double?>(
  maximumWeight: 240,
  weightOf: (_) => 1,
);

class _PreviewMemoryObserver with WidgetsBindingObserver {
  @override
  void didHaveMemoryPressure() {
    _assetImageJobs.clear();
    _videoThumbnailJobs.clear();
    _videoMetadataJobs.clear();
    _mediaDurationJobs.clear();
  }
}

final _previewMemoryObserver = _PreviewMemoryObserver();
WidgetsBinding? _observedBinding;
final _gatewayCacheKeys = Expando<int>('media-preview-gateway');
int _nextGatewayCacheKey = 0;

int _gatewayCacheKey(AppGateway gateway) =>
    _gatewayCacheKeys[gateway] ??= ++_nextGatewayCacheKey;

Object _previewFingerprint(MediaThumbnail input) => (
  _gatewayCacheKey(input.gateway),
  input.kind,
  input.reference?.kind,
  input.reference?.value,
  input.thumbnailReference?.kind,
  input.thumbnailReference?.value,
  input.thumbnailBytes == null ? null : identityHashCode(input.thumbnailBytes),
  input.source,
  input.localPath,
  input.bytes == null ? null : identityHashCode(input.bytes),
  input.mimeType,
  input.mediaUriRevision,
);

/// Decodes at the tile's pixel width instead of the source's: a 1080p frame
/// filling a 200 px tile otherwise costs a full-size decode on every scroll
/// and evicts the whole image cache behind it.
int? _decodeWidthFor(BuildContext context, BoxConstraints constraints) {
  if (!constraints.maxWidth.isFinite || constraints.maxWidth <= 0) return null;
  final ratio = MediaQuery.devicePixelRatioOf(context);
  return (constraints.maxWidth * ratio).ceil();
}

/// A single preview surface for picked, retained, Drive, and remote media.
///
/// Video frames are extracted once per process and can be handed back through
/// [onThumbnail] so the owning record can persist them for future launches.
class MediaThumbnail extends StatefulWidget {
  const MediaThumbnail({
    required this.gateway,
    required this.kind,
    super.key,
    this.bytes,
    this.mimeType,
    this.localPath,
    this.reference,
    this.thumbnailReference,
    this.thumbnailBytes,
    this.source,
    this.fit = BoxFit.cover,
    this.frameLoader,
    this.mediaUriLoader,
    this.mediaUriRevision,
    this.metadataLoader,
    this.durationLoader,
    this.onThumbnail,
    this.onVideoMetadata,
    this.onMediaDuration,
    this.semanticsLabel,
  });

  final AppGateway gateway;
  final MediaReferenceKind kind;
  final Uint8List? bytes;
  final String? mimeType;
  final String? localPath;
  final AssetReference? reference;
  final AssetReference? thumbnailReference;
  final Uint8List? thumbnailBytes;
  final String? source;
  final BoxFit fit;
  final VideoFrameLoader? frameLoader;
  final Future<Uri?> Function()? mediaUriLoader;
  final Object? mediaUriRevision;
  final VideoMetadataLoader? metadataLoader;
  final MediaDurationLoader? durationLoader;
  final ValueChanged<Uint8List>? onThumbnail;
  final ValueChanged<VideoSourceMetadata>? onVideoMetadata;
  final ValueChanged<double>? onMediaDuration;
  final String? semanticsLabel;

  @override
  State<MediaThumbnail> createState() => _MediaThumbnailState();
}

class _MediaThumbnailState extends State<MediaThumbnail> {
  Future<Uint8List>? _imageBytes;
  Future<_VideoThumbnailResult?>? _videoThumbnail;

  int _loadToken = 0;

  @override
  void initState() {
    super.initState();
    if (!identical(_observedBinding, WidgetsBinding.instance)) {
      _observedBinding?.removeObserver(_previewMemoryObserver);
      _observedBinding = WidgetsBinding.instance
        ..addObserver(_previewMemoryObserver);
    }
    _load();
  }

  @override
  void didUpdateWidget(covariant MediaThumbnail oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (_previewFingerprint(oldWidget) != _previewFingerprint(widget) ||
        (oldWidget.onVideoMetadata == null && widget.onVideoMetadata != null) ||
        (oldWidget.onMediaDuration == null && widget.onMediaDuration != null)) {
      _load();
    }
  }

  bool _isCurrent(int token) => mounted && token == _loadToken;

  void _load() {
    final token = ++_loadToken;
    final input = widget;
    // A video tile's frame and metadata share delivery resolution. On web,
    // resolving a picked file can otherwise duplicate its entire data URI.
    Future<Uri?>? resolvedUri;
    Future<Uri?> mediaUri() => resolvedUri ??= _mediaUri(input);
    _imageBytes = null;
    _videoThumbnail = null;
    if (input.kind == MediaReferenceKind.image &&
        input.bytes == null &&
        input.reference?.isLocal == true) {
      _imageBytes = _readAsset(input.gateway, input.reference!);
    } else if (input.kind == MediaReferenceKind.video) {
      _videoThumbnail = _loadVideoThumbnail(input, token, mediaUri);
      if (input.onVideoMetadata != null) {
        unawaited(_loadVideoMetadata(input, token, mediaUri));
      }
    } else if (input.kind == MediaReferenceKind.audio &&
        input.onMediaDuration != null) {
      unawaited(_loadMediaDuration(input, token, mediaUri));
    }
  }

  Future<Uint8List> _readAsset(AppGateway gateway, AssetReference reference) =>
      _assetImageJobs.load((
        _gatewayCacheKey(gateway),
        reference.kind,
        reference.value,
      ), () => gateway.readAsset(reference));

  Future<_VideoThumbnailResult?> _loadVideoThumbnail(
    MediaThumbnail input,
    int token,
    Future<Uri?> Function() mediaUri,
  ) async {
    final providedThumbnail = input.thumbnailBytes;
    if (providedThumbnail != null && providedThumbnail.isNotEmpty) {
      return _VideoThumbnailResult(providedThumbnail);
    }
    final retainedThumbnail = input.thumbnailReference;
    if (retainedThumbnail != null) {
      try {
        final bytes = await _readAsset(input.gateway, retainedThumbnail);
        if (!_isCurrent(token)) return null;
        return _VideoThumbnailResult(bytes);
      } on Object {
        // A stale preview must not hide media that can still make a new frame.
      }
    }
    if (!_isCurrent(token)) return null;
    try {
      final key = (
        _previewFingerprint(input),
        input.frameLoader == null ? null : identityHashCode(input.frameLoader),
      );
      final bytes = await _loadProbe<Uint8List>(
        cache: _videoThumbnailJobs,
        key: key,
        token: token,
        mediaUri: mediaUri,
        probe: (uri) => (input.frameLoader ?? loadVideoFrame)(
          uri,
          const Duration(milliseconds: 250),
        ),
      );
      if (!_isCurrent(token) || bytes == null) return null;
      widget.onThumbnail?.call(bytes);
      return _VideoThumbnailResult(bytes);
    } on Object {
      return null;
    }
  }

  Future<void> _loadVideoMetadata(
    MediaThumbnail input,
    int token,
    Future<Uri?> Function() mediaUri,
  ) async {
    try {
      final key = (
        _previewFingerprint(input),
        input.metadataLoader == null
            ? null
            : identityHashCode(input.metadataLoader),
      );
      final metadata = await _loadProbe<VideoSourceMetadata>(
        cache: _videoMetadataJobs,
        key: key,
        token: token,
        mediaUri: mediaUri,
        probe: input.metadataLoader ?? loadVideoMetadata,
      );
      if (!_isCurrent(token) || metadata == null) return;
      widget.onVideoMetadata?.call(metadata);
    } on Object {
      // URI lookup, platform probes and callbacks are best-effort work. A
      // disconnected source must not escape an unawaited background probe.
    }
  }

  Future<void> _loadMediaDuration(
    MediaThumbnail input,
    int token,
    Future<Uri?> Function() mediaUri,
  ) async {
    try {
      final key = (
        _previewFingerprint(input),
        input.durationLoader == null
            ? null
            : identityHashCode(input.durationLoader),
      );
      final duration = await _loadProbe<double>(
        cache: _mediaDurationJobs,
        key: key,
        token: token,
        mediaUri: mediaUri,
        probe: input.durationLoader ?? loadMediaDuration,
      );
      if (!_isCurrent(token) || duration == null) return;
      widget.onMediaDuration?.call(duration);
    } on Object {
      // Same contract as video metadata: never leak an unhandled async error.
    }
  }

  Future<T?> _loadProbe<T>({
    required AsyncValueCache<T?> cache,
    required Object key,
    required int token,
    required Future<Uri?> Function() mediaUri,
    required Future<T?> Function(Uri uri) probe,
  }) async {
    final cached = cache.lookupFuture(key);
    if (cached != null) return cached;
    if (!_isCurrent(token)) return null;
    // Delivery lookup may wait on disk or network without opening a decoder.
    // Keep it outside the decoder budget so a slow source cannot starve
    // unrelated previews, and empty URL drafts finish immediately.
    final uri = await mediaUri();
    if (!_isCurrent(token) || uri == null) return null;
    return mediaPreviewWork.run(() async {
      if (!_isCurrent(token)) return null;
      // Another visible tile may have filled the cache while this waited.
      final cached = cache.lookupFuture(key);
      if (cached != null) return cached;
      // Only started probes enter the shared cache: cancelling an obsolete
      // queued tile must not cancel another tile that needs the same media.
      return cache.load(key, () => probe(uri));
    });
  }

  Future<Uri?> _mediaUri(MediaThumbnail input) async {
    final loader = input.mediaUriLoader;
    if (loader != null) return loader();
    final path = input.localPath?.trim() ?? '';
    if (path.isNotEmpty) {
      final parsed = Uri.tryParse(path);
      if (kIsWeb && parsed?.hasScheme == true) return parsed;
      return Uri.file(path);
    }
    final reference = input.reference;
    if (reference != null) {
      if (reference.isLocal) return input.gateway.assetUri(reference);
      final remote = Uri.tryParse(reference.value);
      if (remote?.scheme == 'https') {
        return input.gateway.mediaUri(reference.value);
      }
    }
    final source = input.source?.trim() ?? '';
    final remote = Uri.tryParse(source);
    if (remote?.scheme == 'https') return input.gateway.mediaUri(source);
    final bytes = input.bytes;
    if (bytes != null && bytes.isNotEmpty) {
      return Uri.parse(
        'data:${input.mimeType ?? (input.kind == MediaReferenceKind.audio ? 'audio/mpeg' : 'video/mp4')};base64,${base64Encode(bytes)}',
      );
    }
    return null;
  }

  @override
  Widget build(BuildContext context) => Semantics(
    image: true,
    label: widget.semanticsLabel ?? '${widget.kind.label} thumbnail',
    child: switch (widget.kind) {
      MediaReferenceKind.image => _image(context),
      MediaReferenceKind.video => _video(context),
      MediaReferenceKind.audio => const _AudioThumbnail(),
    },
  );

  Widget _decodedImage(Uint8List bytes) => LayoutBuilder(
    builder: (context, constraints) => Image.memory(
      bytes,
      key: const ValueKey('media-thumbnail-image'),
      fit: widget.fit,
      gaplessPlayback: true,
      cacheWidth: _decodeWidthFor(context, constraints),
      errorBuilder: (_, _, _) =>
          const _ThumbnailPlaceholder(icon: Icons.broken_image_outlined),
    ),
  );

  Widget _image(BuildContext context) {
    final bytes = widget.bytes;
    if (bytes != null && bytes.isNotEmpty) return _decodedImage(bytes);
    final reference = widget.reference;
    if (reference != null && !reference.isLocal) {
      return _networkImage(reference.value);
    }
    final source = widget.source?.trim() ?? '';
    if (Uri.tryParse(source)?.scheme == 'https') return _networkImage(source);
    final imageBytes = _imageBytes;
    if (imageBytes == null) {
      return const _ThumbnailPlaceholder(icon: Icons.image_outlined);
    }
    return FutureBuilder<Uint8List>(
      key: ValueKey(_previewFingerprint(widget)),
      future: imageBytes,
      builder: (context, snapshot) {
        if (!snapshot.hasData || snapshot.data!.isEmpty) {
          return _ThumbnailPlaceholder(
            icon: snapshot.hasError
                ? Icons.broken_image_outlined
                : Icons.image_outlined,
            loading: !snapshot.hasError,
          );
        }
        return _decodedImage(snapshot.data!);
      },
    );
  }

  Widget _networkImage(String source) => LayoutBuilder(
    builder: (context, constraints) => Image.network(
      source,
      key: const ValueKey('media-thumbnail-image'),
      fit: widget.fit,
      gaplessPlayback: true,
      cacheWidth: _decodeWidthFor(context, constraints),
      errorBuilder: (_, _, _) =>
          const _ThumbnailPlaceholder(icon: Icons.broken_image_outlined),
      loadingBuilder: (context, child, progress) => progress == null
          ? child
          : const _ThumbnailPlaceholder(
              icon: Icons.image_outlined,
              loading: true,
            ),
    ),
  );

  Widget _video(BuildContext context) {
    final thumbnail = _videoThumbnail;
    if (thumbnail == null) {
      return const _ThumbnailPlaceholder(icon: Icons.movie_outlined);
    }
    return FutureBuilder<_VideoThumbnailResult?>(
      key: ValueKey(_previewFingerprint(widget)),
      future: thumbnail,
      initialData:
          widget.thumbnailBytes != null && widget.thumbnailBytes!.isNotEmpty
          ? _VideoThumbnailResult(widget.thumbnailBytes!)
          : null,
      builder: (context, snapshot) {
        final result = snapshot.data;
        if (result == null || result.bytes.isEmpty) {
          return _ThumbnailPlaceholder(
            icon: Icons.movie_outlined,
            loading: snapshot.connectionState != ConnectionState.done,
          );
        }
        return Stack(
          key: const ValueKey('media-thumbnail-video-frame'),
          fit: StackFit.expand,
          children: <Widget>[
            LayoutBuilder(
              builder: (context, constraints) => Image.memory(
                result.bytes,
                fit: widget.fit,
                gaplessPlayback: true,
                cacheWidth: _decodeWidthFor(context, constraints),
                errorBuilder: (_, _, _) => const _ThumbnailPlaceholder(
                  icon: Icons.broken_image_outlined,
                ),
              ),
            ),
            Center(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: .5),
                  shape: BoxShape.circle,
                ),
                child: const Padding(
                  padding: EdgeInsets.all(4),
                  child: Icon(
                    Icons.play_arrow_rounded,
                    color: Colors.white,
                    size: 16,
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

class _VideoThumbnailResult {
  const _VideoThumbnailResult(this.bytes);

  final Uint8List bytes;
}

class _ThumbnailPlaceholder extends StatelessWidget {
  const _ThumbnailPlaceholder({required this.icon, this.loading = false});

  final IconData icon;
  final bool loading;

  @override
  Widget build(BuildContext context) => ColoredBox(
    color: Theme.of(context).colorScheme.surfaceContainer,
    child: Center(
      child: loading
          ? const SizedBox.square(
              dimension: 16,
              child: PacedCircularProgressIndicator(strokeWidth: 1.8),
            )
          : Icon(
              icon,
              size: 22,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
    ),
  );
}

class _AudioThumbnail extends StatelessWidget {
  const _AudioThumbnail();

  @override
  Widget build(BuildContext context) {
    const heights = <double>[12, 24, 17, 32, 21, 28, 14, 25, 18];
    final scheme = Theme.of(context).colorScheme;
    return ColoredBox(
      color: scheme.surfaceContainer,
      child: Center(
        child: Row(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: heights
              .map(
                (height) => Container(
                  width: 2.5,
                  height: height,
                  margin: const EdgeInsets.symmetric(horizontal: 1.5),
                  decoration: BoxDecoration(
                    color: scheme.primary,
                    borderRadius: BorderRadius.circular(99),
                  ),
                ),
              )
              .toList(),
        ),
      ),
    );
  }
}
