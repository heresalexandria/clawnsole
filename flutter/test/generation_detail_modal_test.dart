import 'dart:async';
import 'dart:convert';

import 'package:clawnsole/app/app_controller.dart';
import 'package:clawnsole/app/app_theme.dart';
import 'package:clawnsole/core/gateway.dart';
import 'package:clawnsole/core/models.dart';
import 'package:clawnsole/core/prompt_rewrite.dart';
import 'package:clawnsole/ui/generation_detail_modal.dart';
import 'package:clawnsole/ui/generation_view_widgets.dart';
import 'package:clawnsole/ui/library_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('a full card body opens the modal and Escape closes it', (
    tester,
  ) async {
    await _sized(tester, const Size(1440, 900));
    final controller = _controller(<Generation>[_film()]);
    addTearDown(controller.dispose);

    await _pump(tester, GenerationCard(controller: controller, item: _film()));
    expect(find.byKey(const ValueKey('detail-close')), findsNothing);

    await _openCardBody(tester, 'film-b');
    expect(find.byKey(const ValueKey('detail-close')), findsOneWidget);
    expect(find.byKey(const ValueKey('detail-title-film-b')), findsOneWidget);

    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await _settle(tester);
    expect(find.byKey(const ValueKey('detail-close')), findsNothing);
  });

  testWidgets('a mini card body and the ⋯ menu both open the modal', (
    tester,
  ) async {
    await _sized(tester, const Size(1440, 900));
    final controller = _controller(<Generation>[_film()]);
    addTearDown(controller.dispose);

    await _pump(
      tester,
      SizedBox(
        width: 260,
        child: MiniGenerationCard(controller: controller, item: _film()),
      ),
    );
    await _openCardBody(tester, 'film-b');
    expect(find.byKey(const ValueKey('detail-close')), findsOneWidget);
    await _close(tester);

    // The ⋯ entry is the same door, renamed: "Open film".
    await _pump(
      tester,
      GenerationActionsMenu(controller: controller, item: _film()),
    );
    await tester.tap(find.byTooltip('Generation actions'));
    await _settle(tester);
    expect(find.text('View details'), findsNothing);
    await tester.tap(find.text('Open film'));
    await _settle(tester);
    expect(find.byKey(const ValueKey('detail-close')), findsOneWidget);
    await _close(tester);
  });

  testWidgets('the modal says everything the card truncates', (tester) async {
    await _sized(tester, const Size(1440, 900));
    final folder = LibraryFolder(
      id: 'folder-1',
      name: 'Harbor cuts',
      createdAt: DateTime.utc(2026, 8, 1),
    );
    final film = _film(
      prompt: _longPrompt,
      tags: const <String>['harbor', 'night'],
      folderId: 'folder-1',
      estimatedCreditsMin: 12,
      estimatedCreditsMax: 18,
    );
    final controller = _controller(
      <Generation>[film],
      folders: <LibraryFolder>[folder],
    );
    addTearDown(controller.dispose);

    await _open(tester, controller, film);

    // The whole direction, verbatim and selectable — the point of the modal.
    final prompt = tester.widget<SelectableText>(
      find.byKey(const ValueKey('detail-prompt-film-b')),
    );
    expect(prompt.data, _longPrompt);
    expect(find.byKey(const ValueKey('detail-copy-prompt')), findsOneWidget);

    // An unnamed film derives its headline from the direction.
    expect(find.text(_derivedTitle), findsOneWidget);

    expect(find.text('Harbor cuts'), findsOneWidget);
    expect(find.text('#harbor'), findsOneWidget);
    expect(find.text('#night'), findsOneWidget);
    expect(find.text('Text to video'), findsOneWidget);
    expect(find.text('16:9'), findsOneWidget);
    expect(find.byKey(const ValueKey('detail-cost')), findsOneWidget);

    // Provider details start folded away and open in place.
    expect(find.text('Provider details'), findsOneWidget);
    expect(find.text('Request ID'), findsNothing);
    await _tap(tester, find.byKey(const ValueKey('detail-provider-toggle')));
    expect(find.text('Request ID'), findsOneWidget);
    expect(find.text('HTTP status'), findsOneWidget);
    expect(find.text('PROVIDER RESPONSE'), findsOneWidget);
    await _close(tester);
  });

  testWidgets('a named film wears its tab name as the headline', (
    tester,
  ) async {
    await _sized(tester, const Size(1440, 900));
    final film = _film(title: 'Harbor, take three');
    final controller = _controller(<Generation>[film]);
    addTearDown(controller.dispose);

    await _open(tester, controller, film);
    expect(find.text('Harbor, take three'), findsOneWidget);
    expect(find.text(_derivedTitle), findsNothing);
    await _close(tester);
  });

  testWidgets('iterations walk the rewrite chain in both directions', (
    tester,
  ) async {
    await _sized(tester, const Size(1440, 900));
    final a = _film(localId: 'film-a', prompt: 'The first pass.');
    final b = _film(
      localId: 'film-b',
      prompt: 'The second pass.',
      rewriteOfLocalId: 'film-a',
      rewriteSummary: 'Warmed the lantern.',
    );
    final c = _film(
      localId: 'film-c',
      prompt: 'The third pass.',
      rewriteOfLocalId: 'film-b',
      rewriteSummary: 'Slowed the dolly.',
    );
    final controller = _controller(<Generation>[c, b, a]);
    addTearDown(controller.dispose);

    await _open(tester, controller, b);
    expect(find.byKey(const ValueKey('detail-iterations')), findsOneWidget);
    expect(find.text('REWRITTEN FROM'), findsOneWidget);
    expect(find.text('THIS FILM'), findsOneWidget);
    expect(find.text('REWRITE'), findsOneWidget);
    expect(find.byKey(const ValueKey('detail-back')), findsNothing);

    // Walking back to the source keeps the modal open, with a way home.
    await _tap(tester, find.byKey(const ValueKey('detail-iteration-film-a')));
    expect(find.byKey(const ValueKey('detail-title-film-a')), findsOneWidget);
    expect(find.byKey(const ValueKey('detail-back')), findsOneWidget);
    expect(find.text('REWRITTEN FROM'), findsNothing);

    await _tap(tester, find.byKey(const ValueKey('detail-back')));
    expect(find.byKey(const ValueKey('detail-title-film-b')), findsOneWidget);
    expect(find.byKey(const ValueKey('detail-back')), findsNothing);

    // Forward, too: the film written from this one.
    await _tap(tester, find.byKey(const ValueKey('detail-iteration-film-c')));
    expect(find.byKey(const ValueKey('detail-title-film-c')), findsOneWidget);
    await _close(tester);
  });

  testWidgets('a rewrite whose source is gone says so quietly', (tester) async {
    await _sized(tester, const Size(1440, 900));
    final orphan = _film(rewriteOfLocalId: 'film-gone');
    final controller = _controller(<Generation>[orphan]);
    addTearDown(controller.dispose);

    await _open(tester, controller, orphan);
    expect(
      find.byKey(const ValueKey('detail-iteration-missing')),
      findsOneWidget,
    );
    expect(find.text('Rewritten from a removed film'), findsOneWidget);
    await _close(tester);
  });

  testWidgets('a delivered film offers Reuse and AI Rewrite', (tester) async {
    await _sized(tester, const Size(1440, 900));
    final film = _film();
    final controller = _controller(<Generation>[film]);
    addTearDown(controller.dispose);

    await _open(tester, controller, film);
    expect(find.byKey(const ValueKey('detail-save')), findsOneWidget);
    expect(find.byKey(const ValueKey('detail-reuse')), findsOneWidget);
    expect(find.text('Reuse'), findsOneWidget);

    await _tap(tester, find.byKey(const ValueKey('detail-rewrite')));
    // The rewrite dialog took over, still above the modal.
    expect(find.byKey(const ValueKey('rewrite-direction')), findsOneWidget);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await _settle(tester);
    expect(find.byKey(const ValueKey('detail-close')), findsOneWidget);
    await _close(tester);
  });

  testWidgets('the ⋯ menu organizes the film and never re-opens it', (
    tester,
  ) async {
    await _sized(tester, const Size(1440, 900));
    final film = _film();
    final controller = _controller(<Generation>[film]);
    addTearDown(controller.dispose);

    await _open(tester, controller, film);
    await _tap(tester, find.byTooltip('Generation actions'));
    expect(find.text('Open film'), findsNothing);
    expect(find.text('Move'), findsOneWidget);
    expect(find.text('Tag'), findsOneWidget);
    expect(find.text('Hide'), findsOneWidget);

    // Removing the record from inside its own modal closes the modal too.
    await tester.tap(find.text('Delete history record'));
    await _settle(tester);
    expect(find.text('Remove this record?'), findsOneWidget);
    await tester.tap(find.text('Remove'));
    await _settle(tester);
    expect(find.byKey(const ValueKey('detail-close')), findsNothing);
    // The removal notice hides itself after four seconds; let it.
    await tester.pump(const Duration(seconds: 5));
  });

  testWidgets('the modal lays out at desktop, laptop, and phone sizes', (
    tester,
  ) async {
    await _sized(tester, const Size(1440, 900));
    for (final (size, brightness) in <(Size, Brightness)>[
      (const Size(1440, 900), Brightness.light),
      (const Size(1024, 768), Brightness.dark),
      (const Size(390, 844), Brightness.light),
    ]) {
      await tester.binding.setSurfaceSize(size);
      final film = _film(
        prompt: _longPrompt,
        tags: const <String>['harbor'],
        rewriteOfLocalId: 'film-a',
        estimatedCreditsMin: 12,
        estimatedCreditsMax: 18,
      );
      final source = _film(localId: 'film-a', prompt: 'The first pass.');
      final controller = _controller(<Generation>[film, source]);
      addTearDown(controller.dispose);

      await _open(tester, controller, film, brightness: brightness);
      expect(find.byType(Dialog), findsOneWidget);
      expect(find.byKey(const ValueKey('detail-close')), findsOneWidget);
      expect(find.byKey(const ValueKey('detail-iterations')), findsOneWidget);
      expect(tester.takeException(), isNull);
      await _close(tester);
    }
  });
}

