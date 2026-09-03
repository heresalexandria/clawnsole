import 'dart:typed_data';

import 'package:clawnsole/app/app_controller.dart';
import 'package:clawnsole/app/app_theme.dart';
import 'package:clawnsole/core/composer_tabs.dart';
import 'package:clawnsole/core/gateway.dart';
import 'package:clawnsole/core/models.dart';
import 'package:clawnsole/ui/create_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('composer tab machinery', () {
    test('opens, switches, and closes drafts without ever emptying', () async {
      final controller = await _controller();
      addTearDown(controller.dispose);

      final first = controller.activeComposerTab;
      expect(controller.composerTabs, hasLength(1));

      final second = controller.addComposerTab();
      expect(controller.composerTabs, hasLength(2));
      expect(controller.activeComposerTabId, second.id);
      // A new tab inherits the console it was opened from, nothing else.
      expect(second.providerId, first.providerId);
      expect(second.modelId, first.modelId);
      expect(second.form.prompt, isEmpty);

      controller.activateComposerTab(first.id);
      expect(controller.activeComposerTabId, first.id);
      controller.activateComposerTab('no-such-tab');
      expect(controller.activeComposerTabId, first.id);

      // Closing the tab in front moves right; there is no right neighbour of
      // the last tab, so it falls back to the left.
      final third = controller.addComposerTab();
      controller.activateComposerTab(second.id);
      controller.closeComposerTab(second.id);
      expect(controller.activeComposerTabId, third.id);
      controller.closeComposerTab(third.id);
      expect(controller.activeComposerTabId, first.id);

      // The strip never empties: the last close leaves a blank tab behind.
      controller.form.prompt = 'A sloth reaches for the last fig.';
      controller.closeComposerTab(first.id);
      expect(controller.composerTabs, hasLength(1));
      expect(controller.activeComposerTab.id, isNot(first.id));
      expect(controller.form.prompt, isEmpty);
      expect(controller.activeComposerTab.providerId, first.providerId);
    });

    test('names a tab and falls back to the direction', () async {
      final controller = await _controller();
      addTearDown(controller.dispose);
      final tab = controller.activeComposerTab;

      expect(tab.label, composerTabUntitled);
      controller.updateForm(
        (form) => form.prompt = 'The reading lamp warms the burl.',
      );
      expect(tab.label, startsWith('The reading lamp warms'));

      controller.renameComposerTab(tab.id, '  Opening shot  ');
      expect(tab.title, 'Opening shot');
      expect(tab.label, 'Opening shot');

      controller.renameComposerTab(tab.id, '   ');
      expect(tab.title, isNull);
      expect(tab.label, startsWith('The reading lamp warms'));
    });

    test('keeps each draft, provider, and model to itself', () async {
      final controller = await _controller();
      addTearDown(controller.dispose);
      final first = controller.activeComposerTab;

      controller.updateForm((form) => form.prompt = 'First draft.');
      await controller.selectProviderModel('bfl', 'flux-3-video');
      controller.setDurationSeconds(6);

      final second = controller.addComposerTab();
      expect(controller.form.prompt, isEmpty);
      controller.updateForm((form) => form.prompt = 'Second draft.');
      await controller.selectProvider('runway');
      controller.setDurationSeconds(10);

      expect(first.form.prompt, 'First draft.');
      expect(first.form.durationSeconds, 6);
      expect(first.providerId, 'bfl');
      expect(second.form.prompt, 'Second draft.');
      expect(second.providerId, 'runway');
      expect(controller.selectedProviderId, 'runway');

      controller.activateComposerTab(first.id);
      expect(controller.form.prompt, 'First draft.');
      expect(controller.selectedProviderId, 'bfl');
      expect(controller.selectedModelId, 'flux-3-video');
    });

    test('reuse fills a blank tab and opens a new one otherwise', () async {
      final item = _delivered();
      final controller = await _controller(generations: <Generation>[item]);
      addTearDown(controller.dispose);
      final first = controller.activeComposerTab;

      await controller.reuse(item);
      expect(controller.composerTabs, hasLength(1));
      expect(controller.activeComposerTabId, first.id);
      expect(controller.form.prompt, item.prompt);
      expect(first.sourceGenerationId, item.localId);

      // The draft is now somebody's work, so the next reuse lands beside it.
      await controller.reuse(item);
      expect(controller.composerTabs, hasLength(2));
      expect(controller.activeComposerTabId, isNot(first.id));
      expect(first.form.prompt, item.prompt);
      expect(controller.form.prompt, item.prompt);
      expect(controller.form.aspectRatio, '21:9');
    });

    test('opens a generation in a new tab with an overridden prompt', () async {
      final item = _delivered();
      final controller = await _controller(
        generations: <Generation>[item],
        assets: <String, Uint8List>{
          'retained/reference.png': Uint8List.fromList(<int>[7, 7, 7]),
        },
      );
      addTearDown(controller.dispose);
      final first = controller.activeComposerTab;
      controller.updateForm((form) => form.prompt = 'Untouched.');

      await controller.openGenerationInNewTab(
        item,
        prompt: 'A rewritten direction, warmer and slower.',
        rewriteSummary: 'Warmed the light and slowed the move.',
      );

      final opened = controller.activeComposerTab;
      expect(opened.id, isNot(first.id));
      expect(first.form.prompt, 'Untouched.');
      expect(opened.form.prompt, 'A rewritten direction, warmer and slower.');
      expect(opened.rewriteSummary, 'Warmed the light and slowed the move.');
      expect(opened.sourceGenerationId, item.localId);
      expect(opened.form.aspectRatio, '21:9');
      expect(opened.form.references, hasLength(1));
      expect(opened.form.references.single.label, 'A grey sloth');
      expect(controller.section, AppSection.create);
    });

    test('async media adds land in the tab they started in', () async {
      final controller = await _controller();
      addTearDown(controller.dispose);
      await controller.selectProviderModel(_referenceProvider, _referenceModel);
      final first = controller.activeComposerTab;

      final pending = controller.attachPickedReferences(
        MediaReferenceKind.image,
        <PickedAsset>[
          PickedAsset(
            name: 'lamp.png',
            bytes: Uint8List.fromList(<int>[1, 2, 3]),
            mimeType: 'image/png',
          ),
        ],
        tab: first,
      );
      // The director moves on before the retention pipeline finishes.
      final second = controller.addComposerTab();
      await pending;

      expect(first.form.references, hasLength(1));
      expect(second.form.references, isEmpty);
      expect(controller.form.references, isEmpty);
    });
  });

  group('composer tab persistence', () {
    test('writes the strip after the debounce and on a switch', () async {
      final gateway = _TabsGateway(_snapshot());
      final controller = AppController(gateway: gateway);
      addTearDown(controller.dispose);
      await controller.initialize();
      await _settle();

      controller.updateForm((form) => form.prompt = 'A slow pan over walnut.');
      controller.renameComposerTab(controller.activeComposerTabId, 'Opening');
      expect(gateway.saves, isEmpty, reason: 'typing must not write at once');

      await Future<void>.delayed(
        AppController.composerTabsSaveDebounce +
            const Duration(milliseconds: 60),
      );
      expect(gateway.saves, isNotEmpty);
      final written = gateway.saves.last;
      expect(written.tabs, hasLength(1));
      expect(written.tabs.single.prompt, 'A slow pan over walnut.');
      expect(written.tabs.single.title, 'Opening');
      expect(written.tabs.single.providerId, controller.selectedProviderId);
      expect(written.activeTabId, controller.activeComposerTabId);

      // A tab switch cannot wait for the debounce; it writes immediately.
      final before = gateway.saves.length;
      final second = controller.addComposerTab();
      await _settle();
      expect(gateway.saves.length, greaterThan(before));
      expect(gateway.saves.last.tabs, hasLength(2));
      expect(gateway.saves.last.activeTabId, second.id);
    });

    test('a gateway without tab storage keeps working', () async {
      final controller = await _controller();
      addTearDown(controller.dispose);
      controller.updateForm((form) => form.prompt = 'Nothing to write to.');
      await Future<void>.delayed(
        AppController.composerTabsSaveDebounce +
            const Duration(milliseconds: 60),
      );
      expect(controller.form.prompt, 'Nothing to write to.');
      expect(controller.composerTabs, hasLength(1));
    });
  });

  group('composer tab startup', () {
    test('reopens saved tabs, with the record overruling the film', () async {
      final item = _delivered();
      final gateway = _TabsGateway(
        _snapshot(generations: <Generation>[item]),
        assets: <String, Uint8List>{
          'retained/reference.png': Uint8List.fromList(<int>[7, 7, 7]),
        },
        stored: ComposerTabsState(
          activeTabId: 'tab-b',
          tabs: <ComposerTabRecord>[
            const ComposerTabRecord(
              id: 'tab-a',
              prompt: 'A quiet establishing shot.',
              title: 'Establishing',
            ),
            ComposerTabRecord(
              id: 'tab-b',
              prompt: 'The rewritten take.',
              providerId: item.provider,
              modelId: item.model,
              // Deliberately unlike the generation's own 21:9 / 17s.
              aspectRatio: '1:1',
              durationSeconds: 5,
              sourceGenerationId: item.localId,
              rewriteSummary: 'Slowed the move.',
            ),
          ],
        ),
      );
      final controller = AppController(gateway: gateway);
      addTearDown(controller.dispose);
      await controller.initialize();
      await _settle();

      expect(controller.composerTabs.map((tab) => tab.id), <String>[
        'tab-a',
        'tab-b',
      ]);
      expect(controller.activeComposerTabId, 'tab-b');
      expect(controller.composerTabs.first.title, 'Establishing');
      expect(controller.composerTabs.first.label, 'Establishing');

      final reopened = controller.activeComposerTab;
      expect(reopened.form.prompt, 'The rewritten take.');
      expect(reopened.rewriteSummary, 'Slowed the move.');
      // Media comes back from the film the tab was seeded from…
      expect(reopened.form.references, hasLength(1));
      expect(reopened.form.references.single.label, 'A grey sloth');
      // …while the record's own scalars win over the film's.
      expect(reopened.form.aspectRatio, '1:1');
      expect(reopened.form.durationSeconds, 5);
    });

    test('without saved tabs it carries the newest film over', () async {
      final item = _delivered();
      final gateway = _TabsGateway(_snapshot(generations: <Generation>[item]));
      final controller = AppController(gateway: gateway);
      addTearDown(controller.dispose);
      await controller.initialize();
      await _settle();

      expect(controller.composerTabs, hasLength(1));
      // Settings carry over; the direction does not, as it always has.
      expect(controller.form.prompt, isEmpty);
      expect(controller.form.aspectRatio, '21:9');
      expect(controller.activeComposerTab.sourceGenerationId, item.localId);
    });

    test('a broken tab store never stops startup', () async {
      final gateway = _TabsGateway(_snapshot(), loadThrows: true);
      final controller = AppController(gateway: gateway);
      addTearDown(controller.dispose);
      await controller.initialize();
      await _settle();

      expect(controller.loadError, isNull);
      expect(controller.composerTabs, hasLength(1));
    });
  });

  group('composer tab strip', () {
    testWidgets('adds, switches, closes, and renames from the strip', (
      tester,
    ) async {
      await tester.binding.setSurfaceSize(const Size(1400, 1400));
      addTearDown(() async {
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.binding.setSurfaceSize(null);
      });
      // Disposed at the end of the body: startup's poll timers must be gone
      // before the framework checks for pending timers.
      final controller = await _controller(settle: false);
      await tester.pumpWidget(_host(controller));
      await tester.pumpAndSettle();

      final firstId = controller.activeComposerTabId;
      expect(find.byKey(ValueKey<String>('composer-tab-$firstId')), findsOne);
      expect(find.text(composerTabUntitled), findsOne);
      // One tab alone offers no close control; the strip cannot empty.
      expect(
        find.byKey(ValueKey<String>('composer-tab-close-$firstId')),
        findsNothing,
      );

      await tester.enterText(_prompt(controller), 'First.');
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const ValueKey('composer-tab-add')));
      await tester.pumpAndSettle();
      final secondId = controller.activeComposerTabId;
      expect(secondId, isNot(firstId));
      expect(controller.composerTabs, hasLength(2));
      // The new draft opens empty, with the first still in the strip.
      expect(_promptText(tester, controller), isEmpty);
      expect(find.text('First.'), findsOne);

      await tester.enterText(_prompt(controller), 'Second.');
      await tester.pumpAndSettle();

      // Tapping a key swaps the whole composer over to that draft.
      await tester.tap(find.byKey(ValueKey<String>('composer-tab-$firstId')));
      await tester.pumpAndSettle();
      expect(controller.activeComposerTabId, firstId);
      expect(_promptText(tester, controller), 'First.');

      // Renaming replaces the derived label.
      await tester.longPress(
        find.byKey(ValueKey<String>('composer-tab-$firstId')),
      );
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('composer-tab-rename-field')),
        'Opening',
      );
      await tester.tap(find.byKey(const ValueKey('composer-tab-rename-save')));
      await tester.pumpAndSettle();
      expect(controller.composerTabs.first.title, 'Opening');
      expect(find.text('Opening'), findsOne);

      // Closing returns to the remaining draft.
      await tester.tap(
        find.byKey(ValueKey<String>('composer-tab-close-$firstId')),
      );
      await tester.pumpAndSettle();
      expect(controller.composerTabs, hasLength(1));
      expect(controller.activeComposerTabId, secondId);
      expect(_promptText(tester, controller), 'Second.');
      controller.dispose();
    });

    testWidgets('desktop runs the rail from the tabs to the plaque', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(1440, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final controller = await _controller(settle: false);
      await tester.pumpWidget(_host(controller));
      await tester.pumpAndSettle();

      // The tabs are the heading: no display headline, the tabs flush left
      // on the same row as the model plaque pinned to the far right, and the
      // composer still above the fold at the size the fold contract names.
      expect(find.text('Make it move.'), findsNothing);
      expect(find.text('VIDEO STUDIO'), findsOne);
      final add = tester.getRect(
        find.byKey(const ValueKey('composer-tab-add')),
      );
      final plaque = tester.getRect(
        find.byKey(const ValueKey('provider-plaque')),
      );
      final generate = tester.getRect(find.text('Generate video'));
      expect(add.right, lessThan(plaque.left));
      expect(add.bottom, closeTo(plaque.bottom, 1));
      expect(plaque.right, closeTo(generate.right, 40));
      expect(generate.bottom, lessThan(900));
      controller.dispose();
    });

    testWidgets('narrow layouts give the strip its own line', (tester) async {
      await tester.binding.setSurfaceSize(const Size(390, 1400));
      addTearDown(() async {
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.binding.setSurfaceSize(null);
      });
      final controller = await _controller(settle: false);
      await tester.pumpWidget(_host(controller));
      await tester.pumpAndSettle();

      expect(find.byKey(const ValueKey('composer-tab-add')), findsOne);
      await tester.tap(find.byKey(const ValueKey('composer-tab-add')));
      await tester.pumpAndSettle();
      expect(controller.composerTabs, hasLength(2));
      controller.dispose();
    });
  });
}

