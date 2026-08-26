import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:clawnsole/core/asset_extensions.dart';
import 'package:clawnsole/core/bfl_api.dart';
import 'package:clawnsole/core/durable_data_store.dart';
import 'package:clawnsole/core/encrypted_file_secure_value_store.dart';
import 'package:clawnsole/core/generation_status.dart';
import 'package:clawnsole/core/google_drive.dart';
import 'package:clawnsole/core/google_drive_asset_presenter_io.dart';
import 'package:clawnsole/core/google_drive_store.dart';
import 'package:clawnsole/core/hybrid_data_store.dart';
import 'package:clawnsole/core/models.dart';
import 'package:clawnsole/core/pricing.dart';
import 'package:clawnsole/core/provider_api.dart';
import 'package:clawnsole/core/provider_catalog.dart';
import 'package:clawnsole/core/provider_manifest.dart';
import 'package:clawnsole/core/reference_video_normalizer.dart';
import 'package:clawnsole/core/settings_vault.dart';
import 'package:clawnsole/core/settings_vault_data_store.dart';
import 'package:clawnsole/core/video_cache.dart';

Future<void> main(List<String> arguments) async {
  final config = CompanionConfig.from(arguments, Platform.environment);
  final bootstrap = await CompanionBootstrap.load(
    Platform.environment,
    stdin,
    requireInput: config.secureBootstrap,
  );
  final deviceKey =
      bootstrap.deviceKey ??
      (config.secureBootstrap
          ? null
          : await DevelopmentDeviceKey.loadOrCreate(
              File('${config.dataFile}.development-key'),
            ));
  final localStore = CompanionStore(File(config.dataFile));
  // The media cache sits beside the companion's data file so it shares the
  // library's lifetime and disk, and survives companion restarts.
  final videoCache = VideoCache(
    directory: () async => Directory(
      '${File(config.dataFile).parent.path}${Platform.pathSeparator}video-cache',
    ),
  );
  final thumbnailCache = VideoCache(
    directory: () async => Directory(
      '${File(config.dataFile).parent.path}${Platform.pathSeparator}thumbnail-cache',
    ),
  );
  final hybrid = HybridDataStore(
    local: localStore,
    drive: GoogleDriveStore(
      presenter: IoGoogleDriveAssetPresenter(
        videoCache: videoCache,
        thumbnailCache: thumbnailCache,
      ),
    ),
  );
  final secureStore = deviceKey == null
      ? null
      : EncryptedFileSecureValueStore(
          file: File('${config.dataFile}.secure'),
          deviceKey: deviceKey,
        );
  final vault = secureStore == null
      ? null
      : SettingsVaultDataStore(delegate: hybrid, secureStore: secureStore);
  final store = CompanionHybridStore(hybrid, vault: vault);
  try {
    final cache = (await store.read()).providerCatalogCache;
    if (cache != null) {
      installProviderCatalog(ProviderCatalogBundle.fromCache(cache).providers);
    }
  } on Object {
    // An invalid cache must not stop the companion. Its bundled definitions
    // remain the complete offline fallback until the renderer supplies a new
    // validated catalog.
  }
  final server = await HttpServer.bind(
    InternetAddress.loopbackIPv4,
    config.port,
  );
  final app = CompanionApp.hybrid(
    store: store,
    api: BflApi(),
    fallbackApiKeys: <String, String>{
      'bfl': Platform.environment['BFL_API_KEY']?.trim() ?? '',
      'ltx': Platform.environment['LTX_API_KEY']?.trim() ?? '',
      'artcraft': Platform.environment['ARTCRAFT_KEY']?.trim() ?? '',
      'atlas': Platform.environment['ATLAS_CLOUD_KEY']?.trim() ?? '',
      'runway':
          Platform.environment['RUNWAY_KEY']?.trim() ??
          Platform.environment['RUNWAYML_API_SECRET']?.trim() ??
          '',
    },
    webRoot: config.webRoot == null ? null : Directory(config.webRoot!),
    requestToken: bootstrap.requestToken,
    allowedOrigin: 'http://127.0.0.1:${server.port}',
    videoCache: videoCache,
    thumbnailCache: thumbnailCache,
    referenceVideoNormalizer: ReferenceVideoNormalizer(
      backend: ProcessReferenceVideoToolBackend(
        ffmpegPath: config.mediaToolsDir == null
            ? 'ffmpeg'
            : '${config.mediaToolsDir}${Platform.pathSeparator}ffmpeg',
        ffprobePath: config.mediaToolsDir == null
            ? 'ffprobe'
            : '${config.mediaToolsDir}${Platform.pathSeparator}ffprobe',
      ),
      cacheDirectory: () async => Directory(
        '${File(config.dataFile).parent.path}'
        '${Platform.pathSeparator}reference-video-fixes',
      ),
    ),
  );
  stdout.writeln(
    'Clawnsole companion is listening on http://127.0.0.1:${server.port}',
  );
  stdout.writeln('Local data: ${config.dataFile}');
  if (config.webRoot != null) stdout.writeln('Web root: ${config.webRoot}');
  stdout.writeln('Press Ctrl+C to stop.');
  await for (final request in server) {
    unawaited(app.handle(request));
  }
}

class CompanionBootstrap {
  const CompanionBootstrap({required this.requestToken, this.deviceKey});

  final String requestToken;
  final String? deviceKey;

  static Future<CompanionBootstrap> load(
    Map<String, String> environment,
    Stream<List<int>> input, {
    bool requireInput = false,
  }) async {
    final developmentToken =
        environment['CLAWNSOLE_COMPANION_TOKEN']?.trim() ?? '';
    if (developmentToken.isNotEmpty) {
      _validateBootstrapKey(developmentToken, 'request token');
      return CompanionBootstrap(requestToken: developmentToken);
    }
    if (!requireInput) return const CompanionBootstrap(requestToken: '');
    final bytes = <int>[];
    await for (final chunk in input) {
      bytes.addAll(chunk);
      if (bytes.length > 8192) {
        throw StateError('The companion bootstrap data is invalid.');
      }
      if (chunk.contains(10)) break;
    }
    final newline = bytes.indexOf(10);
    final lineBytes = newline < 0 ? bytes : bytes.sublist(0, newline);
    return CompanionBootstrap.fromJsonLine(utf8.decode(lineBytes));
  }

  factory CompanionBootstrap.fromJsonLine(String source) {
    try {
      final decoded = jsonDecode(source);
      if (decoded is! Map<Object?, Object?> ||
          decoded.length != 2 ||
          decoded['deviceKey'] is! String ||
          decoded['requestToken'] is! String) {
        throw const FormatException();
      }
      final deviceKey = decoded['deviceKey']! as String;
      final requestToken = decoded['requestToken']! as String;
      _validateBootstrapKey(deviceKey, 'device key');
      _validateBootstrapKey(requestToken, 'request token');
      return CompanionBootstrap(
        requestToken: requestToken,
        deviceKey: deviceKey,
      );
    } on Object {
      throw StateError('The companion bootstrap data is invalid.');
    }
  }
}

void _validateBootstrapKey(String value, String name) {
  Uint8List bytes;
  try {
    bytes = Uint8List.fromList(base64Url.decode(base64Url.normalize(value)));
  } on FormatException {
    throw StateError('The companion $name is invalid.');
  }
  if (bytes.length != 32 ||
      base64UrlEncode(bytes).replaceAll('=', '') != value) {
    throw StateError('The companion $name is invalid.');
  }
}

/// Development-only wrapping key for the internal companion harness.
///
/// Packaged Electron never uses this path: it supplies a safeStorage-protected
/// key over stdin. This file keeps `start_web` useful without putting provider
/// credentials back into clawnsole.json.
class DevelopmentDeviceKey {
  static Future<String> loadOrCreate(File file) async {
    if (await file.exists()) {
      final value = (await file.readAsString()).trim();
      _validateBootstrapKey(value, 'development device key');
      return value;
    }
    final random = Random.secure();
    final value = base64UrlEncode(
      List<int>.generate(32, (_) => random.nextInt(256)),
    ).replaceAll('=', '');
    await file.parent.create(recursive: true);
    final temporary = File('${file.path}.$pid.tmp');
    try {
      await temporary.writeAsString('$value\n', flush: true);
      if (!Platform.isWindows) {
        final result = await Process.run('chmod', <String>[
          '600',
          temporary.path,
        ]);
        if (result.exitCode != 0) {
          throw StateError(
            'The development secure-storage key could not be protected.',
          );
        }
      }
      await temporary.rename(file.path);
      return value;
    } finally {
      if (await temporary.exists()) await temporary.delete();
    }
  }
}

class CompanionConfig {
  const CompanionConfig({
    required this.port,
    required this.dataFile,
    this.webRoot,
    this.mediaToolsDir,
    this.secureBootstrap = false,
  });

  final int port;
  final String dataFile;
  final String? webRoot;
  final String? mediaToolsDir;
  final bool secureBootstrap;

  factory CompanionConfig.from(
    List<String> arguments,
    Map<String, String> environment,
  ) {
    var port = int.tryParse(environment['CLAWNSOLE_PROXY_PORT'] ?? '') ?? 8787;
    var dataFile = environment['CLAWNSOLE_FLUTTER_DATA_FILE']?.trim() ?? '';
    var webRoot = environment['CLAWNSOLE_WEB_ROOT']?.trim() ?? '';
    var mediaToolsDir = environment['CLAWNSOLE_MEDIA_TOOLS_DIR']?.trim() ?? '';
    var secureBootstrap = false;
    for (var index = 0; index < arguments.length; index += 1) {
      if (arguments[index] == '--port' && index + 1 < arguments.length) {
        port = int.parse(arguments[++index]);
      } else if (arguments[index] == '--data-file' &&
          index + 1 < arguments.length) {
        dataFile = arguments[++index];
      } else if (arguments[index] == '--web-root' &&
          index + 1 < arguments.length) {
        webRoot = arguments[++index];
      } else if (arguments[index] == '--secure-bootstrap') {
        secureBootstrap = true;
      } else if (arguments[index] == '--media-tools-dir' &&
          index + 1 < arguments.length) {
        mediaToolsDir = arguments[++index];
      }
    }
    if (dataFile.isEmpty) {
      dataFile =
          '${Directory.current.path}${Platform.pathSeparator}.clawnsole'
          '${Platform.pathSeparator}clawnsole-flutter.json';
    }
    return CompanionConfig(
      port: port,
      dataFile: File(dataFile).absolute.path,
      webRoot: webRoot.isEmpty ? null : Directory(webRoot).absolute.path,
      mediaToolsDir: mediaToolsDir.isEmpty
          ? null
          : Directory(mediaToolsDir).absolute.path,
      secureBootstrap: secureBootstrap,
    );
  }
}

class CompanionStore implements DurableDataStore {
  CompanionStore(this.file);

  final File file;
  Future<void> _queue = Future<void>.value();

  Directory get assets =>
      Directory('${file.parent.path}${Platform.pathSeparator}assets');

  Future<bool> exists() => file.exists();

  String _assetId() {
    final random = Random.secure();
    final timestamp = DateTime.now().microsecondsSinceEpoch.toRadixString(16);
    final suffix = List<int>.generate(
      16,
      (_) => random.nextInt(256),
    ).map((value) => value.toRadixString(16).padLeft(2, '0')).join();
    return '$timestamp-$suffix';
  }

  File assetFile(String id, [String extension = '.asset']) {
    if (!RegExp(r'^[a-f0-9-]{16,80}$').hasMatch(id)) {
      throw StateError('The local asset id is invalid.');
    }
    return File('${assets.path}${Platform.pathSeparator}$id$extension');
  }

  /// Mirrors the native store's resolution order: the typed name derived from
  /// the reference, then the legacy `<id>.asset` name, then any file whose
  /// basename-without-extension equals the id. The scan only runs on a miss.
  Future<File> resolveAssetFile(AssetReference reference) async {
    final extension = retainedAssetExtension(
      reference.contentType,
      reference.label,
    );
    final preferred = assetFile(reference.value, extension);
    if (await preferred.exists()) return preferred;
    final legacy = assetFile(reference.value);
    if (await legacy.exists()) return legacy;
    final match = await _assetFileByStem(reference.value);
    return match ?? legacy;
  }

