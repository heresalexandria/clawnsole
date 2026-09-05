import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:clawnsole/app/app_controller.dart';
import 'package:clawnsole/core/google_drive.dart';
import 'package:clawnsole/core/composer_tabs.dart';
import 'package:clawnsole/core/google_drive_store.dart';
import 'package:clawnsole/core/durable_data_store.dart';
import 'package:clawnsole/core/direct_gateway.dart';
import 'package:clawnsole/core/hybrid_data_store.dart';
import 'package:clawnsole/core/models.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  test(
    'slow Drive publication never blocks saving newer drafts locally',
    () async {
      final local = _MemoryStore(const StoredData());
      final drive = _SlowWorkspaceDriveStore();
      final hybrid = HybridDataStore(local: local, drive: drive);
      await hybrid.connect('token', 'Studio');
      final staleLibrary = await hybrid.read();
      drive.pending = Completer<void>();
      final first = ComposerTabRecord(
        id: 'draft',
        prompt: 'First',
        updatedAt: DateTime.utc(2026),
      );
      await hybrid.writeComposerWorkspace(ComposerTabsState(tabs: [first]));
      await hybrid.writeComposerWorkspace(
        ComposerTabsState(
          tabs: [
            first.copyWith(
              prompt: 'Latest keystrokes',
              updatedAt: DateTime.utc(2026, 2),
            ),
          ],
        ),
      );
      await hybrid.write(staleLibrary);
      expect(
        (await hybrid.readComposerWorkspace())?.tabs.single.prompt,
        'Latest keystrokes',
      );
      drive.pending!.complete();
      await hybrid.syncComposerWorkspaceToDrive();
      expect(drive.data.composerTabs?.tabs.single.prompt, 'Latest keystrokes');
    },
  );

  test(
    'workspace persists offline and merges cloud tabs on reconnect',
    () async {
      final local = _MemoryStore(const StoredData());
      final drive = _MemoryDriveStore(
        const StoredData(
          composerTabs: ComposerTabsState(
            tabs: [ComposerTabRecord(id: 'phone', prompt: 'Phone draft')],
          ),
        ),
      );
      final hybrid = HybridDataStore(local: local, drive: drive);
      await hybrid.writeComposerWorkspace(
        const ComposerTabsState(
          tabs: [ComposerTabRecord(id: 'desktop', prompt: 'Offline draft')],
        ),
      );
      expect(
        (await hybrid.readComposerWorkspace())?.tabs.single.prompt,
        'Offline draft',
      );
      await hybrid.connect('test-token', 'Studio');
      expect(
        (await hybrid.readComposerWorkspace())?.tabs.map((tab) => tab.id),
        ['desktop', 'phone'],
      );
      expect(drive.data.composerTabs?.tabs.length, 2);
      final relaunched = HybridDataStore(local: local, drive: drive);
      expect((await relaunched.readComposerWorkspace())?.tabs.length, 2);
      await hybrid.writeComposerWorkspace(
        const ComposerTabsState(
          tabs: [ComposerTabRecord(id: 'desktop', prompt: 'Offline draft')],
          closedTabIds: {'phone'},
        ),
      );
      await hybrid.syncComposerWorkspaceToDrive();
      expect(drive.data.composerTabs?.tabs.map((tab) => tab.id), ['desktop']);
    },
  );

  test(
    'native reference writes preserve assignments and reject duplicate characters',
    () async {
      final store = _MemoryStore(const StoredData());
      final gateway = DirectGateway(store: store);
      final now = DateTime.utc(2026);
      SavedReference reference(String id, String character) => SavedReference(
        id: id,
        name: '$id.png',
        characterName: character,
        kind: MediaReferenceKind.image,
        asset: AssetReference(
          kind: 'remote',
          value: 'https://example.com/$id.png',
          label: '$id.png',
        ),
        createdAt: now,
        updatedAt: now,
      );
      await gateway.saveReference(reference('one', 'alexandria'));
      expect(store.data.savedReferences.single.characterName, 'ALEXANDRIA');
      await expectLater(
        gateway.saveReference(reference('two', 'Alexandria')),
        throwsStateError,
      );
      expect(store.data.savedReferences, hasLength(1));
      await gateway.saveReference(reference('one', ''));
      await gateway.saveReference(reference('two', 'Alexandria'));
      expect(
        store.data.savedReferences
            .where((item) => item.characterName == 'ALEXANDRIA')
            .single
            .id,
        'two',
      );
    },
  );

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

  test('Drive merge resolves concurrent edits by updated timestamp', () {
    final created = DateTime.utc(2026, 8, 19, 12);
    final base = LibraryFolder(
      id: 'folder-one',
      name: 'Original',
      createdAt: created,
      updatedAt: created,
      storage: LibraryStorage.drive,
    );
    final local = base.copyWith(
      name: 'Older local edit',
      updatedAt: created.add(const Duration(minutes: 1)),
    );
    final remote = base.copyWith(
      name: 'Newer remote edit',
      updatedAt: created.add(const Duration(minutes: 2)),
    );

    final merged = mergeGoogleDriveData(
      base: StoredData(folders: <LibraryFolder>[base]),
      next: StoredData(folders: <LibraryFolder>[local]),
      remote: StoredData(folders: <LibraryFolder>[remote]),
    );

    expect(merged.folders.single.name, 'Newer remote edit');
    expect(
      merged.folders.single.updatedAt,
      created.add(const Duration(minutes: 2)),
    );
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

  test('Drive listings follow every provider page', () async {
    final pageTokens = <String?>[];
    final api = GoogleDriveApi(
      accessToken: 'token',
      apiBase: Uri.parse('https://drive.test/drive/v3/'),
      client: MockClient((request) async {
        final token = request.url.queryParameters['pageToken'];
        pageTokens.add(token);
        return http.Response(
          jsonEncode(<String, Object?>{
            if (token == null) 'nextPageToken': 'second-page',
            'files': <Object?>[
              <String, Object?>{
                'id': token == null ? 'asset-one' : 'asset-two',
                'name': token == null ? 'one.mp4' : 'two.mp4',
                'mimeType': 'video/mp4',
              },
            ],
          }),
          200,
          headers: const <String, String>{'content-type': 'application/json'},
        );
      }),
    );

    final files = await api.listChildren(
      'assets-folder',
      appPropertyKey: 'clawnsoleAsset',
    );

    expect(pageTokens, <String?>[null, 'second-page']);
    expect(files.map((file) => file.id), <String>['asset-one', 'asset-two']);
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
      expect(migrated.toJson()['schemaVersion'], 26);
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

  test(
    'moveLocalToDrive copies, verifies, then clears the local library',
    () async {
      final local = _migrationLocalStore();
      final drive = _MemoryDriveStore(const StoredData());
      final hybrid = HybridDataStore(local: local, drive: drive);
      await hybrid.connect('token', 'Shared Studio');

      final moved = await hybrid.moveLocalToDrive();

      expect(moved.generations, 1);
      expect(moved.references, 1);
      final after = await hybrid.read();
      expect(after.generations.map((item) => item.localId), <String>[
        'drive-local-generation',
      ]);
      expect(after.savedReferences.map((item) => item.id), <String>[
        'drive-local-reference',
      ]);
      expect(
        after.generations.every((item) => item.storage == LibraryStorage.drive),
        isTrue,
      );
      // The local file keeps device secrets, Drive linkage, and a compact
      // Drive metadata mirror so the next launch can render while offline.
      expect(local.data.generations.map((item) => item.localId), <String>[
        'drive-local-generation',
      ]);
      expect(local.data.savedReferences.map((item) => item.id), <String>[
        'drive-local-reference',
      ]);
      expect(
        local.data.generations.every(
          (item) => item.storage == LibraryStorage.drive,
        ),
        isTrue,
      );
      expect(local.data.driveFolderName, 'Shared Studio');
      expect(local.data.driveFolderId, 'drive-root');
      expect(local.data.apiKeyFor('bfl'), 'device-secret');
      expect(local.assets, isEmpty);
      expect(drive.assets.values, hasLength(2));

      final relaunched = HybridDataStore(
        local: local,
        drive: _MemoryDriveStore(const StoredData()),
      );
      final offline = await relaunched.read();
      expect(offline.generations.map((item) => item.localId), <String>[
        'drive-local-generation',
      ]);
      expect(offline.generations.single.storage, LibraryStorage.drive);

      // A second migration is a no-op rather than an error.
      final again = await hybrid.moveLocalToDrive();
      expect(again.generations, 0);
      expect(again.references, 0);
    },
  );

  test(
    'moveLocalToDrive keeps the local library when a copy is unverified',
    () async {
      final local = _migrationLocalStore();
      final drive = _GenerationDroppingDriveStore(const StoredData());
      final hybrid = HybridDataStore(local: local, drive: drive);
      await hybrid.connect('token', 'Shared Studio');

      await expectLater(hybrid.moveLocalToDrive(), throwsStateError);

      expect(
        local.data.generations.where(
          (item) => item.storage == LibraryStorage.local,
        ),
        hasLength(1),
      );
      expect(
        local.data.savedReferences.where(
          (item) => item.storage == LibraryStorage.local,
        ),
        hasLength(1),
      );
      expect(local.assets, isNotEmpty);
    },
  );

  test(
    'move verifies remote bytes before deleting any local originals',
    () async {
      final local = _migrationLocalStore();
      final drive = _CorruptingMemoryDriveStore();
      final hybrid = HybridDataStore(local: local, drive: drive);
      await hybrid.connect('token', 'Shared Studio');

      await expectLater(hybrid.moveLocalToDrive(), throwsStateError);

      expect(local.data.generations.single.storage, LibraryStorage.local);
      expect(local.data.savedReferences.single.storage, LibraryStorage.local);
      expect(local.assets, hasLength(2));
    },
  );

  test(
    'move keeps source revisions changed during upload verification',
    () async {
      final local = _migrationLocalStore();
      final drive = _EditingMemoryDriveStore(() {
        local.data = local.data.copyWith(
          savedReferences: <SavedReference>[
            local.data.savedReferences.single.copyWith(
              name: 'Edited while moving',
            ),
          ],
        );
      });
      final hybrid = HybridDataStore(local: local, drive: drive);
      await hybrid.connect('token', 'Shared Studio');

      await expectLater(hybrid.moveLocalToDrive(), throwsStateError);

      expect(local.data.savedReferences.single.name, 'Edited while moving');
      expect(local.data.generations.single.storage, LibraryStorage.local);
      expect(local.assets, hasLength(2));
      expect(drive.data.generations, hasLength(1));
    },
  );

  test(
    'Drive state reads revalidate with an ETag instead of re-downloading',
    () async {
      var mediaDownloads = 0;
      final seenValidators = <String?>[];
      final client = _stateFileClient(
        onMedia: (request) {
          seenValidators.add(request.headers['If-None-Match']);
          if (request.headers['If-None-Match'] == 'state-v1') {
            return http.Response('', 304);
          }
          mediaDownloads += 1;
          return http.Response(
            _remoteStateBody(),
            200,
            headers: const <String, String>{'etag': 'state-v1'},
          );
        },
      );
      final store = _mockedDriveStore(client);

      final connected = await store.connect('token', 'Shared Studio');
      expect(connected.generations.single.localId, 'remote-film');
      expect(mediaDownloads, 1);

      final revalidated = await store.read();
      expect(revalidated.generations.single.localId, 'remote-film');
      expect(mediaDownloads, 1);
      expect(seenValidators, <String?>[null, 'state-v1']);
    },
  );

  test('a Drive quota burst keeps the connection for a later retry', () async {
    var mode = 'ok';
    final client = _stateFileClient(
      onMedia: (request) => switch (mode) {
        'rate-limited' => http.Response(
          jsonEncode(<String, Object?>{
            'error': <String, Object?>{
              'message': 'User Rate Limit Exceeded',
              'errors': <Object?>[
                <String, Object?>{
                  'domain': 'usageLimits',
                  'reason': 'userRateLimitExceeded',
                },
              ],
            },
          }),
          403,
        ),
        'revoked' => http.Response(
          jsonEncode(<String, Object?>{
            'error': <String, Object?>{
              'message': 'The user has not granted the app access.',
              'errors': <Object?>[
                <String, Object?>{
                  'domain': 'global',
                  'reason': 'insufficientFilePermissions',
                },
              ],
            },
          }),
          403,
        ),
        _ => http.Response(
          _remoteStateBody(),
          200,
          headers: const <String, String>{'etag': 'state-v1'},
        ),
      },
    );
    final store = _mockedDriveStore(client);
    await store.connect('token', 'Shared Studio');

    mode = 'rate-limited';
    await expectLater(
      store.read(),
      throwsA(
        isA<GoogleDriveException>().having(
          (error) => error.isRateLimited,
          'isRateLimited',
          isTrue,
        ),
      ),
    );
    expect(
      store.connection.isConnected,
      isTrue,
      reason: 'a quota burst is transient and must not forget the session',
    );

    mode = 'revoked';
    await expectLater(
      store.read(),
      throwsA(
        isA<GoogleDriveException>().having(
          (error) => error.isRateLimited,
          'isRateLimited',
          isFalse,
        ),
      ),
    );
    expect(store.connection.isConnected, isFalse);
  });

  test(
    'readCached serves the Drive metadata mirror without Drive traffic',
    () async {
      final now = DateTime.utc(2026, 8, 26, 9);
      final local = _MemoryStore(const StoredData());
      final drive = _CountingMemoryDriveStore(
        StoredData(
          generations: <Generation>[
            Generation(
              localId: 'drive-film',
              status: 'Ready',
              prompt: 'Drive film',
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
              thumbnailAsset: const AssetReference(
                kind: 'drive',
                value: 'drive-thumb',
                label: 'thumb.jpg',
                contentType: 'image/jpeg',
              ),
            ),
          ],
        ),
      );
      final hybrid = HybridDataStore(local: local, drive: drive);
      await hybrid.connect('token', 'Shared Studio');
      drive.stateReads = 0;

      final cached = await hybrid.readCached();

      expect(cached.generations.single.localId, 'drive-film');
      expect(cached.generations.single.storage, LibraryStorage.drive);
      expect(cached.generations.single.thumbnailAsset?.value, 'drive-thumb');
      expect(
        drive.stateReads,
        0,
        reason: 'serving retained media must never wait on Drive',
      );
    },
  );
}

/// A Drive backend holding one root folder, one assets folder, and one state
/// file whose media reads are answered by [onMedia].
MockClient _stateFileClient({
  required http.Response Function(http.Request request) onMedia,
}) => MockClient((request) async {
  final path = request.url.path;
  if (path.endsWith('/files') && request.method == 'GET') {
    final query = request.url.queryParameters['q'] ?? '';
    Map<String, Object?> entry(String id, String name, String mimeType) =>
        <String, Object?>{'id': id, 'name': name, 'mimeType': mimeType};
    final files = query.contains('clawnsoleRoot')
        ? <Object?>[
            entry(
              'root-1',
              'Shared Studio',
              'application/vnd.google-apps.folder',
            ),
          ]
        : query.contains('clawnsoleAssets')
        ? <Object?>[
            entry('assets-1', 'assets', 'application/vnd.google-apps.folder'),
          ]
        : query.contains('clawnsoleState')
        ? <Object?>[entry('state-1', 'clawnsole.json', 'application/json')]
        : <Object?>[];
    return http.Response(
      jsonEncode(<String, Object?>{'files': files}),
      200,
      headers: const <String, String>{'content-type': 'application/json'},
    );
  }
  if (path.endsWith('/files/state-1') && request.method == 'GET') {
    return onMedia(request);
  }
  throw StateError('Unexpected Drive request: ${request.method} $path');
});

GoogleDriveStore _mockedDriveStore(http.Client client) => GoogleDriveStore(
  client: client,
  apiFactory: (token) => GoogleDriveApi(
    accessToken: token,
    apiBase: Uri.parse('https://drive.test/drive/v3/'),
    uploadBase: Uri.parse('https://drive.test/upload/drive/v3/'),
    client: client,
  ),
);

String _remoteStateBody() {
  final now = DateTime.utc(2026, 8, 26, 9);
  return StoredData(
    generations: <Generation>[
      Generation(
        localId: 'remote-film',
        status: 'Ready',
        prompt: 'Remote film',
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
  ).encode();
}

class _CountingMemoryDriveStore extends _MemoryDriveStore {
  _CountingMemoryDriveStore(super.data);

  int stateReads = 0;

  @override
  Future<StoredData> read() async {
    stateReads += 1;
    return super.read();
  }
}

_MemoryStore _migrationLocalStore() {
  final now = DateTime.utc(2026, 8, 20);
  return _MemoryStore(
    StoredData(
      apiKeys: const <String, String>{'bfl': 'device-secret'},
      generations: <Generation>[
        Generation(
          localId: 'local-generation',
          status: 'Ready',
          prompt: 'local generation',
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
          resultAsset: const AssetReference(
            kind: 'local',
            value: 'local-video',
            label: 'local.mp4',
            contentType: 'video/mp4',
          ),
        ),
      ],
      savedReferences: <SavedReference>[
        SavedReference(
          id: 'local-reference',
          name: 'Local reference',
          kind: MediaReferenceKind.image,
          asset: const AssetReference(
            kind: 'local',
            value: 'local-image',
            label: 'reference.png',
            contentType: 'image/png',
          ),
          createdAt: now,
          updatedAt: now,
        ),
      ],
    ),
    assets: <String, Uint8List>{
      'local-video': Uint8List.fromList(<int>[1, 2, 3]),
      'local-image': Uint8List.fromList(<int>[4, 5]),
    },
  );
}

/// Simulates a Drive write that silently loses generation records so the
/// migration's verification step must refuse to delete anything local.
class _GenerationDroppingDriveStore extends _MemoryDriveStore {
  _GenerationDroppingDriveStore(super.data);

  @override
  Future<void> write(StoredData value) =>
      super.write(value.copyWith(generations: const <Generation>[]));
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
  ]) async {
    final retained = <String>{};
    void add(AssetReference? reference) {
      if (reference?.kind == 'local') retained.add(reference!.value);
    }

    for (final generation in generations) {
      add(generation.resultAsset);
      add(generation.thumbnailAsset);
      add(generation.timelineThumbnailAsset);
      add(generation.config.source);
      add(generation.config.sourceThumbnailAsset);
      for (final frame
          in generation.config.keyframes ?? const <KeyframeLabel>[]) {
        add(frame.source);
      }
      for (final media
          in generation.config.references ?? const <MediaReferenceLabel>[]) {
        add(media.source);
        add(media.thumbnailAsset);
      }
    }
    for (final reference in savedReferences) {
      add(reference.asset);
      add(reference.thumbnailAsset);
    }
    assets.removeWhere((id, _) => !retained.contains(id));
  }

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
  Future<GoogleDriveByteStream> readAssetStream(
    AssetReference reference,
  ) async => GoogleDriveByteStream(
    Stream<List<int>>.value(await readAsset(reference)),
  );

  @override
  Future<StorageStats> stats(int records) async => StorageStats(
    path: 'drive',
    bytes: data.encode().length,
    records: records,
  );
}

class _SlowWorkspaceDriveStore extends _MemoryDriveStore {
  _SlowWorkspaceDriveStore() : super(const StoredData());
  Completer<void>? pending;
  @override
  Future<void> write(StoredData value) async {
    await pending?.future;
    await super.write(value);
  }
}

class _CorruptingMemoryDriveStore extends _MemoryDriveStore {
  _CorruptingMemoryDriveStore() : super(const StoredData());

  @override
  Future<GoogleDriveByteStream> readAssetStream(
    AssetReference reference,
  ) async => GoogleDriveByteStream(Stream<List<int>>.value(<int>[99]));
}

class _EditingMemoryDriveStore extends _MemoryDriveStore {
  _EditingMemoryDriveStore(this.onVerification) : super(const StoredData());
  final void Function() onVerification;

  @override
  Future<GoogleDriveByteStream> readAssetStream(
    AssetReference reference,
  ) async {
    onVerification();
    return super.readAssetStream(reference);
  }
}
