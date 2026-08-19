import 'dart:typed_data';

import 'models.dart';

/// Durable metadata and media used by a direct-to-provider gateway.
///
/// Native builds implement this with app-document files. The standalone web
/// build implements it with a user-authorized Google Drive folder while
/// keeping provider credentials in browser-local storage.
abstract interface class DurableDataStore {
  Future<StoredData> read();
  Future<void> write(StoredData data);
  Future<void> delete();

  Future<AssetReference> writeAsset(
    Uint8List bytes, {
    required String label,
    required String contentType,
    LibraryStorage storage = LibraryStorage.local,
  });

  Future<AssetReference?> persistSource(
    String source, {
    required String label,
    AssetReference? retained,
    LibraryStorage storage = LibraryStorage.local,
  });

  Future<Uint8List> readAsset(AssetReference reference);
  Future<Uri> assetUri(AssetReference reference);

  Future<void> pruneAssets(
    List<Generation> generations, [
    List<SavedReference> savedReferences,
  ]);

  Future<StorageStats> stats(int records);
}
