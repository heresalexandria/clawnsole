import 'dart:async';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';

const maxRetainedAssetBytes = 2 * 1024 * 1024 * 1024;
const assetStreamIdleTimeout = Duration(seconds: 30);
const assetStreamTotalTimeout = Duration(minutes: 8);

/// A verified, private staging file. The caller owns cleanup until it publishes
/// the file atomically or completes a remote upload.
abstract class StagedAsset {
  String get path;
  int get length;
  String get sha256;
  Stream<List<int>> openRead();
  Future<void> dispose();
}

class AssetTransferException implements Exception {
  const AssetTransferException(this.message);
  final String message;
  @override
  String toString() => message;
}

/// Consumes one chunk at a time, applying backpressure to the producer. Both
/// the source and sink count against the total deadline. Partial data is never
/// considered a successful asset.
Future<({int length, String sha256})> consumeAssetStream(
  Stream<List<int>> source, {
  required Future<void> Function(List<int>) write,
  int? expectedLength,
  String? expectedSha256,
  int maxBytes = maxRetainedAssetBytes,
  Duration idleTimeout = assetStreamIdleTimeout,
  Duration totalTimeout = assetStreamTotalTimeout,
}) async {
  final iterator = StreamIterator(source);
  final clock = Stopwatch()..start();
  var length = 0;
  Digest? digest;
  final hash = sha256.startChunkedConversion(
    _DigestSink((value) => digest = value),
  );
  Duration remaining() {
    final time = totalTimeout - clock.elapsed;
    if (time <= Duration.zero) {
      throw TimeoutException('The media transfer exceeded its total deadline.');
    }
    return time;
  }

  try {
    if (maxBytes <= 0 || expectedLength != null && expectedLength < 0) {
      throw const AssetTransferException('The media size is invalid.');
    }
    if (expectedLength != null && expectedLength > maxBytes) {
      throw const AssetTransferException(
        'The media exceeds the retention size limit.',
      );
    }
    while (await iterator.moveNext().timeout(
      remaining() < idleTimeout ? remaining() : idleTimeout,
    )) {
      final chunk = iterator.current;
      length += chunk.length;
      if (length > maxBytes ||
          expectedLength != null && length > expectedLength) {
        throw const AssetTransferException(
          'The media exceeds its allowed size.',
        );
      }
      hash.add(chunk);
      await write(chunk).timeout(remaining());
    }
    if (length == 0 || expectedLength != null && length != expectedLength) {
      throw const AssetTransferException(
        'The media transfer was empty or truncated.',
      );
    }
    hash.close();
    final checksum = digest.toString();
    if (expectedSha256 != null && checksum != expectedSha256.toLowerCase()) {
      throw const AssetTransferException('The media checksum did not match.');
    }
    return (length: length, sha256: checksum);
  } finally {
    clock.stop();
    await iterator.cancel();
  }
}

class _DigestSink implements Sink<Digest> {
  _DigestSink(this.onDigest);
  final void Function(Digest) onDigest;
  @override
  void add(Digest data) => onDigest(data);
  @override
  void close() {}
}

/// Compatibility for small in-memory stores. Production native/companion
/// stores implement StreamingAssetStore and never take this path for results.
Future<Uint8List> collectSmallAssetStream(
  Stream<List<int>> source, {
  int? expectedLength,
  String? expectedSha256,
  int maxBytes = 8 * 1024 * 1024,
  Duration idleTimeout = assetStreamIdleTimeout,
  Duration totalTimeout = assetStreamTotalTimeout,
}) async {
  final builder = BytesBuilder(copy: false);
  await consumeAssetStream(
    source,
    write: (chunk) async => builder.add(chunk),
    expectedLength: expectedLength,
    expectedSha256: expectedSha256,
    maxBytes: maxBytes,
    idleTimeout: idleTimeout,
    totalTimeout: totalTimeout,
  );
  return builder.takeBytes();
}
