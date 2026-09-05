import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';

import 'asset_extensions.dart';
import 'durable_data_store.dart';
import 'google_drive.dart';
import 'google_drive_store.dart';
import 'models.dart';
import 'composer_tabs.dart';

/// Presents local and Google Drive records as one library while keeping their
/// persistence and retained media physically separate.
class HybridDataStore implements DurableDataStore, ComposerWorkspaceStore {
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

  /// The last reconciled library exactly as this device persisted it: local
  /// records combined with the compact Drive metadata mirror, with no Drive
  /// traffic even while connected. Routes that serve already-retained media
  /// use this so a cached thumbnail or film never waits on the network.
  Future<StoredData> readCached() async {
    final persisted = await _local.read();
    return _combine(_asLocal(persisted), _asCachedDrive(persisted));
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
    StoredData remote;
    try {
      remote = _asDrive(await _drive.read());
    } on Exception catch (error) {
      if (!_isTransientDriveReadError(error)) rethrow;
      // An active authorization is not a network guarantee. Keep device-local
      // work usable against the last durable mirror during a transport outage.
      _lastRemote = cachedRemote;
      return _combine(local, cachedRemote);
    }
    _lastRemote = remote;
    final combined = _combine(local, remote);
    await _persistLocalMirrorIfChanged(persisted, combined);
    return combined;
  }

  @override
  Future<ComposerTabsState?> readComposerWorkspace() async =>
      (await _local.read()).composerTabs;

  Future<void> _workspaceWrites = Future<void>.value();
  Future<void>? _workspacePublish;
  bool _workspaceDirty = false;

  @override
  Future<void> writeComposerWorkspace(ComposerTabsState state) {
    final operation = _workspaceWrites.then((_) async {
      final current = await _local.read();
      final merged = mergeComposerWorkspaces(state, current.composerTabs)!;
      await _local.write(current.copyWith(composerTabs: merged));
      _workspaceDirty = true;
      unawaited(syncComposerWorkspaceToDrive());
    });
    _workspaceWrites = operation.then<void>((_) {}, onError: (_) {});
    return operation;
  }

  /// Publishing runs outside the local write queue: a slow connection must
  /// never hold newer keystrokes in memory behind an earlier network request.
  Future<void> syncComposerWorkspaceToDrive() {
    if (_workspacePublish != null) return _workspacePublish!;
    if (!isDriveConnected) return Future<void>.value();
    return _workspacePublish = _publishComposerWorkspace().whenComplete(() {
      _workspacePublish = null;
    });
  }

  Future<void> _publishComposerWorkspace() async {
    try {
      while (_workspaceDirty && isDriveConnected) {
        _workspaceDirty = false;
        final current = await _local.read();
        final remote = _drivePartition(
          current,
        ).copyWith(driveSyncBase: _asCachedDrive(current));
        await _drive.write(remote);
        _lastRemote = _asDrive(_drive.lastData ?? remote);
        // Serialize the mirror update with new local drafts as well.
        final operation = _workspaceWrites.then((_) async {
          final latest = await _local.read();
          await _local.write(
            latest.copyWith(
              composerTabs: mergeComposerWorkspaces(
                latest.composerTabs,
                _lastRemote!.composerTabs,
              ),
            ),
          );
        });
        _workspaceWrites = operation.then<void>((_) {}, onError: (_) {});
        await operation;
      }
    } on Object {
      _workspaceDirty = true;
      // Drafts are on disk. A foreground/periodic pass retries publication.
    }
  }

