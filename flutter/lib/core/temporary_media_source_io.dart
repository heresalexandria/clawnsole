import 'dart:io';

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
  final uri = Uri.tryParse(value);
  final file = uri?.scheme == 'file'
      ? File.fromUri(uri!)
      : value.isNotEmpty && (uri?.scheme.isEmpty == true || Platform.isWindows)
      ? File(value)
      : null;
  if (file == null || !file.isAbsolute || !await file.exists()) {
    throw StateError(
      'The original media is unavailable. Restore it before generating.',
    );
  }
  return stageAssetStream(
    file.openRead(),
    directory: directory,
    expectedLength: await file.length(),
    maxBytes: maxBytes,
  );
}
