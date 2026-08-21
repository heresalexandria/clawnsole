import 'dart:convert';
import 'dart:typed_data';

import 'package:clawnsole/app/app_controller.dart';
import 'package:clawnsole/core/google_drive.dart';
import 'package:clawnsole/core/google_drive_store.dart';
import 'package:clawnsole/core/durable_data_store.dart';
import 'package:clawnsole/core/direct_gateway.dart';
import 'package:clawnsole/core/hybrid_data_store.dart';
import 'package:clawnsole/core/models.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  test('portable Drive metadata excludes every provider credential', () {
    final portable = googleDrivePortableData(
      const StoredData(
        apiKey: 'bfl-secret',
        apiKeys: <String, String>{'bfl': 'bfl-secret', 'ltx': 'ltx-secret'},
        rejectedIosReviewApiKeyId: 'review-id',
        rejectedIosReviewApiKeyIds: <String, String>{'ltx': 'review-ltx'},
        preferences: AppPreferences(provider: 'ltx'),
      ),
    );

    expect(portable.apiKeys, isEmpty);
    expect(portable.apiKey, isEmpty);
    expect(portable.rejectedIosReviewApiKeyIds, isEmpty);
    expect(portable.preferences.provider, 'bfl');
    expect(portable.preferencesUpdatedAt, isNull);
    expect(portable.encode(), isNot(contains('secret')));
    expect(portable.encode(), isNot(contains('review-id')));
  });

  test('Drive merge preserves unrelated changes from another device', () {
    final now = DateTime.utc(2026, 8, 19, 12);
    Generation generation(String id, String prompt, [int minutes = 0]) =>
        Generation(
          localId: id,
          status: 'Ready',
          prompt: prompt,
          mode: VideoMode.t2v,
          config: const GenerationConfig(
            aspectRatio: '16:9',
            duration: 8,
            resolution: 'hd',
            generateAudio: true,
            safetyTolerance: 2,
            draft: false,
          ),
          createdAt: now.add(Duration(minutes: minutes)),
          updatedAt: now.add(Duration(minutes: minutes)),
        );

    final original = generation('one', 'Original');
    final localEdit = generation('one', 'Edited here');
    final remoteAddition = generation('two', 'Created elsewhere', 1);
    final merged = mergeGoogleDriveData(
      base: StoredData(
        apiKeys: const <String, String>{'bfl': 'device-key'},
        preferences: const AppPreferences(provider: 'bfl'),
        generations: <Generation>[original],
      ),
      next: StoredData(
        apiKeys: const <String, String>{'bfl': 'device-key'},
        preferences: const AppPreferences(provider: 'bfl'),
        generations: <Generation>[localEdit],
      ),
      remote: StoredData(
        preferences: const AppPreferences(provider: 'ltx'),
        generations: <Generation>[remoteAddition, original],
      ),
    );

    expect(merged.generations.map((item) => item.localId), <String>[
      'two',
      'one',
    ]);
    expect(
      merged.generations.singleWhere((item) => item.localId == 'one').prompt,
      'Edited here',
    );
    expect(merged.preferences.provider, 'bfl');
    expect(merged.apiKeys, isEmpty);
  });

  test('Drive folder lookup is app-scoped and authenticated', () async {
    late http.Request observed;
    final api = GoogleDriveApi(
      accessToken: 'short-lived-token',
      apiBase: Uri.parse('https://drive.test/drive/v3/'),
      uploadBase: Uri.parse('https://drive.test/upload/drive/v3/'),
      client: MockClient((request) async {
        observed = request;
        return http.Response(
          jsonEncode(<String, Object?>{
            'files': <Object?>[
              <String, Object?>{
                'id': 'folder-one',
                'name': 'Shared Studio',
                'mimeType': 'application/vnd.google-apps.folder',
              },
            ],
          }),
          200,
          headers: const <String, String>{'content-type': 'application/json'},
        );
      }),
    );

    final folder = await api.findRootFolder('Shared Studio');

    expect(folder?.id, 'folder-one');
    expect(observed.headers['Authorization'], 'Bearer short-lived-token');
    expect(observed.url.queryParameters['q'], contains('clawnsoleRoot'));
    expect(observed.url.queryParameters['q'], contains('Shared Studio'));
    expect(observed.url.queryParameters['spaces'], 'drive');
  });

  test(
    'Drive asset upload uses multipart content and its selected parent',
    () async {
      late http.Request observed;
      final api = GoogleDriveApi(
        accessToken: 'token',
        apiBase: Uri.parse('https://drive.test/drive/v3/'),
        uploadBase: Uri.parse('https://drive.test/upload/drive/v3/'),
        client: MockClient((request) async {
          observed = request;
          return http.Response(
            jsonEncode(<String, Object?>{
              'id': 'asset-one',
              'name': 'clip.mp4',
              'mimeType': 'video/mp4',
              'size': '4',
            }),
            200,
            headers: const <String, String>{'etag': 'asset-etag'},
          );
        }),
      );

      final file = await api.createFile(
        parentId: 'assets-folder',
        name: 'clip.mp4',
        bytes: Uint8List.fromList(<int>[0, 1, 2, 3]),
        contentType: 'video/mp4',
        appProperties: const <String, String>{'clawnsoleAsset': 'true'},
      );

      expect(file.id, 'asset-one');
      expect(file.etag, 'asset-etag');
      expect(observed.method, 'POST');
      expect(observed.url.queryParameters['uploadType'], 'multipart');
      expect(observed.headers['Content-Type'], startsWith('multipart/related'));
      final body = latin1.decode(observed.bodyBytes);
      expect(body, contains('assets-folder'));
      expect(body, contains('clawnsoleAsset'));
      expect(body, contains('video/mp4'));
    },
  );

  test('Drive errors retain status for expired-token handling', () async {
    final api = GoogleDriveApi(
      accessToken: 'expired',
      apiBase: Uri.parse('https://drive.test/drive/v3/'),
      client: MockClient(
        (_) async => http.Response(
          jsonEncode(<String, Object?>{
            'error': <String, Object?>{'message': 'Invalid credentials'},
          }),
          401,
        ),
      ),
    );

    await expectLater(
      api.downloadFile('state-file'),
      throwsA(
        isA<GoogleDriveException>()
            .having((error) => error.status, 'status', 401)
            .having((error) => error.message, 'message', 'Invalid credentials'),
      ),
    );
  });

  test(
    'schema 16 preserves Drive provenance and migrates old items locally',
    () {
      final driveAsset = AssetReference.fromJson(<String, Object?>{
        'kind': 'drive',
        'value': 'file-id',
        'label': 'clip.mp4',
      });
      final migrated = StoredData.decode(
        jsonEncode(<String, Object?>{
          'schemaVersion': 12,
          'generations': <Object?>[
            <String, Object?>{
              'localId': 'legacy',
              'status': 'Ready',
              'prompt': 'Legacy film',
              'mode': 't2v',
              'config': <String, Object?>{},
              'createdAt': '2026-08-19T12:00:00Z',
              'updatedAt': '2026-08-19T12:00:00Z',
            },
          ],
        }),
      );

      expect(driveAsset.kind, 'drive');
      expect(migrated.generations.single.storage, LibraryStorage.local);
      expect(migrated.toJson()['schemaVersion'], 18);
    },
  );

  test('schema 16 round-trips favorites, previews, folders, and views', () {
    final now = DateTime.utc(2026, 8, 19, 12);
    const thumbnail = AssetReference(
      kind: 'drive',
      value: 'thumbnail-file',
      label: 'thumbnail.jpg',
      contentType: 'image/jpeg',
    );
    const timeline = AssetReference(
      kind: 'drive',
      value: 'timeline-file',
      label: 'timeline.png',
      contentType: 'image/png',
    );
    final decoded = StoredData.decode(
      StoredData(
        preferences: const AppPreferences(
          defaultStorage: LibraryStorage.drive,
          recentWorkViewMode: GenerationViewMode.mini,
          libraryViewMode: GenerationViewMode.compact,
          lastLocalGenerationFolderId: 'local-folder',
          lastDriveGenerationFolderId: 'drive-folder',
        ),
        generations: <Generation>[
          Generation(
            localId: 'favorite-film',
            status: 'Ready',
            prompt: 'Favorite film',
            mode: VideoMode.v2v,
            config: const GenerationConfig(
              aspectRatio: '16:9',
              duration: 8,
              resolution: 'hd',
              generateAudio: true,
              safetyTolerance: 2,
              draft: false,
              source: AssetReference(
                kind: 'drive',
                value: 'source-video',
                label: 'source.mp4',
                contentType: 'video/mp4',
              ),
              sourceThumbnailAsset: thumbnail,
              references: <MediaReferenceLabel>[
                MediaReferenceLabel(
                  label: 'motion.mp4',
                  kind: MediaReferenceKind.video,
                  thumbnailAsset: thumbnail,
                ),
              ],
            ),
            createdAt: now,
            updatedAt: now,
            thumbnailAsset: thumbnail,
            timelineThumbnailAsset: timeline,
            favorite: true,
            storage: LibraryStorage.drive,
          ),
        ],
        savedReferences: <SavedReference>[
          SavedReference(
            id: 'favorite-reference',
            name: 'Favorite reference',
            kind: MediaReferenceKind.image,
            asset: thumbnail,
            thumbnailAsset: timeline,
            createdAt: now,
            updatedAt: now,
            favorite: true,
            storage: LibraryStorage.drive,
          ),
        ],
      ).encode(),
    );

    expect(decoded.preferences.lastLocalGenerationFolderId, 'local-folder');
    expect(decoded.preferences.lastDriveGenerationFolderId, 'drive-folder');
    expect(decoded.preferences.recentWorkViewMode, GenerationViewMode.mini);
    expect(decoded.preferences.libraryViewMode, GenerationViewMode.compact);
    expect(decoded.generations.single.favorite, isTrue);
    expect(decoded.generations.single.thumbnailAsset?.value, 'thumbnail-file');
    expect(
      decoded.generations.single.timelineThumbnailAsset?.value,
      'timeline-file',
    );
    expect(
      decoded.generations.single.config.sourceThumbnailAsset?.value,
      'thumbnail-file',
    );
    expect(
      decoded
          .generations
          .single
          .config
          .references
          ?.single
          .thumbnailAsset
          ?.value,
      'thumbnail-file',
    );
    expect(decoded.savedReferences.single.favorite, isTrue);
    expect(
      decoded.savedReferences.single.thumbnailAsset?.value,
      'timeline-file',
    );
  });

  test(
    'preview and favorite updates persist as compact retained assets',
    () async {
      final now = DateTime.utc(2026, 8, 19, 12);
      final store = _MemoryStore(
        StoredData(
          generations: <Generation>[
            Generation(
              localId: 'film',
              status: 'Ready',
              prompt: 'Film',
              mode: VideoMode.t2v,
              config: const GenerationConfig(
                aspectRatio: '16:9',
                duration: 8,
                resolution: 'hd',
                generateAudio: true,
                safetyTolerance: 2,
                draft: false,
              ),
              createdAt: now,
              updatedAt: now,
            ),
          ],
        ),
      );
      final gateway = DirectGateway(store: store);

      await gateway.saveGenerationPreviews(
        'film',
        thumbnailBytes: Uint8List.fromList(<int>[1, 2]),
        timelineBytes: Uint8List.fromList(<int>[3, 4, 5]),
      );
      await gateway.setGenerationFavorite('film', true);

      final film = store.data.generations.single;
      expect(film.favorite, isTrue);
      expect(film.thumbnailAsset?.contentType, 'image/jpeg');
      expect(film.timelineThumbnailAsset?.contentType, 'image/png');
      expect(store.assets, hasLength(2));
    },
  );

  test(
    'video reference and generation-input previews persist by owner',
    () async {
      final now = DateTime.utc(2026, 8, 19, 12);
      const video = AssetReference(
        kind: 'local',
        value: 'retained-video',
        label: 'motion.mp4',
        contentType: 'video/mp4',
      );
      final store = _MemoryStore(
        StoredData(
          generations: <Generation>[
            Generation(
              localId: 'film',
              status: 'Ready',
              prompt: 'Film',
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
                    label: 'motion.mp4',
                    kind: MediaReferenceKind.video,
                    source: video,
                  ),
                ],
              ),
              createdAt: now,
              updatedAt: now,
            ),
          ],
          savedReferences: <SavedReference>[
            SavedReference(
              id: 'motion-reference',
              name: 'Motion',
              kind: MediaReferenceKind.video,
              asset: video,
              createdAt: now,
              updatedAt: now,
            ),
          ],
        ),
      );
      final gateway = DirectGateway(store: store);

      await gateway.saveReferencePreview(
        'motion-reference',
        Uint8List.fromList(<int>[1, 2, 3]),
      );
      await gateway.saveGenerationInputPreview(
        'film',
        video.value,
        Uint8List.fromList(<int>[4, 5, 6]),
      );

      final decoded = StoredData.decode(store.data.encode());
      expect(decoded.savedReferences.single.thumbnailAsset, isNotNull);
      expect(
        decoded.generations.single.config.references!.single.thumbnailAsset,
        isNotNull,
      );
      expect(store.assets, hasLength(2));
    },
  );

  test(
    'generation destination remembers its folder and favorite filters apply',
    () async {
      final now = DateTime.utc(2026, 8, 19, 12);
      Generation film(String id, {required bool favorite}) => Generation(
        localId: id,
        status: 'Ready',
        prompt: id,
        mode: VideoMode.t2v,
        config: const GenerationConfig(
          aspectRatio: '16:9',
          duration: 8,
          resolution: 'hd',
          generateAudio: true,
          safetyTolerance: 2,
          draft: false,
        ),
        createdAt: now,
        updatedAt: now,
        favorite: favorite,
      );
      final store = _MemoryStore(
        StoredData(
          generations: <Generation>[
            film('starred', favorite: true),
            film('plain', favorite: false),
          ],
        ),
      );
      final controller = AppController(gateway: DirectGateway(store: store));
      addTearDown(controller.dispose);
      await controller.initialize();

      expect(
        await controller.saveLibraryFolder(
          'Campaign',
          storage: LibraryStorage.local,
        ),
        isTrue,
      );
      final folderId = controller.folders.single.id;
      await controller.setGenerationFolder(folderId);
      controller.setLibraryFavoriteFilter(FavoriteFilter.starred);

      expect(store.data.preferences.lastLocalGenerationFolderId, folderId);
      expect(controller.selectedGenerationFolderId, folderId);
      expect(
        controller.filteredGenerations.map((item) => item.localId),
        <String>['starred'],
      );
    },
  );

  test(
    'hybrid library combines stores and copies local media idempotently',
    () async {
      final now = DateTime.utc(2026, 8, 19, 12);
      final localAsset = const AssetReference(
        kind: 'local',
        value: 'local-video',
        label: 'local.mp4',
        contentType: 'video/mp4',
      );
      final referenceAsset = const AssetReference(
        kind: 'local',
        value: 'local-image',
        label: 'reference.png',
        contentType: 'image/png',
      );
      final thumbnailAsset = const AssetReference(
        kind: 'local',
        value: 'local-thumbnail',
        label: 'thumbnail.jpg',
        contentType: 'image/jpeg',
      );
      final timelineAsset = const AssetReference(
        kind: 'local',
        value: 'local-timeline',
        label: 'timeline.png',
        contentType: 'image/png',
      );
      Generation generation(String id, LibraryStorage storage) => Generation(
        localId: id,
        status: 'Ready',
        prompt: id,
        mode: VideoMode.t2v,
        config: const GenerationConfig(
          aspectRatio: '16:9',
          duration: 8,
          resolution: 'hd',
          generateAudio: true,
          safetyTolerance: 2,
          draft: false,
        ),
        createdAt: now,
        updatedAt: now,
        resultAsset: storage == LibraryStorage.local ? localAsset : null,
        thumbnailAsset: storage == LibraryStorage.local ? thumbnailAsset : null,
        timelineThumbnailAsset: storage == LibraryStorage.local
            ? timelineAsset
            : null,
        favorite: storage == LibraryStorage.local,
        storage: storage,
      );

      final local = _MemoryStore(
        StoredData(
          apiKeys: const <String, String>{'bfl': 'device-secret'},
          preferences: const AppPreferences(provider: 'bfl'),
          preferencesUpdatedAt: now,
          generations: <Generation>[
            generation('local-generation', LibraryStorage.local),
          ],
          savedReferences: <SavedReference>[
            SavedReference(
              id: 'local-reference',
              name: 'Local reference',
              kind: MediaReferenceKind.image,
              asset: referenceAsset,
              createdAt: now,
              updatedAt: now,
              favorite: true,
            ),
          ],
        ),
        assets: <String, Uint8List>{
          'local-video': Uint8List.fromList(<int>[1, 2, 3]),
          'local-image': Uint8List.fromList(<int>[4, 5]),
          'local-thumbnail': Uint8List.fromList(<int>[6, 7]),
          'local-timeline': Uint8List.fromList(<int>[8, 9]),
        },
      );
      final drive = _MemoryDriveStore(
        StoredData(
          preferences: const AppPreferences(provider: 'ltx'),
          preferencesUpdatedAt: now.add(const Duration(minutes: 1)),
          generations: <Generation>[
            generation('drive-generation', LibraryStorage.drive),
          ],
        ),
      );
      final hybrid = HybridDataStore(local: local, drive: drive);

      final connected = await hybrid.connect('token', 'Shared Studio');
      expect(
        connected.generations.map((item) => item.localId).toSet(),
        <String>{'local-generation', 'drive-generation'},
      );
      expect(connected.preferences.provider, 'ltx');
      expect(connected.apiKeyFor('bfl'), 'device-secret');

      final first = await hybrid.copyLocalToDrive(
        generationIds: const <String>{'local-generation'},
      );
      final second = await hybrid.copyLocalToDrive(
        generationIds: const <String>{'local-generation'},
      );
      final referencesOnly = await hybrid.copyLocalToDrive(
        referenceIds: const <String>{'local-reference'},
      );
      final copied = await hybrid.read();

      expect(first.generations, 1);
      expect(first.references, 0);
      expect(second.generations, 0);
      expect(second.references, 0);
      expect(referencesOnly.generations, 0);
      expect(referencesOnly.references, 1);
      expect(
        copied.generations.map((item) => item.localId),
        containsAll(<String>['local-generation', 'drive-local-generation']),
      );
      expect(
        copied.savedReferences.map((item) => item.id),
        containsAll(<String>['local-reference', 'drive-local-reference']),
      );
      expect(drive.assets.values, hasLength(4));
      expect(
        copied.generations
            .singleWhere((item) => item.localId == 'drive-local-generation')
            .favorite,
        isTrue,
      );
      expect(
        copied.savedReferences
            .singleWhere((item) => item.id == 'drive-local-reference')
            .favorite,
        isTrue,
      );
      expect(drive.data.encode(), isNot(contains('device-secret')));

      await hybrid.disconnect();
      final offline = await hybrid.read();
      await hybrid.write(
        offline.copyWith(
          preferences: const AppPreferences(provider: 'atlas'),
          preferencesUpdatedAt: now.add(const Duration(minutes: 2)),
        ),
      );
      expect(local.data.preferences.provider, 'atlas');
      await expectLater(
        hybrid.write(
          offline.copyWith(
            generations: <Generation>[
              ...offline.generations,
              copied.generations.firstWhere(
                (item) => item.storage == LibraryStorage.drive,
              ),
            ],
          ),
        ),
        throwsStateError,
      );
    },
  );
}

