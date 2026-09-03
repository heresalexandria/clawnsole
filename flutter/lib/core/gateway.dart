import 'package:flutter/foundation.dart';

import 'composer_tabs.dart';
import 'models.dart';
import 'native_gateway.dart';
import 'prompt_rewrite.dart';
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

/// Device-local persistence for the Create screen's composer tabs.
///
/// Tabs are drafts, not library data: they stay on the device that typed them
/// and never ride along to Drive. Gateways without this interface keep tabs
/// for the session only.
abstract interface class ComposerTabsGateway {
  Future<ComposerTabsState?> loadComposerTabs();
  Future<void> saveComposerTabs(ComposerTabsState state);
}

/// AI Rewrite: multimodal LLM calls that must run beside the saved key.
///
/// Native builds call the vendor directly; the web renderer asks the
/// companion, which holds the credential. [candidateKey] lets Settings test
/// a key before it is saved.
abstract interface class PromptRewriteGateway {
  Future<List<RewriteModel>> listRewriteModels(
    String providerId, {
    String? candidateKey,
  });
  Future<PromptRewriteResult> rewritePrompt(PromptRewriteRequest request);
}

/// Recovery of result downloads a platform background transfer service
/// finished while the process was suspended or terminated.
abstract interface class BackgroundDeliveryGateway {
  /// Imports every retained platform download whose generation still lacks a
  /// saved result, returning how many films were recovered.
  Future<int> recoverBackgroundDeliveries();
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

/// Non-destructive edits that create new durable reference media.
///
/// The renderer sends only compact edit metadata. Native builds and the
/// Electron companion perform the media work beside the durable asset store,
/// keeping large video bytes out of web-renderer messages and history JSON.
abstract interface class ReferenceVideoEditingGateway {
  Future<LocalSnapshot> trimReferenceVideo({
    required String sourceReferenceId,
    required SavedReference output,
    required double startSeconds,
    required double endSeconds,
  });
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

/// Whether the keyless on-device provider can actually render here. The
/// Providers desk must never call a provider "ready" on a device whose OS or
/// hardware cannot run it, so the real platform check is exposed and probed
/// at startup instead of being discovered at submit time.
abstract interface class LocalGenerationAvailabilityGateway {
  Future<bool> localGenerationAvailable();
}

/// System notifications for work that finishes while the app is out of view.
abstract interface class GenerationNotificationGateway {
  /// Asks for permission once; later calls report the stored decision.
  Future<bool> requestGenerationNotifications();

  /// Posts "your film is ready" for [item]; false when nothing was shown.
  Future<bool> notifyGenerationReady(Generation item);
}

/// The platform share sheet for a delivered film.
abstract interface class MediaShareGateway {
  Future<bool> shareMedia(Generation item);
}

AppGateway createGateway() => kIsWeb ? WebGateway() : NativeGateway();