// ---------------------------------------------------------------------------
// Fixtures
// ---------------------------------------------------------------------------

Widget _host(AppController controller) => MaterialApp(
  theme: buildClawnsoleTheme(Brightness.light),
  home: Scaffold(
    body: AnimatedBuilder(
      animation: controller,
      builder: (context, _) => CreateScreen(controller: controller),
    ),
  ),
);

Finder _prompt(AppController controller) => find.byKey(
  ValueKey<String>(
    'generation-prompt-${controller.activeComposerTabId}-'
    '${controller.formRevision}',
  ),
);

String _promptText(WidgetTester tester, AppController controller) => tester
    .widget<EditableText>(
      find.descendant(
        of: _prompt(controller),
        matching: find.byType(EditableText),
      ),
    )
    .controller
    .text;

/// Lets the controller's background startup work finish.
Future<void> _settle() =>
    Future<void>.delayed(const Duration(milliseconds: 10));

LocalSnapshot _snapshot({
  List<Generation> generations = const <Generation>[],
}) => LocalSnapshot(
  generations: generations,
  preferences: const AppPreferences(),
  hasApiKey: false,
  storage: const StorageStats(path: 'memory', bytes: 0, records: 0),
);

/// Opens a studio whose gateway cannot store tabs at all. [settle] waits out
/// the background startup restore; widget tests pump the clock instead.
Future<AppController> _controller({
  List<Generation> generations = const <Generation>[],
  Map<String, Uint8List> assets = const <String, Uint8List>{},
  bool settle = true,
}) async {
  final controller = AppController(
    gateway: _PlainGateway(_snapshot(generations: generations), assets: assets),
  );
  await controller.initialize();
  if (settle) await _settle();
  return controller;
}

