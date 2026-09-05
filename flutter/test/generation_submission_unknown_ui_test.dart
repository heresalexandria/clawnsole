import 'package:clawnsole/core/generation_status.dart';
import 'package:clawnsole/core/models.dart';
import 'package:clawnsole/ui/common_widgets.dart';
import 'package:clawnsole/ui/generation_error_thumbnail.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets(
    'uncertain submissions explain account recovery without a spinner',
    (tester) async {
      final semantics = tester.ensureSemantics();
      final now = DateTime.utc(2026, 9, 5);
      final item = Generation(
        localId: 'uncertain',
        status: submissionUnknownStatus,
        prompt: 'A red bird',
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
      expect(item.isWorking, isFalse);
      expect(item.isFailed, isFalse);
      expect(GenerationErrorThumbnail.shouldShow(item), isTrue);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Column(
              children: [
                StatusBadge(item: item),
                SizedBox(
                  width: 400,
                  height: 240,
                  child: GenerationErrorThumbnail(item: item),
                ),
              ],
            ),
          ),
        ),
      );
      expect(find.text(submissionUnknownStatus), findsOneWidget);
      expect(find.text(submissionUnknownMessage), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsNothing);
      expect(
        find.bySemanticsLabel(RegExp('^Submission unknown:')),
        findsOneWidget,
      );
      expect(
        find.bySemanticsLabel(RegExp('^Generation failed:')),
        findsNothing,
      );
      semantics.dispose();
    },
  );
}
