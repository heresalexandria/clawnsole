import 'package:flutter/material.dart';

import '../app/app_controller.dart';
import '../core/models.dart';

Future<void> saveGenerationVideo(
  BuildContext context,
  AppController controller,
  Generation item,
) async {
  final destination = await chooseVideoSaveDestination(
    context,
    supportsPhotos: controller.supportsPhotoLibrarySave,
    isImage: item.isImage,
  );
  if (destination == null) return;
  try {
    await controller.saveMedia(item, destination: destination);
  } on Object catch (error) {
    controller.showErrorNotice(error);
  }
}

Future<VideoSaveDestination?> chooseVideoSaveDestination(
  BuildContext context, {
  required bool supportsPhotos,
  bool isImage = false,
}) {
  if (!supportsPhotos) {
    return Future<VideoSaveDestination?>.value(VideoSaveDestination.files);
  }

  return showModalBottomSheet<VideoSaveDestination>(
    context: context,
    showDragHandle: true,
    builder: (context) => SafeArea(
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
              'Choose where Clawnsole should put this ${isImage ? 'image' : 'video'}.',
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            const SizedBox(height: 16),
            ListTile(
              leading: const Icon(Icons.photo_library_outlined),
              title: const Text('Save to Photos'),
              subtitle: Text(
                'Add the ${isImage ? 'image' : 'video'} to your camera roll',
              ),
              trailing: const Icon(Icons.chevron_right_rounded),
              onTap: () => Navigator.pop(context, VideoSaveDestination.photos),
            ),
            ListTile(
              leading: const Icon(Icons.folder_outlined),
              title: const Text('Save to Files'),
              subtitle: const Text('Choose a folder and filename'),
              trailing: const Icon(Icons.chevron_right_rounded),
              onTap: () => Navigator.pop(context, VideoSaveDestination.files),
            ),
          ],
        ),
      ),
    ),
  );
}
