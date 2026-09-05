import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:clawnsole/core/durable_data_store.dart';
import 'package:clawnsole/core/composer_tabs.dart';
import 'package:clawnsole/core/google_drive.dart';
import 'package:clawnsole/core/google_drive_store.dart';
import 'package:clawnsole/core/hybrid_data_store.dart';
import 'package:clawnsole/core/local_data_store_io.dart';
import 'package:clawnsole/core/models.dart';
import 'package:clawnsole/core/secure_value_store.dart';
import 'package:clawnsole/core/settings_vault_data_store.dart';

final now = DateTime.utc(2026, 9, 5);
LibraryFolder folder(String id, String name) => LibraryFolder(
  id: id,
  name: name,
  createdAt: now,
  updatedAt: now,
  storage: LibraryStorage.drive,
);
void main() {
  test(
    'rejected metadata never publishes its ETag over the valid cache',
    () async {
      final api = FakeApi(const StoredData());
      final drive = GoogleDriveStore(apiFactory: (_) => api);
      await drive.connect('token', 'Studio');
      api.pendingRead = Completer<GoogleDriveContent?>()
        ..complete(
          GoogleDriveContent(
            Uint8List.fromList(utf8.encode('{"schemaVersion":999}')),
            etag: 'future-schema',
          ),
        );

      await expectLater(drive.read(), throwsUnsupportedError);
      await expectLater(drive.read(), throwsUnsupportedError);

      expect(api.validators.last, 'rev-1');
      expect(drive.lastData, isNotNull);
      expect(drive.connection.isConnected, isTrue);
    },
  );
  for (final renewed in [false, true]) {
    test(
      'late successful read cannot publish after ${renewed ? 'renewal' : 'disconnect'}',
      () async {
        final oldData = StoredData(folders: [folder('old', 'Old work')]);
        final freshData = StoredData(folders: [folder('fresh', 'Fresh work')]);
        final oldApi = FakeApi(oldData);
        final renewedApi = FakeApi(freshData);
        final drive = GoogleDriveStore(
          apiFactory: (token) => token == 'old' ? oldApi : renewedApi,
        );
        await drive.connect('old', 'Old studio');
        oldApi.pendingRead = Completer<GoogleDriveContent?>();
        final oldRead = drive.read();
        final rejected = expectLater(oldRead, throwsStateError);
        if (renewed) {
          await drive.connect('new', 'New studio');
        } else {
          await drive.disconnect();
        }
        oldApi.pendingRead!.complete(
          GoogleDriveContent(
            Uint8List.fromList(utf8.encode(oldData.encode())),
            etag: 'stale-response',
          ),
        );
        await rejected;

        expect(drive.connection.isConnected, renewed);
        expect(drive.lastData?.folders.single.id, renewed ? 'fresh' : null);
        if (renewed) {
          expect((await drive.read()).folders.single.id, 'fresh');
        }
      },
    );
  }

  for (final renewed in [false, true]) {
    test(
      'late connection cannot replace ${renewed ? 'a newer connection' : 'signout'}',
      () async {
        final oldApi = FakeApi(const StoredData())
          ..pendingRoot = Completer<GoogleDriveFile?>();
        final renewedApi = FakeApi(const StoredData());
        final drive = GoogleDriveStore(
          apiFactory: (token) => token == 'old' ? oldApi : renewedApi,
        );
        final oldConnect = drive.connect('old', 'Old studio');
        final rejected = expectLater(oldConnect, throwsStateError);
        if (renewed) {
          await drive.connect('new', 'New studio');
        } else {
          await drive.disconnect();
        }
        oldApi.pendingRoot!.complete(oldApi.f('old-root'));
        await rejected;

        expect(drive.connection.isConnected, renewed);
        expect(
          drive.connection.folderName,
          renewed ? 'New studio' : 'Old studio',
        );
        expect(oldApi.childQueries, 0);
      },
    );
  }

  test(
    'late metadata write cannot overwrite a renewed session cache',
    () async {
      final oldApi = FakeApi(const StoredData());
      final renewedApi = FakeApi(
        StoredData(folders: [folder('fresh', 'Fresh work')]),
      );
      final drive = GoogleDriveStore(
        apiFactory: (token) => token == 'old' ? oldApi : renewedApi,
      );
      await drive.connect('old', 'Old studio');
      oldApi.pendingUpdate = Completer<GoogleDriveFile>();
      oldApi.updateStarted = Completer<void>();
      final oldWrite = drive.write(
        StoredData(folders: [folder('old', 'Old work')]),
      );
      final rejected = expectLater(oldWrite, throwsStateError);
      await oldApi.updateStarted!.future;

      await drive.connect('new', 'New studio');
      oldApi.pendingUpdate!.complete(oldApi.f('old-state'));
      await rejected;

      expect(drive.connection.isConnected, isTrue);
      expect(drive.connection.folderName, 'New studio');
      expect(drive.lastData!.folders.single.id, 'fresh');
      expect((await drive.read()).folders.single.id, 'fresh');
    },
  );
  test(
    'an old token failure cannot disconnect a renewed Drive session',
    () async {
      final oldApi = FakeApi(const StoredData());
      final renewedApi = FakeApi(const StoredData());
      final drive = GoogleDriveStore(
        apiFactory: (token) => token == 'old' ? oldApi : renewedApi,
      );
      await drive.connect('old', 'Studio');
      oldApi.pendingRead = Completer<GoogleDriveContent?>();
      final oldRead = drive.read();
      final failure = expectLater(
        oldRead,
        throwsA(isA<GoogleDriveException>()),
      );

      await drive.connect('renewed', 'Studio');
      oldApi.pendingRead!.completeError(
        const GoogleDriveException('Old token expired', status: 401),
      );
      await failure;

      expect(drive.connection.isConnected, isTrue);
      await drive.read();
    },
  );
  for (final status in [401, 403]) {
    test(
      'Drive HTTP $status preserves the local library and remote mirror',
      () async {
        final local = MemoryStore(const StoredData());
        final api = FakeApi(
          StoredData(folders: [folder('saved', 'Saved work')]),
        );
        final hybrid = HybridDataStore(
          local: local,
          drive: GoogleDriveStore(apiFactory: (_) => api),
        );
        await hybrid.connect('fake-token', 'Studio');
        final persistedBefore = local.data.encode();
        api.readError = GoogleDriveException('Expired fixture', status: status);

        final cached = await hybrid.read();

        expect(cached.folders.single.id, 'saved');
        expect(hybrid.connection.isConnected, isFalse);
        expect(local.data.encode(), persistedBefore);
        expect((await hybrid.read()).folders.single.id, 'saved');
        expect(api.deleted, isEmpty);
      },
    );
  }
  test(
    'moving identical generations preserves both runs and rewrite lineage',
    () async {
      Generation generation(String id, {String? rewriteOf}) => Generation(
        localId: id,
        status: 'Ready',
        prompt: 'The same deliberate prompt',
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
        rewriteOfLocalId: rewriteOf,
      );
      final local = MemoryStore(
        StoredData(
          generations: [
            generation('first'),
            generation('second', rewriteOf: 'first'),
          ],
        ),
      );
      final api = FakeApi(const StoredData());
      final hybrid = HybridDataStore(
        local: local,
        drive: GoogleDriveStore(apiFactory: (_) => api),
      );
      await hybrid.connect('fake-token', 'Studio');

      final moved = await hybrid.moveLocalToDrive();

      expect(moved.generations, 2);
      final result = await hybrid.read();
      expect(result.generations.map((item) => item.localId).toSet(), {
        'drive-first',
        'drive-second',
      });
      expect(
        result.generations
            .singleWhere((item) => item.localId == 'drive-second')
            .rewriteOfLocalId,
        'drive-first',
      );
    },
  );
  test(
    'pruning retains media used by active and recoverable local drafts',
    () async {
      final dir = await Directory.systemTemp.createTemp(
        'clawnsole-draft-roots-',
      );
      try {
        final local = LocalDataStore(documentsDirectory: dir);
        final active = await local.writeAsset(
          Uint8List.fromList([1]),
          label: 'active.png',
          contentType: 'image/png',
        );
        final closed = await local.writeAsset(
          Uint8List.fromList([2]),
          label: 'closed.png',
          contentType: 'image/png',
        );
        await local.write(
          StoredData(
            composerTabs: ComposerTabsState(
              tabs: [
                ComposerTabRecord(
                  id: 'active',
                  mediaConfig: {'source': active.toJson()},
                ),
              ],
              closedTabIds: {'closed'},
              closedTabs: [
                ComposerTabRecord(
                  id: 'closed',
                  mediaConfig: {'source': closed.toJson()},
                ),
              ],
            ),
          ),
        );
        await local.pruneAssets([], []);
        expect(await local.readAsset(active), [1]);
        expect(await local.readAsset(closed), [2]);
      } finally {
        await dir.delete(recursive: true);
      }
    },
  );
  test(
    'Drive pruning protects active and recoverable draft originals',
    () async {
      AssetReference asset(String id) =>
          AssetReference(kind: 'drive', value: id, label: '$id.png');
      final api = FakeApi(
        StoredData(
          composerTabs: ComposerTabsState(
            tabs: [
              ComposerTabRecord(
                id: 'active',
                mediaConfig: {'source': asset('active-asset').toJson()},
              ),
            ],
            closedTabIds: {'closed'},
            closedTabs: [
              ComposerTabRecord(
                id: 'closed',
                mediaConfig: {'source': asset('closed-asset').toJson()},
              ),
            ],
          ),
        ),
      );
      api.files = [
        for (final id in ['active-asset', 'closed-asset', 'orphan'])
          GoogleDriveFile(
            id: id,
            name: id,
            mimeType: 'image/png',
            modifiedTime: now.subtract(Duration(days: 1)),
          ),
      ];
      final drive = GoogleDriveStore(apiFactory: (_) => api, clock: () => now);
      await drive.connect('fake-token', 'Studio');
      await drive.pruneAssets([], []);
      expect(api.deleted, ['orphan']);
    },
  );
  test('a remote deletion wins over an edit based on the deleted revision', () {
    final original = folder('deleted', 'Original');
    final merged = mergeGoogleDriveData(
      base: StoredData(folders: [original]),
      next: StoredData(folders: [original.copyWith(name: 'Stale edit')]),
      remote: const StoredData(),
    );
    expect(merged.folders, isEmpty);
  });
  test(
    'vault edits preserve their original Drive baseline across later reads',
    () async {
      final original = folder('existing', 'Original');
      final api = FakeApi(StoredData(folders: [original]));
      final hybrid = HybridDataStore(
        local: MemoryStore(),
        drive: GoogleDriveStore(apiFactory: (_) => api),
      );
      await hybrid.connect('fake-token', 'Audit studio');
      final vault = SettingsVaultDataStore(
        delegate: hybrid,
        secureStore: MemorySecureValueStore(),
      );
      final staleRead = await vault.read();
      api.externalWrite(
        StoredData(
          folders: [original, folder('remote-addition', 'Created on device B')],
        ),
      );
      await vault
          .read(); // Background refresh must not rebase the in-flight edit.
      await vault.write(
        staleRead.copyWith(
          folders: [
            original.copyWith(
              name: 'Edit from device A',
              updatedAt: now.add(Duration(minutes: 1)),
            ),
          ],
        ),
      );
      expect(api.data.folders.map((f) => f.id).toSet(), {
        'existing',
        'remote-addition',
      });
      expect(
        api.data.folders.singleWhere((f) => f.id == 'existing').name,
        'Edit from device A',
      );
    },
  );
  test('full local deletion cannot revive a library backup', () async {
    final dir = await Directory.systemTemp.createTemp('clawnsole-audit-local-');
    try {
      final store = LocalDataStore(documentsDirectory: dir);
      await store.write(
        StoredData(folders: [folder('first', 'First version')]),
      );
      await store.write(
        StoredData(folders: [folder('second', 'Second version')]),
      );
      await store.delete();
      expect((await store.read()).folders, isEmpty);
    } finally {
      await dir.delete(recursive: true);
    }
  });
  test(
    'move preserves the newest local reference and its casting beside an earlier copy',
    () async {
      final reference = SavedReference(
        id: 'local-ref',
        name: 'Original name',
        kind: MediaReferenceKind.image,
        asset: AssetReference(
          kind: 'remote',
          value: 'https://example.invalid/image.png',
          label: 'image.png',
        ),
        createdAt: now,
        updatedAt: now,
      );
      final local = MemoryStore(StoredData(savedReferences: [reference]));
      final api = FakeApi(StoredData());
      final hybrid = HybridDataStore(
        local: local,
        drive: GoogleDriveStore(apiFactory: (_) => api),
      );
      await hybrid.connect('fake-token', 'Audit studio');
      await hybrid.copyLocalToDrive();
      final current = await hybrid.read();
      final changed = SavedReference(
        id: 'local-ref',
        name: 'Newer local name',
        characterName: 'HERO',
        kind: reference.kind,
        asset: reference.asset,
        createdAt: now,
        updatedAt: now.add(Duration(minutes: 1)),
      );
      await hybrid.write(
        current.copyWith(
          savedReferences: [
            changed,
            ...current.savedReferences.where(
              (r) => r.storage == LibraryStorage.drive,
            ),
          ],
        ),
      );
      await hybrid.moveLocalToDrive();
      final after = await hybrid.read();
      expect(after.savedReferences.length, 2);
      expect(
        after.savedReferences.every((r) => r.storage == LibraryStorage.drive),
        isTrue,
      );
      expect(
        after.savedReferences
            .singleWhere((r) => r.name == 'Newer local name')
            .characterName,
        'HERO',
      );
      expect(
        after.savedReferences.any((r) => r.name == 'Original name'),
        isTrue,
      );
    },
  );
  test(
    'secure migration sanitizes the previous metadata backup after securing keys',
    () async {
      final dir = await Directory.systemTemp.createTemp(
        'clawnsole-audit-legacy-',
      );
      try {
        final root = Directory('${dir.path}/Clawnsole');
        await root.create();
        final file = File('${root.path}/clawnsole.json');
        await file.writeAsString(
          jsonEncode({
            'schemaVersion': 1,
            'apiKeys': {'bfl': 'FAKE-LEGACY-SECRET'},
            'generations': [],
          }),
        );
        final local = LocalDataStore(documentsDirectory: dir);
        final vault = SettingsVaultDataStore(
          delegate: local,
          secureStore: MemorySecureValueStore(),
        );
        expect((await vault.read()).apiKeyFor('bfl'), 'FAKE-LEGACY-SECRET');
        expect(
          await file.readAsString(),
          isNot(contains('FAKE-LEGACY-SECRET')),
        );
        expect(
          await File('${file.path}.bak').readAsString(),
          isNot(contains('FAKE-LEGACY-SECRET')),
        );
      } finally {
        await dir.delete(recursive: true);
      }
    },
  );
  test('library parsing rejects invalid roots and future schemas', () {
    expect(() => StoredData.decode('[]'), throwsFormatException);
    expect(() => StoredData.decode('null'), throwsFormatException);
    expect(
      () => StoredData.decode('{"generations":"wrong"}'),
      throwsFormatException,
    );
    expect(
      () => StoredData.decode('{"schemaVersion":999}'),
      throwsUnsupportedError,
    );
  });
  test('a connected Drive outage permits durable local-only edits', () async {
    final local = MemoryStore();
    final api = FakeApi(StoredData());
    final hybrid = HybridDataStore(
      local: local,
      drive: GoogleDriveStore(apiFactory: (_) => api),
    );
    await hybrid.connect('fake-token', 'Audit studio');
    final vault = SettingsVaultDataStore(
      delegate: hybrid,
      secureStore: MemorySecureValueStore(),
    );
    final current = await vault.read();
    api.offline = true;
    final offline = await vault.read();
    expect(offline.folders, current.folders);
    await vault.write(
      offline.copyWith(
        folders: [
          folder('local', 'Local edit').copyWith(storage: LibraryStorage.local),
        ],
      ),
    );
    expect(local.data.folders.single.name, 'Local edit');
  });
}

