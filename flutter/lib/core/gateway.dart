import 'package:flutter/foundation.dart';

import 'models.dart';
import 'native_gateway.dart';
import 'web_gateway.dart';

abstract interface class AppGateway {
  bool get usesCompanion;
  bool get supportsPhotoLibrarySave;
  String get persistenceDescription;

  Future<LocalSnapshot> load();
  Future<LocalSnapshot> setApiKey(String value);
  Future<double> verifyKey([String? candidate]);
  Future<double> getCredits();
  Future<LocalSnapshot> setPreferences(AppPreferences preferences);
  Future<Generation> submit(GenerationSubmission submission);
  Future<Generation> poll(Generation generation);
  Future<LocalSnapshot> deleteGeneration(String localId);
  Future<LocalSnapshot> clearHistory();
  Future<LocalSnapshot> clearPreferences();
  Future<LocalSnapshot> clearApiKey();
  Future<LocalSnapshot> clearAll();
  Future<Uri> assetUri(AssetReference reference);
  Future<Uint8List> readAsset(AssetReference reference);
  Uri mediaUri(String source);
  Future<Uint8List> downloadMedia(String source);
  Future<void> saveMediaToPhotoLibrary(
    Uint8List bytes,
    String fileName,
    String contentType,
  );
}

/// Provider-aware operations implemented by the production gateways. Keeping
/// this separate preserves compatibility with lightweight BFL-only test and
/// embedder gateways while the app can route LTX, ArtCraft, and Atlas Cloud
/// explicitly.
abstract interface class ProviderGateway {
  Future<LocalSnapshot> setProviderApiKey(String provider, String value);
  Future<ProviderAccountStatus> verifyProviderKey(
    String provider, [
    String? candidate,
  ]);
  Future<ProviderAccountStatus> getProviderAccount(String provider);
  Future<LocalSnapshot> clearProviderApiKey(String provider);
  Future<List<ProviderModelPrice>> listProviderModels(String provider);
  Future<CostEstimate?> quoteProviderCost(
    String provider,
    String model,
    Map<String, Object?> input,
  );
}

/// Persists the device-local acknowledgement required before using providers
/// whose completed media may disappear before Clawnsole can retain it.
abstract interface class ProviderRetentionAcknowledgementGateway {
  Future<LocalSnapshot> acknowledgeProviderRetentionRisk(String provider);
}

/// Device-local persistence for the last complete remote provider catalog.
///
/// This stays separate from [AppGateway] so lightweight embedders and tests can
/// continue using only the bundled catalog.
abstract interface class ProviderCatalogCacheGateway {
  Future<Map<String, Object?>?> loadProviderCatalogCache();
  Future<void> saveProviderCatalogCache(Map<String, Object?> cache);
}

abstract interface class LibraryOrganizationGateway {
  Future<LocalSnapshot> saveLibraryFolder(LibraryFolder folder);
  Future<LocalSnapshot> deleteLibraryFolder(String folderId);
  Future<LocalSnapshot> setGenerationOrganization(
    String localId, {
    String? folderId,
    required List<String> tags,
  });
}

abstract interface class ReferenceLibraryGateway {
  Future<LocalSnapshot> saveReference(
    SavedReference reference, {
    String? source,
  });
  Future<LocalSnapshot> deleteReference(String referenceId);
}

abstract interface class FavoriteGateway {
  Future<LocalSnapshot> setGenerationFavorite(String localId, bool favorite);
  Future<LocalSnapshot> setReferenceFavorite(String referenceId, bool favorite);
}

abstract interface class VisibilityGateway {
  Future<LocalSnapshot> setGenerationsHidden(
    List<String> localIds,
    bool hidden,
  );
  Future<LocalSnapshot> setReferencesHidden(
    List<String> referenceIds,
    bool hidden,
  );
}

abstract interface class GenerationPreviewGateway {
  Future<LocalSnapshot> saveGenerationPreviews(
    String localId, {
    Uint8List? thumbnailBytes,
    Uint8List? timelineBytes,
  });
}

/// Durable thumbnails for source videos and creative video references.
///
/// These previews are separate assets so compact history never embeds media
/// bytes and every surface can reuse the same image after an app restart.
abstract interface class MediaPreviewGateway {
  Future<LocalSnapshot> saveReferencePreview(
    String referenceId,
    Uint8List thumbnailBytes,
  );

  Future<LocalSnapshot> saveGenerationInputPreview(
    String localId,
    String sourceAssetValue,
    Uint8List thumbnailBytes,
  );
}

AppGateway createGateway() => kIsWeb ? WebGateway() : NativeGateway();
