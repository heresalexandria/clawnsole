import 'dart:async';

import 'package:clawnsole/app/app_controller.dart';
import 'package:clawnsole/app/app_controller_characters.dart';
import 'package:clawnsole/app/app_theme.dart';
import 'package:clawnsole/core/gateway.dart';
import 'package:clawnsole/core/models.dart';
import 'package:clawnsole/ui/character_library.dart';
import 'package:clawnsole/ui/references_screen.dart';
import 'package:clawnsole/ui/section_tabs.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

SavedReference _saved(
  String name, {
  String? characterName,
  MediaReferenceKind kind = MediaReferenceKind.image,
  bool hidden = false,
}) => SavedReference(
  id: name,
  name: name,
  characterName: characterName,
  kind: kind,
  hidden: hidden,
  asset: AssetReference(
    kind: 'remote',
    value: 'https://example.invalid/$name',
    label: name,
  ),
  createdAt: DateTime.utc(2026),
  updatedAt: DateTime.utc(2026),
);

class _CharacterGateway implements AppGateway, ReferenceLibraryGateway {
  _CharacterGateway(List<SavedReference> references)
    : snapshot = LocalSnapshot(
        generations: const <Generation>[],
        preferences: const AppPreferences(),
        hasApiKey: false,
        storage: const StorageStats(path: 'memory', bytes: 0, records: 0),
        savedReferences: references,
      );

  LocalSnapshot snapshot;

  /// Blocks the next write so a test can watch the busy state.
  Completer<void>? gate;
  int writes = 0;

  @override
  bool get usesCompanion => false;

  @override
  bool get supportsPhotoLibrarySave => false;

  @override
  String get persistenceDescription => 'Memory';

  @override
  Future<LocalSnapshot> load() async => snapshot;

