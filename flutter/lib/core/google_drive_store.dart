import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

import 'asset_extensions.dart';
import 'asset_stream.dart';
import 'durable_data_store.dart';
import 'google_drive.dart';
import 'google_drive_asset_presenter.dart';
import 'models.dart';

typedef GoogleDriveApiFactory = GoogleDriveApi Function(String accessToken);

/// The portable half of Clawnsole's library.
///
/// Authentication and local data are owned by the surface-specific gateway and
/// [HybridDataStore]. This class only owns app-created Drive files.
class GoogleDriveStore implements DurableDataStore, StreamingAssetStore {
  GoogleDriveStore({
    http.Client? client,
    GoogleDriveApiFactory? apiFactory,
    GoogleDriveAssetPresenter? presenter,
    DateTime Function()? clock,
    this.pruneGracePeriod = const Duration(hours: 1),
    this.metadataReadTimeout = const Duration(seconds: 30),
  }) : _client = client ?? http.Client(),
       _apiFactory = apiFactory,
       _presenter = presenter ?? createGoogleDriveAssetPresenter(),
       _clock = clock ?? DateTime.now;

  final http.Client _client;
  final GoogleDriveApiFactory? _apiFactory;
  final GoogleDriveAssetPresenter _presenter;
  final DateTime Function() _clock;
  final Duration pruneGracePeriod;
  final Duration metadataReadTimeout;

  GoogleDriveApi? _api;
  int _sessionRevision = 0;
  GoogleDriveFile? _stateFile;
  String _assetsFolderId = '';
  StoredData? _lastData;
  List<GoogleDriveFile>? _statsAssetListing;
  DateTime? _statsAssetListingAt;
  final Map<String, DateTime> _pendingAssetIds = <String, DateTime>{};

  /// How long [stats] may reuse the last assets-folder listing. A snapshot is
  /// rebuilt after every gateway action, and a fresh Drive listing for each
  /// one slows every interaction while burning Drive request quota.
  static const _statsListingLifetime = Duration(minutes: 2);
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
    final sessionRevision = ++_sessionRevision;
    _api = null;
    _stateFile = null;
    _assetsFolderId = '';
    _lastData = null;
    _connection = GoogleDriveConnection(
      state: GoogleDriveConnectionState.connecting,
      folderName: name,
    );
    _invalidateStatsListing();
    try {
      final api =
          _apiFactory?.call(token) ??
          GoogleDriveApi(accessToken: token, client: _client);
      var root = await api.findRootFolder(name);
      _requireCurrentSession(sessionRevision);
      root ??= await api.createFolder(
        name,
        appProperties: const <String, String>{
          'clawnsoleRoot': 'true',
          'schema': '2',
        },
      );
      _requireCurrentSession(sessionRevision);
      var assets = await api.findChild(
        root.id,
        clawnsoleDriveAssetsFolder,
        appPropertyKey: 'clawnsoleAssets',
      );
      _requireCurrentSession(sessionRevision);
      assets ??= await api.createFolder(
        clawnsoleDriveAssetsFolder,
        parentId: root.id,
        appProperties: const <String, String>{'clawnsoleAssets': 'true'},
      );
      _requireCurrentSession(sessionRevision);
      final stateFile = await api.findChild(
        root.id,
        clawnsoleDriveStateFile,
        appPropertyKey: 'clawnsoleState',
      );
      _requireCurrentSession(sessionRevision);
      _api = api;
      _assetsFolderId = assets.id;
      _stateFile = stateFile;
      _connection = GoogleDriveConnection(
        state: GoogleDriveConnectionState.connected,
        folderName: name,
        folderId: root.id,
        message: 'Synced with Google Drive',
      );
      if (_stateFile == null) {
        const initial = StoredData();
        await _writeRemote(initial);
        _requireCurrentSession(sessionRevision);
        _lastData = initial;
        return initial;
      }
      return await read();
    } on Object catch (error) {
      if (sessionRevision != _sessionRevision) rethrow;
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
    _sessionRevision++;
    _api = null;
    _stateFile = null;
    _assetsFolderId = '';
    _lastData = null;
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
    return read();
  }

