// `containsSemantics` is deprecated on the CI SDK (3.47) in favour of
// `isSemantics`, which the local 3.35 SDK does not have yet; keep the matcher
// both SDKs understand until the toolchains converge.
// ignore_for_file: deprecated_member_use

import 'package:clawnsole/app/app_theme.dart';
import 'package:clawnsole/core/models.dart';
import 'package:clawnsole/ui/filter_menu.dart';
import 'package:clawnsole/ui/generation_view_widgets.dart';
import 'package:clawnsole/ui/hardware.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

Widget _host(Widget child, {Brightness brightness = Brightness.light}) =>
    MaterialApp(
      theme: buildClawnsoleTheme(brightness),
      home: Scaffold(body: Center(child: child)),
    );

/// Runs [body] as if the app were installed on [platform].
///
/// The override has to be back to null before the test body returns —
/// `flutter_test` verifies its foundation invariants before any tearDown
/// runs — so this resets it in a `finally` as well as in the tearDown below.
Future<void> _onPlatform(
  TargetPlatform platform,
  Future<void> Function() body,
) async {
  debugDefaultTargetPlatformOverride = platform;
  try {
    await body();
  } finally {
    debugDefaultTargetPlatformOverride = null;
  }
}

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

const _selectionClick = 'HapticFeedbackType.selectionClick';

/// A canvas that only remembers the circles it was asked to draw, so a paint
/// routine can be inspected without a golden file.
class _CircleTally implements Canvas {
  final List<Color> colors = <Color>[];

