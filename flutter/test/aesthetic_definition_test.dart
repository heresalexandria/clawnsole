import 'package:clawnsole/app/app_controller.dart';
import 'package:clawnsole/app/app_theme.dart';
import 'package:clawnsole/core/composer_tabs.dart';
import 'package:clawnsole/core/gateway.dart';
import 'package:clawnsole/core/models.dart';
import 'package:clawnsole/ui/create_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// The Aesthetic Definition accordion: reading the chosen aesthetic's own
/// words in the composer, editing them into a Custom definition, and the
/// three ways out of Custom (save as new, update the original, revert).
void main() {
  testWidgets('no aesthetic, no accordion; choosing one opens the door', (
    tester,
  ) async {
    final controller = _controller();
    addTearDown(controller.dispose);
    await _pumpCreate(tester, controller);

    expect(
      find.byKey(const ValueKey('aesthetic-accordion-toggle')),
      findsNothing,
    );

    final id = controller.saveAestheticReference(
      title: 'Golden hour',
      text: 'Warm amber light, long shadows.',
      icon: 'sun',
      color: 0xffaf853c,
    );
    controller.selectAestheticReference(id);
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('aesthetic-accordion-toggle')), findsOne);
    expect(_summary(tester), 'Golden hour');
    await _expand(tester);
    expect(_field(tester).text, 'Warm amber light, long shadows.');
  });

  testWidgets('editing the definition makes the draft Custom', (tester) async {
    final controller = _controller();
    addTearDown(controller.dispose);
    controller.selectAestheticReference(_golden(controller));
    await _pumpCreate(tester, controller);
    controller.updateForm((form) => form.prompt = 'A sloth reads.');
    await tester.pumpAndSettle();
    await _expand(tester);

    await tester.enterText(
      find.byKey(const ValueKey('aesthetic-definition-field')),
      'Cold blue moonlight.',
    );
    // Keystrokes never rebuild the studio; the label settles with the rest.
    await tester.pump(const Duration(milliseconds: 400));

    expect(controller.form.aestheticCustomText, 'Cold blue moonlight.');
    expect(controller.hasCustomAestheticText, isTrue);
    expect(
      controller.generationPrompt,
      'A sloth reads.\n\nCold blue moonlight.',
    );
    expect(
      tester
          .widget<Text>(find.byKey(const ValueKey('prompt-aesthetic-label')))
          .data,
      'Custom',
    );
    expect(_summary(tester), 'Custom');
    // The saved aesthetic is untouched until it is asked for.
    expect(
      controller.aestheticReferences.single.text,
      'Warm amber light, long shadows.',
    );
  });

  testWidgets('Save as new files the custom definition and selects it', (
    tester,
  ) async {
    final controller = _controller();
    addTearDown(controller.dispose);
    controller.selectAestheticReference(_golden(controller));
    await _pumpCreate(tester, controller);
    await _expand(tester);
    await tester.enterText(
      find.byKey(const ValueKey('aesthetic-definition-field')),
      'Cold blue moonlight.',
    );
    await tester.pumpAndSettle();

    await _tap(tester, const ValueKey('aesthetic-save-as-new'));
    await tester.enterText(
      find.byKey(const ValueKey('aesthetic-title')),
      'Moonlit',
    );
    await _tap(tester, const ValueKey('aesthetic-save'));

    expect(controller.aestheticReferences.length, 2);
    final saved = controller.aestheticReferences.firstWhere(
      (item) => item.title == 'Moonlit',
    );
    expect(saved.text, 'Cold blue moonlight.');
    expect(controller.selectedAestheticReference?.id, saved.id);
    expect(controller.hasCustomAestheticText, isFalse);
    expect(_summary(tester), 'Moonlit');
  });

  testWidgets('Update writes the edit back onto the original aesthetic', (
    tester,
  ) async {
    final controller = _controller();
    addTearDown(controller.dispose);
    final id = _golden(controller);
    controller.selectAestheticReference(id);
    await _pumpCreate(tester, controller);
    await _expand(tester);
    await tester.enterText(
      find.byKey(const ValueKey('aesthetic-definition-field')),
      'Warmer amber light.',
    );
    await tester.pumpAndSettle();

    await _tap(tester, const ValueKey('aesthetic-update-base'));
    await _tap(tester, const ValueKey('aesthetic-update-confirm'));

    expect(controller.aestheticReferences.single.id, id);
    expect(controller.aestheticReferences.single.text, 'Warmer amber light.');
    expect(controller.aestheticReferences.single.title, 'Golden hour');
    expect(controller.hasCustomAestheticText, isFalse);
    expect(controller.effectiveAestheticText, 'Warmer amber light.');
  });

  testWidgets('Revert puts the saved definition back in the field', (
    tester,
  ) async {
    final controller = _controller();
    addTearDown(controller.dispose);
    controller.selectAestheticReference(_golden(controller));
    await _pumpCreate(tester, controller);
    await _expand(tester);
    await tester.enterText(
      find.byKey(const ValueKey('aesthetic-definition-field')),
      'Cold blue moonlight.',
    );
    await tester.pumpAndSettle();
    expect(controller.hasCustomAestheticText, isTrue);

    await _tap(tester, const ValueKey('aesthetic-revert'));

    expect(controller.hasCustomAestheticText, isFalse);
    expect(_field(tester).text, 'Warm amber light, long shadows.');
    expect(find.byKey(const ValueKey('aesthetic-revert')), findsNothing);
  });

  test('a custom definition is what gets sent, and what makes a tab busy', () {
    final controller = _controller();
    addTearDown(controller.dispose);
    controller.selectAestheticReference(_golden(controller));
    controller.updateForm((form) => form.prompt = 'A sloth reads.');

    controller.updateAestheticCustomText('Cold blue moonlight.');

    expect(controller.hasCustomAestheticText, isTrue);
    expect(
      controller.generationPrompt,
      'A sloth reads.\n\nCold blue moonlight.',
    );
    expect(controller.activeComposerTab.isBlank, isFalse);
    // Typing the saved words back is not an edit.
    controller.updateAestheticCustomText('Warm amber light, long shadows.');
    expect(controller.hasCustomAestheticText, isFalse);
  });

  test('choosing another aesthetic replaces the custom definition', () {
    final controller = _controller();
    addTearDown(controller.dispose);
    controller.selectAestheticReference(_golden(controller));
    controller.updateAestheticCustomText('Cold blue moonlight.');
    final other = controller.saveAestheticReference(
      title: 'Noir',
      text: 'Hard key light, deep shadow.',
      icon: 'moon',
      color: 0xff3689bb,
    );

    controller.selectAestheticReference(other);

    expect(controller.hasCustomAestheticText, isFalse);
    expect(controller.effectiveAestheticText, 'Hard key light, deep shadow.');

    controller.updateAestheticCustomText('Something else entirely.');
    controller.selectAestheticReference(null);
    expect(controller.hasCustomAestheticText, isFalse);
    expect(controller.effectiveAestheticText, isNull);
    expect(controller.hasAestheticDefinition, isFalse);
  });

  test('a custom definition survives a tab switch and a relaunch', () async {
    final gateway = _TabsGateway();
    final controller = AppController(gateway: gateway);
    await controller.initialize();
    await _settle();
    addTearDown(controller.dispose);
    final id = _golden(controller);
    controller
      ..selectAestheticReference(id)
      ..updateForm((form) => form.prompt = 'A sloth reads.')
      ..updateAestheticCustomText('Cold blue moonlight.');
    final first = controller.activeComposerTabId;
    controller.addComposerTab();
    expect(controller.hasCustomAestheticText, isFalse);
    controller.activateComposerTab(first);
    expect(controller.form.aestheticCustomText, 'Cold blue moonlight.');
    await _settle();

    final reopened = AppController(gateway: gateway);
    await reopened.initialize();
    await _settle();
    addTearDown(reopened.dispose);

    expect(reopened.form.aestheticCustomText, 'Cold blue moonlight.');
    expect(reopened.selectedAestheticReference?.id, id);
    expect(reopened.hasCustomAestheticText, isTrue);
    expect(reopened.generationPrompt, 'A sloth reads.\n\nCold blue moonlight.');
  });
}