  @override
  Future<StoredData> read() async {
    _requireConnected();
    final sessionRevision = _sessionRevision;
    if (_stateFile == null) return const StoredData();
    try {
      final current = _stateFile!;
      final cached = _lastData;
      // Reads dominate this store's Drive traffic (every write also reads to
      // merge). Once one full read has landed, later reads validate the held
      // copy with If-None-Match instead of re-downloading the whole file.
      final content = await _api!
          .readFile(
            current.id,
            ifNoneMatch: cached == null ? null : current.etag,
          )
          .timeout(metadataReadTimeout);
      _requireCurrentSession(sessionRevision);
      if (content == null) return cached!.copyWith(driveSyncBase: cached);
      // Accept the validator only with a fully decoded snapshot. Otherwise a
      // later 304 could pair the rejected document's ETag with older data and
      // allow a stale write to overwrite an unsupported schema.
      final data = StoredData.decode(utf8.decode(content.bytes));
      _stateFile = GoogleDriveFile(
        id: current.id,
        name: current.name,
        mimeType: current.mimeType,
        size: content.bytes.length,
        modifiedTime: current.modifiedTime,
        etag: content.etag,
      );
      _lastData = data;
      return data.copyWith(driveSyncBase: data);
    } on GoogleDriveException catch (error) {
      _handleDriveError(error, sessionRevision);
      rethrow;
    }
  }

  @override
  Future<void> write(StoredData data) async {
    _requireConnected();
    final sessionRevision = _sessionRevision;
    try {
      if (_stateFile == null) {
        await _writeRemote(data);
        _requireCurrentSession(sessionRevision);
        _lastData = data;
        _acknowledgePublishedAssets(data);
        return;
      }
      final base = data.driveSyncBase ?? _lastData ?? await read();
      _requireCurrentSession(sessionRevision);
      var remote = await read();
      _requireCurrentSession(sessionRevision);
      var merged = mergeGoogleDriveData(base: base, next: data, remote: remote);
      // A 412 means another device published between our read and write.
      // Re-merge onto the newer remote and try again; three attempts matches
      // the settings vault so active multi-device editing does not drop a
      // whole poll cycle's outcome on the first collision.
      for (var attempt = 1; ; attempt += 1) {
        try {
          _requireCurrentSession(sessionRevision);
          await _writeRemote(merged);
          break;
        } on GoogleDriveException catch (error) {
          if (error.status != 412 || attempt >= 3) rethrow;
          _requireCurrentSession(sessionRevision);
          remote = await read();
          _requireCurrentSession(sessionRevision);
          merged = mergeGoogleDriveData(base: base, next: data, remote: remote);
        }
      }
      _requireCurrentSession(sessionRevision);
      _lastData = merged;
      _acknowledgePublishedAssets(merged);
    } on GoogleDriveException catch (error) {
      _handleDriveError(error, sessionRevision);
      rethrow;
    }
  }

  Future<void> _writeRemote(StoredData data) async {
    _requireConnected();
    final sessionRevision = _sessionRevision;
    final portable = googleDrivePortableData(data);
    final bytes = Uint8List.fromList(utf8.encode(portable.encode()));
    final GoogleDriveFile updated;
    if (_stateFile == null) {
      updated = await _api!.createFile(
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
      updated = await _api!.updateFile(
        _stateFile!.id,
        bytes,
        contentType: 'application/json',
        etag: _stateFile!.etag,
      );
    }
    _requireCurrentSession(sessionRevision);
    _stateFile = updated;
  }

  @override
  Future<AssetReference> writeAsset(
    Uint8List bytes, {
    required String label,
    required String contentType,
    LibraryStorage storage = LibraryStorage.drive,
  }) async {
    _requireConnected();
    final sessionRevision = _sessionRevision;
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
      _handleDriveError(error, sessionRevision);
      rethrow;
    }
  }

