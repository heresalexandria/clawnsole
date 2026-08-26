import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

import 'asset_extensions.dart';
import 'durable_data_store.dart';
import 'google_drive.dart';
import 'google_drive_asset_presenter.dart';
import 'models.dart';

typedef GoogleDriveApiFactory = GoogleDriveApi Function(String accessToken);

/// The portable half of Clawnsole's library.
///
/// Authentication and local data are owned by the surface-specific gateway and
/// [HybridDataStore]. This class only owns app-created Drive files.
class GoogleDriveStore implements DurableDataStore {
  GoogleDriveStore({
    http.Client? client,
    GoogleDriveApiFactory? apiFactory,
    GoogleDriveAssetPresenter? presenter,
    DateTime Function()? clock,
    this.pruneGracePeriod = const Duration(hours: 1),
  }) : _client = client ?? http.Client(),
       _apiFactory = apiFactory,
       _presenter = presenter ?? createGoogleDriveAssetPresenter(),
       _clock = clock ?? DateTime.now;

  final http.Client _client;
  final GoogleDriveApiFactory? _apiFactory;
  final GoogleDriveAssetPresenter _presenter;
  final DateTime Function() _clock;
  final Duration pruneGracePeriod;

  GoogleDriveApi? _api;
  GoogleDriveFile? _stateFile;
  String _assetsFolderId = '';
  String _recordsFolderId = '';
  StoredData? _lastData;
  StoredData? _lastMainData;
  final Map<String, _GenerationRecordEntry> _recordIndex =
      <String, _GenerationRecordEntry>{};
  DateTime? _recordsListedAt;
  List<GoogleDriveFile>? _statsAssetListing;
  DateTime? _statsAssetListingAt;
  final Map<String, DateTime> _pendingAssetIds = <String, DateTime>{};

  /// How long [stats] may reuse the last assets-folder listing. A snapshot is
  /// rebuilt after every gateway action, and a fresh Drive listing for each
  /// one slows every interaction while burning Drive request quota.
  static const _statsListingLifetime = Duration(minutes: 2);

  /// How long [read] may reuse the last records-folder listing. Reads run on
  /// every gateway action; the periodic cross-device refresh (and any
  /// explicit refresh) still sees other devices' records within seconds
  /// without paying a listing per action.
  static const _recordListingLifetime = Duration(seconds: 15);
  GoogleDriveConnection _connection = const GoogleDriveConnection(
    state: GoogleDriveConnectionState.disconnected,
  );

  GoogleDriveConnection get connection => _connection;
  StoredData? get lastData => _lastData;

  Future<StoredData> connect(
    String accessToken,
    String requestedFolderName,
  ) async {
    final token = accessToken.trim();
    final name = requestedFolderName.trim();
    if (token.isEmpty) throw StateError('Google Drive authorization failed.');
    if (name.isEmpty || name.length > 120) {
      throw StateError(
        'Choose a Drive folder name between 1 and 120 characters.',
      );
    }
    _connection = GoogleDriveConnection(
      state: GoogleDriveConnectionState.connecting,
      folderName: name,
    );
    _invalidateStatsListing();
    try {
      _api =
          _apiFactory?.call(token) ??
          GoogleDriveApi(accessToken: token, client: _client);
      final root =
          await _api!.findRootFolder(name) ??
          await _api!.createFolder(
            name,
            appProperties: const <String, String>{
              'clawnsoleRoot': 'true',
              'schema': '2',
            },
          );
      final assets =
          await _api!.findChild(
            root.id,
            clawnsoleDriveAssetsFolder,
            appPropertyKey: 'clawnsoleAssets',
          ) ??
          await _api!.createFolder(
            clawnsoleDriveAssetsFolder,
            parentId: root.id,
            appProperties: const <String, String>{'clawnsoleAssets': 'true'},
          );
      _assetsFolderId = assets.id;
      // Schema 3: each generation lives in its own record file so concurrent
      // devices contend per record instead of on one shared state file. The
      // state file keeps folders, references, and a generations mirror that
      // older clients can still read.
      final records =
          await _api!.findChild(
            root.id,
            clawnsoleDriveRecordsFolder,
            appPropertyKey: 'clawnsoleRecords',
          ) ??
          await _api!.createFolder(
            clawnsoleDriveRecordsFolder,
            parentId: root.id,
            appProperties: const <String, String>{'clawnsoleRecords': 'true'},
          );
      _recordsFolderId = records.id;
      _recordIndex.clear();
      _recordsListedAt = null;
      _lastMainData = null;
      _stateFile = await _api!.findChild(
        root.id,
        clawnsoleDriveStateFile,
        appPropertyKey: 'clawnsoleState',
      );
      _connection = GoogleDriveConnection(
        state: GoogleDriveConnectionState.connected,
        folderName: name,
        folderId: root.id,
        message: 'Synced with Google Drive',
      );
      if (_stateFile == null) {
        const initial = StoredData();
        await _writeRemote(initial);
        _lastData = initial;
        _lastMainData = initial;
        return initial;
      }
      return await read();
    } on Object catch (error) {
      _api = null;
      _connection = GoogleDriveConnection(
        state: GoogleDriveConnectionState.disconnected,
        folderName: name,
        message: _message(error),
      );
      rethrow;
    }
  }

