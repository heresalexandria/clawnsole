import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../app/app_controller.dart';
import '../core/models.dart';
import '../core/native_gateway.dart';

/// The system share sheet is an iOS affordance; other platforms keep the two
/// save destinations.
bool get supportsMediaShareSheet =>
    !kIsWeb && defaultTargetPlatform == TargetPlatform.iOS;

Future<void> saveGenerationVideo(
  BuildContext context,
  AppController controller,
  Generation item,
) async {
  final destination = await chooseVideoSaveDestination(
    context,
    supportsPhotos: controller.supportsPhotoLibrarySave,
    isImage: item.isImage,
    onShare: shareGenerationMediaAction(controller, item),
  );
  if (destination == null) return;
  try {
    await controller.saveMedia(item, destination: destination);
  } on Object catch (error) {
    controller.showErrorNotice(error);
  }
}

/// The sheet's Share… action for [item], or null where no share sheet
/// exists. Errors surface as notices here: the sheet has already closed by
/// the time the share runs, so no caller is left to catch them.
Future<void> Function()? shareGenerationMediaAction(
  AppController controller,
  Generation item,
) {
  final gateway = controller.gateway;
  if (gateway is! NativeGateway || !gateway.supportsShareSheet) return null;
  return () async {
    try {
      await gateway.shareMedia(item);
    } on Object catch (error) {
      controller.showErrorNotice(error);
    }
  };
}

enum _SaveSheetChoice { photos, files, share }

/// Asks where the media should go. [onShare] adds a Share… row on iOS that
/// runs once the sheet has closed; the sheet then resolves to null because no
/// save destination was chosen. The callback owns its own error handling.
Future<VideoSaveDestination?> chooseVideoSaveDestination(
  BuildContext context, {
  required bool supportsPhotos,
  bool isImage = false,
  Future<void> Function()? onShare,
}) async {
  if (!supportsPhotos) return VideoSaveDestination.files;

  final noun = isImage ? 'image' : 'video';
  final showShare = onShare != null && supportsMediaShareSheet;
  final choice = await showModalBottomSheet<_SaveSheetChoice>(
    context: context,
    showDragHandle: true,
    builder: (context) => SafeArea(
      // A third destination pushes the sheet past its height cap on a short
      // screen — a landscape phone, or a large text size — so the body
      // scrolls rather than overflowing.
      child: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              Text(
                isImage ? 'Save image' : 'Save video',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 6),
              Text(
                'Choose where Clawnsole should put this $noun.',
                style: Theme.of(context).textTheme.bodyMedium,
              ),
              const SizedBox(height: 16),
              ListTile(
                leading: const Icon(Icons.photo_library_outlined),
                title: const Text('Save to Photos'),
                subtitle: Text('Add the $noun to your camera roll'),
                trailing: const Icon(Icons.chevron_right_rounded),
                onTap: () => Navigator.pop(context, _SaveSheetChoice.photos),
              ),
              ListTile(
                leading: const Icon(Icons.folder_outlined),
                title: const Text('Save to Files'),
                subtitle: const Text('Choose a folder and filename'),
                trailing: const Icon(Icons.chevron_right_rounded),
                onTap: () => Navigator.pop(context, _SaveSheetChoice.files),
              ),
              if (showShare)
                ListTile(
                  leading: const Icon(Icons.ios_share_rounded),
                  title: const Text('Share…'),
                  subtitle: Text(
                    'Send the $noun with AirDrop, Messages, or another app',
                  ),
                  trailing: const Icon(Icons.chevron_right_rounded),
                  onTap: () => Navigator.pop(context, _SaveSheetChoice.share),
                ),
            ],
          ),
        ),
      ),
    ),
  );
  if (choice == _SaveSheetChoice.share) {
    await onShare?.call();
    return null;
  }
  return switch (choice) {
    _SaveSheetChoice.photos => VideoSaveDestination.photos,
    _SaveSheetChoice.files => VideoSaveDestination.files,
    _SaveSheetChoice.share || null => null,
  };
}
