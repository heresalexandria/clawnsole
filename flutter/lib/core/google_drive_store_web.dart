import 'dart:convert';
import 'dart:js_interop';
import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'package:web/web.dart' as web;

import 'durable_data_store.dart';
import 'google_drive.dart';
import 'models.dart';

const _googleClientId = String.fromEnvironment('CLAWNSOLE_GOOGLE_CLIENT_ID');
const _apiKeysStorageKey = 'clawnsole.web.apiKeys.v1';
const _preferencesStorageKey = 'clawnsole.web.preferences.v1';
const _driveFolderNameStorageKey = 'clawnsole.web.driveFolderName.v1';
const _driveFolderIdStorageKey = 'clawnsole.web.driveFolderId.v1';

@JS('clawnsoleGoogleDrive.authorize')
external JSPromise<JSString> _authorizeGoogleDrive(JSString clientId);

typedef GoogleDriveApiFactory = GoogleDriveApi Function(String accessToken);

class GoogleDriveStore implements DurableDataStore {
  GoogleDriveStore({
    http.Client? client,
    GoogleDriveApiFactory? apiFactory,
    Future<String> Function()? authorize,
  }) : _client = client ?? http.Client(),
       _apiFactory = apiFactory,
       _authorize = authorize;

  final http.Client _client;
  final GoogleDriveApiFactory? _apiFactory;
  final Future<String> Function()? _authorize;
  final Map<String, String> _objectUrls = <String, String>{};

  GoogleDriveApi? _api;
  GoogleDriveFile? _stateFile;
  String _assetsFolderId = '';
  StoredData? _lastData;
  GoogleDriveConnection _connection = GoogleDriveConnection(
    state: _googleClientId.isEmpty
        ? GoogleDriveConnectionState.unavailable
        : GoogleDriveConnectionState.disconnected,
    folderName:
        web.window.localStorage.getItem(_driveFolderNameStorageKey) ?? '',
    folderId: web.window.localStorage.getItem(_driveFolderIdStorageKey) ?? '',
    message: _googleClientId.isEmpty
        ? 'Build this target with CLAWNSOLE_GOOGLE_CLIENT_ID to enable Drive.'
        : '',
  );

  GoogleDriveConnection get connection => _connection;

