import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:gal/gal.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

import 'app_version.dart';
import 'apple_local_runtime.dart';
import 'bfl_api.dart';
import 'asset_extensions.dart';
import 'data_location.dart';
import 'direct_gateway.dart';
import 'directory_reveal.dart';
import 'flutter_secure_value_store.dart';
import 'google_drive.dart';
import 'google_drive_asset_presenter_io.dart';
import 'google_drive_auth.dart';
import 'google_drive_store.dart';
import 'generation_status.dart';
import 'hybrid_data_store.dart';
import 'local_data_store.dart';
import 'media_cache_gateway.dart';
import 'models.dart';
import 'provider_api.dart';
import 'provider_catalog.dart';
import 'reference_video_normalizer.dart';
import 'reference_video_normalizer_mobile.dart';
import 'secure_value_store.dart';
import 'settings_vault.dart';
import 'settings_vault_data_store.dart';
import 'settings_vault_gateway.dart';
import 'settings_vault_remote.dart';
import 'video_cache.dart';
import 'video_cache_gateway.dart';

const _configuredIosReviewApiKey = String.fromEnvironment(
  'CLAWNSOLE_IOS_REVIEW_BFL_API_KEY',
);
const _configuredIosReviewApiKeyId = String.fromEnvironment(
  'CLAWNSOLE_IOS_REVIEW_BFL_API_KEY_ID',
);
const _configuredIosReviewLtxApiKey = String.fromEnvironment(
  'CLAWNSOLE_IOS_REVIEW_LTX_API_KEY',
);
const _configuredIosReviewLtxApiKeyId = String.fromEnvironment(
  'CLAWNSOLE_IOS_REVIEW_LTX_API_KEY_ID',
);
const _configuredIosReviewAtlasApiKey = String.fromEnvironment(
  'CLAWNSOLE_IOS_REVIEW_ATLAS_API_KEY',
);
const _configuredIosReviewAtlasApiKeyId = String.fromEnvironment(
  'CLAWNSOLE_IOS_REVIEW_ATLAS_API_KEY_ID',
);
const _configuredIosReviewArtCraftApiKey = String.fromEnvironment(
  'CLAWNSOLE_IOS_REVIEW_ARTCRAFT_API_KEY',
);
const _configuredIosReviewArtCraftApiKeyId = String.fromEnvironment(
  'CLAWNSOLE_IOS_REVIEW_ARTCRAFT_API_KEY_ID',
);
const _configuredMobileTestArtCraftApiKey = String.fromEnvironment(
  'CLAWNSOLE_ARTCRAFT_TEST_API_KEY',
);
const _configuredMobileTestArtCraftApiKeyId = String.fromEnvironment(
  'CLAWNSOLE_ARTCRAFT_TEST_API_KEY_ID',
);

Set<String> _nativeAvailableProviders(bool isIos) => <String>{
  'bfl',
  'ltx',
  'artcraft',
  'atlas',
  'runway',
  if (isIos) 'apple-local',
};

