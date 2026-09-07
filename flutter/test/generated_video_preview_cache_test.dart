import 'dart:async';
import 'dart:typed_data';

import 'package:clawnsole/ui/generated_video_preview_cache.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final binding = TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'completed jobs release progress records and retain bounded bytes',
    () async {
      final cache = GeneratedVideoPreviewCache(maximumBytes: 10);
      addTearDown(cache.dispose);
      final reads = <String>[];
      Future<GeneratedVideoPreview?> read(String key) => cache
          .load(
            key,
            expectedDuration: const Duration(seconds: 1),
            loader: () async {
              reads.add(key);
              return GeneratedVideoPreview(
                thumbnail: Uint8List(3),
                timeline: Uint8List(3),
              );
            },
          )
          .future;
      await read('first');
      await read('second');
      expect(cache.pendingCount, 0);
      expect(cache.retainedBytes, 6);
      expect(cache.lookup('first'), isNull);
      await read('second');
      expect(reads, ['first', 'second']);
      await read('first');
      expect(reads, ['first', 'second', 'first']);
      expect(cache.retainedBytes, 6);
    },
  );

  test(
    'oversized backing buffers do not survive through completed jobs',
    () async {
      final cache = GeneratedVideoPreviewCache(maximumBytes: 10);
      addTearDown(cache.dispose);
      final preview = GeneratedVideoPreview(
        thumbnail: Uint8List.view(Uint8List(20).buffer, 0, 1),
      );
      final result = await cache
          .load(
            'oversized',
            expectedDuration: Duration.zero,
            loader: () async => preview,
          )
          .future;
      expect(result, same(preview));
      expect(cache.retainedBytes, 0);
      expect(cache.pendingCount, 0);
      expect(cache.lookup('oversized'), isNull);
    },
  );

  test(
    'pressure clears bytes and pending completion cannot restore them',
    () async {
      final cache = GeneratedVideoPreviewCache(maximumBytes: 10);
      addTearDown(cache.dispose);
      final pending = Completer<GeneratedVideoPreview?>();
      var reads = 0;
      GeneratedVideoPreviewJob load() => cache.load(
        'pending',
        expectedDuration: Duration.zero,
        loader: () {
          reads += 1;
          return pending.future;
        },
      );
      final first = load();
      binding.handleMemoryPressure();
      expect(load(), same(first));
      expect(cache.pendingCount, 1);
      pending.complete(GeneratedVideoPreview(thumbnail: Uint8List(4)));
      expect((await first.future)?.thumbnail.length, 4);
      expect(cache.pendingCount, 0);
      expect(cache.retainedBytes, 0);
      expect(cache.lookup('pending'), isNull);
      await load().future;
      expect(reads, 2);
      expect(cache.retainedBytes, 4);
      binding.handleMemoryPressure();
      expect(cache.retainedBytes, 0);
    },
  );

  test('failed and unavailable jobs are released for retry', () async {
    final cache = GeneratedVideoPreviewCache();
    addTearDown(cache.dispose);
    await expectLater(
      cache
          .load(
            'failed',
            expectedDuration: Duration.zero,
            loader: () => throw StateError('offline'),
          )
          .future,
      throwsStateError,
    );
    expect(cache.pendingCount, 0);
    expect(cache.lookup('failed'), isNull);
    expect(
      await cache
          .load(
            'failed',
            expectedDuration: Duration.zero,
            loader: () async => null,
          )
          .future,
      isNull,
    );
    expect(cache.pendingCount, 0);
    expect(cache.lookup('failed'), isNull);
  });
}
