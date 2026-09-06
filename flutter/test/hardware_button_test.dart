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
    await tester.pump(const Duration(milliseconds: 300));

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
    await tester.pump(const Duration(milliseconds: 300));
    expect(_state(tester).litAmount, 1);

    await tester.pumpWidget(
      _host(HardwareLitButton(label: 'Generate video', onPressed: () {})),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 150));
    expect(_state(tester).litAmount, lessThan(1));
    // Cold within half a second, and nothing ticks afterwards.
    await tester.pump(const Duration(milliseconds: 300));
    expect(_state(tester).litAmount, 0);
    expect(_state(tester).isFilamentLit, isFalse);
    await tester.pumpAndSettle();
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
    // Warm-up: a quarter second to full, never a snap.
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 60));
    expect(state.litAmount, inExclusiveRange(0, 1));
    expect(state.isFilamentLit, isTrue);
    await tester.pump(const Duration(milliseconds: 300));
    expect(state.litAmount, 1);

    // On, the filament drifts a few percent — never steady, never wild.
    final samples = <double>{};
    for (var i = 0; i < 24; i++) {
      await tester.pump(const Duration(milliseconds: 37));
      samples.add(state.filament);
      expect(state.filament, inInclusiveRange(.9, 1.05));
    }
    expect(samples.length, greaterThan(4));

    // Off, the wander stops with the light, so a dark console is still.
    await tester.pumpWidget(
      _host(HardwareLitButton(label: 'Generate video', onPressed: () {})),
    );
    await tester.pump(const Duration(milliseconds: 500));
    expect(state.isFilamentLit, isFalse);
    expect(state.filament, 1);
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
