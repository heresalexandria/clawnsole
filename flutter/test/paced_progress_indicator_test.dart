import 'dart:math' as math;

import 'package:clawnsole/ui/paced_progress_indicator.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/shader_recording_canvas.dart';

/// Counts arcs drawn, so a test can tell whether the ring is being redrawn.
class _ArcCountingCanvas extends ShaderRecordingCanvas {
  int arcs = 0;
  int rects = 0;

  @override
  void drawArc(
    Rect rect,
    double startAngle,
    double sweepAngle,
    bool useCenter,
    Paint paint,
  ) {
    arcs += 1;
    super.drawArc(rect, startAngle, sweepAngle, useCenter, paint);
  }

  @override
  void drawRect(Rect rect, Paint paint) {
    rects += 1;
    super.drawRect(rect, paint);
  }
}

Future<void> _pumpSecond(WidgetTester tester) async {
  for (var i = 0; i < 120; i++) {
    await tester.pump(const Duration(microseconds: 8333));
  }
}

void main() {
  test('the ring follows Material geometry: a visible, turning arc', () {
    final (start0, sweep0) = PacedCircularProgressIndicator.arcAt(
      Duration.zero,
    );
    expect(start0, closeTo(-math.pi / 2, 1e-9));
    expect(sweep0, .001, reason: 'both ends at rest before the head moves');
    final (start1, sweep1) = PacedCircularProgressIndicator.arcAt(
      const Duration(milliseconds: 400),
    );
    expect(sweep1, greaterThan(1), reason: 'the head has run ahead');
    expect(start1, isNot(start0));
    // One full 1333 ms path later the sweep repeats.
    final (_, sweepCycle) = PacedCircularProgressIndicator.arcAt(
      const Duration(milliseconds: 1733),
    );
    expect(sweepCycle, closeTo(sweep1, 1e-6));
    expect(
      PacedLinearProgressIndicator.phaseAt(const Duration(milliseconds: 900)),
      closeTo(.5, 1e-9),
    );
  });

  testWidgets('an indeterminate ring and bar repaint on the 24 fps clock', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: Column(
            children: <Widget>[
              SizedBox.square(
                dimension: 12,
                child: PacedCircularProgressIndicator(strokeWidth: 1.5),
              ),
              PacedLinearProgressIndicator(minHeight: 4),
            ],
          ),
        ),
      ),
    );
    final ring = tester
        .widget<CustomPaint>(
          find.descendant(
            of: find.byType(PacedCircularProgressIndicator),
            matching: find.byType(CustomPaint),
          ),
        )
        .painter!;
    final bar = tester
        .widget<CustomPaint>(
          find.descendant(
            of: find.byType(PacedLinearProgressIndicator),
            matching: find.byType(CustomPaint),
          ),
        )
        .painter!;
    final ringCanvas = _ArcCountingCanvas();
    ring.paint(ringCanvas, const Size(12, 12));
    expect(ringCanvas.arcs, 1);
    expect(ringCanvas.shaders, isEmpty, reason: 'a plain stroke, no shader');
    final barCanvas = _ArcCountingCanvas();
    bar.paint(barCanvas, const Size(200, 4));
    expect(barCanvas.rects, greaterThanOrEqualTo(1));

    // The painters' repaint listenables tick together, at film cadence.
    var ringFrames = 0;
    var barFrames = 0;
    ring.addListener(() => ringFrames += 1);
    bar.addListener(() => barFrames += 1);
    await _pumpSecond(tester);
    expect(ringFrames, inInclusiveRange(20, 24));
    expect(barFrames, ringFrames, reason: 'one shared pacer, one frame');
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets(
    'a determinate bar holds its clock and stops when given a value',
    (tester) async {
      Widget host(double? value) => MaterialApp(
        home: Scaffold(
          body: PacedLinearProgressIndicator(value: value, minHeight: 4),
        ),
      );
      await tester.pumpWidget(host(null));
      final live = tester
          .widget<CustomPaint>(
            find.descendant(
              of: find.byType(PacedLinearProgressIndicator),
              matching: find.byType(CustomPaint),
            ),
          )
          .painter!;
      var frames = 0;
      live.addListener(() => frames += 1);
      await _pumpSecond(tester);
      expect(frames, greaterThan(0));

      await tester.pumpWidget(host(.6));
      final settled = tester
          .widget<CustomPaint>(
            find.descendant(
              of: find.byType(PacedLinearProgressIndicator),
              matching: find.byType(CustomPaint),
            ),
          )
          .painter!;
      var settledFrames = 0;
      settled.addListener(() => settledFrames += 1);
      await _pumpSecond(tester);
      expect(
        settledFrames,
        0,
        reason: 'nothing to animate once it has a value',
      );
      final canvas = _ArcCountingCanvas();
      settled.paint(canvas, const Size(200, 4));
      expect(canvas.rects, 2, reason: 'track, then the filled portion');
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
}
