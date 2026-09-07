import 'package:clawnsole/app/app_controller.dart';
import 'package:clawnsole/app/app_theme.dart';
import 'package:clawnsole/core/gateway.dart';
import 'package:clawnsole/core/models.dart';
import 'package:clawnsole/ui/create_screen.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Reference videos and audio cost seconds as well as slots. Models publish
/// both budgets; the composer shows both and refuses an add that would spend
/// more seconds than the model accepts.
void main() {
  group('the controller resolves and spends a seconds budget', () {
    test('a model publishes its seconds budget per kind', () {
      final controller = _director();
      expect(controller.referenceSecondsLimit(MediaReferenceKind.video), 30);
      expect(controller.referenceSecondsLimit(MediaReferenceKind.audio), 30);
      // Images are counted, never timed.
      expect(
        controller.referenceSecondsLimit(MediaReferenceKind.image),
        isNull,
      );

      controller.selectedModelId = 'seedance2';
      expect(controller.referenceSecondsLimit(MediaReferenceKind.video), 15);
      expect(controller.referenceSecondsLimit(MediaReferenceKind.audio), 15);
      controller.dispose();
    });

    test('a by-resolution override wins over the model-wide budget', () {
      final controller = _director(provider: 'ltx', model: 'ltx-2-3-pro');
      controller.form.resolution = 'hd';
      expect(controller.referenceSecondsLimit(MediaReferenceKind.audio), 20);
      controller.form.resolution = 'qhd';
      expect(controller.referenceSecondsLimit(MediaReferenceKind.audio), 10);
      controller.form.resolution = '4k';
      expect(controller.referenceSecondsLimit(MediaReferenceKind.audio), 10);
      controller.dispose();
    });

    test('used seconds sum the measured clips and flag the rest', () {
      final controller = _director();
      _attachVideos(controller, <double?>[12, null, 6]);
      expect(controller.referenceSecondsUsed(MediaReferenceKind.video), 18);
      expect(controller.referenceSecondsPending(MediaReferenceKind.video), 1);
      expect(controller.referenceSecondsUsed(MediaReferenceKind.audio), 0);
      expect(
        controller.referenceSecondsOverBudget(MediaReferenceKind.video),
        isFalse,
      );
      controller.dispose();
    });

    test('a clip that would overrun the budget is refused by name', () {
      final controller = _director();
      _attachVideos(controller, <double?>[12, 18]);
      expect(
        controller
            .checkReferenceBudget(MediaReferenceKind.video, durationSeconds: 12)
            .refusal,
        'Seedance 2.5 accepts up to 30 s of reference video; that clip would '
        'bring it to 42 s.',
      );
      // Exactly full still fits; a measured clip is never refused for
      // rounding noise off a container header.
      expect(
        controller
            .checkReferenceBudget(
              MediaReferenceKind.video,
              durationSeconds: 0.0004,
            )
            .allowed,
        isTrue,
      );
      controller.dispose();
    });

    test('a batch claims seconds in order', () {
      final controller = _director();
      _attachVideos(controller, <double?>[20]);
      // The first candidate fits the remaining 10 s; the second does not.
      expect(
        controller
            .checkReferenceBudget(MediaReferenceKind.video, durationSeconds: 8)
            .allowed,
        isTrue,
      );
      expect(
        controller
            .checkReferenceBudget(
              MediaReferenceKind.video,
              durationSeconds: 8,
              pendingCount: 1,
              pendingSeconds: 8,
            )
            .refusal,
        contains('would bring it to 36 s'),
      );
      controller.dispose();
    });

    test('an audio clip under the model minimum is refused', () {
      final controller = _director(model: 'grok_imagine_1_5');
      expect(
        controller
            .checkReferenceBudget(MediaReferenceKind.audio, durationSeconds: 2)
            .refusal,
        'Grok Imagine 1.5 needs each reference audio clip to be at least 3 s.',
      );
      controller.dispose();
    });

    test('a model switch that shrinks the budget blocks Generate', () {
      final controller = _director();
      controller.form.prompt = 'A slow tide over basalt.';
      _attachVideos(controller, <double?>[12, 12]);
      expect(controller.validate(), isNull);
      expect(
        controller.referenceSecondsOverBudget(MediaReferenceKind.video),
        isFalse,
      );

      controller.selectedModelId = 'seedance2';
      expect(
        controller.referenceSecondsOverBudget(MediaReferenceKind.video),
        isTrue,
      );
      expect(
        controller.validate(),
        'Seedance 2.0 accepts up to 15 s of reference video; the attached '
        'clips come to 24 s.',
      );
      controller.dispose();
    });

    test('a duration measured after the add says so once', () {
      final controller = _director();
      _attachVideos(controller, <double?>[25, null]);
      final measured = controller.form.references.last;
      expect(controller.validate(), isNot(contains('reference video')));

      controller.rememberReferenceDuration(measured.id, 20);
      expect(
        controller.notice,
        'Seedance 2.5 accepts up to 30 s of reference video; the attached '
        'clips come to 45 s.',
      );
      expect(
        controller.validate(),
        contains('the attached clips come to 45 s'),
      );
      controller.dispose();
    });
  });

  group('every add path asks the budget first', () {
    test('a saved candidate that overruns the budget never lands', () async {
      final controller = _director();
      _attachVideos(controller, <double?>[25]);
      await controller.addReferenceCandidates(
        MediaReferenceKind.video,
        <ReferenceCandidate>[_candidate('long', 20)],
      );
      expect(controller.form.referenceCount(MediaReferenceKind.video), 1);
      expect(
        controller.notice,
        'Seedance 2.5 accepts up to 30 s of reference video; that clip would '
        'bring it to 45 s.',
      );
      controller.dispose();
    });

    test('a batch adds what fits and reports the rest in one notice', () async {
      final controller = _director();
      await controller.addReferenceCandidates(
        MediaReferenceKind.video,
        <ReferenceCandidate>[
          _candidate('a', 10),
          _candidate('b', 10),
          _candidate('c', 20),
          _candidate('d', 20),
        ],
      );
      expect(controller.form.referenceCount(MediaReferenceKind.video), 2);
      expect(controller.referenceSecondsUsed(MediaReferenceKind.video), 20);
      expect(controller.notice, endsWith('2 files were left out.'));
      expect(controller.notice, contains('accepts up to 30 s'));
      expect(controller.validate(), isNot(contains('reference video')));
      controller.dispose();
    });

    test('the count budget still refuses through the same helper', () async {
      final controller = _director(model: 'seedance2');
      await controller.addReferenceCandidates(
        MediaReferenceKind.video,
        <ReferenceCandidate>[
          _candidate('a', 1),
          _candidate('b', 1),
          _candidate('c', 1),
          _candidate('d', 1),
        ],
      );
      expect(controller.form.referenceCount(MediaReferenceKind.video), 3);
      expect(controller.notice, 'Seedance 2.0 accepts up to 3 videos.');
      controller.dispose();
    });
  });

  group('the References accordion shows the seconds budget', () {
    testWidgets('a seconds gauge sits under the count gauge', (tester) async {
      final controller = await _pumpCreate(tester);
      _attachVideos(controller, <double?>[12]);
      await tester.pump();

      expect(find.text('12 s / 30 s'), findsOneWidget);
      expect(_gauge(tester, 'video-duration').value, .4);
      expect(_gauge(tester, 'video-duration').color, isNull);
      expect(
        _reading(tester, 'video-duration').style?.color,
        buildClawnsoleTheme(Brightness.light).colorScheme.onSurfaceVariant,
      );
      expect(
        find.byKey(const ValueKey('reference-seconds-over-budget-video')),
        findsNothing,
      );
      controller.dispose();
    });

    testWidgets('an unmeasured clip reads ? with a tooltip', (tester) async {
      final controller = await _pumpCreate(tester);
      _attachVideos(controller, <double?>[12, null]);
      await tester.pump();

      expect(find.text('? / 30 s'), findsOneWidget);
      expect(find.text('12 s / 30 s'), findsNothing);
      final tooltip = tester.widget<Tooltip>(
        find.descendant(
          of: find.byKey(const ValueKey('reference-capacity-video-duration')),
          matching: find.byType(Tooltip),
        ),
      );
      expect(tooltip.message, 'Reading one clip’s duration…');
      controller.dispose();
    });

    testWidgets('an overrun turns the gauge madder and says why', (
      tester,
    ) async {
      final controller = await _pumpCreate(tester);
      _attachVideos(controller, <double?>[25, 20]);
      await tester.pump();

      final error = buildClawnsoleTheme(Brightness.light).colorScheme.error;
      expect(find.text('45 s / 30 s'), findsOneWidget);
      expect(_gauge(tester, 'video-duration').value, 1);
      expect(_gauge(tester, 'video-duration').color, error);
      expect(_reading(tester, 'video-duration').style?.color, error);
      // The count gauge is still comfortable, so it stays quiet.
      expect(_gauge(tester, 'video-count').color, isNull);
      expect(
        find.byKey(const ValueKey('reference-seconds-over-budget-video')),
        findsOneWidget,
      );
      expect(
        find.text(
          'Seedance 2.5 accepts up to 30 s of reference video — remove or '
          'trim a clip before generating.',
        ),
        findsOneWidget,
      );
      controller.dispose();
    });
  });
}

