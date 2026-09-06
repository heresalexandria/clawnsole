import 'dart:ui' show PointerDeviceKind;

import 'package:clawnsole/core/models.dart';
import 'package:clawnsole/core/reference_prompts.dart';
import 'package:clawnsole/ui/reference_prompt_field.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

const _references = [
  PromptReferenceOption(
    id: 'hero',
    mention: PromptReferenceMention(
      kind: MediaReferenceKind.image,
      number: 1,
      name: 'Hero portrait',
    ),
    label: 'hero.png',
  ),
  PromptReferenceOption(
    id: 'camera',
    mention: PromptReferenceMention(
      kind: MediaReferenceKind.video,
      number: 1,
      name: 'Camera move',
    ),
    label: 'camera.mp4',
  ),
];

class _EditorHarness {
  String prompt = '';
  final changes = <String>[];

  Future<void> mount(
    WidgetTester tester, {
    TargetPlatform platform = TargetPlatform.iOS,
    bool screenplay = false,
    int? maxLength,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(platform: platform),
        builder: (context, child) => Actions(
          actions: <Type, Action<Intent>>{
            // Match ClawnsoleApp: a tap outside an editor dismisses the mobile
            // keyboard as well as desktop focus. Suggestions belong to it.
            EditableTextTapOutsideIntent:
                CallbackAction<EditableTextTapOutsideIntent>(
                  onInvoke: (intent) {
                    intent.focusNode.unfocus();
                    return null;
                  },
                ),
          },
          child: child!,
        ),
        home: Scaffold(
          body: StatefulBuilder(
            builder: (context, setState) => ReferencePromptField(
              prompt: prompt,
              formRevision: 0,
              references: _references,
              screenplayMode: screenplay,
              maxLength: maxLength,
              onChanged: (value) => setState(() {
                prompt = value;
                changes.add(value);
              }),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.byType(TextFormField));
    await tester.pumpAndSettle();
  }

  EditableText editor(WidgetTester tester) =>
      tester.widget<EditableText>(find.byType(EditableText));

  Future<void> input(
    WidgetTester tester,
    String text, {
    int? caret,
    TextRange composing = TextRange.empty,
  }) async {
    tester.testTextInput.updateEditingValue(
      TextEditingValue(
        text: text,
        selection: TextSelection.collapsed(offset: caret ?? text.length),
        composing: composing,
      ),
    );
    await tester.pumpAndSettle();
  }

  void expectCompleted(WidgetTester tester, String text, {int? caret}) {
    expect(prompt, text);
    expect(editor(tester).controller.text, text);
    expect(
      editor(tester).controller.selection,
      TextSelection.collapsed(offset: caret ?? text.length),
    );
    expect(editor(tester).focusNode.hasFocus, isTrue);
    expect(tester.testTextInput.isVisible, isTrue);
    expect(
      find.byKey(const ValueKey('prompt-reference-suggestions')),
      findsNothing,
    );
    expect(tester.takeException(), isNull);
  }
}

void main() {
  for (final platform in [TargetPlatform.iOS, TargetPlatform.android]) {
    testWidgets(
      'touch suggestion completes reference on ${platform.name}',
      (tester) async {
        final harness = _EditorHarness();
        await harness.mount(tester, platform: platform);
        await harness.input(tester, 'Follow @Ca');
        final option = find.text('@Camera move');
        expect(option.hitTestable(), findsOneWidget);
        final touch = await tester.startGesture(tester.getCenter(option));
        await tester.pump(const Duration(milliseconds: 100));
        expect(harness.editor(tester).focusNode.hasFocus, isTrue);
        expect(tester.testTextInput.isVisible, isTrue);
        await touch.up();
        await tester.pumpAndSettle();
        harness.expectCompleted(tester, 'Follow @Camera move');
        expect(harness.changes, ['Follow @Ca', 'Follow @Camera move']);
      },
      variant: TargetPlatformVariant({platform}),
    );
  }

  for (final platform in [TargetPlatform.macOS, TargetPlatform.windows]) {
    testWidgets(
      'mouse suggestion completes reference on ${platform.name}',
      (tester) async {
        final harness = _EditorHarness();
        await harness.mount(tester, platform: platform);
        await harness.input(tester, 'Follow @He');
        final option = find.text('@Hero portrait');
        expect(option.hitTestable(), findsOneWidget);
        final mouse = await tester.startGesture(
          tester.getCenter(option),
          kind: PointerDeviceKind.mouse,
        );
        await tester.pump(const Duration(milliseconds: 100));
        expect(harness.editor(tester).focusNode.hasFocus, isTrue);
        await mouse.up();
        await tester.pumpAndSettle();
        harness.expectCompleted(tester, 'Follow @Hero portrait');
        expect(harness.changes, ['Follow @He', 'Follow @Hero portrait']);
      },
      variant: TargetPlatformVariant({platform}),
    );
  }

  for (final key in [
    LogicalKeyboardKey.enter,
    LogicalKeyboardKey.numpadEnter,
  ]) {
    for (final screenplay in [false, true]) {
      testWidgets(
        '${key.keyLabel} accepts first suggestion without arrows, screenplay=$screenplay',
        (tester) async {
          final harness = _EditorHarness();
          await harness.mount(
            tester,
            platform: TargetPlatform.macOS,
            screenplay: screenplay,
          );
          await harness.input(tester, 'Follow @');
          expect(find.text('@Hero portrait'), findsOneWidget);
          await tester.sendKeyEvent(key);
          await tester.pumpAndSettle();
          harness.expectCompleted(tester, 'Follow @Hero portrait');
          expect(harness.changes, ['Follow @', 'Follow @Hero portrait']);
        },
        variant: TargetPlatformVariant({TargetPlatform.macOS}),
      );
    }
  }

  testWidgets(
    'touch completion preserves text after the caret',
    (tester) async {
      final harness = _EditorHarness();
      await harness.mount(tester);
      await harness.input(tester, 'Follow @Ca through the door.', caret: 10);
      await tester.tap(find.text('@Camera move'));
      await tester.pumpAndSettle();
      harness.expectCompleted(
        tester,
        'Follow @Camera move through the door.',
        caret: 19,
      );
    },
    variant: TargetPlatformVariant({TargetPlatform.iOS}),
  );

  testWidgets(
    'Enter accepts the arrow-selected reference',
    (tester) async {
      final harness = _EditorHarness();
      await harness.mount(tester, platform: TargetPlatform.windows);
      await harness.input(tester, 'Follow @');
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();
      harness.expectCompleted(tester, 'Follow @Camera move');
    },
    variant: TargetPlatformVariant({TargetPlatform.windows}),
  );

  for (final screenplay in [false, true]) {
    testWidgets(
      'iOS software Return completes a visible reference, screenplay=$screenplay',
      (tester) async {
        final harness = _EditorHarness();
        await harness.mount(tester, screenplay: screenplay);
        await harness.input(tester, 'Follow @Ca');
        // Multiline iOS keyboards deliver Return as a text edit, not a key
        // event. The subsequent action must not add a newline or lose focus.
        await harness.input(tester, 'Follow @Ca\n');
        await tester.testTextInput.receiveAction(TextInputAction.newline);
        await tester.pumpAndSettle();
        harness.expectCompleted(tester, 'Follow @Camera move');
        expect(harness.changes, ['Follow @Ca', 'Follow @Camera move']);
      },
      variant: TargetPlatformVariant({TargetPlatform.iOS}),
    );
  }

  testWidgets(
    'Shift Return keeps an intentional newline with an open menu',
    (tester) async {
      final harness = _EditorHarness();
      await harness.mount(tester, platform: TargetPlatform.macOS);
      await harness.input(tester, 'Follow @Ca');
      await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await harness.input(tester, 'Follow @Ca\n');
      await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
      await tester.pumpAndSettle();
      harness.expectCompleted(tester, 'Follow @Ca\n');
    },
    variant: TargetPlatformVariant({TargetPlatform.macOS}),
  );

  testWidgets(
    'pasting several lines does not trigger reference completion',
    (tester) async {
      final harness = _EditorHarness();
      await harness.mount(tester);
      await harness.input(tester, 'Follow @Ca');
      await harness.input(tester, 'Follow @Ca\nThe next scene begins.');
      harness.expectCompleted(tester, 'Follow @Ca\nThe next scene begins.');
    },
    variant: TargetPlatformVariant({TargetPlatform.iOS}),
  );

  testWidgets(
    'same reference can be selected again while preserving tags',
    (tester) async {
      final harness = _EditorHarness();
      await harness.mount(tester);
      await harness.input(tester, 'Follow @Ca');
      await tester.tap(find.text('@Camera move'));
      await tester.pumpAndSettle();
      harness.expectCompleted(tester, 'Follow @Camera move');
      await harness.input(tester, 'Follow @Camera move then repeat @Ca');
      await tester.tap(find.text('@Camera move'));
      await tester.pumpAndSettle();
      harness.expectCompleted(
        tester,
        'Follow @Camera move then repeat @Camera move',
      );
    },
    variant: TargetPlatformVariant({TargetPlatform.iOS}),
  );

  testWidgets(
    'Return preserves newlines when no suggestion is available',
    (tester) async {
      final harness = _EditorHarness();
      await harness.mount(tester);
      await harness.input(tester, 'Follow @unknown');
      await harness.input(tester, 'Follow @unknown\n');
      harness.expectCompleted(tester, 'Follow @unknown\n');
    },
    variant: TargetPlatformVariant({TargetPlatform.iOS}),
  );

  testWidgets(
    'composition stays intact and does not accept a reference',
    (tester) async {
      final harness = _EditorHarness();
      await harness.mount(tester);
      await harness.input(
        tester,
        'Follow @Ca',
        composing: const TextRange(start: 8, end: 10),
      );
      expect(
        find.byKey(const ValueKey('prompt-reference-suggestions')),
        findsNothing,
      );
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pump();
      expect(harness.prompt, 'Follow @Ca');
      expect(
        harness.editor(tester).controller.value.composing,
        const TextRange(start: 8, end: 10),
      );
      await harness.input(tester, 'Follow @Ca');
      await tester.tap(find.text('@Camera move'));
      await tester.pumpAndSettle();
      harness.expectCompleted(tester, 'Follow @Camera move');
    },
    variant: TargetPlatformVariant({TargetPlatform.iOS}),
  );

  testWidgets(
    'Escape leaves reference text editable without completion',
    (tester) async {
      final harness = _EditorHarness();
      await harness.mount(tester, platform: TargetPlatform.macOS);
      await harness.input(tester, 'Follow @Ca');
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('prompt-reference-suggestions')),
        findsNothing,
      );
      await harness.input(tester, 'Follow @Ca\n');
      harness.expectCompleted(tester, 'Follow @Ca\n');
    },
    variant: TargetPlatformVariant({TargetPlatform.macOS}),
  );

  testWidgets(
    'outside tap dismisses the menu and keyboard without changing the prompt',
    (tester) async {
      final harness = _EditorHarness();
      await harness.mount(tester);
      await harness.input(tester, 'Follow @Ca');
      expect(find.text('@Camera move'), findsOneWidget);
      await tester.tapAt(
        tester.getBottomRight(find.byType(Scaffold)) - const Offset(16, 16),
      );
      await tester.pumpAndSettle();
      expect(harness.prompt, 'Follow @Ca');
      expect(harness.changes, ['Follow @Ca']);
      expect(harness.editor(tester).focusNode.hasFocus, isFalse);
      expect(tester.testTextInput.isVisible, isFalse);
      expect(
        find.byKey(const ValueKey('prompt-reference-suggestions')),
        findsNothing,
      );
      await tester.tap(find.byType(TextFormField));
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('prompt-reference-suggestions')),
        findsNothing,
      );
      await harness.input(tester, 'Follow @Cam');
      await tester.tap(find.text('@Camera move'));
      await tester.pumpAndSettle();
      harness.expectCompleted(tester, 'Follow @Camera move');
    },
    variant: TargetPlatformVariant({TargetPlatform.iOS}),
  );

  for (final screenplay in [false, true]) {
    testWidgets(
      'manually typed reference remains highlighted, screenplay=$screenplay',
      (tester) async {
        final harness = _EditorHarness();
        await harness.mount(tester, screenplay: screenplay);
        await harness.input(tester, 'Follow @Ca');
        await harness.input(tester, 'Follow @Camera move');
        harness.expectCompleted(tester, 'Follow @Camera move');
        expect(harness.changes, ['Follow @Ca', 'Follow @Camera move']);
        final renderedText = tester.allRenderObjects
            .whereType<RenderEditable>()
            .single
            .text!;
        final highlightedText = <String>[];
        renderedText.visitChildren((span) {
          if (span is TextSpan && span.style?.backgroundColor != null) {
            highlightedText.add(span.text!);
          }
          return true;
        });
        expect(highlightedText, ['@Camera move']);
      },
      variant: TargetPlatformVariant({TargetPlatform.iOS}),
    );
  }

  testWidgets(
    'Escape closes the screenplay reference menu and preserves script Return',
    (tester) async {
      final harness = _EditorHarness();
      await harness.mount(
        tester,
        platform: TargetPlatform.macOS,
        screenplay: true,
      );
      await harness.input(tester, 'Follow @Ca');
      expect(find.text('@Camera move'), findsOneWidget);
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('prompt-reference-suggestions')),
        findsNothing,
      );
      await harness.input(tester, 'Follow @Ca\n');
      harness.expectCompleted(tester, 'Follow @Ca\n\n');
    },
    variant: TargetPlatformVariant({TargetPlatform.macOS}),
  );

  testWidgets(
    'touch and both Return paths keep a reference intact at the length limit',
    (tester) async {
      final touchHarness = _EditorHarness();
      await touchHarness.mount(tester, maxLength: 12);
      await touchHarness.input(tester, 'Follow @Ca');
      await tester.tap(find.text('@Camera move'));
      await tester.pumpAndSettle();
      touchHarness.expectCompleted(tester, 'Follow @Camera move');
      await tester.pumpWidget(const SizedBox.shrink());

      final hardwareHarness = _EditorHarness();
      await hardwareHarness.mount(tester, maxLength: 12);
      await hardwareHarness.input(tester, 'Follow @Ca');
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();
      hardwareHarness.expectCompleted(tester, 'Follow @Camera move');
      await tester.pumpWidget(const SizedBox.shrink());

      final returnHarness = _EditorHarness();
      await returnHarness.mount(tester, maxLength: 12);
      await returnHarness.input(tester, 'Follow @Ca');
      await returnHarness.input(tester, 'Follow @Ca\n');
      returnHarness.expectCompleted(tester, 'Follow @Camera move');
    },
    variant: TargetPlatformVariant({TargetPlatform.iOS}),
  );

  testWidgets(
    'ordinary typing and paste still enforce the prompt character limit',
    (tester) async {
      final harness = _EditorHarness();
      await harness.mount(tester, maxLength: 12);
      await harness.input(tester, '123456789012');
      await harness.input(tester, '1234567890123');
      harness.expectCompleted(tester, '123456789012');
      await harness.input(tester, 'short');
      await harness.input(tester, 'A longer pasted paragraph');
      harness.expectCompleted(tester, 'A longer pas');
      await harness.input(tester, '');
      await harness.input(tester, '🎥' * 13);
      harness.expectCompleted(tester, '🎥' * 12);
    },
    variant: TargetPlatformVariant({TargetPlatform.iOS}),
  );
}
