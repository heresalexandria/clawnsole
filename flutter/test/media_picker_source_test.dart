import 'package:clawnsole/app/app_controller.dart';
import 'package:clawnsole/app/app_theme.dart';
import 'package:clawnsole/core/models.dart';
import 'package:clawnsole/ui/create_screen.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('iOS reference uploads offer Photos and Files', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    await tester.binding.setSurfaceSize(const Size(390, 1400));
    FileType? pickerType;
    bool? pickerAllowsMultiple;
    final controller =
        AppController(
            filePicker:
                ({
                  required FileType type,
                  required bool allowMultiple,
                  required bool withData,
                }) async {
                  pickerType = type;
                  pickerAllowsMultiple = allowMultiple;
                  return FilePickerResult(<PlatformFile>[
                    PlatformFile(
                      name: 'reference.mov',
                      size: 4,
                      bytes: Uint8List.fromList(<int>[0, 1, 2, 3]),
                    ),
                  ]);
                },
          )
          ..selectedProviderId = 'atlas'
          ..selectedModelId = 'bytedance/seedance-2.5/reference-to-video';
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.binding.setSurfaceSize(null);
      debugDefaultTargetPlatformOverride = null;
      controller.dispose();
    });

    try {
      await tester.pumpWidget(
        MaterialApp(
          theme: buildClawnsoleTheme(Brightness.light),
          home: Scaffold(body: CreateScreen(controller: controller)),
        ),
      );
      expect(tester.takeException(), isNull);
      await tester.tap(
        find.byKey(const ValueKey<String>('add-video-reference')),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await tester.tap(find.text('Upload videos'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);

      expect(find.text('Choose from Photos'), findsOneWidget);
      expect(find.text('Browse Files'), findsOneWidget);
      expect(find.textContaining('On My iPhone, iCloud Drive'), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('media-source-files')));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);

      expect(pickerType, FileType.any);
      expect(pickerAllowsMultiple, isTrue);
      expect(controller.form.referenceCount(MediaReferenceKind.video), 1);
      expect(controller.form.references.single.asset?.name, 'reference.mov');
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });

  test('Photos keeps the type-specific native media picker', () async {
    FileType? pickerType;
    final controller =
        AppController(
            filePicker:
                ({
                  required FileType type,
                  required bool allowMultiple,
                  required bool withData,
                }) async {
                  pickerType = type;
                  return FilePickerResult(<PlatformFile>[
                    PlatformFile(
                      name: 'library.mov',
                      size: 2,
                      bytes: Uint8List.fromList(<int>[0, 1]),
                    ),
                  ]);
                },
          )
          ..selectedProviderId = 'atlas'
          ..selectedModelId = 'bytedance/seedance-2.5/reference-to-video';
    addTearDown(controller.dispose);

    await controller.addMediaReferences(MediaReferenceKind.video);

    expect(pickerType, FileType.video);
    expect(controller.form.referenceCount(MediaReferenceKind.video), 1);
  });

  test('Files accepts HEIC references for normalization', () async {
    final controller =
        AppController(
            filePicker:
                ({
                  required FileType type,
                  required bool allowMultiple,
                  required bool withData,
                }) async => FilePickerResult(<PlatformFile>[
                  PlatformFile(
                    name: 'portrait.heic',
                    size: 3,
                    bytes: Uint8List.fromList(<int>[1, 2, 3]),
                  ),
                ]),
          )
          ..selectedProviderId = 'atlas'
          ..selectedModelId = 'bytedance/seedance-2.5/reference-to-video';
    addTearDown(controller.dispose);

    await controller.addMediaReferences(
      MediaReferenceKind.image,
      source: MediaPickerSource.files,
    );

    expect(controller.form.referenceCount(MediaReferenceKind.image), 1);
    expect(controller.form.references.single.asset?.name, 'portrait.heic');
  });

  test('Files rejects a mismatched reference kind', () async {
    final controller =
        AppController(
            filePicker:
                ({
                  required FileType type,
                  required bool allowMultiple,
                  required bool withData,
                }) async => FilePickerResult(<PlatformFile>[
                  PlatformFile(
                    name: 'notes.txt',
                    size: 3,
                    bytes: Uint8List.fromList(<int>[1, 2, 3]),
                  ),
                ]),
          )
          ..selectedProviderId = 'atlas'
          ..selectedModelId = 'bytedance/seedance-2.5/reference-to-video';
    addTearDown(controller.dispose);

    await controller.addMediaReferences(
      MediaReferenceKind.video,
      source: MediaPickerSource.files,
    );

    expect(controller.form.references, isEmpty);
    expect(controller.notice, 'Choose a video file from Files.');
  });
}