  Future<void> disconnect() async {
    _api = null;
    _stateFile = null;
    _assetsFolderId = '';
    _recordsFolderId = '';
    _recordIndex.clear();
    _recordsListedAt = null;
    _lastData = null;
    _lastMainData = null;
    _invalidateStatsListing();
    _connection = GoogleDriveConnection(
      state: GoogleDriveConnectionState.disconnected,
      folderName: connection.folderName,
      folderId: connection.folderId,
      message:
          'Drive disconnected on this device. Cloud files and the bounded local media cache were kept.',
    );
  }

  Future<StoredData> refresh() async {
    _requireConnected();
    _lastData = null;
    _lastMainData = null;
    _recordsListedAt = null;
    return read();
  }

  @override
  Future<StoredData> read() async {
    _requireConnected();
    if (_stateFile == null) return const StoredData();
    try {
      final main = await _readMainFile();
      await _refreshRecordIndex();
      final data = _composeData(main);
      _lastData = data;
      return data;
    } on GoogleDriveException catch (error) {
      _handleDriveError(error);
      rethrow;
    }
  }

  /// Reads the main state file: folders, references, and the generations
  /// mirror kept for older clients. Once one full read has landed, later
  /// reads validate the held copy with If-None-Match instead of
  /// re-downloading the whole file.
  Future<StoredData> _readMainFile() async {
    final current = _stateFile!;
    final cached = _lastMainData;
    final content = await _api!.readFile(
      current.id,
      ifNoneMatch: cached == null ? null : current.etag,
    );
    if (content == null) return cached!;
    _stateFile = GoogleDriveFile(
      id: current.id,
      name: current.name,
      mimeType: current.mimeType,
      size: content.bytes.length,
      modifiedTime: current.modifiedTime,
      etag: content.etag,
    );
    final data = StoredData.decode(utf8.decode(content.bytes));
    _lastMainData = data;
    return data;
  }

