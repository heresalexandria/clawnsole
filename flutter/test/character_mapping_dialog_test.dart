import 'package:clawnsole/app/app_controller.dart';
import 'package:clawnsole/core/gateway.dart';
import 'package:clawnsole/core/models.dart';
import 'package:clawnsole/ui/characters_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

SavedReference _reference(String name, {String? characterName}) =>
    SavedReference(
      id: name,
      name: name,
      characterName: characterName,
      kind: MediaReferenceKind.image,
      asset: AssetReference(
        kind: 'remote',
        value: 'https://example.invalid/$name',
        label: name,
      ),
      createdAt: DateTime.utc(2026),
      updatedAt: DateTime.utc(2026),
    );

class _MappingGateway implements AppGateway {
  _MappingGateway(this.references);
  final List<SavedReference> references;

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
        savedReferences: references,
      );

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

AppController _controller({
  String prompt = '',
  bool screenplayMode = true,
  required List<SavedReference> references,
}) => AppController(gateway: _MappingGateway(references))
  ..selectedProviderId = 'artcraft'
  ..selectedModelId = 'seedance_2p5'
  ..snapshot = LocalSnapshot(
    generations: const [],
    preferences: const AppPreferences(),
    hasApiKey: false,
    storage: const StorageStats(path: 'memory', bytes: 0, records: 0),
    savedReferences: references,
  )
  ..form.prompt = prompt
  ..form.screenplayMode = screenplayMode;

