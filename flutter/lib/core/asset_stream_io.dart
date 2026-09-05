import 'dart:async';
import 'dart:io';

import 'asset_stream_base.dart';

Future<StagedAsset> stageAssetStream(
  Stream<List<int>> source, {
  String? directory,
  int? expectedLength,
  String? expectedSha256,
  int maxBytes = maxRetainedAssetBytes,
  Duration idleTimeout = assetStreamIdleTimeout,
  Duration totalTimeout = assetStreamTotalTimeout,
}) async {
  final watch = Stopwatch()..start();
  Duration remaining() {
    final value = totalTimeout - watch.elapsed;
    if (value <= Duration.zero) {
      throw TimeoutException('The media transfer exceeded its total deadline.');
    }
    return value;
  }

  final root = directory == null ? Directory.systemTemp : Directory(directory);
  Directory? staging;
  RandomAccessFile? sink;
  var ownsSource = false;
  try {
    await root.create(recursive: true);
    staging = await root.createTemp('.clawnsole-retain-');
    final file = File('${staging.path}${Platform.pathSeparator}media.part');
    sink = await file.open(mode: FileMode.writeOnly);
    ownsSource = true;
    final result = await consumeAssetStream(
      source,
      write: (chunk) async {
        await sink!.writeFrom(chunk);
      },
      expectedLength: expectedLength,
      expectedSha256: expectedSha256,
      maxBytes: maxBytes,
      idleTimeout: idleTimeout,
      totalTimeout: remaining(),
    );
    await sink.flush().timeout(remaining());
    await sink.close().timeout(remaining());
    sink = null;
    return _FileStagedAsset(file, staging, result.length, result.sha256);
  } on Object {
    if (!ownsSource) await source.listen(null).cancel();
    try {
      await sink?.close();
    } on Object {
      /* Preserve the original failure. */
    }
    if (staging != null) {
      try {
        await staging.delete(recursive: true);
      } on Object {
        /* Retryable cleanup. */
      }
    }
    rethrow;
  }
}

class _FileStagedAsset implements StagedAsset {
  _FileStagedAsset(this.file, this.directory, this.length, this.sha256);
  final File file;
  final Directory directory;
  @override
  String get path => file.path;
  @override
  final int length;
  @override
  final String sha256;
  @override
  Stream<List<int>> openRead() => file.openRead();
  @override
  Future<void> dispose() async {
    if (await directory.exists()) await directory.delete(recursive: true);
  }
}
