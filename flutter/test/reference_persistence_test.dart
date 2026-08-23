import 'dart:convert';
import 'dart:typed_data';

import 'package:clawnsole/app/app_controller.dart';
import 'package:clawnsole/core/gateway.dart';
import 'package:clawnsole/core/models.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const emptySnapshot = LocalSnapshot(
    generations: <Generation>[],
    preferences: AppPreferences(),
    hasApiKey: false,
    storage: StorageStats(path: 'memory', bytes: 0, records: 0),
  );

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

    expect(migrated.toJson()['schemaVersion'], 21);
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

class _ReferenceGateway implements AppGateway, ReferenceLibraryGateway {
  _ReferenceGateway(this.snapshot);

  LocalSnapshot snapshot;
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
