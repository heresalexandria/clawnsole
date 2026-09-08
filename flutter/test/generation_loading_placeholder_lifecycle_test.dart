import 'dart:ui' as ui;

import 'package:clawnsole/core/models.dart';
import 'package:clawnsole/ui/generation_loading_placeholder.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  for (final style in GenerationPlaceholderStyle.values) {
    testWidgets('${style.name} releases temporary shaders after every paint', (
      tester,
    ) async {
      final painter = await _mountPainter(tester, style);
      final canvas = _ShaderRecordingCanvas();
      for (var frame = 0; frame < 30; frame++) {
        painter.paint(canvas, const Size(320, 180));
      }
      expect(canvas.shaders.length, greaterThanOrEqualTo(60));
      expect(canvas.shaders.every((shader) => shader.debugDisposed), isTrue);

      // A failed draw must also release the temporary shader owner.
      final failing = _ShaderRecordingCanvas(throwOnShader: true);
      expect(
        () => painter.paint(failing, const Size(320, 180)),
        throwsStateError,
      );
      expect(failing.shaders, hasLength(1));
      expect(failing.shaders.single.debugDisposed, isTrue);
      await tester.pumpWidget(const SizedBox.shrink());
    });
  }
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

class _ShaderRecordingCanvas implements Canvas {
  _ShaderRecordingCanvas({this.throwOnShader = false});

  final bool throwOnShader;
  final List<ui.Shader> shaders = <ui.Shader>[];

  void _record(Paint paint) {
    final shader = paint.shader;
    if (shader == null) return;
    shaders.add(shader);
    if (throwOnShader) throw StateError('Synthetic canvas failure');
  }

  @override
  void drawRect(Rect rect, Paint paint) => _record(paint);

  @override
  void drawRRect(RRect rrect, Paint paint) => _record(paint);

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}