  /// Brings the in-memory record index up to date with the records folder.
  /// One listing call discovers changes; only records whose content hash
  /// moved are downloaded, and records absent from the listing were deleted
  /// by another device.
  Future<void> _refreshRecordIndex({bool force = false}) async {
    if (_recordsFolderId.isEmpty) return;
    final listedAt = _recordsListedAt;
    if (!force &&
        listedAt != null &&
        _now().difference(listedAt) < _recordListingLifetime) {
      return;
    }
    final files = await _api!.listChildren(
      _recordsFolderId,
      appPropertyKey: 'clawnsoleGeneration',
    );
    final byFileId = <String, _GenerationRecordEntry>{
      for (final entry in _recordIndex.values) entry.fileId: entry,
    };
    final fetched = <_GenerationRecordEntry>[];
    final changed = <GoogleDriveFile>[];
    for (final file in files) {
      final known = byFileId[file.id];
      if (known != null && known.md5 != null && known.md5 == file.md5) {
        fetched.add(known);
      } else {
        changed.add(file);
      }
    }
    // A cold sync fetches every record once; small parallel batches let a
    // large library attach in seconds instead of a serial crawl. Later
    // refreshes fetch only records whose content hash moved.
    const batch = 6;
    for (var start = 0; start < changed.length; start += batch) {
      final slice = changed.sublist(
        start,
        start + batch > changed.length ? changed.length : start + batch,
      );
      for (final entry in await Future.wait(slice.map(_fetchRecord))) {
        if (entry != null) fetched.add(entry);
      }
    }
    // Two devices can race to publish the same absorbed legacy generation and
    // leave duplicate files behind. Keep the winning content and clear the
    // stragglers so the folder stays canonical.
    final next = <String, _GenerationRecordEntry>{};
    final duplicates = <_GenerationRecordEntry>[];
    for (final entry in fetched) {
      final id = entry.generation.localId;
      final existing = next[id];
      if (existing == null) {
        next[id] = entry;
        continue;
      }
      final winner = resolveGenerationConflict(
        existing.generation,
        entry.generation,
      );
      if (identical(winner, existing.generation)) {
        duplicates.add(entry);
      } else {
        duplicates.add(existing);
        next[id] = entry;
      }
    }
    for (final duplicate in duplicates) {
      try {
        await _api!.deleteFile(duplicate.fileId);
      } on GoogleDriveException catch (error) {
        if (error.status != 404 && !error.isRateLimited) rethrow;
      }
    }
    _recordIndex
      ..clear()
      ..addAll(next);
    _recordsListedAt = _now();
  }

  Future<_GenerationRecordEntry?> _fetchRecord(GoogleDriveFile file) async {
    Uint8List bytes;
    String? etag;
    try {
      final content = (await _api!.readFile(file.id))!;
      bytes = content.bytes;
      etag = content.etag;
    } on GoogleDriveException catch (error) {
      // Deleted between the listing and this fetch: simply not a record.
      if (error.status == 404) return null;
      rethrow;
    }
    try {
      final decoded = jsonDecode(utf8.decode(bytes));
      if (decoded is! Map<Object?, Object?>) return null;
      final generation = Generation.fromJson(
        decoded.map((key, value) => MapEntry(key.toString(), value)),
      );
      if (generation.localId.trim().isEmpty) return null;
      return _GenerationRecordEntry(
        fileId: file.id,
        generation: generation,
        etag: etag,
        md5: file.md5,
      );
    } on Object {
      // A malformed record must not take down the whole library; it simply
      // stays invisible until a device rewrites it.
      return null;
    }
  }

  /// One library view from both layers: folders and references come from the
  /// main file, generations from the record files. A generation that exists
  /// only in the main file — or is newer there — was written by an older
  /// client and is absorbed; the next write publishes the winner back as a
  /// record file.
  StoredData _composeData(StoredData main) {
    final generations = <String, Generation>{
      for (final entry in _recordIndex.values)
        entry.generation.localId: entry.generation,
    };
    for (final legacy in main.generations) {
      final record = generations[legacy.localId];
      generations[legacy.localId] = record == null
          ? legacy
          : resolveGenerationConflict(legacy, record);
    }
    final ordered = generations.values.toList()
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return main.copyWith(generations: ordered);
  }

  @override
  Future<void> write(StoredData data) async {
    _requireConnected();
    try {
      if (_stateFile == null) {
        await _writeRemote(data);
        _lastData = data;
        _lastMainData = data;
        _acknowledgePublishedAssets(data);
        return;
      }
      final generations = await _writeGenerationRecords(data.generations);
      final resolved = data.copyWith(generations: generations);
      await _writeMainFileIfChanged(resolved);
      final composed = _composeData(_lastMainData ?? resolved);
      _lastData = composed;
      _acknowledgePublishedAssets(composed);
    } on GoogleDriveException catch (error) {
      _handleDriveError(error);
      rethrow;
    }
  }

