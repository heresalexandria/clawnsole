import 'package:clawnsole/core/models.dart';
import 'package:clawnsole/core/reference_prompts.dart';
import 'package:clawnsole/ui/reference_prompt_field.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

const _cast = ['VINCE', 'VERA'];

const _references = [
  PromptReferenceOption(
    id: 'portrait',
    mention: PromptReferenceMention(
      kind: MediaReferenceKind.image,
      number: 1,
      name: 'Hero portrait',
    ),
    label: 'portrait.png',
  ),
];

final _menu = find.byKey(const ValueKey('prompt-reference-suggestions'));

Finder _row(String name) => find.byKey(ValueKey('prompt-character-$name'));

Color _rowColor(WidgetTester tester, String name) =>
    tester.widget<ColoredBox>(_row(name)).color;

/// Pumps the Direction editor with a cast, and returns a reader for the text
/// the field has published to its host.
Future<String Function()> _pumpField(
  WidgetTester tester, {
  List<String> characterNames = _cast,
  List<PromptReferenceOption> references = const [],
  bool screenplayMode = false,
  String prompt = '',
}) async {
  var current = prompt;
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: StatefulBuilder(
          builder: (context, setState) => ReferencePromptField(
            prompt: current,
            formRevision: 0,
            references: references,
            characterNames: characterNames,
            screenplayMode: screenplayMode,
            onChanged: (value) => setState(() => current = value),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.byType(TextFormField));
  await tester.pump();
  return () => current;
}

void main() {
  testWidgets('a typed prefix offers the cast in order, first highlighted', (
    tester,
  ) async {
    await _pumpField(tester);
    await tester.enterText(find.byType(TextFormField), 'The camera finds v');
    await tester.pumpAndSettle();
    expect(_menu.hitTestable(), findsOneWidget);
    expect(_row('VINCE'), findsOneWidget);
    expect(_row('VERA'), findsOneWidget);
    expect(
      tester.getTopLeft(_row('VINCE')).dy,
      lessThan(tester.getTopLeft(_row('VERA')).dy),
    );
    expect(_rowColor(tester, 'VINCE'), isNot(Colors.transparent));
    expect(_rowColor(tester, 'VERA'), Colors.transparent);
    // Comfortable on a fingertip, and the height the menu reserves per row.
    expect(tester.getSize(_row('VINCE')).height, greaterThanOrEqualTo(44));
    // The names read as plain names: no tag punctuation in the row.
    expect(
      find.descendant(of: _menu, matching: find.text('@VINCE')),
      findsNothing,
    );
    await tester.enterText(find.byType(TextFormField), 'The camera finds vi');
    await tester.pumpAndSettle();
    expect(_row('VINCE'), findsOneWidget);
    expect(_row('VERA'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Return completes the highlighted name as plain text', (
    tester,
  ) async {
    final prompt = await _pumpField(tester);
    await tester.enterText(find.byType(TextFormField), 'The camera finds vi');
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    // The stored spelling, no @, and no trailing space: the director keeps
    // punctuating the sentence exactly as after a completed mention.
    expect(prompt(), 'The camera finds VINCE');
    expect(_menu, findsNothing);
    final editor = tester.widget<EditableText>(find.byType(EditableText));
    expect(
      editor.controller.selection.baseOffset,
      'The camera finds VINCE'.length,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('Down then Return takes the second name', (tester) async {
    final prompt = await _pumpField(tester);
    await tester.enterText(find.byType(TextFormField), 'Then v');
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pump();
    expect(_rowColor(tester, 'VERA'), isNot(Colors.transparent));
    expect(_rowColor(tester, 'VINCE'), Colors.transparent);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(prompt(), 'Then VERA');
    expect(tester.takeException(), isNull);
  });

  testWidgets('Tab completes a name and a tap completes a name', (
    tester,
  ) async {
    final prompt = await _pumpField(tester);
    await tester.enterText(find.byType(TextFormField), 'Then vi');
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pumpAndSettle();
    expect(prompt(), 'Then VINCE');
    await tester.enterText(find.byType(TextFormField), 'Then VINCE and ve');
    await tester.pumpAndSettle();
    await tester.tap(_row('VERA'));
    await tester.pumpAndSettle();
    expect(prompt(), 'Then VINCE and VERA');
    expect(_menu, findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Escape dismisses the cast for the word being typed', (
    tester,
  ) async {
    await _pumpField(tester);
    await tester.enterText(find.byType(TextFormField), 'v');
    await tester.pumpAndSettle();
    expect(_menu, findsOneWidget);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(_menu, findsNothing);
    // Typing on inside the same word stays quiet…
    await tester.enterText(find.byType(TextFormField), 'vi');
    await tester.pumpAndSettle();
    expect(_menu, findsNothing);
    // …and the next word is offered again.
    await tester.enterText(find.byType(TextFormField), 'vi ve');
    await tester.pumpAndSettle();
    expect(_row('VERA'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a name already spelled in full is not suggested', (
    tester,
  ) async {
    await _pumpField(tester);
    for (final typed in ['Then VINCE', 'Then vince']) {
      await tester.enterText(find.byType(TextFormField), typed);
      await tester.pumpAndSettle();
      expect(_menu, findsNothing, reason: typed);
    }
    expect(tester.takeException(), isNull);
  });

  testWidgets('an active @ query keeps the cast out of the menu', (
    tester,
  ) async {
    await _pumpField(
      tester,
      characterNames: const ['HERO', 'VINCE'],
      references: _references,
    );
    await tester.enterText(find.byType(TextFormField), 'Follow @h');
    await tester.pumpAndSettle();
    expect(_menu, findsOneWidget);
    expect(
      find.descendant(of: _menu, matching: find.text('@Hero portrait')),
      findsOneWidget,
    );
    expect(_row('HERO'), findsNothing);
    // A name typed directly after the @ is part of the mention, not a cue.
    await tester.enterText(find.byType(TextFormField), 'Follow @v');
    await tester.pumpAndSettle();
    expect(_row('VINCE'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('the caret inside a word does not complete it', (tester) async {
    await _pumpField(tester);
    await tester.enterText(find.byType(TextFormField), 'The v');
    await tester.pumpAndSettle();
    expect(_menu, findsOneWidget);
    tester.testTextInput.updateEditingValue(
      const TextEditingValue(
        text: 'The vx',
        selection: TextSelection.collapsed(offset: 5),
      ),
    );
    await tester.pumpAndSettle();
    expect(_menu, findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('moving the caret away dismisses the cast', (tester) async {
    await _pumpField(tester);
    await tester.enterText(find.byType(TextFormField), 'The v');
    await tester.pumpAndSettle();
    expect(_menu, findsOneWidget);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
    await tester.pumpAndSettle();
    expect(_menu, findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a screenplay cue line keeps its own completions', (
    tester,
  ) async {
    await _pumpField(tester, screenplayMode: true);
    await tester.enterText(find.byType(TextFormField), '        v');
    await tester.pumpAndSettle();
    expect(find.widgetWithText(InputChip, 'VINCE'), findsOneWidget);
    expect(find.widgetWithText(InputChip, 'VERA'), findsOneWidget);
    expect(_menu, findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('screenplay action text completes names inline', (tester) async {
    final prompt = await _pumpField(tester, screenplayMode: true);
    await tester.enterText(find.byType(TextFormField), 'The door opens and v');
    await tester.pumpAndSettle();
    expect(find.widgetWithText(InputChip, 'VINCE'), findsNothing);
    expect(_menu.hitTestable(), findsOneWidget);
    expect(_row('VINCE'), findsOneWidget);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(prompt(), 'The door opens and VINCE');
    expect(tester.takeException(), isNull);
  });

  testWidgets('an empty cast leaves the field exactly as it was', (
    tester,
  ) async {
    final prompt = await _pumpField(tester, characterNames: const []);
    await tester.enterText(find.byType(TextFormField), 'Then v');
    await tester.pumpAndSettle();
    expect(_menu, findsNothing);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pumpAndSettle();
    expect(prompt(), 'Then v');
    expect(_menu, findsNothing);
    expect(tester.takeException(), isNull);
  });
}
