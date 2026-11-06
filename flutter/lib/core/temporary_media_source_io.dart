import 'asset_stream.dart';
import 'durable_data_store.dart';
import 'temporary_media_host.dart';

/// Stages app-owned media for a hosting backend without fetching arbitrary URLs.
/// The backend owns disposal of the returned private staging file.
Future<StagedAsset> stageTemporaryMediaSource(
  TemporaryMediaSource source,
  DurableDataStore store, {
  String? directory,
  int maxBytes = maxRetainedAssetBytes,
}) async {
  if (isPublicTemporaryMediaSource(source.source)) {
    throw StateError('Public HTTPS media does not need temporary hosting.');
  }
  final retained = source.retained;
  if (retained?.isLocal == true) {
    return stageAssetStream(
      await store.openAssetRead(retained!),
      directory: directory,
      expectedLength: retained.bytes,
      expectedSha256: retained.sha256,
      maxBytes: maxBytes,
    );
  }
  final value = source.source.trim();
  if (value.startsWith('data:')) {
    // Reject clearly oversized inline payloads before decoding a second copy.
    if (value.length > maxBytes * 4 + 4096) {
      throw const AssetTransferException('The media exceeds its allowed size.');
    }
    final bytes = UriData.parse(value).contentAsBytes();
    return stageAssetStream(
      Stream.value(bytes),
      directory: directory,
      expectedLength: bytes.length,
      maxBytes: maxBytes,
    );
  }
  // Renderer requests may name app-owned assets or carry imported bytes, but
  // must never turn this privileged host into an arbitrary local-file reader.
  throw StateError(
    'The original media is unavailable. Import it into Clawnsole before generating.',
  );
}
