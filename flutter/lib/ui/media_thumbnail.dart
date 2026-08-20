import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../core/gateway.dart';
import '../core/models.dart';
import 'video_frame_loader.dart';
import 'video_metadata_loader.dart';

final Map<String, Future<Uint8List>> _assetImageJobs =
    <String, Future<Uint8List>>{};
final Map<String, Future<Uint8List?>> _videoThumbnailJobs =
    <String, Future<Uint8List?>>{};
final Map<String, Future<VideoSourceMetadata?>> _videoMetadataJobs =
    <String, Future<VideoSourceMetadata?>>{};

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
    this.metadataLoader,
    this.onThumbnail,
    this.onVideoMetadata,
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
  final VideoMetadataLoader? metadataLoader;
  final ValueChanged<Uint8List>? onThumbnail;
  final ValueChanged<VideoSourceMetadata>? onVideoMetadata;
  final String? semanticsLabel;

  @override
  State<MediaThumbnail> createState() => _MediaThumbnailState();
}

class _MediaThumbnailState extends State<MediaThumbnail> {
  Future<Uint8List>? _imageBytes;
  Future<_VideoThumbnailResult?>? _videoThumbnail;

  String get _fingerprint => <Object?>[
    widget.kind.name,
    widget.reference?.kind,
    widget.reference?.value,
    widget.thumbnailReference?.kind,
    widget.thumbnailReference?.value,
    widget.thumbnailBytes == null
        ? null
        : identityHashCode(widget.thumbnailBytes),
    widget.source,
    widget.localPath,
    widget.bytes == null ? null : identityHashCode(widget.bytes),
  ].join(':');

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(covariant MediaThumbnail oldWidget) {
    super.didUpdateWidget(oldWidget);
    final oldFingerprint = <Object?>[
      oldWidget.kind.name,
      oldWidget.reference?.kind,
      oldWidget.reference?.value,
      oldWidget.thumbnailReference?.kind,
      oldWidget.thumbnailReference?.value,
      oldWidget.thumbnailBytes == null
          ? null
          : identityHashCode(oldWidget.thumbnailBytes),
      oldWidget.source,
      oldWidget.localPath,
      oldWidget.bytes == null ? null : identityHashCode(oldWidget.bytes),
    ].join(':');
    if (oldFingerprint != _fingerprint) _load();
  }

  void _load() {
    _imageBytes = null;
    _videoThumbnail = null;
    if (widget.kind == MediaReferenceKind.image &&
        widget.bytes == null &&
        widget.reference?.isLocal == true) {
      _imageBytes = _readAsset(widget.reference!);
    } else if (widget.kind == MediaReferenceKind.video) {
      _videoThumbnail = _loadVideoThumbnail();
      if (widget.onVideoMetadata != null) unawaited(_loadVideoMetadata());
    }
  }

  Future<Uint8List> _readAsset(AssetReference reference) {
    final key = '${reference.kind}:${reference.value}';
    final existing = _assetImageJobs[key];
    if (existing != null) return existing;
    late final Future<Uint8List> job;
    job = widget.gateway.readAsset(reference).catchError((Object error) {
      if (identical(_assetImageJobs[key], job)) _assetImageJobs.remove(key);
      throw error;
    });
    _assetImageJobs[key] = job;
    return job;
  }

  Future<_VideoThumbnailResult?> _loadVideoThumbnail() async {
    final providedThumbnail = widget.thumbnailBytes;
    if (providedThumbnail != null && providedThumbnail.isNotEmpty) {
      return _VideoThumbnailResult(providedThumbnail);
    }
    final retainedThumbnail = widget.thumbnailReference;
    if (retainedThumbnail != null) {
      try {
        return _VideoThumbnailResult(await _readAsset(retainedThumbnail));
      } on Object {
        // A stale preview must not hide media that can still make a new frame.
      }
    }
    final key = _fingerprint;
    var job = _videoThumbnailJobs[key];
    if (job == null) {
      late final Future<Uint8List?> created;
      created = _generateVideoThumbnail()
          .then((bytes) {
            if (bytes == null && identical(_videoThumbnailJobs[key], created)) {
              _videoThumbnailJobs.remove(key);
            }
            return bytes;
          })
          .catchError((Object error) {
            if (identical(_videoThumbnailJobs[key], created)) {
              _videoThumbnailJobs.remove(key);
            }
            throw error;
          });
      _videoThumbnailJobs[key] = created;
      job = created;
    }
    try {
      final bytes = await job;
      if (bytes == null) return null;
      widget.onThumbnail?.call(bytes);
      return _VideoThumbnailResult(bytes);
    } on Object {
      return null;
    }
  }