  /// Publishes generation changes as individual record files, so two devices
  /// updating different generations never contend. Returns the records as
  /// they now stand in Drive: a lost per-record conflict adopts the remote
  /// winner instead of overwriting it.
  Future<List<Generation>> _writeGenerationRecords(
    List<Generation> next,
  ) async {
    if (_recordsFolderId.isEmpty) return next;
    final base = _lastData?.generations ?? const <Generation>[];
    final nextIds = <String>{for (final item in next) item.localId};
    // A record present in the previously composed view but absent from this
    // write was deleted by the caller. A record we have never seen stays: it
    // is a concurrent remote addition the caller's read simply missed.
    for (final previous in base) {
      if (nextIds.contains(previous.localId)) continue;
      final entry = _recordIndex.remove(previous.localId);
      if (entry == null) continue;
      try {
        await _api!.deleteFile(entry.fileId);
      } on GoogleDriveException catch (error) {
        if (error.status != 404) rethrow;
      }
    }
    final resolved = <Generation>[];
    for (final item in next) {
      resolved.add(await _writeGenerationRecord(item));
    }
    return resolved;
  }

  Future<Generation> _writeGenerationRecord(Generation item) async {
    final entry = _recordIndex[item.localId];
    if (entry == null) {
      final file = await _api!.createFile(
        parentId: _recordsFolderId,
        name: _cleanFileName('${item.localId}.json'),
        bytes: _recordBytes(item),
        contentType: 'application/json',
        appProperties: const <String, String>{'clawnsoleGeneration': 'true'},
      );
      _recordIndex[item.localId] = _GenerationRecordEntry(
        fileId: file.id,
        generation: item,
        etag: file.etag,
        md5: file.md5,
      );
      return item;
    }
    if (jsonEncode(entry.generation.toJson()) == jsonEncode(item.toJson())) {
      return item;
    }
    try {
      final file = await _api!.updateFile(
        entry.fileId,
        _recordBytes(item),
        contentType: 'application/json',
        etag: entry.etag,
      );
      entry
        ..generation = item
        ..etag = file.etag
        ..md5 = file.md5;
      return item;
    } on GoogleDriveException catch (error) {
      if (error.status == 404) {
        // The file vanished (another device deleted and this write revives
        // it, or a prune misfired): publish it fresh.
        _recordIndex.remove(item.localId);
        return _writeGenerationRecord(item);
      }
      if (error.status != 412) rethrow;
      // Another device updated this record concurrently: reconcile against
      // the remote version and publish the winner — or adopt it outright.
      final content = await _api!.readFile(entry.fileId);
      final remote = content == null
          ? null
          : await _fetchedGeneration(content.bytes);
      if (remote == null) {
        entry.etag = null;
        return item;
      }
      final winner = resolveGenerationConflict(item, remote);
      if (jsonEncode(winner.toJson()) == jsonEncode(remote.toJson())) {
        entry
          ..generation = remote
          ..etag = content!.etag
          ..md5 = null;
        return remote;
      }
      final file = await _api!.updateFile(
        entry.fileId,
        _recordBytes(winner),
        contentType: 'application/json',
        etag: content!.etag,
      );
      entry
        ..generation = winner
        ..etag = file.etag
        ..md5 = file.md5;
      return winner;
    }
  }

  Future<Generation?> _fetchedGeneration(Uint8List bytes) async {
    try {
      final decoded = jsonDecode(utf8.decode(bytes));
      if (decoded is! Map<Object?, Object?>) return null;
      return Generation.fromJson(
        decoded.map((key, value) => MapEntry(key.toString(), value)),
      );
    } on Object {
      return null;
    }
  }

  Uint8List _recordBytes(Generation item) =>
      Uint8List.fromList(utf8.encode(jsonEncode(item.toJson())));

