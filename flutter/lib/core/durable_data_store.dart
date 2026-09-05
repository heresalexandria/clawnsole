import 'dart:typed_data';

import 'models.dart';
import 'asset_stream_base.dart';

export 'asset_stream_base.dart';

/// Durable metadata and media used by a direct-to-provider gateway.
///
/// Native builds implement this with app-document files. Electron uses the
/// same contract through its loopback companion. Provider credentials live
/// behind a separate secure-storage boundary.
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

/// Optional capability keeps existing small custom stores source-compatible.
/// All native and companion production stores implement this contract.
abstract interface class StreamingAssetStore {
  Future<AssetReference> writeAssetStream(
    Stream<List<int>> stream, {
    required String label,
    required String contentType,
    LibraryStorage storage = LibraryStorage.local,
    int? expectedLength,
    String? expectedSha256,
    int maxBytes = maxRetainedAssetBytes,
    Duration idleTimeout = assetStreamIdleTimeout,
    Duration totalTimeout = assetStreamTotalTimeout,
  });

  Future<Stream<List<int>>> openAssetRead(AssetReference reference);
}

extension DurableAssetStreaming on DurableDataStore {
  Future<AssetReference> writeAssetStream(
    Stream<List<int>> stream, {
    required String label,
    required String contentType,
    LibraryStorage storage = LibraryStorage.local,
    int? expectedLength,
    String? expectedSha256,
    int maxBytes = maxRetainedAssetBytes,
    Duration idleTimeout = assetStreamIdleTimeout,
    Duration totalTimeout = assetStreamTotalTimeout,
  }) async {
    final target = this;
    if (target is StreamingAssetStore) {
      return (target as StreamingAssetStore).writeAssetStream(
        stream,
        label: label,
        contentType: contentType,
        storage: storage,
        expectedLength: expectedLength,
        expectedSha256: expectedSha256,
        maxBytes: maxBytes,
        idleTimeout: idleTimeout,
        totalTimeout: totalTimeout,
      );
    }
    final bytes = await collectSmallAssetStream(
      stream,
      expectedLength: expectedLength,
      expectedSha256: expectedSha256,
      maxBytes: maxBytes < 8 * 1024 * 1024 ? maxBytes : 8 * 1024 * 1024,
      idleTimeout: idleTimeout,
      totalTimeout: totalTimeout,
    );
    return writeAsset(
      bytes,
      label: label,
      contentType: contentType,
      storage: storage,
    );
  }

  Future<Stream<List<int>>> openAssetRead(AssetReference reference) async {
    final target = this;
    if (target is StreamingAssetStore) {
      return (target as StreamingAssetStore).openAssetRead(reference);
    }
    return Stream<List<int>>.value(await readAsset(reference));
  }
}
