import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

import 'bfl_api.dart';
import 'gateway.dart';
import 'models.dart';

Uri _configuredBaseUrl(Uri? override) {
  if (override != null) return override;
  const configured = String.fromEnvironment(
    'CLAWNSOLE_PROXY_URL',
    defaultValue: 'http://127.0.0.1:8787',
  );
  return configured.trim().isEmpty ? Uri.base : Uri.parse(configured);
}

class WebGateway
    implements
        AppGateway,
        ProviderGateway,
        LibraryOrganizationGateway,
        ReferenceLibraryGateway {
  WebGateway({http.Client? client, Uri? baseUrl})
    : _client = client ?? http.Client(),
      _baseUrl = _configuredBaseUrl(baseUrl);

  final http.Client _client;
  final Uri _baseUrl;

  Uri _url(String path, [Map<String, String>? query]) =>
      _baseUrl.resolve(path).replace(queryParameters: query);

  @override
  bool get usesCompanion => true;

  @override
  bool get supportsPhotoLibrarySave => false;

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
  Future<LocalSnapshot> setProviderApiKey(String provider, String value) =>
      _action('setProviderApiKey', <String, Object?>{
        'provider': provider,
        'apiKey': value,
      });

  @override
  Future<double> verifyKey([String? candidate]) async {
    final account = await verifyProviderKey('bfl', candidate);
    return account.balance ?? 0;
  }

  @override
  Future<ProviderAccountStatus> verifyProviderKey(
    String provider, [
    String? candidate,
  ]) async {
    final supplied = candidate?.trim().isNotEmpty == true;
    try {
      final payload = _map(
        await _read(
          await _client.post(
            _url('/account'),
            headers: const <String, String>{'Content-Type': 'application/json'},
            body: jsonEncode(<String, Object?>{
              if (supplied) 'apiKey': candidate!.trim(),
              'provider': provider,
            }),
          ),
        ),
      );
      return ProviderAccountStatus.fromJson(payload);
    } on Object catch (error) {
      if (!supplied &&
          (providerHttpStatus(error) == 401 ||
              providerHttpStatus(error) == 403)) {
        await clearProviderApiKey(provider);
      }
      rethrow;
    }
  }

  @override
  Future<double> getCredits() => verifyKey();

  @override
  Future<ProviderAccountStatus> getProviderAccount(String provider) =>
      verifyProviderKey(provider);

  @override
  Future<List<ProviderModelPrice>> listProviderModels(String provider) async {
    final payload = await _read(
      await _client.get(
        _url('/providers/models', <String, String>{'provider': provider}),
      ),
    );
    if (payload is! List<Object?>) {
      throw const ProviderException('Invalid provider model catalog.');
    }
    return payload
        .whereType<Map<Object?, Object?>>()
        .map(
          (item) => ProviderModelPrice.fromJson(
            item.map((key, value) => MapEntry(key.toString(), value)),
          ),
        )
        .toList();
  }

  @override
  Future<LocalSnapshot> setPreferences(AppPreferences preferences) =>
      _action('setPreferences', preferences.toJson());

  @override
  Future<LocalSnapshot> saveLibraryFolder(LibraryFolder folder) =>
      _action('saveLibraryFolder', folder.toJson());

  @override
  Future<LocalSnapshot> deleteLibraryFolder(String folderId) =>
      _action('deleteLibraryFolder', folderId);

  @override
  Future<LocalSnapshot> setGenerationOrganization(
    String localId, {
    String? folderId,
    required List<String> tags,
  }) => _action('setGenerationOrganization', <String, Object?>{
    'localId': localId,
    'folderId': folderId,
    'tags': tags,
  });

  @override
  Future<LocalSnapshot> saveReference(
    SavedReference reference, {
    String? source,
  }) => _action('saveReference', <String, Object?>{
    'reference': reference.toJson(),
    if (source != null) 'source': source,
  });

  @override
  Future<LocalSnapshot> deleteReference(String referenceId) =>
      _action('deleteReference', referenceId);

  @override
  Future<Generation> submit(GenerationSubmission submission) async {
    try {
      final payload = _map(
        await _read(
          await _client.post(
            _url('/generations'),
            headers: const <String, String>{'Content-Type': 'application/json'},
            body: jsonEncode(<String, Object?>{
              'provider': submission.record.provider,
              'input': submission.input,
              'record': submission.record.toJson(),
            }),
          ),
        ),
      );
      return Generation.fromJson(_map(payload['generation']));
    } on Object catch (error) {
      if (providerHttpStatus(error) == 401 ||
          providerHttpStatus(error) == 403) {
        await clearProviderApiKey(submission.record.provider);
      }
      rethrow;
    }
  }

  @override
  Future<Generation> poll(Generation generation) async {
    final payload = _map(
      await _read(
        await _client.post(
          _url('/generations/status'),
          headers: const <String, String>{'Content-Type': 'application/json'},
          body: jsonEncode(<String, Object?>{
            'provider': generation.provider,
            'localId': generation.localId,
            'pollingUrl': generation.pollingUrl,
          }),
        ),
      ),
    );
    final updated = Generation.fromJson(_map(payload['generation']));
    if (updated.lastProviderStatusCode == 401 ||
        updated.lastProviderStatusCode == 403) {
      await clearProviderApiKey(generation.provider);
    }
    return updated;
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
  Future<LocalSnapshot> clearProviderApiKey(String provider) =>
      _action('clearProviderApiKey', provider);

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
        'This provider delivery link is no longer available.',
        status: response.statusCode,
      );
    }
    return response.bodyBytes;
  }

  @override
  Future<void> saveMediaToPhotoLibrary(
    Uint8List bytes,
    String fileName,
    String contentType,
  ) => throw UnsupportedError(
    'Saving directly to Photos is available in the iOS and Android apps.',
  );
}