  /// Rewrites the main state file only when folders or references changed,
  /// or the generations mirror kept for older clients drifted meaningfully.
  /// Poll bookkeeping never rewrites it — that churn lives in the record
  /// files, which is the whole point of the sharded layout.
  Future<void> _writeMainFileIfChanged(StoredData data) async {
    final base = _lastMainData;
    if (base != null && !_mainFileChanged(base, data)) return;
    final effectiveBase = base ?? await _readMainFile();
    var remote = await _readMainFile();
    var merged = mergeGoogleDriveData(
      base: effectiveBase,
      next: data,
      remote: remote,
    );
    try {
      await _writeRemote(merged);
    } on GoogleDriveException catch (error) {
      if (error.status != 412) rethrow;
      remote = await _readMainFile();
      merged = mergeGoogleDriveData(
        base: effectiveBase,
        next: data,
        remote: remote,
      );
      await _writeRemote(merged);
    }
    _lastMainData = merged;
  }

  bool _mainFileChanged(StoredData base, StoredData next) {
    if (jsonEncode(base.folders.map((item) => item.toJson()).toList()) !=
        jsonEncode(next.folders.map((item) => item.toJson()).toList())) {
      return true;
    }
    if (jsonEncode(
          base.savedReferences.map((item) => item.toJson()).toList(),
        ) !=
        jsonEncode(
          next.savedReferences.map((item) => item.toJson()).toList(),
        )) {
      return true;
    }
    return jsonEncode(
          base.generations.map(generationSyncFingerprint).toList(),
        ) !=
        jsonEncode(next.generations.map(generationSyncFingerprint).toList());
  }

  Future<void> _writeRemote(StoredData data) async {
    _requireConnected();
    final portable = googleDrivePortableData(data);
    final bytes = Uint8List.fromList(utf8.encode(portable.encode()));
    if (_stateFile == null) {
      _stateFile = await _api!.createFile(
        parentId: connection.folderId,
        name: clawnsoleDriveStateFile,
        bytes: bytes,
        contentType: 'application/json',
        appProperties: const <String, String>{
          'clawnsoleState': 'true',
          'schema': '2',
        },
      );
    } else {
      _stateFile = await _api!.updateFile(
        _stateFile!.id,
        bytes,
        contentType: 'application/json',
        etag: _stateFile!.etag,
      );
    }
  }

  @override
  Future<AssetReference> writeAsset(
    Uint8List bytes, {
    required String label,
    required String contentType,
    LibraryStorage storage = LibraryStorage.drive,
  }) async {
    _requireConnected();
    final cleanLabel = _cleanFileName(label);
    final unique = DateTime.now().microsecondsSinceEpoch.toRadixString(16);
    try {
      final file = await _api!.createFile(
        parentId: _assetsFolderId,
        name: '$unique-$cleanLabel',
        bytes: bytes,
        contentType: contentType,
        appProperties: const <String, String>{'clawnsoleAsset': 'true'},
      );
      final reference = AssetReference(
        kind: 'drive',
        value: file.id,
        label: label,
        contentType: contentType,
        bytes: bytes.length,
      );
      // Asset bytes and their metadata reference are necessarily published by
      // separate Drive requests. Keep this id protected until a later state
      // write confirms the reference, so concurrent preview cleanup cannot
      // delete a just-uploaded result in that gap.
      _pendingAssetIds[file.id] = _now();
      _invalidateStatsListing();
      if (_isLocallyCacheable(reference)) {
        try {
          // The uploaded bytes are already in hand. Materialize films and
          // preview images now so a relaunch never has to download them back
          // from Drive before showing the library.
          await _presenter.present(
            reference,
            Stream<List<int>>.value(bytes),
            expectedLength: bytes.length,
          );
        } on Object {
          // Retaining the asset is the durable operation. A cache that is
          // off, full, or temporarily unavailable must never make the upload
          // fail.
        }
      }
      return reference;
    } on GoogleDriveException catch (error) {
      _handleDriveError(error);
      rethrow;
    }
  }

