import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../app/app_controller.dart';
import '../core/models.dart';

bool get usesIosMediaSourcePicker =>
    !kIsWeb && defaultTargetPlatform == TargetPlatform.iOS;

Future<MediaPickerSource?> chooseMediaPickerSource(
  BuildContext context,
  MediaReferenceKind kind,
) async {
  if (!usesIosMediaSourcePicker) return MediaPickerSource.library;
  final libraryLabel = switch (kind) {
    MediaReferenceKind.image => 'Choose from Photos',
    MediaReferenceKind.video => 'Choose from Photos',
    MediaReferenceKind.audio => 'Choose from Music',
  };
  final libraryIcon = kind == MediaReferenceKind.audio
      ? Icons.library_music_rounded
      : Icons.photo_library_rounded;
  return showModalBottomSheet<MediaPickerSource>(
    context: context,
    showDragHandle: true,
    builder: (sheetContext) => SafeArea(
      child: Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            ListTile(
              key: const ValueKey('media-source-library'),
              leading: Icon(libraryIcon),
              title: Text(libraryLabel),
              onTap: () =>
                  Navigator.pop(sheetContext, MediaPickerSource.library),
            ),
            ListTile(
              key: const ValueKey('media-source-files'),
              leading: const Icon(Icons.folder_open_rounded),
              title: const Text('Browse Files'),
              subtitle: const Text(
                'Choose from On My iPhone, iCloud Drive, or another file provider',
              ),
              onTap: () => Navigator.pop(sheetContext, MediaPickerSource.files),
            ),
          ],
        ),
      ),
    ),
  );
}