/// A provider and model that accept creative references, so a restored film
/// keeps the ones it was made with instead of setting them aside.
const String _referenceProvider = 'atlas';
const String _referenceModel = 'bytedance/seedance-2.5/reference-to-video';

Generation _delivered() {
  final now = DateTime.utc(2026, 8, 15);
  return Generation(
    localId: 'film-1',
    status: 'Ready',
    prompt: 'A sloth turns toward the reading lamp.',
    mode: VideoMode.i2v,
    provider: _referenceProvider,
    model: _referenceModel,
    config: const GenerationConfig(
      aspectRatio: '21:9',
      duration: 17,
      resolution: 'fhd',
      generateAudio: false,
      safetyTolerance: 1,
      draft: false,
      references: <MediaReferenceLabel>[
        MediaReferenceLabel(
          label: 'A grey sloth',
          kind: MediaReferenceKind.image,
          promptName: 'Sloth',
          source: AssetReference(
            kind: 'local',
            value: 'retained/reference.png',
            label: 'A grey sloth',
            contentType: 'image/png',
          ),
        ),
      ],
    ),
    resultUrl: 'https://example.com/film-1.mp4',
    createdAt: now,
    updatedAt: now,
  );
}

/// A gateway with no composer-tab storage at all, to prove the feature keeps
/// working on embedders that never gained it.
class _PlainGateway implements AppGateway {
  _PlainGateway(this.snapshot, {this.assets = const <String, Uint8List>{}});

