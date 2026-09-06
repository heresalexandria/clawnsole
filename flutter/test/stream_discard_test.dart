import 'dart:async';

import 'package:clawnsole/core/stream_discard.dart';
import 'package:flutter_test/flutter_test.dart';

/// A source that fails as it is torn down, the way an aborted media client or
/// a cancelled transfer surfaces its abort on the reader that gave up on it.
Stream<int> _failsWhileReleased() async* {
  throw StateError('The media client is closed.');
}

void main() {
  test('discarding releases the source', () async {
    var cancelled = false;
    final controller = StreamController<int>(onCancel: () => cancelled = true);
    controller.add(1);
    await discardStream(controller.stream);
    expect(cancelled, isTrue);
    expect(controller.hasListener, isFalse);
  });

  test(
    'a source that fails while being released keeps the caller\'s failure',
    () async {
      // The caller is already throwing the error worth reporting — "connect
      // Google Drive", "the download returned HTTP 404" — so releasing the
      // stream must not replace it with the teardown's own failure.
      await expectLater(
        _failsWhileReleased().listen(null).cancel(),
        throwsStateError,
      );
      await discardStream(_failsWhileReleased());
    },
  );

  test('releasing a stream in the background never reaches the zone', () async {
    // An unawaited discard has nowhere to report a teardown failure, so it
    // reaches the zone and ends the isolate. The companion serves a desktop
    // app: one abandoned download must not cost the session.
    final escaped = <Object>[];
    final settled = Completer<void>();
    runZonedGuarded(() async {
      unawaited(discardStream(_failsWhileReleased()));
      await Future<void>.delayed(const Duration(milliseconds: 20));
      settled.complete();
    }, (error, stack) => escaped.add(error));
    await settled.future;
    expect(escaped, isEmpty);

    final unguarded = <Object>[];
    final raised = Completer<void>();
    runZonedGuarded(() async {
      unawaited(_failsWhileReleased().listen(null).cancel());
      await Future<void>.delayed(const Duration(milliseconds: 20));
      raised.complete();
    }, (error, stack) => unguarded.add(error));
    await raised.future;
    expect(
      unguarded,
      hasLength(1),
      reason: 'listen(null) has no error handler',
    );
  });
}