  @override
  Future<LocalSnapshot> saveReference(
    SavedReference reference, {
    String? source,
  }) async {
    await gate?.future;
    writes += 1;
    final next = <SavedReference>[...snapshot.savedReferences];
    final index = next.indexWhere((item) => item.id == reference.id);
    if (index >= 0) {
      next[index] = reference;
    } else {
      next.add(reference);
    }
    return snapshot = snapshot.copyWith(savedReferences: next);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

AppController _controller(_CharacterGateway gateway) =>
    AppController(gateway: gateway)
      ..selectedProviderId = 'runway'
      ..selectedModelId = 'gen4.5'
      ..loading = false
      ..snapshot = gateway.snapshot;

Future<void> _pump(WidgetTester tester, AppController controller) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: buildClawnsoleTheme(Brightness.light),
      home: Scaffold(
        body: SingleChildScrollView(
          child: CharacterLibraryView(controller: controller),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> _pumpReferencesDesk(
  WidgetTester tester,
  AppController controller,
) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: buildClawnsoleTheme(Brightness.light),
      home: Scaffold(body: ReferencesScreen(controller: controller)),
    ),
  );
  await tester.pumpAndSettle();
}

String? _characterOf(AppController controller, String id) => controller
    .savedReferences
    .where((item) => item.id == id)
    .first
    .characterName;

void main() {
  test('a character gathers every reference cast under its name', () {
    final gateway = _CharacterGateway(<SavedReference>[
      _saved('star.png', characterName: 'VINNY'),
      _saved('Vinny.mp4', kind: MediaReferenceKind.video),
      _saved('hero.png', characterName: 'ALEXANDRIA'),
      _saved('landscape.png'),
      _saved('gone.png', characterName: 'GHOST', hidden: true),
    ]);
    final controller = _controller(gateway);
    addTearDown(controller.dispose);

    final library = controller.characterLibrary;
    expect(library.map((entry) => entry.name).toList(), <String>[
      'ALEXANDRIA',
      'VINNY',
    ]);
    final vinny = library.last;
    // The assignment leads; the file already called VINNY is cast beside it,
    // which is exactly what Create maps the name to.
    expect(vinny.references.map((item) => item.id).toList(), <String>[
      'star.png',
    ]);
    expect(vinny.matched.map((item) => item.id).toList(), <String>[
      'Vinny.mp4',
    ]);
    expect(vinny.count, 2);
    expect(library.first.count, 1);
    // Hidden media is not cast, so it is not a character either.
    expect(library.any((entry) => entry.name == 'GHOST'), isFalse);
    expect(
      controller.unassignedCharacterReferences.map((item) => item.id).toList(),
      <String>['landscape.png', 'Vinny.mp4'],
    );
    expect(controller.characterFileNameFor(_saved('Vinny.mp4')), 'VINNY');
  });

  test('renaming rewrites every reference of the character, once', () async {
    final gateway = _CharacterGateway(<SavedReference>[
      _saved('star.png', characterName: 'VINCE'),
    ]);
    final controller = _controller(gateway);
    addTearDown(controller.dispose);

    expect(await controller.renameCharacter('VINCE', 'vinnie'), isTrue);

    expect(_characterOf(controller, 'star.png'), 'VINNIE');
    expect(controller.characterLibrary.single.name, 'VINNIE');
    // One notice for the batch, not "Reference updated." per write.
    expect(controller.notice, 'VINCE renamed to VINNIE across 1 reference.');
    expect(gateway.writes, 1);
  });

  test(
    'renaming onto a taken name is refused instead of half-merged',
    () async {
      final gateway = _CharacterGateway(<SavedReference>[
        _saved('star.png', characterName: 'VINCE'),
        _saved('lead.png', characterName: 'VINNIE'),
      ]);
      final controller = _controller(gateway);
      addTearDown(controller.dispose);

      expect(await controller.renameCharacter('VINCE', 'VINNIE'), isFalse);

      // A character name belongs to one reference, so merging two characters
      // cannot be written; nothing moves and the desk says why.
      expect(_characterOf(controller, 'star.png'), 'VINCE');
      expect(_characterOf(controller, 'lead.png'), 'VINNIE');
      expect(gateway.writes, 0);
      expect(controller.notice, contains('VINNIE already names “lead.png”'));
    },
  );

  test('assigning and unassigning move the name, never the media', () async {
    final gateway = _CharacterGateway(<SavedReference>[
      _saved('star.png'),
      _saved('lead.png'),
    ]);
    final controller = _controller(gateway);
    addTearDown(controller.dispose);

    expect(
      await controller.assignReferencesToCharacter('vinny', <String>[
        'star.png',
      ]),
      isTrue,
    );
    expect(_characterOf(controller, 'star.png'), 'VINNY');
    expect(controller.notice, '1 reference added to VINNY.');

    // The name is taken, so the second reference cannot also carry it.
    expect(
      await controller.assignReferencesToCharacter('VINNY', <String>[
        'lead.png',
      ]),
      isFalse,
    );
    expect(_characterOf(controller, 'lead.png'), anyOf(isNull, isEmpty));

    expect(await controller.unassignReference('star.png'), isTrue);
    expect(_characterOf(controller, 'star.png'), isEmpty);
    expect(controller.characterLibrary, isEmpty);
    expect(controller.savedReferences.length, 2);
    expect(controller.notice, '“star.png” is no longer VINNY.');
  });

  test('deleting a character clears its names and keeps the media', () async {
    final gateway = _CharacterGateway(<SavedReference>[
      _saved('star.png', characterName: 'VINNY'),
      _saved('Vinny.mp4', kind: MediaReferenceKind.video),
    ]);
    final controller = _controller(gateway);
    addTearDown(controller.dispose);

    expect(await controller.deleteCharacter('VINNY'), isTrue);

    expect(_characterOf(controller, 'star.png'), isEmpty);
    expect(controller.savedReferences.length, 2);
    expect(controller.characterLibrary, isEmpty);
    expect(
      controller.notice,
      'VINNY cleared from 1 reference. The media stays in References.',
    );
    // The file-named card still casts itself; only the assignment is gone.
    expect(
      controller.characterFileNameFor(controller.savedReferences[1]),
      'VINNY',
    );
  });

  test('one save renames, adds, and releases with a single notice', () async {
    final gateway = _CharacterGateway(<SavedReference>[
      _saved('star.png', characterName: 'VINCE'),
      _saved('lead.png'),
    ]);
    final controller = _controller(gateway);
    addTearDown(controller.dispose);

    expect(
      await controller.saveCharacter(
        name: 'VINNIE',
        previousName: 'VINCE',
        referenceIds: <String>['lead.png'],
      ),
      isTrue,
    );

    expect(_characterOf(controller, 'star.png'), isEmpty);
    expect(_characterOf(controller, 'lead.png'), 'VINNIE');
    expect(gateway.writes, 2);
    expect(
      controller.notice,
      '1 reference added to VINNIE, 1 reference released.',
    );
  });

  testWidgets('the empty desk explains what a character is', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1200, 1000));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final controller = _controller(_CharacterGateway(const <SavedReference>[]));
    addTearDown(controller.dispose);
    await _pump(tester, controller);