  Future<File?> _assetFileByStem(String id) async {
    if (!await assets.exists()) return null;
    await for (final entry in assets.list()) {
      if (entry is! File) continue;
      final name = entry.uri.pathSegments.last;
      final dot = name.lastIndexOf('.');
      final stem = dot > 0 ? name.substring(0, dot) : name;
      if (stem == id) return entry;
    }
    return null;
  }

  @override
  Future<AssetReference> writeAsset(
    Uint8List bytes, {
    required String label,
    required String contentType,
    LibraryStorage storage = LibraryStorage.local,
  }) async {
    final id = _assetId();
    await assets.create(recursive: true);
    await assetFile(
      id,
      retainedAssetExtension(contentType, label),
    ).writeAsBytes(bytes, flush: true);
    return AssetReference(
      kind: 'local',
      value: id,
      label: label,
      contentType: contentType.split(';').first,
      bytes: bytes.length,
    );
  }

  @override
  Future<AssetReference?> persistSource(
    String source, {
    required String label,
    AssetReference? retained,
    LibraryStorage storage = LibraryStorage.local,
  }) async {
    if (retained?.kind == 'local') {
      final existing = await resolveAssetFile(retained!);
      if (await existing.exists()) {
        return AssetReference(
          kind: 'local',
          value: retained.value,
          label: label,
          contentType: retained.contentType,
          bytes: await existing.length(),
        );
      }
    }
    if (source.startsWith('data:')) {
      final comma = source.indexOf(',');
      if (comma < 0) throw StateError('A selected local asset is malformed.');
      final metadata = source.substring(5, comma).split(';');
      final contentType = metadata.firstOrNull?.isNotEmpty == true
          ? metadata.first
          : 'application/octet-stream';
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

  Set<String> _references(
    List<Generation> generations,
    List<SavedReference> savedReferences,
  ) {
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
    return retained;
  }

  @override
  Future<void> pruneAssets(
    List<Generation> generations, [
    List<SavedReference> savedReferences = const <SavedReference>[],
  ]) async {
    if (!await assets.exists()) return;
    final retained = _references(generations, savedReferences);
    await for (final entry in assets.list()) {
      if (entry is! File) continue;
      final name = entry.uri.pathSegments.last;
      final dot = name.lastIndexOf('.');
      final id = dot > 0 ? name.substring(0, dot) : '';
      if (!retained.contains(id)) await entry.delete();
    }
  }

  Future<void> clearAssets() async {
    if (await assets.exists()) await assets.delete(recursive: true);
  }

  Future<StoredData> _readRaw() async {
    if (!await file.exists()) return const StoredData();
    try {
      return StoredData.decode(await file.readAsString());
    } on FormatException {
      throw StateError(
        'Clawnsole could not read ${file.path}. The JSON file is malformed.',
      );
    }
  }

  Future<void> _writeRaw(StoredData data) async {
    await file.parent.create(recursive: true);
    final temporary = File(
      '${file.path}.$pid.${DateTime.now().microsecondsSinceEpoch}.tmp',
    );
    await temporary.writeAsString(data.encode(), flush: true);
    if (await file.exists()) await file.delete();
    await temporary.rename(file.path);
  }

  @override
  Future<StoredData> read() async {
    await _queue;
    return _readRaw();
  }

  Future<T> mutate<T>(
    FutureOr<StoreChange<T>> Function(StoredData data) callback,
  ) {
    final operation = _queue.then((_) async {
      final current = await _readRaw();
      final change = await callback(current);
      await _writeRaw(change.data);
      return change.result;
    });
    _queue = operation.then<void>((_) {}, onError: (_) {});
    return operation;
  }

  Future<void> replace(StoredData replacement) =>
      mutate<void>((_) => StoreChange<void>(replacement, null));

  @override
  Future<void> write(StoredData data) => replace(data);

  @override
  Future<void> delete() {
    final operation = _queue.then((_) async {
      if (await file.exists()) await file.delete();
      await clearAssets();
    });
    _queue = operation.then<void>((_) {}, onError: (_) {});
    return operation;
  }

  @override
  Future<StorageStats> stats(int records) async {
    await _queue;
    var assetBytes = 0;
    var assetCount = 0;
    if (await assets.exists()) {
      await for (final entry in assets.list()) {
        if (entry is! File) continue;
        assetBytes += await entry.length();
        assetCount += 1;
      }
    }
    if (!await file.exists()) {
      return StorageStats(
        path: file.path,
        bytes: 0,
        records: records,
        assetBytes: assetBytes,
        assets: assetCount,
      );
    }
    final value = await file.stat();
    return StorageStats(
      path: file.path,
      bytes: value.size,
      records: records,
      assetBytes: assetBytes,
      assets: assetCount,
      lastUpdated: value.modified,
    );
  }

  @override
  Future<Uint8List> readAsset(AssetReference reference) async {
    if (reference.kind != 'local') {
      throw StateError('The asset is not stored by the local companion.');
    }
    final file = await resolveAssetFile(reference);
    if (!await file.exists()) {
      stderr.writeln(
        'Missing local asset file ${file.path} '
        '(id ${reference.value}, contentType ${reference.contentType}).',
      );
      throw StateError(missingLocalAssetMessage(reference.contentType));
    }
    return file.readAsBytes();
  }

  @override
  Future<Uri> assetUri(AssetReference reference) async =>
      (await resolveAssetFile(reference)).uri;
}

class StoreChange<T> {
  const StoreChange(this.data, this.result);

  final StoredData data;
  final T result;
}

class CompanionHybridStore {
  CompanionHybridStore(this.hybrid, {this.vault});

  final HybridDataStore hybrid;
  final SettingsVaultDataStore? vault;
  Future<void> _queue = Future<void>.value();

  DurableDataStore get _dataStore => vault ?? hybrid;

  GoogleDriveConnection get connection => hybrid.connection;

  Future<StoredData> read() async {
    await _queue;
    return _dataStore.read();
  }

  Future<T> mutate<T>(
    FutureOr<StoreChange<T>> Function(StoredData data) callback,
  ) {
    final operation = _queue.then((_) async {
      final current = await _dataStore.read();
      final change = await callback(current);
      await _dataStore.write(change.data);
      return change.result;
    });
    _queue = operation.then<void>((_) {}, onError: (_) {});
    return operation;
  }

  Future<void> replace(StoredData data) =>
      mutate<void>((_) => StoreChange<void>(data, null));

  Future<void> delete() => _dataStore.delete();

  Future<AssetReference> writeAsset(
    Uint8List bytes, {
    required String label,
    required String contentType,
    LibraryStorage storage = LibraryStorage.local,
  }) => _dataStore.writeAsset(
    bytes,
    label: label,
    contentType: contentType,
    storage: storage,
  );

  Future<AssetReference?> persistSource(
    String source, {
    required String label,
    AssetReference? retained,
    LibraryStorage storage = LibraryStorage.local,
  }) => _dataStore.persistSource(
    source,
    label: label,
    retained: retained,
    storage: storage,
  );

  Future<Uint8List> readAsset(AssetReference reference) =>
      _dataStore.readAsset(reference);

  Future<GoogleDriveByteStream> readDriveAssetStream(
    AssetReference reference,
  ) => hybrid.readDriveAssetStream(reference);

  Future<Uint8List> readDriveAssetRange(
    AssetReference reference,
    int start,
    int end,
  ) => hybrid.readDriveAssetRange(reference, start, end);

  Future<void> pruneAssets(
    List<Generation> generations,
    List<SavedReference> references,
  ) => _dataStore.pruneAssets(generations, references);

  Future<StorageStats> stats(int records) => _dataStore.stats(records);

  Future<StoredData> connectDrive(String accessToken, String folderName) async {
    // Migrate any legacy plaintext credentials before HybridDataStore copies
    // the portable library into Drive.
    await _dataStore.read();
    await hybrid.connect(accessToken, folderName);
    await vault?.connectRemote(accessToken, connection.folderId);
    return _dataStore.read();
  }

  Future<StoredData> disconnectDrive() async {
    await vault?.disconnectRemote();
    await hybrid.disconnect();
    return _dataStore.read();
  }

  Future<StoredData> refreshDrive(String accessToken) async {
    await hybrid.connect(accessToken, hybrid.connection.folderName);
    await vault?.connectRemote(accessToken, connection.folderId);
    return _dataStore.read();
  }

  Future<GoogleDriveCopyCounts> copyLocalToDrive({
    Set<String> generationIds = const <String>{},
    Set<String> referenceIds = const <String>{},
  }) => hybrid.copyLocalToDrive(
    generationIds: generationIds,
    referenceIds: referenceIds,
  );

  Future<GoogleDriveCopyCounts> moveLocalToDrive() => hybrid.moveLocalToDrive();
}

/// One parsed `Range: bytes=a-b` header before it is resolved against a
/// concrete size. Either edge may be absent (`bytes=a-` and `bytes=-n`).
class _RawByteRange {
  const _RawByteRange(this.rawStart, this.rawEnd);

  final int? rawStart;
  final int? rawEnd;
}

List<String> _cleanLibraryTags(Iterable<Object?> input) {
  final tags = <String>[];
  final seen = <String>{};
  for (final value in input) {
    final clean = value
        .toString()
        .trim()
        .replaceFirst(RegExp(r'^#+'), '')
        .trim();
    final key = clean.toLowerCase();
    if (clean.isEmpty || clean.length > 28 || seen.contains(key)) continue;
    seen.add(key);
    tags.add(clean);
    if (tags.length == 12) break;
  }
  return tags;
}

class CompanionApp {
  factory CompanionApp({
    required CompanionStore store,
    required BflApi api,
    ProviderApiRouter? providerRouter,
    Map<String, String> fallbackApiKeys = const <String, String>{},
    Directory? webRoot,
    String requestToken = '',
    String allowedOrigin = '',
    VideoCache? videoCache,
    VideoCache? thumbnailCache,
    ReferenceVideoNormalizationService referenceVideoNormalizer =
        const DisabledReferenceVideoNormalizationService(),
  }) => CompanionApp.hybrid(
    store: CompanionHybridStore(HybridDataStore(local: store)),
    api: api,
    providerRouter: providerRouter,
    fallbackApiKeys: fallbackApiKeys,
    webRoot: webRoot,
    requestToken: requestToken,
    allowedOrigin: allowedOrigin,
    videoCache: videoCache,
    thumbnailCache: thumbnailCache,
    referenceVideoNormalizer: referenceVideoNormalizer,
  );

  CompanionApp.hybrid({
    required CompanionHybridStore store,
    required BflApi api,
    ProviderApiRouter? providerRouter,
    Map<String, String> fallbackApiKeys = const <String, String>{},
    Directory? webRoot,
    String requestToken = '',
    String allowedOrigin = '',
    VideoCache? videoCache,
    VideoCache? thumbnailCache,
    ReferenceVideoNormalizationService referenceVideoNormalizer =
        const DisabledReferenceVideoNormalizationService(),
  }) : _store = store,
       _providers = providerRouter ?? ProviderApiRouter(bfl: api),
       _fallbackApiKeys = fallbackApiKeys,
       _webRoot = webRoot,
       _requestToken = requestToken,
       _allowedOrigin = allowedOrigin,
       _videoCache = videoCache,
       _thumbnailCache = thumbnailCache,
       _referenceVideoNormalizer = referenceVideoNormalizer;

  final CompanionHybridStore _store;
  final ProviderApiRouter _providers;
  final Map<String, String> _fallbackApiKeys;
  final Directory? _webRoot;
  final String _requestToken;
  final String _allowedOrigin;
  final VideoCache? _videoCache;
  final VideoCache? _thumbnailCache;
  final ReferenceVideoNormalizationService _referenceVideoNormalizer;
  ReferenceVideoEditingService? get _referenceVideoEditingService =>
      _referenceVideoNormalizer is ReferenceVideoEditingService
      ? _referenceVideoNormalizer as ReferenceVideoEditingService
      : null;
  final Map<String, Future<File>> _driveVideoFills = <String, Future<File>>{};

  Future<void> handle(HttpRequest request) async {
    final origin = request.headers.value('origin');
    if (!_allowOrigin(origin)) {
      return _json(request.response, 403, <String, Object?>{
        'error': 'The Clawnsole companion only accepts local browser origins.',
      });
    }
    _cors(request.response, origin);
    if (request.method == 'OPTIONS') {
      if (!_allowSession(request)) {
        return _json(request.response, 403, <String, Object?>{
          'error': 'The Clawnsole companion session is invalid.',
        });
      }
      request.response.statusCode = HttpStatus.noContent;
      return request.response.close();
    }
    try {
      final path = request.uri.path;
      if (request.method == 'GET' && path == '/health') {
        return await _json(request.response, 200, <String, Object?>{
          'ok': true,
        });
      }
      if (!_allowSession(request)) {
        return await _json(request.response, 403, <String, Object?>{
          'error': 'The Clawnsole companion session is invalid.',
        });
      }
      if (request.method == 'POST' && path.startsWith('/vault/')) {
        return await _vaultAction(request, path.substring('/vault/'.length));
      }
      if (request.method == 'GET' && path == '/state') {
        return await _json(request.response, 200, await _snapshotPayload());
      }
      if (request.method == 'GET' && path == '/provider-catalog-cache') {
        return await _json(request.response, 200, <String, Object?>{
          'cache': (await _store.read()).providerCatalogCache,
        });
      }
      if (request.method == 'PUT' && path == '/provider-catalog-cache') {
        final body = await _bodyMap(request);
        final raw = body['cache'];
        if (raw is! Map<Object?, Object?>) {
          throw const FormatException('The provider catalog cache is invalid.');
        }
        final cache = raw.map((key, value) => MapEntry(key.toString(), value));
        final bundle = ProviderCatalogBundle.fromCache(cache);
        installProviderCatalog(bundle.providers);
        await _store.mutate<void>(
          (data) => StoreChange<void>(
            data.copyWith(providerCatalogCache: cache),
            null,
          ),
        );
        return await _json(request.response, 200, <String, Object?>{
          'ok': true,
        });
      }
      if (request.method == 'PATCH' && path == '/state') {
        final body = await _bodyMap(request);
        await _stateAction(body['action']?.toString() ?? '', body['value']);
        return await _json(request.response, 200, await _snapshotPayload());
      }
      if (request.method == 'POST' && path == '/drive/connect') {
        final body = await _bodyMap(request);
        final accessToken = body['accessToken']?.toString() ?? '';
        final folderName = body['folderName']?.toString() ?? '';
        await _store.connectDrive(accessToken, folderName);
        return await _json(request.response, 200, await _snapshotPayload());
      }
      if (request.method == 'POST' && path == '/drive/disconnect') {
        await _store.disconnectDrive();
        return await _json(request.response, 200, await _snapshotPayload());
      }
      if (request.method == 'POST' && path == '/drive/refresh') {
        final body = await _bodyMap(request);
        await _store.refreshDrive(body['accessToken']?.toString() ?? '');
        return await _json(request.response, 200, await _snapshotPayload());
      }
      if (request.method == 'POST' && path == '/drive/copy') {
        final body = await _bodyMap(request);
        final copied = await _store.copyLocalToDrive(
          generationIds:
              (body['generationIds'] as List<Object?>? ?? const <Object?>[])
                  .whereType<String>()
                  .toSet(),
          referenceIds:
              (body['referenceIds'] as List<Object?>? ?? const <Object?>[])
                  .whereType<String>()
                  .toSet(),
        );
        return await _json(request.response, 200, <String, Object?>{
          'snapshot': await _snapshotPayload(),
          'generations': copied.generations,
          'references': copied.references,
        });
      }
      if (request.method == 'POST' && path == '/drive/migrate') {
        final moved = await _store.moveLocalToDrive();
        return await _json(request.response, 200, <String, Object?>{
          'snapshot': await _snapshotPayload(),
          'generations': moved.generations,
          'references': moved.references,
        });
      }
      if (request.method == 'POST' &&
          (path == '/account' || path == '/credits')) {
        final body = await _bodyMap(request);
        final provider = body['provider']?.toString() ?? 'bfl';
        final saved = _activeKey(await _store.read(), provider);
        final candidate = body['apiKey']?.toString().trim();
        final key = candidate?.isNotEmpty == true ? candidate! : saved;
        if (key.isEmpty) throw StateError('An API key is required.');
        final account = await _providers.verify(provider, key);
        return await _json(
          request.response,
          200,
          path == '/credits'
              ? <String, Object?>{'credits': account.balance ?? 0}
              : account.toJson(),
        );
      }
      if (request.method == 'GET' && path == '/providers/models') {
        final provider = request.uri.queryParameters['provider'] ?? 'bfl';
        final data = await _store.read();
        final models = await _providers.listModels(
          provider,
          _activeKey(data, provider),
        );
        return await _json(
          request.response,
          200,
          models.map((model) => model.toJson()).toList(),
        );
      }
      if (request.method == 'POST' && path == '/providers/quote') {
        final body = await _bodyMap(request);
        final provider = body['provider']?.toString() ?? '';
        final model = body['model']?.toString() ?? '';
        final input = (body['input'] as Map<Object?, Object?>? ?? const {}).map(
          (key, value) => MapEntry(key.toString(), value),
        );
        final estimate = await _providers.quote(provider, model, input);
        return await _json(request.response, 200, <String, Object?>{
          'available': estimate != null,
          if (estimate != null) ...<String, Object?>{
            'minimumUsd': estimate.minimumUsd,
            'maximumUsd': estimate.maximumUsd,
            'basis': estimate.basis,
            if (estimate.providerUnitsMinimum != null)
              'providerUnitsMinimum': estimate.providerUnitsMinimum,
            if (estimate.providerUnitsMaximum != null)
              'providerUnitsMaximum': estimate.providerUnitsMaximum,
            if (estimate.providerUnitLabel != null)
              'providerUnitLabel': estimate.providerUnitLabel,
          },
        });
      }
      if (request.method == 'POST' && path == '/generations') {
        final generation = await _submit(await _bodyMap(request));
        return await _json(request.response, 201, <String, Object?>{
          'generation': generation.toJson(),
        });
      }
      if (request.method == 'POST' && path == '/generations/status') {
        final generation = await _poll(await _bodyMap(request));
        return await _json(request.response, 200, <String, Object?>{
          'generation': generation.toJson(),
        });
      }
      if (request.method == 'DELETE' && path == '/generations') {
        final localId = request.uri.queryParameters['id'];
        if (localId == null || localId.isEmpty) {
          throw const ProviderException(
            'A generation id is required.',
            status: 400,
          );
        }
        await _store.mutate<void>((current) {
          final next = current.copyWith(
            generations: current.generations
                .where((item) => item.localId != localId)
                .toList(),
          );
          return StoreChange<void>(next, null);
        });
        final data = await _store.read();
        await _store.pruneAssets(data.generations, data.savedReferences);
        return await _json(request.response, 200, await _snapshotPayload());
      }
      if (request.method == 'GET' && path == '/assets') {
        return await _asset(request);
      }
      if (request.method == 'GET' && path == '/asset-cache') {
        return await _cachedAsset(request);
      }
      if (request.method == 'GET' && path == '/media') {
        return await _media(request);
      }
      if (request.method == 'GET' && path == '/video-cache') {
        final cache = await _syncedVideoCache(await _store.read());
        return await _json(request.response, 200, <String, Object?>{
          'usedBytes': cache == null ? 0 : await cache.usedBytes(),
          'capBytes': cache?.maxBytes ?? 0,
        });
      }
      if (request.method == 'DELETE' && path == '/video-cache') {
        await _videoCache?.clear();
        return await _json(request.response, 200, <String, Object?>{
          'ok': true,
        });
      }
      if (request.method == 'GET' && path == '/thumbnail-cache') {
        final cache = await _syncedThumbnailCache(await _store.read());
        return await _json(request.response, 200, <String, Object?>{
          'usedBytes': cache == null ? 0 : await cache.usedBytes(),
          'capBytes': cache?.maxBytes ?? 0,
        });
      }
      if (request.method == 'DELETE' && path == '/thumbnail-cache') {
        await _thumbnailCache?.clear();
        return await _json(request.response, 200, <String, Object?>{
          'ok': true,
        });
      }
      if (request.method == 'POST' && path == '/video-cache/prefetch') {
        return await _prefetchVideo(request);
      }
      if ((request.method == 'GET' || request.method == 'HEAD') &&
          _webRoot != null) {
        return await _staticFile(request);
      }
      return await _json(request.response, 404, <String, Object?>{
        'error': 'The requested companion route does not exist.',
      });
    } on ProviderException catch (error) {
      return _json(request.response, error.status ?? 500, <String, Object?>{
        'error': error.message,
        if (error.details != null) 'details': error.details,
      });
    } on Object catch (error, stack) {
      stderr.writeln(error);
      stderr.writeln(stack);
      return _json(request.response, 500, <String, Object?>{
        'error': error.toString().replaceFirst('Bad state: ', ''),
      });
    }
  }

  bool _allowOrigin(String? origin) {
    if (origin == null || origin.isEmpty) return true;
    if (_allowedOrigin.isNotEmpty) return origin == _allowedOrigin;
    final uri = Uri.tryParse(origin);
    return uri != null &&
        (uri.scheme == 'http' || uri.scheme == 'https') &&
        (uri.host == 'localhost' ||
            uri.host == '127.0.0.1' ||
            uri.host == '::1');
  }

  bool _allowSession(HttpRequest request) {
    if (_requestToken.isEmpty) return true;
    final candidate = request.headers.value('X-Clawnsole-Session') ?? '';
    if (candidate.length != _requestToken.length) return false;
    var difference = 0;
    for (var index = 0; index < _requestToken.length; index += 1) {
      difference |=
          candidate.codeUnitAt(index) ^ _requestToken.codeUnitAt(index);
    }
    return difference == 0;
  }

  void _cors(HttpResponse response, String? origin) {
    if (origin != null) {
      response.headers.set(HttpHeaders.accessControlAllowOriginHeader, origin);
      response.headers.set(HttpHeaders.varyHeader, 'Origin');
    }
    response.headers.set(
      HttpHeaders.accessControlAllowMethodsHeader,
      'GET, POST, PUT, PATCH, DELETE, OPTIONS',
    );
    response.headers.set(
      HttpHeaders.accessControlAllowHeadersHeader,
      'Content-Type, Range, X-Clawnsole-Session',
    );
    response.headers.set(HttpHeaders.cacheControlHeader, 'private, no-store');
  }

  Future<Map<String, Object?>> _bodyMap(HttpRequest request) async {
    final source = await utf8.decoder.bind(request).join();
    if (source.isEmpty) return <String, Object?>{};
    final decoded = jsonDecode(source);
    if (decoded is! Map<Object?, Object?>) {
      throw const ProviderException('A JSON object is required.', status: 400);
    }
    return decoded.map((key, value) => MapEntry(key.toString(), value));
  }

  Future<void> _vaultAction(HttpRequest request, String action) async {
    final vault = _store.vault;
    if (vault == null) {
      return _json(request.response, 503, <String, Object?>{
        'ok': false,
        'state': SettingsVaultState.unavailable.name,
        'error': 'Secure settings sync is unavailable in this session.',
      });
    }
    const valueActions = <String>{
      'setup',
      'unlock',
      'recover',
      'changePassphrase',
    };
    const emptyActions = <String>{'forget', 'sync'};
    if (!valueActions.contains(action) && !emptyActions.contains(action)) {
      return _json(request.response, 404, <String, Object?>{
        'ok': false,
        'state': vault.settingsVaultStatus.state.name,
        'error': 'The settings-vault action is invalid.',
      });
    }
    try {
      final body = await _bodyMap(request);
      final rawValue = body['value'];
      if (rawValue is! String || body.length != 1) {
        throw const FormatException();
      }
      final valueBytes = utf8.encode(rawValue).length;
      if ((valueActions.contains(action) &&
              (valueBytes == 0 || valueBytes > 4096)) ||
          (emptyActions.contains(action) && valueBytes != 0)) {
        throw const FormatException();
      }

      String? recoveryCode;
      switch (action) {
        case 'setup':
          recoveryCode = await vault.setup(rawValue);
        case 'unlock':
          await vault.unlock(rawValue);
        case 'recover':
          await vault.recover(rawValue);
        case 'changePassphrase':
          await vault.changePassphrase(rawValue);
        case 'forget':
          await vault.forgetCachedUnlock();
        case 'sync':
          await vault.sync();
      }
      final status = vault.settingsVaultStatus;
      return await _json(request.response, 200, <String, Object?>{
        'ok': true,
        'state': status.state.name,
        if (status.message.isNotEmpty) 'message': status.message,
        if (status.lastSyncedAt != null)
          'syncedAt': status.lastSyncedAt!.toUtc().toIso8601String(),
        if (action == 'setup' && recoveryCode != null)
          'recoveryCode': recoveryCode,
      });
    } on Object catch (error) {
      final status = vault.settingsVaultStatus;
      return _json(
        request.response,
        _vaultErrorStatus(error),
        <String, Object?>{
          'ok': false,
          'state': status.state.name,
          if (status.message.isNotEmpty) 'message': status.message,
          if (status.lastSyncedAt != null)
            'syncedAt': status.lastSyncedAt!.toUtc().toIso8601String(),
          'error': _safeVaultError(error),
        },
      );
    }
  }

  Future<void> _stateAction(String action, Object? value) async {
    if (action == 'clearAll') return _store.delete();
    await _store.mutate<void>((current) async {
      StoredData next;
      if (action == 'setApiKey') {
        final key = value?.toString().trim() ?? '';
        if (key.length > 2000) {
          throw StateError('The BFL API key is unexpectedly long.');
        }
        next = current.withApiKey('bfl', key);
      } else if (action == 'setProviderApiKey') {
        final map = value is Map<Object?, Object?> ? value : const {};
        final provider = map['provider']?.toString() ?? '';
        final key = map['apiKey']?.toString().trim() ?? '';
        if (provider.isEmpty || key.length > 2000) {
          throw StateError('The provider API key is invalid.');
        }
        next = current.withApiKey(provider, key);
      } else if (action == 'setPreferences') {
        final map = value is Map<Object?, Object?>
            ? value.map((key, child) => MapEntry(key.toString(), child))
            : <String, Object?>{};
        next = current.copyWith(
          preferences: AppPreferences.fromJson(map),
          preferencesUpdatedAt: DateTime.now().toUtc(),
        );
      } else if (action == 'saveLibraryFolder') {
        final map = value is Map<Object?, Object?>
            ? value.map((key, child) => MapEntry(key.toString(), child))
            : <String, Object?>{};
        final folder = LibraryFolder.fromJson(map);
        final name = folder.name.trim();
        if (folder.id.trim().isEmpty || name.isEmpty || name.length > 48) {
          throw StateError('Folder names must be between 1 and 48 characters.');
        }
        final parentId = folder.parentId?.trim().isEmpty == true
            ? null
            : folder.parentId;
        if (parentId != null &&
            !current.folders.any(
              (item) =>
                  item.id == parentId &&
                  item.collection == folder.collection &&
                  item.storage == folder.storage,
            )) {
          throw StateError('The parent folder no longer exists.');
        }
        var ancestorId = parentId;
        while (ancestorId != null) {
          if (ancestorId == folder.id) {
            throw StateError('A folder cannot live inside itself.');
          }
          ancestorId = current.folders
              .where((item) => item.id == ancestorId)
              .firstOrNull
              ?.parentId;
        }
        if (current.folders.any(
          (item) =>
              item.id != folder.id &&
              item.collection == folder.collection &&
              item.storage == folder.storage &&
              item.parentId == parentId &&
              item.name.toLowerCase() == name.toLowerCase(),
        )) {
          throw StateError('A folder named “$name” already exists here.');
        }
        final folders = List<LibraryFolder>.from(current.folders);
        final index = folders.indexWhere((item) => item.id == folder.id);
        final clean = LibraryFolder(
          id: folder.id,
          name: name,
          createdAt: folder.createdAt,
          parentId: parentId,
          collection: folder.collection,
          storage: folder.storage,
        );
        if (index < 0) {
          folders.add(clean);
        } else {
          folders[index] = clean;
        }
        next = current.copyWith(folders: folders);
      } else if (action == 'deleteLibraryFolder') {
        final folderId = value?.toString() ?? '';
        final removed = current.folders
            .where((folder) => folder.id == folderId)
            .firstOrNull;
        next = current.copyWith(
          folders: current.folders
              .where((folder) => folder.id != folderId)
              .map(
                (folder) => folder.parentId == folderId
                    ? folder.copyWith(
                        parentId: removed?.parentId,
                        clearParent: removed?.parentId == null,
                      )
                    : folder,
              )
              .toList(),
          generations: current.generations
              .map(
                (item) => item.folderId == folderId
                    ? item.copyWith(clearFolder: true)
                    : item,
              )
              .toList(),
          savedReferences: current.savedReferences
              .map(
                (item) => item.folderId == folderId
                    ? item.copyWith(clearFolder: true)
                    : item,
              )
              .toList(),
        );
      } else if (action == 'setGenerationOrganization') {
        final map = value is Map<Object?, Object?> ? value : const {};
        final localId = map['localId']?.toString() ?? '';
        final rawFolderId = map['folderId']?.toString().trim() ?? '';
        final folderId = rawFolderId.isEmpty ? null : rawFolderId;
        final target = current.generations
            .where((item) => item.localId == localId)
            .firstOrNull;
        if (target == null) {
          throw StateError('That generation no longer exists.');
        }
        if (folderId != null &&
            !current.folders.any(
              (folder) =>
                  folder.id == folderId &&
                  folder.collection == LibraryCollection.generated &&
                  folder.storage == target.storage,
            )) {
          throw StateError('That folder no longer exists.');
        }
        final tags = _cleanLibraryTags(
          map['tags'] is List<Object?>
              ? map['tags']! as List<Object?>
              : const <Object?>[],
        );
        var found = false;
        final generations = current.generations.map((item) {
          if (item.localId != localId) return item;
          found = true;
          return item.copyWith(
            folderId: folderId,
            clearFolder: folderId == null,
            tags: tags,
          );
        }).toList();
        if (!found) throw StateError('That generation no longer exists.');
        next = current.copyWith(generations: generations);
      } else if (action == 'setGenerationFavorite') {
        final map = value is Map<Object?, Object?> ? value : const {};
        final localId = map['localId']?.toString() ?? '';
        if (!current.generations.any((item) => item.localId == localId)) {
          throw StateError('That generation no longer exists.');
        }
        next = current.copyWith(
          generations: current.generations
              .map(
                (item) => item.localId == localId
                    ? item.copyWith(favorite: map['favorite'] == true)
                    : item,
              )
              .toList(),
        );
      } else if (action == 'setReferenceFavorite') {
        final map = value is Map<Object?, Object?> ? value : const {};
        final referenceId = map['referenceId']?.toString() ?? '';
        if (!current.savedReferences.any((item) => item.id == referenceId)) {
          throw StateError('That reference no longer exists.');
        }
        next = current.copyWith(
          savedReferences: current.savedReferences
              .map(
                (item) => item.id == referenceId
                    ? item.copyWith(
                        favorite: map['favorite'] == true,
                        updatedAt: DateTime.now().toUtc(),
                      )
                    : item,
              )
              .toList(),
        );
      } else if (action == 'setGenerationsHidden') {
        final map = value is Map<Object?, Object?> ? value : const {};
        final ids = (map['localIds'] as List<Object?>? ?? const <Object?>[])
            .whereType<String>()
            .toSet();
        if (!ids.every(
          current.generations.map((item) => item.localId).contains,
        )) {
          throw StateError('One or more generations no longer exist.');
        }
        next = current.copyWith(
          generations: current.generations
              .map(
                (item) => ids.contains(item.localId)
                    ? item.copyWith(hidden: map['hidden'] == true)
                    : item,
              )
              .toList(),
        );
      } else if (action == 'setReferencesHidden') {
        final map = value is Map<Object?, Object?> ? value : const {};
        final ids = (map['referenceIds'] as List<Object?>? ?? const <Object?>[])
            .whereType<String>()
            .toSet();
        if (!ids.every(
          current.savedReferences.map((item) => item.id).contains,
        )) {
          throw StateError('One or more references no longer exist.');
        }
        final now = DateTime.now().toUtc();
        next = current.copyWith(
          savedReferences: current.savedReferences
              .map(
                (item) => ids.contains(item.id)
                    ? item.copyWith(
                        hidden: map['hidden'] == true,
                        updatedAt: now,
                      )
                    : item,
              )
              .toList(),
        );
      } else if (action == 'saveGenerationPreviews') {
        final map = value is Map<Object?, Object?> ? value : const {};
        final localId = map['localId']?.toString() ?? '';
        final target = current.generations
            .where((item) => item.localId == localId)
            .firstOrNull;
        if (target == null) {
          throw StateError('That generation no longer exists.');
        }
        final thumbnailSource = map['thumbnail']?.toString();
        final timelineSource = map['timeline']?.toString();
        final thumbnail = thumbnailSource == null
            ? target.thumbnailAsset
            : await _store.writeAsset(
                base64Decode(thumbnailSource),
                label: 'clawnsole-$localId-thumbnail.jpg',
                contentType: 'image/jpeg',
                storage: target.storage,
              );
        final timeline = timelineSource == null
            ? target.timelineThumbnailAsset
            : await _store.writeAsset(
                base64Decode(timelineSource),
                label: 'clawnsole-$localId-timeline.png',
                contentType: 'image/png',
                storage: target.storage,
              );
        next = current.copyWith(
          generations: current.generations
              .map(
                (item) => item.localId == localId
                    ? item.copyWith(
                        thumbnailAsset: thumbnail ?? item.thumbnailAsset,
                        timelineThumbnailAsset:
                            timeline ?? item.timelineThumbnailAsset,
                      )
                    : item,
              )
              .toList(),
        );
      } else if (action == 'saveReferencePreview') {
        final map = value is Map<Object?, Object?> ? value : const {};
        final referenceId = map['referenceId']?.toString() ?? '';
        final target = current.savedReferences
            .where((item) => item.id == referenceId)
            .firstOrNull;
        if (target == null) {
          throw StateError('That reference no longer exists.');
        }
        final encoded = map['thumbnail']?.toString() ?? '';
        if (encoded.isEmpty) {
          throw StateError('A reference thumbnail is required.');
        }
        final thumbnail = await _store.writeAsset(
          base64Decode(encoded),
          label: 'clawnsole-$referenceId-thumbnail.jpg',
          contentType: 'image/jpeg',
          storage: target.storage,
        );
        next = current.copyWith(
          savedReferences: current.savedReferences
              .map(
                (item) => item.id == referenceId
                    ? item.copyWith(thumbnailAsset: thumbnail)
                    : item,
              )
              .toList(),
        );
      } else if (action == 'saveGenerationInputPreview') {
        final map = value is Map<Object?, Object?> ? value : const {};
        final localId = map['localId']?.toString() ?? '';
        final sourceAssetValue = map['sourceAssetValue']?.toString() ?? '';
        final target = current.generations
            .where((item) => item.localId == localId)
            .firstOrNull;
        if (target == null) {
          throw StateError('That generation no longer exists.');
        }
        final matchesSource = target.config.source?.value == sourceAssetValue;
        final matchesReference =
            target.config.references?.any(
              (item) => item.source?.value == sourceAssetValue,
            ) ==
            true;
        if (!matchesSource && !matchesReference) {
          throw StateError('That generation input no longer exists.');
        }
        final encoded = map['thumbnail']?.toString() ?? '';
        if (encoded.isEmpty) {
          throw StateError('An input thumbnail is required.');
        }
        final thumbnail = await _store.writeAsset(
          base64Decode(encoded),
          label: 'clawnsole-$localId-input-thumbnail.jpg',
          contentType: 'image/jpeg',
          storage: target.storage,
        );
        final references = target.config.references
            ?.map(
              (item) => item.source?.value == sourceAssetValue
                  ? item.copyWith(thumbnailAsset: thumbnail)
                  : item,
            )
            .toList();
        final config = target.config.copyWith(
          references: references,
          sourceThumbnailAsset: matchesSource
              ? thumbnail
              : target.config.sourceThumbnailAsset,
        );
        next = current.copyWith(
          generations: current.generations
              .map(
                (item) => item.localId == localId
                    ? item.copyWith(config: config)
                    : item,
              )
              .toList(),
        );
      } else if (action == 'saveReference') {
        final map = value is Map<Object?, Object?> ? value : const {};
        final rawReference = map['reference'];
        final reference = SavedReference.fromJson(
          rawReference is Map<Object?, Object?>
              ? rawReference.map(
                  (key, child) => MapEntry(key.toString(), child),
                )
              : const <String, Object?>{},
        );
        final name = reference.name.trim();
        if (reference.id.trim().isEmpty || name.isEmpty || name.length > 80) {
          throw StateError(
            'Reference names must be between 1 and 80 characters.',
          );
        }
        if (reference.folderId != null &&
            !current.folders.any(
              (folder) =>
                  folder.id == reference.folderId &&
                  folder.collection == LibraryCollection.references &&
                  folder.storage == reference.storage,
            )) {
          throw StateError('That reference folder no longer exists.');
        }
        final existing = current.savedReferences
            .where((item) => item.id == reference.id)
            .firstOrNull;
        var asset = existing?.asset ?? reference.asset;
        final source = map['source']?.toString();
        if (source != null) {
          asset =
              await _store.persistSource(
                source,
                label: name,
                retained: reference.asset.value.isEmpty
                    ? null
                    : reference.asset,
                storage: reference.storage,
              ) ??
              asset;
        }
        if (asset.value.isEmpty) {
          throw StateError('Choose reference media before saving.');
        }
        final clean = SavedReference(
          id: reference.id,
          name: name,
          kind: reference.kind,
          asset: asset,
          thumbnailAsset: existing?.thumbnailAsset ?? reference.thumbnailAsset,
          createdAt: existing?.createdAt ?? reference.createdAt,
          updatedAt: reference.updatedAt,
          folderId: reference.folderId,
          tags: _cleanLibraryTags(reference.tags),
          favorite: reference.favorite,
          hidden: reference.hidden,
          storage: reference.storage,
          contentDigest: reference.contentDigest ?? existing?.contentDigest,
          durationSeconds:
              reference.durationSeconds ?? existing?.durationSeconds,
        );
        final references = List<SavedReference>.from(current.savedReferences);
        final index = references.indexWhere((item) => item.id == clean.id);
        if (index < 0) {
          references.insert(0, clean);
        } else {
          references[index] = clean;
        }
        next = current.copyWith(savedReferences: references);
      } else if (action == 'trimReferenceVideo') {
        final editor = _referenceVideoEditingService;
        if (editor == null) {
          throw StateError('Video trimming is unavailable on this build.');
        }
        final map = value is Map<Object?, Object?> ? value : const {};
        final sourceReferenceId = map['sourceReferenceId']?.toString() ?? '';
        final source = current.savedReferences
            .where((item) => item.id == sourceReferenceId)
            .firstOrNull;
        if (source == null || source.kind != MediaReferenceKind.video) {
          throw StateError('That reference video no longer exists.');
        }
        final rawOutput = map['output'];
        final output = SavedReference.fromJson(
          rawOutput is Map<Object?, Object?>
              ? rawOutput.map((key, child) => MapEntry(key.toString(), child))
              : const <String, Object?>{},
        );
        final startSeconds = (map['startSeconds'] as num?)?.toDouble();
        final endSeconds = (map['endSeconds'] as num?)?.toDouble();
        final sourceDuration = source.durationSeconds;
        if (sourceDuration == null ||
            startSeconds == null ||
            endSeconds == null ||
            !startSeconds.isFinite ||
            !endSeconds.isFinite ||
            startSeconds < 0 ||
            endSeconds > sourceDuration + .001 ||
            endSeconds - startSeconds < .1) {
          throw StateError('Choose a valid range within the reference video.');
        }
        final name = output.name.trim();
        if (output.id.trim().isEmpty || name.isEmpty || name.length > 80) {
          throw StateError(
            'Reference names must be between 1 and 80 characters.',
          );
        }
        if (current.savedReferences.any((item) => item.id == output.id)) {
          throw StateError('That reference already exists.');
        }
        if (output.storage != source.storage ||
            (output.folderId != null &&
                !current.folders.any(
                  (folder) =>
                      folder.id == output.folderId &&
                      folder.collection == LibraryCollection.references &&
                      folder.storage == source.storage,
                ))) {
          throw StateError('That reference folder no longer exists.');
        }
        final trimmed = await editor.trimVideo(
          await _referenceVideoBytes(source.asset),
          startSeconds: startSeconds,
          endSeconds: endSeconds,
        );
        final asset = await _store.writeAsset(
          trimmed,
          label: name.toLowerCase().endsWith('.mp4') ? name : '$name.mp4',
          contentType: 'video/mp4',
          storage: source.storage,
        );
        final now = DateTime.now().toUtc();
        final saved = SavedReference(
          id: output.id,
          name: name,
          kind: MediaReferenceKind.video,
          asset: asset,
          createdAt: now,
          updatedAt: now,
          folderId: output.folderId,
          tags: _cleanLibraryTags(output.tags),
          favorite: output.favorite,
          hidden: output.hidden,
          storage: source.storage,
          durationSeconds: endSeconds - startSeconds,
        );
        next = current.copyWith(
          savedReferences: <SavedReference>[saved, ...current.savedReferences],
        );
      } else if (action == 'deleteReference') {
        final id = value?.toString() ?? '';
        next = current.copyWith(
          savedReferences: current.savedReferences
              .where((item) => item.id != id)
              .toList(),
        );
      } else if (action == 'clearHistory') {
        next = current.copyWith(generations: <Generation>[]);
      } else if (action == 'clearPreferences') {
        next = current.copyWith(
          preferences: const AppPreferences(),
          preferencesUpdatedAt: DateTime.now().toUtc(),
        );
      } else if (action == 'clearApiKey') {
        next = current.withApiKey('bfl', '');
      } else if (action == 'clearProviderApiKey') {
        next = current.withApiKey(value?.toString() ?? '', '');
      } else {
        throw const ProviderException(
          'Unknown local data action.',
          status: 400,
        );
      }
      return StoreChange<void>(next, null);
    });
    if (action == 'clearHistory' ||
        action == 'deleteReference' ||
        action == 'saveGenerationPreviews' ||
        action == 'saveReferencePreview' ||
        action == 'saveGenerationInputPreview') {
      final data = await _store.read();
      await _store.pruneAssets(data.generations, data.savedReferences);
    }
  }

  Future<Uint8List> _referenceVideoBytes(AssetReference asset) async {
    if (asset.isLocal) return _store.readAsset(asset);
    final uri = Uri.tryParse(asset.value);
    if (uri == null || uri.scheme != 'https') {
      throw StateError('The reference video is not available for trimming.');
    }
    const maximumBytes = 512 * 1024 * 1024;
    final client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 20);
    try {
      final request = await client.getUrl(uri);
      final response = await request.close();
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw StateError('The reference video could not be downloaded.');
      }
      if (response.contentLength > maximumBytes) {
        throw StateError('Reference videos must be 512 MB or smaller.');
      }
      final bytes = BytesBuilder(copy: false);
      var length = 0;
      await for (final chunk in response) {
        length += chunk.length;
        if (length > maximumBytes) {
          throw StateError('Reference videos must be 512 MB or smaller.');
        }
        bytes.add(chunk);
      }
      final value = bytes.takeBytes();
      if (value.isEmpty) throw StateError('The reference video is empty.');
      return value;
    } finally {
      client.close(force: true);
    }
  }