/// The seconds cap named in the accordion's limit line.
const _seedance25VideoSeconds = 30;

AppController _director({
  String provider = 'runway',
  String model = 'seedance2_5',
}) {
  final controller = AppController(gateway: _MemoryGateway())
    ..snapshot = LocalSnapshot(
      generations: const <Generation>[],
      preferences: AppPreferences(provider: provider, model: model),
      hasApiKey: true,
      connectedProviders: <String>{provider},
      availableProviders: <String>{provider},
      storage: const StorageStats(path: 'memory', bytes: 0, records: 0),
    )
    ..loading = false
    ..selectedProviderId = provider
    ..selectedModelId = model;
  return controller;
}

/// Attaches reference videos with the given measured durations; a null
/// duration stands for a clip whose metadata has not been read yet.
void _attachVideos(AppController controller, List<double?> durations) {
  for (final seconds in durations) {
    controller.addUrlReference(MediaReferenceKind.video);
    final added = controller.form.references.last;
    controller.updateReference(added.id, 'https://cdn.test/${added.id}.mp4');
    if (seconds != null) {
      controller.rememberReferenceDuration(added.id, seconds);
    }
  }
}

ReferenceCandidate _candidate(String id, double seconds) => ReferenceCandidate(
  id: id,
  name: 'Clip $id',
  kind: MediaReferenceKind.video,
  asset: AssetReference(
    kind: 'remote',
    value: 'https://cdn.test/$id.mp4',
    label: 'Clip $id',
    contentType: 'video/mp4',
  ),
  createdAt: DateTime.utc(2026, 9, 7),
  generated: true,
  durationSeconds: seconds,
);