    expect(find.text('No characters yet.'), findsOneWidget);
    expect(find.byKey(const ValueKey('new-first-character')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('search narrows characters by name and by reference', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1200, 1000));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final controller = _controller(
      _CharacterGateway(<SavedReference>[
        _saved('star.png', characterName: 'VINNY'),
        _saved('hero.png', characterName: 'ALEXANDRIA'),
        _saved('landscape.png'),
      ]),
    );
    addTearDown(controller.dispose);
    await _pump(tester, controller);

    expect(find.byKey(const ValueKey('character-row-VINNY')), findsOneWidget);
    expect(
      find.byKey(const ValueKey('character-row-ALEXANDRIA')),
      findsOneWidget,
    );

    await tester.enterText(
      find.byKey(const ValueKey('character-library-search')),
      'vinny',
    );
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('character-row-VINNY')), findsOneWidget);
    expect(
      find.byKey(const ValueKey('character-row-ALEXANDRIA')),
      findsNothing,
    );
    expect(
      find.byKey(const ValueKey('unassigned-row-landscape.png')),
      findsNothing,
    );

    // A reference name finds its character too.
    await tester.enterText(
      find.byKey(const ValueKey('character-library-search')),
      'hero',
    );
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('character-row-ALEXANDRIA')),
      findsOneWidget,
    );
    expect(find.byKey(const ValueKey('character-row-VINNY')), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('an unassigned reference adopts the name its file implies', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1200, 1000));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final controller = _controller(
      _CharacterGateway(<SavedReference>[
        _saved('Vinny.mp4', kind: MediaReferenceKind.video),
      ]),
    );
    addTearDown(controller.dispose);
    await _pump(tester, controller);

    await tester.tap(find.byKey(const ValueKey('unassigned-adopt-Vinny.mp4')));
    await tester.pumpAndSettle();

    expect(_characterOf(controller, 'Vinny.mp4'), 'VINNY');
    expect(find.byKey(const ValueKey('character-row-VINNY')), findsOneWidget);
    // Let the notice time out, so the desk leaves no timer behind.
    await tester.pump(const Duration(seconds: 5));
    expect(tester.takeException(), isNull);
  });

  testWidgets('New character names a reference from the sheet', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1200, 1000));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final controller = _controller(
      _CharacterGateway(<SavedReference>[_saved('star.png')]),
    );
    addTearDown(controller.dispose);
    await _pump(tester, controller);

    await tester.tap(find.byKey(const ValueKey('new-character')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('character-name-field')),
      'vinny',
    );
    await tester.pumpAndSettle();

    // A character with no reference has nothing to cast, and says so.
    await tester.tap(find.byKey(const ValueKey('save-character')));
    await tester.pumpAndSettle();
    expect(find.textContaining('Choose a reference'), findsOneWidget);

    await tester.tap(
      find.byKey(const ValueKey('character-reference-star.png')),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('save-character')));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('character-name-field')), findsNothing);
    expect(_characterOf(controller, 'star.png'), 'VINNY');
    expect(find.byKey(const ValueKey('character-row-VINNY')), findsOneWidget);
    await tester.pump(const Duration(seconds: 5));
    expect(tester.takeException(), isNull);
  });

  testWidgets('the save key spins and locks while the write is pending', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1200, 1000));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final gateway = _CharacterGateway(<SavedReference>[
      _saved('star.png', characterName: 'VINCE'),
    ]);
    final controller = _controller(gateway);
    addTearDown(controller.dispose);
    await _pump(tester, controller);

    await tester.tap(find.byKey(const ValueKey('character-row-VINCE')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('character-name-field')),
      'VINNIE',
    );
    await tester.pumpAndSettle();

    final gate = Completer<void>();
    gateway.gate = gate;
    await tester.tap(find.byKey(const ValueKey('save-character')));
    await tester.pump();

    final save = find.byKey(const ValueKey('save-character'));
    expect(tester.widget<FilledButton>(save).onPressed, isNull);
    expect(
      find.descendant(
        of: save,
        matching: find.byType(CircularProgressIndicator),
      ),
      findsOneWidget,
    );

    gate.complete();
    gateway.gate = null;
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('character-name-field')), findsNothing);
    expect(_characterOf(controller, 'star.png'), 'VINNIE');
    await tester.pump(const Duration(seconds: 5));
    expect(tester.takeException(), isNull);
  });

  testWidgets('deleting a character from the row menu keeps the media', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1200, 1000));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final controller = _controller(
      _CharacterGateway(<SavedReference>[
        _saved('star.png', characterName: 'VINNY'),
      ]),
    );
    addTearDown(controller.dispose);
    await _pump(tester, controller);

    await tester.tap(find.byKey(const ValueKey('character-menu-VINNY')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('character-delete-VINNY')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('confirm-delete-character')));
    await tester.pumpAndSettle();

    expect(controller.characterLibrary, isEmpty);
    expect(controller.savedReferences.single.id, 'star.png');
    // The media is still saved: it simply drops back to Unassigned.
    expect(
      find.byKey(const ValueKey('unassigned-row-star.png')),
      findsOneWidget,
    );
    await tester.pump(const Duration(seconds: 5));
    expect(tester.takeException(), isNull);
  });

  testWidgets('the References desk opens its Characters tab from the rail', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1280, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final controller = _controller(
      _CharacterGateway(<SavedReference>[
        _saved('star.png', characterName: 'VINNY'),
        _saved('Vinny.mp4', kind: MediaReferenceKind.video),
        _saved('hero.png', characterName: 'ALEXANDRIA'),
        _saved('landscape.png'),
      ]),
    );
    addTearDown(controller.dispose);
    await _pumpReferencesDesk(tester, controller);

    // The desk opens on media, so the tab is a heading until it is used.
    expect(find.byType(CharacterLibraryView), findsNothing);
    final tab = find.byKey(const ValueKey('references-tab-characters'));
    expect(tab, findsOneWidget);
    // The pill counts characters, not the media cast under them: four saved
    // references, three of them cast, but only two names.
    expect(controller.characterLibrary, hasLength(2));
    expect(find.descendant(of: tab, matching: find.text('2')), findsOneWidget);

    await tester.tap(tab);
    await tester.pumpAndSettle();

    expect(controller.referencesTab, ReferencesTab.characters);
    expect(find.byType(CharacterLibraryView), findsOneWidget);
    expect(
      find.byKey(const ValueKey('reference-library-search')),
      findsNothing,
      reason: 'the media toolbar belongs to the media tab only',
    );

    await tester.tap(find.byKey(const ValueKey('references-tab-media')));
    await tester.pumpAndSettle();
    expect(controller.referencesTab, ReferencesTab.media);
    expect(find.byType(CharacterLibraryView), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a third tab still reaches the rail on a phone', (tester) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final controller = _controller(
      _CharacterGateway(<SavedReference>[
        _saved('star.png', characterName: 'VINNY'),
      ]),
    );
    addTearDown(controller.dispose);
    await _pumpReferencesDesk(tester, controller);

    // Three tabs are wider than 390 pt, so the rail's own horizontal scroll
    // carries the third one rather than overflowing the row.
    expect(
      find.descendant(
        of: find.byType(SectionTabRail),
        matching: find.byType(Scrollable),
      ),
      findsOneWidget,
    );
    final tab = find.byKey(const ValueKey('references-tab-characters'));
    await tester.ensureVisible(tab);
    await tester.pumpAndSettle();
    await tester.tap(tab);
    await tester.pumpAndSettle();

    expect(controller.referencesTab, ReferencesTab.characters);
    expect(find.byType(CharacterLibraryView), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
