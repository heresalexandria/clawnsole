import 'package:clawnsole/app/app_controller.dart';
import 'package:clawnsole/app/app_theme.dart';
import 'package:clawnsole/core/gateway.dart';
import 'package:clawnsole/core/models.dart';
import 'package:clawnsole/ui/create_screen.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

const _snapshot = LocalSnapshot(
  generations: <Generation>[],
  preferences: AppPreferences(),
  hasApiKey: false,
  storage: StorageStats(path: 'memory', bytes: 0, records: 0),
);

const _pickerKey = ValueKey<String>('provider-model-picker');
const _searchKey = ValueKey<String>('provider-model-search');
const _artcraftHeading = ValueKey<String>('provider-model-heading-artcraft');
const _artcraftOption = ValueKey<String>(
  'provider-model-option-artcraft-seedance_2p0',
);

Future<AppController> _studio() async {
  final controller = AppController(gateway: _MemoryGateway(_snapshot));
  await controller.initialize();
  return controller;
}

Widget _host(AppController controller) => MaterialApp(
  theme: buildClawnsoleTheme(Brightness.light),
  home: Scaffold(
    body: AnimatedBuilder(
      animation: controller,
      builder: (context, _) => CreateScreen(controller: controller),
    ),
  ),
);

/// Renders the Create screen at desk width and tears the surface back down.
Future<void> _useDeskSurface(WidgetTester tester) async {
  await tester.binding.setSurfaceSize(const Size(1400, 1000));
  addTearDown(() async {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.binding.setSurfaceSize(null);
  });
}

Future<void> _openPicker(WidgetTester tester) async {
  await tester.tap(find.byTooltip('Choose provider and model'));
  await tester.pumpAndSettle();
}

/// Whether the picker's search field currently holds the keyboard.
bool _searchHasFocus(WidgetTester tester) => tester
    .widget<EditableText>(
      find.descendant(
        of: find.byKey(_searchKey),
        matching: find.byType(EditableText),
      ),
    )
    .focusNode
    .hasFocus;

void main() {
  testWidgets('the plaque opens the shared picker and applies a choice', (
    tester,
  ) async {
    await _useDeskSurface(tester);
    final controller = await _studio();
    await tester.pumpWidget(_host(controller));
    await tester.pumpAndSettle();

    expect(find.byKey(_pickerKey), findsNothing);
    await _openPicker(tester);
    expect(find.byKey(_pickerKey), findsOneWidget);
    expect(find.byKey(_searchKey), findsOneWidget);

    await tester.ensureVisible(find.byKey(_artcraftHeading));
    await tester.tap(find.byKey(_artcraftHeading));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byKey(_artcraftOption));
    await tester.tap(find.byKey(_artcraftOption));
    await tester.pumpAndSettle();

    // The dialog closes and the choice is already live.
    expect(find.byKey(_pickerKey), findsNothing);
    expect(controller.selectedProviderId, 'artcraft');
    expect(controller.selectedModelId, 'seedance_2p0');
    controller.dispose();
  });

  testWidgets('desktop lands in the search field and touch platforms do not', (
    tester,
  ) async {
    await _useDeskSurface(tester);
    try {
      for (final platform in <TargetPlatform>[
        TargetPlatform.macOS,
        TargetPlatform.iOS,
      ]) {
        debugDefaultTargetPlatformOverride = platform;
        final controller = await _studio();
        await tester.pumpWidget(_host(controller));
        await tester.pumpAndSettle();
        await _openPicker(tester);

        expect(
          _searchHasFocus(tester),
          platform == TargetPlatform.macOS,
          reason:
              'a desk lands in the field ready to type; a phone would bury '
              'the list under its keyboard',
        );

        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pumpAndSettle();
        controller.dispose();
      }
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });

  testWidgets('folded sections are remembered per studio', (tester) async {
    await _useDeskSurface(tester);
    final controller = await _studio();
    await tester.pumpWidget(_host(controller));
    await tester.pumpAndSettle();

    // ArtCraft is not the selected provider, so it opens folded.
    await _openPicker(tester);
    expect(find.byKey(_artcraftOption), findsNothing);
    await tester.ensureVisible(find.byKey(_artcraftHeading));
    await tester.tap(find.byKey(_artcraftHeading));
    await tester.pumpAndSettle();
    expect(find.byKey(_artcraftOption), findsOneWidget);

    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(find.byKey(_pickerKey), findsNothing);

    // Reopening finds the section exactly as it was left.
    await _openPicker(tester);
    expect(find.byKey(_artcraftOption), findsOneWidget);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
    controller.dispose();

    // A different studio keeps its own memory: nothing carries over.
    final other = await _studio();
    await tester.pumpWidget(_host(other));
    await tester.pumpAndSettle();
    await _openPicker(tester);
    expect(find.byKey(_artcraftOption), findsNothing);
    other.dispose();
  });

  testWidgets('the close key dismisses the picker and changes nothing', (
    tester,
  ) async {
    await _useDeskSurface(tester);
    final controller = await _studio();
    await tester.pumpWidget(_host(controller));
    await tester.pumpAndSettle();
    final provider = controller.selectedProviderId;
    final model = controller.selectedModelId;

    await _openPicker(tester);
    expect(find.byKey(_pickerKey), findsOneWidget);
    await tester.tap(find.byTooltip('Close'));
    await tester.pumpAndSettle();

    expect(find.byKey(_pickerKey), findsNothing);
    expect(controller.selectedProviderId, provider);
    expect(controller.selectedModelId, model);
    controller.dispose();
  });
}

/// The smallest studio store the picker needs: everything lives in memory and
/// preference writes land at once.
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
