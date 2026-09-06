import 'package:clawnsole/app/app_controller.dart';
import 'package:clawnsole/app/app_theme.dart';
import 'package:clawnsole/core/gateway.dart';
import 'package:clawnsole/core/models.dart';
import 'package:clawnsole/ui/create_screen.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
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
    testWidgets('the model trigger sits between the clear key and the counter '
        'at ${entry.key} width', (tester) async {
      final controller = await _director();
      await _pumpCreate(tester, controller, size: entry.value);

      expect(_trigger, findsOneWidget);
      expect(
        find.descendant(of: _trigger, matching: find.text(_label(controller))),
        findsOneWidget,
      );
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
      final semantics = tester.ensureSemantics();
      expect(
        tester
            .getSemantics(_trigger)
            .getSemanticsData()
            .flagsCollection
            .isButton,
        isTrue,
      );
      semantics.dispose();

      final header = find.byKey(const ValueKey('direction-header'));
      expect(
        tester.getRect(_trigger).right,
        lessThanOrEqualTo(tester.getRect(header).right),
      );
      expect(
        tester.getTopRight(_counter).dx,
        lessThanOrEqualTo(tester.getTopLeft(_expand).dx),
      );
      if (entry.key == 'phone') {
        // A phone's header row cannot hold a model name beside the format
        // dropdown and the counter, so the trigger drops to its own line
        // under the clear key, flush with the header's left edge, and takes
        // the width its label needs.
        expect(
          tester.getTopLeft(_trigger).dy,
          greaterThanOrEqualTo(tester.getBottomLeft(_clear).dy - 1),
        );
        expect(
          tester.getTopLeft(_trigger).dx,
          closeTo(tester.getTopLeft(header).dx, 1),
        );
        expect(tester.getRect(_trigger).width, greaterThan(200));
        expect(tester.getRect(_counter).width, greaterThan(64));
      } else {
        // Ordered left to right: format dropdown, clear key, trigger, counter,
        // expand key — all on one line, none of it overflowing.
        expect(
          tester.getTopLeft(_trigger).dx,
          greaterThanOrEqualTo(tester.getTopRight(_clear).dx),
        );
        expect(
          tester.getTopRight(_trigger).dx,
          lessThanOrEqualTo(tester.getTopLeft(_counter).dx),
        );
        // The counter keeps a readable share of the row beside the trigger.
        expect(tester.getRect(_counter).width, greaterThan(24));
        expect(tester.getRect(_trigger).width, greaterThanOrEqualTo(72));
        expect(
          tester.getCenter(_trigger).dy,
          closeTo(tester.getCenter(_clear).dy, 1),
        );
      }
      expect(tester.takeException(), isNull);
      controller.dispose();
    });
  }

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

  testWidgets('the trigger reads back the newly selected model and provider', (
    tester,
  ) async {
    final controller = await _director();
    await _pumpCreate(tester, controller, size: _desktop);

    await controller.selectProviderModel('artcraft', 'seedance_2p0');
    await tester.pumpAndSettle();
    expect(
      find.descendant(
        of: _trigger,
        matching: find.text('Seedance 2.0 · ArtCraft'),
      ),
      findsOneWidget,
    );
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
    expect(
      find.descendant(of: inEditor, matching: find.text(_label(controller))),
      findsOneWidget,
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
