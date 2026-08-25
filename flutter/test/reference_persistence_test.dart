import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:clawnsole/app/app_controller.dart';
import 'package:clawnsole/app/app_theme.dart';
import 'package:clawnsole/core/gateway.dart';
import 'package:clawnsole/core/models.dart';
import 'package:clawnsole/ui/create_screen.dart';
import 'package:clawnsole/ui/references_screen.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const emptySnapshot = LocalSnapshot(
    generations: <Generation>[],
    preferences: AppPreferences(),
    hasApiKey: false,
    storage: StorageStats(path: 'memory', bytes: 0, records: 0),
  );

  testWidgets('reference upload shows loading while the picker reads a file', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1000, 1400));
    final pickerResult = Completer<FilePickerResult?>();
    final gateway = _ReferenceGateway(emptySnapshot);
    final controller =
        AppController(
            gateway: gateway,
            filePicker:
                ({
                  required FileType type,
                  required bool allowMultiple,
                  required bool withData,
                }) => pickerResult.future,
          )
          ..snapshot = emptySnapshot
          ..loading = false
          ..selectedProviderId = 'artcraft'
          ..selectedModelId = 'seedance_2p5';
    addTearDown(() async {
      if (!pickerResult.isCompleted) pickerResult.complete(null);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.binding.setSurfaceSize(null);
      controller.dispose();
    });
    await tester.pumpWidget(
      MaterialApp(
        theme: buildClawnsoleTheme(Brightness.light),
        home: Scaffold(
          body: ListenableBuilder(
            listenable: controller,
            builder: (context, _) => CreateScreen(controller: controller),
          ),
        ),
      ),
    );

    final upload = controller.addMediaReferences(MediaReferenceKind.image);
    await tester.pump();

    expect(controller.referenceUploadInProgress, isTrue);
    expect(find.byKey(const ValueKey('reference-upload-progress')), findsOne);
    expect(find.text('Waiting for image selection…'), findsOne);
    expect(controller.form.references, isEmpty);

    pickerResult.complete(null);
    await upload;
    await tester.pump();

    expect(controller.referenceUploadInProgress, isFalse);
    expect(
      find.byKey(const ValueKey('reference-upload-progress')),
      findsNothing,
    );
    expect(controller.form.references, isEmpty);
  });

  test(
    'reference loader stays active through processing and persistence',
    () async {
      final saveStarted = Completer<void>();
      final finishSave = Completer<void>();
      final bytes = Uint8List.fromList(<int>[1, 2, 3, 4]);
      final gateway = _ReferenceGateway(
        emptySnapshot,
        beforeSave: () async {
          if (!saveStarted.isCompleted) saveStarted.complete();
          await finishSave.future;
        },
      );
      final controller = AppController(
        gateway: gateway,
        filePicker: _picker(<FileType, PlatformFile>{
          FileType.image: PlatformFile(
            name: 'large-reference.heic',
            size: bytes.length,
            bytes: bytes,
          ),
        }),
      );
      addTearDown(() {
        if (!finishSave.isCompleted) finishSave.complete();
        controller.dispose();
      });
      await controller.initialize();
      await controller.selectProviderModel('artcraft', 'seedance_2p5');

      final upload = controller.addMediaReferences(MediaReferenceKind.image);
      await saveStarted.future.timeout(const Duration(seconds: 5));

      expect(controller.referenceUploadInProgress, isTrue);
      expect(
        controller.referenceUploadStatus,
        'Uploading large-reference.heic…',
      );
      expect(controller.form.references, isEmpty);

      finishSave.complete();
      await upload;

      expect(controller.referenceUploadInProgress, isFalse);
      expect(controller.referenceUploadStatus, isNull);
      expect(controller.form.references, hasLength(1));
    },
  );

  testWidgets('References shows one progress card per selected file', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1200, 1000));
    final saveStarted = Completer<void>();
    final finishSave = Completer<void>();
    final gateway = _ReferenceGateway(
      emptySnapshot,
      beforeSave: () async {
        if (!saveStarted.isCompleted) saveStarted.complete();
        await finishSave.future;
      },
    );
    final first = Uint8List.fromList(<int>[1, 2, 3]);
    final second = Uint8List.fromList(<int>[4, 5, 6]);
    final controller =
        AppController(
            gateway: gateway,
            filePicker:
                ({
                  required FileType type,
                  required bool allowMultiple,
                  required bool withData,
                }) async => FilePickerResult(<PlatformFile>[
                  PlatformFile(
                    name: 'one.png',
                    size: first.length,
                    bytes: first,
                  ),
                  PlatformFile(
                    name: 'two.png',
                    size: second.length,
                    bytes: second,
                  ),
                ]),
          )
          ..snapshot = emptySnapshot
          ..loading = false;
    var disposed = false;
    addTearDown(() async {
      if (!finishSave.isCompleted) finishSave.complete();
      if (!disposed) {
        await tester.pumpWidget(const SizedBox.shrink());
        controller.dispose();
      }
      await tester.binding.setSurfaceSize(null);
    });
    await tester.pumpWidget(
      MaterialApp(
        theme: buildClawnsoleTheme(Brightness.light),
        home: Scaffold(
          body: ListenableBuilder(
            listenable: controller,
            builder: (context, _) => ReferencesScreen(controller: controller),
          ),
        ),
      ),
    );

    final upload = controller.importSavedReferences(MediaReferenceKind.image);
    await tester.pump();

    expect(saveStarted.isCompleted, isTrue, reason: controller.notice);
    expect(controller.referenceImports, hasLength(2));
    expect(find.text('one.png'), findsOneWidget);
    expect(find.text('two.png'), findsOneWidget);
    expect(find.text('Uploading 1 of 2'), findsOneWidget);
    expect(find.text('Waiting to upload'), findsOneWidget);

    finishSave.complete();
    await tester.pump();
    await upload;

    expect(controller.referenceImports, isEmpty);
    expect(controller.savedReferences, hasLength(2));
    expect(find.text('Uploading 1 of 2'), findsNothing);

    await tester.pumpWidget(const SizedBox.shrink());
    controller.dispose();
    disposed = true;
  });

  test(
    'References video imports persist the preview made from picked media',
    () async {
      final video = Uint8List.fromList(<int>[1, 2, 3, 4]);
      final frame = Uint8List.fromList(<int>[9, 8, 7]);
      final gateway = _ReferenceGateway(emptySnapshot);
      final controller = AppController(
        gateway: gateway,
        filePicker:
            ({
              required FileType type,
              required bool allowMultiple,
              required bool withData,
            }) async => FilePickerResult(<PlatformFile>[
              PlatformFile(
                name: 'character.mp4',
                size: video.length,
                bytes: video,
              ),
            ]),
      )..snapshot = emptySnapshot;
      addTearDown(controller.dispose);
      PickedAsset? previewAsset;
      String? previewSource;

      await controller.importSavedReferences(
        MediaReferenceKind.video,
        previewLoader: (asset, source) async {
          previewAsset = asset;
          previewSource = source;
          return frame;
        },
      );

      expect(previewAsset?.name, 'character.mp4');
      expect(previewSource, startsWith('data:video/mp4;base64,'));
      final saved = controller.savedReferences.single;
      expect(saved.thumbnailAsset, isNotNull);
      expect(await gateway.readAsset(saved.thumbnailAsset!), frame);
      expect(controller.cachedReferencePreview(saved), frame);
    },
  );

  testWidgets('References uses one thumbnail ratio for every video card', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1200, 1000));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final now = DateTime.utc(2026, 8, 25);
    final references = <SavedReference>[
      for (final id in <String>['landscape', 'portrait'])
        SavedReference(
          id: id,
          name: '$id.mp4',
          kind: MediaReferenceKind.video,
          asset: AssetReference(
            kind: 'local',
            value: '$id.mp4',
            label: '$id.mp4',
            contentType: 'video/mp4',
          ),
          createdAt: now,
          updatedAt: now,
        ),
    ];
    final snapshot = emptySnapshot.copyWith(savedReferences: references);
    final controller = AppController(gateway: _ReferenceGateway(snapshot))
      ..snapshot = snapshot
      ..loading = false;
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      MaterialApp(
        theme: buildClawnsoleTheme(Brightness.light),
        home: Scaffold(body: ReferencesScreen(controller: controller)),
      ),
    );
    await tester.pump();

    for (final id in <String>['landscape', 'portrait']) {
      final cardMedia = find.byKey(ValueKey('view-saved-reference-$id'));
      final ratio = tester.widget<AspectRatio>(
        find.ancestor(of: cardMedia, matching: find.byType(AspectRatio)).first,
      );
      expect(ratio.aspectRatio, 16 / 9);
    }
    expect(find.byIcon(Icons.play_circle_fill_rounded), findsNothing);
  });

  test(
    'Create image uploads auto-save once and keep durable identity',
    () async {
      final gateway = _ReferenceGateway(emptySnapshot);
      final bytes = Uint8List.fromList(<int>[1, 2, 3, 4]);
      final controller = AppController(
        gateway: gateway,
        filePicker: _picker(<FileType, PlatformFile>{
          FileType.image: PlatformFile(
            name: 'subject.heic',
            size: bytes.length,
            bytes: bytes,
          ),
        }),
      );
      await controller.initialize();
      await controller.selectProviderModel('artcraft', 'seedance_2p5');

      await controller.addMediaReferences(MediaReferenceKind.image);

      expect(controller.savedReferences, hasLength(1));
      final saved = controller.savedReferences.single;
      expect(saved.name, 'subject.heic');
      expect(saved.asset.kind, 'local');
      expect(saved.contentDigest, hasLength(64));
      expect(controller.form.references.single.savedReferenceId, saved.id);
      expect(controller.currentConfig.references!.single.referenceId, saved.id);

      controller.removeReference(controller.form.references.single.id);
      await controller.addMediaReferences(MediaReferenceKind.image);

      expect(controller.savedReferences, hasLength(1));
      expect(controller.form.references.single.savedReferenceId, saved.id);
      controller.dispose();
    },
  );

  test('keyframe and source-video uploads also auto-save', () async {
    final gateway = _ReferenceGateway(emptySnapshot);
    final image = Uint8List.fromList(<int>[5, 6, 7]);
    final video = Uint8List.fromList(<int>[8, 9, 10, 11]);
    final controller = AppController(
      gateway: gateway,
      filePicker: _picker(<FileType, PlatformFile>{
        FileType.image: PlatformFile(
          name: 'opening.heic',
          size: image.length,
          bytes: image,
        ),
        FileType.video: PlatformFile(
          name: 'continuation.mov',
          size: video.length,
          bytes: video,
        ),
      }),
    );
    await controller.initialize();

    await controller.addImageFrame(KeyframeRole.start);
    final frameReferenceId = controller.form.keyframes.single.savedReferenceId;
    expect(frameReferenceId, isNotNull);
    expect(
      controller.currentConfig.keyframes!.single.referenceId,
      frameReferenceId,
    );

    controller.removeFrame(controller.form.keyframes.single.id);
    await controller.pickVideo();
    final videoReferenceId = controller.form.videoSavedReferenceId;
    expect(videoReferenceId, isNotNull);
    expect(controller.currentConfig.sourceReferenceId, videoReferenceId);
    expect(controller.savedReferences, hasLength(2));
    expect(
      controller.savedReferences.map((item) => item.kind),
      containsAll(<MediaReferenceKind>[
        MediaReferenceKind.image,
        MediaReferenceKind.video,
      ]),
    );
    controller.dispose();
  });

  test(
    'upload filenames deconflict while explicit names stay unique',
    () async {
      final now = DateTime.utc(2026, 8, 23);
      final existing = SavedReference(
        id: 'existing-reference',
        name: 'motion.mp4',
        kind: MediaReferenceKind.video,
        asset: const AssetReference(
          kind: 'local',
          value: 'existing-motion',
          label: 'motion.mp4',
          contentType: 'video/mp4',
          bytes: 99,
        ),
        createdAt: now,
        updatedAt: now,
      );
      final snapshot = LocalSnapshot(
        generations: const <Generation>[],
        savedReferences: <SavedReference>[existing],
        preferences: const AppPreferences(),
        hasApiKey: false,
        storage: const StorageStats(path: 'memory', bytes: 0, records: 1),
      );
      final bytes = Uint8List.fromList(<int>[10, 20, 30]);
      final gateway = _ReferenceGateway(snapshot);
      final controller = AppController(
        gateway: gateway,
        filePicker: _picker(<FileType, PlatformFile>{
          FileType.video: PlatformFile(
            name: 'motion.mp4',
            size: bytes.length,
            bytes: bytes,
          ),
        }),
      );
      addTearDown(controller.dispose);
      await controller.initialize();
      await controller.selectProviderModel(
        'atlas',
        'bytedance/seedance-2.5/reference-to-video',
      );

      await controller.addMediaReferences(MediaReferenceKind.video);

      final draft = controller.form.references.single;
      expect(controller.referencePromptName(draft), 'Video 1');
      expect(
        controller.savedReferences.map((reference) => reference.name),
        containsAll(<String>['motion.mp4', 'motion.mp4 2']),
      );
      expect(
        await controller.renameDraftReference(draft.id, 'motion.mp4'),
        isFalse,
      );
      expect(
        await controller.renameDraftReference(draft.id, 'Video 7'),
        isFalse,
      );
      expect(
        await controller.renameDraftReference(draft.id, 'Alexandria'),
        isTrue,
      );
      expect(
        controller.savedReferences
            .singleWhere((reference) => reference.id == draft.savedReferenceId)
            .name,
        'Alexandria',
      );
    },
  );

  test('usage lookup survives normalized derivative assets', () {
    final now = DateTime.utc(2026, 8, 23, 12);
    final reference = SavedReference(
      id: 'reference-subject',
      name: 'Subject',
      kind: MediaReferenceKind.image,
      asset: const AssetReference(
        kind: 'local',
        value: 'original-heic',
        label: 'subject.heic',
        contentType: 'image/heic',
      ),
      createdAt: now,
      updatedAt: now,
    );
    Generation generation(
      String id,
      DateTime createdAt, {
      String? referenceId,
    }) => Generation(
      localId: id,
      status: 'Ready',
      prompt: id,
      mode: VideoMode.i2v,
      config: GenerationConfig(
        aspectRatio: '9:16',
        duration: 8,
        resolution: 'hd',
        generateAudio: true,
        safetyTolerance: 2,
        draft: false,
        references: <MediaReferenceLabel>[
          MediaReferenceLabel(
            label: 'Subject',
            kind: MediaReferenceKind.image,
            referenceId: referenceId,
            source: const AssetReference(
              kind: 'local',
              value: 'normalized-jpeg',
              label: 'subject.jpg',
              contentType: 'image/jpeg',
            ),
          ),
        ],
      ),
      createdAt: createdAt,
      updatedAt: createdAt,
    );
    final controller = AppController();
    controller.snapshot = LocalSnapshot(
      generations: <Generation>[
        generation('linked', now, referenceId: reference.id),
        generation('unlinked', now.add(const Duration(minutes: 1))),
      ],
      savedReferences: <SavedReference>[reference],
      preferences: const AppPreferences(),
      hasApiKey: false,
      storage: const StorageStats(path: 'memory', bytes: 0, records: 2),
    );

    expect(
      controller
          .generationsUsingReference(reference)
          .map((item) => item.localId),
      <String>['linked'],
    );
    controller.dispose();
  });

  test('schema v21 migrates asset-linked reference usage ids', () {
    final now = DateTime.utc(2026, 8, 23);
    const asset = AssetReference(
      kind: 'local',
      value: 'legacy-asset',
      label: 'legacy.png',
      contentType: 'image/png',
    );
    final data = StoredData(
      savedReferences: <SavedReference>[
        SavedReference(
          id: 'legacy-reference',
          name: 'Legacy',
          kind: MediaReferenceKind.image,
          asset: asset,
          createdAt: now,
          updatedAt: now,
        ),
      ],
      generations: <Generation>[
        Generation(
          localId: 'legacy-generation',
          status: 'Ready',
          prompt: 'Legacy',
          mode: VideoMode.i2v,
          config: const GenerationConfig(
            aspectRatio: '16:9',
            duration: 8,
            resolution: 'hd',
            generateAudio: true,
            safetyTolerance: 2,
            draft: false,
            references: <MediaReferenceLabel>[
              MediaReferenceLabel(
                label: 'Legacy',
                kind: MediaReferenceKind.image,
                source: asset,
              ),
            ],
          ),
          createdAt: now,
          updatedAt: now,
        ),
      ],
    );
    final json = jsonDecode(data.encode()) as Map<String, Object?>;
    json['schemaVersion'] = 20;

    final migrated = StoredData.fromJson(json);

    expect(migrated.toJson()['schemaVersion'], 22);
    expect(
      migrated.generations.single.config.references!.single.referenceId,
      'legacy-reference',
    );
  });
}