const String _prompt = 'A lantern sways over a wet harbor at midnight.';

/// What [composerTabTitle] makes of [_prompt] and [_longPrompt] alike: the
/// first words, cut at a word boundary.
const String _derivedTitle = 'A lantern sways over a wet…';

const String _longPrompt =
    'A lantern sways over a wet harbor at midnight while the camera drifts '
    'past coiled rope, a shuttered kiosk, and the slow green blink of a '
    'channel marker; the dolly never stops, the reflections never settle, '
    'and the last frame holds on the water long after the boat has gone.';

/// A decodable 1×1 PNG, so image cards paint instead of logging a codec error.
final Uint8List _onePixelPng = base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNkYPhfDwAC'
  'hwGA60e6kgAAAABJRU5ErkJggg==',
);

Future<void> _sized(WidgetTester tester, Size size) async {
  await tester.binding.setSurfaceSize(size);
  addTearDown(() async {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.binding.setSurfaceSize(null);
  });
}

/// Card previews animate for as long as they are on screen, so every wait
/// here is bounded rather than a settle that would never finish.
Future<void> _settle(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));
}

Future<void> _pump(WidgetTester tester, Widget child) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: buildClawnsoleTheme(Brightness.light),
      home: Scaffold(body: SingleChildScrollView(child: child)),
    ),
  );
  await tester.pump();
}

