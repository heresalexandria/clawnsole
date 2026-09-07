import 'dart:async';

import 'package:clawnsole/core/async_work_pool.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('limits active work and drains queued work in order', () async {
    final pool = AsyncWorkPool(maximumConcurrent: 2);
    final gates = List.generate(5, (_) => Completer<int>());
    final started = <int>[];
    final jobs = List.generate(
      5,
      (index) => pool.run(() {
        started.add(index);
        return gates[index].future;
      }),
    );
    expect(started, [0, 1]);
    gates[1].complete(1);
    await jobs[1];
    await Future<void>.delayed(Duration.zero);
    expect(started, [0, 1, 2]);
    gates[0].complete(0);
    gates[2].complete(2);
    await Future.wait([jobs[0], jobs[2]]);
    await Future<void>.delayed(Duration.zero);
    expect(started, [0, 1, 2, 3, 4]);
    gates[3].complete(3);
    gates[4].complete(4);
    expect(await Future.wait(jobs), [0, 1, 2, 3, 4]);
  });

  test('synchronous and asynchronous failures release their slots', () async {
    final pool = AsyncWorkPool(maximumConcurrent: 1);
    final first = pool.run<int>(() => throw StateError('synchronous'));
    final second = pool.run<int>(() async => throw StateError('asynchronous'));
    final third = pool.run(() async => 3);
    await Future.wait([
      expectLater(first, throwsStateError),
      expectLater(second, throwsStateError),
    ]);
    expect(await third, 3);
  });
}
