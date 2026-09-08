import 'package:clawnsole/app/app_controller.dart';
import 'package:clawnsole/app/app_theme.dart';
import 'package:clawnsole/core/gateway.dart';
import 'package:clawnsole/core/models.dart';
import 'package:clawnsole/core/reference_prompts.dart';
import 'package:clawnsole/ui/reference_prompt_field.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  for (final pauseBeforeEnter in [false, true]) {
    testWidgets(
      'Enter selects a character reference without deleting the line (pause: $pauseBeforeEnter)',
      (tester) async {
        final controller = AppController(gateway: _UnusedGateway())
          ..selectedProviderId = 'runway'
          ..selectedModelId = 'seedance2_5';
        controller.form
          ..screenplayMode = true
          ..prompt =
              'ZED: scientist from @Source Video\n\nEXT. HARBOR\n\nPier at dusk.'
          ..references = const [
            MediaReferenceDraft(
              id: 'alice',
              label: 'Alice.mp4',
              promptName: 'Alice.mp4',
              kind: MediaReferenceKind.video,
              source: '',
              durationSeconds: 6,
            ),
          ];
        try {
          await tester.pumpWidget(
            MaterialApp(
              theme: buildClawnsoleTheme(Brightness.light),
              home: Scaffold(
                body: ListenableBuilder(
                  listenable: controller,
                  builder: (context, _) => ReferencePromptField(
                    prompt: controller.form.prompt,
                    formRevision: controller.formRevision,
                    references: const [
                      PromptReferenceOption(
                        id: 'alice',
                        label: 'Alice.mp4',
                        mention: PromptReferenceMention(
                          kind: MediaReferenceKind.video,
                          number: 1,
                          name: 'Alice.mp4',
                        ),
                      ),
                    ],
                    screenplayMode: true,
                    characterNames: controller.screenplayCharacterNames,
                    onChanged: controller.updatePrompt,
                  ),
                ),
              ),
            ),
          );
          await tester.showKeyboard(find.byType(TextFormField));
          final field = tester.widget<EditableText>(find.byType(EditableText));
          final initial = field.controller.text;
          final insertion = initial.indexOf('\n\n') + 1;
          field.controller.selection = TextSelection.collapsed(
            offset: insertion,
          );
          const partial = 'ALICE: @al';
          final typed = initial.replaceRange(insertion, insertion, partial);
          final caret = insertion + partial.length;
          tester.testTextInput.updateEditingValue(
            TextEditingValue(
              text: typed,
              selection: TextSelection.collapsed(offset: caret),
            ),
          );
          await tester.pump();
          expect(controller.form.prompt, typed);
          if (pauseBeforeEnter) {
            await tester.pump(AppController.promptSettleDelay);
          }

          expect(controller.form.prompt, typed);
          expect(field.controller.text, typed);
          expect(field.controller.selection.extentOffset, caret);
          expect(controller.form.characterMappings, isEmpty);
          expect(
            find.byKey(const ValueKey('prompt-reference-video1')),
            findsOneWidget,
          );

          await tester.sendKeyEvent(LogicalKeyboardKey.enter);
          await tester.pump();
          final completed = initial.replaceRange(
            insertion,
            insertion,
            'ALICE: @Alice.mp4',
          );
          await tester.pump(AppController.promptSettleDelay);
          expect(controller.form.prompt, completed);
          expect(field.controller.text, completed);
          expect(
            field.controller.selection.extentOffset,
            insertion + 'ALICE: @Alice.mp4'.length,
          );

          // Ordinary setting edits and opening Characters must not later remove
          // the line that survived typing and reference selection.
          controller.updateForm(
            (form) => form.generateAudio = !form.generateAudio,
          );
          controller.syncScreenplayCharacterMappings();
          await tester.pump();
          expect(controller.form.prompt, completed);
          expect(field.controller.text, completed);
          expect(controller.promptWithCast, completed);
          expect(tester.takeException(), isNull);
        } finally {
          await tester.pumpWidget(const SizedBox.shrink());
          controller.dispose();
        }
      },
    );
  }
}

class _UnusedGateway implements AppGateway {
  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw StateError('Editing must not access a gateway.');
}