Future<void> _openDialog(WidgetTester tester, AppController controller) async {
  await tester.binding.setSurfaceSize(const Size(360, 900));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  addTearDown(controller.dispose);
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: Builder(
          builder: (context) => TextButton(
            onPressed: () => showCharactersDialog(context, controller),
            child: const Text('Open characters'),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('Open characters'));
  await tester.pumpAndSettle();
}

Future<void> _addCharacter(WidgetTester tester, String name) async {
  await tester.tap(find.text('Add character'));
  await tester.pumpAndSettle();
  await _typeName(tester, name);
}

Future<void> _typeName(WidgetTester tester, String name) async {
  await tester.enterText(
    find.byKey(const ValueKey('mapping-character-name')),
    name,
  );
  await tester.pump();
}

Finder _referenceTile(String name) =>
    find.widgetWithText(CheckboxListTile, '@$name');

bool _selected(WidgetTester tester, String name) =>
    tester.widget<CheckboxListTile>(_referenceTile(name)).value!;

Future<void> _toggle(WidgetTester tester, String name) async {
  final tile = _referenceTile(name);
  await tester.ensureVisible(tile);
  await tester.tap(tile);
  await tester.pump();
}

Future<void> _save(WidgetTester tester) async {
  await tester.tap(find.byKey(const ValueKey('save-character-mapping')));
  await tester.pumpAndSettle();
  expect(find.byKey(const ValueKey('save-character-mapping')), findsNothing);
}

void main() {
  for (final scenario in [
    (label: 'blank screenplay', prompt: '', screenplay: true),
    (
      label: 'action-only screenplay',
      prompt: 'A stranger crosses the empty plaza.',
      screenplay: true,
    ),
    (label: 'blank plain direction', prompt: '', screenplay: false),
  ]) {
    testWidgets('maps a new name in a ${scenario.label} without dialogue', (
      tester,
    ) async {
      final controller = _controller(
        prompt: scenario.prompt,
        screenplayMode: scenario.screenplay,
        references: [_reference('portrait.png')],
      );
      await _openDialog(tester, controller);
      await _addCharacter(tester, 'HERO');
      expect(_selected(tester, 'portrait.png'), isFalse);
      await _toggle(tester, 'portrait.png');
      expect(_selected(tester, 'portrait.png'), isTrue);
      await _save(tester);
      expect(controller.characterMappingReferences('HERO'), ['portrait.png']);
      expect(
        controller.form.references.single.savedReferenceId,
        'portrait.png',
      );
      expect(controller.form.prompt, contains('HERO: @portrait.png'));
      await tester.tap(find.widgetWithText(ListTile, 'HERO'));
      await tester.pumpAndSettle();
      expect(_selected(tester, 'portrait.png'), isTrue);
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });
  }

  for (final reference in [
    _reference('portrait.png', characterName: 'HERO'),
    _reference('Hero.png'),
  ]) {
    testWidgets('typing a new name preselects matching ${reference.name}', (
      tester,
    ) async {
      final controller = _controller(
        references: [reference, _reference('other.png')],
      );
      await _openDialog(tester, controller);
      await _addCharacter(tester, ' hero ');
      expect(_selected(tester, reference.name), isTrue);
      expect(_selected(tester, 'other.png'), isFalse);
      await _save(tester);
      expect(controller.characterMappingReferences('HERO'), [reference.name]);
      expect(controller.form.references.single.savedReferenceId, reference.id);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('manual choice survives name edits, reopen and later dialogue', (
    tester,
  ) async {
    final controller = _controller(
      references: [_reference('Hero.png'), _reference('other.png')],
    );
    await _openDialog(tester, controller);
    await _addCharacter(tester, 'HERO');
    expect(_selected(tester, 'Hero.png'), isTrue);
    await _toggle(tester, 'Hero.png');
    await _toggle(tester, 'other.png');
    await _typeName(tester, 'HERO ALIAS');
    await _typeName(tester, 'HERO');
    expect(_selected(tester, 'Hero.png'), isFalse);
    expect(_selected(tester, 'other.png'), isTrue);
    controller.updateForm((form) => form.prompt = 'The plaza is empty.');
    await tester.pump();
    expect(_selected(tester, 'Hero.png'), isFalse);
    expect(_selected(tester, 'other.png'), isTrue);
    await _save(tester);
    controller.updateForm(
      (form) => form.prompt = '        HERO\n    Hello.\n\n${form.prompt}',
    );
    expect(controller.characterMappingReferences('HERO'), ['other.png']);
    await tester.tap(find.widgetWithText(ListTile, 'HERO'));
    await tester.pumpAndSettle();
    expect(_selected(tester, 'Hero.png'), isFalse);
    expect(_selected(tester, 'other.png'), isTrue);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'Remove all remains empty while editing and after later dialogue',
    (tester) async {
      final controller = _controller(references: [_reference('Hero.png')]);
      await _openDialog(tester, controller);
      await _addCharacter(tester, 'HERO');
      expect(_selected(tester, 'Hero.png'), isTrue);
      await tester.tap(find.text('Remove all'));
      await tester.pump();
      await _typeName(tester, 'HERO ALIAS');
      await _typeName(tester, 'HERO');
      expect(_selected(tester, 'Hero.png'), isFalse);
      await _save(tester);
      expect(controller.characterMappingReferences('HERO'), isEmpty);
      controller.updateForm((form) => form.prompt = '        HERO\n    Hello.');
      await tester.tap(find.widgetWithText(ListTile, 'HERO'));
      await tester.pumpAndSettle();
      expect(_selected(tester, 'Hero.png'), isFalse);
      expect(controller.form.references, isEmpty);
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('a character added before writing survives other form edits', (
    tester,
  ) async {
    final controller = _controller(references: [_reference('portrait.png')]);
    await _openDialog(tester, controller);
    await _addCharacter(tester, 'EXTRA');
    await _save(tester);
    expect(controller.form.prompt, isEmpty);
    expect(find.widgetWithText(ListTile, 'EXTRA'), findsOneWidget);
    controller.updateForm((form) => form.generateAudio = false);
    await tester.pump();
    expect(find.widgetWithText(ListTile, 'EXTRA'), findsOneWidget);
    await tester.tap(find.widgetWithText(ListTile, 'EXTRA'));
    await tester.pumpAndSettle();
    await _toggle(tester, 'portrait.png');
    await _save(tester);
    expect(controller.characterMappingReferences('EXTRA'), ['portrait.png']);
    expect(controller.form.prompt, contains('EXTRA: @portrait.png'));
    expect(tester.takeException(), isNull);
  });

  for (final script in [
    'HERO crosses the plaza.',
    '        HERO\n    Hello.',
  ]) {
    testWidgets('opening a script name shows matching reference: $script', (
      tester,
    ) async {
      final controller = _controller(
        prompt: script,
        references: [_reference('Hero.png')],
      );
      await _openDialog(tester, controller);
      expect(controller.form.references.single.savedReferenceId, 'Hero.png');
      expect(controller.form.prompt, contains('HERO: @Hero.png'));
      expect(find.widgetWithText(ListTile, 'HERO'), findsOneWidget);
      await tester.tap(find.widgetWithText(ListTile, 'HERO'));
      await tester.pumpAndSettle();
      expect(_selected(tester, 'Hero.png'), isTrue);
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });
  }
}
