import 'package:clawnsole/app/app_controller.dart';
import 'package:clawnsole/app/app_theme.dart';
import 'package:clawnsole/core/gateway.dart';
import 'package:clawnsole/ui/common_widgets.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('prompt measurements release paragraphs on every rebuild', (
    tester,
  ) async {
    final controller = AppController(gateway: _UnusedGateway());
    final measurements = <TextPainter>[];
    final prompt = 'Resource fixture: ${'long scene direction ' * 40}';
    void observe(ObjectEvent event) {
      if (event is! ObjectCreated || event.object is! TextPainter) return;
      final painter = event.object as TextPainter;
      // The measurement has no ellipsis; the rendered, collapsed Text does.
      // Observe actual lifecycle events, without adding a production test hook.
      if (painter.text?.toPlainText() == prompt &&
          painter.maxLines == 3 &&
          painter.ellipsis == null) {
        measurements.add(painter);
      }
    }

    FlutterMemoryAllocations.instance.addListener(observe);
    try {
      for (var rebuild = 0; rebuild < 20; rebuild++) {
        await tester.pumpWidget(
          MaterialApp(
            theme: buildClawnsoleTheme(Brightness.light),
            home: Scaffold(
              body: SingleChildScrollView(
                child: SizedBox(
                  width: 280 + (rebuild % 2).toDouble(),
                  child: GenerationPrompt(
                    controller: controller,
                    prompt: prompt,
                    reserveCollapsedHeight: true,
                  ),
                ),
              ),
            ),
          ),
        );
        expect(measurements.length, greaterThanOrEqualTo(rebuild + 1));
        expect(measurements.every((painter) => painter.debugDisposed), isTrue);
      }

      expect(find.text('Show full prompt'), findsOneWidget);
      await tester.tap(find.text('Show full prompt'));
      await tester.pump();
      expect(find.text('Show less'), findsOneWidget);
      expect(tester.widget<Text>(find.text(prompt)).maxLines, isNull);
      await tester.ensureVisible(find.text('Show less'));
      await tester.tap(find.text('Show less'));
      await tester.pump();
      expect(tester.widget<Text>(find.text(prompt)).maxLines, 3);
      expect(measurements.every((painter) => painter.debugDisposed), isTrue);
      expect(tester.takeException(), isNull);
    } finally {
      await tester.pumpWidget(const SizedBox.shrink());
      FlutterMemoryAllocations.instance.removeListener(observe);
      controller.dispose();
    }
  });
}

class _UnusedGateway implements AppGateway {
  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw StateError('Prompt display must not access a gateway.');
}
