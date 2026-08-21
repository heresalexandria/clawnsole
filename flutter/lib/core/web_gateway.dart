import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

import 'bfl_api.dart';
import 'gateway.dart';
import 'google_drive.dart';
import 'google_drive_auth.dart';
import 'models.dart';
import 'settings_vault_gateway.dart';
import 'settings_vault_shell.dart';

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
        ReferenceLibraryGateway,
        FavoriteGateway,
        VisibilityGateway,
        GenerationPreviewGateway,
        MediaPreviewGateway,
        GoogleDriveGateway,
        SettingsVaultGateway {
  WebGateway({
    http.Client? client,
    Uri? baseUrl,
    GoogleDriveAuthorizer? driveAuthorizer,
    SettingsVaultShellInvoker? settingsVaultInvoker,
  }) : _client = client ?? http.Client(),
       _baseUrl = _configuredBaseUrl(baseUrl),
       _driveAuthorizer = driveAuthorizer ?? createGoogleDriveAuthorizer(),
       _settingsVaultInvoker = settingsVaultInvoker ?? invokeSettingsVaultShell;

  final http.Client _client;
  final Uri _baseUrl;
  final GoogleDriveAuthorizer _driveAuthorizer;
  final SettingsVaultShellInvoker _settingsVaultInvoker;
  GoogleDriveConnection _driveConnection = const GoogleDriveConnection(
    state: GoogleDriveConnectionState.disconnected,
  );
  SettingsVaultStatus _settingsVaultStatus =
      const SettingsVaultStatus.unavailable();

  Uri _url(String path, [Map<String, String>? query]) =>
      _baseUrl.resolve(path).replace(queryParameters: query);

  @override
  bool get usesCompanion => true;

  @override
  bool get supportsPhotoLibrarySave => false;

  @override
  String get persistenceDescription =>
      'Combined local companion and optional Google Drive library';

  @override
  bool get supportsLocalLibrary => true;

  @override
  GoogleDriveConnection get googleDriveConnection {
    if (_driveAuthorizer.isAvailable || _driveConnection.isConfigured) {
      return _driveConnection;
    }
    return GoogleDriveConnection(
      state: GoogleDriveConnectionState.unavailable,
      message: _driveAuthorizer.unavailableMessage,
    );
  }

  @override
  SettingsVaultStatus get settingsVaultStatus => _settingsVaultStatus;

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

  Future<LocalSnapshot> _snapshot(http.Response response) async {
    final payload = _map(await _read(response));
    final rawDrive = payload['driveConnection'];
    if (rawDrive is Map<Object?, Object?>) {
      _driveConnection = GoogleDriveConnection.fromJson(
        rawDrive.map((key, value) => MapEntry(key.toString(), value)),
      );
    }
    final snapshot = LocalSnapshot.fromJson(payload);
    _settingsVaultStatus = snapshot.settingsVault;
    return snapshot;
  }

  @override
  Future<LocalSnapshot> load() async =>
      _snapshot(await _client.get(_url('/state')));

  Future<Map<String, Object?>> _settingsVaultAction(
    String action, [
    String value = '',
  ]) async {
    final response = await _settingsVaultInvoker(action, value);
    if (response['ok'] != true) {
      throw ProviderException(
        response['error']?.toString() ??
            'Encrypted settings sync was not completed.',
      );
    }
    return response;
  }

  @override
  Future<SettingsVaultSetupResult> setupSettingsVault(String passphrase) async {
    final response = await _settingsVaultAction('setup', passphrase);
    final recoveryCode = response['recoveryCode']?.toString() ?? '';
    if (recoveryCode.isEmpty) {
      throw const ProviderException(
        'The desktop shell did not return a recovery code.',
      );
    }
    return SettingsVaultSetupResult(
      snapshot: await load(),
      recoveryCode: recoveryCode,
    );
  }

  @override
  Future<LocalSnapshot> unlockSettingsVault(String passphrase) async {
    await _settingsVaultAction('unlock', passphrase);
    return load();
  }

  @override
  Future<LocalSnapshot> recoverSettingsVault(String recoveryCode) async {
    await _settingsVaultAction('recover', recoveryCode);
    return load();
  }

  @override
  Future<LocalSnapshot> syncSettingsVault() async {
    await _settingsVaultAction('sync');
    return load();
  }

  @override
  Future<LocalSnapshot> changeSettingsVaultPassphrase(
    String newPassphrase,
  ) async {
    await _settingsVaultAction('changePassphrase', newPassphrase);
    return load();
  }

  @override
  Future<LocalSnapshot> forgetSettingsVaultUnlock() async {
    await _settingsVaultAction('forget');
    return load();
  }

  @override
  Future<LocalSnapshot> connectGoogleDrive(String folderName) async {
    final token = await _driveAuthorizer.authorize();
    return _snapshot(
      await _client.post(
        _url('/drive/connect'),
        headers: const <String, String>{'Content-Type': 'application/json'},
        body: jsonEncode(<String, Object?>{
          'accessToken': token,
          'folderName': folderName,
        }),
      ),
    );
  }

  @override
  Future<LocalSnapshot> disconnectGoogleDrive() async {
    final snapshot = await _snapshot(
      await _client.post(_url('/drive/disconnect')),
    );
    await _driveAuthorizer.disconnect();
    return snapshot;
  }

  @override
  Future<LocalSnapshot> refreshGoogleDrive() async {
    final token = await _driveAuthorizer.authorize();
    return _snapshot(
      await _client.post(
        _url('/drive/refresh'),
        headers: const <String, String>{'Content-Type': 'application/json'},
        body: jsonEncode(<String, Object?>{'accessToken': token}),
      ),
    );
  }

  @override
  Future<LocalSnapshot?> resumeGoogleDrive() async {
    // The companion holds the Drive session in memory only, so a configured
    // but disconnected library means the process restarted; reattach quietly
    // when a stored grant still exists.
    if (_driveConnection.isConnected || !_driveConnection.isConfigured) {
      return null;
    }
    try {
      final token = await _driveAuthorizer.authorizeSilently();
      if (token == null || token.isEmpty) return null;
      return await _snapshot(
        await _client.post(
          _url('/drive/refresh'),
          headers: const <String, String>{'Content-Type': 'application/json'},
          body: jsonEncode(<String, Object?>{'accessToken': token}),
        ),
      );
    } on Object {
      return null;
    }
  }

  @override
  Future<GoogleDriveCopyResult> copyLocalLibraryToGoogleDrive({
    Set<String> generationIds = const <String>{},
    Set<String> referenceIds = const <String>{},
  }) async {
    final payload = _map(
      await _read(
        await _client.post(
          _url('/drive/copy'),
          headers: const <String, String>{'Content-Type': 'application/json'},
          body: jsonEncode(<String, Object?>{
            'generationIds': generationIds.toList(),
            'referenceIds': referenceIds.toList(),
          }),
        ),
      ),
    );
    final snapshotMap = _map(payload['snapshot']);
    final rawDrive = snapshotMap['driveConnection'];
    if (rawDrive is Map<Object?, Object?>) {
      _driveConnection = GoogleDriveConnection.fromJson(
        rawDrive.map((key, value) => MapEntry(key.toString(), value)),
      );
    }
    return GoogleDriveCopyResult(
      snapshot: LocalSnapshot.fromJson(snapshotMap),
      generations: (payload['generations'] as num?)?.toInt() ?? 0,
      references: (payload['references'] as num?)?.toInt() ?? 0,
    );
  }

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
  Future<CostEstimate?> quoteProviderCost(
    String provider,
    String model,
    Map<String, Object?> input,
  ) async {
    final payload = _map(
      await _read(
        await _client.post(
          _url('/providers/quote'),
          headers: const <String, String>{'Content-Type': 'application/json'},
          body: jsonEncode(<String, Object?>{
            'provider': provider,
            'model': model,
            'input': input,
          }),
        ),
      ),
    );
    if (payload['available'] != true) return null;
    return CostEstimate(
      minimumUsd: (payload['minimumUsd'] as num).toDouble(),
      maximumUsd: (payload['maximumUsd'] as num).toDouble(),
      basis: payload['basis']?.toString() ?? 'provider-quote',
      providerUnitsMinimum: (payload['providerUnitsMinimum'] as num?)
          ?.toDouble(),
      providerUnitsMaximum: (payload['providerUnitsMaximum'] as num?)
          ?.toDouble(),
      providerUnitLabel: payload['providerUnitLabel']?.toString(),
    );
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
  Future<LocalSnapshot> setGenerationFavorite(String localId, bool favorite) =>
      _action('setGenerationFavorite', <String, Object?>{
        'localId': localId,
        'favorite': favorite,
      });

  @override
  Future<LocalSnapshot> setReferenceFavorite(
    String referenceId,
    bool favorite,
  ) => _action('setReferenceFavorite', <String, Object?>{
    'referenceId': referenceId,
    'favorite': favorite,
  });

  @override
  Future<LocalSnapshot> setGenerationsHidden(
    List<String> localIds,
    bool hidden,
  ) => _action('setGenerationsHidden', <String, Object?>{
    'localIds': localIds,
    'hidden': hidden,
  });

  @override
  Future<LocalSnapshot> setReferencesHidden(
    List<String> referenceIds,
    bool hidden,
  ) => _action('setReferencesHidden', <String, Object?>{
    'referenceIds': referenceIds,
    'hidden': hidden,
  });

  @override
  Future<LocalSnapshot> saveGenerationPreviews(
    String localId, {
    Uint8List? thumbnailBytes,
    Uint8List? timelineBytes,
  }) => _action('saveGenerationPreviews', <String, Object?>{
    'localId': localId,
    if (thumbnailBytes != null) 'thumbnail': base64Encode(thumbnailBytes),
    if (timelineBytes != null) 'timeline': base64Encode(timelineBytes),
  });

  @override
  Future<LocalSnapshot> saveReferencePreview(
    String referenceId,
    Uint8List thumbnailBytes,
  ) => _action('saveReferencePreview', <String, Object?>{
    'referenceId': referenceId,
    'thumbnail': base64Encode(thumbnailBytes),
  });

  @override
  Future<LocalSnapshot> saveGenerationInputPreview(
    String localId,
    String sourceAssetValue,
    Uint8List thumbnailBytes,
  ) => _action('saveGenerationInputPreview', <String, Object?>{
    'localId': localId,
    'sourceAssetValue': sourceAssetValue,
    'thumbnail': base64Encode(thumbnailBytes),
  });

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
      ? _url('/assets', <String, String>{
          'id': reference.value,
          'kind': reference.kind,
        })
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
