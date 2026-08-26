import 'dart:typed_data';

import 'package:clawnsole/core/asset_extensions.dart';
import 'package:clawnsole/core/durable_data_store.dart';
import 'package:clawnsole/core/google_drive.dart';
import 'package:clawnsole/core/google_drive_store.dart';
import 'package:clawnsole/core/google_drive_upload_pump.dart';
import 'package:clawnsole/core/hybrid_data_store.dart';
import 'package:clawnsole/core/models.dart';
import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final now = DateTime.utc(2026, 8, 26, 12);

  SavedReference reference(
    String id, {
    LibraryStorage storage = LibraryStorage.drive,
    required AssetReference asset,
  }) => SavedReference(
    id: id,
    name: id,
    kind: MediaReferenceKind.image,
    asset: asset,
    createdAt: now,
    updatedAt: now,
    storage: storage,
  );

  Future<(HybridDataStore, _MemoryStore, _MemoryDriveStore)>
  connectedHybrid() async {
    final local = _MemoryStore(const StoredData());
    final drive = _MemoryDriveStore(const StoredData());
    final hybrid = HybridDataStore(local: local, drive: drive);
    await hybrid.connect('token', 'Clawnsole');
    return (hybrid, local, drive);
  }

  test('Drive-tagged media writes stage locally and mark pending', () async {
    final (hybrid, local, drive) = await connectedHybrid();
    var deferred = 0;
    hybrid.onDeferredDriveUpload = () => deferred += 1;

    final staged = await hybrid.writeAsset(
      Uint8List.fromList(<int>[1, 2, 3]),
      label: 'subject.png',
      contentType: 'image/png',
      storage: LibraryStorage.drive,
    );

    expect(staged.kind, 'local');
    expect(deferred, 1);
    expect(local.assets, hasLength(1));
    expect(drive.assets, isEmpty);

    final data = StoredData(
      savedReferences: <SavedReference>[reference('subject', asset: staged)],
    );
    expect(HybridDataStore.pendingDriveUploads(data).keys, <String>[
      staged.value,
    ]);
    expect(
      pendingDriveUploadAssets(
        data.generations,
        data.savedReferences,
      ).map((asset) => asset.value),
      <String>[staged.value],
    );
  });

  test('persistSource keeps an already-published Drive asset', () async {
    final (hybrid, _, drive) = await connectedHybrid();
    const retained = AssetReference(
      kind: 'drive',
      value: 'drive-file-1',
      label: 'existing.png',
      contentType: 'image/png',
      bytes: 3,
    );
    final resolved = await hybrid.persistSource(
      'data:image/png;base64,AQID',
      label: 'existing.png',
      retained: retained,
      storage: LibraryStorage.drive,
    );
    expect(resolved!.kind, 'drive');
    expect(resolved.value, 'drive-file-1');
    expect(drive.assets, isEmpty, reason: 'nothing re-uploaded');
  });

  test('an upload pass publishes staged media and swaps records', () async {
    final (hybrid, local, drive) = await connectedHybrid();
    final staged = await hybrid.writeAsset(
      Uint8List.fromList(<int>[9, 9, 9]),
      label: 'film.mp4',
      contentType: 'video/mp4',
      storage: LibraryStorage.drive,
    );
    final localAsset = await hybrid.writeAsset(
      Uint8List.fromList(<int>[7]),
      label: 'local.png',
      contentType: 'image/png',
    );
    await hybrid.write(
      StoredData(
        savedReferences: <SavedReference>[
          reference('pending', asset: staged),
          reference(
            'stays-local',
            storage: LibraryStorage.local,
            asset: localAsset,
          ),
        ],
      ),
    );

    final done = await runDriveUploadPass(
      hybrid: hybrid,
      read: hybrid.read,
      write: hybrid.write,
    );

    expect(done, isTrue);
    final data = await hybrid.read();
    final published = data.savedReferences.singleWhere(
      (item) => item.id == 'pending',
    );
    expect(published.asset.kind, 'drive');
    expect(drive.assets[published.asset.value], <int>[9, 9, 9]);
    expect(
      published.updatedAt.isAfter(now),
      isTrue,
      reason: 'swap bumps updatedAt so cross-device merges keep it',
    );
    final untouched = data.savedReferences.singleWhere(
      (item) => item.id == 'stays-local',
    );
    expect(
      untouched.asset.kind,
      'local',
      reason: 'local records never publish to Drive',
    );
    expect(HybridDataStore.pendingDriveUploads(data), isEmpty);
  });

  test(
    'a pass skips staged media whose bytes live on another device',
    () async {
      final (hybrid, _, drive) = await connectedHybrid();
      const foreign = AssetReference(
        kind: 'local',
        value: 'only-on-other-device',
        label: 'remote.mp4',
        contentType: 'video/mp4',
      );
      final result = await hybrid.uploadQueuedDriveAssets(
        StoredData(
          savedReferences: <SavedReference>[
            reference('foreign', asset: foreign),
          ],
        ),
      );
      expect(result.replacements, isEmpty);
      expect(result.failures, 0, reason: 'nothing this device can retry');
      expect(drive.assets, isEmpty);
    },
  );

  test('clearing the local library keeps not-yet-published bytes', () async {
    final (hybrid, local, _) = await connectedHybrid();
    final staged = await hybrid.writeAsset(
      Uint8List.fromList(<int>[5, 5]),
      label: 'pending.png',
      contentType: 'image/png',
      storage: LibraryStorage.drive,
    );
    final localAsset = await hybrid.writeAsset(
      Uint8List.fromList(<int>[6]),
      label: 'local.png',
      contentType: 'image/png',
    );
    await hybrid.write(
      StoredData(
        savedReferences: <SavedReference>[
          reference('pending', asset: staged),
          reference(
            'local-only',
            storage: LibraryStorage.local,
            asset: localAsset,
          ),
        ],
      ),
    );

    await hybrid.deleteLocalLibrary();

    expect(
      local.assets.containsKey(staged.value),
      isTrue,
      reason: 'staged Drive media survives until the upload pass publishes it',
    );
    expect(local.assets.containsKey(localAsset.value), isFalse);
  });

  test('the pump retries with backoff until a pass succeeds', () {
    fakeAsync((async) {
      var calls = 0;
      final pump = DriveUploadPump(
        flush: () async => ++calls >= 3,
        initialRetryDelay: const Duration(seconds: 5),
        maximumRetryDelay: const Duration(seconds: 40),
      );
      pump.schedule();
      async.elapse(Duration.zero);
      expect(calls, 1);
      async.elapse(const Duration(seconds: 5));
      expect(calls, 2);
      async.elapse(const Duration(seconds: 10));
      expect(calls, 3);
      async.elapse(const Duration(minutes: 10));
      expect(calls, 3, reason: 'a completed pass stops the retry chain');
      pump.dispose();
    });
  });

  test('a merge never discards the record holding the film', () {
    final base = Generation(
      localId: 'gen',
      status: 'Pending',
      prompt: 'p',
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
      pollingUrl: 'https://provider.example/poll',
      storage: LibraryStorage.drive,
    );
    const film = AssetReference(kind: 'drive', value: 'film-1', label: 'film');
    // The delivered record carries an OLDER updatedAt than the concurrent
    // status poll — the exact clock-skew shape that used to drop the film.
    final delivered = base.copyWith(
      status: 'Ready',
      resultAsset: film,
      updatedAt: now.add(const Duration(seconds: 1)),
    );
    final polledLater = base.copyWith(
      statusCheckCount: 4,
      updatedAt: now.add(const Duration(minutes: 1)),
    );

    for (final (next, remote) in <(Generation, Generation)>[
      (delivered, polledLater),
      (polledLater, delivered),
    ]) {
      final merged = mergeGoogleDriveData(
        base: StoredData(generations: <Generation>[base]),
        next: StoredData(generations: <Generation>[next]),
        remote: StoredData(generations: <Generation>[remote]),
      );
      expect(
        merged.generations.single.resultAsset,
        film,
        reason: 'the delivered side wins in both directions',
      );
    }
  });
}

