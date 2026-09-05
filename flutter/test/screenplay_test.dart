import 'package:clawnsole/app/app_controller.dart';
import 'package:clawnsole/core/composer_tabs.dart';
import 'package:clawnsole/core/models.dart';
import 'package:clawnsole/core/prompt_rewrite.dart';
import 'package:clawnsole/core/provider_catalog.dart';
import 'package:clawnsole/core/reference_prompts.dart';
import 'package:clawnsole/core/screenplay.dart';
import 'package:clawnsole/ui/reference_prompt_field.dart';
import 'package:clawnsole/ui/characters_dialog.dart';
import 'package:clawnsole/ui/create_screen.dart';
import 'package:clawnsole/app/app_theme.dart';
import 'package:clawnsole/ui/screenplay_input.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

TextEditingValue edit(String text, [int? caret]) => TextEditingValue(
  text: text,
  selection: TextSelection.collapsed(offset: caret ?? text.length),
);
SavedReference actor(String id, String character) => SavedReference(
  id: id,
  name: '$id.mp4',
  characterName: character,
  kind: MediaReferenceKind.video,
  asset: AssetReference(
    kind: 'remote',
    value: 'https://example.com/$id.mp4',
    label: '$id.mp4',
  ),
  createdAt: DateTime.utc(2026),
  updatedAt: DateTime.utc(2026),
);
AppController director({List<SavedReference> references = const []}) =>
    AppController()
      ..selectedProviderId = 'artcraft'
      ..selectedModelId = 'seedance_2p5'
      ..snapshot = LocalSnapshot(
        generations: const [],
        preferences: const AppPreferences(),
        hasApiKey: false,
        storage: const StorageStats(path: 'memory', bytes: 0, records: 0),
        savedReferences: references,
      );

