import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

import 'bfl_api.dart';
import 'gateway.dart';
import 'models.dart';

class WebGateway implements AppGateway {
  WebGateway({http.Client? client, Uri? baseUrl})
    : _client = client ?? http.Client(),
      _baseUrl =
          baseUrl ??
          Uri.parse(
            const String.fromEnvironment(
              'CLAWNSOLE_PROXY_URL',
              defaultValue: 'http://127.0.0.1:8787',
            ),
          );

  final http.Client _client;
  final Uri _baseUrl;

  Uri _url(String path, [Map<String, String>? query]) =>
      _baseUrl.resolve(path).replace(queryParameters: query);

  @override
  bool get usesCompanion => true;

  @override
  String get persistenceDescription =>
      'Local companion JSON file (browser storage is not used)';

  Future<Object?> _read(http.Response response) async {
    Object? payload;
    try {
      payload = jsonDecode(response.body);
    } on FormatException {
      payload = response.body;
    }
    if (response.statusCode >= 200 && response.statusCode < 300) return payload;
    final message = payload is Map<Object?, Object?>
        ? payload['error']?.toString()
        : null;
    throw ProviderException(
      message ??
          'The local Clawnsole companion returned ${response.statusCode}.',
      status: response.statusCode,
      details: payload,
    );
  }

  Map<String, Object?> _map(Object? value) {
    if (value is! Map<Object?, Object?>) {
      throw const ProviderException(
        'The local companion returned invalid data.',
      );
    }
    return value.map((key, child) => MapEntry(key.toString(), child));
  }

  Future<LocalSnapshot> _snapshot(http.Response response) async =>
      LocalSnapshot.fromJson(_map(await _read(response)));

  @override
  Future<LocalSnapshot> load() async =>
      _snapshot(await _client.get(_url('/state')));

  Future<LocalSnapshot> _action(String action, [Object? value]) async =>
      _snapshot(
        await _client.patch(
          _url('/state'),
          headers: const <String, String>{'Content-Type': 'application/json'},
          body: jsonEncode(<String, Object?>{'action': action, 'value': value}),
        ),
      );

  @override
  Future<LocalSnapshot> setApiKey(String value) => _action('setApiKey', value);

  @override
  Future<double> verifyKey([String? candidate]) async {
    final payload = _map(
      await _read(
        await _client.post(
          _url('/credits'),
          headers: const <String, String>{'Content-Type': 'application/json'},
          body: jsonEncode(<String, Object?>{
            if (candidate?.trim().isNotEmpty == true)
              'apiKey': candidate!.trim(),
          }),
        ),
      ),
    );
    final credits = payload['credits'];
    if (credits is! num) {
      throw const ProviderException('Invalid credit balance.');
    }
    return credits.toDouble();
  }

  @override
  Future<double> getCredits() => verifyKey();

  @override
  Future<LocalSnapshot> setPreferences(AppPreferences preferences) =>
      _action('setPreferences', preferences.toJson());

  @override
  Future<Generation> submit(GenerationSubmission submission) async {
    final payload = _map(
      await _read(
        await _client.post(
          _url('/generations'),
          headers: const <String, String>{'Content-Type': 'application/json'},
          body: jsonEncode(<String, Object?>{
            'provider': 'bfl',
            'input': submission.input,
            'record': submission.record.toJson(),
          }),
        ),
      ),
    );
    return Generation.fromJson(_map(payload['generation']));
  }

  @override
  Future<Generation> poll(Generation generation) async {
    final payload = _map(
      await _read(
        await _client.post(
          _url('/generations/status'),
          headers: const <String, String>{'Content-Type': 'application/json'},
          body: jsonEncode(<String, Object?>{
            'provider': 'bfl',
            'localId': generation.localId,
            'pollingUrl': generation.pollingUrl,
          }),
        ),
      ),
    );
    return Generation.fromJson(_map(payload['generation']));
  }

  @override
  Future<LocalSnapshot> deleteGeneration(String localId) async => _snapshot(
    await _client.delete(_url('/generations', <String, String>{'id': localId})),
  );

  @override
  Future<LocalSnapshot> clearHistory() => _action('clearHistory');

  @override
  Future<LocalSnapshot> clearPreferences() => _action('clearPreferences');

  @override
  Future<LocalSnapshot> clearApiKey() => _action('clearApiKey');

  @override
  Future<LocalSnapshot> clearAll() => _action('clearAll');

  @override
  Future<Uri> assetUri(AssetReference reference) async => reference.isLocal
      ? _url('/assets', <String, String>{'id': reference.value})
      : Uri.parse(reference.value);

  @override
  Future<Uint8List> readAsset(AssetReference reference) async {
    final response = await _client.get(await assetUri(reference));
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw ProviderException(
        'The retained input is unavailable.',
        status: response.statusCode,
      );
    }
    return response.bodyBytes;
  }

  @override
  Uri mediaUri(String source) =>
      _url('/media', <String, String>{'url': source});

  @override
  Future<Uint8List> downloadMedia(String source) async {
    final response = await _client.get(mediaUri(source));
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw ProviderException(
        'This BFL delivery link is no longer available.',
        status: response.statusCode,
      );
    }
    return response.bodyBytes;
  }
}
