import 'package:clawnsole/app/app_theme.dart';
import 'package:clawnsole/ui/filter_menu.dart';
import 'package:clawnsole/ui/hardware.dart';
import 'package:clawnsole/ui/panels.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

double _luminance(Color color) => color.computeLuminance();

/// WCAG contrast ratio, so "readable" is measured rather than eyeballed.
double _contrast(Color a, Color b) {
  final high = _luminance(a) > _luminance(b) ? _luminance(a) : _luminance(b);
  final low = _luminance(a) > _luminance(b) ? _luminance(b) : _luminance(a);
  return (high + .05) / (low + .05);
}

/// The colour the ink actually sits on, read back off the widget that paints
/// it rather than copied out of the theme by hand.
BoxDecoration _decorationOf(WidgetTester tester, Finder finder) =>
    switch (tester.widget(finder)) {
      Container(:final decoration) => decoration! as BoxDecoration,
      AnimatedContainer(:final decoration) => decoration! as BoxDecoration,
      _ => throw StateError('no decoration on $finder'),
    };

/// Every colour the ink might land on: a gradient's stops, or a flat fill.
List<Color> _grounds(BoxDecoration decoration) {
  final gradient = decoration.gradient;
  return gradient is LinearGradient
      ? gradient.colors
      : <Color>[decoration.color!];
}

Widget _host(Widget child, {Brightness brightness = Brightness.light}) =>
    MaterialApp(
      theme: buildClawnsoleTheme(brightness),
      home: Scaffold(body: Center(child: child)),
    );

