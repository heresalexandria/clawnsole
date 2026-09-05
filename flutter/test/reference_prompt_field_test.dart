import 'package:clawnsole/app/app_theme.dart';
import 'package:clawnsole/core/models.dart';
import 'package:clawnsole/core/reference_prompts.dart';
import 'package:clawnsole/ui/reference_prompt_field.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

const references = [
  PromptReferenceOption(
    id: 'portrait',
    mention: PromptReferenceMention(
      kind: MediaReferenceKind.image,
      number: 1,
      name: 'Hero portrait',
    ),
    label: 'portrait.png',
  ),
  PromptReferenceOption(
    id: 'motion',
    mention: PromptReferenceMention(
      kind: MediaReferenceKind.video,
      number: 1,
      name: 'Camera move',
    ),
    label: 'motion.mp4',
  ),
];

void main() {
  testWidgets('Escape then Tab lets a screenplay editor release focus', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Column(
            children: [
              ReferencePromptField(
                prompt: 'INT. STUDIO - DAY',
                formRevision: 0,
                references: const [],
                screenplayMode: true,
                onChanged: (_) {},
              ),
              TextButton(onPressed: () {}, child: const Text('Next control')),
            ],
          ),
        ),
      ),
    );
    await tester.tap(find.byType(TextFormField));
    final editor = tester.widget<EditableText>(find.byType(EditableText));
    expect(editor.focusNode.hasFocus, isTrue);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pump();
    expect(editor.focusNode.hasFocus, isFalse);
  });

  testWidgets(
    'plaintext wrapped-line navigation matches a stock text field after screenplay',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(360, 900));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      const prompt =
          'First line is deliberately long enough to wrap across several visual rows in this narrow prompt field.\n    Indented plain text stays indented.\nLast short line.';
      Future<List<TextSelection>> navigate({required bool stock}) async {
        final plain = TextEditingController(text: prompt);
        Widget app({bool screenplay = false}) => MaterialApp(
          theme: buildClawnsoleTheme(Brightness.dark),
          home: Scaffold(
            body: Padding(
              padding: const EdgeInsets.all(16),
              child: stock
                  ? TextFormField(
                      controller: plain,
                      minLines: 4,
                      maxLines: 10,
                      maxLength: 50000,
                      style: const TextStyle(
                        fontFamily: promptFontFamily,
                        fontSize: 14,
                        height: 1.55,
                      ),
                      decoration: const InputDecoration(
                        counterText: '',
                        alignLabelWithHint: true,
                      ),
                    )
                  : ReferencePromptField(
                      prompt: prompt,
                      formRevision: 0,
                      references: const [],
                      screenplayMode: screenplay,
                      onChanged: (_) {},
                    ),
            ),
          ),
        );
        if (!stock) {
          await tester.pumpWidget(app(screenplay: true));
          await tester.pumpAndSettle();
        }
        await tester.pumpWidget(app());
        await tester.tap(find.byType(TextFormField));
        final editor = tester.widget<EditableText>(find.byType(EditableText));
        editor.controller.selection = const TextSelection.collapsed(
          offset: prompt.length,
        );
        await tester.pumpAndSettle();
        final selections = <TextSelection>[];
        for (final key in [
          LogicalKeyboardKey.arrowUp,
          LogicalKeyboardKey.arrowUp,
          LogicalKeyboardKey.arrowLeft,
          LogicalKeyboardKey.arrowRight,
          LogicalKeyboardKey.arrowDown,
        ]) {
          await tester.sendKeyEvent(key);
          await tester.pump();
          selections.add(editor.controller.selection);
        }
        await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
        for (final key in [
          LogicalKeyboardKey.arrowUp,
          LogicalKeyboardKey.arrowUp,
          LogicalKeyboardKey.arrowDown,
          LogicalKeyboardKey.arrowRight,
        ]) {
          await tester.sendKeyEvent(key);
          await tester.pump();
          selections.add(editor.controller.selection);
        }
        await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
        expect(editor.controller.text, prompt);
        await tester.pumpWidget(const SizedBox.shrink());
        plain.dispose();
        return selections;
      }

      final standard = await navigate(stock: true);
      expect(await navigate(stock: false), standard);
    },
  );

  testWidgets(
    'moving through existing plaintext references does not open a menu',
    (tester) async {
      const prompt = 'Track @Camera move at dawn.\nKeep the horizon level.';
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ReferencePromptField(
              prompt: prompt,
              formRevision: 0,
              references: references,
              onChanged: (_) {},
            ),
          ),
        ),
      );
      await tester.tap(find.byType(TextFormField));
      final editor = tester.widget<EditableText>(find.byType(EditableText));
      final offset = prompt.indexOf('@Camera') + 4;
      editor.controller.selection = TextSelection.collapsed(offset: offset);
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('prompt-reference-suggestions')),
        findsNothing,
      );
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.pump();
      expect(
        find.byKey(const ValueKey('prompt-reference-suggestions')),
        findsNothing,
      );
      expect(editor.controller.text, prompt);
      final actualSelection = editor.controller.selection;
      final plain = TextEditingController(text: prompt);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: TextFormField(
              controller: plain,
              minLines: 4,
              maxLines: 10,
              style: const TextStyle(
                fontFamily: promptFontFamily,
                fontSize: 14,
                height: 1.55,
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.byType(TextFormField));
      plain.selection = TextSelection.collapsed(offset: offset);
      await tester.pumpAndSettle();
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.pump();
      expect(actualSelection, plain.selection);
      await tester.pumpWidget(const SizedBox.shrink());
      plain.dispose();
    },
  );

  testWidgets(
    'Shift arrows select plaintext even when the reference menu is open',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ReferencePromptField(
              prompt: '',
              formRevision: 0,
              references: references,
              onChanged: (_) {},
            ),
          ),
        ),
      );
      await tester.enterText(find.byType(TextFormField), 'Follow @');
      await tester.pumpAndSettle();
      final menu = find.byKey(const ValueKey('prompt-reference-suggestions'));
      expect(menu, findsOneWidget);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
      await tester.pumpAndSettle();
      final editor = tester.widget<EditableText>(find.byType(EditableText));
      expect(editor.controller.selection.isCollapsed, isFalse);
      expect(editor.controller.text, 'Follow @');
      expect(menu, findsNothing);
    },
  );

  testWidgets('@ menu survives format and expanded-editor changes', (
    tester,
  ) async {
    var prompt = 'Follow ';
    var screenplay = false;
    var expanded = false;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: StatefulBuilder(
            builder: (context, setState) => Column(
              children: [
                TextButton(
                  onPressed: () => setState(() => screenplay = !screenplay),
                  child: const Text('Toggle format'),
                ),
                TextButton(
                  onPressed: () => setState(() => expanded = !expanded),
                  child: const Text('Toggle expanded'),
                ),
                Expanded(
                  child: ReferencePromptField(
                    prompt: prompt,
                    formRevision: 0,
                    references: references,
                    screenplayMode: screenplay,
                    expands: expanded,
                    onChanged: (value) => setState(() => prompt = value),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    for (final toggle in [
      null,
      'Toggle format',
      'Toggle format',
      'Toggle expanded',
      'Toggle format',
    ]) {
      if (toggle != null) {
        await tester.tap(find.text(toggle));
        await tester.pumpAndSettle();
      }
      await tester.tap(find.byType(TextFormField));
      final editable = tester.widget<EditableText>(find.byType(EditableText));
      editable.controller.selection = TextSelection.collapsed(
        offset: prompt.length,
      );
      tester.testTextInput.updateEditingValue(
        TextEditingValue(
          text: '$prompt @',
          selection: TextSelection.collapsed(offset: prompt.length + 2),
        ),
      );
      await tester.pumpAndSettle();
      final menu = find.byKey(const ValueKey('prompt-reference-suggestions'));
      expect(
        menu.hitTestable(),
        findsOneWidget,
        reason: 'format=$screenplay expanded=$expanded prompt=$prompt',
      );
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();
      expect(prompt, endsWith('@Camera move'));
      expect(menu, findsNothing);
      expect(tester.takeException(), isNull);
    }
  });

  testWidgets(
    '@ menu stays visible when the prompt is partly scrolled offscreen',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(1200, 800));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final scroll = ScrollController();
      addTearDown(scroll.dispose);
      var prompt = 'First line.\nSecond line.\nThird line.\nFollow ';
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              controller: scroll,
              child: Column(
                children: [
                  const SizedBox(height: 400),
                  StatefulBuilder(
                    builder: (context, setState) => ReferencePromptField(
                      prompt: prompt,
                      formRevision: 0,
                      references: references,
                      onChanged: (value) => setState(() => prompt = value),
                    ),
                  ),
                  const SizedBox(height: 1200),
                ],
              ),
            ),
          ),
        ),
      );
      scroll.jumpTo(430);
      await tester.pumpAndSettle();
      await tester.tap(find.byType(TextFormField));
      final editable = tester.widget<EditableText>(find.byType(EditableText));
      editable.controller.selection = TextSelection.collapsed(
        offset: prompt.length,
      );
      tester.testTextInput.updateEditingValue(
        TextEditingValue(
          text: '$prompt@',
          selection: TextSelection.collapsed(offset: prompt.length + 1),
        ),
      );
      await tester.pumpAndSettle();
      final menu = find.byKey(const ValueKey('prompt-reference-suggestions'));
      expect(menu.hitTestable(), findsOneWidget);
      expect(tester.getRect(menu).top, greaterThanOrEqualTo(0));
      expect(tester.takeException(), isNull);
    },
  );

  for (final screenplay in [false, true]) {
    for (final expanded in [false, true]) {
      testWidgets(
        '@ references at the caret: screenplay=$screenplay expanded=$expanded',
        (tester) async {
          await tester.binding.setSurfaceSize(const Size(1400, 1000));
          addTearDown(() => tester.binding.setSurfaceSize(null));
          var prompt = 'A camera follows the subject.\n\nFollow ';
          await tester.pumpWidget(
            MaterialApp(
              home: Scaffold(
                body: StatefulBuilder(
                  builder: (context, setState) => ReferencePromptField(
                    prompt: prompt,
                    formRevision: 0,
                    references: references,
                    screenplayMode: screenplay,
                    expands: expanded,
                    onChanged: (value) => setState(() => prompt = value),
                  ),
                ),
              ),
            ),
          );
          await tester.tap(find.byType(TextFormField));
          final editable = tester.widget<EditableText>(
            find.byType(EditableText),
          );
          editable.controller.selection = TextSelection.collapsed(
            offset: prompt.length,
          );
          tester.testTextInput.updateEditingValue(
            TextEditingValue(
              text: '$prompt@',
              selection: TextSelection.collapsed(offset: prompt.length + 1),
            ),
          );
          await tester.pumpAndSettle();
          final menu = find.byKey(
            const ValueKey('prompt-reference-suggestions'),
          );
          expect(menu, findsOneWidget);
          expect(menu.hitTestable(), findsOneWidget);
          expect(
            find.descendant(of: menu, matching: find.text('@Hero portrait')),
            findsOneWidget,
          );
          expect(
            find.descendant(of: menu, matching: find.text('@Camera move')),
            findsOneWidget,
          );
          await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
          await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
          await tester.sendKeyEvent(LogicalKeyboardKey.enter);
          await tester.pumpAndSettle();
          expect(
            prompt,
            'A camera follows the subject.\n\nFollow @Camera move',
          );
          expect(menu, findsNothing);
          expect(tester.takeException(), isNull);
        },
      );
    }
  }
}
