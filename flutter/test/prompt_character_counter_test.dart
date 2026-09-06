import 'package:clawnsole/app/app_controller.dart';
import 'package:clawnsole/app/app_theme.dart';
import 'package:clawnsole/core/gateway.dart';
import 'package:clawnsole/core/models.dart';
import 'package:clawnsole/ui/create_screen.dart';
import 'package:clawnsole/ui/prompt_character_counter.dart';
import 'package:clawnsole/ui/reference_prompt_field.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Finder get _progress => find.byKey(const ValueKey('prompt-character-progress'));

Future<void> _pumpCounter(
  WidgetTester tester, {
  required int used,
  int limit = 1000,
  Brightness brightness = Brightness.light,
  bool isProviderLimit = true,
  bool compact = false,
}) => tester.pumpWidget(
  MaterialApp(
    theme: buildClawnsoleTheme(brightness),
    home: Scaffold(
      body: Center(
        child: PromptCharacterCounter(
          used: used,
          limit: limit,
          modelLabel: 'Test model',
          isProviderLimit: isProviderLimit,
          compact: compact,
        ),
      ),
    ),
  ),
);

Color _progressColor(WidgetTester tester) => tester
    .widget<ColoredBox>(
      find.descendant(of: _progress, matching: find.byType(ColoredBox)),
    )
    .color;

