import 'dart:typed_data';

import 'durable_data_store.dart';
import 'models.dart';

class LocalDataStore implements DurableDataStore {
  Future<bool> exists() => throw UnsupportedError(
    'Browser builds use the Clawnsole local companion service.',
  );

  Future<String> dataDirectoryPath() =>
      throw UnsupportedError('Browser builds use the local companion.');

  Future<bool> hasLibraryAt(String directory) =>
      throw UnsupportedError('Browser builds use the local companion.');

  Future<void> relocate(String directory, {bool useExistingLibrary = false}) =>
      throw UnsupportedError('Browser builds use the local companion.');

  @override
  Future<StoredData> read() => throw UnsupportedError(
    'Browser builds use the Clawnsole local companion service.',
  );

  @override
  Future<void> write(StoredData data) => throw UnsupportedError(
    'Browser builds use the Clawnsole local companion service.',
  );

  @override
  Future<void> delete() => throw UnsupportedError(
    'Browser builds use the Clawnsole local companion service.',
  );

  @override
  Future<AssetReference> writeAsset(
    Uint8List bytes, {
    required String label,
    required String contentType,
    LibraryStorage storage = LibraryStorage.local,
  }) => throw UnsupportedError('Browser builds use the local companion.');

  @override
  Future<AssetReference?> persistSource(
    String source, {
    required String label,
    AssetReference? retained,
    LibraryStorage storage = LibraryStorage.local,
  }) => throw UnsupportedError('Browser builds use the local companion.');

  @override
  Future<Uint8List> readAsset(AssetReference reference) =>
      throw UnsupportedError('Browser builds use the local companion.');

  @override
  Future<Uri> assetUri(AssetReference reference) =>
      throw UnsupportedError('Browser builds use the local companion.');

  @override
  Future<void> pruneAssets(
    List<Generation> generations, [
    List<SavedReference> savedReferences = const <SavedReference>[],
  ]) => throw UnsupportedError('Browser builds use the local companion.');

  Future<void> clearAssets() =>
      throw UnsupportedError('Browser builds use the local companion.');

  @override
  Future<StorageStats> stats(int records) => throw UnsupportedError(
    'Browser builds use the Clawnsole local companion service.',
  );
}