class _MemoryStore implements DurableDataStore {
  _MemoryStore(this.data);

  StoredData data;
  final Map<String, Uint8List> assets = <String, Uint8List>{};
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
    final id = 'local-asset-${_assetCounter++}';
    assets[id] = bytes;
    return AssetReference(
      kind: 'local',
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
  Future<Uint8List> readAsset(AssetReference reference) async {
    final bytes = assets[reference.value];
    if (bytes == null) throw StateError('Missing asset ${reference.value}.');
    return bytes;
  }

  @override
  Future<Uri> assetUri(AssetReference reference) async =>
      Uri.parse('memory:${reference.value}');

  @override
  Future<void> pruneAssets(
    List<Generation> generations, [
    List<SavedReference> savedReferences = const <SavedReference>[],
  ]) async {
    final retained = <String>{};
    for (final generation in generations) {
      for (final asset in generationAssetReferences(generation)) {
        if (asset.kind == 'local') retained.add(asset.value);
      }
    }
    for (final reference in savedReferences) {
      for (final asset in savedReferenceAssetReferences(reference)) {
        if (asset.kind == 'local') retained.add(asset.value);
      }
    }
    assets.removeWhere((id, _) => !retained.contains(id));
  }

  @override
  Future<void> delete() async {
    data = const StoredData();
    assets.clear();
  }

  @override
  Future<StorageStats> stats(int records) async =>
      StorageStats(path: 'memory', bytes: 0, records: records);
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
  Future<StoredData> repairMissingCachedAssets(StoredData value) async => value;

  @override
  Future<StorageStats> stats(int records) async =>
      StorageStats(path: 'drive', bytes: 0, records: records);
}
