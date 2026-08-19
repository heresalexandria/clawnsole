import 'dart:convert';
import 'dart:typed_data';

import 'durable_data_store.dart';
import 'google_drive.dart';
import 'google_drive_store.dart';
import 'models.dart';

/// Presents local and Google Drive records as one library while keeping their
/// persistence and retained media physically separate.
class HybridDataStore implements DurableDataStore {
  HybridDataStore({
    required DurableDataStore local,
    GoogleDriveStore? drive,
    this.localLibraryAvailable = true,
  }) : _local = local,
       _drive = drive ?? GoogleDriveStore();

  final DurableDataStore _local;
  final GoogleDriveStore _drive;
  final bool localLibraryAvailable;

  StoredData? _lastLocal;
  StoredData? _lastRemote;

  GoogleDriveConnection get connection {
    final current = _drive.connection;
    if (current.folderName.isNotEmpty || _lastLocal == null) return current;
    return GoogleDriveConnection(
      state: current.state,
      folderName: _lastLocal!.driveFolderName,
      folderId: _lastLocal!.driveFolderId,
      message: current.message,
    );
  }

  bool get isDriveConnected => _drive.connection.isConnected;

  Future<StoredData> connect(String accessToken, String folderName) async {
    final local = _asLocal(await _local.read());
    final remote = _asDrive(await _drive.connect(accessToken, folderName));
    _lastLocal = local;
    _lastRemote = remote;
    final combined = _combine(local, remote);
    await write(
      combined.copyWith(
        driveFolderName: _drive.connection.folderName,
        driveFolderId: _drive.connection.folderId,
      ),
    );
    return read();
  }

  Future<StoredData> disconnect() async {
    await _drive.disconnect();
    _lastRemote = null;
    return read();
  }

  Future<StoredData> refresh() async {
    final local = _asLocal(await _local.read());
    final remote = _asDrive(await _drive.refresh());
    _lastLocal = local;
    _lastRemote = remote;
    return _combine(local, remote);
  }

  @override
  Future<StoredData> read() async {
    final local = _asLocal(await _local.read());
    _lastLocal = local;
    if (!isDriveConnected) return local;
    final remote = _asDrive(await _drive.read());
    _lastRemote = remote;
    return _combine(local, remote);
  }

  @override
  Future<void> write(StoredData data) async {
    final local = _localPartition(data);
    final remote = _drivePartition(data);
    final remoteChanged = _lastRemote == null
        ? _hasPortableContent(remote)
        : _encoded(_lastRemote!) != _encoded(remote);
    if (remoteChanged) {
      if (!isDriveConnected) {
        if (_remoteRecordsChanged(remote)) {
          throw StateError(
            'Connect Google Drive before changing Drive generations, folders, or references.',
          );
        }
      } else {
        await _drive.write(remote);
        _lastRemote = remote;
      }
    }
    await _local.write(local);
    _lastLocal = local;
  }

  @override
  Future<AssetReference> writeAsset(
    Uint8List bytes, {
    required String label,
    required String contentType,
    LibraryStorage storage = LibraryStorage.local,
  }) {
    if (storage == LibraryStorage.drive) {
      if (!isDriveConnected) {
        throw StateError('Connect Google Drive before storing this media.');
      }
      return _drive.writeAsset(
        bytes,
        label: label,
        contentType: contentType,
        storage: storage,
      );
    }
    if (!localLibraryAvailable) {
      throw StateError('This build stores generated media in Google Drive.');
    }
    return _local.writeAsset(
      bytes,
      label: label,
      contentType: contentType,
      storage: storage,
    );
  }

  @override
  Future<AssetReference?> persistSource(
    String source, {
    required String label,
    AssetReference? retained,
    LibraryStorage storage = LibraryStorage.local,
  }) {
    if (storage == LibraryStorage.drive) {
      if (!isDriveConnected) {
        throw StateError('Connect Google Drive before storing this media.');
      }
      return _drive.persistSource(
        source,
        label: label,
        retained: retained,
        storage: storage,
      );
    }
    if (!localLibraryAvailable) {
      throw StateError('This build stores retained media in Google Drive.');
    }
    return _local.persistSource(
      source,
      label: label,
      retained: retained,
      storage: storage,
    );
  }

  @override
  Future<Uint8List> readAsset(AssetReference reference) =>
      reference.kind == 'drive'
      ? _drive.readAsset(reference)
      : _local.readAsset(reference);