  Future<StoredData> connect(String requestedFolderName) async {
    final name = requestedFolderName.trim();
    if (_googleClientId.isEmpty && _authorize == null) {
      throw StateError(
        'This build does not have a Google OAuth client ID configured.',
      );
    }
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
      final token = await (_authorize?.call() ?? _authorizeWithGoogle());
      _api =
          _apiFactory?.call(token) ??
          GoogleDriveApi(accessToken: token, client: _client);
      final root =
          await _api!.findRootFolder(name) ??
          await _api!.createFolder(
            name,
            appProperties: const <String, String>{
              'clawnsoleRoot': 'true',
              'schema': '1',
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
      web.window.localStorage.setItem(_driveFolderNameStorageKey, name);
      web.window.localStorage.setItem(_driveFolderIdStorageKey, root.id);
      _connection = GoogleDriveConnection(
        state: GoogleDriveConnectionState.connected,
        folderName: name,
        folderId: root.id,
        message: 'Synced with Google Drive',
      );
      if (_stateFile == null) {
        final initial = _localData();
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

  Future<String> _authorizeWithGoogle() async {
    final token = await _authorizeGoogleDrive(_googleClientId.toJS).toDart;
    final value = token.toDart.trim();
    if (value.isEmpty) throw StateError('Google Drive authorization failed.');
    return value;
  }

  Future<StoredData> disconnect() async {
    _api = null;
    _stateFile = null;
    _assetsFolderId = '';
    _lastData = null;
    for (final url in _objectUrls.values) {
      web.URL.revokeObjectURL(url);
    }
    _objectUrls.clear();
    _connection = GoogleDriveConnection(
      state: _googleClientId.isEmpty
          ? GoogleDriveConnectionState.unavailable
          : GoogleDriveConnectionState.disconnected,
      folderName: connection.folderName,
      folderId: connection.folderId,
      message: 'Drive disconnected on this device. Cloud files were kept.',
    );
    return _localData();
  }

  Future<StoredData> refresh() async {
    _requireConnected();
    _lastData = null;
    return read();
  }

  @override
  Future<StoredData> read() async {
    final local = _localData();
    if (_api == null || _stateFile == null) {
      _lastData = local;
      return local;
    }
    try {
      final combined = await _readRemote(local);
      _savePreferences(combined.preferences);
      _lastData = combined;
      return combined;
    } on GoogleDriveException catch (error) {
      _handleDriveError(error);
      rethrow;
    }
  }

  @override
  Future<void> write(StoredData data) async {
    _saveLocal(data);
    if (_api == null) {
      if (_portableContentChanged(_lastData ?? _localData(), data)) {
        throw StateError(
          'Connect Google Drive before saving generations, folders, or references in the standalone web app.',
        );
      }
      _lastData = data;
      return;
    }
    try {
      if (_stateFile == null) {
        await _writeRemote(data);
        _lastData = data;
        return;
      }
      final base = _lastData ?? await read();
      var remote = await _readRemote(_localData());
      var merged = mergeGoogleDriveData(base: base, next: data, remote: remote);
      try {
        await _writeRemote(merged);
      } on GoogleDriveException catch (error) {
        if (error.status != 412) rethrow;
        remote = await _readRemote(_localData());
        merged = mergeGoogleDriveData(base: base, next: data, remote: remote);
        await _writeRemote(merged);
      }
      _saveLocal(merged);
      _lastData = merged;
    } on GoogleDriveException catch (error) {
      _handleDriveError(error);
      rethrow;
    }
  }

  Future<StoredData> _readRemote(StoredData local) async {
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
    final cloud = StoredData.decode(utf8.decode(content.bytes));
    return cloud.copyWith(
      apiKey: local.apiKey,
      apiKeys: local.apiKeys,
      rejectedIosReviewApiKeyId: '',
      rejectedIosReviewApiKeyIds: const <String, String>{},
    );
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
          'schema': '1',
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
      return AssetReference(
        kind: 'drive',
        value: file.id,
        label: label,
        contentType: contentType,
        bytes: bytes.length,
      );
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
      if (comma < 0) throw StateError('A selected browser asset is malformed.');
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
    _requireConnected();
    try {
      return await _api!.downloadFile(reference.value);
    } on GoogleDriveException catch (error) {
      _handleDriveError(error);
      rethrow;
    }
  }

  @override
  Future<Uri> assetUri(AssetReference reference) async {
    if (reference.kind != 'drive') return Uri.parse(reference.value);
    final cached = _objectUrls[reference.value];
    if (cached != null) return Uri.parse(cached);
    final bytes = await readAsset(reference);
    final blob = web.Blob(
      <web.BlobPart>[bytes.toJS].toJS,
      web.BlobPropertyBag(
        type: reference.contentType ?? 'application/octet-stream',
      ),
    );
    final url = web.URL.createObjectURL(blob);
    _objectUrls[reference.value] = url;
    return Uri.parse(url);
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
    if (_api != null && _assetsFolderId.isNotEmpty) {
      for (final file in await _driveAssets()) {
        await _api!.deleteFile(file.id);
      }
      if (_stateFile != null) await _api!.deleteFile(_stateFile!.id);
      _stateFile = null;
    }
    web.window.localStorage.removeItem(_apiKeysStorageKey);
    web.window.localStorage.removeItem(_preferencesStorageKey);
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
    final data = _lastData ?? _localData();
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

  StoredData _localData() {
    final keys = _decodeMap(
      web.window.localStorage.getItem(_apiKeysStorageKey),
    );
    final preferences = _decodeMap(
      web.window.localStorage.getItem(_preferencesStorageKey),
    );
    return StoredData(
      apiKey: keys['bfl']?.toString() ?? '',
      apiKeys: keys.map((key, value) => MapEntry(key, value?.toString() ?? ''))
        ..removeWhere((key, value) => value.isEmpty),
      preferences: AppPreferences.fromJson(preferences),
    );
  }

  void _saveLocal(StoredData data) {
    final keys = <String, String>{
      if (data.apiKey.isNotEmpty) 'bfl': data.apiKey,
      ...data.apiKeys,
    }..removeWhere((key, value) => value.trim().isEmpty);
    web.window.localStorage.setItem(_apiKeysStorageKey, jsonEncode(keys));
    _savePreferences(data.preferences);
  }

  void _savePreferences(AppPreferences preferences) => web.window.localStorage
      .setItem(_preferencesStorageKey, jsonEncode(preferences.toJson()));

  Map<String, Object?> _decodeMap(String? source) {
    if (source == null || source.isEmpty) return <String, Object?>{};
    try {
      final value = jsonDecode(source);
      if (value is Map<Object?, Object?>) {
        return value.map((key, child) => MapEntry(key.toString(), child));
      }
    } on FormatException {
      // Corrupt browser-local settings fall back to defaults. Cloud data is
      // never discarded by this path.
    }
    return <String, Object?>{};
  }

  bool _portableContentChanged(StoredData previous, StoredData next) {
    final before = googleDrivePortableData(previous).toJson();
    final after = googleDrivePortableData(next).toJson();
    before['preferences'] = const <String, Object?>{};
    after['preferences'] = const <String, Object?>{};
    return jsonEncode(before) != jsonEncode(after);
  }

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
      add(generation.config.source);
      for (final frame
          in generation.config.keyframes ?? const <KeyframeLabel>[]) {
        add(frame.source);
      }
      for (final media
          in generation.config.references ?? const <MediaReferenceLabel>[]) {
        add(media.source);
      }
    }
    for (final reference in references) {
      add(reference.asset);
    }
    return retained;
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
