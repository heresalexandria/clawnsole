import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:clawnsole/core/bfl_api.dart';
import 'package:clawnsole/core/generation_status.dart';
import 'package:clawnsole/core/models.dart';
import 'package:clawnsole/core/pricing.dart';
import 'package:clawnsole/core/provider_api.dart';
import 'package:clawnsole/core/provider_catalog.dart';

import 'apple_local_process_runtime.dart';

Future<void> main(List<String> arguments) async {
  final config = CompanionConfig.from(arguments, Platform.environment);
  final store = CompanionStore(File(config.dataFile));
  final appleLocal = AppleLocalProcessRuntime(
    config.appleLocalGenerator == null
        ? null
        : Directory(config.appleLocalGenerator!),
  );
  await appleLocal.initialize();
  final app = CompanionApp(
    store: store,
    api: BflApi(),
    fallbackApiKeys: <String, String>{
      'bfl': Platform.environment['BFL_API_KEY']?.trim() ?? '',
      'ltx': Platform.environment['LTX_API_KEY']?.trim() ?? '',
      'artcraft': Platform.environment['ARTCRAFT_KEY']?.trim() ?? '',
      'atlas': Platform.environment['ATLAS_CLOUD_KEY']?.trim() ?? '',
    },
    webRoot: config.webRoot == null ? null : Directory(config.webRoot!),
    appleLocal: appleLocal,
  );
  final server = await HttpServer.bind(
    InternetAddress.loopbackIPv4,
    config.port,
  );
  stdout.writeln(
    'Clawnsole companion is listening on http://127.0.0.1:${server.port}',
  );
  stdout.writeln('Local data: ${config.dataFile}');
  if (config.webRoot != null) stdout.writeln('Web root: ${config.webRoot}');
  if (appleLocal.isAvailable) stdout.writeln('Apple Local: available');
  stdout.writeln('Press Ctrl+C to stop.');
  await for (final request in server) {
    unawaited(app.handle(request));
  }
}

class CompanionConfig {
  const CompanionConfig({
    required this.port,
    required this.dataFile,
    this.webRoot,
    this.appleLocalGenerator,
  });

  final int port;
  final String dataFile;
  final String? webRoot;
  final String? appleLocalGenerator;

  factory CompanionConfig.from(
    List<String> arguments,
    Map<String, String> environment,
  ) {
    var port = int.tryParse(environment['CLAWNSOLE_PROXY_PORT'] ?? '') ?? 8787;
    var dataFile = environment['CLAWNSOLE_FLUTTER_DATA_FILE']?.trim() ?? '';
    var webRoot = environment['CLAWNSOLE_WEB_ROOT']?.trim() ?? '';
    var appleLocalGenerator =
        environment['CLAWNSOLE_APPLE_LOCAL_GENERATOR']?.trim() ?? '';
    for (var index = 0; index < arguments.length; index += 1) {
      if (arguments[index] == '--port' && index + 1 < arguments.length) {
        port = int.parse(arguments[++index]);
      } else if (arguments[index] == '--data-file' &&
          index + 1 < arguments.length) {
        dataFile = arguments[++index];
      } else if (arguments[index] == '--web-root' &&
          index + 1 < arguments.length) {
        webRoot = arguments[++index];
      } else if (arguments[index] == '--apple-local-generator' &&
          index + 1 < arguments.length) {
        appleLocalGenerator = arguments[++index];
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
      appleLocalGenerator: appleLocalGenerator.isEmpty
          ? null
          : File(appleLocalGenerator).absolute.path,
    );
  }
}

class CompanionStore {
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

  File assetFile(String id) {
    if (!RegExp(r'^[a-f0-9-]{16,80}$').hasMatch(id)) {
      throw StateError('The local asset id is invalid.');
    }
    return File('${assets.path}${Platform.pathSeparator}$id.asset');
  }

  Future<AssetReference> writeAsset(
    Uint8List bytes, {
    required String label,
    required String contentType,
  }) async {
    final id = _assetId();
    await assets.create(recursive: true);
    await assetFile(id).writeAsBytes(bytes, flush: true);
    return AssetReference(
      kind: 'local',
      value: id,
      label: label,
      contentType: contentType.split(';').first,
      bytes: bytes.length,
    );
  }