  @override
  Future<Uri> assetUri(AssetReference reference) => reference.kind == 'drive'
      ? _drive.assetUri(reference)
      : _local.assetUri(reference);

  @override
  Future<void> pruneAssets(
    List<Generation> generations, [
    List<SavedReference> savedReferences = const <SavedReference>[],
  ]) async {
    final localGenerations = generations
        .where((item) => item.storage == LibraryStorage.local)
        .toList();
    final driveGenerations = generations
        .where((item) => item.storage == LibraryStorage.drive)
        .toList();
    final localReferences = savedReferences
        .where((item) => item.storage == LibraryStorage.local)
        .toList();
    final driveReferences = savedReferences
        .where((item) => item.storage == LibraryStorage.drive)
        .toList();
    await _local.pruneAssets(localGenerations, localReferences);
    if (isDriveConnected) {
      await _drive.pruneAssets(driveGenerations, driveReferences);
    }
  }

  @override
  Future<void> delete() async {
    if (isDriveConnected) await _drive.delete();
    await _local.delete();
    _lastLocal = const StoredData();
    _lastRemote = isDriveConnected ? const StoredData() : null;
  }

  Future<void> deleteLocalLibrary() async {
    final current = await _local.read();
    await _local.write(
      current.copyWith(
        generations: const <Generation>[],
        folders: current.folders
            .where((folder) => folder.storage == LibraryStorage.drive)
            .toList(),
        savedReferences: const <SavedReference>[],
      ),
    );
    await _local.pruneAssets(const <Generation>[], const <SavedReference>[]);
    _lastLocal = null;
  }

  Future<void> deleteDriveLibrary() async {
    if (!isDriveConnected) {
      throw StateError('Connect Google Drive before deleting its library.');
    }
    await _drive.delete();
    _lastRemote = const StoredData();
  }

  @override
  Future<StorageStats> stats(int records) async {
    final local = await _local.stats(
      (_lastLocal?.generations.length ?? 0) +
          (_lastLocal?.savedReferences.length ?? 0),
    );
    if (!isDriveConnected) return local;
    final remote = await _drive.stats(
      (_lastRemote?.generations.length ?? 0) +
          (_lastRemote?.savedReferences.length ?? 0),
    );
    return StorageStats(
      path: '${local.path} + ${remote.path}',
      bytes: local.bytes + remote.bytes,
      records: records,
      assetBytes: local.assetBytes + remote.assetBytes,
      assets: local.assets + remote.assets,
      lastUpdated: _latest(local.lastUpdated, remote.lastUpdated),
    );
  }

  Future<GoogleDriveCopyCounts> copyLocalToDrive({
    Set<String> generationIds = const <String>{},
    Set<String> referenceIds = const <String>{},
  }) async {
    if (!isDriveConnected) {
      throw StateError('Connect Google Drive before copying local items.');
    }
    final current = await read();
    final remoteIds = current.generations
        .where((item) => item.storage == LibraryStorage.drive)
        .map((item) => item.localId)
        .toSet();
    final remoteReferenceIds = current.savedReferences
        .where((item) => item.storage == LibraryStorage.drive)
        .map((item) => item.id)
        .toSet();
    final copyEverything = generationIds.isEmpty && referenceIds.isEmpty;
    final requestedGenerations = current.generations.where(
      (item) =>
          item.storage == LibraryStorage.local &&
          (copyEverything || generationIds.contains(item.localId)),
    );
    final requestedReferences = current.savedReferences.where(
      (item) =>
          item.storage == LibraryStorage.local &&
          (copyEverything || referenceIds.contains(item.id)),
    );
    final folderMap = <String, String>{};
    final driveFolders = <LibraryFolder>[
      ...current.folders.where(
        (folder) => folder.storage == LibraryStorage.drive,
      ),
    ];
    for (final folder in current.folders.where(
      (item) => item.storage == LibraryStorage.local,
    )) {
      final id = 'drive-${folder.id}';
      folderMap[folder.id] = id;
      if (driveFolders.any((item) => item.id == id)) continue;
      driveFolders.add(
        folder
            .copyWith(
              storage: LibraryStorage.drive,
              parentId: folder.parentId == null
                  ? null
                  : 'drive-${folder.parentId}',
              clearParent: folder.parentId == null,
            )
            .withId(id),
      );
    }

    var copiedGenerations = 0;
    final generations = <Generation>[...current.generations];
    for (final generation in requestedGenerations) {
      final id = 'drive-${generation.localId}';
      if (remoteIds.contains(id)) continue;
      generations.add(
        await _copyGeneration(
          generation,
          id: id,
          folderId: generation.folderId == null
              ? null
              : folderMap[generation.folderId],
        ),
      );
      remoteIds.add(id);
      copiedGenerations += 1;
    }

    var copiedReferences = 0;
    final references = <SavedReference>[...current.savedReferences];
    for (final reference in requestedReferences) {
      final id = 'drive-${reference.id}';
      if (remoteReferenceIds.contains(id)) continue;
      references.add(
        SavedReference(
          id: id,
          name: reference.name,
          kind: reference.kind,
          asset: (await _copyAsset(reference.asset))!,
          createdAt: reference.createdAt,
          updatedAt: DateTime.now().toUtc(),
          folderId: reference.folderId == null
              ? null
              : folderMap[reference.folderId],
          tags: reference.tags,
          storage: LibraryStorage.drive,
        ),
      );
      remoteReferenceIds.add(id);
      copiedReferences += 1;
    }

    await write(
      current.copyWith(
        generations: generations,
        folders: <LibraryFolder>[
          ...current.folders.where(
            (folder) => folder.storage == LibraryStorage.local,
          ),
          ...driveFolders,
        ],
        savedReferences: references,
      ),
    );
    return GoogleDriveCopyCounts(
      generations: copiedGenerations,
      references: copiedReferences,
    );
  }

