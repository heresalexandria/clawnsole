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
  final value = source.source.trim();
  if (retained?.isLocal == true) {
    try {
      return await stageAssetStream(
        await store.openAssetRead(retained!),
        directory: directory,
        expectedLength: retained.bytes,
        expectedSha256: retained.sha256,
        maxBytes: maxBytes,
      );
    } on Object {
      // A background Drive upload can move this staged file into its cache
      // after the submission captured the local reference. The submitted
      // inline media remains a complete source even when that file is gone;
      // its retained size/checksum below still require identical bytes.
      // Await staging above so a lazy file stream failure takes this path too.
      if (!value.startsWith('data:')) rethrow;
    }
  }
  if (value.startsWith('data:')) {
    // Reject clearly oversized inline payloads before decoding a second copy.
    if (value.length > maxBytes * 4 + 4096) {
      throw const AssetTransferException('The media exceeds its allowed size.');
    }
    final bytes = UriData.parse(value).contentAsBytes();
    return stageAssetStream(
      Stream.value(bytes),
      directory: directory,
      expectedLength: retained?.bytes ?? bytes.length,
      expectedSha256: retained?.sha256,
      maxBytes: maxBytes,
    );
  }
  // Renderer requests may name app-owned assets or carry imported bytes, but
  // must never turn this privileged host into an arbitrary local-file reader.
  throw StateError(
    'The original media is unavailable. Import it into Clawnsole before generating.',
  );
}
