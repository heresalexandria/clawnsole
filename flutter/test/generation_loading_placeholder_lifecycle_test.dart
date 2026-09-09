import 'dart:ui' as ui;

import 'package:clawnsole/core/models.dart';
import 'package:clawnsole/ui/generation_loading_placeholder.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/shader_recording_canvas.dart';

void main() {
  for (final style in GenerationPlaceholderStyle.values) {
    testWidgets(
      '${style.name} releases per-frame shaders and reuses the rest',
      (tester) async {
        final painter = await _mountPainter(tester, style);
        const size = Size(320, 180);

        // Frame one: everything is new. Frame two: whatever the surface
        // keeps (vignette, sheen, grain, the hum bar's shape) is the same
        // object again, and whatever it builds per frame is disposed before
        // the frame ends. Nothing new survives the second paint.
        final report = paintTwice(painter.paint, size);
        expect(report.first, isNotEmpty);
        expect(report.leakedOnSecond, isEmpty);
        expect(
          report.second.intersection(report.first),
          isNotEmpty,
          reason: 'size-only shaders are kept across frames',
        );
        for (final shader in report.newOnSecond) {
          expect(shader.debugDisposed, isTrue);
        }

        // Thirty frames later the picture is the same: the kept set does not
        // grow, and nothing the frames created is left alive.
        final canvas = ShaderRecordingCanvas();
        for (var frame = 0; frame < 30; frame++) {
          painter.paint(canvas, size);
        }
        final alive = canvas.distinctShaders
            .where((shader) => !shader.debugDisposed)
            .toSet();
        expect(alive, equals(report.first.intersection(report.second)));
        expect(
          canvas.maskFilters,
          isEmpty,
          reason: 'a continuously repainting surface never blurs',
        );

        // A failed draw must also release a temporary shader owner.
        final failing = ShaderRecordingCanvas(throwOnShader: true);
        expect(() => painter.paint(failing, size), throwsStateError);
        await tester.pumpWidget(const SizedBox.shrink());
      },
    );
  }

  testWidgets('a failed draw releases the frame-only shader it was holding', (
    tester,
  ) async {
    final painter = await _mountPainter(
      tester,
      GenerationPlaceholderStyle.cyclone,
    );
    // The cyclone's chased border is the one shader it builds each frame;
    // warm the cache first so the failing draw lands on it.
    painter.paint(ShaderRecordingCanvas(), const Size(320, 180));
    final failing = _FailOnSweepCanvas();
    expect(
      () => painter.paint(failing, const Size(320, 180)),
      throwsStateError,
    );
    expect(failing.failed, isNotNull);
    expect(failing.failed!.debugDisposed, isTrue);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}

Future<CustomPainter> _mountPainter(
  WidgetTester tester,
  GenerationPlaceholderStyle style,
) async {
  final now = DateTime.utc(2026, 9, 7);
  await tester.pumpWidget(
    MaterialApp(
      home: MediaQuery(
        data: const MediaQueryData(disableAnimations: true),
        child: Center(
          child: SizedBox(
            width: 320,
            height: 180,
            child: GenerationLoadingPlaceholder(
              style: style,
              item: Generation(
                localId: 'ownership-test',
                status: 'Pending',
                prompt: 'Synthetic rendering test.',
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
              ),
            ),
          ),
        ),
      ),
    ),
  );
  final kind = style == GenerationPlaceholderStyle.broadcastStatic
      ? 'static'
      : 'cyclone';
  return tester
      .widget<CustomPaint>(
        find.byKey(ValueKey('generation-loading-$kind-ownership-test')),
      )
      .painter!;
}

/// Fails the first stroked round-rect draw carrying a shader: the cyclone's
/// per-frame chased border.
class _FailOnSweepCanvas extends ShaderRecordingCanvas {
  ui.Shader? failed;

  @override
  void drawRRect(RRect rrect, Paint paint) {
    if (paint.shader != null &&
        paint.style == PaintingStyle.stroke &&
        failed == null) {
      failed = paint.shader;
      throw StateError('Synthetic canvas failure');
    }
    super.drawRRect(rrect, paint);
  }
}
