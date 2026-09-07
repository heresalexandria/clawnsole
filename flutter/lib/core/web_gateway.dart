import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

import 'bfl_api.dart';
import 'composer_tabs.dart';
import 'data_location.dart';
import 'data_location_shell.dart';
import 'gateway.dart';
import 'asset_extensions.dart';
import 'google_drive.dart';
import 'google_drive_auth.dart';
import 'google_drive_upload_pump.dart';
import 'media_cache_gateway.dart';
import 'models.dart';
import 'prompt_rewrite.dart';
import 'settings_vault_gateway.dart';
import 'settings_vault_shell.dart';
import 'video_cache_gateway.dart';

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
        GenerationDeliveryGateway,
        ProviderGateway,
        ProviderRetentionAcknowledgementGateway,
        ProviderCatalogCacheGateway,
        ComposerTabsGateway,
        PromptRewriteGateway,
        LibraryOrganizationGateway,
        ReferenceLibraryGateway,
        ReferenceVideoEditingGateway,
        FavoriteGateway,
        VisibilityGateway,
        GenerationPreviewGateway,
        MediaPreviewGateway,
        GoogleDriveGateway,
        SettingsVaultGateway,
        DataLocationGateway,
        MediaCacheGateway,
        VideoCacheGateway,
        DriveUploadStatusSource {
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
    _adoptDriveUploadStatus(payload['driveUploads']);
    final snapshot = LocalSnapshot.fromJson(payload);
    _settingsVaultStatus = snapshot.settingsVault;
    return snapshot;
  }

  DriveUploadQueueReport _driveUploadStatus = DriveUploadQueueReport.unknown;
  void Function()? _onDriveUploadStatus;

  /// Takes the companion's queue as this renderer's own.
  ///
  /// Nothing here publishes to Drive: the companion process beside this
  /// renderer holds the staged bytes and runs the pump, so its report *is*
  /// what this device is doing. A response that carries no report — an older
  /// companion — leaves the queue unknown, which the chips read as the
  /// truthful "Awaiting upload" rather than as an empty queue.
  void _adoptDriveUploadStatus(Object? raw) {
    final next = raw is Map<Object?, Object?>
        ? driveUploadQueueReportFromJson(
            raw.map((key, value) => MapEntry(key.toString(), value)),
          )
        : DriveUploadQueueReport.unknown;
    if (sameDriveUploadQueueReport(_driveUploadStatus, next)) return;
    _driveUploadStatus = next;
    _onDriveUploadStatus?.call();
  }

  @override
  DriveUploadQueueReport get driveUploadStatus => _driveUploadStatus;

  @override
  set onDriveUploadStatus(void Function()? listener) =>
      _onDriveUploadStatus = listener;

  @override
  Future<bool> flushDriveUploads() async {
    try {
      final payload = _map(
        await _read(await _client.post(_url('/drive/uploads/flush'))),
      );
      _adoptDriveUploadStatus(payload['driveUploads']);
      return payload['settled'] == true;
    } on Object {
      // A companion without the route, or one whose pass failed, has told us
      // nothing new; the queue keeps whatever `/state` last reported and the
      // pump on the far side keeps retrying. The native pump swallows a
      // failed pass the same way rather than surfacing it as an error.
      return false;
    }
  }

  @override
  Future<LocalSnapshot> load() async =>
      _snapshot(await _client.get(_url('/state')));

  @override
  Future<Map<String, Object?>?> loadProviderCatalogCache() async {
    final payload = _map(
      await _read(await _client.get(_url('/provider-catalog-cache'))),
    );
    final cache = payload['cache'];
    return cache is Map<Object?, Object?>
        ? cache.map((key, value) => MapEntry(key.toString(), value))
        : null;
  }

  @override
  Future<void> saveProviderCatalogCache(Map<String, Object?> cache) async {
    await _read(
      await _client.put(
        _url('/provider-catalog-cache'),
        headers: const <String, String>{'Content-Type': 'application/json'},
        body: jsonEncode(<String, Object?>{'cache': cache}),
      ),
    );
  }

  @override
  Future<ComposerTabsState?> loadComposerTabs() async {
    final payload = _map(
      await _read(await _client.get(_url('/composer-tabs'))),
    );
    final state = payload['composerTabs'];
    return state is Map<Object?, Object?>
        ? ComposerTabsState.fromJson(
            state.map((key, value) => MapEntry(key.toString(), value)),
          )
        : null;
  }

  @override
  Future<void> saveComposerTabs(
    ComposerTabsState state, {
    bool publishNow = false,
  }) async {
    await _read(
      await _client.put(
        _url('/composer-tabs'),
        headers: const <String, String>{'Content-Type': 'application/json'},
        body: jsonEncode(<String, Object?>{
          'composerTabs': state.toJson(),
          if (publishNow) 'publish': 'now',
        }),
      ),
    );
  }

  @override
  Future<void> publishComposerTabs() async {
    await _read(await _client.post(_url('/composer-tabs/publish')));
  }

  @override
  Future<List<RewriteModel>> listRewriteModels(
    String providerId, {
    String? candidateKey,
  }) async {
    final supplied = candidateKey?.trim().isNotEmpty == true;
    final payload = await _readRewrite(
      await _client.post(
        _url('/rewrite/models'),
        headers: const <String, String>{'Content-Type': 'application/json'},
        body: jsonEncode(<String, Object?>{
          'provider': providerId,
          if (supplied) 'apiKey': candidateKey!.trim(),
        }),
      ),
    );
    final models = payload['models'];
    if (models is! List<Object?>) return const <RewriteModel>[];
    return models
        .whereType<Map<Object?, Object?>>()
        .map(
          (item) => RewriteModel.fromJson(
            item.map((key, value) => MapEntry(key.toString(), value)),
          ),
        )
        .where((model) => model.id.isNotEmpty)
        .toList();
  }

  @override
  Future<PromptRewriteResult> rewritePrompt(
    PromptRewriteRequest request,
  ) async {
    final payload = await _readRewrite(
      await _client.post(
        _url('/rewrite/prompt'),
        headers: const <String, String>{'Content-Type': 'application/json'},
        body: jsonEncode(request.toJson()),
      ),
    );
    return PromptRewriteResult.fromJson(payload);
  }

  /// Rewrite routes answer errors as `{error, failure, status}` so the typed
  /// failure survives the companion hop.
  Future<Map<String, Object?>> _readRewrite(http.Response response) async {
    Object? decoded;
    try {
      decoded = jsonDecode(utf8.decode(response.bodyBytes));
    } on FormatException {
      decoded = null;
    }
    final payload = decoded is Map<Object?, Object?>
        ? decoded.map((key, value) => MapEntry(key.toString(), value))
        : <String, Object?>{};
    if (response.statusCode >= 200 && response.statusCode < 300) {
      return payload;
    }
    final failureName = payload['failure']?.toString();
    throw PromptRewriteException(
      payload['error']?.toString() ??
          'The companion could not complete the rewrite '
              '(HTTP ${response.statusCode}).',
      failure:
          PromptRewriteFailure.values
              .where((value) => value.name == failureName)
              .firstOrNull ??
          PromptRewriteFailure.other,
      status: response.statusCode,
    );
  }

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
  Future<LocalSnapshot?> resumeGoogleDrive({bool force = false}) async {
    // The companion holds the Drive session in memory only, so a configured
    // but disconnected library means the process restarted; reattach quietly
    // when a stored grant still exists. A forced resume replaces a token that
    // expired while the client still believed the companion was connected.
    if ((!force && _driveConnection.isConnected) ||
        !_driveConnection.isConfigured) {
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
  }) => _driveTransfer('/drive/copy', <String, Object?>{
    'generationIds': generationIds.toList(),
    'referenceIds': referenceIds.toList(),
  });

  @override
  Future<GoogleDriveCopyResult> moveLocalLibraryToGoogleDrive() =>
      _driveTransfer('/drive/migrate', const <String, Object?>{});

  Future<GoogleDriveCopyResult> _driveTransfer(
    String path,
    Map<String, Object?> body,
  ) async {
    final payload = _map(
      await _read(
        await _client.post(
          _url(path),
          headers: const <String, String>{'Content-Type': 'application/json'},
          body: jsonEncode(body),
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
    // A transfer stages everything it moved, so its snapshot is exactly when
    // the queue changes most.
    _adoptDriveUploadStatus(snapshotMap['driveUploads']);
    return GoogleDriveCopyResult(
      snapshot: LocalSnapshot.fromJson(snapshotMap),
      generations: (payload['generations'] as num?)?.toInt() ?? 0,
      references: (payload['references'] as num?)?.toInt() ?? 0,
    );
  }

  @override
  bool get supportsRevealDataFolder => shellManagesDataLocation;

  @override
  bool get supportsDataRelocation => shellManagesDataLocation;

  @override
  bool get shellManagesDataRelocation => shellManagesDataLocation;

  @override
  Future<void> revealDataFolder() async {
    final result = await revealShellDataFolder();
    if (result['ok'] != true) {
      throw StateError(
        result['error']?.toString() ?? 'The data folder could not be opened.',
      );
    }
  }

  @override
  Future<bool> dataDirectoryHasLibrary(String directory) =>
      throw StateError('The desktop shell inspects the chosen folder itself.');

  @override
  Future<LocalSnapshot> relocateDataDirectory(
    String directory, {
    bool useExistingLibrary = false,
  }) => throw StateError('The desktop shell moves the data folder itself.');

  @override
  Future<ShellDataRelocation> relocateDataDirectoryViaShell() async {
    final result = await chooseShellDataDirectory();
    if (result['ok'] != true) {
      throw StateError(
        result['error']?.toString() ?? 'The data folder could not be moved.',
      );
    }
    return ShellDataRelocation(
      moved: result['moved'] == true,
      canceled: result['canceled'] == true,
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
  Future<LocalSnapshot> acknowledgeProviderRetentionRisk(String provider) =>
      _action('acknowledgeProviderRetentionRisk', provider);

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
  Future<LocalSnapshot> trimReferenceVideo({
    required String sourceReferenceId,
    required SavedReference output,
    required double startSeconds,
    required double endSeconds,
  }) => _action('trimReferenceVideo', <String, Object?>{
    'sourceReferenceId': sourceReferenceId,
    'output': output.toJson(),
    'startSeconds': startSeconds,
    'endSeconds': endSeconds,
  });

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
              if (submission.autoFixReferenceVideos case final value?)
                'autoFixReferenceVideos': value,
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
  Future<Generation> poll(Generation generation) => _poll(generation);

  @override
  Future<Generation> pollStatus(Generation generation) =>
      _poll(generation, statusOnly: true);

  Future<Generation> _poll(
    Generation generation, {
    bool statusOnly = false,
  }) async {
    final payload = _map(
      await _read(
        await _client.post(
          _url('/generations/status'),
          headers: const <String, String>{'Content-Type': 'application/json'},
          body: jsonEncode(<String, Object?>{
            'provider': generation.provider,
            'localId': generation.localId,
            'pollingUrl': generation.pollingUrl,
            if (statusOnly) 'statusOnly': true,
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
  Future<Generation> retainResult(Generation generation) async {
    final payload = _map(
      await _read(
        await _client.post(
          _url('/generations/retain'),
          headers: const <String, String>{'Content-Type': 'application/json'},
          body: jsonEncode(<String, Object?>{'localId': generation.localId}),
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
        'The retained media is unavailable.',
        status: response.statusCode,
      );
    }
    return response.bodyBytes;
  }

  @override
  Future<int> videoCacheUsedBytes() async {
    final payload = _map(await _read(await _client.get(_url('/video-cache'))));
    return (payload['usedBytes'] as num?)?.toInt() ?? 0;
  }

  @override
  Future<int> thumbnailCacheUsedBytes() async {
    final payload = _map(
      await _read(await _client.get(_url('/thumbnail-cache'))),
    );
    return (payload['usedBytes'] as num?)?.toInt() ?? 0;
  }

  @override
  Future<void> clearVideoCache() async {
    await _read(await _client.delete(_url('/video-cache')));
  }

  @override
  Future<void> clearThumbnailCache() async {
    await _read(await _client.delete(_url('/thumbnail-cache')));
  }

  @override
  Future<Uint8List?> cachedAssetBytes(AssetReference reference) async {
    final response = await _client.get(
      _url('/asset-cache', <String, String>{'id': reference.value}),
    );
    if (response.statusCode == 404) return null;
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw ProviderException(
        'The local media cache could not be read.',
        status: response.statusCode,
      );
    }
    return response.bodyBytes;
  }

  @override
  Future<Uri?> cachedVideoAssetUri(AssetReference reference) =>
      Future<Uri?>.value(
        _url('/asset-cache', <String, String>{'id': reference.value}),
      );

  @override
  Future<void> prefetchVideoAsset(AssetReference reference) async {
    if (reference.kind != 'drive') return;
    await _read(
      await _client.post(
        _url('/video-cache/prefetch'),
        headers: const <String, String>{'Content-Type': 'application/json'},
        body: jsonEncode(<String, Object?>{'id': reference.value}),
      ),
    );
  }

  @override
  void addVideoProgressListener(
    String assetId,
    VideoDeliveryProgressListener listener,
  ) {
    // A browser video element exposes no byte progress for its own fetches,
    // so web surfaces stay on the indeterminate loader.
  }

  @override
  void removeVideoProgressListener(
    String assetId,
    VideoDeliveryProgressListener listener,
  ) {}

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
