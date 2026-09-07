import 'dart:async';
import 'dart:typed_data';

import 'package:clawnsole/core/async_value_cache.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('synchronous values and reads share the same eviction budget', () async {
    final cache = AsyncValueCache<int>(maximumWeight: 10, weightOf: (n) => n);
    cache.put('first', 4);
    cache.put('second', 4);
    expect(cache.lookup('first'), 4);
    cache.put('third', 4);
    expect(cache.lookup('second'), isNull);
    expect(cache.lookupFuture('second'), isNull);
    expect(cache.retainedWeight, 8);
    cache.put('first', 3);
    expect(cache.retainedWeight, 7);
    expect(await cache.load('first', () => throw StateError('refetch')), 3);
    cache.remove('first');
    expect(cache.retainedWeight, 4);
    cache.put('oversized', 11);
    expect(cache.lookup('oversized'), isNull);
    expect(cache.retainedWeight, 4);
  });

  test('synchronous replacement survives an older pending load', () async {
    final cache = AsyncValueCache<int>(maximumWeight: 10, weightOf: (n) => n);
    final pending = Completer<int>();
    final result = cache.load('preview', () => pending.future);
    expect(cache.lookup('preview'), isNull);
    cache.put('preview', 3);
    pending.complete(4);
    expect(await result, 4);
    expect(cache.lookup('preview'), 3);
    expect(cache.retainedWeight, 3);
  });

  test('byte budget evicts least recently used completed values', () async {
    final cache = AsyncValueCache<Uint8List>(
      maximumWeight: 10,
      weightOf: (bytes) => bytes.buffer.lengthInBytes,
    );
    final reads = <String, int>{};
    Future<Uint8List> read(String key) => cache.load(key, () async {
      reads.update(key, (count) => count + 1, ifAbsent: () => 1);
      return Uint8List(4);
    });
    await read('a');
    await read('b');
    await read('a');
    await read('c');
    expect(cache.retainedWeight, 8);
    expect(cache.length, 2);
    await read('a');
    expect(reads['a'], 1);
    await read('b');
    expect(reads['b'], 2);
    expect(cache.retainedWeight, lessThanOrEqualTo(10));
  });

  test(
    'oversized buffers are served but not retained, including views',
    () async {
      final cache = AsyncValueCache<Uint8List>(
        maximumWeight: 10,
        weightOf: (bytes) => bytes.buffer.lengthInBytes,
      );
      var reads = 0;
      Future<Uint8List> read() => cache.load('large', () async {
        reads += 1;
        return Uint8List.view(Uint8List(20).buffer, 0, 2);
      });
      expect((await read()).length, 2);
      expect(cache.retainedWeight, 0);
      expect(cache.length, 0);
      await read();
      expect(reads, 2);
    },
  );

  test('concurrent consumers share one pending load', () async {
    final cache = AsyncValueCache<int>(maximumWeight: 10, weightOf: (_) => 1);
    final pending = Completer<int>();
    var calls = 0;
    Future<int> read() => cache.load('same', () {
      calls += 1;
      return pending.future;
    });
    final first = read();
    final second = read();
    expect(identical(first, second), isTrue);
    pending.complete(5);
    expect(await first, 5);
    expect(await second, 5);
    expect(calls, 1);
  });

  test('cleared or evicted work cannot restore retained memory', () async {
    final cache = AsyncValueCache<int>(
      maximumWeight: 10,
      maximumEntries: 1,
      weightOf: (_) => 1,
    );
    final oldLoad = Completer<int>();
    final old = cache.load('old', () => oldLoad.future);
    await cache.load('new', () async => 2);
    oldLoad.complete(1);
    expect(await old, 1);
    expect(cache.length, 1);
    expect(cache.retainedWeight, 1);
    final pending = Completer<int>();
    final work = cache.load('pending', () => pending.future);
    cache.clear();
    pending.complete(3);
    expect(await work, 3);
    expect(cache.length, 0);
    expect(cache.retainedWeight, 0);
  });

  test('failed and unavailable results can be retried', () async {
    final cache = AsyncValueCache<int?>(maximumWeight: 10, weightOf: (_) => 1);
    await expectLater(
      cache.load('value', () => throw StateError('offline')),
      throwsStateError,
    );
    expect(cache.length, 0);
    expect(await cache.load('value', () async => null), isNull);
    expect(cache.length, 0);
    expect(await cache.load('value', () async => 7), 7);
    expect(cache.length, 1);
  });
}
