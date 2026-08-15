import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:clawnsole/core/bfl_api.dart';
import 'package:clawnsole/core/models.dart';
import 'package:clawnsole/core/pricing.dart';

Future<void> main(List<String> arguments) async {
  final config = CompanionConfig.from(arguments, Platform.environment);
  final store = CompanionStore(File(config.dataFile));
  final app = CompanionApp(store: store, api: BflApi());
  final server = await HttpServer.bind(
    InternetAddress.loopbackIPv4,
    config.port,
  );
  stdout.writeln(
    'Clawnsole companion is listening on http://127.0.0.1:${server.port}',
  );
  stdout.writeln('Local data: ${config.dataFile}');
  stdout.writeln('Press Ctrl+C to stop.');
  await for (final request in server) {
    unawaited(app.handle(request));
  }
}

class CompanionConfig {
  const CompanionConfig({required this.port, required this.dataFile});

  final int port;
  final String dataFile;

  factory CompanionConfig.from(
    List<String> arguments,
    Map<String, String> environment,
  ) {
    var port = int.tryParse(environment['CLAWNSOLE_PROXY_PORT'] ?? '') ?? 8787;
    var dataFile = environment['CLAWNSOLE_FLUTTER_DATA_FILE']?.trim() ?? '';
    for (var index = 0; index < arguments.length; index += 1) {
      if (arguments[index] == '--port' && index + 1 < arguments.length) {
        port = int.parse(arguments[++index]);
      } else if (arguments[index] == '--data-file' &&
          index + 1 < arguments.length) {
        dataFile = arguments[++index];
      }
    }
    if (dataFile.isEmpty) {
      dataFile =
          '${Directory.current.path}${Platform.pathSeparator}.clawnsole'
          '${Platform.pathSeparator}clawnsole-flutter.json';
    }
    return CompanionConfig(port: port, dataFile: File(dataFile).absolute.path);
  }
}

class CompanionStore {
  CompanionStore(this.file);

  final File file;
  Future<void> _queue = Future<void>.value();

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
    });
    _queue = operation.then<void>((_) {}, onError: (_) {});
    return operation;
  }

  Future<StorageStats> stats(int records) async {
    await _queue;
    if (!await file.exists()) {
      return StorageStats(path: file.path, bytes: 0, records: records);
    }
    final value = await file.stat();
    return StorageStats(
      path: file.path,
      bytes: value.size,
      records: records,
      lastUpdated: value.modified,
    );
  }
}

class StoreChange<T> {
  const StoreChange(this.data, this.result);

  final StoredData data;
  final T result;
}

class CompanionApp {
  CompanionApp({required CompanionStore store, required BflApi api})
    : _store = store,
      _api = api;

