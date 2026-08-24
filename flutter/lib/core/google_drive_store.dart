import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

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
  }) : _client = client ?? http.Client(),
       _apiFactory = apiFactory,
       _presenter = presenter ?? createGoogleDriveAssetPresenter();

  final http.Client _client;
  final GoogleDriveApiFactory? _apiFactory;
  final GoogleDriveAssetPresenter _presenter;

  GoogleDriveApi? _api;
  GoogleDriveFile? _stateFile;
  String _assetsFolderId = '';
  StoredData? _lastData;
  GoogleDriveConnection _connection = const GoogleDriveConnection(
    state: GoogleDriveConnectionState.disconnected,
  );

  GoogleDriveConnection get connection => _connection;

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
    _lastData = null;
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
    if (_stateFile == null) return const StoredData();
    try {
      final current = _stateFile!;
      final content = await _api!.readFile(current.id);
      _stateFile = GoogleDriveFile(
        id: current.id,
        name: current.name,
        mimeType: current.mimeType,
        size: content.bytes.length,
        modifiedTime: current.modifiedTime,
        etag: content.etag,
      );
      final data = StoredData.decode(utf8.decode(content.bytes));
      _lastData = data;
      return data;
    } on GoogleDriveException catch (error) {
      _handleDriveError(error);
      rethrow;
    }
  }

  @override
  Future<void> write(StoredData data) async {
    _requireConnected();
    try {
      if (_stateFile == null) {
        await _writeRemote(data);
        _lastData = data;
        return;
      }
      final base = _lastData ?? await read();
      var remote = await read();
      var merged = mergeGoogleDriveData(base: base, next: data, remote: remote);
      try {
        await _writeRemote(merged);
      } on GoogleDriveException catch (error) {
        if (error.status != 412) rethrow;
        remote = await read();
        merged = mergeGoogleDriveData(base: base, next: data, remote: remote);
        await _writeRemote(merged);
      }
      _lastData = merged;
    } on GoogleDriveException catch (error) {
      _handleDriveError(error);
      rethrow;
    }
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
    for (final file in await _driveAssets()) {
      if (!retained.contains(file.id)) await _api!.deleteFile(file.id);
    }
  }

  @override
  Future<void> delete() async {
    _requireConnected();
    for (final file in await _driveAssets()) {
      await _api!.deleteFile(file.id);
    }
    if (_stateFile != null) await _api!.deleteFile(_stateFile!.id);
    _stateFile = null;
    _lastData = const StoredData();
  }

  @override
  Future<StorageStats> stats(int records) async {
    var assetBytes = 0;
    var assets = 0;
    if (_api != null && _assetsFolderId.isNotEmpty) {
      final files = await _driveAssets();
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

  Future<List<GoogleDriveFile>> _driveAssets() =>
      _api!.listChildren(_assetsFolderId, appPropertyKey: 'clawnsoleAsset');

  Set<String> _referencedAssetIds(
    List<Generation> generations,
    List<SavedReference> references,
  ) {
    final retained = <String>{};
    void add(AssetReference? reference) {
      if (reference?.kind == 'drive') retained.add(reference!.value);
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
    for (final reference in references) {
      add(reference.asset);
      add(reference.thumbnailAsset);
    }
    return retained;
  }

  bool _isLocallyCacheable(AssetReference reference) {
    final contentType = reference.contentType?.toLowerCase() ?? '';
    return contentType.startsWith('video/') || contentType.startsWith('image/');
  }

  void _requireConnected() {
    if (_api == null || !connection.isConnected) {
      throw StateError('Connect Google Drive to continue.');
    }
  }

  void _handleDriveError(GoogleDriveException error) {
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
