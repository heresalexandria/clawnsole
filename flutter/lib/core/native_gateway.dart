import 'dart:io';
import 'dart:typed_data';

import 'package:gal/gal.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

import 'bfl_api.dart';
import 'data_location.dart';
import 'direct_gateway.dart';
import 'directory_reveal.dart';
import 'flutter_secure_value_store.dart';
import 'google_drive.dart';
import 'google_drive_asset_presenter_io.dart';
import 'google_drive_auth.dart';
import 'google_drive_store.dart';
import 'hybrid_data_store.dart';
import 'local_data_store.dart';
import 'models.dart';
import 'provider_api.dart';
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
    ProviderApiRouter? providerRouter,
    bool? isIos,
    SecureValueStore? secureValueStore,
    SettingsVaultRemote? settingsVaultRemote,
    SettingsVaultCodec? settingsVaultCodec,
    SettingsVaultDataStore? settingsVaultStore,
  }) {
    final localStore = store ?? (hybridStore == null ? LocalDataStore() : null);
    // The video cache lives in the app cache directory: unlike a per-process
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
    final hybrid =
        hybridStore ??
        HybridDataStore(
          local: localStore!,
          drive: GoogleDriveStore(
            presenter: IoGoogleDriveAssetPresenter(cache: videoCache),
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
      providerRouter: providerRouter,
      isIos: isIos,
    );
  }

  // ignore: use_super_parameters
  NativeGateway._({
    required HybridDataStore hybrid,
    required SettingsVaultDataStore vault,
    required VideoCache videoCache,
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
    ProviderApiRouter? providerRouter,
    bool? isIos,
  }) : _hybrid = hybrid,
       _localStore = localStore,
       _vault = vault,
       _videoCache = videoCache,
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
       _isIos = isIos ?? Platform.isIOS,
       super(
         store: vault,
         api: api,
         client: client,
         providerRouter: providerRouter,
         persistenceDescription:
             'Combined local app documents and optional Google Drive library',
       );

  final HybridDataStore _hybrid;
  final LocalDataStore? _localStore;
  final SettingsVaultDataStore _vault;
  final VideoCache _videoCache;
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
  final bool _isIos;

  @override
  bool get supportsLocalLibrary => true;

  /// Keeps the on-disk cap in step with the persisted preference. Failures
  /// never surface: the cache is a best-effort speed-up, not user data.
  Future<void> _applyVideoCachePreference(AppPreferences preferences) async {
    try {
      await _videoCache.setMaxBytes(
        preferences.localVideoCacheMb * 1024 * 1024,
      );
    } on Object {
      // Ignored: the next successful write or sweep restores the invariant.
    }
  }

  @override
  Future<LocalSnapshot> load() async {
    final snapshot = await super.load();
    await _applyVideoCachePreference(snapshot.preferences);
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
  Future<void> clearVideoCache() => _videoCache.clear();

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

  @override
  ActiveApiKey? activeApiKey(String provider, StoredData data) {
    final saved = super.activeApiKey(provider, data);
    if (saved != null) return saved;
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
