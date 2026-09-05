import 'asset_stream_base.dart';

Future<StagedAsset> stageAssetStream(
  Stream<List<int>> source, {
  String? directory,
  int? expectedLength,
  String? expectedSha256,
  int maxBytes = maxRetainedAssetBytes,
  Duration idleTimeout = assetStreamIdleTimeout,
  Duration totalTimeout = assetStreamTotalTimeout,
}) =>
    throw UnsupportedError('Browser media retention uses the local companion.');