  final CompanionStore _store;
  final BflApi _api;

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
        return _json(request.response, 200, <String, Object?>{'ok': true});
      }
      if (request.method == 'GET' && path == '/state') {
        return _json(request.response, 200, (await _snapshot()).toJson());
      }
      if (request.method == 'PATCH' && path == '/state') {
        final body = await _bodyMap(request);
        await _stateAction(body['action']?.toString() ?? '', body['value']);
        return _json(request.response, 200, (await _snapshot()).toJson());
      }
      if (request.method == 'POST' && path == '/credits') {
        final body = await _bodyMap(request);
        final saved = (await _store.read()).apiKey.trim();
        final candidate = body['apiKey']?.toString().trim();
        final key = candidate?.isNotEmpty == true ? candidate! : saved;
        if (key.isEmpty) throw StateError('An API key is required.');
        final credits = await _api.getCredits(key);
        return _json(request.response, 200, <String, Object?>{
          'credits': credits,
        });
      }
      if (request.method == 'POST' && path == '/generations') {
        final generation = await _submit(await _bodyMap(request));
        return _json(request.response, 201, <String, Object?>{
          'generation': generation.toJson(),
        });
      }
      if (request.method == 'POST' && path == '/generations/status') {
        final generation = await _poll(await _bodyMap(request));
        return _json(request.response, 200, <String, Object?>{
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
        return _json(request.response, 200, (await _snapshot()).toJson());
      }
      if (request.method == 'GET' && path == '/media') {
        return _media(request);
      }
      return _json(request.response, 404, <String, Object?>{
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
        next = current.copyWith(apiKey: key);
      } else if (action == 'setPreferences') {
        final map = value is Map<Object?, Object?>
            ? value.map((key, child) => MapEntry(key.toString(), child))
            : <String, Object?>{};
        next = current.copyWith(preferences: AppPreferences.fromJson(map));
      } else if (action == 'clearHistory') {
        next = current.copyWith(generations: <Generation>[]);
      } else if (action == 'clearPreferences') {
        next = current.copyWith(preferences: const AppPreferences());
      } else if (action == 'clearApiKey') {
        next = current.copyWith(apiKey: '');
      } else {
        throw const ProviderException(
          'Unknown local data action.',
          status: 400,
        );
      }
      return StoreChange<void>(next, null);
    });
  }

  Future<LocalSnapshot> _snapshot() async {
    var data = await _store.read();
    final now = DateTime.now().toUtc();
    var changed = false;
    final generations = data.generations.map((item) {
      if (item.deliveryExpiresAt == null ||
          item.deliveryExpiresAt!.isAfter(now) ||
          (item.resultUrl == null && item.draftCacheUrl == null)) {
        return item;
      }
      changed = true;
      final json = item.toJson()
        ..remove('resultUrl')
        ..remove('draftCacheUrl')
        ..['deliveryExpired'] = true;
      return Generation.fromJson(json);
    }).toList();
    if (changed) {
      data = data.copyWith(generations: generations);
      await _store.replace(data);
    }
    return LocalSnapshot(
      generations: data.generations,
      preferences: data.preferences,
      hasApiKey: data.apiKey.trim().isNotEmpty,
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

  Future<double?> _creditsSafely(String key) async {
    try {
      return await _api.getCredits(key);
    } on Object {
      return null;
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
    final key = data.apiKey.trim();
    if (key.isEmpty) throw StateError('Add a BFL API key before generating.');
    var generation = Generation.fromJson(
      rawRecord.map((key, value) => MapEntry(key.toString(), value)),
    );
    final estimate = estimateCredits(
      generation.mode,
      generation.config,
      data.generations,
    );
    generation = generation.copyWith(
      status: 'submitting',
      estimatedCreditsMin: estimate.minimum,
      estimatedCreditsMax: estimate.maximum,
      estimateBasis: estimate.basis,
      updatedAt: DateTime.now().toUtc(),
    );
    await _upsert(generation);
    try {
      final creditsBefore = await _creditsSafely(key);
      if (creditsBefore != null) {
        generation = generation.copyWith(creditsBefore: creditsBefore);
        await _upsert(generation);
      }
      final receipt = await _api.submit(
        key,
        input.map((key, value) => MapEntry(key.toString(), value)),
      );
      final requestId = receipt['id'];
      final pollingUrl = receipt['polling_url'];
      if (requestId is! String || pollingUrl is! String) {
        throw const ProviderException(
          'BFL returned an invalid generation receipt.',
          status: 502,
        );
      }
      final cost = (receipt['cost'] as num?)?.toDouble();
      final liveAfter = await _creditsSafely(key);
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
        updatedAt: DateTime.now().toUtc(),
      );
      await _upsert(generation);
      return generation;
    } on Object catch (error) {
      generation = generation.copyWith(
        status: 'Error',
        error: error.toString(),
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
    final key = data.apiKey.trim();
    if (key.isEmpty) throw StateError('The saved BFL API key is missing.');
    final current = data.generations
        .where((item) => item.localId == localId)
        .firstOrNull;
    if (current == null) {
      throw const ProviderException(
        'The generation was not found.',
        status: 404,
      );
    }
    final payload = await _api.poll(key, pollingUrl);
    final rawStatus = payload['status'] as String? ?? 'Pending';
    final terminal = const <String>{
      'Ready',
      'Error',
      'Failed',
      'Request Moderated',
      'Content Moderated',
    };
    final status = terminal.contains(rawStatus) ? rawStatus : 'Pending';
    final failed = status != 'Ready' && status != 'Pending';
    final next = current.copyWith(
      status: status,
      progress: status == 'Ready'
          ? 100
          : normalizedProgress(payload['progress']),
      resultUrl: status == 'Ready'
          ? findResultUrl(payload['result'], draft: false)
          : null,
      draftCacheUrl: status == 'Ready'
          ? findResultUrl(payload['result'], draft: true)
          : null,
      deliveryExpiresAt: status == 'Ready'
          ? DateTime.now().toUtc().add(const Duration(minutes: 10))
          : null,
      error: failed
          ? jsonEncode(payload['details'] ?? payload['result'] ?? status)
          : null,
      clearError: !failed,
      updatedAt: DateTime.now().toUtc(),
    );
    await _upsert(next);
    return next;
  }

  Future<void> _media(HttpRequest request) async {
    final source = request.uri.queryParameters['url'];
    if (source == null) {
      throw const ProviderException('A media URL is required.', status: 400);
    }
    final target = validatedBflUrl(source);
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

  Future<void> _json(
    HttpResponse response,
    int status,
    Map<String, Object?> payload,
  ) async {
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
