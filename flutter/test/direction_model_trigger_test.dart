import 'package:clawnsole/app/app_controller.dart';
import 'package:clawnsole/app/app_theme.dart';
import 'package:clawnsole/core/gateway.dart';
import 'package:clawnsole/core/models.dart';
import 'package:clawnsole/ui/create_screen.dart';
import 'package:clawnsole/ui/prompt_character_counter.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

const Size _desktop = Size(1400, 1000);
const Size _phone = Size(390, 844);

Finder get _trigger => find.byKey(const ValueKey('direction-model-trigger'));
Finder get _clear => find.byKey(const ValueKey('prompt-clear-button'));
Finder get _counter => find.byKey(const ValueKey('prompt-character-limit'));
Finder get _expand => find.byKey(const ValueKey('prompt-fullscreen-button'));
Finder get _picker => find.byKey(const ValueKey('provider-model-picker'));

String _label(AppController controller) =>
    '${controller.selectedModel.label} · ${controller.selectedProvider.name}';

/// The label actually painted in the trigger, and whether it had to clip.
/// First of the two paragraphs under the button — the chevron is the other.
RenderParagraph _shown(WidgetTester tester, [Finder? within]) =>
    tester.renderObject<RenderParagraph>(
      find
          .descendant(of: within ?? _trigger, matching: find.byType(RichText))
          .first,
    );

String _shownText(WidgetTester tester, [Finder? within]) =>
    _shown(tester, within).text.toPlainText();

/// The real type, so the width the trigger measures is the width an iPhone
/// draws. Ahem's square glyphs would make every reading fall back at once.
Future<void> _loadType(WidgetTester tester) => tester.runAsync(() async {
  final font = FontLoader('DM Sans')
    ..addFont(rootBundle.load('assets/fonts/DMSans-400.ttf'))
    ..addFont(rootBundle.load('assets/fonts/DMSans-500.ttf'))
    ..addFont(rootBundle.load('assets/fonts/DMSans-700.ttf'));
  await font.load();
});

Future<AppController> _director() async {
  final controller = AppController(
    gateway: _MemoryGateway(
      const LocalSnapshot(
        generations: <Generation>[],
        preferences: AppPreferences(),
        hasApiKey: false,
        storage: StorageStats(path: 'memory', bytes: 0, records: 0),
      ),
    ),
  );
  await controller.initialize();
  return controller;
}

Future<void> _pumpCreate(
  WidgetTester tester,
  AppController controller, {
  required Size size,
}) async {
  await _loadType(tester);
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
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
}

