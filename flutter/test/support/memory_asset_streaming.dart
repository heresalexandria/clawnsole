import 'package:clawnsole/core/durable_data_store.dart';
import 'package:clawnsole/core/models.dart';

/// Keeps deliberately in-memory test stores on their fake backend when the
/// production store adds a streaming capability.
mixin MemoryAssetStreaming on DurableDataStore implements StreamingAssetStore {
  @override
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
  }) async => writeAsset(
    await collectSmallAssetStream(
      stream,
      expectedLength: expectedLength,
      expectedSha256: expectedSha256,
      maxBytes: maxBytes,
      idleTimeout: idleTimeout,
      totalTimeout: totalTimeout,
    ),
    label: label,
    contentType: contentType,
    storage: storage,
  );

  @override
  Future<Stream<List<int>>> openAssetRead(AssetReference reference) async =>
      Stream<List<int>>.value(await readAsset(reference));
}
