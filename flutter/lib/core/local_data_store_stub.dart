import 'dart:typed_data';

import 'models.dart';

class LocalDataStore {
  Future<StoredData> read() => throw UnsupportedError(
    'Browser builds use the Clawnsole local companion service.',
  );

  Future<void> write(StoredData data) => throw UnsupportedError(
    'Browser builds use the Clawnsole local companion service.',
  );

  Future<void> delete() => throw UnsupportedError(
    'Browser builds use the Clawnsole local companion service.',
  );

  Future<AssetReference> writeAsset(
    Uint8List bytes, {
    required String label,
    required String contentType,
  }) => throw UnsupportedError('Browser builds use the local companion.');

  Future<AssetReference?> persistSource(
    String source, {
    required String label,
    AssetReference? retained,
  }) => throw UnsupportedError('Browser builds use the local companion.');

  Future<Uint8List> readAsset(AssetReference reference) =>
      throw UnsupportedError('Browser builds use the local companion.');

  Future<Uri> assetUri(AssetReference reference) =>
      throw UnsupportedError('Browser builds use the local companion.');

  Future<void> pruneAssets(List<Generation> generations) =>
      throw UnsupportedError('Browser builds use the local companion.');

  Future<void> clearAssets() =>
      throw UnsupportedError('Browser builds use the local companion.');

  Future<StorageStats> stats(int records) => throw UnsupportedError(
    'Browser builds use the Clawnsole local companion service.',
  );
}