void main() {
  for (final entry in <String, Size>{
    'desktop': _desktop,
    'phone': _phone,
  }.entries) {
    testWidgets('the model trigger keeps one row between the clear key and '
        'the counter at ${entry.key} width', (tester) async {
      final controller = await _director();
      await _pumpCreate(tester, controller, size: entry.value);

      expect(_trigger, findsOneWidget);
      expect(
        find.descendant(
          of: _trigger,
          matching: find.byIcon(Icons.arrow_drop_down_rounded),
        ),
        findsOneWidget,
      );
      expect(
        tester
            .widget<Tooltip>(
              find.ancestor(of: _trigger, matching: find.byType(Tooltip)),
            )
            .message,
        'Change model',
      );
      // A shortened reading still answers with the provider.
      final semantics = tester.ensureSemantics();
      final data = tester.getSemantics(_trigger).getSemanticsData();
      expect(data.flagsCollection.isButton, isTrue);
      expect(data.label, _label(controller));
      semantics.dispose();

      final header = find.byKey(const ValueKey('direction-header'));
      // Ordered left to right on ONE line: format picker, clear key, trigger,
      // counter, expand key — at a phone's width as much as a desk's.
      expect(
        tester.getTopLeft(_trigger).dx,
        greaterThanOrEqualTo(tester.getTopRight(_clear).dx),
      );
      expect(
        tester.getTopRight(_trigger).dx,
        lessThanOrEqualTo(tester.getTopLeft(_counter).dx),
      );
      expect(
        tester.getCenter(_trigger).dy,
        closeTo(tester.getCenter(_clear).dy, 1),
      );
      expect(
        tester.getCenter(_counter).dy,
        closeTo(tester.getCenter(_clear).dy, 1),
      );
      // Nothing wrapped: the row is no taller than one key.
      expect(tester.getRect(header).height, lessThanOrEqualTo(48));
      expect(
        tester.getRect(_expand).right,
        lessThanOrEqualTo(tester.getRect(header).right + .5),
      );
      expect(
        tester.getTopRight(_counter).dx,
        lessThanOrEqualTo(tester.getTopLeft(_expand).dx),
      );
      // Both readouts keep a share worth reading.
      expect(tester.getRect(_trigger).width, greaterThanOrEqualTo(56));
      expect(tester.getRect(_counter).width, greaterThanOrEqualTo(44));
      // The trigger names the model only; the footer readout carries the
      // provider, so the row spends its width on the model name.
      expect(_shownText(tester), controller.selectedModel.label);
      expect(_shownText(tester), isNot(contains('·')));
      expect(_shown(tester).didExceedMaxLines, isFalse);

      final limit = controller.promptCharacterLimit;
      if (entry.key == 'phone') {
        // A phone row's counter takes its compact reading ("0 / 10k").
        expect(
          find.descendant(
            of: _counter,
            matching: find.text(
              '0 / ${PromptCharacterCounter.shortLimit(limit)}',
            ),
          ),
          findsOneWidget,
        );
        // The format picker is sized to its own words, so "Plaintext" and
        // "Screenplay" are drawn unscaled.
        final format = find.byKey(const ValueKey('prompt-format-picker'));
        final word = find.descendant(
          of: format,
          matching: find.text('Plaintext'),
        );
        expect(
          tester.getRect(word).width,
          closeTo(tester.renderObject<RenderParagraph>(word).size.width, .5),
        );
      } else {
        expect(
          find.descendant(of: _counter, matching: find.text('0 / $limit')),
          findsOneWidget,
        );
      }
      expect(tester.takeException(), isNull);
      controller.dispose();
    });
  }

  testWidgets('a phone spells a long model name whole on one row', (
    tester,
  ) async {
    // The owner's own case: Krea's Seedance 2.5 on a 390pt iPhone.
    final controller = await _director();
    await controller.selectProviderModel('krea', 'bytedance/seedance-2-5');
    expect(controller.selectedModel.label, 'Seedance 2.5');

    for (final size in <Size>[_phone, const Size(430, 932)]) {
      await _pumpCreate(tester, controller, size: size);
      expect(_shownText(tester), 'Seedance 2.5');
      expect(_shown(tester).didExceedMaxLines, isFalse);
      expect(
        tester.getRect(find.byKey(const ValueKey('direction-header'))).height,
        lessThanOrEqualTo(48),
      );
    }
    expect(tester.takeException(), isNull);
    controller.dispose();
  });

  testWidgets('a name the row cannot hold clips instead of wrapping', (
    tester,
  ) async {
    final controller = await _director();
    // The longest labels in the catalog belong to Atlas Cloud's routes.
    await controller.selectProviderModel(
      'atlas',
      'bytedance/seedance-2.5/image-to-video',
    );
    expect(controller.selectedModel.label, contains('·'));

    await _pumpCreate(tester, controller, size: const Size(320, 700));
    expect(_shownText(tester), controller.selectedModel.label);
    expect(
      tester.getRect(find.byKey(const ValueKey('direction-header'))).height,
      lessThanOrEqualTo(48),
    );
    final semantics = tester.ensureSemantics();
    expect(
      tester.getSemantics(_trigger).getSemanticsData().label,
      _label(controller),
    );
    semantics.dispose();
    expect(tester.takeException(), isNull);
    controller.dispose();
  });

  testWidgets(
    'tapping the trigger opens the shared provider and model picker',
    (tester) async {
      final controller = await _director();
      await _pumpCreate(tester, controller, size: _desktop);

      expect(_picker, findsNothing);
      await tester.tap(_trigger);
      await tester.pumpAndSettle();
      expect(_picker, findsOneWidget);
      expect(tester.takeException(), isNull);
      controller.dispose();
    },
  );

  testWidgets('the trigger reads back the newly selected model', (
    tester,
  ) async {
    final controller = await _director();
    await _pumpCreate(tester, controller, size: _desktop);

    await controller.selectProviderModel('artcraft', 'seedance_2p0');
    await tester.pumpAndSettle();
    expect(_shownText(tester), 'Seedance 2.0');
    final semantics = tester.ensureSemantics();
    expect(
      tester.getSemantics(_trigger).getSemanticsData().label,
      'Seedance 2.0 · ArtCraft',
    );
    semantics.dispose();
    expect(tester.takeException(), isNull);
    controller.dispose();
  });

  testWidgets('the fullscreen editor carries the same trigger', (tester) async {
    final controller = await _director();
    await _pumpCreate(tester, controller, size: _phone);

    await tester.tap(_expand);
    await tester.pumpAndSettle();
    final editor = find.byKey(const ValueKey('prompt-fullscreen-editor'));
    expect(editor, findsOneWidget);
    final inEditor = find.descendant(of: editor, matching: _trigger);
    expect(inEditor, findsOneWidget);
    // Same one-row rule inside the editor: the model name alone, with the
    // provider kept in the tooltip and the semantic label.
    expect(_shownText(tester, inEditor), controller.selectedModel.label);
    expect(_shown(tester, inEditor).didExceedMaxLines, isFalse);
    expect(
      tester
          .widget<Tooltip>(
            find.ancestor(of: inEditor, matching: find.byType(Tooltip)),
          )
          .message,
      'Change model',
    );

    await tester.tap(inEditor);
    await tester.pumpAndSettle();
    expect(_picker, findsOneWidget);
    expect(tester.takeException(), isNull);
    controller.dispose();
  });
}

class _MemoryGateway implements AppGateway {
  _MemoryGateway(this.snapshot);

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