  Future<LocalSnapshot> _snapshot() async {
    var data = await _store.read();
    // Apply persisted caps immediately, but keep maintenance sweeps off the
    // startup response path. setMaxBytes updates the active bound before its
    // first asynchronous filesystem pass, so newly generated media already
    // honors the setting while old files are trimmed in the background.
    _applyCachePreferences(data);
    final now = DateTime.now().toUtc();
    var changed = false;
    final generations = data.generations.map((item) {
      var next = item.recoverInterruptedSubmission(now);
      if (!identical(next, item)) changed = true;
      if (next.provider == 'apple-local' && next.isWorking) {
        changed = true;
        next = next.copyWith(
          status: 'Error',
          error: 'Apple Local generation has been retired.',
          updatedAt: now,
        );
      }
      if (next.isReady && next.resultAsset == null) {
        final availability = providerById(
          next.provider,
        ).resultDelivery.availability;
        final expectedExpiry = availability == null
            ? null
            : next.lastProviderResponseAt?.add(availability);
        if (availability == null && next.deliveryExpiresAt != null) {
          changed = true;
          next = next.copyWith(clearDeliveryExpiresAt: true);
        } else if (expectedExpiry != null &&
            (next.deliveryExpiresAt == null ||
                next.deliveryExpiresAt!.isBefore(expectedExpiry))) {
          changed = true;
          next = next.copyWith(deliveryExpiresAt: expectedExpiry);
        }
      }
      // An undelivered record keeps its links past the retention estimate
      // until at least one status check ran after the estimate lapsed: the
      // estimate can expire entirely while the process is suspended or dead,
      // and purging on the next load would destroy the delivery link before
      // the recovery poll gets its one chance to download from it.
      final attemptedAfterExpiry =
          next.resultAsset != null ||
          (next.deliveryExpiresAt != null &&
              next.lastCheckedAt?.isAfter(next.deliveryExpiresAt!) == true);
      if (next.deliveryExpiresAt == null ||
          next.deliveryExpiresAt!.isAfter(now) ||
          (next.resultUrl == null && next.draftCacheUrl == null) ||
          !attemptedAfterExpiry) {
        return next;
      }
      changed = true;
      final json = next.toJson()
        ..remove('resultUrl')
        ..remove('draftCacheUrl')
        ..['deliveryExpired'] =
            next.resultAsset == null || next.draftCacheUrl != null;
      return Generation.fromJson(json);
    }).toList();
    if (changed) {
      data = data.copyWith(generations: generations);
      await _store.replace(data);
    }
    final connected = videoProviders
        .where((provider) => _activeKey(data, provider.id).isNotEmpty)
        .map((provider) => provider.id)
        .toSet();
    return LocalSnapshot(
      generations: data.generations,
      folders: data.folders,
      savedReferences: data.savedReferences,
      preferences: data.preferences,
      hasApiKey: connected.contains('bfl'),
      connectedProviders: connected,
      availableProviders: const <String>{
        'bfl',
        'ltx',
        'artcraft',
        'atlas',
        'runway',
      },
      settingsVault:
          _store.vault?.settingsVaultStatus ??
          const SettingsVaultStatus.unavailable(),
      storage: await _store.stats(
        data.generations.length + data.savedReferences.length,
      ),
    );
  }

