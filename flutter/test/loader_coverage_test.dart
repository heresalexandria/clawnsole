import 'dart:async';

import 'package:clawnsole/app/app_controller.dart';
import 'package:clawnsole/app/app_theme.dart';
import 'package:clawnsole/core/gateway.dart';
import 'package:clawnsole/core/models.dart';
import 'package:clawnsole/ui/busy_button.dart';
import 'package:clawnsole/ui/library_folders.dart';
import 'package:clawnsole/ui/library_screen.dart';
import 'package:clawnsole/ui/providers_screen.dart';
import 'package:clawnsole/ui/references_screen.dart';
import 'package:clawnsole/ui/settings_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Every converted control answers the same two questions while it works:
/// is it disabled, and is the 14 px mark on screen?
Finder get _spinner => find.byType(BusySpinner);

const LocalSnapshot _empty = LocalSnapshot(
  generations: <Generation>[],
  preferences: AppPreferences(),
  hasApiKey: false,
  storage: StorageStats(path: 'memory', bytes: 0, records: 0),
);

SavedReference _reference({bool hidden = false, String? folderId}) =>
    SavedReference(
      id: 'photo',
      name: 'IMG_1234.png',
      kind: MediaReferenceKind.image,
      hidden: hidden,
      folderId: folderId,
      asset: const AssetReference(
        kind: 'local',
        value: 'photo',
        label: 'IMG_1234.png',
      ),
      createdAt: DateTime.utc(2026),
      updatedAt: DateTime.utc(2026),
    );

Generation _film() {
  final now = DateTime.utc(2026);
  return Generation(
    localId: 'film',
    status: 'Ready',
    prompt: 'A kite over the bay',
    mode: VideoMode.t2v,
    provider: 'runway',
    model: 'gen4.5',
    config: const GenerationConfig(
      aspectRatio: '16:9',
      duration: 5,
      resolution: 'hd',
      generateAudio: false,
      safetyTolerance: 2,
      draft: false,
    ),
    resultUrl: 'https://example.invalid/film.mp4',
    createdAt: now,
    updatedAt: now,
  );
}

