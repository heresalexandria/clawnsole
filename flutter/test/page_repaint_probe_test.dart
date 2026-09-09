import 'package:clawnsole/core/models.dart';
import 'package:clawnsole/ui/busy_button.dart';
import 'package:clawnsole/ui/common_widgets.dart';
import 'package:clawnsole/ui/generation_loading_placeholder.dart';
import 'package:clawnsole/ui/motion_isolate.dart';
import 'package:clawnsole/ui/paced_progress_indicator.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Counts how often the page picture around a rendering card is recorded.
class _ProbePainter extends CustomPainter {
  int paints = 0;

  @override
  void paint(Canvas canvas, Size size) => paints += 1;

  @override
  bool shouldRepaint(_ProbePainter oldDelegate) => false;
}

Generation _pending() {
  final now = DateTime.utc(2026, 9, 8);
  return Generation(
    localId: 'probe',
    status: 'Pending',
    prompt: 'A page that keeps its picture.',
    mode: VideoMode.t2v,
    config: const GenerationConfig(
      aspectRatio: '16:9',
      duration: 8,
      resolution: 'hd',
      generateAudio: true,
      safetyTolerance: 2,
      draft: false,
    ),
    createdAt: now,
    updatedAt: now,
  );
}

/// A studio page in miniature: a probe outside the card, then a card that
/// carries every vsync-driven site the real one does — the rendering
/// placeholder, the status chip's spinner, the indeterminate progress bar,
/// a busy mark — under the same [LayoutBuilder] the real card's media box
/// puts them under.
Widget _page({
  required _ProbePainter probe,
  required Widget spinner,
  required Widget bar,
}) {
  final item = _pending();
  return MaterialApp(
    home: Scaffold(
      body: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            CustomPaint(size: const Size(200, 40), painter: probe),
            const SizedBox(height: 12),
            RepaintBoundary(
              child: LayoutBuilder(
                builder: (context, constraints) => SizedBox(
                  height: 240,
                  child: Stack(
                    fit: StackFit.expand,
                    children: <Widget>[
                      GenerationLoadingPlaceholder(item: item),
                      Positioned(top: 10, left: 10, child: spinner),
                      Positioned(
                        top: 10,
                        right: 10,
                        child: BusySpinner(color: Colors.white),
                      ),
                      Positioned(bottom: 0, left: 0, right: 0, child: bar),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(height: 12),
            const Text('Recent work'),
          ],
        ),
      ),
    ),
  );
}

Future<void> _pumpFrames(WidgetTester tester, int frames) async {
  for (var i = 0; i < frames; i++) {
    await tester.pump(const Duration(milliseconds: 16));
  }
}

void main() {
  testWidgets('thirty frames of a rendering card record the page once', (
    tester,
  ) async {
    final probe = _ProbePainter();
    await tester.pumpWidget(
      _page(
        probe: probe,
        spinner: StatusBadge(item: _pending()),
        bar: const MotionIsolate(
          height: 5,
          child: LinearProgressIndicator(minHeight: 5),
        ),
      ),
    );
    await tester.pump();
    expect(probe.paints, 1);

    final surface =
        tester
                .widget<CustomPaint>(
                  find.byKey(const ValueKey('generation-loading-static-probe')),
                )
                .painter!
            as GenerationPlaceholderPainter;
    final frames = surface.frame.value;
    await _pumpFrames(tester, 30);
    expect(
      surface.frame.value - frames,
      greaterThanOrEqualTo(8),
      reason: 'the placeholder animated through the run',
    );
    expect(
      find.byType(PacedCircularProgressIndicator),
      findsOneWidget,
      reason: 'the status chip keeps its paced ring',
    );
    expect(
      find.byType(CircularProgressIndicator),
      findsOneWidget,
      reason: 'the busy mark keeps spinning in its island',
    );
    expect(
      probe.paints,
      1,
      reason: 'nothing outside the isolated islands was re-recorded',
    );
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets(
    'the probe does see an unisolated spinner under a LayoutBuilder',
    (tester) async {
      // The control: the same page with the bar's animation left bare. Its
      // per-frame rebuild schedules the LayoutBuilder above it, which dirties
      // the page's layout and repaints the probe — the failure mode this file
      // guards against.
      final probe = _ProbePainter();
      await tester.pumpWidget(
        _page(
          probe: probe,
          spinner: const SizedBox.square(
            dimension: 10,
            child: CircularProgressIndicator(strokeWidth: 1.5),
          ),
          bar: const LinearProgressIndicator(minHeight: 5),
        ),
      );
      await tester.pump();
      await _pumpFrames(tester, 30);
      expect(probe.paints, greaterThan(1));
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets('a MotionIsolate keeps a spinner from re-recording its page', (
    tester,
  ) async {
    final probe = _ProbePainter();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: LayoutBuilder(
            builder: (context, constraints) => Column(
              children: <Widget>[
                CustomPaint(size: const Size(100, 20), painter: probe),
                const MotionIsolate(
                  width: 14,
                  height: 14,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    expect(probe.paints, 1);
    await _pumpFrames(tester, 30);
    expect(probe.paints, 1);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