String? _golden(AppController controller) => controller.saveAestheticReference(
  title: 'Golden hour',
  text: 'Warm amber light, long shadows.',
  icon: 'sun',
  color: 0xffaf853c,
);

AppController _controller() => AppController(gateway: _DefinitionGateway())
  ..selectedProviderId = 'artcraft'
  ..selectedModelId = 'seedance_2p5'
  ..loading = false
  ..snapshot = const LocalSnapshot(
    generations: [],
    preferences: AppPreferences(),
    hasApiKey: false,
    storage: StorageStats(path: 'memory', bytes: 0, records: 0),
  );

Future<void> _pumpCreate(WidgetTester tester, AppController controller) async {
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

Future<void> _expand(WidgetTester tester) =>
    _tap(tester, const ValueKey('aesthetic-accordion-toggle'));

Future<void> _tap(WidgetTester tester, Key key) async {
  final target = find.byKey(key);
  await tester.ensureVisible(target);
  await tester.pumpAndSettle();
  await tester.tap(target);
  await tester.pumpAndSettle();
}

TextEditingController _field(WidgetTester tester) => tester
    .widget<TextField>(find.byKey(const ValueKey('aesthetic-definition-field')))
    .controller!;

/// The status word on the collapsed accordion header.
String _summary(WidgetTester tester) {
  final texts = tester.widgetList<Text>(
    find.descendant(
      of: find.byKey(const ValueKey('aesthetic-accordion-toggle')),
      matching: find.byType(Text),
    ),
  );
  return texts.last.data ?? '';
}

Future<void> _settle() =>
    Future<void>.delayed(const Duration(milliseconds: 10));

class _DefinitionGateway implements AppGateway {
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

/// The same gateway plus a device-local workspace file, so a draft can be
/// written and read back by a second studio.
class _TabsGateway extends _DefinitionGateway implements ComposerTabsGateway {
  ComposerTabsState? stored;

  @override
  Future<LocalSnapshot> load() async => const LocalSnapshot(
    generations: [],
    preferences: AppPreferences(),
    hasApiKey: false,
    storage: StorageStats(path: 'memory', bytes: 0, records: 0),
  );

  @override
  Future<ComposerTabsState?> loadComposerTabs() async => stored;

  @override
  Future<void> saveComposerTabs(
    ComposerTabsState state, {
    bool publishNow = false,
  }) async {
    stored = mergeComposerWorkspaces(state, stored);
  }

  @override
  Future<void> publishComposerTabs() async {}
}
