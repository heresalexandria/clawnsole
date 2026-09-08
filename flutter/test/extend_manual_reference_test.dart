import 'package:clawnsole/app/app_controller.dart';
import 'package:clawnsole/app/app_theme.dart';
import 'package:clawnsole/core/gateway.dart';
import 'package:clawnsole/core/models.dart';
import 'package:clawnsole/ui/reference_prompt_field.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

const _snapshot = LocalSnapshot(
  generations: [],
  preferences: AppPreferences(),
  hasApiKey: false,
  storage: StorageStats(path: 'memory', bytes: 0, records: 0),
);

void main() {
  for (final selectWithTap in [true, false]) {
    testWidgets(
      'Extend preserves a manually recast line selected by ${selectWithTap ? 'touch' : 'Enter'}',
      (tester) async {
        await tester.binding.setSurfaceSize(const Size(390, 844));
        addTearDown(() => tester.binding.setSurfaceSize(null));
        final controller = AppController(gateway: _ExtendGateway())
          ..selectedProviderId = 'krea'
          ..selectedModelId = 'bytedance/seedance-2-5'
          ..snapshot = _snapshot
          ..loading = false;
        try {
          await controller.extend(_previousFilm());
          expect(controller.notice, startsWith('Ready to extend'));
          expect(controller.form.characterMappings, {
            'ALEXANDRIA': ['Alexandria.mp4 trim'],
            'ZAP': ['Zap.mp4'],
          });
          const initial =
              'Extend @Previous scene seamlessly.\n'
              'ZAP: man in lab coat from @Previous scene\n\n'
              'EXT. BROOKLYN WATERFRONT CAVE - DUSK\n\n'
              'Vince and Alexandria stand next to each other.';
          controller.updatePrompt(initial);
          await tester.pumpWidget(
            MaterialApp(
              theme: buildClawnsoleTheme(Brightness.light),
              home: Scaffold(
                body: ListenableBuilder(
                  listenable: controller,
                  builder: (context, _) => ReferencePromptField(
                    prompt: controller.form.prompt,
                    formRevision: controller.formRevision,
                    references: [
                      for (final entry
                          in controller.form.references.asMap().entries)
                        PromptReferenceOption(
                          id: entry.value.id,
                          label: entry.value.label,
                          mention:
                              controller.formPromptReferenceMentions[entry.key],
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
          final insertion = initial.indexOf('\n\n') + 1;
          const partial = 'ALEXANDRIA: @Prev';
          final typed = initial.replaceRange(insertion, insertion, partial);
          tester.testTextInput.updateEditingValue(
            TextEditingValue(
              text: typed,
              selection: TextSelection.collapsed(
                offset: insertion + partial.length,
              ),
            ),
          );
          await tester.pump();
          final suggestion = find.byKey(
            const ValueKey('prompt-reference-video1'),
          );
          expect(suggestion, findsOneWidget);
          if (selectWithTap) {
            await tester.tap(suggestion);
          } else {
            await tester.sendKeyEvent(LogicalKeyboardKey.enter);
          }
          await tester.pump(AppController.promptSettleDelay);
          await tester.pump();
          final completed = initial.replaceRange(
            insertion,
            insertion,
            'ALEXANDRIA: @Previous scene',
          );
          expect(controller.form.prompt, completed);
          expect(field.controller.text, completed);
          expect(
            field.controller.selection.extentOffset,
            insertion + 'ALEXANDRIA: @Previous scene'.length,
          );
          expect(controller.generatedCharacterReferenceText, isEmpty);
          expect(controller.promptWithCast, completed);
          // Opening Characters and changing settings must neither erase the
          // manual override nor restore conflicting generated instructions.
          controller.syncScreenplayCharacterMappings();
          controller.updateForm((form) => form.aspectRatio = '16:9');
          await tester.pump();
          expect(controller.form.prompt, completed);
          expect(field.controller.text, completed);
          expect(controller.promptWithCast, completed);
          expect(controller.form.characterMappings, {
            'ALEXANDRIA': ['Alexandria.mp4 trim'],
            'ZAP': ['Zap.mp4'],
          });
          expect(tester.takeException(), isNull);
        } finally {
          await tester.pumpWidget(const SizedBox.shrink());
          controller.dispose();
        }
      },
    );
  }
}

Generation _previousFilm() => Generation(
  localId: 'previous-film',
  status: 'Ready',
  prompt:
      'Alexandria watches.\n\nALEXANDRIA: @Alexandria.mp4 trim\nZAP: @Zap.mp4',
  title: 'Previous scene',
  mode: VideoMode.t2v,
  provider: 'krea',
  model: 'bytedance/seedance-2-5',
  config: const GenerationConfig(
    aspectRatio: '9:16',
    duration: 5,
    resolution: 'hd',
    generateAudio: true,
    safetyTolerance: 2,
    draft: false,
    screenplayMode: true,
    references: [
      MediaReferenceLabel(
        label: 'Alexandria.mp4 trim',
        kind: MediaReferenceKind.video,
        promptName: 'Alexandria.mp4 trim',
        durationSeconds: 5,
        source: AssetReference(
          kind: 'remote',
          value: 'https://example.invalid/alexandria.mp4',
          label: 'Alexandria.mp4 trim',
        ),
      ),
      MediaReferenceLabel(
        label: 'Zap.mp4',
        kind: MediaReferenceKind.video,
        promptName: 'Zap.mp4',
        durationSeconds: 5,
        source: AssetReference(
          kind: 'remote',
          value: 'https://example.invalid/zap.mp4',
          label: 'Zap.mp4',
        ),
      ),
    ],
  ),
  resultUrl: 'https://example.invalid/previous-film.mp4',
  createdAt: DateTime.utc(2026, 9, 7),
  updatedAt: DateTime.utc(2026, 9, 7),
);

class _ExtendGateway implements AppGateway {
  @override
  bool get usesCompanion => false;

  @override
  bool get supportsPhotoLibrarySave => false;

  @override
  String get persistenceDescription => 'Memory';

  @override
  Future<LocalSnapshot> load() async => _snapshot;

  @override
  Future<LocalSnapshot> setPreferences(AppPreferences preferences) async =>
      _snapshot;

  @override
  Future<Uint8List> readAsset(AssetReference reference) async => Uint8List(0);

  @override
  dynamic noSuchMethod(Invocation invocation) => throw StateError(
    'Unexpected fixture gateway call: ${invocation.memberName}',
  );
}
