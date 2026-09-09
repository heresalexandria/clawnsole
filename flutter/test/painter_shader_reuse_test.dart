import 'package:clawnsole/app/app_theme.dart';
import 'package:clawnsole/ui/hardware.dart';
import 'package:clawnsole/ui/hardware_button.dart';
import 'package:clawnsole/ui/hardware_selector.dart';
import 'package:clawnsole/ui/paint_cache.dart';
import 'package:clawnsole/ui/panels.dart';
import 'package:clawnsole/ui/update_available_chip.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/shader_recording_canvas.dart';

Widget _host(Widget child, {Brightness brightness = Brightness.dark}) =>
    MaterialApp(
      theme: buildClawnsoleTheme(brightness),
      home: Scaffold(
        body: Align(alignment: Alignment.topLeft, child: child),
      ),
    );

CustomPainter _painterOf(WidgetTester tester, Finder finder) =>
    tester.widget<CustomPaint>(finder).painter!;

void main() {
  test('a shader cache hands back the same object and disposes evictions', () {
    final cache = ShaderCache<int>(capacity: 2);
    final one = cache.obtain(1, () => _gradient());
    expect(identical(cache.obtain(1, () => _gradient()), one), isTrue);
    final two = cache.obtain(2, () => _gradient());
    cache.obtain(3, () => _gradient());
    expect(one.debugDisposed, isTrue, reason: 'least recently used goes');
    expect(two.debugDisposed, isFalse);
    cache.clear();
    expect(two.debugDisposed, isTrue);
    expect(cache.length, 0);
  });

  for (final brightness in Brightness.values) {
    test('the machined knob reuses its machining (${brightness.name})', () {
      void paint(Canvas canvas, Size size) => paintMachinedKnob(
        canvas,
        size.center(Offset.zero),
        14,
        brightness: brightness,
        indicator: ClawnsoleColors.plum,
      );
      final report = paintTwice(paint, const Size(40, 40));
      expect(report.first, hasLength(3), reason: 'rim, face, dome');
      expect(report.newOnSecond, isEmpty);

      // A knob that moves along its groove still draws with the same three.
      final moved = ShaderRecordingCanvas();
      paintMachinedKnob(
        moved,
        const Offset(200, 20),
        14,
        brightness: brightness,
      );
      expect(moved.distinctShaders, equals(report.first));
    });
  }

  testWidgets('the switch repaints without new shaders', (tester) async {
    await tester.pumpWidget(
      _host(HardwareSwitch(value: true, onChanged: (_) {})),
    );
    final painter = _painterOf(
      tester,
      find.descendant(
        of: find.byType(HardwareSwitch),
        matching: find.byType(CustomPaint),
      ),
    );
    final report = paintTwice(painter.paint, const Size(50, 28));
    expect(report.first, isNotEmpty);
    expect(report.newOnSecond, isEmpty);
  });

  testWidgets('the Generate key reuses its bezel and lens shaders', (
    tester,
  ) async {
    await tester.pumpWidget(
      _host(HardwareLitButton(label: 'Generate video', onPressed: () {})),
    );
    final painter = _painterOf(
      tester,
      find.descendant(
        of: find.byType(HardwareLitButton),
        matching: find.byType(CustomPaint),
      ),
    );
    final report = paintTwice(painter.paint, const Size(220, 56));
    expect(report.first, hasLength(greaterThanOrEqualTo(5)));
    expect(report.newOnSecond, isEmpty);
  });

  testWidgets('a lit Generate key releases its per-frame lamp shaders', (
    tester,
  ) async {
    await tester.pumpWidget(
      _host(
        HardwareLitButton(label: 'Generate video', onPressed: () {}, lit: true),
      ),
    );
    await tester.pump(const Duration(milliseconds: 600));
    final painter = _painterOf(
      tester,
      find.descendant(
        of: find.byType(HardwareLitButton),
        matching: find.byType(CustomPaint),
      ),
    );
    final report = paintTwice(painter.paint, const Size(220, 56));
    // The lamps' halos and hot spots follow the filament, so they are built
    // for the frame; everything else is kept.
    expect(report.leakedOnSecond, isEmpty);
    expect(report.second.intersection(report.first), isNotEmpty);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('the model selector plate and key reuse their shaders', (
    tester,
  ) async {
    await tester.pumpWidget(
      _host(const HardwareSelector(child: Text('Black Forest Labs'))),
    );
    final frame = _painterOf(
      tester,
      find.byKey(const ValueKey<String>('hardware-selector-frame')),
    );
    final key = _painterOf(
      tester,
      find.byKey(const ValueKey<String>('hardware-selector-chevron')),
    );
    final plate = paintTwice(frame.paint, const Size(260, 56));
    expect(plate.first, hasLength(greaterThanOrEqualTo(8)));
    expect(plate.newOnSecond, isEmpty);
    final chevron = paintTwice(key.paint, const Size(30, 38));
    expect(chevron.first, hasLength(2));
    expect(chevron.newOnSecond, isEmpty);
  });

  test('selector painters without a cache still paint on their own', () {
    const painter = HardwareSelectorFramePainter(brightness: Brightness.light);
    final canvas = ShaderRecordingCanvas();
    painter.paint(canvas, const Size(260, 56));
    expect(canvas.shaders, isNotEmpty);
  });

  testWidgets('a stitched panel cuts its outline once', (tester) async {
    await tester.pumpWidget(
      _host(
        const SizedBox(
          width: 200,
          height: 120,
          child: TexturePanel(stitched: true, child: SizedBox()),
        ),
      ),
    );
    final stitches = tester
        .widget<CustomPaint>(
          find
              .descendant(
                of: find.byType(TexturePanel),
                matching: find.byWidgetPredicate(
                  (widget) =>
                      widget is CustomPaint &&
                      '${widget.foregroundPainter.runtimeType}' ==
                          '_StitchPainter',
                ),
              )
              .first,
        )
        .foregroundPainter!;
    final one = ShaderRecordingCanvas();
    stitches.paint(one, const Size(200, 120));
    final two = ShaderRecordingCanvas();
    stitches.paint(two, const Size(200, 120));
    expect(one.paths, hasLength(1), reason: 'every dash in one path');
    expect(identical(one.paths.single, two.paths.single), isTrue);
  });

  testWidgets('the update chip glow is released every frame, unblurred', (
    tester,
  ) async {
    await tester.pumpWidget(
      _host(UpdateAvailableChip(onPressed: () {}, installable: true)),
    );
    final painter =
        _painterOf(tester, find.byKey(const Key('update-available-glow')))
            as UpdateGlowPainter;
    final canvas = ShaderRecordingCanvas();
    for (var frame = 0; frame < 10; frame++) {
      painter.paint(canvas, const Size(120, 28));
    }
    expect(canvas.shaders, hasLength(10));
    expect(canvas.shaders.every((shader) => shader.debugDisposed), isTrue);
    expect(canvas.maskFilters, isEmpty);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}

Shader _gradient() => const LinearGradient(
  colors: <Color>[Colors.black, Colors.white],
).createShader(const Rect.fromLTWH(0, 0, 10, 10));
