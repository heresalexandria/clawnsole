import 'package:clawnsole/app/app_controller.dart';
import 'package:clawnsole/app/app_theme.dart';
import 'package:clawnsole/core/gateway.dart';
import 'package:clawnsole/core/models.dart';
import 'package:clawnsole/ui/cast_row.dart';
import 'package:clawnsole/ui/create_screen.dart';
import 'package:clawnsole/ui/media_thumbnail.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

SavedReference _saved(
  String name, {
  String? characterName,
  MediaReferenceKind kind = MediaReferenceKind.image,
}) => SavedReference(
  id: name,
  name: name,
  characterName: characterName,
  kind: kind,
  asset: AssetReference(
    kind: 'remote',
    value: 'https://example.invalid/$name',
    label: name,
  ),
  createdAt: DateTime.utc(2026),
  updatedAt: DateTime.utc(2026),
);

AppController _controller({
  List<SavedReference> references = const [],
  String provider = 'artcraft',
  String model = 'seedance_2p5',
}) => AppController(gateway: _CastGateway())
  ..selectedProviderId = provider
  ..selectedModelId = model
  ..loading = false
  ..snapshot = LocalSnapshot(
    generations: const [],
    preferences: const AppPreferences(),
    hasApiKey: false,
    storage: const StorageStats(path: 'memory', bytes: 0, records: 0),
    savedReferences: references,
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

Finder _tile(String name) => find.widgetWithText(CheckboxListTile, '@$name');

void main() {
  test('a pasted casting line lands in the cast, not the direction', () {
    final controller = _controller(references: [_saved('portrait.png')]);
    addTearDown(controller.dispose);

    controller.updateForm(
      (form) => form.prompt = 'A stranger waits.\n\nHERO: @portrait.png',
    );

    expect(controller.form.prompt, 'A stranger waits.');
    expect(controller.form.characterMappings, {
      'HERO': ['portrait.png'],
    });
    expect(
      controller.promptWithCast,
      'A stranger waits.\n\nHERO: @portrait.png',
    );
    expect(controller.generationPrompt, controller.promptWithCast);
  });

  test('removing a reference prunes it out of every cast entry', () {
    final controller = _controller();
    addTearDown(controller.dispose);
    controller.form.references = const [
      MediaReferenceDraft(
        id: 'one',
        label: 'one.png',
        promptName: 'one.png',
        kind: MediaReferenceKind.image,
        source: 'https://example.invalid/one.png',
      ),
    ];
    controller.form.characterMappings
      ..['HERO'] = ['one.png', 'two.png']
      ..['EXTRA'] = ['one.png'];

    controller.removeReference('one');

    expect(controller.form.characterMappings, {
      'HERO': ['two.png'],
    });
    expect(controller.form.screenplayLinkedCharacters, contains('EXTRA'));
  });

  test('renaming a draft reference follows into the cast', () async {
    final controller = _controller();
    addTearDown(controller.dispose);
    controller.form.references = const [
      MediaReferenceDraft(
        id: 'one',
        label: 'one.png',
        promptName: 'one.png',
        kind: MediaReferenceKind.image,
        source: 'https://example.invalid/one.png',
      ),
    ];
    controller.form.characterMappings['HERO'] = ['one.png'];

    expect(await controller.renameDraftReference('one', 'lead.png'), isTrue);

    expect(controller.form.characterMappings, {
      'HERO': ['lead.png'],
    });
  });

  testWidgets('the character counter measures the appended cast', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1200, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final controller = _controller(
      references: [_saved('portrait.png')],
      provider: 'runway',
      model: 'gen4.5',
    );
    addTearDown(controller.dispose);
    controller.form.prompt = 'A bird';
    await _pumpCreate(tester, controller);
    expect(find.text('6 / 1000'), findsOneWidget);

    controller.updateForm(
      (form) => form.characterMappings['HERO'] = ['portrait.png'],
    );
    await tester.pumpAndSettle();
    // 'A bird' + blank line + 'HERO: @portrait.png'.
    expect(find.text('27 / 1000'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('the cast row appears only once a character holds media', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1200, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final controller = _controller(references: [_saved('portrait.png')]);
    addTearDown(controller.dispose);
    await _pumpCreate(tester, controller);
    expect(find.byType(CastRow), findsNothing);
    expect(find.text('CAST'), findsNothing);

    controller.updateForm(
      (form) => form.characterMappings['HERO'] = ['portrait.png'],
    );
    await tester.pumpAndSettle();
    final chip = find.byKey(const ValueKey('cast-chip-HERO'));
    expect(chip, findsOneWidget);
    expect(find.text('CAST'), findsOneWidget);
    expect(
      find.descendant(of: chip, matching: find.byType(MediaThumbnail)),
      findsOneWidget,
    );
    // The strip stays out of the way of the heading-to-Generate fold.
    expect(tester.getSize(find.byType(CastRow)).height, lessThan(56));

    await tester.tap(chip);
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<TextField>(
            find.byKey(const ValueKey('mapping-character-name')),
          )
          .controller!
          .text,
      'HERO',
    );
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets('Add character in the cast row opens an empty editor', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1200, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final controller = _controller(references: [_saved('portrait.png')]);
    addTearDown(controller.dispose);
    controller.form.characterMappings['HERO'] = ['portrait.png'];
    await _pumpCreate(tester, controller);

    await tester.tap(find.byKey(const ValueKey('cast-add-character')));
    await tester.pumpAndSettle();
    expect(find.text('Add character'), findsWidgets);
    expect(
      tester
          .widget<TextField>(
            find.byKey(const ValueKey('mapping-character-name')),
          )
          .controller!
          .text,
      isEmpty,
    );
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets('each cast chip recasts and uncasts in place', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1200, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final controller = _controller(references: [_saved('portrait.png')]);
    addTearDown(controller.dispose);
    controller.form.characterMappings['HERO'] = ['portrait.png'];
    await _pumpCreate(tester, controller);

    await tester.tap(find.byKey(const ValueKey('cast-edit-HERO')));
    await tester.pumpAndSettle();
    expect(find.text('Edit character'), findsOneWidget);
    expect(
      tester
          .widget<TextField>(
            find.byKey(const ValueKey('mapping-character-name')),
          )
          .controller!
          .text,
      'HERO',
    );
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('cast-remove-HERO')));
    await tester.pumpAndSettle();
    expect(controller.form.characterMappings, isEmpty);
    expect(find.byType(CastRow), findsNothing);
    expect(controller.notice, contains('HERO removed from the cast'));
    // Uncasting is an explicit choice: typing must not cast HERO again.
    controller.updateForm((form) => form.prompt = 'HERO waits.');
    await tester.pumpAndSettle();
    expect(controller.characterMappingReferences('HERO'), isEmpty);
    expect(find.byType(CastRow), findsNothing);
    await tester.pump(const Duration(seconds: 5));
    expect(tester.takeException(), isNull);
  });

  testWidgets('the chooser searches, filters by kind and leads with matches', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1000, 1400));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final controller = _controller(
      references: [
        _saved('Vinny.mp4', kind: MediaReferenceKind.video),
        _saved('star.png', characterName: 'VINNY'),
        _saved('other.png'),
      ],
    );
    addTearDown(controller.dispose);
    controller.form.characterMappings['HERO'] = ['other.png'];
    await _pumpCreate(tester, controller);
    await tester.tap(find.byKey(const ValueKey('cast-add-character')));
    await tester.pumpAndSettle();

    await tester.enterText(
      find.byKey(const ValueKey('mapping-character-name')),
      'VINNY',
    );
    await tester.pump();
    // Both a matching character name and a matching file name lead the list.
    expect(find.text('MATCHES VINNY'), findsOneWidget);
    final unrelated = tester.getTopLeft(find.text('@other.png')).dy;
    expect(tester.getTopLeft(find.text('@Vinny.mp4')).dy, lessThan(unrelated));
    expect(tester.getTopLeft(find.text('@star.png')).dy, lessThan(unrelated));
    expect(
      tester.widget<CheckboxListTile>(_tile('Vinny.mp4')).value,
      isTrue,
      reason: 'matching media stays preselected for a new character',
    );
    expect(tester.widget<CheckboxListTile>(_tile('other.png')).value, isFalse);

    await tester.tap(find.byKey(const ValueKey('mapping-kind-video')));
    await tester.pumpAndSettle();
    expect(_tile('Vinny.mp4'), findsOneWidget);
    expect(_tile('star.png'), findsNothing);
    expect(_tile('other.png'), findsNothing);

    await tester.tap(find.byKey(const ValueKey('mapping-kind-all')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('mapping-reference-search')),
      'oth',
    );
    await tester.pumpAndSettle();
    expect(_tile('other.png'), findsOneWidget);
    expect(_tile('Vinny.mp4'), findsNothing);
    expect(_tile('star.png'), findsNothing);

    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });
}

class _CastGateway implements AppGateway {
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