class _MemoryStore implements DurableDataStore {
  _MemoryStore(this.data, {Map<String, Uint8List>? assets})
    : assets = assets ?? <String, Uint8List>{};

  StoredData data;
  final Map<String, Uint8List> assets;
  int _assetCounter = 0;

  @override
  Future<StoredData> read() async => data;

  @override
  Future<void> write(StoredData value) async => data = value;

  @override
  Future<AssetReference> writeAsset(
    Uint8List bytes, {
    required String label,
    required String contentType,
    LibraryStorage storage = LibraryStorage.local,
  }) async {
    final id = 'asset-${_assetCounter++}';
    assets[id] = bytes;
    return AssetReference(
      kind: storage == LibraryStorage.drive ? 'drive' : 'local',
      value: id,
      label: label,
      contentType: contentType,
      bytes: bytes.length,
    );
  }

  @override
  Future<AssetReference?> persistSource(
    String source, {
    required String label,
    AssetReference? retained,
    LibraryStorage storage = LibraryStorage.local,
  }) async => retained;

  @override
  Future<Uint8List> readAsset(AssetReference reference) async =>
      assets[reference.value] ?? Uint8List(0);

  @override
  Future<Uri> assetUri(AssetReference reference) async =>
      Uri.parse('memory:${reference.value}');