  Future<Generation> _copyGeneration(
    Generation source, {
    required String id,
    String? folderId,
  }) async {
    final keyframes = <KeyframeLabel>[];
    for (final frame in source.config.keyframes ?? const <KeyframeLabel>[]) {
      keyframes.add(
        KeyframeLabel(
          label: frame.label,
          role: frame.role,
          seconds: frame.seconds,
          source: await _copyAsset(frame.source),
        ),
      );
    }
    final references = <MediaReferenceLabel>[];
    for (final item
        in source.config.references ?? const <MediaReferenceLabel>[]) {
      references.add(
        MediaReferenceLabel(
          label: item.label,
          kind: item.kind,
          source: await _copyAsset(item.source),
        ),
      );
    }
    final config = source.config.copyWith(
      keyframes: keyframes,
      references: references,
      source: await _copyAsset(source.config.source),
    );
    return Generation.fromJson(<String, Object?>{
      ...source.toJson(),
      'localId': id,
      'storage': LibraryStorage.drive.name,
      'config': config.toJson(),
      if (folderId != null) 'folderId': folderId else 'folderId': null,
      if (source.resultAsset != null)
        'resultAsset': (await _copyAsset(source.resultAsset))?.toJson(),
    });
  }

  Future<AssetReference?> _copyAsset(AssetReference? reference) async {
    if (reference == null || reference.kind == 'drive') return reference;
    if (reference.kind != 'local') return reference;
    final bytes = await _local.readAsset(reference);
    return _drive.writeAsset(
      bytes,
      label: reference.label,
      contentType: reference.contentType ?? 'application/octet-stream',
    );
  }

  StoredData _combine(StoredData local, StoredData remote) {
    final remotePreferencesAreNewer = _isAfter(
      remote.preferencesUpdatedAt,
      local.preferencesUpdatedAt,
    );
    final preferences = remotePreferencesAreNewer
        ? remote.preferences
        : local.preferences;
    final preferencesUpdatedAt = remotePreferencesAreNewer
        ? remote.preferencesUpdatedAt
        : local.preferencesUpdatedAt;
    return StoredData(
      apiKey: local.apiKey,
      apiKeys: local.apiKeys,
      rejectedIosReviewApiKeyId: local.rejectedIosReviewApiKeyId,
      rejectedIosReviewApiKeyIds: local.rejectedIosReviewApiKeyIds,
      preferences: preferences,
      preferencesUpdatedAt: preferencesUpdatedAt,
      driveFolderName: _drive.connection.folderName.isNotEmpty
          ? _drive.connection.folderName
          : local.driveFolderName,
      driveFolderId: _drive.connection.folderId.isNotEmpty
          ? _drive.connection.folderId
          : local.driveFolderId,
      generations: <Generation>[...local.generations, ...remote.generations]
        ..sort((a, b) => b.createdAt.compareTo(a.createdAt)),
      folders: <LibraryFolder>[...local.folders, ...remote.folders],
      savedReferences: <SavedReference>[
        ...local.savedReferences,
        ...remote.savedReferences,
      ]..sort((a, b) => b.updatedAt.compareTo(a.updatedAt)),
    );
  }

