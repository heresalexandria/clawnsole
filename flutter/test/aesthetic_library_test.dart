import 'package:clawnsole/app/app_controller.dart';
import 'package:clawnsole/app/app_theme.dart';
import 'package:clawnsole/core/gateway.dart';
import 'package:clawnsole/core/models.dart';
import 'package:clawnsole/ui/create_screen.dart';
import 'package:clawnsole/ui/references_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

const _snapshot = LocalSnapshot(
  generations: <Generation>[],
  savedReferences: <SavedReference>[],
  preferences: AppPreferences(),
  hasApiKey: false,
  storage: StorageStats(path: 'memory', bytes: 0, records: 0),
);

class _AestheticGateway implements AppGateway {
  @override
  bool get usesCompanion => false;

  @override
  bool get supportsPhotoLibrarySave => false;

  @override
  String get persistenceDescription => 'Memory';

  @override
  Future<LocalSnapshot> load() async => _snapshot;

  @override
  Future<LocalSnapshot> setPreferences(AppPreferences preferences) async =>
      _snapshot;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

AppController _controller() => AppController(gateway: _AestheticGateway())
  ..selectedProviderId = 'runway'
  ..selectedModelId = 'gen4.5'
  ..snapshot = _snapshot;

void _seed(
  AppController controller,
  String id,
  String title, {
  String? text,
  List<String> tags = const <String>[],
  bool favorite = false,
}) => controller.saveAestheticReference(
  id: id,
  title: title,
  text: text ?? '$title direction.',
  icon: 'sparkles',
  color: 0xffaf853c,
  tags: tags,
  favorite: favorite,
);

Finder _row(String id) => find.byKey(ValueKey('aesthetic-row-$id'));

/// The tab's own scroll view. A toolbar text field owns a second (horizontal)
/// scrollable inside it, so the outer one is taken by position.
Finder get _aestheticScrollable => find
    .descendant(
      of: find.byKey(const ValueKey('aesthetic-library-scroll')),
      matching: find.byType(Scrollable),
    )
    .first;

List<String> _rowIds(WidgetTester tester) => tester
    .widgetList<Widget>(
      find.byWidgetPredicate(
        (widget) =>
            widget.key is ValueKey<String> &&
            (widget.key! as ValueKey<String>).value.startsWith(
              'aesthetic-row-',
            ),
      ),
    )
    .map(
      (widget) => (widget.key! as ValueKey<String>).value.replaceFirst(
        'aesthetic-row-',
        '',
      ),
    )
    .toList();

/// Whether [finder]'s box overlaps the surface, so an off-screen row inside a
/// laid-out (never lazy) `SingleChildScrollView` still counts as hidden.
bool _onScreen(WidgetTester tester, Finder finder) {
  if (finder.evaluate().isEmpty) return false;
  final rect = tester.getRect(finder);
  final surface = tester.view.physicalSize / tester.view.devicePixelRatio;
  return rect.bottom > 0 && rect.top < surface.height;
}

Future<void> _pumpReferences(
  WidgetTester tester,
  AppController controller, {
  Size size = const Size(1280, 900),
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MaterialApp(
      theme: buildClawnsoleTheme(Brightness.dark),
      home: Scaffold(body: ReferencesScreen(controller: controller)),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  group('aesthetic library controller', () {
    test('starred entries lead, then titles A→Z', () {
      final controller = _controller();
      addTearDown(controller.dispose);
      _seed(controller, 'b', 'Bergman');
      _seed(controller, 'a', 'anamorphic');
      _seed(controller, 'z', 'Zebra', favorite: true);
      expect(
        controller.sortedAestheticReferences.map((item) => item.id),
        <String>['z', 'a', 'b'],
      );
    });

    test('search reads titles, text, and tags', () {
      final controller = _controller();
      addTearDown(controller.dispose);
      _seed(controller, 'a', 'Golden hour', text: 'Warm amber light.');
      _seed(
        controller,
        'b',
        'Night',
        text: 'Sodium streetlamps.',
        tags: ['noir'],
      );
      _seed(controller, 'c', 'Studio', text: 'Even key light.');

      controller.setAestheticSearch('golden');
      expect(controller.filteredAestheticReferences.single.id, 'a');

      controller.setAestheticSearch('sodium');
      expect(controller.filteredAestheticReferences.single.id, 'b');

      controller.setAestheticSearch('NOIR');
      expect(controller.filteredAestheticReferences.single.id, 'b');

      controller.setAestheticSearch('light');
      expect(
        controller.filteredAestheticReferences.map((item) => item.id),
        <String>['a', 'c'],
      );
    });

    test('tag filter and starred facet counts share one search', () {
      final controller = _controller();
      addTearDown(controller.dispose);
      _seed(controller, 'a', 'Alpha', tags: ['noir'], favorite: true);
      _seed(controller, 'b', 'Beta', tags: ['noir']);
      _seed(controller, 'c', 'Gamma', tags: ['1970s']);

      expect(controller.aestheticCount(), 3);
      expect(controller.aestheticCount(favoritesOnly: true), 1);

      controller.setAestheticTag('noir');
      expect(
        controller.filteredAestheticReferences.map((item) => item.id),
        <String>['a', 'b'],
      );
      // The starred key never changes the All key's count.
      expect(controller.aestheticCount(), 2);
      expect(controller.aestheticCount(favoritesOnly: true), 1);

      controller.setAestheticFavoritesOnly(true);
      expect(controller.filteredAestheticReferences.single.id, 'a');

      expect(controller.hasAestheticFilters, isTrue);
      controller.resetAestheticFilters();
      expect(controller.hasAestheticFilters, isFalse);
      expect(controller.filteredAestheticReferences.length, 3);
    });

    test('starring an aesthetic keeps it in the library', () {
      final controller = _controller();
      addTearDown(controller.dispose);
      _seed(controller, 'a', 'Alpha');
      controller.toggleAestheticFavorite('a');
      expect(
        controller.aestheticReferences.single.favorite,
        isTrue,
        reason: 'a star is durable, not a view preference',
      );
      controller.toggleAestheticFavorite('a');
      expect(controller.aestheticReferences.single.favorite, isFalse);
      // Unknown ids are ignored rather than throwing.
      controller.toggleAestheticFavorite('missing');
      expect(controller.aestheticReferences.length, 1);
    });

    test('tags de-duplicate case-insensitively and sort', () {
      final controller = _controller();
      addTearDown(controller.dispose);
      _seed(controller, 'a', 'Alpha', tags: ['Noir', 'zoom']);
      _seed(controller, 'b', 'Beta', tags: ['noir', '1970s']);
      expect(controller.aestheticTags, <String>['1970s', 'Noir', 'zoom']);
      expect(controller.aestheticTagCount('NOIR'), 2);
      expect(controller.aestheticTagCount('zoom'), 1);
    });
  });

  testWidgets('References desk switches between its media and aesthetic tabs', (
    tester,
  ) async {
    final controller = _controller();
    addTearDown(controller.dispose);
    _seed(controller, 'a', 'Alpha');
    await _pumpReferences(tester, controller);

    expect(
      find.byKey(const ValueKey('reference-library-search')),
      findsOneWidget,
    );
    expect(_row('a'), findsNothing);

    await tester.tap(find.byKey(const ValueKey('references-tab-aesthetics')));
    await tester.pumpAndSettle();
    expect(controller.referencesTab, ReferencesTab.aesthetics);
    expect(_row('a'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('reference-library-search')),
      findsNothing,
      reason: 'the media toolbar belongs to the media tab only',
    );

    await tester.tap(find.byKey(const ValueKey('references-tab-media')));
    await tester.pumpAndSettle();
    expect(controller.referencesTab, ReferencesTab.media);
    expect(_row('a'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a long aesthetic list scrolls under a pinned heading', (
    tester,
  ) async {
    final controller = _controller();
    addTearDown(controller.dispose);
    for (var index = 0; index < 40; index += 1) {
      final id = index.toString().padLeft(2, '0');
      _seed(controller, 'a$id', 'Aesthetic $id');
    }
    controller.setReferencesTab(ReferencesTab.aesthetics);
    await _pumpReferences(tester, controller);

    expect(_row('a39'), findsOneWidget);
    expect(
      _onScreen(tester, _row('a39')),
      isFalse,
      reason: 'the last of 40 rows starts below the fold',
    );

    final scrollable = _aestheticScrollable;
    await tester.scrollUntilVisible(_row('a39'), 400, scrollable: scrollable);
    await tester.pumpAndSettle();

    expect(
      _onScreen(tester, _row('a39')),
      isTrue,
      reason: 'the list must scroll instead of growing the heading',
    );
    expect(
      _onScreen(tester, find.text('Your creative ingredients.')),
      isTrue,
      reason: 'the heading stays pinned while the list scrolls',
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('search, tags, and stars narrow and reorder the list', (
    tester,
  ) async {
    final controller = _controller();
    addTearDown(controller.dispose);
    _seed(controller, 'a', 'Alpha', text: 'Warm amber.', tags: ['noir']);
    _seed(controller, 'b', 'Beta', text: 'Cold sodium.', tags: ['1970s']);
    _seed(controller, 'c', 'Gamma', text: 'Even key.');
    controller.setReferencesTab(ReferencesTab.aesthetics);
    await _pumpReferences(tester, controller);
    expect(_rowIds(tester), <String>['a', 'b', 'c']);

    await tester.enterText(
      find.byKey(const ValueKey('aesthetic-library-search')),
      'sodium',
    );
    await tester.pumpAndSettle();
    expect(_rowIds(tester), <String>['b']);

    await tester.enterText(
      find.byKey(const ValueKey('aesthetic-library-search')),
      '',
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('aesthetic-tag-button')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('aesthetic-tag-noir')));
    await tester.pumpAndSettle();
    expect(controller.aestheticTag, 'noir');
    expect(_rowIds(tester), <String>['a']);

    await tester.tap(find.byKey(const ValueKey('aesthetic-filter-reset')));
    await tester.pumpAndSettle();
    expect(controller.hasAestheticFilters, isFalse);
    // The panel stays anchored over the toolbar; dismiss it before tapping on.
    await tester.tapAt(const Offset(640, 870));
    await tester.pumpAndSettle();
    expect(_rowIds(tester), <String>['a', 'b', 'c']);

    await tester.tap(find.byKey(const ValueKey('aesthetic-favorite-c')));
    await tester.pumpAndSettle();
    expect(_rowIds(tester), <String>[
      'c',
      'a',
      'b',
    ], reason: 'starring lifts a row to the top of the list');

    await tester.tap(find.byKey(const ValueKey('aesthetic-filter-starred')));
    await tester.pumpAndSettle();
    expect(_rowIds(tester), <String>['c']);
    expect(tester.takeException(), isNull);
  });

  testWidgets('the aesthetic tab lists and scrolls on a narrow surface', (
    tester,
  ) async {
    final controller = _controller();
    addTearDown(controller.dispose);
    for (var index = 0; index < 20; index += 1) {
      final id = index.toString().padLeft(2, '0');
      _seed(controller, 'a$id', 'Aesthetic $id', tags: ['noir', '1970s']);
    }
    controller.setReferencesTab(ReferencesTab.aesthetics);
    await _pumpReferences(tester, controller, size: const Size(390, 844));

    expect(_row('a00'), findsOneWidget);
    expect(_onScreen(tester, _row('a19')), isFalse);
    await tester.scrollUntilVisible(
      _row('a19'),
      400,
      scrollable: _aestheticScrollable,
    );
    await tester.pumpAndSettle();
    expect(_onScreen(tester, _row('a19')), isTrue);
    expect(tester.takeException(), isNull);
  });

  testWidgets('an empty aesthetic tab explains itself and offers Add', (
    tester,
  ) async {
    final controller = _controller();
    addTearDown(controller.dispose);
    controller.setReferencesTab(ReferencesTab.aesthetics);
    await _pumpReferences(tester, controller);
    expect(find.text('No aesthetics yet.'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('add-first-aesthetic-reference')),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('the editor saves tags and a star, and the row shows both', (
    tester,
  ) async {
    final controller = _controller();
    addTearDown(controller.dispose);
    controller.setReferencesTab(ReferencesTab.aesthetics);
    await _pumpReferences(tester, controller);

    await tester.tap(
      find.byKey(const ValueKey('add-first-aesthetic-reference')),
    );
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('aesthetic-title')),
      'Silver screen',
    );
    await tester.enterText(
      find.byKey(const ValueKey('aesthetic-tags')),
      'noir, 1970s',
    );
    await tester.ensureVisible(find.byKey(const ValueKey('aesthetic-text')));
    await tester.enterText(
      find.byKey(const ValueKey('aesthetic-text')),
      'Soft monochrome grain.',
    );
    await tester.tap(find.byKey(const ValueKey('aesthetic-favorite-toggle')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('aesthetic-save')));
    await tester.pumpAndSettle();

    final saved = controller.aestheticReferences.single;
    expect(saved.tags, <String>['noir', '1970s']);
    expect(saved.favorite, isTrue);
    expect(find.text('#noir'), findsWidgets);
    expect(tester.takeException(), isNull);
  });

  testWidgets('the Create picker searches, stars in place, and clears', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1200, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final controller = _controller();
    addTearDown(controller.dispose);
    _seed(controller, 'golden', 'Golden hour', text: 'Warm amber light.');
    _seed(controller, 'noir', 'Night city', text: 'Sodium streetlamps.');
    await tester.pumpWidget(
      MaterialApp(
        theme: buildClawnsoleTheme(Brightness.dark),
        home: Scaffold(body: CreateScreen(controller: controller)),
      ),
    );
    await tester.pumpAndSettle();

    Future<void> openPicker() async {
      await tester.tap(find.byKey(const ValueKey('prompt-aesthetic-picker')));
      await tester.pumpAndSettle();
    }

    await openPicker();
    expect(
      find.byKey(const ValueKey('prompt-aesthetic-option-golden')),
      findsOneWidget,
    );
    await tester.enterText(
      find.byKey(const ValueKey('prompt-aesthetic-search')),
      'sodium',
    );
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('prompt-aesthetic-option-golden')),
      findsNothing,
    );
    expect(
      find.byKey(const ValueKey('prompt-aesthetic-option-noir')),
      findsOneWidget,
    );

    await tester.tap(find.byKey(const ValueKey('prompt-aesthetic-star-noir')));
    await tester.pumpAndSettle();
    expect(
      controller.aestheticReferences
          .firstWhere((item) => item.id == 'noir')
          .favorite,
      isTrue,
    );
    expect(
      find.byKey(const ValueKey('prompt-aesthetic-option-noir')),
      findsOneWidget,
      reason: 'starring must not close the panel',
    );

    await tester.tap(
      find.byKey(const ValueKey('prompt-aesthetic-option-noir')),
    );
    await tester.pumpAndSettle();
    expect(controller.form.aestheticReferenceId, 'noir');
    expect(
      find.byKey(const ValueKey('prompt-aesthetic-search')),
      findsNothing,
      reason: 'choosing an aesthetic closes the panel',
    );

    await openPicker();
    expect(
      find.byKey(const ValueKey('prompt-aesthetic-option-golden')),
      findsOneWidget,
      reason: 'the search box resets on every open',
    );
    await tester.tap(find.byKey(const ValueKey('prompt-aesthetic-none')));
    await tester.pumpAndSettle();
    expect(controller.form.aestheticReferenceId, isNull);

    await openPicker();
    await tester.tap(find.byKey(const ValueKey('prompt-aesthetic-manage')));
    await tester.pumpAndSettle();
    expect(controller.referencesTab, ReferencesTab.aesthetics);
    expect(controller.section, AppSection.references);
    expect(tester.takeException(), isNull);
  });
}
