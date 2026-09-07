import 'dart:async';

import 'package:clawnsole/app/app_controller.dart';
import 'package:clawnsole/app/app_theme.dart';
import 'package:clawnsole/core/gateway.dart';
import 'package:clawnsole/core/models.dart';
import 'package:clawnsole/ui/create_screen.dart';
import 'package:clawnsole/ui/hardware_button.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

final Finder _generateKey = find.byKey(const ValueKey<String>('generate-key'));

HardwareLitButton _key(WidgetTester tester) =>
    tester.widget<HardwareLitButton>(_generateKey);

/// The transport key says what the console is doing. While a submission is
/// in flight it reads SUBMITTING — lit and inert, as it has always been —
/// and it must not change width doing it: the key hugs its own legend, so
/// the shorter reading would shrink it under the finger that pressed it.
void main() {
  testWidgets('the Generate key reads SUBMITTING while a submission is in '
      'flight and keeps its width', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1400, 1000));
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.binding.setSurfaceSize(null);
    });
    final gate = Completer<void>();
    final controller = AppController(gateway: _BlockingGateway(gate));
    await controller.initialize();
    controller
      ..selectedProviderId = 'runway'
      ..selectedModelId = 'seedance2_5';
    controller.updateForm((form) => form.prompt = 'A slow tide over basalt.');

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

    expect(find.text('GENERATE VIDEO'), findsOneWidget);
    expect(find.text('SUBMITTING'), findsNothing);
    final resting = tester.getSize(_generateKey);
    expect(_key(tester).onPressed, isNotNull);

    final submission = controller.submit(
      providerRetentionRiskAcknowledged: true,
    );
    for (
      var attempt = 0;
      attempt < 20 && !controller.submitting;
      attempt += 1
    ) {
      await tester.pump();
    }
    expect(controller.submitting, isTrue);
    await tester.pump();

    expect(find.text('SUBMITTING'), findsOneWidget);
    expect(find.text('GENERATE VIDEO'), findsNothing);
    // Lit and inert, exactly as before — only the legend changed.
    expect(_key(tester).lit, isTrue);
    expect(_key(tester).onPressed, isNull);
    // The reserved width holds the key still through the shorter reading.
    expect(tester.getSize(_generateKey), resting);

    gate.completeError(StateError('the provider refused the job'));
    await submission;
    for (var attempt = 0; attempt < 40 && controller.submitting; attempt += 1) {
      await tester.pump();
    }
    expect(controller.submitting, isFalse);
    await tester.pump();

    expect(find.text('GENERATE VIDEO'), findsOneWidget);
    expect(find.text('SUBMITTING'), findsNothing);
    expect(tester.getSize(_generateKey), resting);
    // Disposal cancels the controller's poll, credit, and notice timers
    // before the binding checks for stragglers.
    controller.dispose();
  });
}

/// Holds `submit` open so the console can be read mid-flight.
class _BlockingGateway implements AppGateway {
  _BlockingGateway(this.gate);

  final Completer<void> gate;

  LocalSnapshot snapshot = const LocalSnapshot(
    generations: <Generation>[],
    preferences: AppPreferences(provider: 'runway', model: 'seedance2_5'),
    hasApiKey: true,
    connectedProviders: <String>{'runway'},
    availableProviders: <String>{'runway'},
    storage: StorageStats(path: 'memory', bytes: 0, records: 0),
  );

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
  Future<Generation> submit(GenerationSubmission submission) async {
    await gate.future;
    return submission.record;
  }

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
