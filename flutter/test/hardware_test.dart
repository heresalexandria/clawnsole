import 'package:clawnsole/app/app_theme.dart';
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
