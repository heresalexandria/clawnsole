import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:clawnsole/core/video_cache.dart';

/// Isolated local cache experiment; no network, credentials or user library.
/// Run `dart run tool/cache_memory_benchmark.dart 250` from flutter/.
Future<void> main(List<String> arguments) async {
  final sizeMiB = arguments.isEmpty ? 50 : int.parse(arguments.single);
  if (sizeMiB <= 0 || sizeMiB > 1024) {
    throw ArgumentError('Choose a fixture size from 1 to 1024 MiB.');
  }
  final directory = await Directory.systemTemp.createTemp(
    'clawnsole-cache-rss-',
  );
  final cache = VideoCache(directory: () async => directory);
  final chunk = Uint8List(64 * 1024);
  final baseline = ProcessInfo.currentRss;
  var peak = baseline;
  final sample = Timer.periodic(const Duration(milliseconds: 5), (_) {
    final rss = ProcessInfo.currentRss;
    if (rss > peak) peak = rss;
  });
  final watch = Stopwatch()..start();
  try {
    Stream<List<int>> source() async* {
      for (var index = 0; index < sizeMiB * 16; index++) {
        yield chunk;
      }
    }

    final file = await cache.put(
      'fixture',
      '.mp4',
      source(),
      expectedLength: sizeMiB * 1024 * 1024,
    );
    if (await file.length() != sizeMiB * 1024 * 1024) {
      throw StateError('Incorrect cached fixture length.');
    }
    stdout.writeln(
      jsonEncode({
        'sizeMiB': sizeMiB,
        'elapsedMs': watch.elapsedMilliseconds,
        'baselineRss': baseline,
        'peakRss': peak,
        'increaseBytes': peak - baseline,
      }),
    );
  } finally {
    sample.cancel();
    await directory.delete(recursive: true);
  }
}