LinearProgressIndicator _gauge(WidgetTester tester, String name) =>
    tester.widget<LinearProgressIndicator>(
      find.descendant(
        of: find.byKey(ValueKey('reference-capacity-$name')),
        matching: find.byType(LinearProgressIndicator),
      ),
    );

/// The `x / y` reading beside a gauge's label.
Text _reading(WidgetTester tester, String name) => tester
    .widgetList<Text>(
      find.descendant(
        of: find.byKey(ValueKey('reference-capacity-$name')),
        matching: find.byType(Text),
      ),
    )
    .last;

Future<AppController> _pumpCreate(WidgetTester tester) async {
  await tester.binding.setSurfaceSize(const Size(1400, 1400));
  addTearDown(() async {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.binding.setSurfaceSize(null);
  });
  final controller = _director();
  await tester.pumpWidget(
    MaterialApp(
      theme: buildClawnsoleTheme(Brightness.light),
      home: Scaffold(
        body: ListenableBuilder(
          listenable: controller,
          builder: (context, _) => CreateScreen(controller: controller),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(const ValueKey('references-accordion-toggle')));
  await tester.pumpAndSettle();
  // The limit line names the seconds cap before any clip is attached.
  expect(
    find.textContaining('$_seedance25VideoSeconds s total'),
    findsOneWidget,
  );
  return controller;
}

class _MemoryGateway implements AppGateway {
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
