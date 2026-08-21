import 'dart:typed_data';

import 'package:clawnsole/app/app_controller.dart';
import 'package:clawnsole/app/app_theme.dart';
import 'package:clawnsole/core/gateway.dart';
import 'package:clawnsole/core/models.dart';
import 'package:clawnsole/core/provider_catalog.dart';
import 'package:clawnsole/ui/providers_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('tapping the 10 sec header sorts cheapest-first and toggles', (
    tester,
  ) async {
    final gateway = _CostDeskGateway();
    final controller = await _controller(gateway);
    await _pump(tester, controller);

    await tester.ensureVisible(find.text('10 sec'));
    await tester.tap(find.text('10 sec'));
    await tester.pumpAndSettle();
    _expectPriceOrder(_sec10CellTexts(tester), ascending: true);

    await tester.tap(find.text('10 sec'));
    await tester.pumpAndSettle();
    _expectPriceOrder(_sec10CellTexts(tester), ascending: false);
    controller.dispose();
  });

  testWidgets('columns popover hides a column and persists the layout', (
    tester,
  ) async {
    final gateway = _CostDeskGateway();
    final controller = await _controller(gateway);
    await _pump(tester, controller);

    await tester.ensureVisible(find.byKey(const ValueKey('cost-desk-columns')));
    await tester.tap(find.byKey(const ValueKey('cost-desk-columns')));
    await tester.pumpAndSettle();
    expect(find.text('Modes'), findsNWidgets(2));

    await tester.tap(
      find.byKey(const ValueKey('cost-desk-column-toggle-modes')),
    );
    await tester.pumpAndSettle();

    expect(find.text('Modes'), findsOneWidget);
    final table = tester.widget<DataTable>(find.byType(DataTable));
    expect(table.columns.length, CostDeskColumn.values.length - 1);

    final saved = gateway.savedPreferences.last;
    expect(saved.costDeskColumns, isNotNull);
    expect(saved.costDeskColumns, isNot(contains('modes')));
    expect(saved.costDeskColumns, contains('provider'));
    final restored = AppPreferences.fromJson(saved.toJson());
    expect(restored.costDeskColumns, saved.costDeskColumns);
    controller.dispose();
  });

  testWidgets('provider model column renders the provider route id', (
    tester,
  ) async {
    final gateway = _CostDeskGateway();
    final controller = await _controller(gateway);
    await _pump(tester, controller);

    final routeId = publishedProviderPrices('bfl').first.model;
    await tester.ensureVisible(find.text(routeId));
    expect(find.text(routeId), findsOneWidget);
    controller.dispose();
  });
}

Future<AppController> _controller(_CostDeskGateway gateway) async {
  final controller = AppController(gateway: gateway);
  await controller.initialize();
  return controller;
}

Future<void> _pump(WidgetTester tester, AppController controller) async {
  await tester.binding.setSurfaceSize(const Size(1500, 2200));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(
    MaterialApp(
      theme: buildClawnsoleTheme(Brightness.light),
      home: Scaffold(
        body: AnimatedBuilder(
          animation: controller,
          builder: (context, _) => ProvidersScreen(controller: controller),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

List<String> _sec10CellTexts(WidgetTester tester) {
  final table = tester.widget<DataTable>(find.byType(DataTable));
  final index = CostDeskColumn.values.indexOf(CostDeskColumn.sec10);
  return table.rows
      .map((row) => (row.cells[index].child as Text).data!)
      .toList();
}

/// Priced rows must come first in the requested order; rows without a clip
/// price (dashes and per-megapixel-second quotes) stay last either way.
void _expectPriceOrder(List<String> texts, {required bool ascending}) {
  final priced = RegExp(r'^\$\d+\.\d\d$');
  final prices = <double>[];
  var seenUnpriced = false;
  for (final text in texts) {
    if (priced.hasMatch(text)) {
      expect(
        seenUnpriced,
        isFalse,
        reason: 'priced row after unpriced rows in $texts',
      );
      prices.add(double.parse(text.substring(1)));
    } else {
      seenUnpriced = true;
    }
  }
  expect(prices.length, greaterThan(1));
  final sorted = List<double>.of(prices)..sort();
  expect(prices, ascending ? sorted : sorted.reversed.toList());
}

class _CostDeskGateway implements AppGateway {
  final List<AppPreferences> savedPreferences = <AppPreferences>[];
  LocalSnapshot _snapshot = const LocalSnapshot(
    generations: <Generation>[],
    preferences: AppPreferences(),
    hasApiKey: true,
    connectedProviders: <String>{'bfl'},
    availableProviders: <String>{'bfl'},
    storage: StorageStats(path: 'memory', bytes: 0, records: 0),
  );

  @override
  bool get usesCompanion => false;

  @override
  bool get supportsPhotoLibrarySave => false;

  @override
  String get persistenceDescription => 'Memory';

  @override
  Future<LocalSnapshot> load() async => _snapshot;

  @override
  Future<LocalSnapshot> setPreferences(AppPreferences preferences) async {
    savedPreferences.add(preferences);
    _snapshot = _snapshot.copyWith(preferences: preferences);
    return _snapshot;
  }

  @override
  Future<LocalSnapshot> setApiKey(String value) async => _snapshot;

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
  Future<LocalSnapshot> deleteGeneration(String localId) async => _snapshot;

  @override
  Future<LocalSnapshot> clearHistory() async => _snapshot;

  @override
  Future<LocalSnapshot> clearPreferences() async => _snapshot;

  @override
  Future<LocalSnapshot> clearApiKey() async => _snapshot;

  @override
  Future<LocalSnapshot> clearAll() async => _snapshot;

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