  @override
  Future<AssetReference> writeAssetStream(
    Stream<List<int>> stream, {
    required String label,
    required String contentType,
    LibraryStorage storage = LibraryStorage.drive,
    int? expectedLength,
    String? expectedSha256,
    int maxBytes = maxRetainedAssetBytes,
    Duration idleTimeout = assetStreamIdleTimeout,
    Duration totalTimeout = assetStreamTotalTimeout,
  }) async {
    if (!_connection.isConnected) {
      await stream.listen(null).cancel();
      _requireConnected();
    }
    final sessionRevision = _sessionRevision;
    final watch = Stopwatch()..start();
    Duration remaining() {
      final value = totalTimeout - watch.elapsed;
      if (value <= Duration.zero) {
        throw TimeoutException(
          'The media transfer exceeded its total deadline.',
        );
      }
      return value;
    }

    final staged = await stageAssetStream(
      stream,
      expectedLength: expectedLength,
      expectedSha256: expectedSha256,
      maxBytes: maxBytes,
      idleTimeout: idleTimeout,
      totalTimeout: remaining(),
    );
    try {
      _requireCurrentSession(sessionRevision);
      _requireConnected();
      final unique = DateTime.now().microsecondsSinceEpoch.toRadixString(16);
      final file = await _api!.createFileStream(
        parentId: _assetsFolderId,
        name: '$unique-${_cleanFileName(label)}',
        bytes: staged.openRead(),
        length: staged.length,
        contentType: contentType,
        appProperties: {'clawnsoleAsset': 'true', 'sha256': staged.sha256},
        timeout: remaining(),
      );
      if (file.size != staged.length) {
        throw const AssetTransferException(
          'Google Drive retained an unexpected media size.',
        );
      }
      final reference = AssetReference(
        kind: 'drive',
        value: file.id,
        label: label,
        contentType: contentType,
        bytes: staged.length,
        sha256: staged.sha256,
      );
      _pendingAssetIds[file.id] = _now();
      _invalidateStatsListing();
      if (_isLocallyCacheable(reference)) {
        try {
          await _presenter
              .present(
                reference,
                staged.openRead(),
                expectedLength: staged.length,
              )
              .timeout(remaining());
        } on Object {
          /* A cache failure does not undo a durable upload. */
        }
      }
      return reference;
    } on GoogleDriveException catch (error) {
      _handleDriveError(error, sessionRevision);
      rethrow;
    } finally {
      await staged.dispose();
    }
  }