/// Taps a card body inside its padding, where nothing else can claim the
/// gesture, the way a director clicks the card to open the film.
Future<void> _openCardBody(WidgetTester tester, String localId) async {
  final body = find.byKey(ValueKey<String>('generation-open-$localId'));
  await tester.tapAt(tester.getTopLeft(body) + const Offset(24, 6));
  await _settle(tester);
}

/// Opens the modal straight from a host button, the way every entry point
/// eventually does.
Future<void> _open(
  WidgetTester tester,
  AppController controller,
  Generation item, {
  Brightness brightness = Brightness.light,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: buildClawnsoleTheme(brightness),
      home: Scaffold(
        body: Builder(
          builder: (context) => TextButton(
            onPressed: () => unawaited(
              showGenerationDetailModal(
                context,
                controller: controller,
                item: item,
              ),
            ),
            child: const Text('open'),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('open'));
  await _settle(tester);
}

/// The modal scrolls, so anything below the fold is brought into view before
/// it is tapped.
Future<void> _tap(WidgetTester tester, Finder finder) async {
  await tester.ensureVisible(finder);
  await _settle(tester);
  await tester.tap(finder);
  await _settle(tester);
}

Future<void> _close(WidgetTester tester) async {
  await tester.tap(find.byKey(const ValueKey('detail-close')));
  await _settle(tester);
}

/// A controller seeded straight from a snapshot. Skipping `initialize()`
/// keeps startup polling, catalog fetches, and platform probes out of tests
/// that only care about the detail modal.
AppController _controller(
  List<Generation> generations, {
  List<LibraryFolder> folders = const <LibraryFolder>[],
}) {
  final gateway = _DetailGateway(
    LocalSnapshot(
      generations: generations,
      preferences: const AppPreferences(),
      hasApiKey: true,
      connectedProviders: const <String>{'artcraft'},
      availableProviders: const <String>{'artcraft'},
      providerRetentionAcknowledgements: const <String>{'artcraft'},
      folders: folders,
      storage: const StorageStats(path: 'memory', bytes: 0, records: 0),
      connectedRewriteProviders: const <String>{'openai'},
    ),
  );
  return AppController(gateway: gateway)..snapshot = gateway.snapshot;
}

Generation _film({
  String localId = 'film-b',
  String prompt = _prompt,
  String status = 'Ready',
  String? resultUrl = 'https://cdn.example.com/film.mp4',
  String? title,
  String? rewriteOfLocalId,
  String? rewriteSummary,
  String? folderId,
  List<String> tags = const <String>[],
  double? estimatedCreditsMin,
  double? estimatedCreditsMax,
}) {
  final now = DateTime.utc(2026, 9, 1, 21);
  return Generation(
    localId: localId,
    title: title,
    rewriteOfLocalId: rewriteOfLocalId,
    rewriteSummary: rewriteSummary,
    folderId: folderId,
    tags: tags,
    provider: 'artcraft',
    model: 'seedance_2p5',
    status: status,
    prompt: prompt,
    mode: VideoMode.t2v,
    config: const GenerationConfig(
      aspectRatio: '16:9',
      duration: 8,
      resolution: 'hd',
      generateAudio: true,
      safetyTolerance: 2,
      draft: false,
    ),
    resultUrl: resultUrl,
    estimatedCreditsMin: estimatedCreditsMin,
    estimatedCreditsMax: estimatedCreditsMax,
    requestId: 'req-90210',
    lastProviderStatusCode: 200,
    lastProviderResponse: '{"status":"Ready"}',
    lastProviderResponseAt: now,
    providerAcceptedAt: now,
    providerCompletedAt: now,
    createdAt: now,
    updatedAt: now,
  );
}

/// The smallest gateway the modal's surfaces can run against: a snapshot, a
/// rewrite vendor with a key, and media that resolves without a decoder.
class _DetailGateway
    implements AppGateway, ProviderGateway, PromptRewriteGateway {
  _DetailGateway(this.snapshot);

  LocalSnapshot snapshot;

  @override
  Future<List<RewriteModel>> listRewriteModels(
    String providerId, {
    String? candidateKey,
  }) async =>
      RewriteProvider.byId(providerId)?.curatedModels ?? const <RewriteModel>[];

  @override
  Future<PromptRewriteResult> rewritePrompt(
    PromptRewriteRequest request,
  ) async => PromptRewriteResult(
    prompt: 'A slower dolly past a warm lantern.',
    summary: 'Warmed the lantern.',
    providerId: request.providerId,
    modelId: request.modelId,
  );

  @override
  Future<LocalSnapshot> setProviderApiKey(
    String provider,
    String value,
  ) async => snapshot;

  @override
  Future<LocalSnapshot> clearProviderApiKey(String provider) async => snapshot;

  @override
  Future<ProviderAccountStatus> verifyProviderKey(
    String provider, [
    String? candidate,
  ]) async => ProviderAccountStatus(provider: provider);

  @override
  Future<ProviderAccountStatus> getProviderAccount(String provider) async =>
      ProviderAccountStatus(provider: provider);

  @override
  Future<List<ProviderModelPrice>> listProviderModels(String provider) async =>
      const <ProviderModelPrice>[];

  @override
  Future<CostEstimate?> quoteProviderCost(
    String provider,
    String model,
    Map<String, Object?> input,
  ) async => null;

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
  Future<Uint8List> readAsset(AssetReference reference) async => _onePixelPng;

  @override
  Uri mediaUri(String source) => Uri.parse(source);

  @override
  Future<Uint8List> downloadMedia(String source) async => _onePixelPng;

  @override
  Future<void> saveMediaToPhotoLibrary(
    Uint8List bytes,
    String fileName,
    String contentType,
  ) async {}
}