  StoredData _asLocal(StoredData data) => data.copyWith(
    generations: data.generations
        .map((item) => item.copyWith(storage: LibraryStorage.local))
        .toList(),
    folders: data.folders
        .map((item) => item.copyWith(storage: LibraryStorage.local))
        .toList(),
    savedReferences: data.savedReferences
        .map((item) => item.copyWith(storage: LibraryStorage.local))
        .toList(),
  );

  StoredData _asDrive(StoredData data) => data.copyWith(
    generations: data.generations
        .map((item) => item.copyWith(storage: LibraryStorage.drive))
        .toList(),
    folders: data.folders
        .map((item) => item.copyWith(storage: LibraryStorage.drive))
        .toList(),
    savedReferences: data.savedReferences
        .map((item) => item.copyWith(storage: LibraryStorage.drive))
        .toList(),
    driveFolderName: '',
    driveFolderId: '',
  );

  StoredData _localPartition(StoredData data) => StoredData(
    apiKey: data.apiKey,
    apiKeys: data.apiKeys,
    rejectedIosReviewApiKeyId: data.rejectedIosReviewApiKeyId,
    rejectedIosReviewApiKeyIds: data.rejectedIosReviewApiKeyIds,
    preferences: data.preferences,
    preferencesUpdatedAt: data.preferencesUpdatedAt,
    driveFolderName: data.driveFolderName,
    driveFolderId: data.driveFolderId,
    generations: data.generations
        .where((item) => item.storage == LibraryStorage.local)
        .toList(),
    folders: data.folders
        .where((item) => item.storage == LibraryStorage.local)
        .toList(),
    savedReferences: data.savedReferences
        .where((item) => item.storage == LibraryStorage.local)
        .toList(),
  );

  StoredData _drivePartition(StoredData data) => StoredData(
    preferences: data.preferences,
    preferencesUpdatedAt: data.preferencesUpdatedAt,
    generations: data.generations
        .where((item) => item.storage == LibraryStorage.drive)
        .toList(),
    folders: data.folders
        .where((item) => item.storage == LibraryStorage.drive)
        .toList(),
    savedReferences: data.savedReferences
        .where((item) => item.storage == LibraryStorage.drive)
        .toList(),
  );

  String _encoded(StoredData data) =>
      jsonEncode(googleDrivePortableData(data).toJson());

  bool _hasPortableContent(StoredData data) =>
      data.generations.isNotEmpty ||
      data.folders.isNotEmpty ||
      data.savedReferences.isNotEmpty ||
      data.preferencesUpdatedAt != null;

  bool _remoteRecordsChanged(StoredData remote) {
    final previous = _lastRemote;
    if (previous == null) {
      return remote.generations.isNotEmpty ||
          remote.folders.isNotEmpty ||
          remote.savedReferences.isNotEmpty;
    }
    Map<String, Object?> records(StoredData data) => <String, Object?>{
      'generations': data.generations.map((item) => item.toJson()).toList(),
      'folders': data.folders.map((item) => item.toJson()).toList(),
      'savedReferences': data.savedReferences
          .map((item) => item.toJson())
          .toList(),
    };
    return jsonEncode(records(previous)) != jsonEncode(records(remote));
  }

  bool _isAfter(DateTime? candidate, DateTime? other) {
    if (candidate == null) return false;
    if (other == null) return true;
    return candidate.isAfter(other);
  }

  DateTime? _latest(DateTime? a, DateTime? b) {
    if (a == null) return b;
    if (b == null) return a;
    return a.isAfter(b) ? a : b;
  }
}

class GoogleDriveCopyCounts {
  const GoogleDriveCopyCounts({
    required this.generations,
    required this.references,
  });

  final int generations;
  final int references;
}

extension on LibraryFolder {
  LibraryFolder withId(String value) => LibraryFolder(
    id: value,
    name: name,
    createdAt: createdAt,
    parentId: parentId,
    collection: collection,
    storage: storage,
  );
}