  @override
  void drawCircle(Offset center, double radius, Paint paint) =>
      colors.add(paint.color);

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

void main() {
  tearDown(() => debugDefaultTargetPlatformOverride = null);

  test('the focus halo adds brass rings the idle knob does not paint', () {
    final idle = _CircleTally();
    paintMachinedKnob(
      idle,
      Offset.zero,
      14,
      brightness: Brightness.light,
      indicator: ClawnsoleColors.plum,
    );
    final lit = _CircleTally();
    paintMachinedKnob(
      lit,
      Offset.zero,
      14,
      brightness: Brightness.light,
      indicator: ClawnsoleColors.plum,
      focusGlow: ClawnsoleColors.brass,
    );
    expect(lit.colors.length, idle.colors.length + 2);
    expect(
      lit.colors.take(2).map((color) => color.withValues(alpha: 1).toARGB32()),
      everyElement(ClawnsoleColors.brass.toARGB32()),
    );
  });

  group('touch targets', () {
    testWidgets('the switch keeps its artwork inside a finger-sized box', (
      tester,
    ) async {
      Widget build() => _host(HardwareSwitch(value: false, onChanged: (_) {}));
      late Size drawn;
      await _onPlatform(TargetPlatform.macOS, () async {
        await tester.pumpWidget(build());
        await tester.pumpAndSettle();
        drawn = tester.getSize(
          find.descendant(
            of: find.byType(HardwareSwitch),
            matching: find.byType(InkWell),
          ),
        );
        // Desktop is exactly what it always drew: 50×28 plus 3 px of padding.
        expect(drawn, const Size(56, 34));
        expect(tester.getSize(find.byType(HardwareSwitch)), drawn);
      });

      await _onPlatform(TargetPlatform.iOS, () async {
        await tester.pumpWidget(build());
        await tester.pumpAndSettle();
        final box = tester.getSize(find.byType(HardwareSwitch));
        expect(box.width, greaterThanOrEqualTo(kHardwareTouchTarget));
        expect(box.height, greaterThanOrEqualTo(kHardwareTouchTarget));
        // …around the same unchanged artwork.
        expect(
          tester.getSize(
            find.descendant(
              of: find.byType(HardwareSwitch),
              matching: find.byType(InkWell),
            ),
          ),
          drawn,
        );
      });
    });

    testWidgets('a near miss above the switch still throws it', (tester) async {
      await _onPlatform(TargetPlatform.iOS, () async {
        bool? received;
        await tester.pumpWidget(
          _host(
            HardwareSwitch(
              value: false,
              onChanged: (value) => received = value,
            ),
          ),
        );
        await tester.pumpAndSettle();
        final box = tester.getRect(find.byType(HardwareSwitch));
        await tester.tapAt(Offset(box.center.dx, box.top + 2));
        await tester.pumpAndSettle();
        expect(received, isTrue);
      });
    });

    testWidgets('the switch tile keeps its drawn row height on touch', (
      tester,
    ) async {
      Widget build() => _host(
        const SizedBox(
          width: 320,
          child: HardwareSwitchTile(
            title: 'Synchronized audio',
            subtitle: 'Dialogue, ambience, and sound',
            value: true,
            onChanged: null,
          ),
        ),
      );
      late double desktopHeight;
      await _onPlatform(TargetPlatform.macOS, () async {
        await tester.pumpWidget(build());
        await tester.pumpAndSettle();
        desktopHeight = tester.getSize(find.byType(HardwareSwitchTile)).height;
      });
      await _onPlatform(TargetPlatform.iOS, () async {
        await tester.pumpWidget(build());
        await tester.pumpAndSettle();
        final height = tester.getSize(find.byType(HardwareSwitchTile)).height;
        expect(height, desktopHeight);
        expect(height, greaterThanOrEqualTo(kHardwareTouchTarget));
      });
    });

    testWidgets('each carriage half answers to a finger', (tester) async {
      Widget build(ValueChanged<bool>? onChanged) => _host(
        HardwareChoiceSwitch(
          firstLabel: 'AUTO',
          secondLabel: 'MANUAL',
          firstSelected: true,
          onChanged: onChanged,
        ),
      );
      await _onPlatform(TargetPlatform.macOS, () async {
        await tester.pumpWidget(build((_) {}));
        await tester.pumpAndSettle();
        expect(
          tester.getSize(find.byType(HardwareChoiceSwitch)),
          const Size(164, 36),
        );
      });

      await _onPlatform(TargetPlatform.iOS, () async {
        bool? picked;
        await tester.pumpWidget(build((value) => picked = value));
        await tester.pumpAndSettle();
        final box = tester.getRect(find.byType(HardwareChoiceSwitch));
        expect(box.height, greaterThanOrEqualTo(kHardwareTouchTarget));
        // The well still paints 36 tall inside the taller band.
        expect(
          tester.getSize(
            find
                .descendant(
                  of: find.byType(HardwareChoiceSwitch),
                  matching: find.byType(Container),
                )
                .first,
          ),
          const Size(164, 36),
        );
        // A tap that misses the well low still picks the right half.
        await tester.tapAt(Offset(box.left + 40, box.bottom - 2));
        await tester.pumpAndSettle();
        expect(picked, isTrue);
        await tester.tapAt(Offset(box.right - 40, box.bottom - 2));
        await tester.pumpAndSettle();
        expect(picked, isFalse);
      });
    });

    testWidgets('console filter keys grow their hit area, not their key', (
      tester,
    ) async {
      Widget build() => _host(
        ConsoleFilterSegment(
          label: 'Ready',
          icon: Icons.check_circle_outline_rounded,
          count: 3,
          selected: true,
          onTap: () {},
        ),
      );
      late Size drawn;
      await _onPlatform(TargetPlatform.macOS, () async {
        await tester.pumpWidget(build());
        await tester.pumpAndSettle();
        drawn = tester.getSize(find.byType(AnimatedContainer));
        expect(tester.getSize(find.byType(ConsoleFilterSegment)), drawn);
      });
      await _onPlatform(TargetPlatform.iOS, () async {
        await tester.pumpWidget(build());
        await tester.pumpAndSettle();
        final box = tester.getSize(find.byType(ConsoleFilterSegment));
        expect(box.height, greaterThanOrEqualTo(kHardwareTouchTarget));
        expect(box.width, greaterThanOrEqualTo(kHardwareTouchTarget));
        expect(tester.getSize(find.byType(AnimatedContainer)), drawn);
      });
    });

    testWidgets('view-mode keys reach 44 without redrawing the tile', (
      tester,
    ) async {
      Widget build() => _host(
        GenerationViewToggle(
          value: GenerationViewMode.mini,
          keyPrefix: 'probe',
          onChanged: (_) {},
        ),
      );
      final tile = find.byKey(const ValueKey('probe-compact'));
      await _onPlatform(TargetPlatform.macOS, () async {
        await tester.pumpWidget(build());
        await tester.pumpAndSettle();
        expect(tester.getSize(tile), const Size(34, 30));
        expect(
          tester.getSize(find.byType(HardwareTouchTarget).first),
          const Size(34, 30),
        );
      });
      await _onPlatform(TargetPlatform.iOS, () async {
        await tester.pumpWidget(build());
        await tester.pumpAndSettle();
        // Still 34×30 of paint…
        expect(tester.getSize(tile), const Size(34, 30));
        for (final mode in GenerationViewMode.values) {
          final box = tester.getSize(
            find
                .ancestor(
                  of: find.byKey(ValueKey('probe-${mode.name}')),
                  matching: find.byType(HardwareTouchTarget),
                )
                .first,
          );
          expect(box.width, greaterThanOrEqualTo(kHardwareTouchTarget));
          expect(box.height, greaterThanOrEqualTo(kHardwareTouchTarget));
        }
      });
    });
  });

  group('assistive tech', () {
    testWidgets('the knob is a slider that speaks the caller units', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      await tester.pumpWidget(
        _host(
          SizedBox(
            width: 400,
            child: HardwareSlider(
              value: 6,
              min: 2,
              max: 10,
              divisions: 8,
              semanticLabel: 'Duration',
              semanticFormatterCallback: (value) => '${value.round()} seconds',
              onChanged: (_) {},
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(
        tester.getSemantics(find.byType(HardwareSlider)),
        containsSemantics(
          isSlider: true,
          label: 'Duration',
          value: '6 seconds',
          increasedValue: '7 seconds',
          decreasedValue: '5 seconds',
          hasIncreaseAction: true,
          hasDecreaseAction: true,
        ),
      );
      handle.dispose();
    });

    testWidgets('a knob without a formatter still counts, never percents', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      await tester.pumpWidget(
        _host(
          SizedBox(
            width: 400,
            child: HardwareSlider(
              value: 2.4,
              min: 1.5,
              max: 3,
              divisions: 15,
              onChanged: (_) {},
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(
        tester.getSemantics(find.byType(HardwareSlider)),
        containsSemantics(isSlider: true, value: '2.4'),
      );
      handle.dispose();
    });

    testWidgets('each carriage half is announced once, not twice', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      await tester.pumpWidget(
        _host(
          HardwareChoiceSwitch(
            firstKey: const ValueKey('auto'),
            secondKey: const ValueKey('manual'),
            firstLabel: 'AUTO',
            secondLabel: 'MANUAL',
            firstSelected: true,
            semanticLabel: 'Duration mode',
            onChanged: (_) {},
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(
        tester.getSemantics(find.byKey(const ValueKey('auto'))),
        containsSemantics(
          // Not 'AUTO AUTO': the carriage text is excluded so the node
          // speaks its name exactly once.
          label: 'AUTO',
          hint: 'Duration mode',
          isButton: true,
          isSelected: true,
          isInMutuallyExclusiveGroup: true,
          hasTapAction: true,
        ),
      );
      expect(
        tester.getSemantics(find.byKey(const ValueKey('manual'))),
        containsSemantics(label: 'MANUAL', isSelected: false),
      );
      handle.dispose();
    });

    testWidgets('a switch tile reads as one labelled switch', (tester) async {
      final handle = tester.ensureSemantics();
      await tester.pumpWidget(
        _host(
          const SizedBox(
            width: 320,
            child: HardwareSwitchTile(
              title: 'Synchronized audio',
              subtitle: 'Dialogue, ambience, and sound',
              value: true,
              onChanged: null,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(
        tester.getSemantics(find.byType(HardwareSwitchTile)),
        containsSemantics(
          label: 'Synchronized audio',
          hint: 'Dialogue, ambience, and sound',
          hasToggledState: true,
          isToggled: true,
        ),
      );
      handle.dispose();
    });

    testWidgets('a standalone switch carries its own name', (tester) async {
      final handle = tester.ensureSemantics();
      await tester.pumpWidget(
        _host(
          HardwareSwitch(
            value: false,
            semanticLabel: 'Normalize visual references',
            onChanged: (_) {},
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(
        tester.getSemantics(find.byType(HardwareSwitch)),
        containsSemantics(
          label: 'Normalize visual references',
          hasToggledState: true,
          isToggled: false,
          hasTapAction: true,
        ),
      );
      handle.dispose();
    });

    testWidgets('the readout window names what it counts', (tester) async {
      final handle = tester.ensureSemantics();
      await tester.pumpWidget(
        _host(
          const CounterReadout(
            '3',
            unit: 'fps',
            semanticLabel: 'Frame rate',
            unitLabel: 'frames per second',
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(
        tester.getSemantics(find.byType(CounterReadout)),
        containsSemantics(
          label: 'Frame rate',
          value: '3 frames per second',
          isReadOnly: true,
        ),
      );
      handle.dispose();
    });

    testWidgets('the editable readout announces as a named field', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      await tester.pumpWidget(
        _host(
          CounterReadoutField(
            value: '10',
            unit: 's',
            semanticLabel: 'Duration',
            unitLabel: 'seconds',
            onCommit: (_) {},
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(
        tester.getSemantics(find.byType(CounterReadoutField)),
        containsSemantics(
          label: 'Duration, seconds',
          value: '10',
          isTextField: true,
        ),
      );
      handle.dispose();
    });

    testWidgets('a console filter key states its selection and count', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      await tester.pumpWidget(
        _host(
          ConsoleFilterSegment(
            label: 'Ready',
            count: 3,
            selected: true,
            onTap: () {},
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(
        tester.getSemantics(find.byType(ConsoleFilterSegment)),
        containsSemantics(
          label: 'Ready',
          value: '3',
          isButton: true,
          isSelected: true,
          hasTapAction: true,
        ),
      );
      handle.dispose();
    });

    testWidgets('a view-mode key states its selection', (tester) async {
      final handle = tester.ensureSemantics();
      await tester.pumpWidget(
        _host(
          GenerationViewToggle(
            value: GenerationViewMode.mini,
            keyPrefix: 'probe',
            onChanged: (_) {},
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(
        tester.getSemantics(find.byKey(const ValueKey('probe-mini'))),
        containsSemantics(label: 'Mini', isButton: true, isSelected: true),
      );
      expect(
        tester.getSemantics(find.byKey(const ValueKey('probe-full'))),
        containsSemantics(label: 'Full', isButton: true, isSelected: false),
      );
      handle.dispose();
    });
  });

  group('keyboard', () {
    testWidgets('arrow keys walk the groove one division at a time', (
      tester,
    ) async {
      final seen = <double>[];
      await tester.pumpWidget(
        _host(
          SizedBox(
            width: 400,
            child: HardwareSlider(
              value: 6,
              min: 2,
              max: 10,
              divisions: 8,
              onChanged: seen.add,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      tester.widget<Slider>(find.byType(Slider)).focusNode!.requestFocus();
      await tester.pumpAndSettle();

      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await tester.pumpAndSettle();
      expect(seen.last, 7);

      await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
      await tester.pumpAndSettle();
      expect(seen.last, 5);
    });

    testWidgets('Home and End park the knob at the ends of its travel', (
      tester,
    ) async {
      final seen = <double>[];
      await tester.pumpWidget(
        _host(
          SizedBox(
            width: 400,
            child: HardwareSlider(
              value: 6,
              min: 2,
              max: 10,
              divisions: 8,
              onChanged: seen.add,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      tester.widget<Slider>(find.byType(Slider)).focusNode!.requestFocus();
      await tester.pumpAndSettle();

      await tester.sendKeyEvent(LogicalKeyboardKey.home);
      await tester.pumpAndSettle();
      expect(seen.last, 2);

      await tester.sendKeyEvent(LogicalKeyboardKey.end);
      await tester.pumpAndSettle();
      expect(seen.last, 10);
    });

    testWidgets('focus re-dresses the knob and letting go puts it back', (
      tester,
    ) async {
      await tester.pumpWidget(
        _host(
          SizedBox(
            width: 400,
            child: HardwareSlider(
              value: 6,
              min: 2,
              max: 10,
              divisions: 8,
              onChanged: (_) {},
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      SliderComponentShape thumb() => tester
          .widget<SliderTheme>(
            find.descendant(
              of: find.byType(HardwareSlider),
              matching: find.byType(SliderTheme),
            ),
          )
          .data
          .thumbShape!;
      final idle = thumb();
      final focus = tester.widget<Slider>(find.byType(Slider)).focusNode!;

      focus.requestFocus();
      await tester.pumpAndSettle();
      expect(thumb(), isNot(idle));

      focus.unfocus();
      await tester.pumpAndSettle();
      expect(thumb(), idle);
    });

    testWidgets('a disabled knob never lights', (tester) async {
      await tester.pumpWidget(
        _host(
          const SizedBox(
            width: 400,
            child: HardwareSlider(value: 6, min: 2, max: 10, onChanged: null),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.widget<Slider>(find.byType(Slider)).onChanged, isNull);
    });

    testWidgets('Space throws a switch and a switch tile', (tester) async {
      var switched = false;
      var tiled = false;
      await tester.pumpWidget(
        _host(
          SizedBox(
            width: 320,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                HardwareSwitch(
                  value: false,
                  onChanged: (value) => switched = value,
                ),
                HardwareSwitchTile(
                  title: 'Fast draft',
                  value: false,
                  onChanged: (value) => tiled = value,
                ),
              ],
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pumpAndSettle();
      await tester.sendKeyEvent(LogicalKeyboardKey.space);
      await tester.pumpAndSettle();
      expect(switched, isTrue);

      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pumpAndSettle();
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();
      expect(tiled, isTrue);
    });

    testWidgets('Enter selects a carriage half and a console key', (
      tester,
    ) async {
      bool? picked;
      var tapped = 0;
      await tester.pumpWidget(
        _host(
          Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              HardwareChoiceSwitch(
                firstLabel: 'AUTO',
                secondLabel: 'MANUAL',
                firstSelected: true,
                onChanged: (value) => picked = value,
              ),
              ConsoleFilterSegment(
                label: 'Ready',
                selected: false,
                onTap: () => tapped += 1,
              ),
            ],
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pumpAndSettle();
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();
      expect(picked, isTrue);

      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pumpAndSettle();
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();
      expect(tapped, 1);
    });
  });

  group('haptics', () {
    testWidgets('touch platforms click on toggles, detents, and keys', (
      tester,
    ) async {
      await _onPlatform(TargetPlatform.iOS, () async {
        final taps = _recordHaptics(tester);
        await tester.pumpWidget(
          _host(HardwareSwitch(value: false, onChanged: (_) {})),
        );
        await tester.pumpAndSettle();
        await tester.tap(find.byType(HardwareSwitch));
        await tester.pumpAndSettle();
        expect(taps, <String>[_selectionClick]);

        taps.clear();
        await tester.pumpWidget(
          _host(
            ConsoleFilterSegment(label: 'All', selected: false, onTap: () {}),
          ),
        );
        await tester.pumpAndSettle();
        await tester.tap(find.byType(ConsoleFilterSegment));
        await tester.pumpAndSettle();
        expect(taps, <String>[_selectionClick]);

        taps.clear();
        await tester.pumpWidget(
          _host(
            SizedBox(
              width: 400,
              child: HardwareSlider(
                value: 2,
                min: 2,
                max: 10,
                divisions: 8,
                onChanged: (_) {},
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        await tester.drag(find.byType(Slider), const Offset(220, 0));
        await tester.pumpAndSettle();
        expect(taps, isNotEmpty);
        expect(taps.every((tap) => tap == _selectionClick), isTrue);
      });
    });

    testWidgets('desktop stays silent', (tester) async {
      await _onPlatform(TargetPlatform.macOS, () async {
        final taps = _recordHaptics(tester);
        await tester.pumpWidget(
          _host(HardwareSwitch(value: false, onChanged: (_) {})),
        );
        await tester.pumpAndSettle();
        await tester.tap(find.byType(HardwareSwitch));
        await tester.pumpAndSettle();
        expect(taps, isEmpty);
      });
    });
  });
}