  LocalSnapshot snapshot;
  final Map<String, Uint8List> assets;

  @override
  bool get usesCompanion => false;

  @override
  bool get supportsPhotoLibrarySave => false;

  @override
  String get persistenceDescription => 'Memory';

  @override
  Future<LocalSnapshot> load() async => snapshot;

  @override
  Future<LocalSnapshot> setPreferences(AppPreferences preferences) async {
    snapshot = snapshot.copyWith(preferences: preferences);
    return snapshot;
  }

  @override
  Future<LocalSnapshot> setApiKey(String value) async => snapshot;

  @override
  Future<double> verifyKey([String? candidate]) async => 0;

  @override
  Future<double> getCredits() async => 0;

  @override
  Future<Generation> submit(GenerationSubmission submission) async =>
      submission.record;

  @override
  Future<Generation> poll(Generation generation) async => generation;

  @override
  Future<LocalSnapshot> deleteGeneration(String localId) async => snapshot;

  @override
  Future<LocalSnapshot> clearHistory() async => snapshot;

  @override
  Future<LocalSnapshot> clearPreferences() async => snapshot;

  @override
  Future<LocalSnapshot> clearApiKey() async => snapshot;

  @override
  Future<LocalSnapshot> clearAll() async => snapshot;

  @override
  Future<Uri> assetUri(AssetReference reference) async =>
      Uri.parse(reference.value);

  @override
  Future<Uint8List> readAsset(AssetReference reference) async =>
      assets[reference.value] ?? Uint8List(0);

  @override
  Uri mediaUri(String source) => Uri.parse(source);

  @override
  Future<Uint8List> downloadMedia(String source) async => Uint8List(0);

  @override
  Future<void> saveMediaToPhotoLibrary(
    Uint8List bytes,
    String fileName,
    String contentType,
  ) async {}
}

/// The same gateway plus device-local composer-tab storage.
class _TabsGateway extends _PlainGateway implements ComposerTabsGateway {
  _TabsGateway(
    super.snapshot, {
    super.assets,
    this.stored,
    this.loadThrows = false,
  });

  ComposerTabsState? stored;
  final bool loadThrows;
  final List<ComposerTabsState> saves = <ComposerTabsState>[];

  @override
  Future<ComposerTabsState?> loadComposerTabs() async {
    if (loadThrows) throw StateError('the tab store is unreadable');
    return stored;
  }

  @override
  Future<void> saveComposerTabs(ComposerTabsState state) async {
    stored = state;
    saves.add(state);
  }
}
