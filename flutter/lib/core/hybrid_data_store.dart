import 'dart:convert';
import 'dart:typed_data';

import 'asset_extensions.dart';
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
    this.deferDriveUploads = true,
  }) : _local = local,
       _drive = drive ?? GoogleDriveStore();

  final DurableDataStore _local;
  final GoogleDriveStore _drive;
  final bool localLibraryAvailable;

  /// When set, Drive-tagged media writes stage into the local store and are
  /// published to Drive by a background upload pass, so saving media finishes
  /// at local-disk speed. Disabled on builds without a local library.
  final bool deferDriveUploads;

  /// Invoked whenever a Drive-tagged media write was staged locally, so the
  /// owner can schedule a background upload pass.
  void Function()? onDeferredDriveUpload;

  bool get _stagesDriveUploads => deferDriveUploads && localLibraryAvailable;

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
    final connected = await _drive.connect(accessToken, folderName);
    final remote = _asDrive(await _repairCachedDriveAssets(connected));
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
    final persisted = await _local.read();
    final local = _asLocal(persisted);
    final refreshed = await _drive.refresh();
    final remote = _asDrive(await _repairCachedDriveAssets(refreshed));
    _lastLocal = local;
    _lastRemote = remote;
    final combined = _combine(local, remote);
    await _persistLocalMirrorIfChanged(persisted, combined);
    return combined;
  }

  @override
  Future<StoredData> read() async {
    final persisted = await _local.read();
    final local = _asLocal(persisted);
    final cachedRemote = _asCachedDrive(persisted);
    _lastLocal = local;
    if (!isDriveConnected) {
      _lastRemote = cachedRemote;
      return _combine(local, cachedRemote);
    }
    final remote = _asDrive(await _drive.read());
    _lastRemote = remote;
    final combined = _combine(local, remote);
    await _persistLocalMirrorIfChanged(persisted, combined);
    return combined;
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
        _lastRemote = _asDrive(_drive.lastData ?? remote);
      }
    }
    final mirrored = isDriveConnected && _lastRemote != null
        ? _combine(local, _lastRemote!)
        : data;
    await _local.write(_localMirror(mirrored));
    _lastLocal = local;
  }

  @override
  Future<AssetReference> writeAsset(
    Uint8List bytes, {
    required String label,
    required String contentType,
    LibraryStorage storage = LibraryStorage.local,
  }) async {
    if (storage == LibraryStorage.drive) {
      if (!isDriveConnected) {
        throw StateError('Connect Google Drive before storing this media.');
      }
      if (_stagesDriveUploads) {
        // Stage locally so the save finishes at disk speed; the background
        // upload pass publishes the bytes and swaps the record to the Drive
        // file afterwards.
        final staged = await _local.writeAsset(
          bytes,
          label: label,
          contentType: contentType,
        );
        onDeferredDriveUpload?.call();
        return staged;
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
  }) async {
    if (storage == LibraryStorage.drive) {
      if (!isDriveConnected) {
        throw StateError('Connect Google Drive before storing this media.');
      }
      if (_stagesDriveUploads) {
        if (retained?.kind == 'drive' && retained!.value.isNotEmpty) {
          return AssetReference(
            kind: 'drive',
            value: retained.value,
            label: label,
            contentType: retained.contentType,
            bytes: retained.bytes,
          );
        }
        final staged = await _local.persistSource(
          source,
          label: label,
          retained: retained,
        );
        if (staged?.kind == 'local') onDeferredDriveUpload?.call();
        return staged;
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

  /// Local-kind media still referenced by Drive-tagged records: bytes staged
  /// by a deferred Drive write that a background pass has not yet published.
  static Map<String, AssetReference> pendingDriveUploads(StoredData data) {
    final pending = <String, AssetReference>{};
    for (final reference in pendingDriveUploadAssets(
      data.generations,
      data.savedReferences,
    )) {
      pending.putIfAbsent(reference.value, () => reference);
    }
    return pending;
  }

  /// Uploads the staged media referenced by [data] to Drive without touching
  /// any records. Returns the published Drive files keyed by staged local
  /// asset id. [DriveUploadPassResult.failures] counts uploads this device
  /// holds bytes for that did not reach Drive and should be retried; staged
  /// media whose bytes live on another device is skipped silently, because
  /// only that device can publish it.
  Future<DriveUploadPassResult> uploadQueuedDriveAssets(StoredData data) async {
    if (!isDriveConnected) {
      return const DriveUploadPassResult(<String, AssetReference>{}, 0);
    }
    final replacements = <String, AssetReference>{};
    var failures = 0;
    for (final entry in pendingDriveUploads(data).entries) {
      Uint8List bytes;
      try {
        bytes = await _local.readAsset(entry.value);
      } on Object {
        continue;
      }
      try {
        replacements[entry.key] = await _drive.writeAsset(
          bytes,
          label: entry.value.label,
          contentType: entry.value.contentType ?? 'application/octet-stream',
        );
      } on Object {
        failures += 1;
      }
    }
    return DriveUploadPassResult(replacements, failures);
  }

  /// Points Drive-tagged records at their published Drive files. Changed
  /// records get a fresh updatedAt so cross-device merges keep the swap.
  static StoredData applyDriveAssetReplacements(
    StoredData data,
    Map<String, AssetReference> replacements,
  ) {
    if (replacements.isEmpty) return data;
    final now = DateTime.now().toUtc();
    AssetReference? lookup(AssetReference reference) =>
        reference.kind == 'local' ? replacements[reference.value] : null;
    return data.copyWith(
      generations: data.generations.map((item) {
        if (item.storage != LibraryStorage.drive) return item;
        var changed = false;
        final swapped = mapGenerationAssets(item, (reference) {
          final next = lookup(reference);
          if (next == null) return reference;
          changed = true;
          return next;
        });
        return changed ? swapped.copyWith(updatedAt: now) : item;
      }).toList(),
      savedReferences: data.savedReferences.map((item) {
        if (item.storage != LibraryStorage.drive) return item;
        var changed = false;
        final swapped = mapSavedReferenceAssets(item, (reference) {
          final next = lookup(reference);
          if (next == null) return reference;
          changed = true;
          return next;
        });
        return changed ? swapped.copyWith(updatedAt: now) : item;
      }).toList(),
    );
  }

  @override
  Future<Uint8List> readAsset(AssetReference reference) =>
      reference.kind == 'drive'
      ? _drive.readAsset(reference)
      : _local.readAsset(reference);

  /// Streams a Drive-kind asset without buffering it in memory. Local assets
  /// are not streamed here; read them with [readAsset].
  Future<GoogleDriveByteStream> readDriveAssetStream(
    AssetReference reference,
  ) => _drive.readAssetStream(reference);

  /// Reads one byte range of a Drive-kind asset.
  Future<Uint8List> readDriveAssetRange(
    AssetReference reference,
    int start,
    int end,
  ) => _drive.readAssetRange(reference, start, end);

  /// The locally materialized URI for [reference] when one exists, without
  /// triggering any Drive download.
  Future<Uri?> cachedAssetUri(AssetReference reference) =>
      reference.kind == 'drive'
      ? _drive.cachedAssetUri(reference)
      : _local.assetUri(reference);

  @override
  Future<Uri> assetUri(AssetReference reference) => reference.kind == 'drive'
      ? _drive.assetUri(reference)
      : _local.assetUri(reference);

  @override
  Future<void> pruneAssets(
    List<Generation> generations, [
    List<SavedReference> savedReferences = const <SavedReference>[],
  ]) async {
    // Both stores compute their retention sets from AssetReference.kind, so
    // hand each of them the ENTIRE dataset. Partitioning by the record's
    // storage tag would let a storage/kind mismatch (a Drive-tagged record
    // still holding a local-kind asset, or the reverse) delete a file that is
    // still referenced.
    await _local.pruneAssets(generations, savedReferences);
    if (isDriveConnected) {
      await _drive.pruneAssets(generations, savedReferences);
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
    final driveGenerations = current.generations
        .where((item) => item.storage == LibraryStorage.drive)
        .toList();
    final driveReferences = current.savedReferences
        .where((item) => item.storage == LibraryStorage.drive)
        .toList();
    await _local.write(
      current.copyWith(
        generations: driveGenerations,
        folders: current.folders
            .where((folder) => folder.storage == LibraryStorage.drive)
            .toList(),
        savedReferences: driveReferences,
      ),
    );
    // Clearing the local library clears every local media byte that only
    // local records used. The kept Drive records are metadata whose originals
    // remain in Drive — except staged media a deferred upload has not
    // published yet, which those records still reference by local kind and
    // which must survive until the background pass uploads it.
    await _local.pruneAssets(driveGenerations, driveReferences);
    _lastLocal = null;
  }

  Future<void> deleteDriveLibrary() async {
    if (!isDriveConnected) {
      throw StateError('Connect Google Drive before deleting its library.');
    }
    await _drive.delete();
    _lastRemote = const StoredData();
    final current = await _local.read();
    await _local.write(
      current.copyWith(
        generations: current.generations
            .where((item) => item.storage == LibraryStorage.local)
            .toList(),
        folders: current.folders
            .where((item) => item.storage == LibraryStorage.local)
            .toList(),
        savedReferences: current.savedReferences
            .where((item) => item.storage == LibraryStorage.local)
            .toList(),
      ),
    );
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
    final referenceIdMap = <String, String>{
      for (final reference in current.savedReferences.where(
        (item) => item.storage == LibraryStorage.local,
      ))
        if (copyEverything ||
            referenceIds.contains(reference.id) ||
            remoteReferenceIds.contains('drive-${reference.id}'))
          reference.id: 'drive-${reference.id}',
    };
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
          referenceIdMap: referenceIdMap,
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
          thumbnailAsset: await _copyAsset(reference.thumbnailAsset),
          createdAt: reference.createdAt,
          updatedAt: DateTime.now().toUtc(),
          folderId: reference.folderId == null
              ? null
              : folderMap[reference.folderId],
          tags: reference.tags,
          favorite: reference.favorite,
          hidden: reference.hidden,
          storage: LibraryStorage.drive,
          contentDigest: reference.contentDigest,
          durationSeconds: reference.durationSeconds,
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

  /// Copies everything local into Drive and, only after verifying that every
  /// local record now has a Drive counterpart, removes the local originals.
  /// The Drive folder linkage in the local file survives so the connection
  /// resumes on the next launch. A partial copy aborts before any deletion.
  Future<GoogleDriveCopyCounts> moveLocalToDrive() async {
    final copied = await copyLocalToDrive();
    final current = await read();
    final driveGenerationIds = current.generations
        .where((item) => item.storage == LibraryStorage.drive)
        .map((item) => item.localId)
        .toSet();
    final driveReferenceIds = current.savedReferences
        .where((item) => item.storage == LibraryStorage.drive)
        .map((item) => item.id)
        .toSet();
    final unverified =
        current.generations.any(
          (item) =>
              item.storage == LibraryStorage.local &&
              !driveGenerationIds.contains('drive-${item.localId}'),
        ) ||
        current.savedReferences.any(
          (item) =>
              item.storage == LibraryStorage.local &&
              !driveReferenceIds.contains('drive-${item.id}'),
        );
    if (unverified) {
      throw StateError(
        'Some local items were not confirmed in Google Drive, so the local '
        'library was kept.',
      );
    }
    await deleteLocalLibrary();
    return copied;
  }

  Future<Generation> _copyGeneration(
    Generation source, {
    required String id,
    Map<String, String> referenceIdMap = const <String, String>{},
    String? folderId,
  }) async {
    final keyframes = <KeyframeLabel>[];
    for (final frame in source.config.keyframes ?? const <KeyframeLabel>[]) {
      keyframes.add(
        KeyframeLabel(
          label: frame.label,
          role: frame.role,
          seconds: frame.seconds,
          referenceId: frame.referenceId == null
              ? null
              : referenceIdMap[frame.referenceId] ?? frame.referenceId,
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
          referenceId: item.referenceId == null
              ? null
              : referenceIdMap[item.referenceId] ?? item.referenceId,
          source: await _copyAsset(item.source),
          thumbnailAsset: await _copyAsset(item.thumbnailAsset),
        ),
      );
    }
    final config = source.config.copyWith(
      keyframes: keyframes,
      references: references,
      sourceReferenceId: source.config.sourceReferenceId == null
          ? null
          : referenceIdMap[source.config.sourceReferenceId] ??
                source.config.sourceReferenceId,
      source: await _copyAsset(source.config.source),
      sourceThumbnailAsset: await _copyAsset(
        source.config.sourceThumbnailAsset,
      ),
    );
    return Generation.fromJson(<String, Object?>{
      ...source.toJson(),
      'localId': id,
      'storage': LibraryStorage.drive.name,
      'config': config.toJson(),
      if (folderId != null) 'folderId': folderId else 'folderId': null,
      if (source.resultAsset != null)
        'resultAsset': (await _copyAsset(source.resultAsset))?.toJson(),
      if (source.thumbnailAsset != null)
        'thumbnailAsset': (await _copyAsset(source.thumbnailAsset))?.toJson(),
      if (source.timelineThumbnailAsset != null)
        'timelineThumbnailAsset': (await _copyAsset(
          source.timelineThumbnailAsset,
        ))?.toJson(),
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
      providerCatalogCache: local.providerCatalogCache,
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

  /// Extracts device-owned records from the local file. Drive-tagged records
  /// in that file are a read-through metadata mirror, not local originals.
  StoredData _asLocal(StoredData data) => data.copyWith(
    generations: data.generations
        .where((item) => item.storage != LibraryStorage.drive)
        .map((item) => item.copyWith(storage: LibraryStorage.local))
        .toList(),
    folders: data.folders
        .where((item) => item.storage != LibraryStorage.drive)
        .map((item) => item.copyWith(storage: LibraryStorage.local))
        .toList(),
    savedReferences: data.savedReferences
        .where((item) => item.storage != LibraryStorage.drive)
        .map((item) => item.copyWith(storage: LibraryStorage.local))
        .toList(),
  );

  /// Extracts the last successfully reconciled Drive metadata from the local
  /// file. This mirror lets every surface open its library immediately while
  /// Drive authorization and polling continue in the background.
  StoredData _asCachedDrive(StoredData data) => StoredData(
    generations: data.generations
        .where((item) => item.storage == LibraryStorage.drive)
        .map((item) => item.copyWith(storage: LibraryStorage.drive))
        .toList(),
    folders: data.folders
        .where((item) => item.storage == LibraryStorage.drive)
        .map((item) => item.copyWith(storage: LibraryStorage.drive))
        .toList(),
    savedReferences: data.savedReferences
        .where((item) => item.storage == LibraryStorage.drive)
        .map((item) => item.copyWith(storage: LibraryStorage.drive))
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
    providerCatalogCache: data.providerCatalogCache,
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

  /// The local data file owns device settings and local records while also
  /// retaining a compact mirror of Drive metadata. Media bytes remain in the
  /// bounded caches and originals remain solely in their respective stores.
  StoredData _localMirror(StoredData data) => StoredData(
    apiKey: data.apiKey,
    apiKeys: data.apiKeys,
    rejectedIosReviewApiKeyId: data.rejectedIosReviewApiKeyId,
    rejectedIosReviewApiKeyIds: data.rejectedIosReviewApiKeyIds,
    preferences: data.preferences,
    preferencesUpdatedAt: data.preferencesUpdatedAt,
    driveFolderName: data.driveFolderName,
    driveFolderId: data.driveFolderId,
    generations: data.generations,
    folders: data.folders,
    savedReferences: data.savedReferences,
  );

  Future<void> _persistLocalMirrorIfChanged(
    StoredData persisted,
    StoredData combined,
  ) async {
    final mirror = _localMirror(combined);
    if (jsonEncode(persisted.toJson()) == jsonEncode(mirror.toJson())) return;
    await _local.write(mirror);
  }

  String _encoded(StoredData data) =>
      jsonEncode(googleDrivePortableData(data).toJson());

  Future<StoredData> _repairCachedDriveAssets(StoredData data) async {
    try {
      return await _drive.repairMissingCachedAssets(data);
    } on Object {
      if (!_drive.connection.isConnected) rethrow;
      // Reconciliation remains usable during a transient listing or upload
      // failure. The source device retries the repair on its next reconnect
      // or explicit Drive refresh.
      return data;
    }
  }

  bool _hasPortableContent(StoredData data) =>
      data.generations.isNotEmpty ||
      data.folders.isNotEmpty ||
      data.savedReferences.isNotEmpty;

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

/// The outcome of one background Drive upload pass.
class DriveUploadPassResult {
  const DriveUploadPassResult(this.replacements, this.failures);

  /// Published Drive files keyed by the staged local asset id they replace.
  final Map<String, AssetReference> replacements;

  /// Uploads this device holds bytes for that failed and should be retried.
  final int failures;
}

extension on LibraryFolder {
  LibraryFolder withId(String value) => LibraryFolder(
    id: value,
    name: name,
    createdAt: createdAt,
    updatedAt: updatedAt,
    parentId: parentId,
    collection: collection,
    storage: storage,
  );
}