/// A gateway that can be held open, so a test can look at a control while its
/// work is still in flight.
class _SlowGateway
    implements
        AppGateway,
        ProviderGateway,
        ReferenceLibraryGateway,
        VisibilityGateway,
        LibraryOrganizationGateway {
  _SlowGateway(this.snapshot);

  LocalSnapshot snapshot;
  Completer<void>? hold;

  Completer<void> block() => hold = Completer<void>();

  Future<LocalSnapshot> _answer(LocalSnapshot Function() apply) async {
    final gate = hold;
    if (gate != null) await gate.future;
    return snapshot = apply();
  }

  @override
  bool get usesCompanion => false;
  @override
  bool get supportsPhotoLibrarySave => false;
  @override
  String get persistenceDescription => 'Memory';

  @override
  Future<LocalSnapshot> saveReference(
    SavedReference reference, {
    String? source,
  }) => _answer(() => snapshot.copyWith(savedReferences: [reference]));

  @override
  Future<LocalSnapshot> deleteReference(String referenceId) =>
      _answer(() => snapshot.copyWith(savedReferences: const []));

  @override
  Future<LocalSnapshot> setReferencesHidden(
    List<String> referenceIds,
    bool hidden,
  ) => _answer(
    () => snapshot.copyWith(
      savedReferences: snapshot.savedReferences
          .map(
            (item) => referenceIds.contains(item.id)
                ? item.copyWith(hidden: hidden)
                : item,
          )
          .toList(),
    ),
  );

  @override
  Future<LocalSnapshot> setGenerationsHidden(
    List<String> localIds,
    bool hidden,
  ) => _answer(
    () => snapshot.copyWith(
      generations: snapshot.generations
          .map(
            (item) => localIds.contains(item.localId)
                ? item.copyWith(hidden: hidden)
                : item,
          )
          .toList(),
    ),
  );

  @override
  Future<LocalSnapshot> saveLibraryFolder(LibraryFolder folder) => _answer(
    () => snapshot.copyWith(
      folders: <LibraryFolder>[...snapshot.folders, folder],
    ),
  );

  @override
  Future<LocalSnapshot> deleteLibraryFolder(String folderId) => _answer(
    () => snapshot.copyWith(
      folders: snapshot.folders
          .where((folder) => folder.id != folderId)
          .toList(),
    ),
  );

  @override
  Future<LocalSnapshot> setGenerationOrganization(
    String localId, {
    String? folderId,
    required List<String> tags,
  }) => _answer(() => snapshot);

  @override
  Future<LocalSnapshot> clearHistory() =>
      _answer(() => snapshot.copyWith(generations: const []));

  @override
  Future<ProviderAccountStatus> verifyProviderKey(
    String provider, [
    String? candidate,
  ]) async {
    final gate = hold;
    if (gate != null) await gate.future;
    return ProviderAccountStatus(
      provider: provider,
      balance: 12,
      currency: 'credits',
    );
  }

  @override
  Future<LocalSnapshot> clearProviderApiKey(String provider) => _answer(
    () => snapshot.copyWith(
      connectedProviders: snapshot.connectedProviders
          .where((id) => id != provider)
          .toSet(),
    ),
  );

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

AppController _controller(_SlowGateway gateway) =>
    AppController(gateway: gateway)
      ..snapshot = gateway.snapshot
      ..loading = false
      // Hidden items stay listed, so a card that is being hidden is still on
      // screen to show its loader.
      ..libraryVisibilityFilter = VisibilityFilter.all
      ..referenceVisibilityFilter = VisibilityFilter.all;

Future<void> _pump(
  WidgetTester tester,
  AppController controller,
  Widget body, {
  Size size = const Size(1500, 1800),
}) async {
  await tester.binding.setSurfaceSize(size);
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(
    MaterialApp(
      theme: buildClawnsoleTheme(Brightness.light),
      home: Scaffold(
        body: ListenableBuilder(
          listenable: controller,
          builder: (context, _) => body,
        ),
      ),
    ),
  );
  await tester.pump();
}

void main() {
  testWidgets('saving reference details holds the dialog and says so', (
    tester,
  ) async {
    final gateway = _SlowGateway(
      _empty.copyWith(savedReferences: [_reference()]),
    );
    final controller = _controller(gateway);
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      MaterialApp(
        theme: buildClawnsoleTheme(Brightness.light),
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () => showReferenceMetadataDialog(
                context,
                controller,
                reference: controller.savedReferences.single,
              ),
              child: const Text('Edit details'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Edit details'));
    await tester.pumpAndSettle();

    final gate = gateway.block();
    await tester.tap(find.byKey(const ValueKey('save-reference-metadata')));
    await tester.pump();

    // The reported bug: this used to hang with nothing on screen.
    expect(_spinner, findsOneWidget);
    expect(find.text('Saving…'), findsOneWidget);
    final save = tester.widget<FilledButton>(
      find.descendant(
        of: find.byKey(const ValueKey('save-reference-metadata')),
        matching: find.byType(FilledButton),
      ),
    );
    expect(save.onPressed, isNull);
    expect(
      tester
          .widget<TextButton>(find.widgetWithText(TextButton, 'Cancel'))
          .onPressed,
      isNull,
    );
    expect(
      tester
          .widget<TextField>(
            find.byKey(const ValueKey('reference-character-name')),
          )
          .enabled,
      isFalse,
    );

    gate.complete();
    await tester.pumpAndSettle();
    expect(find.text('Edit reference'), findsNothing);
    await tester.pump(const Duration(seconds: 6));
  });

  testWidgets('hiding a reference from its menu lights the card', (
    tester,
  ) async {
    final gateway = _SlowGateway(
      _empty.copyWith(savedReferences: [_reference()]),
    );
    final controller = _controller(gateway);
    addTearDown(controller.dispose);
    await _pump(tester, controller, ReferencesScreen(controller: controller));

    final gate = gateway.block();
    await tester.tap(find.byTooltip('IMG_1234.png options'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Hide').last);
    // The card is spinning, so the tree never settles: pump the menu's
    // dismissal by hand instead.
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    // The menu closed the moment it was chosen; the card carries the work.
    expect(controller.busy.isBusy('reference', 'photo'), isTrue);
    expect(_spinner, findsOneWidget);
    expect(find.byTooltip('IMG_1234.png options'), findsNothing);

    gate.complete();
    await tester.pumpAndSettle();
    expect(controller.busy.isBusy('reference', 'photo'), isFalse);
    expect(_spinner, findsNothing);
    expect(find.byTooltip('IMG_1234.png options'), findsOneWidget);
    await tester.pump(const Duration(seconds: 6));
  });

  testWidgets('deleting a reference waits behind its own confirm key', (
    tester,
  ) async {
    final gateway = _SlowGateway(
      _empty.copyWith(savedReferences: [_reference()]),
    );
    final controller = _controller(gateway);
    addTearDown(controller.dispose);
    await _pump(tester, controller, ReferencesScreen(controller: controller));

    await tester.tap(find.byTooltip('IMG_1234.png options'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Delete').last);
    await tester.pumpAndSettle();

    final gate = gateway.block();
    final confirm = find.byKey(const ValueKey('confirm-reference-delete'));
    await tester.tap(confirm);
    await tester.pump();

    expect(find.text('Deleting…'), findsOneWidget);
    expect(controller.busy.isBusy('reference', 'photo'), isTrue);
    expect(
      tester
          .widget<TextButton>(find.widgetWithText(TextButton, 'Cancel'))
          .onPressed,
      isNull,
    );

    gate.complete();
    await tester.pumpAndSettle();
    expect(confirm, findsNothing);
    expect(controller.savedReferences, isEmpty);
    await tester.pump(const Duration(seconds: 6));
  });

  testWidgets('the references bulk bar shows the hide it is doing', (
    tester,
  ) async {
    final gateway = _SlowGateway(
      _empty.copyWith(savedReferences: [_reference()]),
    );
    final controller = _controller(gateway);
    addTearDown(controller.dispose);
    await _pump(tester, controller, ReferencesScreen(controller: controller));

    await tester.tap(find.byKey(const ValueKey('reference-select-button')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Select visible'));
    await tester.pumpAndSettle();

    final gate = gateway.block();
    final hide = find.byKey(const ValueKey('reference-bulk-visibility'));
    await tester.tap(hide);
    await tester.pump();

    expect(find.descendant(of: hide, matching: _spinner), findsOneWidget);
    expect(
      tester
          .widget<OutlinedButton>(
            find.descendant(of: hide, matching: find.byType(OutlinedButton)),
          )
          .onPressed,
      isNull,
    );

    gate.complete();
    await tester.pumpAndSettle();
    expect(controller.savedReferences.single.hidden, isTrue);
    await tester.pump(const Duration(seconds: 6));
  });

  testWidgets('the library bulk bar shows the hide it is doing', (
    tester,
  ) async {
    final gateway = _SlowGateway(_empty.copyWith(generations: [_film()]));
    final controller = _controller(gateway);
    addTearDown(controller.dispose);
    await _pump(tester, controller, LibraryScreen(controller: controller));

    await tester.tap(find.byKey(const ValueKey('library-select-button')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Select visible'));
    await tester.pumpAndSettle();

    final gate = gateway.block();
    final hide = find.byKey(const ValueKey('library-bulk-visibility'));
    await tester.tap(hide);
    await tester.pump();

    expect(find.descendant(of: hide, matching: _spinner), findsOneWidget);
    expect(
      tester
          .widget<OutlinedButton>(
            find.descendant(of: hide, matching: find.byType(OutlinedButton)),
          )
          .onPressed,
      isNull,
    );

    gate.complete();
    await tester.pumpAndSettle();
    expect(controller.generations.single.hidden, isTrue);
    await tester.pump(const Duration(seconds: 6));
  });

  testWidgets('a film answers for work started from its closed menu', (
    tester,
  ) async {
    final gateway = _SlowGateway(_empty.copyWith(generations: [_film()]));
    final controller = _controller(gateway);
    addTearDown(controller.dispose);
    await _pump(tester, controller, LibraryScreen(controller: controller));

    final reuse = find.byKey(const ValueKey('library-reuse-film'));
    expect(
      tester
          .widget<OutlinedButton>(
            find.descendant(of: reuse, matching: find.byType(OutlinedButton)),
          )
          .onPressed,
      isNotNull,
    );

    final gate = Completer<void>();
    unawaited(controller.busy.run('generation', 'film', () => gate.future));
    await tester.pump();

    expect(
      tester
          .widget<OutlinedButton>(
            find.descendant(of: reuse, matching: find.byType(OutlinedButton)),
          )
          .onPressed,
      isNull,
    );
    expect(find.descendant(of: reuse, matching: _spinner), findsOneWidget);

    gate.complete();
    await tester.pumpAndSettle();
    expect(find.descendant(of: reuse, matching: _spinner), findsNothing);
  });

  testWidgets('a folder row shows the drop it is taking and refuses more', (
    tester,
  ) async {
    final folder = LibraryFolder(
      id: 'trips',
      name: 'Trips',
      collection: LibraryCollection.references,
      createdAt: DateTime.utc(2026),
      updatedAt: DateTime.utc(2026),
    );
    final gateway = _SlowGateway(
      _empty.copyWith(
        savedReferences: [_reference()],
        folders: <LibraryFolder>[folder],
      ),
    );
    final controller = _controller(gateway);
    addTearDown(controller.dispose);
    await _pump(
      tester,
      controller,
      FolderTree(
        scope: FolderScope.references(controller),
        selectedId: AppController.libraryFolderAll,
        onSelect: (_) {},
      ),
    );

    final row = find.byKey(const ValueKey('folder-row-trips'));
    expect(row, findsOneWidget);
    expect(find.descendant(of: row, matching: _spinner), findsNothing);

    final gate = Completer<void>();
    unawaited(controller.busy.run('folder', 'trips', () => gate.future));
    await tester.pump();

    expect(find.descendant(of: row, matching: _spinner), findsOneWidget);
    final target = tester.widget<DragTarget<LibraryDragData>>(
      find.descendant(
        of: row,
        matching: find.byType(DragTarget<LibraryDragData>),
      ),
    );
    expect(
      target.onWillAcceptWithDetails!(
        DragTargetDetails<LibraryDragData>(
          data: LibraryDragData(
            collection: LibraryCollection.references,
            storage: LibraryStorage.local,
            itemIds: const <String>{'photo'},
            label: 'Move 1 reference',
          ),
          offset: Offset.zero,
        ),
      ),
      isFalse,
    );

    gate.complete();
    await tester.pumpAndSettle();
    expect(find.descendant(of: row, matching: _spinner), findsNothing);
  });

  testWidgets('removing a folder waits behind its confirm key', (tester) async {
    final folder = LibraryFolder(
      id: 'trips',
      name: 'Trips',
      collection: LibraryCollection.references,
      createdAt: DateTime.utc(2026),
      updatedAt: DateTime.utc(2026),
    );
    final gateway = _SlowGateway(
      _empty.copyWith(folders: <LibraryFolder>[folder]),
    );
    final controller = _controller(gateway);
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      MaterialApp(
        theme: buildClawnsoleTheme(Brightness.light),
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () => confirmFolderDelete(
                context,
                FolderScope.references(controller),
                folder,
              ),
              child: const Text('Remove folder…'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Remove folder…'));
    await tester.pumpAndSettle();

    final gate = gateway.block();
    final confirm = find.byKey(const ValueKey('confirm-folder-remove'));
    await tester.tap(confirm);
    await tester.pump();

    expect(find.text('Removing…'), findsOneWidget);
    expect(_spinner, findsOneWidget);
    expect(controller.busy.isBusy('folder', 'trips'), isTrue);

    gate.complete();
    await tester.pumpAndSettle();
    expect(confirm, findsNothing);
    await tester.pump(const Duration(seconds: 6));
  });

  testWidgets('testing a provider key spins on Test, not on Save', (
    tester,
  ) async {
    final gateway = _SlowGateway(
      _empty.copyWith(connectedProviders: <String>{'runway'}),
    );
    final controller = _controller(gateway);
    addTearDown(controller.dispose);
    await _pump(
      tester,
      controller,
      ProvidersScreen(controller: controller),
      size: const Size(900, 3000),
    );

    final test = find.byKey(const ValueKey('provider-key-test-runway'));
    final save = find.byKey(const ValueKey('provider-key-save-runway'));
    await tester.ensureVisible(test);
    final gate = gateway.block();
    await tester.tap(test);
    await tester.pump();

    // The loader used to land on Save whichever key was pressed.
    expect(find.descendant(of: test, matching: _spinner), findsOneWidget);
    expect(find.descendant(of: save, matching: _spinner), findsNothing);
    expect(
      tester
          .widget<FilledButton>(
            find.descendant(of: save, matching: find.byType(FilledButton)),
          )
          .onPressed,
      isNull,
    );

    gate.complete();
    await tester.pumpAndSettle();
    expect(find.descendant(of: test, matching: _spinner), findsNothing);
    await tester.pump(const Duration(seconds: 6));
  });

  testWidgets('clearing history shows the work on its own tile', (
    tester,
  ) async {
    final gateway = _SlowGateway(_empty.copyWith(generations: [_film()]));
    final controller = _controller(gateway);
    addTearDown(controller.dispose);
    await _pump(
      tester,
      controller,
      SettingsScreen(controller: controller),
      size: const Size(900, 2600),
    );
    await tester.pumpAndSettle();

    final tile = find.byKey(const ValueKey('clear-Clear history'));
    await tester.ensureVisible(tile);
    await tester.tap(tile);
    await tester.pumpAndSettle();

    // The confirmation is asked before any loader appears.
    expect(_spinner, findsNothing);
    final gate = gateway.block();
    await tester.tap(find.text('Continue'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.descendant(of: tile, matching: _spinner), findsOneWidget);
    expect(tester.widget<ListTile>(tile).enabled, isFalse);

    gate.complete();
    await tester.pumpAndSettle();
    expect(find.descendant(of: tile, matching: _spinner), findsNothing);
    expect(controller.generations, isEmpty);
    await tester.pump(const Duration(seconds: 6));
  });
}