  @override
  Future<void> pruneAssets(
    List<Generation> generations, [
    List<SavedReference> savedReferences = const <SavedReference>[],
  ]) async {}

  @override
  Future<void> delete() async {
    data = const StoredData();
    assets.clear();
  }

  @override
  Future<StorageStats> stats(int records) async => StorageStats(
    path: 'memory',
    bytes: data.encode().length,
    records: records,
  );
}

class _MemoryDriveStore extends GoogleDriveStore {
  _MemoryDriveStore(this.data);

  StoredData data;
  final Map<String, Uint8List> assets = <String, Uint8List>{};
  int _assetCounter = 0;
  GoogleDriveConnection _memoryConnection = const GoogleDriveConnection(
    state: GoogleDriveConnectionState.disconnected,
  );

  @override
  GoogleDriveConnection get connection => _memoryConnection;

  @override
  Future<StoredData> connect(String accessToken, String folderName) async {
    _memoryConnection = GoogleDriveConnection(
      state: GoogleDriveConnectionState.connected,
      folderName: folderName,
      folderId: 'drive-root',
    );
    return data;
  }

  @override
  Future<void> disconnect() async {
    _memoryConnection = GoogleDriveConnection(
      state: GoogleDriveConnectionState.disconnected,
      folderName: connection.folderName,
      folderId: connection.folderId,
    );
  }

  @override
  Future<StoredData> read() async => data;

  @override
  Future<void> write(StoredData value) async =>
      data = googleDrivePortableData(value);

  @override
  Future<AssetReference> writeAsset(
    Uint8List bytes, {
    required String label,
    required String contentType,
    LibraryStorage storage = LibraryStorage.drive,
  }) async {
    final id = 'drive-asset-${_assetCounter++}';
    assets[id] = bytes;
    return AssetReference(
      kind: 'drive',
      value: id,
      label: label,
      contentType: contentType,
      bytes: bytes.length,
    );
  }

  @override
  Future<Uint8List> readAsset(AssetReference reference) async =>
      assets[reference.value] ?? Uint8List(0);

  @override
  Future<StorageStats> stats(int records) async => StorageStats(
    path: 'drive',
    bytes: data.encode().length,
    records: records,
  );
}
