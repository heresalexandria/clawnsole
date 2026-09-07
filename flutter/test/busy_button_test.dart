import 'dart:async';

import 'package:clawnsole/ui/busy_button.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Future<void> _pump(WidgetTester tester, Widget child) => tester.pumpWidget(
  MaterialApp(
    home: Scaffold(body: Center(child: child)),
  ),
);

Finder get _spinner => find.byType(CircularProgressIndicator);

void main() {
  testWidgets('an icon button swaps its icon for the busy mark and back', (
    tester,
  ) async {
    final gate = Completer<void>();
    var runs = 0;
    await _pump(
      tester,
      BusyFilledButton.icon(
        onPressed: () async {
          runs += 1;
          await gate.future;
        },
        icon: const Icon(Icons.download_rounded, size: 16),
        label: const Text('Download'),
      ),
    );

    final button = find.byType(FilledButton);
    final idleSize = tester.getSize(button);
    final iconCentre = tester.getCenter(find.byIcon(Icons.download_rounded));
    expect(tester.widget<FilledButton>(button).onPressed, isNotNull);
    expect(_spinner, findsNothing);

    await tester.tap(button);
    await tester.pump();

    // Disabled, spinning where the icon stood, and the same size as before:
    // the row must not shuffle when the work starts.
    expect(tester.widget<FilledButton>(button).onPressed, isNull);
    expect(_spinner, findsOneWidget);
    expect(tester.getSize(_spinner), const Size(14, 14));
    expect(
      tester.widget<CircularProgressIndicator>(_spinner).strokeWidth,
      kBusySpinnerStroke,
    );
    expect(tester.getCenter(_spinner), iconCentre);
    expect(tester.getSize(button), idleSize);
    expect(find.text('Download'), findsOneWidget);
    expect(find.byIcon(Icons.download_rounded), findsNothing);

    // A second tap while the first run is pending is not a second run.
    await tester.tap(button, warnIfMissed: false);
    await tester.pump();
    expect(runs, 1);

    gate.complete();
    await tester.pumpAndSettle();

    expect(_spinner, findsNothing);
    expect(find.byIcon(Icons.download_rounded), findsOneWidget);
    expect(tester.widget<FilledButton>(button).onPressed, isNotNull);
    expect(tester.getSize(button), idleSize);
  });

  testWidgets('a plain button keeps its label and leads it with the mark', (
    tester,
  ) async {
    final gate = Completer<void>();
    await _pump(
      tester,
      BusyFilledButton(
        onPressed: () => gate.future,
        busyLabel: 'Saving…',
        child: const Text('Save'),
      ),
    );

    final button = find.byType(FilledButton);
    final idleSize = tester.getSize(button);
    await tester.tap(button);
    await tester.pump();

    expect(_spinner, findsOneWidget);
    expect(tester.getSize(_spinner), const Size(14, 14));
    expect(find.text('Saving…'), findsOneWidget);
    expect(find.text('Save'), findsNothing);
    // The mark leads the label, and the button never shrinks under it.
    expect(
      tester.getCenter(_spinner).dx,
      lessThan(tester.getCenter(find.text('Saving…')).dx),
    );
    expect(tester.getSize(button).width, greaterThanOrEqualTo(idleSize.width));

    gate.complete();
    await tester.pumpAndSettle();
    expect(_spinner, findsNothing);
    expect(find.text('Save'), findsOneWidget);
  });

  testWidgets('an exception clears the busy state and then propagates', (
    tester,
  ) async {
    Completer<void>? gate;
    await _pump(
      tester,
      BusyOutlinedButton.icon(
        onPressed: () => (gate = Completer<void>()).future,
        icon: const Icon(Icons.refresh_rounded, size: 16),
        label: const Text('Retry'),
      ),
    );

    final button = find.byType(OutlinedButton);
    // The button drops the future it started, exactly as the hand-rolled
    // `unawaited(...)` call sites did, so a failure still reaches the zone
    // instead of dying inside the loader. Pressing from a guarded zone is
    // what lets the test watch that happen.
    Object? escaped;
    runZonedGuarded(
      () => tester.widget<OutlinedButton>(button).onPressed!(),
      (error, stack) => escaped = error,
    );
    await tester.pump();
    expect(_spinner, findsOneWidget);

    gate!.completeError(StateError('the gateway said no'));
    await tester.pumpAndSettle();

    expect(escaped, isA<StateError>());
    expect(_spinner, findsNothing);
    expect(tester.widget<OutlinedButton>(button).onPressed, isNotNull);
  });

  testWidgets('the busy override drives the button on its own', (tester) async {
    Widget build(bool busy) => BusyTextButton(
      onPressed: () async {},
      busy: busy,
      busyLabel: 'Working…',
      child: const Text('Test'),
    );

    await _pump(tester, build(true));
    expect(_spinner, findsOneWidget);
    expect(find.text('Working…'), findsOneWidget);
    expect(
      tester.widget<TextButton>(find.byType(TextButton)).onPressed,
      isNull,
    );

    await _pump(tester, build(false));
    await tester.pump();
    expect(_spinner, findsNothing);
    expect(
      tester.widget<TextButton>(find.byType(TextButton)).onPressed,
      isNotNull,
    );
  });

  testWidgets('a button that leaves mid-flight never sets state after all', (
    tester,
  ) async {
    final gate = Completer<void>();
    await _pump(
      tester,
      BusyIconButton(
        onPressed: () => gate.future,
        tooltip: 'Remove',
        icon: const Icon(Icons.close_rounded),
      ),
    );

    await tester.tap(find.byType(IconButton));
    await tester.pump();
    expect(_spinner, findsOneWidget);

    await _pump(tester, const Text('gone'));
    gate.complete();
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.text('gone'), findsOneWidget);
  });

  testWidgets('a gate disables a dialog’s siblings while its action runs', (
    tester,
  ) async {
    final gate = Completer<void>();
    await _pump(
      tester,
      BusyGate(
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            BusyGateBuilder(
              builder: (context, busy) => TextButton(
                onPressed: busy ? null : () {},
                child: const Text('Cancel'),
              ),
            ),
            BusyFilledButton(
              onPressed: () => gate.future,
              child: const Text('Save'),
            ),
          ],
        ),
      ),
    );

    final cancel = find.byType(TextButton);
    expect(tester.widget<TextButton>(cancel).onPressed, isNotNull);

    await tester.tap(find.byType(FilledButton));
    await tester.pump();
    expect(tester.widget<TextButton>(cancel).onPressed, isNull);

    gate.complete();
    await tester.pumpAndSettle();
    expect(tester.widget<TextButton>(cancel).onPressed, isNotNull);
  });
}
