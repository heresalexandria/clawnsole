import 'package:flutter/foundation.dart';

import 'models.dart';
import 'native_gateway.dart';
import 'web_gateway.dart';

abstract interface class AppGateway {
  bool get usesCompanion;
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
}

AppGateway createGateway() => kIsWeb ? WebGateway() : NativeGateway();
