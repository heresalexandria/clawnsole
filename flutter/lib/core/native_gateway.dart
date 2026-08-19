import 'dart:io';
import 'dart:typed_data';

import 'package:gal/gal.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

import 'bfl_api.dart';
import 'direct_gateway.dart';
import 'local_data_store.dart';
import 'models.dart';
import 'provider_api.dart';

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
/// Provider and persistence behavior lives in [DirectGateway] so the
/// standalone browser build can use the same contracts with Google Drive.
class NativeGateway extends DirectGateway {
  // The public constructor preserves the existing injectable native API while
  // also preparing iOS review-key state before the superclass is initialized.
  // ignore: use_super_parameters
  NativeGateway({
    LocalDataStore? store,
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
  }) : _iosReviewKeys = <String, String>{
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
         store: store ?? LocalDataStore(),
         api: api,
         client: client,
         providerRouter: providerRouter,
         persistenceDescription:
             'Private JSON in this app’s documents directory',
       );

  final Map<String, String> _iosReviewKeys;
  final Map<String, String> _iosReviewKeyIds;
  final bool _isIos;

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