  Future<Map<String, Object?>> _snapshotPayload() async => <String, Object?>{
    ...(await _snapshot()).toJson(),
    'driveConnection': _store.connection.toJson(),
  };

  Future<Generation> _upsert(Generation generation) async {
    return _store.mutate<Generation>((current) {
      final generations = List<Generation>.from(current.generations);
      final index = generations.indexWhere(
        (item) => item.localId == generation.localId,
      );
      var persisted = generation;
      if (index >= 0) {
        final existing = generations[index];
        persisted = generation.copyWith(
          folderId: existing.folderId,
          clearFolder: existing.folderId == null,
          tags: existing.tags,
          favorite: existing.favorite,
          hidden: existing.hidden,
          storage: existing.storage,
        );
        generations[index] = persisted;
      } else {
        generations.insert(0, persisted);
      }
      return StoreChange<Generation>(
        current.copyWith(generations: generations),
        persisted,
      );
    });
  }

  String _activeKey(StoredData data, String provider) {
    final saved = data.apiKeyFor(provider).trim();
    return saved.isNotEmpty ? saved : _fallbackApiKeys[provider]?.trim() ?? '';
  }

  Future<double?> _balanceSafely(String provider, String key) async {
    try {
      return (await _providers.verify(provider, key)).balance;
    } on Object {
      return null;
    }
  }