  @override
  Future<AssetReference?> persistSource(
    String source, {
    required String label,
    AssetReference? retained,
    LibraryStorage storage = LibraryStorage.drive,
  }) async {
    if (retained?.kind == 'drive' && retained!.value.isNotEmpty) {
      return AssetReference(
        kind: 'drive',
        value: retained.value,
        label: label,
        contentType: retained.contentType,
        bytes: retained.bytes,
      );
    }
    if (source.startsWith('data:')) {
      final comma = source.indexOf(',');
      if (comma < 0) throw StateError('A selected asset is malformed.');
      final metadata = source.substring(5, comma).split(';');
      final contentType = metadata.first.isEmpty
          ? 'application/octet-stream'
          : metadata.first;
      final encoded = source.substring(comma + 1);
      final bytes = metadata.contains('base64')
          ? base64Decode(encoded)
          : Uint8List.fromList(utf8.encode(Uri.decodeComponent(encoded)));
      return writeAsset(bytes, label: label, contentType: contentType);
    }
    final remote = Uri.tryParse(source);
    if (remote?.scheme == 'https') {
      return AssetReference(kind: 'remote', value: source, label: label);
    }
    return null;
  }

  @override
  Future<Uint8List> readAsset(AssetReference reference) async {
    if (reference.kind != 'drive') {
      throw StateError('The asset is not stored in Google Drive.');
    }
    final cached = await _presenter.read(reference);
    if (cached != null) return cached;
    _requireConnected();
    try {
      final bytes = await _api!.downloadFile(reference.value);
      if (_isLocallyCacheable(reference)) {
        try {
          await _presenter.present(
            reference,
            Stream<List<int>>.value(bytes),
            expectedLength: bytes.length,
          );
        } on Object {
          // A read still succeeds when the bounded local cache is disabled,
          // full, or unavailable.
        }
      }
      return bytes;
    } on GoogleDriveException catch (error) {
      _handleDriveError(error);
      rethrow;
    }
  }

  /// Streams a Drive asset without buffering it in memory, for callers that
  /// write large videos to disk (or to an HTTP response) as bytes arrive.
  Future<GoogleDriveByteStream> readAssetStream(
    AssetReference reference,
  ) async {
    if (reference.kind != 'drive') {
      throw StateError('The asset is not stored in Google Drive.');
    }
    _requireConnected();
    try {
      return await _api!.readFileStream(reference.value);
    } on GoogleDriveException catch (error) {
      _handleDriveError(error);
      rethrow;
    }
  }

  /// Reads one byte range of a Drive asset for HTTP Range serving.
  Future<Uint8List> readAssetRange(
    AssetReference reference,
    int start,
    int end,
  ) async {
    if (reference.kind != 'drive') {
      throw StateError('The asset is not stored in Google Drive.');
    }
    _requireConnected();
    try {
      return await _api!.readFileRange(reference.value, start, end);
    } on GoogleDriveException catch (error) {
      _handleDriveError(error);
      rethrow;
    }
  }

  /// The already-materialized URI for [reference], or null when presenting it
  /// would require a Drive download.
  Future<Uri?> cachedAssetUri(AssetReference reference) async {
    if (reference.kind != 'drive') return Uri.parse(reference.value);
    return _presenter.lookup(reference);
  }