void main() {
  for (final brightness in Brightness.values) {
    testWidgets('budget fills and warns at 80 and 95 percent in $brightness', (
      tester,
    ) async {
      await _pumpCounter(tester, used: 0, brightness: brightness);
      expect(find.text('0 / 1000'), findsOneWidget);
      expect(tester.getSize(_progress).width, 0);
      expect(tester.getSize(_progress).height, 3);
      final green = _progressColor(tester);

      await _pumpCounter(tester, used: 799, brightness: brightness);
      expect(find.text('799 / 1000'), findsOneWidget);
      expect(tester.widget<FractionallySizedBox>(_progress).widthFactor, .799);
      expect(_progressColor(tester), green);

      await _pumpCounter(tester, used: 800, brightness: brightness);
      final orange = _progressColor(tester);
      expect(orange, isNot(green));

      await _pumpCounter(tester, used: 949, brightness: brightness);
      expect(_progressColor(tester), orange);

      await _pumpCounter(tester, used: 950, brightness: brightness);
      final red = _progressColor(tester);
      expect(red, isNot(orange));
      expect(red, Theme.of(tester.element(_progress)).colorScheme.error);

      await _pumpCounter(tester, used: 1000, brightness: brightness);
      expect(find.text('1000 / 1000'), findsOneWidget);
      expect(tester.widget<FractionallySizedBox>(_progress).widthFactor, 1);
      expect(_progressColor(tester), red);

      // Added direction or a restored draft can exceed a newly selected cap.
      await _pumpCounter(tester, used: 1007, brightness: brightness);
      expect(find.text('1007 / 1000'), findsOneWidget);
      expect(tester.widget<FractionallySizedBox>(_progress).widthFactor, 1);
      expect(
        tester.widget<Tooltip>(find.byType(Tooltip)).message,
        contains('7 characters over the limit'),
      );
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('readout announces usage and remaining allowance once', (
    tester,
  ) async {
    final handle = tester.ensureSemantics();
    await _pumpCounter(tester, used: 800);
    final semantics = tester
        .getSemantics(find.bySemanticsLabel('Prompt character budget'))
        .getSemanticsData();
    expect(semantics.label, 'Prompt character budget');
    expect(
      semantics.value,
      '800 of 1000 characters used; 200 characters remaining',
    );
    expect(semantics.hint, 'Test model accepts up to 1000 characters');
    expect(find.bySemanticsLabel('800 / 1000'), findsNothing);
    handle.dispose();
  });

  testWidgets('unpublished provider caps identify the actual editor limit', (
    tester,
  ) async {
    await _pumpCounter(tester, used: 42, limit: 50000, isProviderLimit: false);
    expect(find.text('42 / 50000'), findsOneWidget);
    final tooltip = tester.widget<Tooltip>(find.byType(Tooltip));
    expect(tooltip.message, contains('49958 characters remaining'));
    expect(
      tooltip.message,
      contains(
        '50000-character editor limit; Test model has not published a limit',
      ),
    );
  });

  testWidgets('the compact readout abbreviates round limits and keeps the '
      'exact figures for the tooltip and screen reader', (tester) async {
    expect(PromptCharacterCounter.shortLimit(50000), '50k');
    expect(PromptCharacterCounter.shortLimit(10000), '10k');
    expect(PromptCharacterCounter.shortLimit(4096), '4096');
    expect(PromptCharacterCounter.shortLimit(9000), '9000');

    final handle = tester.ensureSemantics();
    await _pumpCounter(tester, used: 42, limit: 50000, compact: true);
    expect(find.text('42 / 50k'), findsOneWidget);
    expect(find.text('42 / 50000'), findsNothing);
    expect(
      tester.widget<Tooltip>(find.byType(Tooltip)).message,
      contains('42 of 50000 characters used'),
    );
    expect(
      tester
          .getSemantics(find.bySemanticsLabel('Prompt character budget'))
          .getSemanticsData()
          .value,
      '42 of 50000 characters used; 49958 characters remaining',
    );
    // The compact readout gives up part of its width for the row beside it.
    final compactWidth = tester
        .getSize(find.byKey(const ValueKey('prompt-character-limit')))
        .width;
    await _pumpCounter(tester, used: 42, limit: 50000);
    expect(find.text('42 / 50000'), findsOneWidget);
    expect(
      tester
          .getSize(find.byKey(const ValueKey('prompt-character-limit')))
          .width,
      greaterThan(compactWidth),
    );
    handle.dispose();
  });

  testWidgets(
    'readout fits a narrow scaled toolbar without losing its budget',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: MediaQuery(
              data: const MediaQueryData(textScaler: TextScaler.linear(2)),
              child: const Center(
                child: SizedBox(
                  width: 72,
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    child: PromptCharacterCounter(
                      used: 49999,
                      limit: 50000,
                      modelLabel: 'Test model',
                      isProviderLimit: false,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      expect(find.text('49999 / 50000'), findsOneWidget);
      expect(
        tester
            .getRect(find.byKey(const ValueKey('prompt-character-limit')))
            .width,
        lessThanOrEqualTo(72),
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'inline and fullscreen counters include added aesthetic direction',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(390, 844));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final controller = AppController(gateway: _CounterGateway())
        ..selectedProviderId = 'runway'
        ..selectedModelId = 'gen4.5';
      addTearDown(controller.dispose);
      controller.form.prompt = 'A bird';
      controller.saveAestheticReference(
        id: 'style',
        title: 'Light',
        text: 'Warm light',
        icon: 'sparkles',
        color: 0xffaf853c,
      );
      controller.selectAestheticReference('style');
      await tester.pumpWidget(
        MaterialApp(
          theme: buildClawnsoleTheme(Brightness.light),
          home: Scaffold(body: CreateScreen(controller: controller)),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('18 / 1000'), findsOneWidget);
      expect(
        tester
            .widget<ReferencePromptField>(find.byType(ReferencePromptField))
            .maxLength,
        1000,
      );

      await tester.tap(find.byKey(const ValueKey('prompt-fullscreen-button')));
      await tester.pumpAndSettle();
      final fullscreen = find.byKey(const ValueKey('prompt-fullscreen-editor'));
      expect(
        find.descendant(of: fullscreen, matching: find.text('18 / 1000')),
        findsOneWidget,
      );
      final editor = find.descendant(
        of: fullscreen,
        matching: find.byType(ReferencePromptField),
      );
      expect(tester.widget<ReferencePromptField>(editor).maxLength, 1000);
      await tester.enterText(editor, 'A blue bird');
      await tester.pump();
      expect(
        find.descendant(of: fullscreen, matching: find.text('23 / 1000')),
        findsOneWidget,
      );

      await tester.tap(
        find.byKey(const ValueKey('prompt-fullscreen-minimize')),
      );
      await tester.pumpAndSettle();
      expect(find.text('23 / 1000'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('switching models updates both the displayed and enforced cap', (
    tester,
  ) async {
    final controller = AppController(gateway: _CounterGateway())
      ..selectedProviderId = 'runway'
      ..selectedModelId = 'gen4.5';
    addTearDown(controller.dispose);
    controller.form.prompt = 'A bird';
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
    expect(find.text('6 / 1000'), findsOneWidget);

    await controller.selectProviderModel('ltx', 'ltx-2-3-fast');
    await tester.pumpAndSettle();
    expect(controller.selectedModel.maxPromptCharacters, isNull);
    expect(find.text('6 / 50000'), findsOneWidget);
    expect(
      tester
          .widget<ReferencePromptField>(find.byType(ReferencePromptField))
          .maxLength,
      50000,
    );

    await tester.tap(find.byKey(const ValueKey('prompt-fullscreen-button')));
    await tester.pumpAndSettle();
    final fullscreen = find.byKey(const ValueKey('prompt-fullscreen-editor'));
    expect(
      find.descendant(of: fullscreen, matching: find.text('6 / 50000')),
      findsOneWidget,
    );
    expect(
      tester
          .widget<ReferencePromptField>(
            find.descendant(
              of: fullscreen,
              matching: find.byType(ReferencePromptField),
            ),
          )
          .maxLength,
      50000,
    );
    expect(tester.takeException(), isNull);
  });
}

class _CounterGateway implements AppGateway {
  @override
  bool get usesCompanion => false;

  @override
  bool get supportsPhotoLibrarySave => false;

  @override
  String get persistenceDescription => 'Memory';

  @override
  Future<LocalSnapshot> setPreferences(AppPreferences preferences) async =>
      LocalSnapshot(
        generations: const [],
        preferences: preferences,
        hasApiKey: false,
        storage: const StorageStats(path: 'memory', bytes: 0, records: 0),
      );

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