  String _keyframeSource(Object? value) {
    if (value is String) return value;
    if (value is List<Object?> && value.length > 1 && value[1] is String) {
      return value[1]! as String;
    }
    return '';
  }

  Future<GenerationConfig> _persistInputs(
    GenerationConfig config,
    Map<String, Object?> input,
    LibraryStorage storage,
  ) async {
    final mode = input['mode'];
    if (mode == 'i2v') {
      final rawFrames = input['keyframes'] as List<Object?>? ?? const [];
      final frames = <KeyframeLabel>[];
      for (var index = 0; index < (config.keyframes?.length ?? 0); index += 1) {
        final frame = config.keyframes![index];
        frames.add(
          KeyframeLabel(
            label: frame.label,
            role: frame.role,
            seconds: frame.seconds,
            referenceId: frame.referenceId,
            source: await _store.persistSource(
              index < rawFrames.length ? _keyframeSource(rawFrames[index]) : '',
              label: frame.label,
              retained: frame.source,
              storage: storage,
            ),
          ),
        );
      }
      final rawReferences = <MediaReferenceKind, List<Object?>>{
        MediaReferenceKind.image:
            input['reference_images'] as List<Object?>? ?? const [],
        MediaReferenceKind.video:
            input['reference_videos'] as List<Object?>? ?? const [],
        MediaReferenceKind.audio:
            input['reference_audios'] as List<Object?>? ?? const [],
      };
      final offsets = <MediaReferenceKind, int>{
        for (final kind in MediaReferenceKind.values) kind: 0,
      };
      final references = <MediaReferenceLabel>[];
      for (final media in config.references ?? const <MediaReferenceLabel>[]) {
        final index = offsets[media.kind]!;
        final sources = rawReferences[media.kind]!;
        offsets[media.kind] = index + 1;
        references.add(
          MediaReferenceLabel(
            label: media.label,
            kind: media.kind,
            promptName: media.promptName,
            referenceId: media.referenceId,
            thumbnailAsset: media.thumbnailAsset,
            source: await _store.persistSource(
              index < sources.length ? sources[index]?.toString() ?? '' : '',
              label: media.label,
              retained: media.source,
              storage: storage,
            ),
          ),
        );
      }
      return config.copyWith(keyframes: frames, references: references);
    }
    if (mode == 'v2v' ||
        mode == 'draft_enhance' ||
        input.containsKey('input_video')) {
      return config.copyWith(
        source: await _store.persistSource(
          (input.containsKey('input_video')
                      ? input['input_video']
                      : input[mode == 'v2v' ? 'start_video' : 'draft_cache'])
                  ?.toString() ??
              '',
          label: config.sourceLabel ?? 'Clawnsole source',
          retained: config.source,
          storage: storage,
        ),
        sourceThumbnailAsset: config.sourceThumbnailAsset,
      );
    }
    return config;
  }

