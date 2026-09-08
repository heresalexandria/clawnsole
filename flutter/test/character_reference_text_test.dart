import 'dart:convert';

import 'package:clawnsole/app/app_controller.dart';
import 'package:clawnsole/core/gateway.dart';
import 'package:clawnsole/core/models.dart';
import 'package:clawnsole/core/prompt_rewrite.dart';
import 'package:clawnsole/core/web_gateway.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

const _direction = 'EXT. HARBOR\n\nSOURCE: @Source Video\n\nAlice waits.\n';
const _custom = 'Use the reference for appearance only.\n Keep this spacing.\n';
const _generated = 'ALICE: @Alice.mp4';
const _snapshot = LocalSnapshot(
  generations: [],
  preferences: AppPreferences(),
  hasApiKey: false,
  connectedProviders: {'runway'},
  storage: StorageStats(path: 'memory', bytes: 0, records: 0),
);

void main() {
  testWidgets(
    'character text edits settle once and remain independent per tab',
    (tester) async {
      final controller = _controller(_UnusedGateway());
      final originalTab = controller.activeComposerTabId;
      controller.form
        ..prompt = _direction
        ..characterMappings['ALICE'] = ['Alice.mp4'];
      var notifications = 0;
      var textEdits = 0;
      controller.addListener(() => notifications += 1);
      controller.promptEdits.addListener(() => textEdits += 1);
      expect(controller.characterReferenceText, _generated);
      for (final text in ['Use', 'Use the', _custom]) {
        controller.updateCharacterReferenceText(text);
      }
      expect(controller.characterReferenceText, _custom);
      expect(controller.form.prompt, _direction);
      expect(notifications, 0);
      expect(textEdits, 3);
      await tester.pump(AppController.promptSettleDelay);
      expect(notifications, 1);
      controller.updateForm(
        (form) => form.characterMappings['ALICE'] = ['new.mp4'],
      );
      expect(controller.characterReferenceText, _custom);
      expect(controller.generatedCharacterReferenceText, 'ALICE: @new.mp4');
      controller.addComposerTab();
      controller.updateCharacterReferenceText('');
      expect(controller.hasCharacterReferenceTextOverride, isTrue);
      expect(controller.activeComposerTab.isBlank, isFalse);
      controller.activateComposerTab(originalTab);
      expect(controller.characterReferenceText, _custom);
      expect(controller.form.prompt, _direction);
      controller.resetCharacterReferenceText();
      expect(controller.hasCharacterReferenceTextOverride, isFalse);
      expect(controller.characterReferenceText, 'ALICE: @new.mp4');
      expect(controller.form.prompt, _direction);
      controller.dispose();
    },
  );

  test(
    'reference rename follows mentions without deleting custom prose',
    () async {
      final controller = _controller(_UnusedGateway());
      addTearDown(controller.dispose);
      controller.form.references = const [
        MediaReferenceDraft(
          id: 'alice',
          label: 'Alice.mp4',
          promptName: 'Alice.mp4',
          kind: MediaReferenceKind.video,
          source: '',
        ),
      ];
      controller.updateCharacterReferenceText(
        'Use @Alice.mp4 for appearance.\nLeave @Other untouched.\n',
      );
      expect(
        await controller.renameDraftReference('alice', 'Alice profile'),
        isTrue,
      );
      const renamed =
          'Use @Alice profile for appearance.\nLeave @Other untouched.\n';
      expect(controller.characterReferenceText, renamed);
      controller.removeReference('alice');
      expect(controller.characterReferenceText, renamed);
      expect(controller.form.prompt, isEmpty);
    },
  );

  test('edited reference text keeps conflicting authored choices verbatim', () {
    final controller = _controller(_UnusedGateway());
    addTearDown(controller.dispose);
    const direction = 'Extend @Film.\n\nALICE: @New clip\n';
    const edited = '  ALICE: @Another clip\nKeep this explicit choice.\n';
    controller.form
      ..prompt = direction
      ..characterMappings['ALICE'] = ['Earlier clip'];

    controller.updateCharacterReferenceText(edited);

    expect(controller.characterHasAuthoredMapping('ALICE'), isTrue);
    expect(controller.generatedCharacterReferenceText, isEmpty);
    expect(controller.characterReferenceText, edited);
    expect(controller.form.prompt, direction);
    expect(controller.promptWithCast, '${direction.trimRight()}\n\n$edited');
    expect(controller.form.characterMappings, {
      'ALICE': ['Earlier clip'],
    });
    controller.resetCharacterReferenceText();
    expect(controller.promptWithCast, direction);
  });

  for (final (direction, generated) in [
    (_direction, _generated),
    (_direction.replaceFirst('SOURCE:', 'ALICE:'), ''),
  ]) {
    for (final override in <String?>[null, '', _custom]) {
      test(
        'submission and reuse preserve ${generated.isEmpty ? 'authored casting with' : 'unrelated inline text with'} ${override == null
            ? 'automatic'
            : override.isEmpty
            ? 'empty'
            : 'edited'} character text',
        () async {
          final submissions = <Map<String, dynamic>>[];
          final gateway = WebGateway(
            baseUrl: Uri.parse('http://127.0.0.1:8787'),
            client: MockClient((request) async {
              switch (request.url.path) {
                case '/account':
                  return http.Response(jsonEncode({'provider': 'runway'}), 200);
                case '/generations':
                  final body = jsonDecode(request.body) as Map<String, dynamic>;
                  submissions.add(body);
                  return http.Response(
                    jsonEncode({'generation': body['record']}),
                    201,
                  );
                case '/composer-tabs':
                  return http.Response('{}', 200);
                case '/action':
                  return http.Response(jsonEncode(_snapshot.toJson()), 200);
                default:
                  throw StateError('Unexpected fixture request.');
              }
            }),
          );
          final controller = _controller(gateway);
          addTearDown(controller.dispose);
          controller.form
            ..prompt = direction
            ..characterMappings['ALICE'] = ['Alice.mp4'];
          if (override != null) {
            controller.updateCharacterReferenceText(override);
          }
          final referenceText = override ?? generated;
          final composed = referenceText.isEmpty
              ? direction
              : '${direction.trimRight()}\n\n$referenceText';
          final expected = composed.trim();
          expect(controller.promptWithCast, composed);
          expect(controller.generationPrompt, expected);
          await controller.submit(providerRetentionRiskAcknowledged: true);
          expect(submissions, hasLength(1), reason: controller.notice);
          final record = Generation.fromJson(
            Map<String, Object?>.from(submissions.single['record'] as Map),
          );
          expect(record.prompt, expected);
          expect(record.config.authoredPrompt, direction);
          expect(record.config.characterReferenceTextOverride, override);
          expect(record.config.characterMappings, {
            'ALICE': ['Alice.mp4'],
          });
          final copiedConfig = GenerationConfig.fromJson(
            record.config.copyWith().toJson(),
          );
          expect(copiedConfig.authoredPrompt, direction);
          expect(copiedConfig.characterReferenceTextOverride, override);
          expect(
            copiedConfig.characterMappings,
            record.config.characterMappings,
          );
          controller.addComposerTab();
          await controller.reuse(record);
          expect(controller.form.prompt, direction);
          expect(controller.characterReferenceText, override ?? generated);
          expect(controller.generationPrompt, expected);
          controller.resetCharacterReferenceText();
          expect(controller.characterReferenceText, generated);
          expect(controller.form.prompt, direction);
        },
      );
    }
  }

  test('a rewrite for a closed tab is retained in a separate draft', () {
    final controller = _controller(_UnusedGateway());
    addTearDown(controller.dispose);
    final closedId = controller.activeComposerTabId;
    controller.closeComposerTab(closedId);
    final active = controller.activeComposerTab;
    controller.updatePrompt('Keep this newer work.');
    controller.applyRewrittenDirection(
      const PromptRewriteResult(
        prompt: 'The completed rewrite.',
        summary: '',
        providerId: 'openai',
        modelId: 'test',
      ),
      tabId: closedId,
      expectedPrompt: 'The original draft.',
    );
    expect(controller.activeComposerTabId, active.id);
    expect(active.form.prompt, 'Keep this newer work.');
    expect(controller.composerTabs, hasLength(2));
    expect(controller.composerTabs.last.form.prompt, 'The completed rewrite.');
  });

  test(
    'rewrite and undo preserve editable character text and authored lines',
    () {
      final controller = _controller(_UnusedGateway());
      addTearDown(controller.dispose);
      controller.form
        ..prompt = _direction
        ..characterMappings['ALICE'] = ['Alice.mp4'];
      controller.updateCharacterReferenceText(_custom);
      const rewritten = 'EXT. HARBOR\n\nSOURCE: @Source Video\n\nAlice leaves.';
      controller.applyRewrittenDirection(
        const PromptRewriteResult(
          prompt: rewritten,
          summary: '',
          providerId: 'openai',
          modelId: 'test',
        ),
        tabId: controller.activeComposerTabId,
      );
      expect(controller.form.prompt, rewritten);
      expect(controller.characterReferenceText, _custom);
      expect(
        controller.generationPrompt,
        '$rewritten\n\n${_custom.trimRight()}',
      );
      controller.updateForm(
        (form) => form.characterMappings['ALICE'] = ['new.mp4'],
      );
      controller.undoDirectionRewrite();
      expect(controller.form.prompt, _direction);
      expect(controller.characterReferenceText, _custom);
      expect(controller.generatedCharacterReferenceText, 'ALICE: @new.mp4');
    },
  );
}

AppController _controller(AppGateway gateway) => AppController(gateway: gateway)
  ..snapshot = _snapshot
  ..loading = false
  ..selectedProviderId = 'runway'
  ..selectedModelId = 'seedance2_5';

class _UnusedGateway implements AppGateway {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
