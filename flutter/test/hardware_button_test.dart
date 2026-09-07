// `containsSemantics` is deprecated on the CI SDK (3.47) in favour of
// `isSemantics`, which the local 3.35 SDK does not have yet; keep the matcher
// both SDKs understand until the toolchains converge.
// ignore_for_file: deprecated_member_use

import 'package:clawnsole/app/app_theme.dart';
import 'package:clawnsole/ui/hardware.dart';
import 'package:clawnsole/ui/hardware_button.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

Widget _host(Widget child, {Brightness brightness = Brightness.light}) =>
    MaterialApp(
      theme: buildClawnsoleTheme(brightness),
      home: Scaffold(body: Center(child: child)),
    );

HardwareLitButtonState _state(WidgetTester tester) =>
    tester.state<HardwareLitButtonState>(find.byType(HardwareLitButton));

/// Records the haptics the platform channel is asked for.
List<String> _recordHaptics(WidgetTester tester) {
  final taps = <String>[];
  tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
    SystemChannels.platform,
    (call) async {
      if (call.method == 'HapticFeedback.vibrate') {
        taps.add('${call.arguments}');
      }
      return null;
    },
  );
  addTearDown(
    () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      null,
    ),
  );
  return taps;
}

void main() {
  testWidgets('paints the legend and the leading mark', (tester) async {
    await tester.pumpWidget(
      _host(
        HardwareLitButton(
          icon: const Icon(Icons.circle, size: 18, key: ValueKey<String>('m')),
          label: 'Generate video',
          onPressed: () {},
        ),
      ),
    );

    // The legend is engraved in capitals; the semantics keep the label.
    expect(find.text('GENERATE VIDEO'), findsOneWidget);
    expect(find.text('Generate video'), findsNothing);
    expect(find.byKey(const ValueKey<String>('m')), findsOneWidget);
    // No Material ripple painting over the plastic.
    expect(find.byType(InkWell), findsNothing);
  });

  testWidgets('stands exactly one console control tall', (tester) async {
    await tester.pumpWidget(
      _host(HardwareLitButton(label: 'Generate video', onPressed: () {})),
    );
    expect(
      tester.getSize(find.byType(HardwareLitButton)).height,
      kConsoleControlHeight,
    );
  });

  testWidgets('fires on tap-up and clicks on touch hardware', (tester) async {
    // The override has to be back to null before the test body returns:
    // `flutter_test` checks its foundation invariants before any tearDown.
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    try {
      final haptics = _recordHaptics(tester);
      var taps = 0;
      await tester.pumpWidget(
        _host(
          HardwareLitButton(
            label: 'Generate video',
            onPressed: () => taps += 1,
          ),
        ),
      );

      await tester.tap(find.text('GENERATE VIDEO'));
      await tester.pumpAndSettle();
      expect(taps, 1);
      expect(haptics, <String>['HapticFeedbackType.selectionClick']);
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });

  testWidgets('a disabled key ignores taps and dims', (tester) async {
    await tester.pumpWidget(
      _host(const HardwareLitButton(label: 'Generate video', onPressed: null)),
    );

    await tester.tap(find.text('GENERATE VIDEO'), warnIfMissed: false);
    await tester.pumpAndSettle();
    expect(_state(tester).litAmount, 0);

    final opacity = tester.widget<Opacity>(
      find.descendant(
        of: find.byType(HardwareLitButton),
        matching: find.byType(Opacity),
      ),
    );
    expect(opacity.opacity, lessThan(1));
  });

  testWidgets('stays lit while working, even though it takes no taps', (
    tester,
  ) async {
    await tester.pumpWidget(
      _host(
        const HardwareLitButton(
          label: 'Generate video',
          onPressed: null,
          lit: true,
        ),
      ),
    );
    // A lit lamp keeps ticking, so settle by the clock instead.
    await tester.pump(const Duration(milliseconds: 400));

    expect(_state(tester).litAmount, 1);
    // A working key is not dimmed: the lamp is the signal.
    expect(
      find.descendant(
        of: find.byType(HardwareLitButton),
        matching: find.byType(Opacity),
      ),
      findsNothing,
    );
  });

  testWidgets('the lamp fades out when the render finishes', (tester) async {
    await tester.pumpWidget(
      _host(
        HardwareLitButton(label: 'Generate video', onPressed: () {}, lit: true),
      ),
    );
    await tester.pump(const Duration(milliseconds: 400));
    expect(_state(tester).litAmount, 1);

    await tester.pumpWidget(
      _host(HardwareLitButton(label: 'Generate video', onPressed: () {})),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 150));
    expect(_state(tester).litAmount, lessThan(1));
    // Cold by the end of the afterglow, and nothing ticks afterwards.
    await tester.pump(const Duration(milliseconds: 500));
    expect(_state(tester).litAmount, 0);
    expect(_state(tester).isFilamentLit, isFalse);
    await tester.pumpAndSettle();
  });

  testWidgets('the filament flares as it warms, then settles to steady', (
    tester,
  ) async {
    await tester.pumpWidget(
      _host(HardwareLitButton(label: 'Generate video', onPressed: () {})),
    );
    final state = _state(tester);
    expect(state.litAmount, 0);

    await tester.pumpWidget(
      _host(
        const HardwareLitButton(
          label: 'Generate video',
          onPressed: null,
          lit: true,
        ),
      ),
    );
    await tester.pump();

    // Sampled by the clock across the warm-up: a real rise, not a snap.
    final curve = <int, double>{};
    for (var ms = 30; ms <= 420; ms += 30) {
      await tester.pump(const Duration(milliseconds: 30));
      curve[ms] = state.litAmount;
    }

    // A third of the way up after two frames, most of the way by 120 ms.
    expect(curve[30], inExclusiveRange(.15, .55));
    expect(curve[60], inExclusiveRange(.45, .8));
    expect(curve[120], greaterThan(.9));
    // A cold wire draws hard, so it overshoots before it settles.
    final peak = curve.values.reduce((a, b) => a > b ? a : b);
    expect(peak, greaterThan(1.04));
    expect(peak, lessThan(1.12));
    expect(curve[180], greaterThan(1.04), reason: 'the flare is mid-warm-up');
    // And lands exactly on its working brightness by the end of the warm-up.
    expect(curve[360], moreOrLessEquals(1, epsilon: .001));
    expect(curve[420], 1);
  });

  testWidgets('the afterglow drops fast, then lingers', (tester) async {
    await tester.pumpWidget(
      _host(
        const HardwareLitButton(
          label: 'Generate video',
          onPressed: null,
          lit: true,
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 400));
    final state = _state(tester);

    await tester.pumpWidget(
      _host(HardwareLitButton(label: 'Generate video', onPressed: () {})),
    );
    await tester.pump();
    final cool = <int, double>{};
    for (var ms = 50; ms <= 700; ms += 50) {
      await tester.pump(const Duration(milliseconds: 50));
      cool[ms] = state.litAmount;
    }

    // Half gone in a breath, three quarters gone by a tenth of a second.
    expect(cool[50], inExclusiveRange(.35, .6));
    expect(cool[100], inExclusiveRange(.18, .38));
    // Then an ember that hangs on rather than snapping out.
    expect(cool[300], inExclusiveRange(.02, .12));
    expect(cool[500], inExclusiveRange(0, .04));
    expect(cool[600], 0);
    expect(state.isFilamentLit, isFalse, reason: 'a cold lamp costs nothing');
    await tester.pumpAndSettle();
  });

  testWidgets('the lit lamp breathes, and the hot spots lead the block', (
    tester,
  ) async {
    await tester.pumpWidget(
      _host(
        HardwareLitButton(label: 'Generate video', onPressed: () {}, lit: true),
      ),
    );
    final state = _state(tester);
    // Past the warm-up and the breath's fade-in.
    await tester.pump(const Duration(milliseconds: 600));

    final hot = <double>[];
    final body = <double>[];
    // Two seconds at 120 Hz: more than two full breaths.
    for (var i = 0; i < 240; i++) {
      await tester.pump(const Duration(milliseconds: 8));
      hot.add(state.filament);
      body.add(state.filamentBody);
      expect(state.filament, inInclusiveRange(.62, 1.08));
      expect(state.filamentBody, inInclusiveRange(.62, 1.08));
    }

    // The breath is deep enough to see: down to about three quarters, and
    // never below the floor even when a sag lands in the trough.
    final low = hot.reduce((a, b) => a < b ? a : b);
    final high = hot.reduce((a, b) => a > b ? a : b);
    expect(low, lessThan(.8), reason: 'a visible breath, not a shimmer');
    expect(low, greaterThanOrEqualTo(.62), reason: 'and never wild');
    expect(high, greaterThan(.93));
    // The block breathes with it rather than sitting flat.
    final bodyLow = body.reduce((a, b) => a < b ? a : b);
    expect(bodyLow, lessThan(.82));

    // Roughly one and a bit a second: counted with hysteresis so the fine
    // flicker riding on the breath cannot be mistaken for one.
    var troughs = 0;
    var breathedIn = true;
    for (final value in hot) {
      if (breathedIn && value < .8) {
        troughs += 1;
        breathedIn = false;
      } else if (!breathedIn && value > .95) {
        breathedIn = true;
      }
    }
    expect(troughs, inInclusiveRange(2, 3), reason: 'about 1.2 breaths a s');

    // The hot spots sit closest to the wire, so they move first: when they
    // are climbing they are above the block, and below it on the way down.
    // Read off the breath, with the fine flicker averaged away first.
    List<double> smooth(List<double> series) => <double>[
      for (var i = 8; i < series.length - 8; i++)
        series.sublist(i - 8, i + 9).reduce((a, b) => a + b) / 17,
    ];
    final slowHot = smooth(hot);
    final slowBody = smooth(body);
    var lead = 0.0;
    for (var i = 1; i < slowHot.length; i++) {
      lead += (slowHot[i] - slowHot[i - 1]) * (slowHot[i] - slowBody[i]);
    }
    expect(lead, greaterThan(0), reason: 'the diffuser lags the filament');
  });

  testWidgets('the filament wanders while lit and rests when cold', (
    tester,
  ) async {
    await tester.pumpWidget(
      _host(HardwareLitButton(label: 'Generate video', onPressed: () {})),
    );
    final state = _state(tester);
    expect(state.isFilamentLit, isFalse);
    expect(state.filament, 1);

    await tester.pumpWidget(
      _host(
        HardwareLitButton(label: 'Generate video', onPressed: () {}, lit: true),
      ),
    );
    // Warm-up: a third of a second to full, never a snap.
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 60));
    expect(state.litAmount, inExclusiveRange(0, 1));
    expect(state.isFilamentLit, isTrue);
    await tester.pump(const Duration(milliseconds: 360));
    expect(state.litAmount, 1);

    // On, the filament is never still and never wild.
    final samples = <double>{};
    for (var i = 0; i < 24; i++) {
      await tester.pump(const Duration(milliseconds: 37));
      samples.add(state.filament);
      expect(state.filament, inInclusiveRange(.62, 1.08));
    }
    expect(samples.length, greaterThan(4));

    // Off, the wander stops with the light, so a dark console is still.
    await tester.pumpWidget(
      _host(HardwareLitButton(label: 'Generate video', onPressed: () {})),
    );
    await tester.pump(const Duration(milliseconds: 700));
    expect(state.isFilamentLit, isFalse);
    expect(state.filament, 1);
    expect(state.filamentBody, 1);
    await tester.pumpAndSettle();
  });

  testWidgets('lights up on pointer-down, before the tap completes', (
    tester,
  ) async {
    await tester.pumpWidget(
      _host(HardwareLitButton(label: 'Generate video', onPressed: () {})),
    );
    expect(_state(tester).litAmount, 0);

    final gesture = await tester.startGesture(
      tester.getCenter(find.byType(HardwareLitButton)),
    );
    await tester.pump();
    expect(_state(tester).isPressed, isTrue);
    await tester.pump(const Duration(milliseconds: 60));
    expect(_state(tester).litAmount, greaterThan(0));

    await gesture.up();
    await tester.pumpAndSettle();
    expect(_state(tester).isPressed, isFalse);
    expect(_state(tester).litAmount, 0);
  });

  testWidgets('a held key glows at the contact, not at the lamps', (
    tester,
  ) async {
    await tester.pumpWidget(
      _host(HardwareLitButton(label: 'Generate video', onPressed: () {})),
    );
    final state = _state(tester);

    final gesture = await tester.startGesture(
      tester.getCenter(find.byType(HardwareLitButton)),
    );
    await tester.pump();
    // Held well past the lamps' own warm-up.
    await tester.pump(const Duration(milliseconds: 500));
    // The finger's glow is dim and it stops there: the console has not
    // accepted anything, so the lamps are still cold and the filament is
    // still asleep. This is what keeps the warm-up whole for the submission.
    expect(state.litAmount, inExclusiveRange(.2, .4));
    expect(state.isFilamentLit, isFalse);

    // Releasing without a submission takes the cap back to dark.
    await gesture.up();
    await tester.pumpAndSettle();
    expect(state.litAmount, 0);
  });

  testWidgets('the whole warm-up survives the press that started it', (
    tester,
  ) async {
    // The footer rebuilds the key with `lit: true` and `onPressed: null` in
    // the same breath, on the far side of a pointer-up. Neither the release
    // nor going inert may cancel or short-circuit the lamps.
    var lit = false;
    Widget build(StateSetter setState) => HardwareLitButton(
      key: const ValueKey<String>('generate-key'),
      label: 'Generate video',
      lit: lit,
      onPressed: lit ? null : () => setState(() => lit = true),
    );
    await tester.pumpWidget(
      _host(StatefulBuilder(builder: (context, setState) => build(setState))),
    );
    final state = _state(tester);

    // A real finger: down for 140 ms, then up.
    final gesture = await tester.startGesture(
      tester.getCenter(find.byType(HardwareLitButton)),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 140));
    final atRelease = state.litAmount;
    expect(
      atRelease,
      lessThan(.35),
      reason: 'the press must not have spent the warm-up',
    );

    await gesture.up();
    await tester.pump();
    expect(lit, isTrue);
    // From here the lamps run their whole course, flare and all.
    final curve = <int, double>{};
    for (var ms = 30; ms <= 420; ms += 30) {
      await tester.pump(const Duration(milliseconds: 30));
      curve[ms] = state.litAmount;
    }
    expect(curve[30], greaterThan(atRelease));
    expect(curve.values.reduce((a, b) => a > b ? a : b), greaterThan(1.04));
    expect(curve[420], 1);
    expect(state.isFilamentLit, isTrue);
  });

  testWidgets('a pointer-up while lit never reverses the lamps', (
    tester,
  ) async {
    await tester.pumpWidget(
      _host(
        HardwareLitButton(label: 'Generate video', onPressed: () {}, lit: true),
      ),
    );
    await tester.pump(const Duration(milliseconds: 400));
    final state = _state(tester);
    expect(state.litAmount, 1);

    // Pressing and releasing a lit key touches only the contact glow.
    final gesture = await tester.startGesture(
      tester.getCenter(find.byType(HardwareLitButton)),
    );
    await tester.pump(const Duration(milliseconds: 80));
    expect(state.litAmount, 1);
    await gesture.up();
    for (var i = 0; i < 8; i++) {
      await tester.pump(const Duration(milliseconds: 40));
      expect(state.litAmount, 1, reason: 'the console still holds the key on');
    }
    expect(state.isFilamentLit, isTrue);
  });

  testWidgets('reads as one enabled button node carrying the label', (
    tester,
  ) async {
    final handle = tester.ensureSemantics();
    await tester.pumpWidget(
      _host(HardwareLitButton(label: 'Generate video', onPressed: () {})),
    );

    expect(
      tester.getSemantics(find.byType(HardwareLitButton)),
      containsSemantics(
        label: 'Generate video',
        isButton: true,
        isEnabled: true,
        hasEnabledState: true,
      ),
    );
    expect(find.bySemanticsLabel('Generate video'), findsOneWidget);
    handle.dispose();
  });

  testWidgets('a disabled key says so, and a custom label is honoured', (
    tester,
  ) async {
    final handle = tester.ensureSemantics();
    await tester.pumpWidget(
      _host(
        const HardwareLitButton(
          label: 'Generate video',
          semanticLabel: 'Generate video, working',
          onPressed: null,
          lit: true,
        ),
      ),
    );

    expect(
      tester.getSemantics(find.byType(HardwareLitButton)),
      containsSemantics(
        label: 'Generate video, working',
        isButton: true,
        isEnabled: false,
        hasEnabledState: true,
      ),
    );
    handle.dispose();
  });

  testWidgets('Space and Enter activate the focused key', (tester) async {
    var taps = 0;
    await tester.pumpWidget(
      _host(
        HardwareLitButton(label: 'Generate video', onPressed: () => taps += 1),
      ),
    );

    FocusManager.instance.highlightStrategy =
        FocusHighlightStrategy.alwaysTraditional;
    Focus.of(
      tester.element(
        find.descendant(
          of: find.byType(HardwareLitButton),
          matching: find.byType(GestureDetector),
        ),
      ),
    ).requestFocus();
    await tester.pumpAndSettle();
    expect(_state(tester).isFocused, isTrue);

    await tester.sendKeyEvent(LogicalKeyboardKey.space);
    await tester.pumpAndSettle();
    expect(taps, 1);

    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(taps, 2);
  });

  testWidgets('a disabled key cannot be focused', (tester) async {
    await tester.pumpWidget(
      _host(const HardwareLitButton(label: 'Generate video', onPressed: null)),
    );
    FocusManager.instance.highlightStrategy =
        FocusHighlightStrategy.alwaysTraditional;
    Focus.of(
      tester.element(
        find.descendant(
          of: find.byType(HardwareLitButton),
          matching: find.byType(GestureDetector),
        ),
      ),
    ).requestFocus();
    await tester.pumpAndSettle();
    expect(_state(tester).isFocused, isFalse);
  });

  testWidgets('hugs a short legend but fills a stretched column', (
    tester,
  ) async {
    await tester.pumpWidget(
      _host(HardwareLitButton(label: 'Go', onPressed: () {})),
    );
    final hugged = tester.getSize(find.byType(HardwareLitButton)).width;
    expect(hugged, 170);

    await tester.pumpWidget(
      _host(
        SizedBox(
          width: 420,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              HardwareLitButton(label: 'Go', onPressed: () {}),
            ],
          ),
        ),
      ),
    );
    expect(tester.getSize(find.byType(HardwareLitButton)).width, 420);
  });

  testWidgets('draws in both rooms without a Material ripple', (tester) async {
    for (final brightness in <Brightness>[Brightness.light, Brightness.dark]) {
      await tester.pumpWidget(
        _host(
          HardwareLitButton(label: 'Generate video', onPressed: () {}),
          brightness: brightness,
        ),
      );
      await tester.pumpAndSettle();
      final painters = tester
          .widgetList<CustomPaint>(
            find.descendant(
              of: find.byType(HardwareLitButton),
              matching: find.byType(CustomPaint),
            ),
          )
          .map((paint) => paint.painter)
          .whereType<CustomPainter>();
      expect(painters, isNotEmpty);
      expect(find.byType(InkWell), findsNothing);
      expect(tester.takeException(), isNull);
    }
  });
}