  Future<AssetReference?> _retainResult(
    String source,
    String label,
    LibraryStorage storage,
  ) async {
    final target = validatedProviderUrl(source);
    final client = HttpClient();
    try {
      final request = await client.getUrl(target);
      final upstream = await request.close().timeout(
        const Duration(seconds: 30),
      );
      if (upstream.statusCode < 200 || upstream.statusCode >= 300) {
        throw ProviderException(
          'The provider result download returned HTTP ${upstream.statusCode}.',
          status: upstream.statusCode,
        );
      }
      final builder = BytesBuilder(copy: false);
      await for (final chunk in upstream.timeout(const Duration(seconds: 30))) {
        builder.add(chunk);
      }
      return await _store.writeAsset(
        builder.takeBytes(),
        label: label,
        contentType: upstream.headers.contentType?.mimeType ?? 'video/mp4',
        storage: storage,
      );
    } on TimeoutException {
      throw const ProviderException(
        'The provider result download stalled. Clawnsole will retry it.',
      );
    } finally {
      client.close(force: true);
    }
  }

  /// Retains a ready result through its previously captured delivery link
  /// after a status check failed. `stalled` distinguishes a timed-out
  /// download — which says nothing about the link itself and must keep the
  /// generation retryable — from a definitive link failure.
  Future<({AssetReference? asset, bool stalled})> _downloadRetainedResult(
    Generation current,
  ) async {
    final url = current.resultUrl;
    if (!current.isReady || current.resultAsset != null || url == null) {
      return (asset: null, stalled: false);
    }
    try {
      return (
        asset: await _retainResult(
          url,
          'clawnsole-${current.localId}.mp4',
          current.storage,
        ),
        stalled: false,
      );
    } on ProviderException catch (error) {
      // _retainResult reports a timed-out download as a status-less
      // ProviderException.
      return (asset: null, stalled: error.status == null);
    } on Object {
      return (asset: null, stalled: false);
    }
  }

  /// Persists a poll outcome unless the stored record advanced past the
  /// [expected] baseline while this poll ran, returning null when it did.
  ///
  /// A poll abandoned by its caller's timeout keeps running on a dead socket
  /// and can complete much later; without this guard its stale write would
  /// overwrite a newer poll's outcome — even discarding a delivered result
  /// asset — or resurrect a deleted record. Every persisted poll outcome
  /// advances statusCheckCount, so it serves as the write version.
  Future<Generation?> _persistPollUpdate(
    Generation next, {
    required Generation expected,
  }) {
    return _store.mutate<Generation?>((current) {
      final generations = List<Generation>.from(current.generations);
      final index = generations.indexWhere(
        (item) => item.localId == next.localId,
      );
      if (index < 0) return StoreChange<Generation?>(current, null);
      final existing = generations[index];
      if (existing.statusCheckCount != expected.statusCheckCount) {
        return StoreChange<Generation?>(current, null);
      }
      final persisted = next.copyWith(
        folderId: existing.folderId,
        clearFolder: existing.folderId == null,
        tags: existing.tags,
        favorite: existing.favorite,
        hidden: existing.hidden,
        storage: existing.storage,
      );
      generations[index] = persisted;
      return StoreChange<Generation?>(
        current.copyWith(generations: generations),
        persisted,
      );
    });
  }

  /// The stored version of [generation], or the caller's copy when the
  /// record no longer exists.
  Future<Generation> _storedOrInput(Generation generation) async {
    final data = await _store.read();
    return data.generations
            .where((item) => item.localId == generation.localId)
            .firstOrNull ??
        generation;
  }

  Future<Generation> _submit(Map<String, Object?> body) async {
    final input = body['input'];
    final rawRecord = body['record'];
    if (input is! Map<Object?, Object?> ||
        rawRecord is! Map<Object?, Object?>) {
      throw const ProviderException(
        'The generation request is incomplete.',
        status: 400,
      );
    }
    final data = await _store.read();
    var generation = Generation.fromJson(
      rawRecord.map((key, value) => MapEntry(key.toString(), value)),
    );
    var cleanInput = input.map((key, value) => MapEntry(key.toString(), value));
    final provider = generation.provider;
    if (provider == 'apple-local') {
      throw StateError(
        'Apple Local generation has been retired. Choose another provider.',
      );
    }
    final key = _activeKey(data, provider);
    if (key.isEmpty) {
      throw StateError(
        'Add a ${providerById(provider).name} API key before generating.',
      );
    }
    final autoFixReferenceVideos = switch (body['autoFixReferenceVideos']) {
      final bool value => value,
      _ => data.preferences.autoFixReferenceVideos,
    };
    final model = modelById(provider, generation.model);
    final referenceVideoProfile = model.referenceVideoCompatibilityProfile;
    final referenceImageProfile = model.referenceImageCompatibilityProfile;
    if (autoFixReferenceVideos) {
      final ReferenceImageNormalizationService imageNormalizer =
          _referenceVideoNormalizer is ReferenceImageNormalizationService
          ? _referenceVideoNormalizer as ReferenceImageNormalizationService
          : const DisabledReferenceVideoNormalizationService();
      final prepared = await prepareGenerationReferences(
        input: cleanInput,
        config: generation.config,
        videoNormalizer: _referenceVideoNormalizer,
        imageNormalizer: imageNormalizer,
        videoProfile: referenceVideoProfile,
        imageProfile: referenceImageProfile,
      );
      cleanInput = prepared.input;
      generation = generation.copyWith(config: prepared.config);
    }
    generation = generation.copyWith(
      config: await _persistInputs(
        generation.config,
        cleanInput,
        generation.storage,
      ),
    );
    final estimate = estimateCost(
      provider,
      generation.model,
      generation.mode,
      generation.config,
      data.generations,
    );
    generation = generation.copyWith(
      status: 'submitting',
      canonicalModelId:
          generation.canonicalModelId ??
          canonicalModelIdFor(provider, generation.model),
      estimatedCreditsMin:
          generation.estimatedCreditsMin ??
          estimate.providerUnitsMinimum ??
          estimate.minimumUsd,
      estimatedCreditsMax:
          generation.estimatedCreditsMax ??
          estimate.providerUnitsMaximum ??
          estimate.maximumUsd,
      estimateBasis: generation.estimateBasis ?? estimate.basis,
      quotedCostUsdMin: generation.quotedCostUsdMin ?? estimate.minimumUsd,
      quotedCostUsdMax: generation.quotedCostUsdMax ?? estimate.maximumUsd,
      updatedAt: DateTime.now().toUtc(),
    );
    generation = await _upsert(generation);
    try {
      final creditsBefore = await _balanceSafely(provider, key);
      if (creditsBefore != null) {
        generation = generation.copyWith(creditsBefore: creditsBefore);
        generation = await _upsert(generation);
      }
      final receipt = await _providers.submit(
        provider,
        key,
        generation.model,
        cleanInput,
      );
      final requestId = receipt['id'];
      final pollingUrl = receipt['polling_url'];
      if (requestId is! String || pollingUrl is! String) {
        throw const ProviderException(
          'The provider returned an invalid generation receipt.',
          status: 502,
        );
      }
      final acceptedAt = DateTime.now().toUtc();
      final receiptEstimate = (receipt['estimated_credits'] as num?)
          ?.toDouble();
      generation = generation.copyWith(
        requestId: requestId,
        pollingUrl: pollingUrl,
        status: 'Pending',
        clearProgress: true,
        estimatedCreditsMax: receiptEstimate,
        estimateBasis: receiptEstimate == null
            ? null
            : 'provider submission receipt · maximum charge',
        quotedCostUsdMax: receiptEstimate == null
            ? null
            : creditsToUsd(receiptEstimate),
        lastProviderStatusCode: 200,
        lastProviderResponse: compactProviderResponse(receipt),
        lastProviderResponseAt: acceptedAt,
        updatedAt: acceptedAt,
      );
      // Keep the provider task recoverable even if the process exits or the
      // optional balance/cost refresh below loses connectivity.
      generation = await _upsert(generation);
      final liveAfter = await _balanceSafely(provider, key);
      final realized = resolveProviderCost(
        generation,
        receipt,
        balanceAfter: liveAfter,
      );
      final cost = realized.providerUnits;
      generation = generation.copyWith(
        cost: cost,
        clearCost: cost == null,
        realizedCostUsd: realized.usd,
        realizedCostSource: realized.source,
        creditsBefore: creditsBefore,
        creditsAfter:
            liveAfter ??
            (creditsBefore != null && cost != null
                ? (creditsBefore - cost).clamp(0, double.infinity)
                : null),
        updatedAt: DateTime.now().toUtc(),
      );
      generation = await _upsert(generation);
      return generation;
    } on Object catch (error) {
      if (generation.canCheckStatus) return generation;
      generation = generation.copyWith(
        status: 'Error',
        error: generationExceptionMessage(error),
        lastProviderStatusCode: providerHttpStatus(error),
        lastProviderResponse: providerErrorResponse(error),
        lastProviderResponseAt: DateTime.now().toUtc(),
        updatedAt: DateTime.now().toUtc(),
      );
      generation = await _upsert(generation);
      rethrow;
    }
  }

