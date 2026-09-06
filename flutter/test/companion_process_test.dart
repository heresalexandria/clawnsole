import 'dart:async';

import 'package:flutter_test/flutter_test.dart';

import '../tool/clawnsole_companion.dart';

void main() {
  test(
    'a stray asynchronous error is logged and the companion keeps serving',
    () async {
      // An unhandled asynchronous error ends the Dart isolate, and the desktop
      // shell turns a second exit inside its restart budget into a "could not be
      // restarted" dialog. An abandoned download costs its own request, not the
      // user's session.
      final log = StringBuffer();
      final serving = Completer<void>();
      var stopped = false;
      final process = runCompanionProcess(() async {
        unawaited(
          Future<void>.error(StateError('The media client is closed.')),
        );
        await serving.future;
      }, log: log);
      unawaited(process.whenComplete(() => stopped = true));
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(stopped, isFalse);
      expect(log.toString(), contains('The media client is closed.'));
      expect(log.toString(), contains('Unhandled companion error'));
      serving.complete();
      await process;
      expect(stopped, isTrue);
    },
  );

  test('a companion that cannot start still ends the process', () async {
    // The shell can relaunch a companion that failed to start; it cannot
    // recover one that is listening on nothing.
    final log = StringBuffer();
    await expectLater(
      runCompanionProcess(
        () async => throw StateError('Failed to bind the companion port.'),
        log: log,
      ),
      throwsStateError,
    );
    expect(log.toString(), isEmpty);
  });
}