/// Native direct-provider gateway backed by the private app-documents store.
///
/// Provider and persistence behavior lives in [DirectGateway]. Google Drive
/// library data and the independently encrypted settings vault stay behind
/// separate storage boundaries.
class NativeGateway extends DirectGateway
    implements
        GoogleDriveGateway,
        SettingsVaultGateway,
        DataLocationGateway,
        MediaCacheGateway,
        VideoCacheGateway {
  // The public constructor preserves the existing injectable native API while
  // also preparing iOS review-key state before the superclass is initialized.
  // ignore: use_super_parameters
  factory NativeGateway({
    LocalDataStore? store,
    HybridDataStore? hybridStore,
    GoogleDriveAuthorizer? driveAuthorizer,
    BflApi? api,
    http.Client? client,
    String? iosReviewApiKey,
    String? iosReviewApiKeyId,
    String? iosReviewLtxApiKey,
    String? iosReviewLtxApiKeyId,
    String? iosReviewAtlasApiKey,
    String? iosReviewAtlasApiKeyId,
    String? iosReviewArtCraftApiKey,
    String? iosReviewArtCraftApiKeyId,
    String? mobileTestArtCraftApiKey,
    String? mobileTestArtCraftApiKeyId,
    ProviderApiRouter? providerRouter,
    AppleLocalRuntime? appleLocalRuntime,
    bool? isIos,
    bool? isMobile,
    SecureValueStore? secureValueStore,
    SettingsVaultRemote? settingsVaultRemote,
    SettingsVaultCodec? settingsVaultCodec,
    SettingsVaultDataStore? settingsVaultStore,
    ReferenceVideoNormalizationService? referenceVideoNormalizer,
  }) {
    final localStore = store ?? (hybridStore == null ? LocalDataStore() : null);
    // The media cache lives in the app cache directory: unlike a per-process
    // system-temp folder it survives relaunches (which is the entire point of
    // the cache), while the operating system may still reclaim it under
    // storage pressure and it stays out of device backups. The directory is
    // resolved lazily so constructing a gateway never touches path_provider.
    final videoCache = VideoCache(
      directory: () async => Directory(
        '${(await getApplicationCacheDirectory()).path}'
        '${Platform.pathSeparator}video-cache',
      ),
    );
    final thumbnailCache = VideoCache(
      directory: () async => Directory(
        '${(await getApplicationCacheDirectory()).path}'
        '${Platform.pathSeparator}thumbnail-cache',
      ),
    );
    final hybrid =
        hybridStore ??
        HybridDataStore(
          local: localStore!,
          drive: GoogleDriveStore(
            presenter: IoGoogleDriveAssetPresenter(
              videoCache: videoCache,
              thumbnailCache: thumbnailCache,
            ),
          ),
        );
    final vault =
        settingsVaultStore ??
        SettingsVaultDataStore(
          delegate: hybrid,
          secureStore:
              secureValueStore ??
              (store != null || hybridStore != null
                  ? MemorySecureValueStore()
                  : FlutterSecureValueStore()),
          remote: settingsVaultRemote,
          codec: settingsVaultCodec,
        );
    return NativeGateway._(
      hybrid: hybrid,
      localStore: localStore,
      vault: vault,
      videoCache: videoCache,
      thumbnailCache: thumbnailCache,
      driveAuthorizer: driveAuthorizer ?? createGoogleDriveAuthorizer(),
      api: api,
      client: client,
      iosReviewApiKey: iosReviewApiKey,
      iosReviewApiKeyId: iosReviewApiKeyId,
      iosReviewLtxApiKey: iosReviewLtxApiKey,
      iosReviewLtxApiKeyId: iosReviewLtxApiKeyId,
      iosReviewAtlasApiKey: iosReviewAtlasApiKey,
      iosReviewAtlasApiKeyId: iosReviewAtlasApiKeyId,
      iosReviewArtCraftApiKey: iosReviewArtCraftApiKey,
      iosReviewArtCraftApiKeyId: iosReviewArtCraftApiKeyId,
      mobileTestArtCraftApiKey: mobileTestArtCraftApiKey,
      mobileTestArtCraftApiKeyId: mobileTestArtCraftApiKeyId,
      providerRouter: providerRouter,
      appleLocalRuntime: appleLocalRuntime,
      isIos: isIos,
      isMobile: isMobile,
      referenceVideoNormalizer:
          referenceVideoNormalizer ??
          ReferenceVideoNormalizer(
            backend: nativeReferenceVideoToolBackend(),
            imageBackend: nativeReferenceImageToolBackend(),
            cacheDirectory: () async => Directory(
              '${(await getApplicationCacheDirectory()).path}'
              '${Platform.pathSeparator}reference-video-fixes',
            ),
          ),
    );
  }

  // ignore: use_super_parameters
  NativeGateway._({
    required HybridDataStore hybrid,
    required SettingsVaultDataStore vault,
    required VideoCache videoCache,
    required VideoCache thumbnailCache,
    required GoogleDriveAuthorizer driveAuthorizer,
    LocalDataStore? localStore,
    BflApi? api,
    http.Client? client,
    String? iosReviewApiKey,
    String? iosReviewApiKeyId,
    String? iosReviewLtxApiKey,
    String? iosReviewLtxApiKeyId,
    String? iosReviewAtlasApiKey,
    String? iosReviewAtlasApiKeyId,
    String? iosReviewArtCraftApiKey,
    String? iosReviewArtCraftApiKeyId,
    String? mobileTestArtCraftApiKey,
    String? mobileTestArtCraftApiKeyId,
    ProviderApiRouter? providerRouter,
    AppleLocalRuntime? appleLocalRuntime,
    bool? isIos,
    bool? isMobile,
    required ReferenceVideoNormalizationService referenceVideoNormalizer,
  }) : _hybrid = hybrid,
       _localStore = localStore,
       _vault = vault,
       _videoCache = videoCache,
       _thumbnailCache = thumbnailCache,
       _driveAuthorizer = driveAuthorizer,
       _iosReviewKeys = <String, String>{
         'bfl': (iosReviewApiKey ?? _configuredIosReviewApiKey).trim(),
         'ltx': (iosReviewLtxApiKey ?? _configuredIosReviewLtxApiKey).trim(),
         'atlas': (iosReviewAtlasApiKey ?? _configuredIosReviewAtlasApiKey)
             .trim(),
         'artcraft':
             (iosReviewArtCraftApiKey ?? _configuredIosReviewArtCraftApiKey)
                 .trim(),
       },
       _iosReviewKeyIds = <String, String>{
         'bfl': (iosReviewApiKeyId ?? _configuredIosReviewApiKeyId).trim(),
         'ltx': (iosReviewLtxApiKeyId ?? _configuredIosReviewLtxApiKeyId)
             .trim(),
         'atlas': (iosReviewAtlasApiKeyId ?? _configuredIosReviewAtlasApiKeyId)
             .trim(),
         'artcraft':
             (iosReviewArtCraftApiKeyId ?? _configuredIosReviewArtCraftApiKeyId)
                 .trim(),
       },
       _mobileTestArtCraftApiKey =
           (mobileTestArtCraftApiKey ?? _configuredMobileTestArtCraftApiKey)
               .trim(),
       _mobileTestArtCraftApiKeyId =
           (mobileTestArtCraftApiKeyId ?? _configuredMobileTestArtCraftApiKeyId)
               .trim(),
       _appleLocal =
           appleLocalRuntime ?? const MethodChannelAppleLocalRuntime(),
       _isIos = isIos ?? Platform.isIOS,
       _isMobile = isMobile ?? isIos ?? (Platform.isIOS || Platform.isAndroid),
       super(
         store: vault,
         api: api,
         client: client,
         providerRouter: providerRouter,
         availableProviders: _nativeAvailableProviders(isIos ?? Platform.isIOS),
         referenceVideoNormalizer: referenceVideoNormalizer,
         persistenceDescription:
             'Combined local app documents and optional Google Drive library',
       );

  final HybridDataStore _hybrid;
  final LocalDataStore? _localStore;
  final SettingsVaultDataStore _vault;
  final VideoCache _videoCache;
  final VideoCache _thumbnailCache;
  final GoogleDriveAuthorizer _driveAuthorizer;
  final Map<
    String,
    Map<VideoDeliveryProgressListener, VideoCacheProgressListener>
  >
  _videoProgressListeners =
      <
        String,
        Map<VideoDeliveryProgressListener, VideoCacheProgressListener>
      >{};
  final Map<String, String> _iosReviewKeys;
  final Map<String, String> _iosReviewKeyIds;
  final String _mobileTestArtCraftApiKey;
  final String _mobileTestArtCraftApiKeyId;
  final AppleLocalRuntime _appleLocal;
  final bool _isIos;
  final bool _isMobile;

  String get _mobileTestArtCraftRejectionId =>
      '$_mobileTestArtCraftApiKeyId:$clawnsoleVersion';

  @override
  bool get supportsLocalLibrary => true;

  /// Keeps the on-disk cap in step with the persisted preference. Failures
  /// never surface: the cache is a best-effort speed-up, not user data.
  Future<void> _applyVideoCachePreference(AppPreferences preferences) async {
    try {
      await Future.wait(<Future<void>>[
        _videoCache.setMaxBytes(preferences.localVideoCacheMb * 1024 * 1024),
        _thumbnailCache.setMaxBytes(
          preferences.localThumbnailCacheMb * 1024 * 1024,
        ),
      ]);
    } on Object {
      // Ignored: the next successful write or sweep restores the invariant.
    }
  }

  @override
  Future<LocalSnapshot> load() async {
    final snapshot = await super.load();
    // Cache maintenance is local best-effort work and must never extend the
    // splash-screen critical path. setMaxBytes adopts each cap immediately;
    // any LRU sweep finishes after first paint.
    unawaited(_applyVideoCachePreference(snapshot.preferences));
    return snapshot;
  }

  @override
  Future<LocalSnapshot> setPreferences(AppPreferences preferences) async {
    final snapshot = await super.setPreferences(preferences);
    await _applyVideoCachePreference(snapshot.preferences);
    return snapshot;
  }

  @override
  Future<int> videoCacheUsedBytes() => _videoCache.usedBytes();

  @override
  Future<int> thumbnailCacheUsedBytes() => _thumbnailCache.usedBytes();

  @override
  Future<void> clearVideoCache() => _videoCache.clear();

  @override
  Future<void> clearThumbnailCache() => _thumbnailCache.clear();

  @override
  Future<Uint8List?> cachedAssetBytes(AssetReference reference) async {
    try {
      if (reference.kind != 'drive') {
        return await _hybrid.readAsset(reference);
      }
      final cache = isRetainedVideoAsset(reference.contentType, reference.label)
          ? _videoCache
          : _thumbnailCache;
      if (!cache.enabled) return null;
      final cached = await cache.lookup(reference.value);
      return cached == null ? null : await cached.readAsBytes();
    } on Object {
      return null;
    }
  }

  @override
  Future<Uri?> cachedVideoAssetUri(AssetReference reference) =>
      _hybrid.cachedAssetUri(reference);

  @override
  Future<void> prefetchVideoAsset(AssetReference reference) async {
    if (reference.kind != 'drive' || !_videoCache.enabled) return;
    await _hybrid.assetUri(reference);
  }

  @override
  void addVideoProgressListener(
    String assetId,
    VideoDeliveryProgressListener listener,
  ) {
    void wrapped(int received, int? total, bool done) {
      if (done) {
        listener(1);
      } else if (total != null && total > 0) {
        listener((received / total).clamp(0.0, 1.0));
      } else {
        listener(null);
      }
    }

    _videoProgressListeners.putIfAbsent(
      assetId,
      () => <VideoDeliveryProgressListener, VideoCacheProgressListener>{},
    )[listener] = wrapped;
    _videoCache.addProgressListener(assetId, wrapped);
  }

  @override
  void removeVideoProgressListener(
    String assetId,
    VideoDeliveryProgressListener listener,
  ) {
    final wrapped = _videoProgressListeners[assetId]?.remove(listener);
    if (_videoProgressListeners[assetId]?.isEmpty ?? false) {
      _videoProgressListeners.remove(assetId);
    }
    if (wrapped != null) _videoCache.removeProgressListener(assetId, wrapped);
  }

  @override
  SettingsVaultStatus get settingsVaultStatus => _vault.settingsVaultStatus;

  @override
  GoogleDriveConnection get googleDriveConnection {
    final connection = _hybrid.connection;
    if (_driveAuthorizer.isAvailable || connection.isConfigured) {
      return connection;
    }
    return GoogleDriveConnection(
      state: GoogleDriveConnectionState.unavailable,
      message: _driveAuthorizer.unavailableMessage,
    );
  }

  @override
  Future<LocalSnapshot> connectGoogleDrive(String folderName) async {
    final token = await _driveAuthorizer.authorize();
    await _hybrid.connect(token, folderName);
    await _vault.connectRemote(token, _hybrid.connection.folderId);
    return load();
  }

  @override
  Future<LocalSnapshot> disconnectGoogleDrive() async {
    await _vault.disconnectRemote();
    await _hybrid.disconnect();
    await _driveAuthorizer.disconnect();
    return load();
  }

  @override
  Future<LocalSnapshot> refreshGoogleDrive() async {
    final token = await _driveAuthorizer.authorize();
    await _hybrid.connect(token, googleDriveConnection.folderName);
    await _vault.connectRemote(token, _hybrid.connection.folderId);
    return load();
  }

  @override
  Future<LocalSnapshot?> resumeGoogleDrive({bool force = false}) async {
    try {
      // A read populates the persisted folder name so a fresh process knows
      // whether Drive was configured before deciding to reattach.
      if (!force) await _hybrid.read();
      final connection = _hybrid.connection;
      if ((!force && connection.isConnected) || !connection.isConfigured) {
        return null;
      }
      final token = await _driveAuthorizer.authorizeSilently();
      if (token == null || token.isEmpty) return null;
      await _hybrid.connect(token, connection.folderName);
      await _vault.connectRemote(token, _hybrid.connection.folderId);
      return await load();
    } on Object {
      return null;
    }
  }

  @override
  Future<SettingsVaultSetupResult> setupSettingsVault(String passphrase) async {
    final recoveryCode = await _vault.setup(passphrase);
    return SettingsVaultSetupResult(
      snapshot: await load(),
      recoveryCode: recoveryCode,
    );
  }

  @override
  Future<LocalSnapshot> unlockSettingsVault(String passphrase) async {
    await _vault.unlock(passphrase);
    return load();
  }

  @override
  Future<LocalSnapshot> recoverSettingsVault(String recoveryCode) async {
    await _vault.recover(recoveryCode);
    return load();
  }

  @override
  Future<LocalSnapshot> syncSettingsVault() async {
    await _vault.sync();
    return load();
  }

  @override
  Future<LocalSnapshot> changeSettingsVaultPassphrase(
    String newPassphrase,
  ) async {
    await _vault.changePassphrase(newPassphrase);
    return load();
  }

  @override
  Future<LocalSnapshot> forgetSettingsVaultUnlock() async {
    await _vault.forgetCachedUnlock();
    return load();
  }

  @override
  Future<GoogleDriveCopyResult> copyLocalLibraryToGoogleDrive({
    Set<String> generationIds = const <String>{},
    Set<String> referenceIds = const <String>{},
  }) async {
    final copied = await _hybrid.copyLocalToDrive(
      generationIds: generationIds,
      referenceIds: referenceIds,
    );
    return GoogleDriveCopyResult(
      snapshot: await load(),
      generations: copied.generations,
      references: copied.references,
    );
  }

  @override
  Future<GoogleDriveCopyResult> moveLocalLibraryToGoogleDrive() async {
    final moved = await _hybrid.moveLocalToDrive();
    return GoogleDriveCopyResult(
      snapshot: await load(),
      generations: moved.generations,
      references: moved.references,
    );
  }

  @override
  bool get supportsRevealDataFolder =>
      _localStore != null && canRevealDirectory;

  @override
  bool get supportsDataRelocation =>
      _localStore != null &&
      (Platform.isWindows || Platform.isLinux || Platform.isMacOS);

  @override
  bool get shellManagesDataRelocation => false;

  @override
  Future<void> revealDataFolder() async {
    final store = _localStore;
    if (store == null || !supportsRevealDataFolder) {
      throw StateError('Opening the data folder is not supported here.');
    }
    await revealDirectory(await store.dataDirectoryPath());
  }

  @override
  Future<bool> dataDirectoryHasLibrary(String directory) {
    final store = _localStore;
    if (store == null) {
      throw StateError('Moving the data folder is not supported here.');
    }
    return store.hasLibraryAt(directory);
  }

  @override
  Future<LocalSnapshot> relocateDataDirectory(
    String directory, {
    bool useExistingLibrary = false,
  }) async {
    final store = _localStore;
    if (store == null || !supportsDataRelocation) {
      throw StateError('Moving the data folder is not supported here.');
    }
    await store.relocate(directory, useExistingLibrary: useExistingLibrary);
    return load();
  }

  @override
  Future<ShellDataRelocation> relocateDataDirectoryViaShell() =>
      throw StateError(
        'This build moves its data folder directly rather than via a shell.',
      );

  @override
  bool get supportsPhotoLibrarySave => Platform.isIOS || Platform.isAndroid;

  Future<Generation> _replaceAppleLocalGeneration(Generation generation) async {
    final current = await _vault.read();
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
    await _vault.write(current.copyWith(generations: generations));
    return persisted;
  }

  @override
  Future<Generation> submit(GenerationSubmission submission) async {
    if (submission.record.provider != 'apple-local') {
      return super.submit(submission);
    }
    return _submitAppleLocal(submission.record);
  }

  Future<Generation> _submitAppleLocal(Generation inputRecord) async {
    var record = inputRecord;
    final provider = providerByIdOrNull(record.provider);
    final model = provider?.models
        .where((candidate) => candidate.id == record.model)
        .firstOrNull;
    if (provider == null || model == null) {
      throw StateError(
        'Apple Intelligence is not available for this Clawnsole version.',
      );
    }
    if (!_isIos || !await _appleLocal.isAvailable()) {
      throw StateError(
        'Apple Intelligence image creation requires a supported iPhone or iPad with iOS 18.4 or later and Image Playground enabled.',
      );
    }
    final duration = record.config.duration is num
        ? (record.config.duration as num).toInt()
        : model.minDuration;
    if (duration < model.minDuration || duration > model.maxDuration) {
      throw StateError(
        '${model.label} supports ${model.minDuration}–${model.maxDuration} seconds.',
      );
    }
    record = record.copyWith(
      canonicalModelId: record.canonicalModelId ?? model.canonicalId,
      estimatedCreditsMin: 0,
      estimatedCreditsMax: 0,
      estimateBasis: 'Apple system service · no provider charge',
      quotedCostUsdMin: 0,
      quotedCostUsdMax: 0,
      updatedAt: DateTime.now().toUtc(),
    );
    record = await _replaceAppleLocalGeneration(record);
    try {
      final receipt = await _appleLocal.submit(<String, Object?>{
        'requestId': record.localId,
        'mode': record.isImage ? 'image' : 'sequence',
        'prompt': record.prompt,
        'aspectRatio': record.config.aspectRatio,
        'resolution': record.config.resolution,
        'durationSeconds': record.isImage ? 1 : duration,
      });
      final jobId = receipt['jobId']?.toString().trim();
      if (jobId == null || jobId.isEmpty) {
        throw StateError(
          'Apple Intelligence returned an invalid generation receipt.',
        );
      }
      final acceptedAt = DateTime.now().toUtc();
      record = record.copyWith(
        requestId: jobId,
        pollingUrl: 'apple-local://$jobId',
        status: 'Pending',
        progress: 0,
        providerAcceptedAt: acceptedAt,
        lastProviderStatusCode: 200,
        lastProviderResponse: compactProviderResponse(receipt),
        lastProviderResponseAt: acceptedAt,
        updatedAt: acceptedAt,
      );
      return await _replaceAppleLocalGeneration(record);
    } on Object catch (error) {
      record = record.copyWith(
        status: 'Error',
        error: generationExceptionMessage(error),
        updatedAt: DateTime.now().toUtc(),
      );
      await _replaceAppleLocalGeneration(record);
      rethrow;
    }
  }

  @override
  Future<Generation> poll(Generation generation) {
    if (generation.provider != 'apple-local') return super.poll(generation);
    return _pollAppleLocal(generation);
  }

  Future<Generation> _pollAppleLocal(Generation generation) async {
    final checkedAt = DateTime.now().toUtc();
    try {
      final jobId = generation.requestId?.trim() ?? '';
      if (jobId.isEmpty) {
        throw StateError(
          'This Apple Intelligence generation has no local job id.',
        );
      }
      final payload = await _appleLocal.poll(jobId);
      final providerStatus = payload['status']?.toString() ?? 'Pending';
      final status = normalizeGenerationStatus(providerStatus);
      AssetReference? resultAsset = generation.resultAsset;
      if (status == 'Ready' && resultAsset == null) {
        final resultPath = payload['resultPath']?.toString().trim() ?? '';
        if (resultPath.isEmpty) {
          throw StateError(
            'Apple Intelligence finished without returning a media file.',
          );
        }
        final resultFile = File(resultPath);
        final contentType =
            payload['contentType']?.toString() ??
            (generation.isImage ? 'image/png' : 'video/mp4');
        resultAsset = await _vault.writeAsset(
          await resultFile.readAsBytes(),
          label:
              'clawnsole-${generation.localId}.${generation.isImage ? 'png' : 'mp4'}',
          contentType: contentType,
          storage: generation.storage,
        );
        try {
          await resultFile.parent.delete(recursive: true);
        } on FileSystemException {
          // The operating system also reclaims the temporary job directory.
        }
      }
      final failed = isGenerationFailureStatus(status);
      final next = generation.copyWith(
        status: status,
        progress: status == 'Ready'
            ? 100
            : normalizedProgress(payload['progress']),
        resultAsset: resultAsset,
        providerCompletedAt: status == 'Ready' ? checkedAt : null,
        error: failed ? payload['error']?.toString() ?? providerStatus : null,
        clearError: !failed,
        lastCheckedAt: checkedAt,
        statusCheckCount: generation.statusCheckCount + 1,
        consecutiveCheckFailures: 0,
        clearLastCheckError: true,
        lastProviderStatusCode: 200,
        lastProviderResponse: compactProviderResponse(<String, Object?>{
          'status': providerStatus,
          'progress': payload['progress'],
          if (payload['message'] != null) 'message': payload['message'],
          if (payload['error'] != null) 'error': payload['error'],
        }),
        lastProviderResponseAt: checkedAt,
        updatedAt: checkedAt,
      );
      return await _replaceAppleLocalGeneration(next);
    } on Object catch (error) {
      final next = generation.copyWith(
        lastCheckedAt: checkedAt,
        statusCheckCount: generation.statusCheckCount + 1,
        consecutiveCheckFailures: generation.consecutiveCheckFailures + 1,
        lastCheckError: generationExceptionMessage(error),
        updatedAt: checkedAt,
      );
      return _replaceAppleLocalGeneration(next);
    }
  }

  @override
  ActiveApiKey? activeApiKey(String provider, StoredData data) {
    final saved = super.activeApiKey(provider, data);
    if (saved != null) return saved;
    if (_isMobile &&
        activeProviderCatalogIsMobileTest &&
        provider == mobileTestProviderId &&
        _mobileTestArtCraftApiKey.isNotEmpty &&
        _mobileTestArtCraftApiKeyId.isNotEmpty &&
        data.rejectedReviewKeyIdFor(provider) !=
            _mobileTestArtCraftRejectionId) {
      return ActiveApiKey(_mobileTestArtCraftApiKey, ApiKeySource.configured);
    }
    final key = _iosReviewKeys[provider] ?? '';
    final keyId = _iosReviewKeyIds[provider] ?? '';
    if (_isIos &&
        key.isNotEmpty &&
        keyId.isNotEmpty &&
        data.rejectedReviewKeyIdFor(provider) != keyId) {
      return ActiveApiKey(key, ApiKeySource.configured);
    }
    return null;
  }

  @override
  StoredData clearCredential(String provider, StoredData data) {
    var next = super.clearCredential(provider, data);
    return rejectConfiguredCredential(provider, next);
  }

  @override
  StoredData rejectConfiguredCredential(String provider, StoredData data) {
    var next = data;
    if (_isMobile &&
        activeProviderCatalogIsMobileTest &&
        provider == mobileTestProviderId &&
        _mobileTestArtCraftApiKeyId.isNotEmpty) {
      return next.withRejectedReviewKeyId(
        provider,
        _mobileTestArtCraftRejectionId,
      );
    }
    final reviewId = _iosReviewKeyIds[provider] ?? '';
    if (_isIos && reviewId.isNotEmpty) {
      next = next.withRejectedReviewKeyId(provider, reviewId);
    }
    return next;
  }

  @override
  Future<void> saveMediaToPhotoLibrary(
    Uint8List bytes,
    String fileName,
    String contentType,
  ) async {
    if (!supportsPhotoLibrarySave) {
      throw UnsupportedError(
        'Saving directly to Photos is available in the iOS and Android apps.',
      );
    }

    final hasAccess = await Gal.hasAccess();
    if (!hasAccess && !await Gal.requestAccess()) {
      throw StateError(
        'Photos access was not granted. Allow Clawnsole to add videos in system settings and try again.',
      );
    }

    final directory = await getTemporaryDirectory();
    final file = File('${directory.path}/$fileName');
    try {
      await file.writeAsBytes(bytes, flush: true);
      if (contentType.startsWith('image/')) {
        await Gal.putImage(file.path);
      } else {
        await Gal.putVideo(file.path);
      }
    } on GalException catch (error) {
      throw StateError(error.type.message);
    } finally {
      try {
        if (await file.exists()) await file.delete();
      } on FileSystemException {
        // The operating system also cleans this temporary directory.
      }
    }
  }
}
