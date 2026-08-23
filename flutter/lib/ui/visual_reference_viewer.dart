import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../app/app_controller.dart';
import '../core/models.dart';
import 'generation_video.dart';
import 'media_thumbnail.dart';

/// Opens an image or video reference on a dedicated fullscreen surface.
///
/// The arguments mirror [MediaThumbnail], so picked media can be viewed before
/// it has a durable asset and retained/remote media can use its existing
/// delivery path without presentation code copying it into history.
Future<void> showVisualReferenceViewer(
  BuildContext context, {
  required AppController controller,
  required MediaReferenceKind kind,
  required String label,
  Uint8List? bytes,
  String? mimeType,
  String? localPath,
  AssetReference? reference,
  AssetReference? thumbnailReference,
  Uint8List? thumbnailBytes,
  String? source,
  Future<Uri?>? deferredVideoUri,
  ValueListenable<double?>? videoProgress,
  Future<void> Function(VideoSaveDestination destination)? onVideoDownload,
}) {
  if (kind == MediaReferenceKind.video) {
    return showVideoPlayerModal(
      context,
      deferredUri:
          deferredVideoUri ??
          _referenceVideoUri(
            controller,
            bytes: bytes,
            mimeType: mimeType,
            localPath: localPath,
            reference: reference,
            source: source,
          ),
      progress: videoProgress,
      forceFullscreen: true,
      supportsPhotos: controller.supportsPhotoLibrarySave,
      onDownload:
          onVideoDownload ??
          (destination) => _saveVideoReference(
            controller,
            label: label,
            reference: reference,
            source: source,
            destination: destination,
          ),
    );
  }
  if (kind != MediaReferenceKind.image) return Future<void>.value();
  return Navigator.of(context).push<void>(
    MaterialPageRoute<void>(
      fullscreenDialog: true,
      builder: (context) => _VisualReferenceImagePage(
        controller: controller,
        label: label,
        bytes: bytes,
        mimeType: mimeType,
        localPath: localPath,
        reference: reference,
        thumbnailReference: thumbnailReference,
        thumbnailBytes: thumbnailBytes,
        source: source,
      ),
    ),
  );
}

Future<void> showSavedReferenceViewer(
  BuildContext context,
  AppController controller,
  SavedReference reference,
) {
  if (reference.kind == MediaReferenceKind.video) {
    final delivery = controller.referenceMediaDelivery(reference);
    return showVisualReferenceViewer(
      context,
      controller: controller,
      kind: reference.kind,
      label: reference.name,
      reference: reference.asset,
      thumbnailReference: reference.thumbnailAsset,
      deferredVideoUri: delivery.uri,
      videoProgress: delivery.progress,
      onVideoDownload: (destination) =>
          controller.saveReferenceVideo(reference, destination: destination),
    );
  }
  return showVisualReferenceViewer(
    context,
    controller: controller,
    kind: reference.kind,
    label: reference.name,
    reference: reference.asset,
    thumbnailReference: reference.thumbnailAsset,
  );
}

Future<Uri?> _referenceVideoUri(
  AppController controller, {
  Uint8List? bytes,
  String? mimeType,
  String? localPath,
  AssetReference? reference,
  String? source,
}) async {
  final path = localPath?.trim() ?? '';
  if (path.isNotEmpty) {
    final parsed = Uri.tryParse(path);
    if (kIsWeb && parsed?.hasScheme == true) return parsed;
    return Uri.file(path);
  }
  if (reference != null) {
    if (reference.isLocal) return controller.gateway.assetUri(reference);
    if (Uri.tryParse(reference.value)?.scheme == 'https') {
      return controller.gateway.mediaUri(reference.value);
    }
  }
  final remote = source?.trim() ?? '';
  if (Uri.tryParse(remote)?.scheme == 'https') {
    return controller.gateway.mediaUri(remote);
  }
  if (bytes != null && bytes.isNotEmpty) {
    return Uri.parse(
      'data:${mimeType ?? 'video/mp4'};base64,${base64Encode(bytes)}',
    );
  }
  return null;
}

Future<void> _saveVideoReference(
  AppController controller, {
  required String label,
  required AssetReference? reference,
  required String? source,
  required VideoSaveDestination destination,
}) async {
  final remote = source?.trim() ?? '';
  final asset =
      reference ??
      (Uri.tryParse(remote)?.scheme == 'https'
          ? AssetReference(
              kind: 'remote',
              value: remote,
              label: label,
              contentType: 'video/mp4',
            )
          : null);
  if (asset == null) {
    controller.showNotice('Save this reference to References to download it.');
    return;
  }
  final now = DateTime.now().toUtc();
  await controller.saveReferenceVideo(
    SavedReference(
      id: 'reference-viewer',
      name: label,
      kind: MediaReferenceKind.video,
      asset: asset,
      createdAt: now,
      updatedAt: now,
    ),
    destination: destination,
  );
}

class _VisualReferenceImagePage extends StatelessWidget {
  const _VisualReferenceImagePage({
    required this.controller,
    required this.label,
    this.bytes,
    this.mimeType,
    this.localPath,
    this.reference,
    this.thumbnailReference,
    this.thumbnailBytes,
    this.source,
  });

  final AppController controller;
  final String label;
  final Uint8List? bytes;
  final String? mimeType;
  final String? localPath;
  final AssetReference? reference;
  final AssetReference? thumbnailReference;
  final Uint8List? thumbnailBytes;
  final String? source;

  @override
  Widget build(BuildContext context) => Scaffold(
    key: const ValueKey('visual-reference-viewer'),
    backgroundColor: Colors.black,
    appBar: AppBar(
      backgroundColor: Colors.black,
      foregroundColor: Colors.white,
      title: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis),
      actions: <Widget>[
        if (reference != null)
          IconButton(
            tooltip: 'Download image',
            onPressed: () => unawaited(() async {
              try {
                await controller.saveReferenceImage(reference!);
              } on Object catch (error) {
                controller.showErrorNotice(error);
              }
            }()),
            icon: const Icon(Icons.download_rounded),
          ),
      ],
    ),
    body: SafeArea(
      top: false,
      child: LayoutBuilder(
        builder: (context, constraints) => InteractiveViewer(
          minScale: 1,
          maxScale: 6,
          child: SizedBox(
            width: constraints.maxWidth,
            height: constraints.maxHeight,
            child: MediaThumbnail(
              gateway: controller.gateway,
              kind: MediaReferenceKind.image,
              bytes: bytes,
              mimeType: mimeType,
              localPath: localPath,
              reference: reference,
              thumbnailReference: thumbnailReference,
              thumbnailBytes: thumbnailBytes,
              source: source,
              fit: BoxFit.contain,
              semanticsLabel: '$label full-screen reference',
            ),
          ),
        ),
      ),
    ),
  );
}