void main() {
  testWidgets('HardwareSwitch reports the opposite state on tap', (
    tester,
  ) async {
    bool? received;
    await tester.pumpWidget(
      _host(
        HardwareSwitch(value: false, onChanged: (value) => received = value),
      ),
    );
    await tester.tap(find.byType(HardwareSwitch));
    expect(received, isTrue);

    await tester.pumpWidget(
      _host(
        HardwareSwitch(value: true, onChanged: (value) => received = value),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byType(HardwareSwitch));
    expect(received, isFalse);
  });

  testWidgets('HardwareSwitch dims and ignores taps when disabled', (
    tester,
  ) async {
    await tester.pumpWidget(
      _host(const HardwareSwitch(value: false, onChanged: null)),
    );
    await tester.tap(find.byType(HardwareSwitch));
    await tester.pump();
    final opacity = tester.widget<Opacity>(
      find.descendant(
        of: find.byType(HardwareSwitch),
        matching: find.byType(Opacity),
      ),
    );
    expect(opacity.opacity, lessThan(1));
  });

  testWidgets('HardwareSwitchTile toggles from anywhere on the row', (
    tester,
  ) async {
    var value = true;
    await tester.pumpWidget(
      _host(
        StatefulBuilder(
          builder: (context, setState) => HardwareSwitchTile(
            title: 'Synchronized audio',
            subtitle: 'Dialogue, ambience, and sound',
            value: value,
            onChanged: (next) => setState(() => value = next),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Synchronized audio'));
    await tester.pumpAndSettle();
    expect(value, isFalse);
    await tester.tap(find.text('Dialogue, ambience, and sound'));
    await tester.pumpAndSettle();
    expect(value, isTrue);
  });

  testWidgets('HardwareSlider snaps dragging to its divisions', (tester) async {
    final seen = <double>[];
    await tester.pumpWidget(
      _host(
        SizedBox(
          width: 400,
          child: HardwareSlider(
            value: 2,
            min: 2,
            max: 10,
            divisions: 8,
            onChanged: seen.add,
          ),
        ),
      ),
    );
    await tester.drag(find.byType(Slider), const Offset(220, 0));
    await tester.pumpAndSettle();
    expect(seen, isNotEmpty);
    expect(seen.last, greaterThan(2));
    expect(seen.last, seen.last.roundToDouble());
    expect(seen.last, lessThanOrEqualTo(10));
  });

  testWidgets('HardwareSlider renders in dark mode', (tester) async {
    await tester.pumpWidget(
      _host(
        SizedBox(
          width: 400,
          child: HardwareSlider(
            value: 3,
            min: 0,
            max: 4,
            divisions: 4,
            onChanged: (_) {},
          ),
        ),
        brightness: Brightness.dark,
      ),
    );
    expect(find.byType(Slider), findsOneWidget);
  });

  testWidgets('CounterReadout shows the value with its unit', (tester) async {
    await tester.pumpWidget(_host(const CounterReadout('8', unit: 's')));
    expect(find.text('8'), findsOneWidget);
    expect(find.text('s'), findsOneWidget);
  });

  test('the money surface and switch lamp stay light on paper', () {
    // Green is money in both modes, but light mode must never carry a large
    // dark block or a dark accent on a control.
    expect(_luminance(ClawnsoleTokens.light.money), greaterThan(.6));
    expect(_luminance(ClawnsoleTokens.dark.money), lessThan(.1));
    expect(
      _contrast(
        ClawnsoleTokens.light.onMoneyMuted,
        ClawnsoleTokens.light.money,
      ),
      greaterThan(4.5),
    );
    // The lit switch reads as a lamp on paper, not a dark blot.
    expect(
      _luminance(ClawnsoleTokens.light.switchOn),
      greaterThan(_luminance(ClawnsoleTokens.dark.switchOn)),
    );
  });

  test('light mode gives a dark background only to casework', () {
    // The rule: in light mode the only dark backgrounds are buttons and the
    // rail/tab bar. Every other panel is content and follows the mode.
    for (final surface in PanelSurface.values) {
      final onPaper = surface.ground(ClawnsoleTokens.light);
      if (surface.isCasework) {
        expect(
          _luminance(onPaper),
          lessThan(.1),
          reason: '$surface is the cabinet and stays dark',
        );
      } else {
        expect(
          _luminance(onPaper),
          greaterThan(.5),
          reason: '$surface is content and must not be a dark block on paper',
        );
      }
      // At night every panel is dark, and ink is readable on all of them.
      expect(
        _luminance(surface.ground(ClawnsoleTokens.dark)),
        lessThan(.2),
        reason: '$surface should stay dark at night',
      );
      for (final tokens in <ClawnsoleTokens>[
        ClawnsoleTokens.light,
        ClawnsoleTokens.dark,
      ]) {
        expect(
          _contrast(surface.ink(tokens).on, surface.ground(tokens)),
          greaterThan(4.5),
          reason: '$surface ink must clear the body-text floor',
        );
      }
    }
  });

  testWidgets('the selected label clears 4.5:1 on the brushed carriage', (
    tester,
  ) async {
    for (final brightness in Brightness.values) {
      await tester.pumpWidget(
        _host(
          HardwareChoiceSwitch(
            firstLabel: 'AUTO',
            secondLabel: 'MANUAL',
            firstSelected: true,
            onChanged: (_) {},
          ),
          brightness: brightness,
        ),
      );
      // MaterialApp lerps between themes; settle before reading the paint.
      await tester.pumpAndSettle();
      final ink = tester.widget<Text>(find.text('AUTO')).style!.color!;
      final carriage = _grounds(
        _decorationOf(
          tester,
          find.descendant(
            of: find.byType(FractionallySizedBox),
            matching: find.byType(Container),
          ),
        ),
      );
      for (final ground in carriage) {
        expect(
          _contrast(ink, ground),
          greaterThan(4.5),
          reason:
              'the lit half of the carriage must stay readable in '
              '$brightness (ground $ground)',
        );
      }
      // …and the idle half, which sits on the recessed well.
      final idle = tester.widget<Text>(find.text('MANUAL')).style!.color!;
      final well = _decorationOf(
        tester,
        find
            .descendant(
              of: find.byType(HardwareChoiceSwitch),
              matching: find.byType(Container),
            )
            .first,
      ).color!;
      expect(
        _contrast(idle, well),
        greaterThan(4.5),
        reason: 'the unlit half must stay readable in $brightness',
      );
    }
  });

  testWidgets('counter numerals clear 4.5:1 on the readout window', (
    tester,
  ) async {
    for (final brightness in Brightness.values) {
      await tester.pumpWidget(
        _host(const CounterReadout('10', unit: 's'), brightness: brightness),
      );
      await tester.pumpAndSettle();
      final window = _grounds(
        _decorationOf(
          tester,
          find.descendant(
            of: find.byType(CounterReadout),
            matching: find.byType(Container),
          ),
        ),
      );
      final numerals = tester.widget<Text>(find.text('10')).style!.color!;
      final unit = tester.widget<Text>(find.text('s')).style!.color!;
      for (final ground in window) {
        expect(
          _contrast(numerals, ground),
          greaterThan(4.5),
          reason: 'readout numerals must stay readable in $brightness',
        );
        expect(
          _contrast(unit, ground),
          greaterThan(4.5),
          reason: 'the readout unit must stay readable in $brightness',
        );
      }
    }
  });

  testWidgets('a lit console key clears 4.5:1 on the plum gradient', (
    tester,
  ) async {
    for (final brightness in Brightness.values) {
      await tester.pumpWidget(
        _host(
          ConsoleFilterSegment(
            label: 'Ready',
            count: 3,
            selected: true,
            onTap: () {},
          ),
          brightness: brightness,
        ),
      );
      await tester.pumpAndSettle();
      final key = _grounds(
        _decorationOf(tester, find.byType(AnimatedContainer)),
      );
      final ink = tester.widget<Text>(find.text('Ready')).style!.color!;
      for (final ground in key) {
        expect(
          _contrast(ink, ground),
          greaterThan(4.5),
          reason:
              'a selected console key must stay readable in $brightness '
              '(ground $ground)',
        );
      }
    }
  });

  testWidgets('the estimated-charge panel paints the money surface', (
    tester,
  ) async {
    for (final brightness in Brightness.values) {
      await tester.pumpWidget(
        _host(
          const TexturePanel(
            surface: PanelSurface.hunterFelt,
            stitched: true,
            child: Text('Estimated charge'),
          ),
          brightness: brightness,
        ),
      );
      // MaterialApp lerps between themes; settle before reading the paint.
      await tester.pumpAndSettle();
      final decoration =
          tester
                  .widget<Container>(
                    find
                        .descendant(
                          of: find.byType(TexturePanel),
                          matching: find.byType(Container),
                        )
                        .first,
                  )
                  .decoration
              as BoxDecoration;
      final tokens = brightness == Brightness.dark
          ? ClawnsoleTokens.dark
          : ClawnsoleTokens.light;
      expect(decoration.color, tokens.money);
    }
  });
}