void main() {
  test('only screenplay cues become detected characters', () {
    const script =
        'INT. LIVING ROOM - NIGHT\n\n'
        'ALICE watches TV. A VHS-style image fills the TV-screen.\n\n'
        '        ÉLODIE (V.O.)\n      (quietly)\n    Hello.\n\n'
        'BOB\nHello again.\n\n'
        'CUT TO:\n\n'
        'EXTRA: @portrait';
    expect(screenplayCharacters(script), {'ÉLODIE', 'BOB'});
    expect(screenplayCompletions(script, 'TV', []), isEmpty);
    expect(screenplayCharacters('TV VHS USA NASA'), isEmpty);
  });

  test('plaintext cast is manual and survives format changes', () async {
    final controller = director();
    addTearDown(controller.dispose);
    controller.form.prompt = 'ALICE\nHello.\n\nA TV plays VHS tapes.';
    expect(controller.scriptCharacterNames, isEmpty);
    expect(
      await controller.saveCharacterMapping(
        scriptName: 'EXTRA',
        name: 'EXTRA',
        referenceNames: [],
      ),
      isNull,
    );
    expect(controller.scriptCharacterNames, ['EXTRA']);
    controller.setScreenplayMode(true);
    expect(controller.scriptCharacterNames, ['ALICE', 'EXTRA']);
    controller.setScreenplayMode(false);
    expect(controller.scriptCharacterNames, ['EXTRA']);
  });

  test('casting requires visual references, independent of pinned frames', () {
    VideoModelDefinition model({int images = 0, int videos = 0}) =>
        VideoModelDefinition(
          id: 'test',
          label: 'Test',
          description: '',
          modes: const [VideoMode.t2v],
          aspectRatios: const ['16:9'],
          resolutions: const [],
          minDuration: 1,
          maxDuration: 1,
          durationStep: 1,
          maxKeyframes: 2,
          maxAudioReferences: 1,
          maxImageReferences: images,
          maxVideoReferences: videos,
          usdPerSecond: 0,
        );
    expect(model().supportsMediaReferences, isTrue);
    expect(model().supportsCharacterReferences, isFalse);
    expect(model(images: 1).supportsCharacterReferences, isTrue);
    expect(model(videos: 1).supportsCharacterReferences, isTrue);
  });

  test('keyframe-only models reject even reference-free cast edits', () async {
    final controller = director(references: [actor('alx', 'ALEXANDRIA')]);
    addTearDown(controller.dispose);
    controller.selectedProviderId = 'bfl';
    controller.selectedModelId = 'flux-3-video';
    controller.form.prompt = 'ALEXANDRIA\nHello.';
    controller.setScreenplayMode(true);
    final prompt = controller.form.prompt;
    expect(controller.form.references, isEmpty);
    expect(
      await controller.saveCharacterMapping(
        scriptName: 'EXTRA',
        name: 'EXTRA',
        referenceNames: [],
      ),
      isNotNull,
    );
    expect(controller.form.screenplayCharacterAliases, isEmpty);
    expect(controller.form.prompt, prompt);
  });

  test(
    'imports scene, cue, dialogue and parenthetical without changing mappings',
    () {
      const script =
          'int. station - night\n\nALEXANDRIA\n(quietly)\nWe should go.\n\nALEXANDRIA crosses the platform.\n\nALEXANDRIA: @alx.mp4';
      final result = formatScreenplay(script);
      expect(result, startsWith('INT. STATION - NIGHT'));
      expect(
        result,
        contains('        ALEXANDRIA\n      (quietly)\n    We should go.'),
      );
      expect(result, contains('\nALEXANDRIA crosses the platform.'));
      expect(result, endsWith('ALEXANDRIA: @alx.mp4'));
      expect(formatScreenplay(result), result);
      expect(screenplayCharacters(script), {'ALEXANDRIA'});
    },
  );
  test(
    'matches whole uppercase names and action entities, excluding mapping text',
    () {
      expect(
        screenplayMentionsCharacter('ALEXANDRIA walks in.', 'ALEXANDRIA'),
        isTrue,
      );
      expect(
        screenplayMentionsCharacter('ALEXANDRIA walks in.', 'ALEX'),
        isFalse,
      );
      expect(
        screenplayMentionsCharacter('alexandria walks in.', 'ALEXANDRIA'),
        isFalse,
      );
      expect(
        screenplayMentionsCharacter('ALEXANDRIA: @alx.mp4', 'ALEXANDRIA'),
        isFalse,
      );
      expect(screenplayMentionsCharacter('ÉLODIE turns.', 'ÉLODIE'), isTrue);
      expect(screenplayCharacterNameProblem('Élodie'), isNull);
      expect(screenplayCharacterNameProblem('ALEX: @foo'), isNotNull);
    },
  );
  test('scene and character completion include script and assigned names', () {
    expect(screenplayCompletions('', 'in', []), contains('INT.'));
    expect(
      screenplayCompletions('        ALICE\n    Hello.', '        AL', [
        'ALEXANDRIA',
      ]),
      containsAll(['ALICE', 'ALEXANDRIA']),
    );
    expect(screenplayCompletions('', '    AL', ['ALICE']), isEmpty);
  });
  test('software Return advances cues and parentheticals to dialogue', () {
    const formatter = ScreenplayInputFormatter();
    expect(
      formatter
          .formatEditUpdate(edit('        ALEX'), edit('        ALEX\n'))
          .text,
      '        ALEX\n    ',
    );
    expect(
      formatter
          .formatEditUpdate(edit('      (softly'), edit('      (softly\n'))
          .text,
      '      (softly)\n    ',
    );
    expect(
      formatter.formatEditUpdate(edit('    Hello.'), edit('    Hello.\n')).text,
      '    Hello.\n\n',
    );
    expect(formatter.formatEditUpdate(edit('    '), edit('    \n')).text, '\n');
  });
  test(
    'capitalization keeps selection correct and leaves composing edits intact',
    () {
      const formatter = ScreenplayInputFormatter();
      final value = formatter.formatEditUpdate(
        edit('        '),
        edit('        a'),
      );
      expect(value.text, '        A');
      expect(value.selection.extentOffset, 9);
      final composing = edit(
        '        é',
      ).copyWith(composing: const TextRange(start: 8, end: 9));
      expect(
        formatter.formatEditUpdate(edit('        '), composing),
        composing,
      );
      expect(
        formatter.formatEditUpdate(edit('int'), edit('int.')).text,
        'INT.',
      );
      expect(
        formatter
            .formatEditUpdate(edit('        ABC'), edit('        AB'))
            .text,
        '        AB',
      );
    },
  );
  test(
    'paste preserves mapping text and Enter can replace a multiline selection',
    () {
      const formatter = ScreenplayInputFormatter();
      const script =
          'int. station - day\n\nALEXANDRIA\nHello.\n\nALEXANDRIA: @alx.mp4';
      final pasted = formatter.formatEditUpdate(edit(''), edit(script));
      expect(pasted.text, formatScreenplay(script));
      expect(pasted.selection.extentOffset, pasted.text.length);
      final selected = edit('INT. ROOM\n\n        ').copyWith(
        selection: const TextSelection(baseOffset: 0, extentOffset: 19),
      );
      expect(formatter.formatEditUpdate(selected, edit('\n')).text, '\n');
      expect(
        formatter
            .formatEditUpdate(
              edit('            CUT TO:'),
              edit('            CUT TO:\n'),
            )
            .text,
        endsWith('\n\nINT. '),
      );
    },
  );
  test('Return recognizes typed cues and uppercases known names', () {
    const formatter = ScreenplayInputFormatter(characterNames: ['ALEXANDRIA']);
    expect(
      formatter
          .formatEditUpdate(edit(''), edit('int. observatory - night'))
          .text,
      'INT. OBSERVATORY - NIGHT',
    );
    expect(
      formatter.formatEditUpdate(edit('alexandria'), edit('alexandria\n')).text,
      '        ALEXANDRIA\n    ',
    );
    expect(
      formatter
          .formatEditUpdate(edit('NEW SPEAKER'), edit('NEW SPEAKER\n'))
          .text,
      '        NEW SPEAKER\n    ',
    );
    expect(
      formatter.formatEditUpdate(edit('An action.'), edit('An action.\n')).text,
      'An action.\n\n',
    );
  });
  test('screenplay rewrite instructions preserve casting over the wire', () {
    const request = PromptRewriteRequest(
      providerId: 'openai',
      modelId: 'test',
      originalPrompt: 'ALEXANDRIA',
      direction: 'Add a pause',
      screenplayMode: true,
    );
    final decoded = PromptRewriteRequest.fromJson(request.toJson());
    expect(decoded.screenplayMode, isTrue);
    expect(
      buildRewriteInstructions(decoded),
      contains('Preserve screenplay layout'),
    );
    expect(
      buildRewriteInstructions(decoded),
      contains('CHARACTER: @reference'),
    );
  });
  test(
    'automatic casting attaches once and translates through provider dialects',
    () {
      final controller = director(references: [actor('alx', 'ALEXANDRIA')]);
      addTearDown(controller.dispose);
      controller.setScreenplayMode(true);
      controller.updateForm((form) => form.prompt = 'ALEXANDRIA enters.');
      expect(controller.form.references, hasLength(1));
      expect(
        controller.form.prompt,
        'ALEXANDRIA enters.\n\nALEXANDRIA: @alx.mp4',
      );
      expect(
        translateReferencePrompt(
          controller.form.prompt,
          dialect: ReferencePromptDialect.compactAt,
          available: controller.formPromptReferenceMentions,
        ),
        endsWith('ALEXANDRIA: @video1'),
      );
      controller.updateForm(
        (form) => form.prompt = 'ALEXANDRIA enters.\n\nALEXANDRIA: @custom',
      );
      controller.updateForm((form) => form.prompt += '\nALEXANDRIA sits.');
      expect(controller.form.prompt, contains('@custom'));
      expect(controller.form.prompt, isNot(contains('@alx.mp4')));
      controller.removeReference(controller.form.references.single.id);
      controller.updateForm((form) => form.prompt += '\nALEXANDRIA leaves.');
      expect(controller.form.references, isEmpty);
    },
  );
  test('typing in prose or an unsupported model never attaches references', () {
    final controller = director(references: [actor('alx', 'ALEXANDRIA')]);
    addTearDown(controller.dispose);
    controller.updateForm((form) => form.prompt = 'ALEXANDRIA');
    expect(controller.form.references, isEmpty);
    controller.selectedProviderId = 'runway';
    controller.selectedModelId = 'gen4.5';
    controller.setScreenplayMode(true);
    expect(controller.form.references, isEmpty);
    expect(controller.selectedModelId, 'gen4.5');
  });
  test(
    'manual assignments normalize names, reject duplicates and unassign',
    () async {
      final controller = director();
      addTearDown(controller.dispose);
      controller.form.references = const [
        MediaReferenceDraft(
          id: 'one',
          label: 'one.mp4',
          kind: MediaReferenceKind.video,
          source: 'https://example.com/one.mp4',
        ),
        MediaReferenceDraft(
          id: 'two',
          label: 'two.mp4',
          kind: MediaReferenceKind.video,
          source: 'https://example.com/two.mp4',
        ),
      ];
      controller.setScreenplayMode(true);
      controller.updateForm((form) => form.prompt = 'ALEXANDRIA enters.');
      expect(
        await controller.setDraftCharacterName('one', ' alexandria '),
        isTrue,
      );
      expect(controller.form.prompt, contains('ALEXANDRIA: @Video 1'));
      expect(
        await controller.setDraftCharacterName('two', 'Alexandria'),
        isFalse,
      );
      expect(await controller.setDraftCharacterName('one', ''), isTrue);
      expect(controller.form.prompt, isNot(contains('ALEXANDRIA: @')));
    },
  );
  test('mode and removed-link memory round trip without storing media', () {
    final original = ComposerTabRecord(
      id: 'script',
      screenplayMode: true,
      screenplayLinkedCharacters: const ['ALEXANDRIA'],
      screenplayReferenceNames: const {'alx': 'alx.mp4'},
      screenplayCharacterAliases: const {'ALEXANDRIA': 'ALEX'},
    );
    final result = ComposerTabRecord.fromJson(original.toJson());
    expect(result.screenplayMode, isTrue);
    expect(result.screenplayLinkedCharacters, ['ALEXANDRIA']);
    expect(result.screenplayReferenceNames, {'alx': 'alx.mp4'});
    expect(result.screenplayCharacterAliases, {'ALEXANDRIA': 'ALEX'});
    final legacy = ComposerTabRecord.fromJson({
      'id': 'old',
      'prompt': 'Keep me.',
    });
    expect(legacy.screenplayMode, isFalse);
    expect(legacy.prompt, 'Keep me.');
    expect(
      SavedReference.fromJson(
        actor('alx', 'ALEXANDRIA').toJson(),
      ).characterName,
      'ALEXANDRIA',
    );
  });
  test(
    'cast supports multiple media, alias-only rename, script rename and removal',
    () async {
      final controller = director(
        references: [actor('alx', 'ALEXANDRIA'), actor('alt', '')],
      );
      addTearDown(controller.dispose);
      controller.setScreenplayMode(true);
      controller.updateForm(
        (form) => form.prompt = 'ALEXANDRIA turns. ALEXANDRIAN waits.',
      );
      expect(
        await controller.saveCharacterMapping(
          scriptName: 'ALEXANDRIA',
          name: 'HERO',
          referenceNames: ['alx.mp4', 'alt.mp4'],
        ),
        isNull,
      );
      expect(controller.form.references, hasLength(2));
      expect(controller.form.prompt, contains('ALEXANDRIA turns.'));
      expect(controller.form.prompt, endsWith('HERO: @alx.mp4 @alt.mp4'));
      expect(controller.characterMappingReferences('ALEXANDRIA'), [
        'alx.mp4',
        'alt.mp4',
      ]);
      expect(controller.scriptCharacterNames, isNot(contains('HERO')));
      expect(
        await controller.saveCharacterMapping(
          scriptName: 'ALEXANDRIA',
          name: 'HERO',
          renameInScript: true,
          referenceNames: ['alt.mp4'],
        ),
        isNull,
      );
      expect(
        controller.form.prompt,
        startsWith('HERO turns. ALEXANDRIAN waits.'),
      );
      expect(controller.form.prompt, endsWith('HERO: @alt.mp4'));
      controller.removeReference(controller.form.references.last.id);
      expect(screenplayMappings(controller.form.prompt), isEmpty);
      expect(
        await controller.saveCharacterMapping(
          scriptName: 'HERO',
          name: 'HERO',
          referenceNames: [],
        ),
        isNull,
      );
      controller.updateForm((form) => form.prompt += '\nMore action.');
      expect(screenplayMappings(controller.form.prompt), isEmpty);
    },
  );

  test(
    'cast rejects duplicate names and incompatible media without editing text',
    () async {
      final controller = director(references: [actor('alx', '')]);
      addTearDown(controller.dispose);
      controller.form.screenplayMode = true;
      controller.form.prompt = 'ALICE\nHello.\n\nBOB\nHi.';
      final original = controller.form.prompt;
      expect(
        await controller.saveCharacterMapping(
          scriptName: 'ALICE',
          name: 'BOB',
          referenceNames: [],
        ),
        isNotNull,
      );
      controller.selectedProviderId = 'runway';
      controller.selectedModelId = 'gen4.5';
      expect(
        await controller.saveCharacterMapping(
          scriptName: 'ALICE',
          name: 'ALICE',
          referenceNames: ['alx.mp4'],
        ),
        isNotNull,
      );
      expect(controller.form.prompt, original);
      expect(controller.form.references, isEmpty);
    },
  );

  for (final supported in [false, true]) {
    testWidgets('character controls follow model support: $supported', (
      tester,
    ) async {
      final controller = director();
      addTearDown(controller.dispose);
      if (!supported) {
        controller.selectedProviderId = 'bfl';
        controller.selectedModelId = 'flux-3-video';
      }
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: CreateScreen(controller: controller)),
        ),
      );
      await tester.pumpAndSettle();
      final characters = find.byKey(const ValueKey('prompt-characters-button'));
      expect(characters, supported ? findsOneWidget : findsNothing);
      await tester.tap(find.byKey(const ValueKey('prompt-fullscreen-button')));
      await tester.pumpAndSettle();
      expect(
        find.descendant(
          of: find.byKey(const ValueKey('prompt-fullscreen-editor')),
          matching: characters,
        ),
        supported ? findsOneWidget : findsNothing,
      );
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets(
    'mobile toolbar stays on one line and screenplay controls follow the editor',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(360, 850));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final controller = director();
      addTearDown(controller.dispose);
      controller.form.screenplayMode = true;
      await tester.runAsync(() async {
        final font = FontLoader('DM Sans')
          ..addFont(rootBundle.load('assets/fonts/DMSans-400.ttf'))
          ..addFont(rootBundle.load('assets/fonts/DMSans-700.ttf'));
        await font.load();
      });
      final theme = buildClawnsoleTheme(Brightness.dark);
      await tester.pumpWidget(
        MaterialApp(
          theme: theme,
          home: Scaffold(body: CreateScreen(controller: controller)),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Direction'), findsNothing);
      final header = find.byKey(const ValueKey('direction-header'));
      final headerY = tester.getCenter(header).dy;
      for (final key in [
        'prompt-format-picker',
        'prompt-clear-button',
        'prompt-character-limit',
        'prompt-fullscreen-button',
      ]) {
        expect(
          tester.getCenter(find.byKey(ValueKey(key))).dy,
          closeTo(headerY, 1),
        );
        expect(
          tester.getRect(find.byKey(ValueKey(key))).right,
          lessThanOrEqualTo(tester.getRect(header).right),
        );
      }
      final copy = find.byKey(const ValueKey('prompt-copy-button'));
      final rewrite = find.byKey(const ValueKey('prompt-rewrite-button'));
      final characters = find.byKey(const ValueKey('prompt-characters-button'));
      expect(tester.getCenter(copy).dy, tester.getCenter(rewrite).dy);
      expect(tester.getCenter(copy).dy, tester.getCenter(characters).dy);
      expect(
        tester.getRect(characters).right,
        lessThanOrEqualTo(
          tester.getRect(find.byKey(const ValueKey('direction-toolbar'))).right,
        ),
      );
      final aesthetic = find.byKey(const ValueKey('prompt-aesthetic-picker'));
      expect(
        tester.getRect(aesthetic).left,
        greaterThanOrEqualTo(tester.getRect(characters).right),
      );
      expect(
        tester.getRect(aesthetic).right,
        lessThanOrEqualTo(
          tester.getRect(find.byKey(const ValueKey('direction-toolbar'))).right,
        ),
      );
      final field = find.byType(TextFormField).first;
      expect(
        tester.getBottomLeft(copy).dy,
        lessThan(tester.getTopLeft(field).dy),
      );
      expect(
        tester
            .getTopLeft(
              find.byKey(const ValueKey('screenplay-element-toolbar')),
            )
            .dy,
        greaterThan(tester.getBottomLeft(field).dy),
      );
      expect(
        TextButtonTheme.of(
          tester.element(copy),
        ).style!.foregroundColor!.resolve({}),
        theme.textButtonTheme.style!.foregroundColor!.resolve({}),
      );
      expect(tester.takeException(), isNull);
      await tester.binding.setSurfaceSize(const Size(320, 850));
      await tester.pumpAndSettle();
      final narrowY = tester.getCenter(header).dy;
      for (final key in [
        'prompt-format-picker',
        'prompt-clear-button',
        'prompt-character-limit',
        'prompt-fullscreen-button',
      ]) {
        expect(
          tester.getCenter(find.byKey(ValueKey(key))).dy,
          closeTo(narrowY, 1),
        );
        expect(
          tester.getRect(find.byKey(ValueKey(key))).right,
          lessThanOrEqualTo(tester.getRect(header).right),
        );
      }
    },
  );

  testWidgets(
    'ordinary arrows move and select text with screenplay completions visible',
    (tester) async {
      const prompt = 'A first line.\n\n';
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ReferencePromptField(
              prompt: prompt,
              formRevision: 0,
              references: const [],
              screenplayMode: true,
              characterNames: const ['ALEXANDRIA'],
              onChanged: (_) {},
            ),
          ),
        ),
      );
      await tester.tap(find.byType(TextFormField));
      final editor = tester.widget<EditableText>(find.byType(EditableText));
      editor.controller.selection = const TextSelection.collapsed(
        offset: prompt.length,
      );
      await tester.pump();
      expect(find.widgetWithText(InputChip, 'INT.'), findsOneWidget);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
      await tester.pump();
      expect(editor.controller.selection.extentOffset, lessThan(prompt.length));
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.pump();
      expect(editor.controller.selection.extentOffset, prompt.length);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
      await tester.pump();
      expect(editor.controller.selection.isCollapsed, isFalse);
      expect(editor.controller.text, prompt);
    },
  );

  for (final width in [360.0, 1200.0]) {
    testWidgets('characters modal maps and renames at width $width', (
      tester,
    ) async {
      await tester.binding.setSurfaceSize(Size(width, 900));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final controller = director(references: [actor('alx', '')]);
      addTearDown(controller.dispose);
      controller.form.screenplayMode = true;
      controller.form.prompt = '        ALEXANDRIA\n    Hello.';
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () => showCharactersDialog(context, controller),
                child: const Text('Open cast'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Open cast'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('ALEXANDRIA'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('mapping-character-name')),
        'HERO',
      );
      await tester.tap(find.text('@alx.mp4'));
      await tester.tap(find.byKey(const ValueKey('save-character-mapping')));
      await tester.pumpAndSettle();
      expect(
        controller.form.prompt,
        '        ALEXANDRIA\n    Hello.\n\nHERO: @alx.mp4',
      );
      expect(find.text('HERO'), findsOneWidget);
      await tester.tap(find.text('HERO'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Also rename in direction'));
      await tester.tap(find.text('Remove all'));
      await tester.tap(find.byKey(const ValueKey('save-character-mapping')));
      await tester.pumpAndSettle();
      expect(controller.form.prompt, '        HERO\n    Hello.');
      controller.setScreenplayMode(false);
      await tester.tap(find.text('Add character'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('mapping-character-name')),
        'EXTRA',
      );
      await tester.tap(find.byKey(const ValueKey('save-character-mapping')));
      await tester.pumpAndSettle();
      expect(find.text('EXTRA'), findsOneWidget);
      expect(controller.scriptCharacterNames, ['EXTRA', 'HERO']);
      expect(controller.form.prompt, '        HERO\n    Hello.');
      expect(tester.takeException(), isNull);
    });
  }
  for (final width in [360.0, 1200.0]) {
    testWidgets('screenplay keyboard and touch editing at width $width', (
      tester,
    ) async {
      await tester.binding.setSurfaceSize(Size(width, 800));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      var prompt = '';
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: StatefulBuilder(
              builder: (context, setState) => ReferencePromptField(
                prompt: prompt,
                formRevision: 0,
                references: const [],
                screenplayMode: true,
                characterNames: const ['ALEXANDRIA'],
                onChanged: (value) => setState(() => prompt = value),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.byType(TextFormField));
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pump();
      expect(prompt, '        ');
      await tester.enterText(find.byType(TextFormField), '        al');
      await tester.pump();
      expect(
        tester
            .getTopLeft(
              find.byKey(const ValueKey('screenplay-element-toolbar')),
            )
            .dy,
        lessThan(
          tester.getTopLeft(find.widgetWithText(InputChip, 'ALEXANDRIA')).dy,
        ),
      );
      await tester.tap(find.widgetWithText(InputChip, 'ALEXANDRIA'));
      await tester.pump();
      expect(prompt, '        ALEXANDRIA');
      await tester.enterText(find.byType(TextFormField), '$prompt\n');
      await tester.pump();
      expect(prompt, '        ALEXANDRIA\n    ');
      await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
      await tester.pump();
      expect(prompt, endsWith('\n        '));
      await tester.tap(find.text('Prev'));
      await tester.pump();
      expect(prompt, endsWith('\n'));
      expect(tester.takeException(), isNull);
    });
  }
}