  @override
  Future<Stream<List<int>>> openAssetRead(AssetReference reference) async =>
      (await readAssetStream(reference)).stream;

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
        sha256: retained.sha256,
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
    final sessionRevision = _sessionRevision;
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
      _handleDriveError(error, sessionRevision);
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
    final sessionRevision = _sessionRevision;
    try {
      return await _api!.readFileStream(reference.value);
    } on GoogleDriveException catch (error) {
      _handleDriveError(error, sessionRevision);
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
    final sessionRevision = _sessionRevision;
    try {
      return await _api!.readFileRange(reference.value, start, end);
    } on GoogleDriveException catch (error) {
      _handleDriveError(error, sessionRevision);
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
    final sessionRevision = _sessionRevision;
    try {
      final liveIds = (await _driveAssets()).map((file) => file.id).toSet();
      final referenced = _referencedAssetReferences(
        data.generations,
        data.savedReferences,
      );
      final replacements = <String, AssetReference>{};
      for (final entry in referenced.entries) {
        _requireCurrentSession(sessionRevision);
        if (liveIds.contains(entry.key)) continue;
        final bytes = await _presenter.read(entry.value);
        if (bytes == null || bytes.isEmpty) continue;
        _requireCurrentSession(sessionRevision);
        replacements[entry.key] = await writeAsset(
          bytes,
          label: entry.value.label,
          contentType: entry.value.contentType ?? 'application/octet-stream',
        );
      }
      _requireCurrentSession(sessionRevision);
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
      _handleDriveError(error, sessionRevision);
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
    final sessionRevision = _sessionRevision;
    try {
      final download = await _api!.readFileStream(reference.value);
      return await _presenter.present(
        reference,
        download.stream,
        expectedLength: download.contentLength ?? reference.bytes,
      );
    } on GoogleDriveException catch (error) {
      _handleDriveError(error, sessionRevision);
      rethrow;
    }
  }

  @override
  Future<void> pruneAssets(
    List<Generation> generations, [
    List<SavedReference> savedReferences = const <SavedReference>[],
  ]) async {
    if (_api == null || _assetsFolderId.isEmpty) return;
    final sessionRevision = _sessionRevision;
    final retained = _referencedAssetIds(generations, savedReferences);
    final canonical = _lastData;
    if (canonical != null) {
      retained.addAll(
        _referencedAssetIds(canonical.generations, canonical.savedReferences),
      );
      for (final json
          in canonical.composerTabs?.retainedAssetJson ??
              const <Map<String, Object?>>[]) {
        final reference = AssetReference.fromJson(json);
        if (reference.kind == 'drive') retained.add(reference.value);
      }
    }
    final cutoff = _now().subtract(pruneGracePeriod);
    _pendingAssetIds.removeWhere((_, createdAt) => createdAt.isBefore(cutoff));
    retained.addAll(_pendingAssetIds.keys);
    var deleted = false;
    for (final file in await _driveAssets()) {
      _requireCurrentSession(sessionRevision);
      final recentlyUploaded =
          file.modifiedTime != null && !file.modifiedTime!.isBefore(cutoff);
      if (!retained.contains(file.id) && !recentlyUploaded) {
        await _api!.deleteFile(file.id);
        deleted = true;
      }
    }
    _requireCurrentSession(sessionRevision);
    if (deleted) _invalidateStatsListing();
  }

  @override
  Future<void> delete() async {
    _requireConnected();
    final sessionRevision = _sessionRevision;
    for (final file in await _driveAssets()) {
      _requireCurrentSession(sessionRevision);
      await _api!.deleteFile(file.id);
    }
    _requireCurrentSession(sessionRevision);
    if (_stateFile != null) await _api!.deleteFile(_stateFile!.id);
    _requireCurrentSession(sessionRevision);
    _stateFile = null;
    _lastData = const StoredData();
    _invalidateStatsListing();
  }

  @override
  Future<StorageStats> stats(int records) async {
    var assetBytes = 0;
    var assets = 0;
    if (_api != null && _assetsFolderId.isNotEmpty) {
      final files = await _statsAssets().timeout(metadataReadTimeout);
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
    _requireConnected();
    final sessionRevision = _sessionRevision;
    final files = await _api!.listChildren(
      _assetsFolderId,
      appPropertyKey: 'clawnsoleAsset',
    );
    _requireCurrentSession(sessionRevision);
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

  void _requireCurrentSession(int revision) {
    if (revision != _sessionRevision) {
      throw StateError('The Drive session changed. Try the operation again.');
    }
  }

  void _handleDriveError(GoogleDriveException error, int sessionRevision) {
    // A response from the old token must not disconnect the replacement
    // session that silent renewal established while this request was pending.
    if (sessionRevision != _sessionRevision) return;
    // A quota burst also answers 403, and treating it as an expired grant
    // would flap the connection into a reconnect loop that burns yet more
    // quota. Only genuine authorization failures forget the session.
    if (error.isRateLimited) return;
    if (error.status == 401 || error.status == 403) {
      _sessionRevision++;
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
