import 'dart:async';

import 'package:clawnsole/app/busy_registry.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('a run marks its id, tells listeners, and clears when it finishes', () {
    final registry = BusyRegistry();
    addTearDown(registry.dispose);
    var notifications = 0;
    registry.addListener(() => notifications += 1);

    final gate = Completer<String>();
    expect(registry.isBusy('reference', 'photo'), isFalse);

    final work = registry.run('reference', 'photo', () => gate.future);
    expect(registry.isBusy('reference', 'photo'), isTrue);
    expect(registry.isAnyBusy, isTrue);
    expect(notifications, 1);

    gate.complete('saved');
    return work.then((value) {
      expect(value, 'saved');
      expect(registry.isBusy('reference', 'photo'), isFalse);
      expect(registry.isAnyBusy, isFalse);
      expect(notifications, 2);
    });
  });

  test('different ids and kinds stay apart', () async {
    final registry = BusyRegistry();
    addTearDown(registry.dispose);
    final first = Completer<void>();
    final second = Completer<void>();

    final a = registry.run('reference', 'photo', () => first.future);
    final b = registry.run('folder', 'photo', () => second.future);
    expect(registry.busyKeys, <String>{'reference:photo', 'folder:photo'});

    first.complete();
    await a;
    expect(registry.isBusy('reference', 'photo'), isFalse);
    expect(registry.isBusy('folder', 'photo'), isTrue);

    second.complete();
    await b;
    expect(registry.isAnyBusy, isFalse);
  });

  test('two runs on one id both have to finish before it clears', () async {
    final registry = BusyRegistry();
    addTearDown(registry.dispose);
    var notifications = 0;
    registry.addListener(() => notifications += 1);
    final outer = Completer<void>();
    final inner = Completer<void>();

    final a = registry.run('generation', 'film', () => outer.future);
    final b = registry.run('generation', 'film', () => inner.future);
    // One key, one notification: the row is already showing its loader.
    expect(notifications, 1);

    outer.complete();
    await a;
    expect(registry.isBusy('generation', 'film'), isTrue);
    expect(notifications, 1);

    inner.complete();
    await b;
    expect(registry.isBusy('generation', 'film'), isFalse);
    expect(notifications, 2);
  });

  test('a nested run on one id survives its inner run finishing', () async {
    final registry = BusyRegistry();
    addTearDown(registry.dispose);
    var seenInside = false;

    await registry.run('provider', 'runway', () async {
      await registry.run('provider', 'runway', () async {});
      seenInside = registry.isBusy('provider', 'runway');
    });

    expect(seenInside, isTrue);
    expect(registry.isBusy('provider', 'runway'), isFalse);
  });

  test('a throwing run clears the mark and passes the error on', () async {
    final registry = BusyRegistry();
    addTearDown(registry.dispose);

    await expectLater(
      registry.run<void>('folder', 'inbox', () async {
        expect(registry.isBusy('folder', 'inbox'), isTrue);
        throw StateError('drive said no');
      }),
      throwsA(isA<StateError>()),
    );
    expect(registry.isBusy('folder', 'inbox'), isFalse);
    expect(registry.isAnyBusy, isFalse);
  });

  test('work that outlives the registry does not wake it', () async {
    final registry = BusyRegistry();
    final gate = Completer<void>();
    final work = registry.run('reference', 'late', () => gate.future);
    registry.dispose();
    gate.complete();
    await work;
  });
}