  /// Re-uploads referenced Drive assets that disappeared remotely when their
  /// bytes still exist in this device's bounded cache.
  ///
  /// This repairs the publication/pruning race in older builds without
  /// putting media in history JSON. The device that generated or previously
  /// played the media owns the recovery bytes; other devices simply keep the
  /// existing reference until that source device reconnects.
  Future<StoredData> repairMissingCachedAssets(StoredData data) async {
    _requireConnected();
    try {
      final liveIds = (await _driveAssets()).map((file) => file.id).toSet();
      final referenced = _referencedAssetReferences(
        data.generations,
        data.savedReferences,
      );
      final replacements = <String, AssetReference>{};
      for (final entry in referenced.entries) {
        if (liveIds.contains(entry.key)) continue;
        final bytes = await _presenter.read(entry.value);
        if (bytes == null || bytes.isEmpty) continue;
        replacements[entry.key] = await writeAsset(
          bytes,
          label: entry.value.label,
          contentType: entry.value.contentType ?? 'application/octet-stream',
        );
      }
      if (replacements.isEmpty) return data;
      final repaired = data.copyWith(
        generations: data.generations
            .map((item) => _replaceGenerationAssets(item, replacements))
            .toList(),
        savedReferences: data.savedReferences
            .map((item) => _replaceSavedReferenceAssets(item, replacements))
            .toList(),
      );
      await write(repaired);
      return _lastData ?? repaired;
    } on GoogleDriveException catch (error) {
      _handleDriveError(error);
      rethrow;
    }
  }

  @override
  Future<Uri> assetUri(AssetReference reference) async {
    if (reference.kind != 'drive') return Uri.parse(reference.value);
    // A cached asset plays instantly, even while Drive is reconnecting.
    final cached = await _presenter.lookup(reference);
    if (cached != null) return cached;
    _requireConnected();
    try {
      final download = await _api!.readFileStream(reference.value);
      return await _presenter.present(
        reference,
        download.stream,
        expectedLength: download.contentLength ?? reference.bytes,
      );
    } on GoogleDriveException catch (error) {
      _handleDriveError(error);
      rethrow;
    }
  }

  @override
  Future<void> pruneAssets(
    List<Generation> generations, [
    List<SavedReference> savedReferences = const <SavedReference>[],
  ]) async {
    if (_api == null || _assetsFolderId.isEmpty) return;
    final retained = _referencedAssetIds(generations, savedReferences);
    final canonical = _lastData;
    if (canonical != null) {
      retained.addAll(
        _referencedAssetIds(canonical.generations, canonical.savedReferences),
      );
    }
    final cutoff = _now().subtract(pruneGracePeriod);
    _pendingAssetIds.removeWhere((_, createdAt) => createdAt.isBefore(cutoff));
    retained.addAll(_pendingAssetIds.keys);
    var deleted = false;
    for (final file in await _driveAssets()) {
      final recentlyUploaded =
          file.modifiedTime != null && !file.modifiedTime!.isBefore(cutoff);
      if (!retained.contains(file.id) && !recentlyUploaded) {
        await _api!.deleteFile(file.id);
        deleted = true;
      }
    }
    if (deleted) _invalidateStatsListing();
  }

  @override
  Future<void> delete() async {
    _requireConnected();
    for (final file in await _driveAssets()) {
      await _api!.deleteFile(file.id);
    }
    if (_recordsFolderId.isNotEmpty) {
      for (final file in await _api!.listChildren(
        _recordsFolderId,
        appPropertyKey: 'clawnsoleGeneration',
      )) {
        await _api!.deleteFile(file.id);
      }
    }
    _recordIndex.clear();
    _recordsListedAt = null;
    if (_stateFile != null) await _api!.deleteFile(_stateFile!.id);
    _stateFile = null;
    _lastData = const StoredData();
    _lastMainData = const StoredData();
    _invalidateStatsListing();
  }

  @override
  Future<StorageStats> stats(int records) async {
    var assetBytes = 0;
    var assets = 0;
    if (_api != null && _assetsFolderId.isNotEmpty) {
      final files = await _statsAssets();
      assetBytes = files.fold(0, (sum, file) => sum + file.size);
      assets = files.length;
    }
    final data = _lastData ?? const StoredData();
    return StorageStats(
      path: connection.isConnected
          ? 'Google Drive / ${connection.folderName} / $clawnsoleDriveStateFile'
          : 'Google Drive not connected',
      bytes: utf8.encode(googleDrivePortableData(data).encode()).length,
      records: records,
      assetBytes: assetBytes,
      assets: assets,
      lastUpdated: _stateFile?.modifiedTime,
    );
  }