class MemoryStore implements DurableDataStore {
  MemoryStore([this.data = const StoredData()]);
  StoredData data;
  @override
  Future<StoredData> read() async => data;
  @override
  Future<void> write(StoredData next) async {
    data = next;
  }

  @override
  Future<void> pruneAssets(
    List<Generation> g, [
    List<SavedReference> r = const [],
  ]) async {}
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class FakeApi extends GoogleDriveApi {
  FakeApi(this.data) : super(accessToken: 'fake-token');
  StoredData data;
  int revision = 1;
  bool offline = false;
  GoogleDriveException? readError;
  Completer<GoogleDriveContent?>? pendingRead;
  Completer<GoogleDriveFile?>? pendingRoot;
  Completer<GoogleDriveFile>? pendingUpdate;
  Completer<void>? updateStarted;
  int childQueries = 0;
  final validators = <String?>[];
  List<GoogleDriveFile> files = [];
  final List<String> deleted = [];
  void externalWrite(StoredData next) {
    data = next;
    revision++;
  }

  GoogleDriveFile f(String id) => GoogleDriveFile(
    id: id,
    name: id,
    mimeType: 'application/json',
    etag: 'rev-$revision',
  );
  @override
  Future<GoogleDriveFile?> findRootFolder(String name) async =>
      pendingRoot == null ? f('root') : await pendingRoot!.future;
  @override
  Future<GoogleDriveFile?> findChild(
    String parentId,
    String name, {
    String? appPropertyKey,
    String? appPropertyValue,
  }) async {
    childQueries++;
    return f(name == 'assets' ? 'assets' : 'state');
  }

  @override
  Future<List<GoogleDriveFile>> listChildren(
    String parentId, {
    String? appPropertyKey,
    String? appPropertyValue,
  }) async => files;
  @override
  Future<void> deleteFile(String id) async {
    deleted.add(id);
  }

  @override
  Future<GoogleDriveContent?> readFile(String id, {String? ifNoneMatch}) async {
    validators.add(ifNoneMatch);
    if (pendingRead != null) return pendingRead!.future;
    if (readError != null) throw readError!;
    if (offline) throw SocketException('Audit simulated offline');
    if (ifNoneMatch == 'rev-$revision') return null;
    return GoogleDriveContent(
      Uint8List.fromList(utf8.encode(data.encode())),
      etag: 'rev-$revision',
    );
  }

  @override
  Future<GoogleDriveFile> updateFile(
    String id,
    Uint8List bytes, {
    required String contentType,
    String? etag,
  }) async {
    updateStarted?.complete();
    if (pendingUpdate != null) return pendingUpdate!.future;
    if (etag != 'rev-$revision') {
      throw GoogleDriveException('Conflict', status: 412);
    }
    data = StoredData.decode(utf8.decode(bytes));
    revision++;
    return f(id);
  }
}