  Future<Generation> _poll(Map<String, Object?> body) async {
    final localId = body['localId']?.toString();
    final pollingUrl = body['pollingUrl']?.toString();
    if (localId == null || pollingUrl == null) {
      throw const ProviderException(
        'A generation id and polling URL are required.',
        status: 400,
      );
    }
    final data = await _store.read();
    final current = data.generations
        .where((item) => item.localId == localId)
        .firstOrNull;
    if (current == null) {
      throw const ProviderException(
        'The generation was not found.',
        status: 404,
      );
    }
    if (current.provider == 'apple-local') {
      throw StateError(
        'Apple Local generation has been retired. Existing downloaded media remains in the Library.',
      );
    }
    final key = _activeKey(data, current.provider);
    if (key.isEmpty) {
      throw StateError(
        'The saved ${providerById(current.provider).name} API key is missing.',
      );
    }
    final checkedAt = DateTime.now().toUtc();
    late Generation next;
    try {
      final payload = await _providers.poll(current.provider, key, pollingUrl);
      final reportedStatus = normalizeGenerationStatus(payload['status']);
      var status = reportedStatus;
      if (isGenerationFailureStatus(status) && current.hasDeliveredMedia) {
        // A provider expiring or forgetting a task whose film — or still-held
        // delivery link — already arrived must not fail the generation; a
        // restored ready status lets retention keep trying the link below.
        status = normalizeGenerationStatus(current.status);
      }
      final result = payload['result'] ?? payload['outputs'] ?? payload;
      // Fresh links come only from a payload that itself reported ready — a
      // failure payload must never have an incidental URL mistaken for one.
      final resultUrl = reportedStatus == 'Ready'
          ? findResultUrl(result, draft: false)
          : null;
      final draftUrl = reportedStatus == 'Ready'
          ? findResultUrl(result, draft: true)
          : null;
      var failureMessage = isGenerationFailureStatus(status)
          ? providerNamedFailureMessage(
              providerById(current.provider).name,
              payload,
              fallback: status,
            )
          : null;
      var resultAsset = current.resultAsset;
      var retentionFailures = current.resultRetentionFailures;
      String? retentionError;
      var attemptedRetention = false;
      // A previously captured delivery link often outlives the provider's
      // status payload, so retention falls back to it whenever this poll's
      // payload no longer carries a fresh link.
      final downloadUrl = status == 'Ready'
          ? (resultUrl ?? current.resultUrl)
          : resultUrl;
      final deliveryAvailability = providerById(
        current.provider,
      ).resultDelivery.availability;
      if (status == 'Ready' && resultAsset == null && resultUrl != null) {
        // The ready status and its delivery link are an irreplaceable receipt:
        // they must survive a crash or shutdown during the download attempt
        // below, so they are persisted now rather than only at poll end.
        final receipt = await _persistPollUpdate(
          expected: current,
          current.copyWith(
            status: status,
            resultUrl: resultUrl,
            draftCacheUrl: draftUrl,
            deliveryExpiresAt: deliveryAvailability != null
                ? current.deliveryExpiresAt ??
                      checkedAt.add(deliveryAvailability)
                : null,
            clearDeliveryExpiresAt: deliveryAvailability == null,
            deliveryExpired: false,
            lastProviderResponse: compactProviderResponse(payload),
            lastProviderResponseAt: checkedAt,
            updatedAt: checkedAt,
          ),
        );
        if (receipt == null) {
          // A newer poll outcome (or a deletion) superseded this one while
          // it ran; downloading against the stale baseline would only race
          // that winner's write.
          return await _storedOrInput(current);
        }
      }
      if (status == 'Ready' && resultAsset == null && downloadUrl == null) {
        attemptedRetention = true;
        retentionFailures += 1;
        retentionError =
            '${providerById(current.provider).name} reports that the generation is ready, but has not supplied a downloadable result yet. Clawnsole will keep retrying.';
      } else if (downloadUrl != null && resultAsset == null) {
        attemptedRetention = true;
        try {
          resultAsset = await _retainResult(
            downloadUrl,
            'clawnsole-${current.localId}.mp4',
            current.storage,
          );
          retentionFailures = 0;
        } on Object catch (error) {
          retentionFailures += 1;
          retentionError = generationExceptionMessage(error);
        }
      }
      final failed = isGenerationFailureStatus(status);
      final terminal = status == 'Ready' || failed;
      final balanceAfter = terminal
          ? await _balanceSafely(current.provider, key)
          : null;
      final realized = resolveProviderCost(
        current,
        payload,
        balanceAfter: balanceAfter,
        allowDeterministicQuote: status == 'Ready',
        terminal: terminal,
      );
      next = current.copyWith(
        status: status,
        progress: status == 'Ready'
            ? 100
            : normalizedProgress(payload['progress']),
        resultUrl: resultUrl,
        resultAsset: resultAsset,
        deliveryExpired: status == 'Ready' ? false : current.deliveryExpired,
        draftCacheUrl: draftUrl,
        deliveryExpiresAt: status == 'Ready' && deliveryAvailability != null
            ? current.deliveryExpiresAt ?? checkedAt.add(deliveryAvailability)
            : null,
        clearDeliveryExpiresAt:
            status == 'Ready' && deliveryAvailability == null,
        lastResultRetentionAttemptAt: attemptedRetention ? checkedAt : null,
        resultRetentionFailures: resultAsset != null ? 0 : retentionFailures,
        resultRetentionError: retentionError,
        clearResultRetentionError:
            resultAsset != null || status != 'Ready' || retentionError == null,
        error: failureMessage,
        clearError: !failed,
        cost: realized.providerUnits,
        realizedCostUsd: realized.usd,
        realizedCostSource: realized.source,
        creditsAfter: balanceAfter,
        lastCheckedAt: checkedAt,
        statusCheckCount: current.statusCheckCount + 1,
        consecutiveCheckFailures: 0,
        clearLastCheckError: true,
        lastProviderStatusCode: 200,
        lastProviderResponse: compactProviderResponse(payload),
        lastProviderResponseAt: checkedAt,
        updatedAt: checkedAt,
      );
    } on Object catch (error) {
      final rescue = await _downloadRetainedResult(current);
      final payload = providerErrorPayload(error);
      final providerStatus = normalizeGenerationStatus(payload?['status']);
      if (rescue.asset != null) {
        // The status check failed, but the film itself was still available at
        // the previously captured delivery link, so the generation completes.
        next = current.copyWith(
          resultAsset: rescue.asset,
          lastResultRetentionAttemptAt: checkedAt,
          resultRetentionFailures: 0,
          clearResultRetentionError: true,
          lastCheckedAt: checkedAt,
          statusCheckCount: current.statusCheckCount + 1,
          consecutiveCheckFailures: 0,
          clearLastCheckError: true,
          lastProviderStatusCode: providerHttpStatus(error),
          lastProviderResponse: providerErrorResponse(error),
          lastProviderResponseAt: checkedAt,
          updatedAt: checkedAt,
        );
      } else if (payload != null &&
          isGenerationFailureStatus(providerStatus) &&
          current.hasDeliveredMedia) {
        // The film — or its still-held delivery link — already arrived; an
        // expired or failed provider job cannot retract it, and the rescue
        // above will keep retrying the link until the delivery window purge
        // releases it. Record the check without downgrading the delivery.
        next = current.copyWith(
          lastCheckedAt: checkedAt,
          statusCheckCount: current.statusCheckCount + 1,
          consecutiveCheckFailures: 0,
          clearLastCheckError: true,
          lastResultRetentionAttemptAt: current.needsResultRetention
              ? checkedAt
              : null,
          resultRetentionFailures: current.needsResultRetention
              ? current.resultRetentionFailures + 1
              : current.resultRetentionFailures,
          lastProviderStatusCode: providerHttpStatus(error),
          lastProviderResponse: providerErrorResponse(error),
          lastProviderResponseAt: checkedAt,
          updatedAt: checkedAt,
        );
      } else if (payload != null && isGenerationFailureStatus(providerStatus)) {
        next = current.copyWith(
          status: providerStatus,
          progress: normalizedProgress(payload['progress']),
          error: providerNamedFailureMessage(
            providerById(current.provider).name,
            payload,
            fallback: providerStatus,
          ),
          lastCheckedAt: checkedAt,
          statusCheckCount: current.statusCheckCount + 1,
          consecutiveCheckFailures: 0,
          clearLastCheckError: true,
          lastProviderStatusCode: providerHttpStatus(error),
          lastProviderResponse: providerErrorResponse(error),
          lastProviderResponseAt: checkedAt,
          updatedAt: checkedAt,
        );
      } else {
        next = current.copyWith(
          lastCheckedAt: checkedAt,
          statusCheckCount: current.statusCheckCount + 1,
          consecutiveCheckFailures: current.consecutiveCheckFailures + 1,
          lastCheckError: generationExceptionMessage(error),
          lastResultRetentionAttemptAt: current.needsResultRetention
              ? checkedAt
              : null,
          resultRetentionFailures: current.needsResultRetention
              ? current.resultRetentionFailures + 1
              : current.resultRetentionFailures,
          resultRetentionError: current.needsResultRetention
              ? generationExceptionMessage(error)
              : null,
          lastProviderStatusCode: providerHttpStatus(error),
          lastProviderResponse: providerErrorResponse(error),
          lastProviderResponseAt: checkedAt,
          updatedAt: checkedAt,
        );
      }
    }
    return await _persistPollUpdate(next, expected: current) ??
        await _storedOrInput(current);
  }

  AssetReference? _findAsset(
    List<Generation> generations,
    List<SavedReference> savedReferences,
    String id,
  ) {
    for (final reference in savedReferences) {
      for (final asset in <AssetReference?>[
        reference.asset,
        reference.thumbnailAsset,
      ]) {
        if (asset?.isLocal == true && asset!.value == id) return asset;
      }
    }
    for (final generation in generations) {
      final references = <AssetReference?>[
        generation.resultAsset,
        generation.thumbnailAsset,
        generation.timelineThumbnailAsset,
        generation.config.source,
        generation.config.sourceThumbnailAsset,
        ...(generation.config.keyframes ?? const <KeyframeLabel>[]).map(
          (frame) => frame.source,
        ),
        ...(generation.config.references ?? const <MediaReferenceLabel>[])
            .expand(
              (media) => <AssetReference?>[media.source, media.thumbnailAsset],
            ),
      ];
      for (final reference in references) {
        if (reference?.isLocal == true && reference!.value == id) {
          return reference;
        }
      }
    }
    return null;
  }

  String? _resultFallbackUrl(StoredData data, String assetId) => data
      .generations
      .where(
        (item) =>
            item.resultAsset?.value == assetId &&
            item.resultUrl?.trim().isNotEmpty == true,
      )
      .firstOrNull
      ?.resultUrl;

  /// Applies the persisted cache-cap preference before any cache use, so a
  /// cap changed on another surface (through the synced preferences) takes
  /// effect on the very next request.
  Future<VideoCache?> _syncedVideoCache(StoredData data) async {
    final cache = _videoCache;
    if (cache == null) return null;
    await cache.setMaxBytes(data.preferences.localVideoCacheMb * 1024 * 1024);
    return cache;
  }

  Future<VideoCache?> _syncedThumbnailCache(StoredData data) async {
    final cache = _thumbnailCache;
    if (cache == null) return null;
    await cache.setMaxBytes(
      data.preferences.localThumbnailCacheMb * 1024 * 1024,
    );
    return cache;
  }

  void _applyCachePreferences(StoredData data) {
    for (final operation in <Future<VideoCache?>>[
      _syncedVideoCache(data),
      _syncedThumbnailCache(data),
    ]) {
      unawaited(operation.then<void>((_) {}, onError: (Object _) {}));
    }
  }

  bool _isVideoAsset(AssetReference reference) =>
      isRetainedVideoAsset(reference.contentType, reference.label);

  Future<void> _asset(HttpRequest request) async {
    final id = request.uri.queryParameters['id'];
    if (id == null) {
      throw const ProviderException(
        'A local asset id is required.',
        status: 400,
      );
    }
    final data = await _store.read();
    final reference = _findAsset(data.generations, data.savedReferences, id);
    if (reference == null) {
      throw const ProviderException(
        'The local asset was not found.',
        status: 404,
      );
    }
    // Retained asset ids are immutable: replacing content always mints a new
    // id, so the browser may privately reuse a delivered film for a day
    // instead of refetching it on every playback. `private` keeps user media
    // out of shared caches; the blanket CORS default stays no-store.
    request.response.headers.set(
      HttpHeaders.cacheControlHeader,
      'private, max-age=86400, immutable',
    );
    try {
      if (reference.kind == 'drive' && _isVideoAsset(reference)) {
        final cache = await _syncedVideoCache(data);
        if (cache != null && cache.enabled) {
          return await _driveVideoAsset(request, reference, cache);
        }
      }
      return await _serveAssetBytes(
        request,
        reference,
        await _store.readAsset(reference),
      );
    } on GoogleDriveException catch (error) {
      final fallback = error.status == 404
          ? _resultFallbackUrl(data, reference.value)
          : null;
      if (fallback != null) return _serveRemoteMedia(request, fallback);
      rethrow;
    }
  }