  @override
  Future<void> write(StoredData data) async {
    final local = _localPartition(data);
    final remote = _drivePartition(data);
    final base = data.driveSyncBase ?? _lastRemote;
    final remoteChanged = base == null
        ? _hasPortableContent(remote)
        : _encoded(base) != _encoded(remote);
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
    await _persistLocalMirrorIfChanged(
      await _local.read(),
      mirrored,
      forceWrite: true,
    );
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
    StorageStats remote;
    try {
      remote = await _drive.stats(
        (_lastRemote?.generations.length ?? 0) +
            (_lastRemote?.savedReferences.length ?? 0),
      );
    } on Exception catch (error) {
      if (!_isTransientDriveReadError(error)) rethrow;
      return StorageStats(
        path: '${local.path} (Drive storage totals temporarily unavailable)',
        bytes: local.bytes,
        records: records,
        assetBytes: local.assetBytes,
        assets: local.assets,
        lastUpdated: local.lastUpdated,
      );
    }
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

  /// Publishes the current local revision, verifies its metadata and uploaded
  /// bytes, then removes only unchanged source records. An earlier copy is an
  /// independent revision: keep it and publish a new id instead of overwriting
  /// remote edits or mistaking its identity for proof that the source is safe.
  Future<GoogleDriveCopyCounts> moveLocalToDrive() async {
    if (!isDriveConnected) {
      throw StateError('Connect Google Drive before moving local items.');
    }
    final source = _asLocal(await _local.read());
    final remote = _asDrive(await _drive.read());
    final remoteNames = remote.savedReferences
        .map((item) => item.characterName?.trim().toUpperCase() ?? '')
        .where((name) => name.isNotEmpty)
        .toSet();
    for (final item in source.savedReferences) {
      final name = item.characterName?.trim().toUpperCase() ?? '';
      if (name.isNotEmpty && remoteNames.contains(name)) {
        throw StateError(
          'Google Drive already has a reference assigned to $name. '
          'Resolve that casting assignment before moving this library.',
        );
      }
    }
    final random = Random.secure();
    final moveId = List<int>.generate(
      16,
      (_) => random.nextInt(256),
    ).map((byte) => byte.toRadixString(16).padLeft(2, '0')).join();
    Map<String, String> ids(Iterable<String> local, Iterable<String> remote) {
      final occupied = remote.toSet();
      return <String, String>{
        for (final id in local)
          id: occupied.contains('drive-$id')
              ? 'drive-$id-move-$moveId'
              : 'drive-$id',
      };
    }

    final folderIds = ids(
      source.folders.map((item) => item.id),
      remote.folders.map((item) => item.id),
    );
    final referenceIds = ids(
      source.savedReferences.map((item) => item.id),
      remote.savedReferences.map((item) => item.id),
    );
    final generationIds = ids(
      source.generations.map((item) => item.localId),
      remote.generations.map((item) => item.localId),
    );
    final assetCopies = <String, AssetReference>{};
    final generations = <Generation>[];
    for (final item in source.generations) {
      generations.add(
        await _copyGeneration(
          item,
          id: generationIds[item.localId]!,
          referenceIdMap: referenceIds,
          generationIdMap: generationIds,
          folderId: folderIds[item.folderId],
          assetCopies: assetCopies,
        ),
      );
    }
    final references = <SavedReference>[];
    for (final item in source.savedReferences) {
      references.add(
        SavedReference.fromJson(<String, Object?>{
          ...item.toJson(),
          'id': referenceIds[item.id]!,
          'storage': LibraryStorage.drive.name,
          'folderId': folderIds[item.folderId],
          'asset': (await _copyAsset(
            item.asset,
            copies: assetCopies,
          ))!.toJson(),
          if (item.thumbnailAsset != null)
            'thumbnailAsset': (await _copyAsset(
              item.thumbnailAsset,
              copies: assetCopies,
            ))!.toJson(),
        }),
      );
    }
    final folders = source.folders
        .map(
          (item) => item
              .copyWith(
                storage: LibraryStorage.drive,
                parentId: folderIds[item.parentId],
                clearParent: item.parentId == null,
              )
              .withId(folderIds[item.id]!),
        )
        .toList();

    // Verify uploaded originals through an uncached Drive stream. A local
    // upload cache or an existing record id is not proof of cloud durability.
    final sourceAssets = <String, AssetReference>{};
    for (final item in source.generations) {
      for (final asset in generationAssetReferences(item)) {
        if (asset.kind == 'local') sourceAssets[asset.value] = asset;
      }
    }
    for (final item in source.savedReferences) {
      for (final asset in savedReferenceAssetReferences(item)) {
        if (asset.kind == 'local') sourceAssets[asset.value] = asset;
      }
    }
    for (final entry in sourceAssets.entries) {
      final published = assetCopies[entry.key];
      if (published == null) {
        throw StateError(
          'A local asset was not copied. The local library was kept.',
        );
      }
      final expected = sha256.convert(await _local.readAsset(entry.value));
      final download = await _drive.readAssetStream(published);
      final actual = await sha256.bind(download.stream).first;
      if (actual != expected) {
        throw StateError(
          'A Drive asset failed verification. The local library was kept.',
        );
      }
    }

    final latestRemote = _asDrive(await _drive.read());
    if (latestRemote.generations.any(
          (item) => generationIds.values.contains(item.localId),
        ) ||
        latestRemote.savedReferences.any(
          (item) => referenceIds.values.contains(item.id),
        ) ||
        latestRemote.folders.any(
          (item) => folderIds.values.contains(item.id),
        )) {
      throw StateError(
        'Google Drive changed while the library was copied. '
        'No local originals were removed. Try moving again.',
      );
    }
    await _drive.write(
      latestRemote.copyWith(
        driveSyncBase: googleDrivePortableData(latestRemote),
        generations: <Generation>[...latestRemote.generations, ...generations],
        savedReferences: <SavedReference>[
          ...latestRemote.savedReferences,
          ...references,
        ],
        folders: <LibraryFolder>[...latestRemote.folders, ...folders],
      ),
    );
    final verified = _asDrive(await _drive.read());
    bool containsEvery<T>(
      Iterable<T> expected,
      Iterable<T> actual,
      String Function(T) id,
      Map<String, Object?> Function(T) json,
    ) {
      final actualById = <String, T>{for (final item in actual) id(item): item};
      return expected.every(
        (item) =>
            actualById.containsKey(id(item)) &&
            jsonEncode(json(item)) ==
                jsonEncode(json(actualById[id(item)] as T)),
      );
    }

    bool matches(StoredData expected, StoredData actual) =>
        containsEvery(
          expected.generations,
          actual.generations,
          (item) => item.localId,
          (item) => item.toJson(),
        ) &&
        containsEvery(
          expected.savedReferences,
          actual.savedReferences,
          (item) => item.id,
          (item) => item.toJson(),
        ) &&
        containsEvery(
          expected.folders,
          actual.folders,
          (item) => item.id,
          (item) => item.toJson(),
        );
    if (!matches(
      StoredData(
        generations: generations,
        savedReferences: references,
        folders: folders,
      ),
      verified,
    )) {
      throw StateError(
        'Some Drive copies failed verification. The local library was kept.',
      );
    }
    final operation = _workspaceWrites.then((_) async {
      final current = await _local.read();
      final currentLocal = _asLocal(current);
      if (!matches(source, currentLocal) ||
          source.generations.length != currentLocal.generations.length ||
          source.savedReferences.length !=
              currentLocal.savedReferences.length ||
          source.folders.length != currentLocal.folders.length) {
        throw StateError(
          'The local library changed while it was copied. Drive copies were '
          'kept, and no local originals were removed. Try moving again.',
        );
      }
      final kept = _asLocal(current).copyWith(
        generations: current.generations
            .where(
              (item) =>
                  item.storage == LibraryStorage.local &&
                  !generationIds.containsKey(item.localId),
            )
            .toList(),
        savedReferences: current.savedReferences
            .where(
              (item) =>
                  item.storage == LibraryStorage.local &&
                  !referenceIds.containsKey(item.id),
            )
            .toList(),
        folders: current.folders
            .where(
              (item) =>
                  item.storage == LibraryStorage.local &&
                  !folderIds.containsKey(item.id),
            )
            .toList(),
      );
      final combined = _combine(kept, verified);
      await _local.write(_localMirror(combined));
      await _local.pruneAssets(combined.generations, combined.savedReferences);
      _lastLocal = kept;
      _lastRemote = verified;
    });
    _workspaceWrites = operation.then<void>((_) {}, onError: (_) {});
    await operation;
    return GoogleDriveCopyCounts(
      generations: generations.length,
      references: references.length,
    );
  }

  Future<Generation> _copyGeneration(
    Generation source, {
    required String id,
    Map<String, String> referenceIdMap = const <String, String>{},
    Map<String, String> generationIdMap = const <String, String>{},
    String? folderId,
    Map<String, AssetReference>? assetCopies,
  }) async {
    Future<AssetReference?> copyAsset(AssetReference? reference) =>
        _copyAsset(reference, copies: assetCopies);
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
          source: await copyAsset(frame.source),
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
          promptName: item.promptName,
          durationSeconds: item.durationSeconds,
          referenceId: item.referenceId == null
              ? null
              : referenceIdMap[item.referenceId] ?? item.referenceId,
          source: await copyAsset(item.source),
          thumbnailAsset: await copyAsset(item.thumbnailAsset),
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
      source: await copyAsset(source.config.source),
      sourceThumbnailAsset: await copyAsset(source.config.sourceThumbnailAsset),
    );
    return Generation.fromJson(<String, Object?>{
      ...source.toJson(),
      'localId': id,
      'storage': LibraryStorage.drive.name,
      'config': config.toJson(),
      if (source.rewriteOfLocalId != null)
        'rewriteOfLocalId':
            generationIdMap[source.rewriteOfLocalId] ?? source.rewriteOfLocalId,
      if (folderId != null) 'folderId': folderId else 'folderId': null,
      if (source.resultAsset != null)
        'resultAsset': (await copyAsset(source.resultAsset))?.toJson(),
      if (source.thumbnailAsset != null)
        'thumbnailAsset': (await copyAsset(source.thumbnailAsset))?.toJson(),
      if (source.timelineThumbnailAsset != null)
        'timelineThumbnailAsset': (await copyAsset(
          source.timelineThumbnailAsset,
        ))?.toJson(),
    });
  }