  Future<AssetReference?> persistSource(
    String source, {
    required String label,
    AssetReference? retained,
  }) async {
    if (retained?.isLocal == true) {
      final existing = assetFile(retained!.value);
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

  Set<String> _references(List<Generation> generations) {
    final retained = <String>{};
    void add(AssetReference? reference) {
      if (reference?.isLocal == true) retained.add(reference!.value);
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
    return retained;
  }

  Future<void> pruneAssets(List<Generation> generations) async {
    if (!await assets.exists()) return;
    final retained = _references(generations);
    await for (final entry in assets.list()) {
      if (entry is! File) continue;
      final name = entry.uri.pathSegments.last;
      final id = name.endsWith('.asset')
          ? name.substring(0, name.length - 6)
          : '';
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

  Future<void> delete() {
    final operation = _queue.then((_) async {
      if (await file.exists()) await file.delete();
      await clearAssets();
    });
    _queue = operation.then<void>((_) {}, onError: (_) {});
    return operation;
  }

  Future<StorageStats> stats(int records) async {
    await _queue;
    var assetBytes = 0;
    var assetCount = 0;
    if (await assets.exists()) {
      await for (final entry in assets.list()) {
        if (entry is! File || !entry.path.endsWith('.asset')) continue;
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
}

class StoreChange<T> {
  const StoreChange(this.data, this.result);

  final StoredData data;
  final T result;
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
  CompanionApp({
    required CompanionStore store,
    required BflApi api,
    ProviderApiRouter? providerRouter,
    Map<String, String> fallbackApiKeys = const <String, String>{},
    Directory? webRoot,
    AppleLocalProcessRuntime? appleLocal,
  }) : _store = store,
       _providers = providerRouter ?? ProviderApiRouter(bfl: api),
       _fallbackApiKeys = fallbackApiKeys,
       _webRoot = webRoot,
       _appleLocal = appleLocal ?? AppleLocalProcessRuntime(null);

  final CompanionStore _store;
  final ProviderApiRouter _providers;
  final Map<String, String> _fallbackApiKeys;
  final Directory? _webRoot;
  final AppleLocalProcessRuntime _appleLocal;

  Future<void> handle(HttpRequest request) async {
    final origin = request.headers.value('origin');
    if (!_allowOrigin(origin)) {
      return _json(request.response, 403, <String, Object?>{
        'error': 'The Clawnsole companion only accepts local browser origins.',
      });
    }
    _cors(request.response, origin);
    if (request.method == 'OPTIONS') {
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
      if (request.method == 'GET' && path == '/state') {
        return await _json(request.response, 200, (await _snapshot()).toJson());
      }
      if (request.method == 'PATCH' && path == '/state') {
        final body = await _bodyMap(request);
        await _stateAction(body['action']?.toString() ?? '', body['value']);
        return await _json(request.response, 200, (await _snapshot()).toJson());
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
        await _store.pruneAssets((await _store.read()).generations);
        return await _json(request.response, 200, (await _snapshot()).toJson());
      }
      if (request.method == 'GET' && path == '/assets') {
        return await _asset(request);
      }
      if (request.method == 'GET' && path == '/media') {
        return await _media(request);
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
    final uri = Uri.tryParse(origin);
    return uri != null &&
        (uri.scheme == 'http' || uri.scheme == 'https') &&
        (uri.host == 'localhost' ||
            uri.host == '127.0.0.1' ||
            uri.host == '::1');
  }

  void _cors(HttpResponse response, String? origin) {
    if (origin != null) {
      response.headers.set(HttpHeaders.accessControlAllowOriginHeader, origin);
      response.headers.set(HttpHeaders.varyHeader, 'Origin');
    }
    response.headers.set(
      HttpHeaders.accessControlAllowMethodsHeader,
      'GET, POST, PATCH, DELETE, OPTIONS',
    );
    response.headers.set(
      HttpHeaders.accessControlAllowHeadersHeader,
      'Content-Type, Range',
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

  Future<void> _stateAction(String action, Object? value) async {
    if (action == 'clearAll') return _store.delete();
    await _store.mutate<void>((current) {
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
        next = current.copyWith(preferences: AppPreferences.fromJson(map));
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
            !current.folders.any((item) => item.id == parentId)) {
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
        );
      } else if (action == 'setGenerationOrganization') {
        final map = value is Map<Object?, Object?> ? value : const {};
        final localId = map['localId']?.toString() ?? '';
        final rawFolderId = map['folderId']?.toString().trim() ?? '';
        final folderId = rawFolderId.isEmpty ? null : rawFolderId;
        if (folderId != null &&
            !current.folders.any((folder) => folder.id == folderId)) {
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
      } else if (action == 'clearHistory') {
        next = current.copyWith(generations: <Generation>[]);
      } else if (action == 'clearPreferences') {
        next = current.copyWith(
          preferences: _appleLocal.isAvailable
              ? const AppPreferences(
                  provider: 'apple-local',
                  model: 'apple-local-image',
                )
              : const AppPreferences(),
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
    if (action == 'clearHistory') await _store.clearAssets();
  }

  Future<LocalSnapshot> _snapshot() async {
    var data = await _store.read();
    if (_appleLocal.isAvailable && !await _store.exists()) {
      data = data.copyWith(
        preferences: const AppPreferences(
          provider: 'apple-local',
          model: 'apple-local-image',
        ),
      );
      await _store.replace(data);
    }
    final now = DateTime.now().toUtc();
    var changed = false;
    final generations = data.generations.map((item) {
      var next = item.recoverInterruptedSubmission(now);
      if (!identical(next, item)) changed = true;
      if (next.deliveryExpiresAt == null ||
          next.deliveryExpiresAt!.isAfter(now) ||
          (next.resultUrl == null && next.draftCacheUrl == null)) {
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
    if (_appleLocal.isAvailable) connected.add('apple-local');
    return LocalSnapshot(
      generations: data.generations,
      folders: data.folders,
      preferences: data.preferences,
      hasApiKey: connected.contains('bfl'),
      connectedProviders: connected,
      availableProviders: <String>{
        'bfl',
        'ltx',
        'artcraft',
        'atlas',
        if (_appleLocal.isAvailable) 'apple-local',
      },
      storage: await _store.stats(data.generations.length),
    );
  }

  Future<void> _upsert(Generation generation) async {
    await _store.mutate<void>((current) {
      final generations = List<Generation>.from(current.generations);
      final index = generations.indexWhere(
        (item) => item.localId == generation.localId,
      );
      if (index >= 0) {
        generations[index] = generation;
      } else {
        generations.insert(0, generation);
      }
      return StoreChange<void>(
        current.copyWith(generations: generations),
        null,
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
            source: await _store.persistSource(
              index < rawFrames.length ? _keyframeSource(rawFrames[index]) : '',
              label: frame.label,
              retained: frame.source,
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
            source: await _store.persistSource(
              index < sources.length ? sources[index]?.toString() ?? '' : '',
              label: media.label,
              retained: media.source,
            ),
          ),
        );
      }
      return config.copyWith(keyframes: frames, references: references);
    }
    if (mode == 'v2v' || mode == 'draft_enhance') {
      return config.copyWith(
        source: await _store.persistSource(
          input[mode == 'v2v' ? 'start_video' : 'draft_cache']?.toString() ??
              '',
          label: config.sourceLabel ?? 'Clawnsole source',
          retained: config.source,
        ),
      );
    }
    return config;
  }

  Future<AssetReference?> _retainResult(String source, String label) async {
    final target = validatedProviderUrl(source);
    final client = HttpClient();
    try {
      final upstream = await (await client.getUrl(target)).close();
      if (upstream.statusCode < 200 || upstream.statusCode >= 300) return null;
      final builder = BytesBuilder(copy: false);
      await for (final chunk in upstream) {
        builder.add(chunk);
      }
      return await _store.writeAsset(
        builder.takeBytes(),
        label: label,
        contentType: upstream.headers.contentType?.mimeType ?? 'video/mp4',
      );
    } finally {
      client.close(force: true);
    }
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
    final cleanInput = input.map(
      (key, value) => MapEntry(key.toString(), value),
    );
    final provider = generation.provider;
    if (provider == 'apple-local') {
      return _submitAppleLocal(generation, cleanInput);
    }
    final key = _activeKey(data, provider);
    if (key.isEmpty) {
      throw StateError(
        'Add a ${providerById(provider).name} API key before generating.',
      );
    }
    generation = generation.copyWith(
      config: await _persistInputs(generation.config, cleanInput),
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
      estimatedCreditsMin:
          generation.estimatedCreditsMin ??
          estimate.providerUnitsMinimum ??
          estimate.minimumUsd,
      estimatedCreditsMax:
          generation.estimatedCreditsMax ??
          estimate.providerUnitsMaximum ??
          estimate.maximumUsd,
      estimateBasis: generation.estimateBasis ?? estimate.basis,
      updatedAt: DateTime.now().toUtc(),
    );
    await _upsert(generation);
    try {
      final creditsBefore = await _balanceSafely(provider, key);
      if (creditsBefore != null) {
        generation = generation.copyWith(creditsBefore: creditsBefore);
        await _upsert(generation);
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
      final cost = (receipt['cost'] as num?)?.toDouble();
      final liveAfter = await _balanceSafely(provider, key);
      generation = generation.copyWith(
        requestId: requestId,
        pollingUrl: pollingUrl,
        status: 'Pending',
        clearProgress: true,
        cost: cost,
        clearCost: cost == null,
        creditsBefore: creditsBefore,
        creditsAfter:
            liveAfter ??
            (creditsBefore != null && cost != null
                ? (creditsBefore - cost).clamp(0, double.infinity)
                : null),
        lastProviderStatusCode: 200,
        lastProviderResponse: compactProviderResponse(receipt),
        lastProviderResponseAt: DateTime.now().toUtc(),
        updatedAt: DateTime.now().toUtc(),
      );
      await _upsert(generation);
      return generation;
    } on Object catch (error) {
      generation = generation.copyWith(
        status: 'Error',
        error: generationExceptionMessage(error),
        lastProviderStatusCode: providerHttpStatus(error),
        lastProviderResponse: providerErrorResponse(error),
        lastProviderResponseAt: DateTime.now().toUtc(),
        updatedAt: DateTime.now().toUtc(),
      );
      await _upsert(generation);
      rethrow;
    }
  }

  Future<Generation> _submitAppleLocal(
    Generation generation,
    Map<String, Object?> input,
  ) async {
    if (!generation.isImage || generation.model != 'apple-local-image') {
      throw StateError(
        'Apple Local animation is no longer available. Choose another video provider.',
      );
    }
    if (!_appleLocal.isAvailable) {
      throw StateError('Apple Local generation is unavailable on this Mac.');
    }
    generation = generation.copyWith(
      config: await _persistInputs(generation.config, input),
      updatedAt: DateTime.now().toUtc(),
    );
    await _upsert(generation);
    try {
      String? referenceImagePath;
      final frames = generation.config.keyframes;
      final reference = frames == null || frames.isEmpty
          ? null
          : frames.first.source;
      if (reference != null) {
        if (!reference.isLocal) {
          throw StateError(
            'Apple Local reference images must be uploaded from this Mac.',
          );
        }
        referenceImagePath = _store.assetFile(reference.value).path;
      }
      final jobDirectory = Directory(
        '${_store.file.parent.path}${Platform.pathSeparator}apple-local'
        '${Platform.pathSeparator}jobs${Platform.pathSeparator}${generation.localId}',
      );
      final modelsDirectory = Directory(
        '${_store.file.parent.path}${Platform.pathSeparator}apple-local'
        '${Platform.pathSeparator}models',
      );
      final duration = generation.config.duration is num
          ? (generation.config.duration as num).toInt()
          : 1;
      final receipt = await _appleLocal.submit(<String, Object?>{
        'requestId': generation.localId,
        'mode': 'image',
        'prompt': generation.prompt,
        'aspectRatio': generation.config.aspectRatio,
        'resolution': generation.config.resolution,
        'durationSeconds': duration,
        'frameRate': generation.config.frameRate,
        if (referenceImagePath != null)
          'referenceImagePath': referenceImagePath,
        'outputDirectory': jobDirectory.path,
        'modelsDirectory': modelsDirectory.path,
      });
      final jobId = receipt['jobId']?.toString();
      if (jobId == null || jobId.isEmpty) {
        throw StateError('Apple Local returned an invalid generation receipt.');
      }
      generation = generation.copyWith(
        requestId: jobId,
        pollingUrl: 'apple-local://$jobId',
        status: 'Pending',
        progress: 0,
        lastProviderStatusCode: 200,
        lastProviderResponse: jsonEncode(receipt),
        lastProviderResponseAt: DateTime.now().toUtc(),
        updatedAt: DateTime.now().toUtc(),
      );
      await _upsert(generation);
      return generation;
    } on Object catch (error) {
      generation = generation.copyWith(
        status: 'Error',
        error: generationExceptionMessage(error),
        updatedAt: DateTime.now().toUtc(),
      );
      await _upsert(generation);
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
      return _pollAppleLocal(current);
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
      var status = normalizeGenerationStatus(payload['status']);
      final result = payload['result'] ?? payload['outputs'] ?? payload;
      final resultUrl = status == 'Ready'
          ? findResultUrl(result, draft: false)
          : null;
      var failureMessage = isGenerationFailureStatus(status)
          ? providerNamedFailureMessage(
              providerById(current.provider).name,
              payload,
              fallback: status,
            )
          : null;
      if (status == 'Ready' && resultUrl == null) {
        status = 'Error';
        failureMessage =
            '${providerById(current.provider).name} reported that the generation was ready but did not include a video URL.';
      }
      var resultAsset = current.resultAsset;
      if (resultUrl != null && resultAsset == null) {
        try {
          resultAsset = await _retainResult(
            resultUrl,
            'clawnsole-${current.localId}.mp4',
          );
        } on Object {
          // The temporary BFL URL remains usable if local retention fails.
        }
      }
      final failed = isGenerationFailureStatus(status);
      next = current.copyWith(
        status: status,
        progress: status == 'Ready'
            ? 100
            : normalizedProgress(payload['progress']),
        resultUrl: resultUrl,
        resultAsset: resultAsset,
        deliveryExpired: status == 'Ready' ? false : current.deliveryExpired,
        draftCacheUrl: status == 'Ready'
            ? findResultUrl(result, draft: true)
            : null,
        deliveryExpiresAt: status == 'Ready'
            ? checkedAt.add(const Duration(minutes: 10))
            : null,
        error: failureMessage,
        clearError: !failed,
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
      final payload = providerErrorPayload(error);
      final providerStatus = normalizeGenerationStatus(payload?['status']);
      if (payload != null && isGenerationFailureStatus(providerStatus)) {
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
          lastProviderStatusCode: providerHttpStatus(error),
          lastProviderResponse: providerErrorResponse(error),
          lastProviderResponseAt: checkedAt,
          updatedAt: checkedAt,
        );
      }
    }
    await _upsert(next);
    return next;
  }

  Future<Generation> _pollAppleLocal(Generation current) async {
    final checkedAt = DateTime.now().toUtc();
    try {
      final jobId = current.requestId;
      if (jobId == null || jobId.isEmpty) {
        throw StateError('This Apple Local generation has no job id.');
      }
      final payload = _appleLocal.poll(jobId);
      final status = normalizeGenerationStatus(payload['status']);
      var resultAsset = current.resultAsset;
      if (status == 'Ready' && resultAsset == null) {
        final resultPath = payload['resultPath']?.toString();
        if (resultPath == null || resultPath.isEmpty) {
          throw StateError(
            'Apple Local finished without returning a media file.',
          );
        }
        final file = File(resultPath);
        final contentType =
            payload['contentType']?.toString() ??
            (current.isImage ? 'image/png' : 'video/mp4');
        resultAsset = await _store.writeAsset(
          await file.readAsBytes(),
          label:
              'clawnsole-${current.localId}.${current.isImage ? 'png' : 'mp4'}',
          contentType: contentType,
        );
        try {
          await file.parent.delete(recursive: true);
        } on FileSystemException {
          // A later cleanup can remove an already-consumed job directory.
        }
      }
      final failed = isGenerationFailureStatus(status);
      final next = current.copyWith(
        status: status,
        progress: status == 'Ready'
            ? 100
            : normalizedProgress(payload['progress']),
        resultAsset: resultAsset,
        error: failed ? payload['error']?.toString() ?? status : null,
        clearError: !failed,
        lastCheckedAt: checkedAt,
        statusCheckCount: current.statusCheckCount + 1,
        consecutiveCheckFailures: 0,
        clearLastCheckError: true,
        lastProviderStatusCode: 200,
        lastProviderResponse: compactProviderResponse(<String, Object?>{
          'status': status,
          'progress': payload['progress'],
          if (payload['message'] != null) 'message': payload['message'],
          if (payload['error'] != null) 'error': payload['error'],
        }),
        lastProviderResponseAt: checkedAt,
        updatedAt: checkedAt,
      );
      await _upsert(next);
      return next;
    } on Object catch (error) {
      final next = current.copyWith(
        lastCheckedAt: checkedAt,
        statusCheckCount: current.statusCheckCount + 1,
        consecutiveCheckFailures: current.consecutiveCheckFailures + 1,
        lastCheckError: generationExceptionMessage(error),
        updatedAt: checkedAt,
      );
      await _upsert(next);
      return next;
    }
  }

  AssetReference? _findAsset(List<Generation> generations, String id) {
    for (final generation in generations) {
      final references = <AssetReference?>[
        generation.resultAsset,
        generation.config.source,
        ...(generation.config.keyframes ?? const <KeyframeLabel>[]).map(
          (frame) => frame.source,
        ),
        ...(generation.config.references ?? const <MediaReferenceLabel>[]).map(
          (media) => media.source,
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

  Future<void> _asset(HttpRequest request) async {
    final id = request.uri.queryParameters['id'];
    if (id == null) {
      throw const ProviderException(
        'A local asset id is required.',
        status: 400,
      );
    }
    final reference = _findAsset((await _store.read()).generations, id);
    if (reference == null) {
      throw const ProviderException(
        'The local asset was not found.',
        status: 404,
      );
    }
    final file = _store.assetFile(id);
    if (!await file.exists()) {
      throw const ProviderException(
        'The local asset file is missing.',
        status: 404,
      );
    }
    final size = await file.length();
    var start = 0;
    var end = size - 1;
    final range = request.headers.value(HttpHeaders.rangeHeader);
    final match = range == null
        ? null
        : RegExp(r'^bytes=(\d*)-(\d*)$').firstMatch(range);
    if (match != null) {
      final parsedStart = int.tryParse(match.group(1) ?? '');
      final parsedEnd = int.tryParse(match.group(2) ?? '');
      if (parsedStart == null && parsedEnd != null) {
        start = max(0, size - parsedEnd);
      } else if (parsedStart != null) {
        start = parsedStart;
      }
      if (parsedEnd != null && parsedStart != null) end = min(parsedEnd, end);
      if (start < 0 || start >= size || end < start) {
        request.response.statusCode = HttpStatus.requestedRangeNotSatisfiable;
        request.response.headers.set(
          HttpHeaders.contentRangeHeader,
          'bytes */$size',
        );
        return request.response.close();
      }
      request.response
        ..statusCode = HttpStatus.partialContent
        ..headers.set(
          HttpHeaders.contentRangeHeader,
          'bytes $start-$end/$size',
        );
    }
    request.response.headers
      ..contentType = ContentType.parse(
        reference.contentType ?? 'application/octet-stream',
      )
      ..set(HttpHeaders.acceptRangesHeader, 'bytes')
      ..contentLength = end - start + 1;
    await file.openRead(start, end + 1).pipe(request.response);
  }

  Future<void> _media(HttpRequest request) async {
    final source = request.uri.queryParameters['url'];
    if (source == null) {
      throw const ProviderException('A media URL is required.', status: 400);
    }
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

extension<T> on Iterable<T> {
  T? get firstOrNull {
    final iterator = this.iterator;
    return iterator.moveNext() ? iterator.current : null;
  }
}
