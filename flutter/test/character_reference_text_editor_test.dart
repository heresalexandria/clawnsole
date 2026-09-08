import 'package:clawnsole/app/app_controller.dart';
import 'package:clawnsole/app/app_theme.dart';
import 'package:clawnsole/core/gateway.dart';
import 'package:clawnsole/core/models.dart';
import 'package:clawnsole/ui/create_screen.dart';
import 'package:clawnsole/ui/reference_prompt_field.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

const _toggleKey = ValueKey('character-reference-text-toggle');
const _fieldKey = ValueKey('character-reference-text-field');
const _resetKey = ValueKey('character-reference-text-reset');
const _prompt = 'INT. LAB - NIGHT\n\nALICE waits beside the window.';

AppController _controller() {
  final controller = AppController(gateway: _UnusedGateway())
    ..selectedProviderId = 'runway'
    ..selectedModelId = 'seedance2_5'
    ..loading = false;
  controller.form
    ..prompt = _prompt
    ..references = const [
      MediaReferenceDraft(
        id: 'portrait',
        kind: MediaReferenceKind.image,
        label: 'Portrait',
        promptName: 'Portrait',
        source: '',
      ),
    ];
  controller.form.characterMappings['ALICE'] = ['Portrait'];
  return controller;
}

Future<void> _mount(WidgetTester tester, AppController controller) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: buildClawnsoleTheme(Brightness.light),
      home: ListenableBuilder(
        listenable: controller,
        builder: (context, _) =>
            Scaffold(body: CreateScreen(controller: controller)),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> _tap(WidgetTester tester, Finder finder) async {
  await tester.ensureVisible(finder);
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

Finder _textField([Finder? scope]) => find.descendant(
  of: scope ?? find.byKey(_fieldKey),
  matching: find.byType(TextFormField),
);

String _text(WidgetTester tester, [Finder? scope]) =>
    tester.widget<TextFormField>(_textField(scope)).controller!.text;

void main() {
  testWidgets(
    'manual casting keeps the added-text editor visible and both fields intact',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(390, 1100));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final controller = _controller();
      const manual = 'ALICE: @Manual Clip\n\n$_prompt';
      controller.form.prompt = manual;
      try {
        await _mount(tester, controller);
        expect(find.byKey(_toggleKey), findsOneWidget);
        expect(find.text('Not added'), findsOneWidget);
        await _tap(tester, find.byKey(_toggleKey));
        expect(_text(tester), isEmpty);
        expect(controller.promptWithCast, manual);

        const edited = 'ALICE: @Portrait\nUse this only for her coat.  ';
        await tester.enterText(_textField(), edited);
        await tester.pumpAndSettle();
        expect(controller.form.prompt, manual);
        controller.updatePrompt('$manual\nShe opens the door.');
        await tester.pump(AppController.promptSettleDelay);
        await tester.pumpAndSettle();
        expect(_text(tester), edited);
        expect(controller.characterReferenceText, edited);
        expect(controller.form.prompt, '$manual\nShe opens the door.');

        await _tap(tester, find.byKey(_resetKey));
        expect(_text(tester), isEmpty);
        expect(controller.form.prompt, '$manual\nShe opens the door.');
        expect(controller.promptWithCast, controller.form.prompt);
        expect(find.byKey(_toggleKey), findsOneWidget);
        expect(tester.takeException(), isNull);
      } finally {
        await tester.pumpWidget(const SizedBox.shrink());
        controller.dispose();
      }
    },
  );

  for (final width in [390.0, 1200.0]) {
    testWidgets('character text is editable and resettable at width $width', (
      tester,
    ) async {
      await tester.binding.setSurfaceSize(Size(width, 1100));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final controller = _controller();
      try {
        await _mount(tester, controller);
        expect(find.byKey(_toggleKey), findsOneWidget);
        expect(find.byKey(_fieldKey), findsNothing);
        final mainField = tester
            .widget<TextFormField>(
              find.descendant(
                of: find.byType(ReferencePromptField),
                matching: find.byType(TextFormField),
              ),
            )
            .controller!;
        mainField.selection = const TextSelection.collapsed(offset: 4);
        await _tap(tester, find.byKey(_toggleKey));
        expect(_text(tester), controller.generatedCharacterReferenceText);
        expect(
          tester
              .widget<ReferencePromptField>(find.byKey(_fieldKey))
              .screenplayMode,
          isFalse,
        );

        const custom =
            'ALICE: use @Portrait for her face.\nKeep her coat blue.  ';
        await tester.enterText(_textField(), custom);
        await tester.pumpAndSettle();
        expect(_text(tester), custom);
        expect(controller.characterReferenceText, custom);
        expect(controller.form.prompt, _prompt);
        expect(controller.hasCharacterReferenceTextOverride, isTrue);
        expect(controller.promptWithCast, contains('Keep her coat blue.'));
        await tester.pump(AppController.promptSettleDelay);
        expect(mainField.text, _prompt);
        expect(mainField.selection.extentOffset, 4);

        await _tap(tester, find.byKey(_toggleKey));
        expect(find.byKey(_fieldKey), findsNothing);
        await _tap(tester, find.byKey(_toggleKey));
        expect(_text(tester), custom);

        await tester.enterText(_textField(), '');
        await tester.pumpAndSettle();
        expect(controller.characterReferenceText, isEmpty);
        expect(controller.promptWithCast, _prompt);
        expect(find.byKey(_toggleKey), findsOneWidget);
        expect(find.text('Not added'), findsOneWidget);

        await _tap(tester, find.byKey(_resetKey));
        expect(controller.hasCharacterReferenceTextOverride, isFalse);
        expect(_text(tester), controller.generatedCharacterReferenceText);
        expect(controller.form.prompt, _prompt);
        expect(tester.takeException(), isNull);
      } finally {
        await tester.pumpWidget(const SizedBox.shrink());
        controller.dispose();
      }
    });
  }

  testWidgets(
    'empty drafts stay compact and custom text remains visible without mappings',
    (tester) async {
      final controller = _controller();
      controller.form.characterMappings.clear();
      try {
        await _mount(tester, controller);
        expect(find.byKey(_toggleKey), findsNothing);
        controller.updateCharacterReferenceText(
          'Use the same person throughout.',
        );
        await tester.pump(AppController.promptSettleDelay);
        await tester.pumpAndSettle();
        await _tap(tester, find.byKey(_toggleKey));
        expect(_text(tester), 'Use the same person throughout.');
        expect(controller.form.prompt, _prompt);
      } finally {
        await tester.pumpWidget(const SizedBox.shrink());
        controller.dispose();
      }
    },
  );

  testWidgets(
    'fullscreen editing uses the same character text and keeps direction intact',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(1200, 900));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final controller = _controller();
      try {
        await _mount(tester, controller);
        await _tap(
          tester,
          find.byKey(const ValueKey('prompt-fullscreen-button')),
        );
        final fullscreen = find.byKey(
          const ValueKey('prompt-fullscreen-editor'),
        );
        final toggle = find.descendant(
          of: fullscreen,
          matching: find.byKey(_toggleKey),
        );
        await _tap(tester, toggle);
        final field = find.descendant(
          of: fullscreen,
          matching: find.byKey(_fieldKey),
        );
        await tester.enterText(
          _textField(field),
          'ALICE: @Portrait, now wearing a red coat.',
        );
        await tester.pumpAndSettle();
        expect(
          controller.characterReferenceText,
          'ALICE: @Portrait, now wearing a red coat.',
        );
        expect(controller.form.prompt, _prompt);
        expect(tester.takeException(), isNull);
      } finally {
        await tester.pumpWidget(const SizedBox.shrink());
        controller.dispose();
      }
    },
  );

  testWidgets('character text fits a 320px screen with double-size text', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1200, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final controller = _controller();
    try {
      await _mount(tester, controller);
      // Exercise the actual Create editor on its own: the surrounding legacy
      // panels have unrelated 320px/large-text overflows.
      final editor = tester.widget<Widget>(
        find.byKey(
          ValueKey(
            'character-reference-text-${controller.activeComposerTabId}',
          ),
        ),
      );
      await tester.binding.setSurfaceSize(const Size(320, 1000));
      await tester.pumpWidget(
        MaterialApp(
          theme: buildClawnsoleTheme(Brightness.light),
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(textScaler: const TextScaler.linear(2)),
            child: child!,
          ),
          home: Scaffold(
            body: SingleChildScrollView(
              child: Padding(padding: const EdgeInsets.all(16), child: editor),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await _tap(tester, find.byKey(_toggleKey));
      expect(_text(tester), controller.generatedCharacterReferenceText);
      await tester.enterText(
        _textField(),
        'ALICE: @Portrait, with a long description that wraps within this field.',
      );
      await tester.pumpAndSettle();
      await _tap(tester, find.byKey(_resetKey));
      expect(_text(tester), controller.generatedCharacterReferenceText);
      expect(tester.takeException(), isNull);
    } finally {
      await tester.pumpWidget(const SizedBox.shrink());
      controller.dispose();
    }
  });
}

class _UnusedGateway implements AppGateway {
  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw StateError('Editing character text must not access a gateway.');
}