  Future<AssetReference?> _copyAsset(
    AssetReference? reference, {
    Map<String, AssetReference>? copies,
  }) async {
    if (reference == null || reference.kind == 'drive') return reference;
    if (reference.kind != 'local') return reference;
    final existing = copies?[reference.value];
    if (existing != null) return existing;
    final bytes = await _local.readAsset(reference);
    final copied = await _drive.writeAsset(
      bytes,
      label: reference.label,
      contentType: reference.contentType ?? 'application/octet-stream',
    );
    copies?[reference.value] = copied;
    return copied;
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
      composerTabs: mergeComposerWorkspaces(
        local.composerTabs,
        remote.composerTabs,
      ),
      driveSyncBase: googleDrivePortableData(remote),
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
    composerTabs: data.composerTabs,
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
    composerTabs: data.composerTabs,
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
    driveSyncBase: data.driveSyncBase,
    composerTabs: data.composerTabs,
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
    providerCatalogCache: data.providerCatalogCache,
    composerTabs: data.composerTabs,
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
    StoredData combined, {
    bool forceWrite = false,
  }) async {
    // Reads and library writes may have started before a newer draft save.
    // Serialize this merge with local authoring so neither can erase that edit.
    final operation = _workspaceWrites.then((_) async {
      final latest = await _local.read();
      final mirror = _localMirror(combined).copyWith(
        composerTabs: mergeComposerWorkspaces(
          latest.composerTabs,
          combined.composerTabs,
        ),
      );
      if (!forceWrite &&
          jsonEncode(latest.toJson()) == jsonEncode(mirror.toJson())) {
        return;
      }
      await _local.write(mirror);
    });
    _workspaceWrites = operation.then<void>((_) {}, onError: (_) {});
    await operation;
  }

  String _encoded(StoredData data) =>
      jsonEncode(googleDrivePortableData(data).toJson());

  bool _isTransientDriveReadError(Exception error) {
    if (error is FormatException) return false;
    if (error is GoogleDriveException) {
      return error.isRateLimited || (error.status ?? 0) >= 500;
    }
    // http.ClientException, SocketException and TimeoutException are transport
    // failures. Schema/programming errors extend Error and never land here.
    return true;
  }

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
      data.composerTabs != null ||
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
