import 'package:clawnsole/app/app_controller.dart';
import 'package:clawnsole/app/app_theme.dart';
import 'package:clawnsole/app/clawnsole_app.dart';
import 'package:clawnsole/core/gateway.dart';
import 'package:clawnsole/core/models.dart';
import 'package:clawnsole/ui/create_screen.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('favorites preferences', () {
    test('round-trip through JSON and stay out of untouched preferences', () {
      const untouched = AppPreferences();
      expect(untouched.toJson().containsKey('favoriteModels'), isFalse);
      expect(untouched.toJson().containsKey('favoriteProviders'), isFalse);

      const starred = AppPreferences(
        favoriteModels: <String>['ltx|ltx-2-3-fast', 'bfl|flux-3-video'],
        favoriteProviders: <String>['artcraft'],
      );
      final restored = AppPreferences.fromJson(starred.toJson());
      expect(restored.favoriteModels, <String>[
        'ltx|ltx-2-3-fast',
        'bfl|flux-3-video',
      ]);
      expect(restored.favoriteProviders, <String>['artcraft']);
    });

    test('parsing drops junk and repeats while keeping first positions', () {
      final restored = AppPreferences.fromJson(<String, Object?>{
        'favoriteModels': <Object?>['bfl|flux-3-video', 4, '', ' ', 'x|y'],
        'favoriteProviders': <Object?>['ltx', 'ltx', null, 'bfl'],
      });
      expect(restored.favoriteModels, <String>['bfl|flux-3-video', 'x|y']);
      expect(restored.favoriteProviders, <String>['ltx', 'bfl']);
      expect(
        AppPreferences.fromJson(<String, Object?>{
          'favoriteModels': 'not-a-list',
        }).favoriteModels,
        isEmpty,
      );
    });

    test('model keys split back into provider and model ids', () {
      expect(modelFavoriteKey('bfl', 'flux-3-video'), 'bfl|flux-3-video');
      expect(parseModelFavoriteKey('bfl|flux-3-video'), (
        providerId: 'bfl',
        modelId: 'flux-3-video',
      ));
      expect(parseModelFavoriteKey('nodivider'), isNull);
      expect(parseModelFavoriteKey('|model'), isNull);
      expect(parseModelFavoriteKey('provider|'), isNull);
    });
  });

  group('controller favorites', () {
    test('starring persists and resolves in catalog order', () async {
      final gateway = OrganizationGateway(snapshotFor());
      final controller = AppController(gateway: gateway);
      addTearDown(controller.dispose);
      await controller.initialize();

      await controller.toggleFavoriteModel('ltx', 'ltx-2-3-fast');
      await controller.toggleFavoriteModel('bfl', 'flux-3-video');
      expect(gateway.snapshot.preferences.favoriteModels, <String>[
        'ltx|ltx-2-3-fast',
        'bfl|flux-3-video',
      ]);
      // Catalog order (BFL before LTX), not star order.
      expect(
        controller.favoriteModels
            .map((item) => '${item.provider.id}/${item.model.id}')
            .toList(),
        <String>['bfl/flux-3-video', 'ltx/ltx-2-3-fast'],
      );
      expect(controller.isFavoriteModel('ltx', 'ltx-2-3-fast'), isTrue);

      await controller.toggleFavoriteModel('ltx', 'ltx-2-3-fast');
      expect(controller.isFavoriteModel('ltx', 'ltx-2-3-fast'), isFalse);
      expect(gateway.snapshot.preferences.favoriteModels, <String>[
        'bfl|flux-3-video',
      ]);
    });

    test('starred providers lead the provider order', () async {
      final gateway = OrganizationGateway(snapshotFor());
      final controller = AppController(gateway: gateway);
      addTearDown(controller.dispose);
      await controller.initialize();

      final catalogOrder = controller.providers
          .map((provider) => provider.id)
          .toList();
      expect(catalogOrder.first, isNot('ltx'));

      await controller.toggleFavoriteProvider('ltx');
      expect(gateway.snapshot.preferences.favoriteProviders, <String>['ltx']);
      final preferred = controller.providersByPreference
          .map((provider) => provider.id)
          .toList();
      expect(preferred.first, 'ltx');
      expect(preferred.toSet(), catalogOrder.toSet());
      expect(preferred.sublist(1), catalogOrder.where((id) => id != 'ltx'));
    });

    test('restored favorites survive a reload and skip unknown ids', () async {
      final gateway = OrganizationGateway(
        snapshotFor(
          preferences: const AppPreferences(
            favoriteModels: <String>['bfl|flux-3-video', 'ghost|nope'],
            favoriteProviders: <String>['artcraft', 'ghost'],
          ),
        ),
      );
      final controller = AppController(gateway: gateway);
      addTearDown(controller.dispose);
      await controller.initialize();

      expect(controller.favoriteModels.map((item) => item.model.id), <String>[
        'flux-3-video',
      ]);
      expect(
        controller.favoriteProviders.map((provider) => provider.id),
        <String>['artcraft'],
      );
      // Unknown ids are kept in the preference, not silently dropped, so a
      // provider that returns later is still starred.
      await controller.toggleFavoriteProvider('ltx');
      expect(gateway.snapshot.preferences.favoriteProviders, <String>[
        'artcraft',
        'ghost',
        'ltx',
      ]);
    });
  });

  group('media type facets', () {
    test('library type counts respect every other filter', () async {
      final gateway = OrganizationGateway(
        snapshotFor(
          generations: <Generation>[
            film(0),
            film(1),
            film(2, outputKind: GenerationOutputKind.image),
            film(3, outputKind: GenerationOutputKind.image, hidden: true),
          ],
        ),
      );
      final controller = AppController(gateway: gateway);
      addTearDown(controller.dispose);
      await controller.initialize();

      expect(controller.libraryOutputKindCount(null), 3);
      expect(controller.libraryOutputKindCount(GenerationOutputKind.video), 2);
      expect(controller.libraryOutputKindCount(GenerationOutputKind.image), 1);

      controller.setLibraryOutputKind(GenerationOutputKind.image);
      expect(
        controller.filteredGenerations.map((item) => item.localId),
        <String>['film-2'],
      );
      // The facet counts ignore the type filter itself but honour the rest.
      expect(controller.libraryOutputKindCount(GenerationOutputKind.video), 2);
      controller.setSearch('number 1');
      expect(controller.libraryOutputKindCount(GenerationOutputKind.video), 1);
      expect(controller.libraryOutputKindCount(GenerationOutputKind.image), 0);
      expect(controller.filteredGenerations, isEmpty);
    });

    test('reference kind counts respect every other filter', () async {
      final gateway = OrganizationGateway(
        snapshotFor(
          savedReferences: <SavedReference>[
            _reference('a', MediaReferenceKind.image),
            _reference('b', MediaReferenceKind.video),
            _reference('c', MediaReferenceKind.audio, favorite: true),
          ],
        ),
      );
      final controller = AppController(gateway: gateway);
      addTearDown(controller.dispose);
      await controller.initialize();

      expect(controller.referenceKindCount(null), 3);
      expect(controller.referenceKindCount(MediaReferenceKind.audio), 1);
      controller.setReferenceKind(MediaReferenceKind.video);
      expect(controller.filteredSavedReferences.single.id, 'b');
      expect(controller.referenceKindCount(MediaReferenceKind.audio), 1);
      controller.setReferenceFavoriteFilter(FavoriteFilter.starred);
      expect(controller.referenceKindCount(MediaReferenceKind.audio), 1);
      expect(controller.referenceKindCount(MediaReferenceKind.video), 0);
      expect(controller.filteredSavedReferences, isEmpty);
    });
  });

  group('folder tree state', () {
    test('collapse hides descendants and selecting reveals them', () async {
      final gateway = OrganizationGateway(
        snapshotFor(folders: foldersFixture()),
      );
      final controller = AppController(gateway: gateway);
      addTearDown(controller.dispose);
      await controller.initialize();

      expect(controller.folderAncestors('drafts'), <String>[
        'deliverables',
        'client',
      ]);
      controller.setFolderCollapsed('client', true);
      expect(controller.isFolderHidden('deliverables'), isTrue);
      expect(controller.isFolderHidden('drafts'), isTrue);
      expect(controller.isFolderHidden('client'), isFalse);

      controller.setLibraryFolderView('drafts');
      expect(controller.isFolderCollapsed('client'), isFalse);
      expect(controller.isFolderHidden('drafts'), isFalse);
    });

    test(
      'moving a folder refuses cross-storage and self-branch parents',
      () async {
        final gateway = OrganizationGateway(
          snapshotFor(folders: foldersFixture()),
        );
        final controller = AppController(gateway: gateway);
        addTearDown(controller.dispose);
        await controller.initialize();

        final client = controller.folderById('client')!;
        final drafts = controller.folderById('drafts')!;
        final drive = controller.folderById('drive-folder')!;
        expect(controller.canMoveFolder(client, parentId: 'drafts'), isFalse);
        expect(
          controller.canMoveFolder(client, parentId: 'drive-folder'),
          isFalse,
        );
        expect(controller.canMoveFolder(drafts, parentId: 'client'), isTrue);
        expect(controller.canMoveFolder(drafts, parentId: null), isTrue);

        expect(
          await controller.moveFolder(client, parentId: 'drafts'),
          isFalse,
        );
        expect(controller.notice, 'A folder cannot move inside itself.');
        expect(
          await controller.moveFolder(drafts, parentId: 'drive-folder'),
          isFalse,
        );
        expect(
          controller.notice,
          'Folders can only move within the same storage.',
        );
        expect(await controller.moveFolder(drive, parentId: null), isTrue);

        controller.setFolderCollapsed('client', true);
        expect(await controller.moveFolder(drafts, parentId: 'client'), isTrue);
        expect(controller.folderById('drafts')!.parentId, 'client');
        // The destination opens so the moved folder is in view.
        expect(controller.isFolderCollapsed('client'), isFalse);
        expect(controller.notice, 'Folder moved.');

        expect(await controller.renameFolder(drafts, 'Sketches'), isTrue);
        expect(controller.folderById('drafts')!.name, 'Sketches');
        expect(controller.folderById('drafts')!.parentId, 'client');
        expect(controller.notice, 'Folder renamed.');
      },
    );
  });

  group('folder rail', () {
    testWidgets('collapses branches, renames in place, and adds subfolders', (
      tester,
    ) async {
      await tester.binding.setSurfaceSize(const Size(1440, 1000));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final gateway = OrganizationGateway(
        snapshotFor(
          activeSection: AppSection.library,
          folders: foldersFixture(),
          generations: <Generation>[
            film(0),
            film(1, folderId: 'drafts'),
          ],
        ),
      );
      await tester.pumpWidget(
        ClawnsoleApp(gateway: gateway, checkForUpdates: false),
      );
      await tester.pumpAndSettle();

      const client = ValueKey('folder-row-client');
      const deliverables = ValueKey('folder-row-deliverables');
      const drafts = ValueKey('folder-row-drafts');
      expect(find.byKey(client), findsOneWidget);
      expect(find.byKey(deliverables), findsOneWidget);
      expect(find.byKey(drafts), findsOneWidget);

      // Chevron folds the whole branch; the leaf has no chevron.
      expect(find.byKey(const ValueKey('folder-toggle-drafts')), findsNothing);
      await tester.tap(find.byKey(const ValueKey('folder-toggle-client')));
      await tester.pumpAndSettle();
      expect(find.byKey(deliverables), findsNothing);
      expect(find.byKey(drafts), findsNothing);
      await tester.tap(find.byKey(const ValueKey('folder-toggle-client')));
      await tester.pumpAndSettle();
      expect(find.byKey(drafts), findsOneWidget);

      // Rename in place: select the row (which reveals its menu), then type.
      await tester.tap(find.byKey(client));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('folder-menu-client')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Rename'));
      await tester.pumpAndSettle();
      const field = ValueKey('folder-editor-field');
      expect(find.byKey(field), findsOneWidget);
      await tester.enterText(find.byKey(field), 'Studio work');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();
      expect(find.byKey(field), findsNothing);
      expect(
        gateway.snapshot.folders.singleWhere((f) => f.id == 'client').name,
        'Studio work',
      );
      expect(find.text('Studio work'), findsWidgets);

      // Escape abandons an edit without saving.
      await tester.tap(find.byKey(const ValueKey('folder-menu-client')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Rename'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(field), 'Nope');
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(find.byKey(field), findsNothing);
      expect(
        gateway.snapshot.folders.singleWhere((f) => f.id == 'client').name,
        'Studio work',
      );

      // A subfolder grows from the row's menu as an editor row beneath it.
      await tester.tap(find.byKey(const ValueKey('folder-menu-client')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('New subfolder'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(field), 'Pitches');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();
      final pitches = gateway.snapshot.folders.singleWhere(
        (f) => f.name == 'Pitches',
      );
      expect(pitches.parentId, 'client');
      expect(pitches.storage, LibraryStorage.local);
      expect(find.byKey(ValueKey('folder-row-${pitches.id}')), findsOneWidget);

      // The rail's + key adds a top-level folder the same way.
      await tester.tap(find.byKey(const ValueKey('folder-rail-new')));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(field), 'Archive');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();
      expect(
        gateway.snapshot.folders
            .singleWhere((f) => f.name == 'Archive')
            .parentId,
        isNull,
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('drags cards and folders onto folder rows', (tester) async {
      await tester.binding.setSurfaceSize(const Size(1440, 1000));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final gateway = OrganizationGateway(
        snapshotFor(
          activeSection: AppSection.library,
          folders: foldersFixture(),
          generations: <Generation>[film(0), film(1)],
        ),
      );
      await tester.pumpWidget(
        ClawnsoleApp(gateway: gateway, checkForUpdates: false),
      );
      await tester.pumpAndSettle();

      Future<void> dragTo(Finder from, Offset start, Finder to) async {
        final gesture = await tester.startGesture(
          start,
          kind: PointerDeviceKind.mouse,
        );
        await gesture.moveBy(const Offset(0, 12));
        await tester.pump();
        await gesture.moveTo(tester.getCenter(to));
        await tester.pump();
        await gesture.up();
        await tester.pumpAndSettle();
      }

      // A card lands in the folder it is dropped on.
      final card = find.byKey(const ValueKey('library-generation-film-0'));
      final cardTop = tester.getTopLeft(card);
      await dragTo(
        card,
        Offset(cardTop.dx + tester.getSize(card).width / 2, cardTop.dy + 70),
        find.byKey(const ValueKey('folder-row-client')),
      );
      expect(
        gateway.snapshot.generations
            .singleWhere((g) => g.localId == 'film-0')
            .folderId,
        'client',
      );

      // A folder row dropped on Unfiled moves to the top level.
      final drafts = find.byKey(const ValueKey('folder-row-drafts'));
      await dragTo(
        drafts,
        tester.getCenter(drafts),
        find.byKey(const ValueKey('folder-row-unfiled')),
      );
      expect(
        gateway.snapshot.folders.singleWhere((f) => f.id == 'drafts').parentId,
        isNull,
      );

      // A folder cannot be dropped into its own branch: nothing changes.
      final client = find.byKey(const ValueKey('folder-row-client'));
      await dragTo(
        client,
        tester.getCenter(client),
        find.byKey(const ValueKey('folder-row-deliverables')),
      );
      expect(
        gateway.snapshot.folders.singleWhere((f) => f.id == 'client').parentId,
        isNull,
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('type segments narrow the library with facet counts', (
      tester,
    ) async {
      await tester.binding.setSurfaceSize(const Size(1440, 1000));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final gateway = OrganizationGateway(
        snapshotFor(
          activeSection: AppSection.library,
          generations: <Generation>[
            film(0),
            film(1),
            film(2, outputKind: GenerationOutputKind.image),
          ],
        ),
      );
      await tester.pumpWidget(
        ClawnsoleApp(gateway: gateway, checkForUpdates: false),
      );
      await tester.pumpAndSettle();

      expect(
        find.byKey(const ValueKey('library-generation-film-0')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('library-generation-film-2')),
        findsOneWidget,
      );
      await tester.tap(find.byKey(const ValueKey('library-kind-image')));
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('library-generation-film-0')),
        findsNothing,
      );
      expect(
        find.byKey(const ValueKey('library-generation-film-2')),
        findsOneWidget,
      );
      // Facet counts still describe the whole view: 2 videos, 1 image.
      final videoSegment = find.byKey(const ValueKey('library-kind-video'));
      expect(
        find.descendant(of: videoSegment, matching: find.text('2')),
        findsOneWidget,
      );
      await tester.tap(videoSegment);
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('library-generation-film-2')),
        findsNothing,
      );
      expect(
        find.byKey(const ValueKey('library-generation-film-1')),
        findsOneWidget,
      );
      await tester.tap(find.byKey(const ValueKey('library-kind-all')));
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('library-generation-film-2')),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('narrow references use the console-key folder dropdown', (
      tester,
    ) async {
      await tester.binding.setSurfaceSize(const Size(390, 844));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final gateway = OrganizationGateway(
        snapshotFor(
          activeSection: AppSection.references,
          folders: <LibraryFolder>[
            _folder('moods', 'Moods', collection: LibraryCollection.references),
            _folder(
              'noir',
              'Noir',
              parentId: 'moods',
              collection: LibraryCollection.references,
            ),
          ],
        ),
      );
      await tester.pumpWidget(
        ClawnsoleApp(gateway: gateway, checkForUpdates: false),
      );
      await tester.pumpAndSettle();

      final dropdown = find.byKey(const ValueKey('mobile-folder-dropdown'));
      expect(dropdown, findsOneWidget);
      expect(find.text('All references'), findsOneWidget);
      await tester.tap(dropdown);
      await tester.pumpAndSettle();
      expect(find.text('Choose a folder'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('folder-row-noir')));
      await tester.pumpAndSettle();
      expect(find.text('Choose a folder'), findsNothing);
      expect(find.text('Moods / Noir'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });

  group('favorites in the picker and desk', () {
    testWidgets('starred models pin above providers and select on tap', (
      tester,
    ) async {
      await tester.binding.setSurfaceSize(const Size(1400, 1000));
      addTearDown(() async {
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.binding.setSurfaceSize(null);
      });
      final gateway = OrganizationGateway(snapshotFor());
      final controller = AppController(gateway: gateway);
      await controller.initialize();
      await tester.pumpWidget(
        MaterialApp(
          theme: buildClawnsoleTheme(Brightness.light),
          home: Scaffold(
            body: AnimatedBuilder(
              animation: controller,
              builder: (context, _) => CreateScreen(controller: controller),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byTooltip('Choose provider and model'));
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('provider-model-favorites')),
        findsNothing,
      );

      // The picker lists providers alphabetically; ArtCraft leads, BFL sits
      // third, so both stay inside the lazily built menu list.
      const artcraftHeading = ValueKey('provider-model-heading-artcraft');
      const bflHeading = ValueKey('provider-model-heading-bfl');
      await tester.tap(find.byKey(artcraftHeading));
      await tester.pumpAndSettle();
      const star = ValueKey('provider-model-star-artcraft-seedance_2p0');
      await tester.ensureVisible(find.byKey(star));
      await tester.tap(find.byKey(star));
      await tester.pumpAndSettle();
      // Fold ArtCraft again so every heading sits inside the lazily built
      // list for the position checks below.
      await tester.tap(find.byKey(artcraftHeading));
      await tester.pumpAndSettle();

      expect(gateway.snapshot.preferences.favoriteModels, <String>[
        'artcraft|seedance_2p0',
      ]);
      final favorites = find.byKey(const ValueKey('provider-model-favorites'));
      expect(favorites, findsOneWidget);
      final favoriteRow = find.byKey(
        const ValueKey('provider-model-favorite-artcraft-seedance_2p0'),
      );
      expect(favoriteRow, findsOneWidget);
      expect(
        tester.getTopLeft(favorites).dy,
        lessThan(tester.getTopLeft(find.byKey(artcraftHeading)).dy),
      );

      // Starring a provider lifts its section above the rest.
      expect(
        tester.getTopLeft(find.byKey(artcraftHeading)).dy,
        lessThan(tester.getTopLeft(find.byKey(bflHeading)).dy),
      );
      await tester.tap(find.byKey(const ValueKey('provider-favorite-bfl')));
      await tester.pumpAndSettle();
      expect(gateway.snapshot.preferences.favoriteProviders, <String>['bfl']);
      // A freshly starred provider opens so its models are in reach.
      expect(
        find.byKey(const ValueKey('provider-model-option-bfl-flux-3-video')),
        findsOneWidget,
      );
      expect(
        tester.getTopLeft(find.byKey(bflHeading)).dy,
        lessThan(tester.getTopLeft(find.byKey(artcraftHeading)).dy),
      );
      // The favorites block still leads.
      expect(
        tester.getTopLeft(favorites).dy,
        lessThan(tester.getTopLeft(find.byKey(bflHeading)).dy),
      );

      // Tapping the pinned model selects it.
      await tester.ensureVisible(favoriteRow);
      await tester.pumpAndSettle();
      await tester.tap(favoriteRow);
      await tester.pumpAndSettle();
      expect(controller.selectedProviderId, 'artcraft');
      expect(controller.selectedModelId, 'seedance_2p0');
      expect(gateway.snapshot.preferences.provider, 'artcraft');
      expect(tester.takeException(), isNull);
      // Cancel the controller's poll timers before the binding checks for
      // stragglers, like the other direct-harness picker tests.
      controller.dispose();
    });

    testWidgets('the provider desk groups starred providers first', (
      tester,
    ) async {
      await tester.binding.setSurfaceSize(const Size(1400, 1000));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final gateway = OrganizationGateway(
        snapshotFor(
          activeSection: AppSection.providers,
          preferences: const AppPreferences(
            activeSection: AppSection.providers,
            favoriteProviders: <String>['ltx'],
          ),
        ),
      );
      await tester.pumpWidget(
        ClawnsoleApp(gateway: gateway, checkForUpdates: false),
      );
      await tester.pumpAndSettle();

      expect(find.text('FAVORITES'), findsOneWidget);
      expect(find.text('OTHER PROVIDERS'), findsOneWidget);
      final ltxCard = find.byKey(const ValueKey('provider-card-star-ltx'));
      final bflCard = find.byKey(const ValueKey('provider-card-star-bfl'));
      expect(
        tester.getTopLeft(ltxCard).dy,
        lessThan(tester.getTopLeft(bflCard).dy),
      );

      await tester.tap(ltxCard);
      await tester.pumpAndSettle();
      expect(gateway.snapshot.preferences.favoriteProviders, isEmpty);
      expect(find.text('FAVORITES'), findsNothing);
      expect(tester.takeException(), isNull);
    });
  });
}

LocalSnapshot snapshotFor({
  AppSection activeSection = AppSection.create,
  AppPreferences? preferences,
  List<Generation> generations = const <Generation>[],
  List<LibraryFolder> folders = const <LibraryFolder>[],
  List<SavedReference> savedReferences = const <SavedReference>[],
}) => LocalSnapshot(
  generations: generations,
  folders: folders,
  savedReferences: savedReferences,
  preferences: preferences ?? AppPreferences(activeSection: activeSection),
  hasApiKey: false,
  storage: StorageStats(path: 'memory', bytes: 0, records: generations.length),
);

final DateTime _now = DateTime.utc(2026, 9, 2, 12);

LibraryFolder _folder(
  String id,
  String name, {
  String? parentId,
  LibraryStorage storage = LibraryStorage.local,
  LibraryCollection collection = LibraryCollection.generated,
}) => LibraryFolder(
  id: id,
  name: name,
  createdAt: _now,
  parentId: parentId,
  storage: storage,
  collection: collection,
);

/// Client work ▸ Deliverables ▸ Drafts, plus a Drive-side folder.
List<LibraryFolder> foldersFixture() => <LibraryFolder>[
  _folder('client', 'Client work'),
  _folder('deliverables', 'Deliverables', parentId: 'client'),
  _folder('drafts', 'Drafts', parentId: 'deliverables'),
  _folder('drive-folder', 'Cloud cuts', storage: LibraryStorage.drive),
];

Generation film(
  int index, {
  String? folderId,
  GenerationOutputKind outputKind = GenerationOutputKind.video,
  bool hidden = false,
}) {
  final createdAt = _now.subtract(Duration(minutes: index));
  return Generation(
    localId: 'film-$index',
    provider: 'bfl',
    model: 'flux-3-video',
    status: 'Ready',
    prompt: 'A compact generation preview number $index.',
    mode: VideoMode.t2v,
    outputKind: outputKind,
    folderId: folderId,
    hidden: hidden,
    config: const GenerationConfig(
      aspectRatio: '16:9',
      duration: 8,
      resolution: 'hd',
      generateAudio: true,
      safetyTolerance: 2,
      draft: false,
    ),
    createdAt: createdAt,
    updatedAt: createdAt,
  );
}

SavedReference _reference(
  String id,
  MediaReferenceKind kind, {
  bool favorite = false,
}) => SavedReference(
  id: id,
  name: 'Reference $id',
  kind: kind,
  asset: AssetReference(
    kind: 'local',
    value: 'asset-$id',
    label: 'asset-$id',
    contentType: kind == MediaReferenceKind.audio ? 'audio/mpeg' : 'image/png',
  ),
  createdAt: _now,
  updatedAt: _now,
  favorite: favorite,
);

/// An in-memory gateway that persists folders, organization, references, and
/// preferences the way the direct gateway does, so the rail and pickers can
/// be driven end to end.
class OrganizationGateway
    implements AppGateway, LibraryOrganizationGateway, ReferenceLibraryGateway {
  OrganizationGateway(this.snapshot);

  LocalSnapshot snapshot;

  @override
  bool get usesCompanion => false;

  @override
  bool get supportsPhotoLibrarySave => false;

  @override
  String get persistenceDescription => 'Memory';

  @override
  Future<LocalSnapshot> load() async => snapshot;

  @override
  Future<LocalSnapshot> setPreferences(AppPreferences preferences) async =>
      snapshot = snapshot.copyWith(preferences: preferences);

  @override
  Future<LocalSnapshot> saveLibraryFolder(LibraryFolder folder) async {
    final folders = List<LibraryFolder>.from(snapshot.folders);
    final index = folders.indexWhere((item) => item.id == folder.id);
    if (index < 0) {
      folders.add(folder);
    } else {
      folders[index] = folder;
    }
    return snapshot = snapshot.copyWith(folders: folders);
  }

  @override
  Future<LocalSnapshot> deleteLibraryFolder(String folderId) async {
    final removed = snapshot.folders
        .where((folder) => folder.id == folderId)
        .firstOrNull;
    return snapshot = snapshot.copyWith(
      folders: snapshot.folders
          .where((folder) => folder.id != folderId)
          .map(
            (folder) => folder.parentId == folderId
                ? folder.copyWith(
                    parentId: removed?.parentId,
                    clearParent: removed?.parentId == null,
                  )
                : folder,
          )
          .toList(),
      generations: snapshot.generations
          .map(
            (item) => item.folderId == folderId
                ? item.copyWith(clearFolder: true)
                : item,
          )
          .toList(),
      savedReferences: snapshot.savedReferences
          .map(
            (item) => item.folderId == folderId
                ? item.copyWith(clearFolder: true)
                : item,
          )
          .toList(),
    );
  }

  @override
  Future<LocalSnapshot> setGenerationOrganization(
    String localId, {
    String? folderId,
    required List<String> tags,
  }) async => snapshot = snapshot.copyWith(
    generations: snapshot.generations
        .map(
          (item) => item.localId == localId
              ? item.copyWith(
                  folderId: folderId,
                  clearFolder: folderId == null,
                  tags: tags,
                )
              : item,
        )
        .toList(),
  );

  @override
  Future<LocalSnapshot> saveReference(
    SavedReference reference, {
    String? source,
  }) async {
    final references = List<SavedReference>.from(snapshot.savedReferences);
    final index = references.indexWhere((item) => item.id == reference.id);
    if (index < 0) {
      references.add(reference);
    } else {
      references[index] = reference;
    }
    return snapshot = snapshot.copyWith(savedReferences: references);
  }

  @override
  Future<LocalSnapshot> deleteReference(String referenceId) async =>
      snapshot = snapshot.copyWith(
        savedReferences: snapshot.savedReferences
            .where((item) => item.id != referenceId)
            .toList(),
      );

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
  Future<Uint8List> readAsset(AssetReference reference) async => Uint8List(0);

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