  Future<Uint8List?> _generateVideoThumbnail() async {
    final uri = await _videoUri();
    if (uri == null) return null;
    return (widget.frameLoader ?? loadVideoFrame)(
      uri,
      const Duration(milliseconds: 250),
    );
  }

  Future<void> _loadVideoMetadata() async {
    final uri = await _videoUri();
    if (uri == null) return;
    final key = _fingerprint;
    var job = _videoMetadataJobs[key];
    if (job == null) {
      late final Future<VideoSourceMetadata?> created;
      created = (widget.metadataLoader ?? loadVideoMetadata)(uri)
          .then((metadata) {
            if (metadata == null &&
                identical(_videoMetadataJobs[key], created)) {
              _videoMetadataJobs.remove(key);
            }
            return metadata;
          })
          .catchError((Object error) {
            if (identical(_videoMetadataJobs[key], created)) {
              _videoMetadataJobs.remove(key);
            }
            return null;
          });
      _videoMetadataJobs[key] = created;
      job = created;
    }
    final metadata = await job;
    if (!mounted || metadata == null) return;
    widget.onVideoMetadata?.call(metadata);
  }

  Future<Uri?> _videoUri() async {
    final path = widget.localPath?.trim() ?? '';
    if (path.isNotEmpty) {
      final parsed = Uri.tryParse(path);
      if (kIsWeb && parsed?.hasScheme == true) return parsed;
      return Uri.file(path);
    }
    final reference = widget.reference;
    if (reference != null) {
      if (reference.isLocal) return widget.gateway.assetUri(reference);
      final remote = Uri.tryParse(reference.value);
      if (remote?.scheme == 'https') {
        return widget.gateway.mediaUri(reference.value);
      }
    }
    final source = widget.source?.trim() ?? '';
    final remote = Uri.tryParse(source);
    if (remote?.scheme == 'https') return widget.gateway.mediaUri(source);
    final bytes = widget.bytes;
    if (bytes != null && bytes.isNotEmpty) {
      return Uri.parse(
        'data:${widget.mimeType ?? 'video/mp4'};base64,${base64Encode(bytes)}',
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

  Widget _image(BuildContext context) {
    final bytes = widget.bytes;
    if (bytes != null && bytes.isNotEmpty) {
      return Image.memory(
        bytes,
        key: const ValueKey('media-thumbnail-image'),
        fit: widget.fit,
        gaplessPlayback: true,
        errorBuilder: (_, _, _) =>
            const _ThumbnailPlaceholder(icon: Icons.broken_image_outlined),
      );
    }
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
        return Image.memory(
          snapshot.data!,
          key: const ValueKey('media-thumbnail-image'),
          fit: widget.fit,
          gaplessPlayback: true,
        );
      },
    );
  }

  Widget _networkImage(String source) => Image.network(
    source,
    key: const ValueKey('media-thumbnail-image'),
    fit: widget.fit,
    gaplessPlayback: true,
    errorBuilder: (_, _, _) =>
        const _ThumbnailPlaceholder(icon: Icons.broken_image_outlined),
    loadingBuilder: (context, child, progress) => progress == null
        ? child
        : const _ThumbnailPlaceholder(
            icon: Icons.image_outlined,
            loading: true,
          ),
  );

  Widget _video(BuildContext context) {
    final thumbnail = _videoThumbnail;
    if (thumbnail == null) {
      return const _ThumbnailPlaceholder(icon: Icons.movie_outlined);
    }
    return FutureBuilder<_VideoThumbnailResult?>(
      future: thumbnail,
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
            Image.memory(result.bytes, fit: widget.fit, gaplessPlayback: true),
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
              child: CircularProgressIndicator(strokeWidth: 1.8),
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