  /// Returns retained bytes only when they already exist on this device.
  /// A cache miss is intentionally a 404: startup preview restoration must
  /// never turn into an implicit Google Drive download.
  Future<void> _cachedAsset(HttpRequest request) async {
    final id = request.uri.queryParameters['id'];
    if (id == null || id.isEmpty) {
      throw const ProviderException('An asset id is required.', status: 400);
    }
    final data = await _store.read();
    final reference = _findAsset(data.generations, data.savedReferences, id);
    if (reference == null) {
      throw const ProviderException(
        'The retained asset was not found.',
        status: 404,
      );
    }
    if (reference.kind != 'drive') {
      return _serveAssetBytes(
        request,
        reference,
        await _store.readAsset(reference),
      );
    }
    final cache = _isVideoAsset(reference)
        ? await _syncedVideoCache(data)
        : await _syncedThumbnailCache(data);
    final file = cache?.enabled == true
        ? await cache!.lookup(reference.value)
        : null;
    if (file == null) {
      throw const ProviderException(
        'The retained asset is not cached on this device.',
        status: 404,
      );
    }
    return _serveAssetFile(request, reference, file);
  }

  /// Serves a Drive-stored film from the local disk cache, filling the cache
  /// exactly once on a miss. A cold request for a later byte range is
  /// answered directly from Drive's Range support while the full file is also
  /// materialized in the background. Browser players commonly begin with a
  /// tiny or nonzero range, so range playback must still warm the durable
  /// cache for the next open and the next process launch.
  Future<void> _driveVideoAsset(
    HttpRequest request,
    AssetReference reference,
    VideoCache cache,
  ) async {
    final cached = await cache.lookup(reference.value);
    if (cached != null) return _serveAssetFile(request, reference, cached);
    final range = _parseByteRange(request);
    final knownSize = reference.bytes;
    final opensAtZero =
        range == null || (range.rawStart == 0 && range.rawEnd == null);
    if (!opensAtZero && knownSize != null && knownSize > 0) {
      _queueDriveVideoFill(reference, cache);
      final resolved = _resolveByteRange(range, knownSize);
      if (resolved == null) {
        return _rangeNotSatisfiable(request, knownSize);
      }
      final bytes = await _store.readDriveAssetRange(
        reference,
        resolved.start,
        resolved.end,
      );
      request.response
        ..statusCode = HttpStatus.partialContent
        ..headers.set(
          HttpHeaders.contentRangeHeader,
          'bytes ${resolved.start}-${resolved.end}/$knownSize',
        );
      request.response.headers
        ..contentType = ContentType.parse(
          reference.contentType ?? 'application/octet-stream',
        )
        ..set(HttpHeaders.acceptRangesHeader, 'bytes')
        ..contentLength = bytes.length;
      request.response.add(bytes);
      return request.response.close();
    }
    final file = await _fillDriveVideo(reference, cache);
    return _serveAssetFile(request, reference, file);
  }

  /// Streams one Drive download into the cache, shared across concurrent
  /// requests so a film is never fetched upstream more than once at a time.
  Future<File> _fillDriveVideo(AssetReference reference, VideoCache cache) {
    final existing = _driveVideoFills[reference.value];
    if (existing != null) return existing;
    late final Future<File> operation;
    operation =
        () async {
          final already = await cache.lookup(reference.value);
          if (already != null) return already;
          final download = await _store.readDriveAssetStream(reference);
          return cache.put(
            reference.value,
            retainedAssetExtension(reference.contentType, reference.label),
            download.stream,
            expectedLength: download.contentLength ?? reference.bytes,
          );
        }().whenComplete(() {
          if (identical(_driveVideoFills[reference.value], operation)) {
            _driveVideoFills.remove(reference.value);
          }
        });
    _driveVideoFills[reference.value] = operation;
    return operation;
  }

  void _queueDriveVideoFill(AssetReference reference, VideoCache cache) {
    unawaited(
      _fillDriveVideo(reference, cache).then<void>(
        (_) {},
        onError: (Object error) {
          stderr.writeln(
            'Video cache fill failed for ${reference.value}: $error',
          );
        },
      ),
    );
  }

  Future<void> _prefetchVideo(HttpRequest request) async {
    final body = await _bodyMap(request);
    final id = body['id']?.toString() ?? '';
    if (id.isEmpty) {
      throw const ProviderException('An asset id is required.', status: 400);
    }
    final data = await _store.read();
    final reference = _findAsset(data.generations, data.savedReferences, id);
    if (reference == null) {
      throw const ProviderException(
        'The local asset was not found.',
        status: 404,
      );
    }
    final cache = await _syncedVideoCache(data);
    final queued =
        reference.kind == 'drive' &&
        _isVideoAsset(reference) &&
        cache != null &&
        cache.enabled;
    if (queued) await _fillDriveVideo(reference, cache);
    return _json(request.response, 200, <String, Object?>{
      'ok': true,
      'queued': queued,
      'cached': queued,
    });
  }

  Future<void> _serveAssetFile(
    HttpRequest request,
    AssetReference reference,
    File file,
  ) async {
    final size = await file.length();
    final range = _parseByteRange(request);
    final resolved = _resolveByteRange(range, size);
    if (resolved == null) return _rangeNotSatisfiable(request, size);
    if (range != null) {
      request.response
        ..statusCode = HttpStatus.partialContent
        ..headers.set(
          HttpHeaders.contentRangeHeader,
          'bytes ${resolved.start}-${resolved.end}/$size',
        );
    }
    request.response.headers
      ..contentType = ContentType.parse(
        reference.contentType ?? 'application/octet-stream',
      )
      ..set(HttpHeaders.acceptRangesHeader, 'bytes')
      ..contentLength = resolved.end - resolved.start + 1;
    await request.response.addStream(
      file.openRead(resolved.start, resolved.end + 1),
    );
    return request.response.close();
  }

  Future<void> _serveAssetBytes(
    HttpRequest request,
    AssetReference reference,
    Uint8List bytes,
  ) async {
    final size = bytes.length;
    final range = _parseByteRange(request);
    final resolved = _resolveByteRange(range, size);
    if (resolved == null) return _rangeNotSatisfiable(request, size);
    if (range != null) {
      request.response
        ..statusCode = HttpStatus.partialContent
        ..headers.set(
          HttpHeaders.contentRangeHeader,
          'bytes ${resolved.start}-${resolved.end}/$size',
        );
    }
    request.response.headers
      ..contentType = ContentType.parse(
        reference.contentType ?? 'application/octet-stream',
      )
      ..set(HttpHeaders.acceptRangesHeader, 'bytes')
      ..contentLength = resolved.end - resolved.start + 1;
    request.response.add(bytes.sublist(resolved.start, resolved.end + 1));
    return request.response.close();
  }

  _RawByteRange? _parseByteRange(HttpRequest request) {
    final range = request.headers.value(HttpHeaders.rangeHeader);
    final match = range == null
        ? null
        : RegExp(r'^bytes=(\d*)-(\d*)$').firstMatch(range);
    if (match == null) return null;
    return _RawByteRange(
      int.tryParse(match.group(1) ?? ''),
      int.tryParse(match.group(2) ?? ''),
    );
  }

  ({int start, int end})? _resolveByteRange(_RawByteRange? range, int size) {
    var start = 0;
    var end = size - 1;
    if (range != null) {
      if (range.rawStart == null && range.rawEnd != null) {
        start = max(0, size - range.rawEnd!);
      } else if (range.rawStart != null) {
        start = range.rawStart!;
      }
      if (range.rawEnd != null && range.rawStart != null) {
        end = min(range.rawEnd!, end);
      }
      if (start < 0 || start >= size || end < start) return null;
    }
    return (start: start, end: end);
  }

  Future<void> _rangeNotSatisfiable(HttpRequest request, int size) {
    request.response.statusCode = HttpStatus.requestedRangeNotSatisfiable;
    request.response.headers.set(
      HttpHeaders.contentRangeHeader,
      'bytes */$size',
    );
    return request.response.close();
  }

  Future<void> _media(HttpRequest request) async {
    final source = request.uri.queryParameters['url'];
    if (source == null) {
      throw const ProviderException('A media URL is required.', status: 400);
    }
    return _serveRemoteMedia(request, source);
  }

  Future<void> _serveRemoteMedia(HttpRequest request, String source) async {
    final target = validatedProviderUrl(source);
    final client = HttpClient();
    try {
      final upstreamRequest = await client.getUrl(target);
      final range = request.headers.value(HttpHeaders.rangeHeader);
      if (range != null) {
        upstreamRequest.headers.set(HttpHeaders.rangeHeader, range);
      }
      final upstream = await upstreamRequest.close();
      request.response.statusCode = upstream.statusCode;
      for (final name in <String>[
        HttpHeaders.contentTypeHeader,
        HttpHeaders.contentLengthHeader,
        HttpHeaders.contentRangeHeader,
        HttpHeaders.acceptRangesHeader,
      ]) {
        final value = upstream.headers.value(name);
        if (value != null) request.response.headers.set(name, value);
      }
      await upstream.pipe(request.response);
    } finally {
      client.close(force: true);
    }
  }

  Future<void> _staticFile(HttpRequest request) async {
    final root = _webRoot!.absolute;
    final segments = request.uri.pathSegments;
    if (segments.any(
      (segment) =>
          segment == '.' ||
          segment == '..' ||
          segment.contains('/') ||
          segment.contains('\\'),
    )) {
      throw const ProviderException('Invalid web asset path.', status: 400);
    }
    final relative = segments.isEmpty ? 'index.html' : segments.join('/');
    final file = File(
      '${root.path}${Platform.pathSeparator}'
      '${relative.replaceAll('/', Platform.pathSeparator)}',
    ).absolute;
    final rootPrefix = '${root.path}${Platform.pathSeparator}';
    if (!file.path.startsWith(rootPrefix) || !await file.exists()) {
      return _json(request.response, 404, <String, Object?>{
        'error': 'The requested web asset does not exist.',
      });
    }

    final extension = file.uri.pathSegments.last.split('.').last.toLowerCase();
    final type = switch (extension) {
      'html' => ContentType.html,
      'js' ||
      'mjs' => ContentType('application', 'javascript', charset: 'utf-8'),
      'css' => ContentType('text', 'css', charset: 'utf-8'),
      'json' || 'map' => ContentType.json,
      'svg' => ContentType('image', 'svg+xml'),
      'png' => ContentType('image', 'png'),
      'jpg' || 'jpeg' => ContentType('image', 'jpeg'),
      'webp' => ContentType('image', 'webp'),
      'ico' => ContentType('image', 'x-icon'),
      'wasm' => ContentType('application', 'wasm'),
      'ttf' => ContentType('font', 'ttf'),
      _ => ContentType.binary,
    };
    request.response.headers
      ..contentType = type
      ..contentLength = await file.length()
      ..set(HttpHeaders.cacheControlHeader, 'private, no-store');
    if (request.method == 'HEAD') return request.response.close();
    await file.openRead().pipe(request.response);
  }

  Future<void> _json(HttpResponse response, int status, Object? payload) async {
    response.statusCode = status;
    response.headers.contentType = ContentType.json;
    response.write(jsonEncode(payload));
    await response.close();
  }
}

int _vaultErrorStatus(Object error) {
  if (error is GoogleDriveException) return 502;
  if (error is StateError ||
      error is ArgumentError ||
      error is FormatException ||
      error is SettingsVaultFormatException ||
      error is SettingsVaultAuthenticationException) {
    return 400;
  }
  return 500;
}

String _safeVaultError(Object error) {
  if (error is SettingsVaultAuthenticationException) return error.message;
  if (error is SettingsVaultFormatException) return error.message;
  if (error is GoogleDriveException) return error.message;
  if (error is StateError) return error.message;
  if (error is ArgumentError && error.message is String) {
    return error.message! as String;
  }
  if (error is FormatException) {
    return 'The settings-vault request is invalid.';
  }
  return 'Encrypted settings sync failed. Your local settings were kept.';
}

extension<T> on Iterable<T> {
  T? get firstOrNull {
    final iterator = this.iterator;
    return iterator.moveNext() ? iterator.current : null;
  }
}
