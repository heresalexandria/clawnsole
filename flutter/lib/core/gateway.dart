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
  Future<void> saveVideoToPhotoLibrary(Uint8List bytes, String fileName);
}

/// Provider-aware operations implemented by the production gateways. Keeping
/// this separate preserves compatibility with lightweight BFL-only test and
/// embedder gateways while the app can route LTX and Atlas Cloud explicitly.
abstract interface class ProviderGateway {
  Future<LocalSnapshot> setProviderApiKey(String provider, String value);
  Future<ProviderAccountStatus> verifyProviderKey(
    String provider, [
    String? candidate,
  ]);
  Future<ProviderAccountStatus> getProviderAccount(String provider);
  Future<LocalSnapshot> clearProviderApiKey(String provider);
  Future<List<ProviderModelPrice>> listProviderModels(String provider);
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

AppGateway createGateway() => kIsWeb ? WebGateway() : NativeGateway();