FilePickerInvocation _picker(Map<FileType, PlatformFile> files) =>
    ({
      required FileType type,
      required bool allowMultiple,
      required bool withData,
    }) async {
      final file = files[type];
      return file == null ? null : FilePickerResult(<PlatformFile>[file]);
    };

class _ReferenceGateway
    implements AppGateway, ReferenceLibraryGateway, MediaPreviewGateway {
  _ReferenceGateway(this.snapshot, {this.beforeSave});

  LocalSnapshot snapshot;
  final Future<void> Function()? beforeSave;
  final Map<String, Uint8List> _assets = <String, Uint8List>{};

  @override
  bool get usesCompanion => false;

  @override
  bool get supportsPhotoLibrarySave => false;

  @override
  String get persistenceDescription => 'Memory';

  @override
  Future<LocalSnapshot> load() async => snapshot;

  @override
  Future<LocalSnapshot> saveReference(
    SavedReference reference, {
    String? source,
  }) async {
    await beforeSave?.call();
    var asset = reference.asset;
    if (source != null) {
      final comma = source.indexOf(',');
      final bytes = base64Decode(source.substring(comma + 1));
      final id = reference.id;
      _assets[id] = bytes;
      asset = AssetReference(
        kind: 'local',
        value: id,
        label: reference.name,
        contentType: reference.asset.contentType,
        bytes: bytes.length,
      );
    }
    final saved = reference.copyWith(asset: asset);
    final references = <SavedReference>[
      saved,
      ...snapshot.savedReferences.where((item) => item.id != saved.id),
    ];
    snapshot = snapshot.copyWith(savedReferences: references);
    return snapshot;
  }

  @override
  Future<LocalSnapshot> deleteReference(String referenceId) async {
    snapshot = snapshot.copyWith(
      savedReferences: snapshot.savedReferences
          .where((item) => item.id != referenceId)
          .toList(),
    );
    return snapshot;
  }

  @override
  Future<LocalSnapshot> saveReferencePreview(
    String referenceId,
    Uint8List thumbnailBytes,
  ) async {
    final value = '$referenceId-thumbnail.jpg';
    _assets[value] = thumbnailBytes;
    final thumbnail = AssetReference(
      kind: 'local',
      value: value,
      label: value,
      contentType: 'image/jpeg',
      bytes: thumbnailBytes.length,
    );
    snapshot = snapshot.copyWith(
      savedReferences: snapshot.savedReferences
          .map(
            (item) => item.id == referenceId
                ? item.copyWith(thumbnailAsset: thumbnail)
                : item,
          )
          .toList(),
    );
    return snapshot;
  }

  @override
  Future<LocalSnapshot> saveGenerationInputPreview(
    String localId,
    String sourceAssetValue,
    Uint8List thumbnailBytes,
  ) async => snapshot;

  @override
  Future<LocalSnapshot> setPreferences(AppPreferences preferences) async {
    snapshot = snapshot.copyWith(preferences: preferences);
    return snapshot;
  }

  @override
  Future<Uint8List> readAsset(AssetReference reference) async =>
      _assets[reference.value] ?? Uint8List(0);

  @override
  Future<Uri> assetUri(AssetReference reference) async =>
      Uri.parse('memory://${reference.value}');

  @override
  Uri mediaUri(String source) => Uri.parse(source);

  @override
  Future<Uint8List> downloadMedia(String source) async => Uint8List(0);

  @override
  Future<void> saveMediaToPhotoLibrary(
    Uint8List bytes,
    String fileName,
    String contentType,
  ) async {}

  @override
  Future<LocalSnapshot> setApiKey(String value) async => snapshot;

  @override
  Future<double> verifyKey([String? candidate]) async => 0;

  @override
  Future<double> getCredits() async => 0;

  @override
  Future<Generation> submit(GenerationSubmission submission) async =>
      submission.record;

  @override
  Future<Generation> poll(Generation generation) async => generation;

  @override
  Future<LocalSnapshot> deleteGeneration(String localId) async => snapshot;

  @override
  Future<LocalSnapshot> clearHistory() async => snapshot;

  @override
  Future<LocalSnapshot> clearPreferences() async => snapshot;

  @override
  Future<LocalSnapshot> clearApiKey() async => snapshot;

  @override
  Future<LocalSnapshot> clearAll() async => snapshot;
}