  Future<List<GoogleDriveFile>> _driveAssets() async {
    final files = await _api!.listChildren(
      _assetsFolderId,
      appPropertyKey: 'clawnsoleAsset',
    );
    _statsAssetListing = files;
    _statsAssetListingAt = _now();
    return files;
  }

  Future<List<GoogleDriveFile>> _statsAssets() async {
    final cached = _statsAssetListing;
    final fetchedAt = _statsAssetListingAt;
    if (cached != null &&
        fetchedAt != null &&
        _now().difference(fetchedAt) < _statsListingLifetime) {
      return cached;
    }
    return _driveAssets();
  }

  void _invalidateStatsListing() {
    _statsAssetListing = null;
    _statsAssetListingAt = null;
  }

  Set<String> _referencedAssetIds(
    List<Generation> generations,
    List<SavedReference> references,
  ) => _referencedAssetReferences(generations, references).keys.toSet();

  Map<String, AssetReference> _referencedAssetReferences(
    List<Generation> generations,
    List<SavedReference> references,
  ) {
    final retained = <String, AssetReference>{};
    void add(AssetReference reference) {
      if (reference.kind == 'drive' && reference.value.isNotEmpty) {
        retained.putIfAbsent(reference.value, () => reference);
      }
    }

    for (final generation in generations) {
      generationAssetReferences(generation).forEach(add);
    }
    for (final reference in references) {
      savedReferenceAssetReferences(reference).forEach(add);
    }
    return retained;
  }

  void _acknowledgePublishedAssets(StoredData data) {
    final published = _referencedAssetIds(
      data.generations,
      data.savedReferences,
    );
    _pendingAssetIds.removeWhere((id, _) => published.contains(id));
  }

  Generation _replaceGenerationAssets(
    Generation item,
    Map<String, AssetReference> replacements,
  ) => mapGenerationAssets(
    item,
    (reference) => reference.kind == 'drive'
        ? replacements[reference.value] ?? reference
        : reference,
  );

  SavedReference _replaceSavedReferenceAssets(
    SavedReference item,
    Map<String, AssetReference> replacements,
  ) => mapSavedReferenceAssets(
    item,
    (reference) => reference.kind == 'drive'
        ? replacements[reference.value] ?? reference
        : reference,
  );

  bool _isLocallyCacheable(AssetReference reference) {
    final contentType = reference.contentType?.toLowerCase() ?? '';
    return contentType.startsWith('video/') || contentType.startsWith('image/');
  }

  DateTime _now() => _clock().toUtc();

  void _requireConnected() {
    if (_api == null || !connection.isConnected) {
      throw StateError('Connect Google Drive to continue.');
    }
  }

  void _handleDriveError(GoogleDriveException error) {
    // A quota burst also answers 403, and treating it as an expired grant
    // would flap the connection into a reconnect loop that burns yet more
    // quota. Only genuine authorization failures forget the session.
    if (error.isRateLimited) return;
    if (error.status == 401 || error.status == 403) {
      _api = null;
      _connection = GoogleDriveConnection(
        state: GoogleDriveConnectionState.disconnected,
        folderName: connection.folderName,
        folderId: connection.folderId,
        message: 'Drive access expired. Reconnect to continue syncing.',
      );
    }
  }

  String _cleanFileName(String value) {
    final clean = value
        .replaceAll(RegExp(r'[\\/:*?"<>|]'), '-')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    return clean.isEmpty
        ? 'clawnsole.asset'
        : clean.substring(0, clean.length.clamp(0, 100));
  }

  String _message(Object error) => error
      .toString()
      .replaceFirst('Bad state: ', '')
      .replaceFirst('Exception: ', '');
}

/// One generation's Drive record file as this device last saw it. The etag
/// guards concurrent updates; the listing hash spots remote changes without
/// downloading unchanged records.
class _GenerationRecordEntry {
  _GenerationRecordEntry({
    required this.fileId,
    required this.generation,
    this.etag,
    this.md5,
  });

  final String fileId;
  Generation generation;
  String? etag;
  String? md5;
}
