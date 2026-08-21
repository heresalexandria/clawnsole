import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'dart:ui' show PointerDeviceKind;

import 'package:clawnsole/app/app_controller.dart';
import 'package:clawnsole/app/app_theme.dart';
import 'package:clawnsole/app/clawnsole_app.dart';
import 'package:clawnsole/core/app_version.dart';
import 'package:clawnsole/core/bfl_api.dart';
import 'package:clawnsole/core/asset_extensions.dart';
import 'package:clawnsole/core/generation_status.dart';
import 'package:clawnsole/core/gateway.dart';
import 'package:clawnsole/core/google_drive.dart';
import 'package:clawnsole/core/local_data_store.dart';
import 'package:clawnsole/core/ltx_api.dart';
import 'package:clawnsole/core/models.dart';
import 'package:clawnsole/core/native_gateway.dart';
import 'package:clawnsole/core/pricing.dart';
import 'package:clawnsole/core/provider_api.dart';
import 'package:clawnsole/core/provider_catalog.dart';
import 'package:clawnsole/core/shell_bridge.dart';
import 'package:clawnsole/core/store_update.dart';
import 'package:clawnsole/core/update_check.dart';
import 'package:clawnsole/core/update_status.dart';
import 'package:clawnsole/core/web_gateway.dart';
import 'package:clawnsole/ui/common_widgets.dart';
import 'package:clawnsole/ui/create_screen.dart';
import 'package:clawnsole/ui/generation_loading_placeholder.dart';
import 'package:clawnsole/ui/generation_view_widgets.dart';
import 'package:clawnsole/ui/hardware.dart';
import 'package:clawnsole/ui/inline_video.dart';
import 'package:clawnsole/ui/media_thumbnail.dart';
import 'package:clawnsole/ui/panels.dart';
import 'package:clawnsole/ui/references_screen.dart';
import 'package:clawnsole/ui/settings_screen.dart';
import 'package:clawnsole/ui/update_available_chip.dart';
import 'package:flutter/foundation.dart'
    show TargetPlatform, debugDefaultTargetPlatformOverride;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  testWidgets('video media thumbnail extracts and exposes a reusable frame', (
    tester,
  ) async {
    final gateway = _MemoryGateway(
      const LocalSnapshot(
        generations: <Generation>[],
        preferences: AppPreferences(),
        hasApiKey: false,
        storage: StorageStats(path: 'memory', bytes: 0, records: 0),
      ),
    );
    final frame = base64Decode(
      'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII=',
    );
    Uri? requested;
    Uint8List? generated;
    VideoSourceMetadata? metadata;

    await tester.pumpWidget(
      MaterialApp(
        home: SizedBox(
          width: 160,
          height: 90,
          child: MediaThumbnail(
            gateway: gateway,
            kind: MediaReferenceKind.video,
            reference: const AssetReference(
              kind: 'remote',
              value: 'https://cdn.test/reference.mp4',
              label: 'reference.mp4',
              contentType: 'video/mp4',
            ),
            frameLoader: (uri, _) async {
              requested = uri;
              return frame;
            },
            metadataLoader: (_) async => const VideoSourceMetadata(
              width: 1920,
              height: 1080,
              durationSeconds: 8,
            ),
            onThumbnail: (bytes) => generated = bytes,
            onVideoMetadata: (value) => metadata = value,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(requested, Uri.parse('https://cdn.test/reference.mp4'));
    expect(generated, frame);
    expect(metadata?.signature, '1920×1080@8.000');
    expect(
      find.byKey(const ValueKey('media-thumbnail-video-frame')),
      findsOneWidget,
    );
  });

  test('duration defaults to manual and model capabilities gate Auto', () {
    final controller = AppController();

    expect(controller.form.autoDuration, isFalse);
    controller.setAutoDuration(true);
    expect(controller.form.autoDuration, isTrue);

    controller.setAutoDuration(false);
    controller
      ..selectedProviderId = 'ltx'
      ..selectedModelId = 'ltx-2-3-fast';
    controller.setAutoDuration(true);
    expect(controller.form.autoDuration, isFalse);

    final fullHd = controller.selectedModel.durationRangeFor('fhd');
    final quadHd = controller.selectedModel.durationRangeFor('qhd');
    expect(
      (fullHd.minimumSeconds, fullHd.maximumSeconds, fullHd.stepSeconds),
      (6, 20, 2),
    );
    expect((quadHd.minimumSeconds, quadHd.maximumSeconds), (6, 10));
    expect(quadHd.normalize(19), 10);
    controller.dispose();
  });

  test('uses BFL published FLUX 3 video rates', () {
    const hdEightSeconds = GenerationConfig(
      aspectRatio: '16:9',
      duration: 8,
      resolution: 'hd',
      generateAudio: true,
      safetyTolerance: 2,
      draft: false,
    );
    const draftTenSeconds = GenerationConfig(
      aspectRatio: '16:9',
      duration: 10,
      resolution: 'hd',
      generateAudio: true,
      safetyTolerance: 2,
      draft: true,
    );

    expect(estimateCredits(VideoMode.t2v, hdEightSeconds).minimum, 136);
    expect(estimateCredits(VideoMode.v2v, hdEightSeconds).minimum, 344);
    expect(estimateCredits(VideoMode.t2v, draftTenSeconds).minimum, 60);
    expect(creditsToUsd(136), 1.36);

    const fhdAuto = GenerationConfig(
      aspectRatio: '16:9',
      duration: 'auto',
      resolution: 'fhd',
      generateAudio: true,
      safetyTolerance: 2,
      draft: false,
    );
    final autoEstimate = estimateCredits(VideoMode.v2v, fhdAuto);
    expect(autoEstimate.minimum, 270);
    expect(autoEstimate.maximum, 1080);
  });

  test('calculates BFL estimates from current inputs instead of history', () {
    final now = DateTime.utc(2026, 8, 15);
    const config = GenerationConfig(
      aspectRatio: '16:9',
      duration: 8,
      resolution: 'hd',
      generateAudio: true,
      safetyTolerance: 2,
      draft: false,
    );
    final history = <Generation>[
      Generation(
        localId: 'quote',
        status: 'Ready',
        prompt: 'Prior generation',
        mode: VideoMode.t2v,
        config: config,
        createdAt: now,
        updatedAt: now,
        cost: 130,
      ),
    ];

    final estimate = estimateCredits(VideoMode.t2v, config, history);
    expect(estimate.minimum, 136);
    expect(estimate.maximum, 136);
    expect(estimate.basis, 'bfl-rate');
  });

  test('BFL estimates ignore matching history from other providers', () {
    final now = DateTime.utc(2026, 8, 19);
    const config = GenerationConfig(
      aspectRatio: '16:9',
      duration: 10,
      resolution: 'hd',
      generateAudio: true,
      safetyTolerance: 2,
      draft: false,
    );
    final estimate = estimateCredits(VideoMode.t2v, config, <Generation>[
      Generation(
        localId: 'artcraft-quote',
        provider: 'artcraft',
        model: 'seedance_2p0',
        status: 'Ready',
        prompt: 'Another provider',
        mode: VideoMode.t2v,
        config: config,
        createdAt: now,
        updatedAt: now,
        cost: 999,
      ),
    ]);

    expect(estimate.minimum, 170);
    expect(estimate.maximum, 170);
    expect(estimate.basis, 'bfl-rate');
  });

  test(
    'ArtCraft live quotes replace the published fallback estimate',
    () async {
      final gateway = _ProviderMemoryGateway(
        const LocalSnapshot(
          generations: <Generation>[],
          preferences: AppPreferences(
            provider: 'artcraft',
            model: 'seedance_2p0',
          ),
          hasApiKey: false,
          storage: StorageStats(path: 'memory', bytes: 0, records: 0),
        ),
      );
      final controller = AppController(gateway: gateway);

      await controller.initialize();
      await controller.refreshProviderEstimate();

      expect(controller.currentEstimate.minimumUsd, 1.85);
      expect(controller.currentEstimate.providerUnitsMinimum, 185);
      expect(controller.currentEstimate.basis, 'artcraft-live-quote');
      expect(controller.currentEstimate.rateUsd, isPositive);

      controller.updateForm((form) => form.prompt = 'Premium prompt');
      expect(controller.currentEstimate.basis, isNot('artcraft-live-quote'));
      await controller.refreshProviderEstimate();

      expect(controller.currentEstimate.minimumUsd, 7);
      expect(gateway.quotedInputs.last['prompt'], 'Premium prompt');

      controller.updateForm((form) {
        form
          ..prompt = ''
          ..resolution = 'fhd';
      });
      await controller.refreshProviderEstimate();

      expect(controller.currentEstimate.minimumUsd, 4.66);
      expect(controller.currentEstimate.providerUnitsMinimum, 466);
      expect(gateway.quotedResolutions, containsAll(<String>['hd', 'fhd']));
      controller.dispose();
    },
  );

  test('preserves terminal BFL statuses and extracts provider errors', () {
    expect(normalizeGenerationStatus('task not found'), 'Task not found');
    expect(isGenerationFailureStatus('Task not found'), isTrue);
    expect(isGenerationWorkingStatus('Error', canPoll: true), isFalse);
    expect(
      providerFailureMessage(<String, Object?>{
        'status': 'Error',
        'details': <String, Object?>{
          'message': 'Generation dependency unavailable',
        },
      }, fallback: 'Error'),
      'Generation dependency unavailable',
    );
  });

  test(
    'preserves a terminal provider payload delivered with HTTP 503',
    () async {
      final api = BflApi(
        client: MockClient(
          (_) async => http.Response(
            jsonEncode(<String, Object?>{
              'status': 'Error',
              'details': <String, Object?>{
                'message': 'Generation dependency unavailable',
              },
            }),
            503,
          ),
        ),
      );

      try {
        await api.poll('key', 'https://api.bfl.ai/v1/get_result?id=test');
        fail('Expected a provider exception.');
      } on ProviderException catch (error) {
        final payload = providerErrorPayload(error);
        expect(error.status, 503);
        expect(payload?['status'], 'Error');
        expect(
          providerFailureMessage(payload, fallback: 'Error'),
          'Generation dependency unavailable',
        );
        expect(providerErrorResponse(error), contains('"status": "Error"'));
      }
    },
  );

  test('recovers an interrupted submission instead of polling forever', () {
    final now = DateTime.utc(2026, 8, 15, 12);
    final interrupted = Generation(
      localId: 'interrupted',
      status: 'submitting',
      prompt: 'A slow pan through a blue room.',
      mode: VideoMode.t2v,
      config: const GenerationConfig(
        aspectRatio: '16:9',
        duration: 8,
        resolution: 'hd',
        generateAudio: true,
        safetyTolerance: 2,
        draft: false,
      ),
      createdAt: now.subtract(const Duration(minutes: 4)),
      updatedAt: now.subtract(const Duration(minutes: 3)),
    );

    final recovered = interrupted.recoverInterruptedSubmission(now);
    expect(recovered.status, 'Error');
    expect(recovered.isWorking, isFalse);
    expect(recovered.error, contains('interrupted'));
  });

  test('clears stale progress when a provider stops reporting it', () async {
    final now = DateTime.utc(2026, 8, 19, 12);
    final item = Generation(
      localId: 'stale-progress',
      status: 'Pending',
      progress: 38,
      prompt: 'A slow orbit around a glass sculpture.',
      mode: VideoMode.t2v,
      config: const GenerationConfig(
        aspectRatio: '16:9',
        duration: 8,
        resolution: 'hd',
        generateAudio: true,
        safetyTolerance: 2,
        draft: false,
      ),
      createdAt: now,
      updatedAt: now,
      pollingUrl: 'https://api.bfl.ai/v1/get_result?id=stale-progress',
    );
    final store = _MemoryLocalDataStore(
      StoredData(apiKey: 'key', generations: <Generation>[item]),
    );
    final gateway = NativeGateway(
      store: store,
      api: _StatusWithoutProgressApi(),
      isIos: false,
    );

    final updated = await gateway.poll(item);

    expect(updated.progress, isNull);
    expect((await store.read()).generations.single.progress, isNull);
  });

  testWidgets('shows a failed status check as recoverable, not in progress', (
    tester,
  ) async {
    final now = DateTime.utc(2026, 8, 15, 12);
    final item = Generation(
      localId: 'unavailable',
      status: 'Pending',
      prompt: 'A sloth reaches for a switch.',
      mode: VideoMode.t2v,
      config: const GenerationConfig(
        aspectRatio: '16:9',
        duration: 8,
        resolution: 'hd',
        generateAudio: true,
        safetyTolerance: 2,
        draft: false,
      ),
      createdAt: now,
      updatedAt: now,
      pollingUrl: 'https://api.bfl.ai/v1/get_result?id=test',
      lastCheckedAt: now,
      lastCheckError: 'BFL is temporarily unavailable (HTTP 503).',
      lastProviderStatusCode: 503,
      lastProviderResponse: '{"detail":"upstream unavailable"}',
      lastProviderResponseAt: now,
    );
    final controller = AppController();

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Column(
            children: <Widget>[
              StatusBadge(item: item),
              GenerationStatusButton(controller: controller, item: item),
              GenerationDetailsButton(item: item),
            ],
          ),
        ),
      ),
    );

    expect(find.text('Status unavailable'), findsOneWidget);
    expect(find.text('In progress'), findsNothing);
    expect(find.text('Retry status'), findsOneWidget);
    expect(find.text('View details'), findsOneWidget);

    await tester.tap(find.text('View details'));
    await tester.pumpAndSettle();
    expect(find.text('Generation details'), findsOneWidget);
    expect(find.text('503'), findsOneWidget);
    expect(find.text('{"detail":"upstream unavailable"}'), findsOneWidget);
  });

  testWidgets(
    'shows broadcast static at the generation aspect ratio by default',
    (tester) async {
      final now = DateTime.utc(2026, 8, 19, 12);
      final item = Generation(
        localId: 'portrait-video',
        status: 'Pending',
        progress: 42,
        prompt: 'A late-night signal fighting through antenna snow.',
        mode: VideoMode.t2v,
        config: const GenerationConfig(
          aspectRatio: '9:16',
          duration: 8,
          resolution: 'hd',
          generateAudio: true,
          safetyTolerance: 2,
          draft: false,
        ),
        createdAt: now,
        updatedAt: now,
      );
      final controller = AppController();

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: SizedBox(
                width: 320,
                child: ActivityCard(controller: controller, item: item),
              ),
            ),
          ),
        ),
      );

      expect(find.byType(GenerationLoadingPlaceholder), findsOneWidget);
      expect(
        controller.generationPlaceholderStyle,
        GenerationPlaceholderStyle.broadcastStatic,
      );
      expect(
        find.byKey(const ValueKey('generation-loading-static-portrait-video')),
        findsOneWidget,
      );
      expect(find.text('Saved generation'), findsNothing);
      expect(find.text('RENDERING — 42%'), findsOneWidget);
      final size = tester.getSize(find.byType(GenerationLoadingPlaceholder));
      expect(size.width / size.height, closeTo(9 / 16, .01));

      await tester.pumpWidget(const SizedBox.shrink());
      controller.dispose();
    },
  );

  testWidgets('applies the Cyclone preference across dense render paths', (
    tester,
  ) async {
    final now = DateTime.utc(2026, 8, 20, 12);
    final item = Generation(
      localId: 'styled-video',
      status: 'Pending',
      progress: 18,
      prompt: 'Ribbons take over the placeholder.',
      mode: VideoMode.t2v,
      config: const GenerationConfig(
        aspectRatio: '16:9',
        duration: 8,
        resolution: 'hd',
        generateAudio: true,
        safetyTolerance: 2,
        draft: false,
      ),
      createdAt: now,
      updatedAt: now,
    );
    final controller = AppController()
      ..generationPlaceholderStyle = GenerationPlaceholderStyle.cyclone;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: SizedBox(
              width: 320,
              child: ActivityCard(controller: controller, item: item),
            ),
          ),
        ),
      ),
    );
    expect(
      find.byKey(const ValueKey('generation-loading-cyclone-styled-video')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('generation-loading-static-styled-video')),
      findsNothing,
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: SizedBox(
              width: 260,
              child: MiniGenerationCard(controller: controller, item: item),
            ),
          ),
        ),
      ),
    );
    expect(
      find.byKey(const ValueKey('generation-loading-cyclone-styled-video')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('generation-loading-static-styled-video')),
      findsNothing,
    );

    await tester.pumpWidget(const SizedBox.shrink());
    controller.dispose();
  });

  testWidgets('full cards frame delivered media at its stored aspect ratio', (
    tester,
  ) async {
    final frame = base64Decode(
      'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII=',
    );
    final gateway = _MemoryGateway(
      const LocalSnapshot(
        generations: <Generation>[],
        preferences: AppPreferences(),
        hasApiKey: false,
        storage: StorageStats(path: 'memory', bytes: 0, records: 0),
      ),
      assets: <String, Uint8List>{
        'aspect-thumb.png': frame,
        'aspect-strip.png': frame,
      },
    );
    final controller = AppController(gateway: gateway);
    addTearDown(controller.dispose);

    Widget card(String aspect) => MaterialApp(
      home: Scaffold(
        body: SingleChildScrollView(
          child: SizedBox(
            width: 640,
            child: ActivityCard(
              controller: controller,
              item: _deliveredGeneration('aspect-$aspect', aspect: aspect),
            ),
          ),
        ),
      ),
    );

    // A 16:9 film fills the card's width at its true ratio — never cropped
    // into a strip.
    await tester.pumpWidget(card('16:9'));
    await tester.pumpAndSettle();
    var box = tester.getSize(find.byType(InlineVideoMediaBox));
    // The card border leaves 638 of the 640 for media.
    expect(box.width, closeTo(638, .5));
    expect(box.width / box.height, closeTo(16 / 9, .01));

    // A 9:16 film would want 1138px of height at this width, so the box caps
    // at 70% of the 600px viewport with the whole frame centered inside.
    await tester.pumpWidget(card('9:16'));
    await tester.pumpAndSettle();
    box = tester.getSize(find.byType(InlineVideoMediaBox));
    expect(box.height, closeTo(420, .1));
    final film = tester.getSize(
      find.descendant(
        of: find.byType(InlineVideoMediaBox),
        matching: find.byType(AspectRatio),
      ),
    );
    expect(film.width / film.height, closeTo(9 / 16, .01));
    expect(film.height, closeTo(420, .1));

    // In-progress video cards use the identical capped media viewport, so a
    // portrait placeholder cannot make the card taller than its delivered
    // neighbor with the same ratio.
    final now = DateTime.utc(2026, 8, 21, 12);
    final working = Generation(
      localId: 'working-portrait',
      status: 'Pending',
      prompt: 'A portrait render crossing the wire.',
      mode: VideoMode.t2v,
      config: const GenerationConfig(
        aspectRatio: '9:16',
        duration: 8,
        resolution: 'hd',
        generateAudio: true,
        safetyTolerance: 2,
        draft: false,
      ),
      createdAt: now,
      updatedAt: now,
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: SizedBox(
              width: 640,
              child: ActivityCard(controller: controller, item: working),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    final workingBox = tester.getSize(find.byType(InlineVideoMediaBox));
    expect(workingBox.height, closeTo(box.height, .1));

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
  });

  testWidgets('the filmstrip scales with its preview and hides when short', (
    tester,
  ) async {
    final frame = base64Decode(
      'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII=',
    );
    final gateway = _MemoryGateway(
      const LocalSnapshot(
        generations: <Generation>[],
        preferences: AppPreferences(),
        hasApiKey: false,
        storage: StorageStats(path: 'memory', bytes: 0, records: 0),
      ),
      assets: <String, Uint8List>{
        'strip-thumb.png': frame,
        'strip-strip.png': frame,
      },
    );
    final controller = AppController(gateway: gateway);
    addTearDown(controller.dispose);
    final item = _deliveredGeneration(
      'strip',
      thumbnail: 'strip-thumb.png',
      timeline: 'strip-strip.png',
    );
    const stripKey = ValueKey('generation-video-filmstrip');

    // Compact rows stay a clean cover thumbnail: no band at 68px.
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 420,
            child: CompactGenerationRow(controller: controller, item: item),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byKey(stripKey), findsNothing);

    // Mini cards keep a slim band under their 118px preview.
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: SizedBox(
              width: 260,
              child: MiniGenerationCard(controller: controller, item: item),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(tester.getSize(find.byKey(stripKey)).height, 24);

    // Full cards keep the complete band under the aspect-true frame.
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: SizedBox(
              width: 640,
              child: ActivityCard(controller: controller, item: item),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(tester.getSize(find.byKey(stripKey)).height, 48);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
  });

  testWidgets('keeps Cyclone available as a generation placeholder', (
    tester,
  ) async {
    final now = DateTime.utc(2026, 8, 20, 12);
    final item = Generation(
      localId: 'cyclone-video',
      status: 'Pending',
      prompt: 'Luminous ribbons in a feedback field.',
      mode: VideoMode.t2v,
      config: const GenerationConfig(
        aspectRatio: '16:9',
        duration: 8,
        resolution: 'hd',
        generateAudio: true,
        safetyTolerance: 2,
        draft: false,
      ),
      createdAt: now,
      updatedAt: now,
    );

    await tester.pumpWidget(
      MaterialApp(
        home: SizedBox(
          width: 320,
          height: 180,
          child: GenerationLoadingPlaceholder(
            item: item,
            style: GenerationPlaceholderStyle.cyclone,
          ),
        ),
      ),
    );

    expect(
      find.byKey(const ValueKey('generation-loading-cyclone-cyclone-video')),
      findsOneWidget,
    );
    expect(find.text('RENDERING'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  test('generation placeholder preference migrates safely and round-trips', () {
    expect(
      AppPreferences.fromJson(
        const <String, Object?>{},
      ).generationPlaceholderStyle,
      GenerationPlaceholderStyle.broadcastStatic,
    );
    final restored = AppPreferences.fromJson(
      const AppPreferences(
        generationPlaceholderStyle: GenerationPlaceholderStyle.cyclone,
      ).toJson(),
    );
    expect(
      restored.generationPlaceholderStyle,
      GenerationPlaceholderStyle.cyclone,
    );
  });

  test(
    'round-trips compact history, billing, and durable asset references',
    () {
      final now = DateTime.utc(2026, 8, 15);
      final original = StoredData(
        apiKey: 'secret',
        generations: <Generation>[
          Generation(
            localId: 'one',
            status: 'Ready',
            prompt: 'A patient sloth reaches for a brass switch.',
            mode: VideoMode.i2v,
            config: const GenerationConfig(
              aspectRatio: '16:9',
              duration: 8,
              resolution: 'hd',
              generateAudio: true,
              safetyTolerance: 2,
              draft: false,
              exactTiming: true,
              referenceTask: MediaReferenceTask.edit,
              keyframes: <KeyframeLabel>[
                KeyframeLabel(
                  label: 'start.png',
                  role: KeyframeRole.start,
                  seconds: 0,
                  source: AssetReference(
                    kind: 'local',
                    value: 'asset-input',
                    label: 'start.png',
                    contentType: 'image/png',
                    bytes: 42,
                  ),
                ),
              ],
              references: <MediaReferenceLabel>[
                MediaReferenceLabel(
                  label: 'motion.mp4',
                  kind: MediaReferenceKind.video,
                  source: AssetReference(
                    kind: 'local',
                    value: 'asset-motion',
                    label: 'motion.mp4',
                    contentType: 'video/mp4',
                    bytes: 84,
                  ),
                ),
                MediaReferenceLabel(
                  label: 'voice.mp3',
                  kind: MediaReferenceKind.audio,
                  source: AssetReference(
                    kind: 'remote',
                    value: 'https://cdn.test/voice.mp3',
                    label: 'voice.mp3',
                    contentType: 'audio/mpeg',
                  ),
                ),
              ],
            ),
            createdAt: now,
            updatedAt: now,
            estimatedCreditsMin: 136,
            estimatedCreditsMax: 136,
            creditsBefore: 500,
            creditsAfter: 364,
            cost: 136,
            resultAsset: const AssetReference(
              kind: 'local',
              value: 'asset-video',
              label: 'clawnsole.mp4',
              contentType: 'video/mp4',
              bytes: 1024,
            ),
            lastCheckedAt: now,
            statusCheckCount: 3,
            consecutiveCheckFailures: 1,
            lastCheckError: 'Temporary provider timeout',
            lastProviderStatusCode: 503,
            lastProviderResponse: '{"detail":"try again"}',
            lastProviderResponseAt: now,
          ),
        ],
      );

      final decoded = StoredData.decode(original.encode());
      expect(original.encode(), isNot(contains('secret')));
      expect(decoded.apiKey, isEmpty);
      expect(decoded.generations.single.cost, 136);
      expect(decoded.generations.single.creditsAfter, 364);
      expect(decoded.generations.single.config.exactTiming, isTrue);
      expect(
        decoded.generations.single.config.referenceTask,
        MediaReferenceTask.edit,
      );
      expect(
        decoded.generations.single.config.keyframes!.single.role,
        KeyframeRole.start,
      );
      expect(
        decoded.generations.single.config.keyframes!.single.source!.value,
        'asset-input',
      );
      expect(
        decoded.generations.single.config.references!.map((item) => item.kind),
        <MediaReferenceKind>[
          MediaReferenceKind.video,
          MediaReferenceKind.audio,
        ],
      );
      expect(
        decoded.generations.single.config.references!.first.source!.value,
        'asset-motion',
      );
      expect(decoded.generations.single.resultAsset!.value, 'asset-video');
      expect(decoded.generations.single.lastCheckedAt, now);
      expect(decoded.generations.single.statusCheckCount, 3);
      expect(decoded.generations.single.consecutiveCheckFailures, 1);
      expect(
        decoded.generations.single.lastCheckError,
        'Temporary provider timeout',
      );
      expect(decoded.generations.single.lastProviderStatusCode, 503);
      expect(
        decoded.generations.single.lastProviderResponse,
        '{"detail":"try again"}',
      );
      expect(decoded.generations.single.lastProviderResponseAt, now);
      expect(decoded.rejectedIosReviewApiKeyId, isEmpty);
      expect(original.encode(), isNot(contains('data:image')));
    },
  );

  test('migrates legacy keyframe ordering to explicit frame roles', () {
    final decoded = StoredData.fromJson(<String, Object?>{
      'schemaVersion': 4,
      'generations': <Object?>[
        <String, Object?>{
          'localId': 'legacy',
          'status': 'Ready',
          'prompt': 'Legacy frames',
          'mode': 'i2v',
          'createdAt': '2026-08-15T12:00:00Z',
          'updatedAt': '2026-08-15T12:00:00Z',
          'config': <String, Object?>{
            'aspectRatio': '16:9',
            'duration': 8,
            'resolution': 'hd',
            'generateAudio': true,
            'safetyTolerance': 2,
            'draft': false,
            'keyframes': <Object?>[
              <String, Object?>{'label': 'first.png'},
              <String, Object?>{'label': 'middle.png'},
              <String, Object?>{'label': 'last.png'},
            ],
          },
        },
      ],
    });

    expect(
      decoded.generations.single.config.keyframes!.map((frame) => frame.role),
      <KeyframeRole>[KeyframeRole.start, KeyframeRole.middle, KeyframeRole.end],
    );
    expect(decoded.toJson()['schemaVersion'], 18);
  });

  test(
    'favorites update optimistically and hidden items filter explicitly',
    () async {
      final now = DateTime.utc(2026, 8, 21, 12);
      Generation generation(String id, {bool hidden = false}) => Generation(
        localId: id,
        status: 'Ready',
        prompt: '$id film',
        mode: VideoMode.t2v,
        config: const GenerationConfig(
          aspectRatio: '16:9',
          duration: 8,
          resolution: 'hd',
          generateAudio: true,
          safetyTolerance: 2,
          draft: false,
        ),
        createdAt: now,
        updatedAt: now,
        hidden: hidden,
      );

      final initial = StoredData(
        generations: <Generation>[
          generation('visible'),
          generation('hidden', hidden: true),
        ],
      );
      final store = _MemoryLocalDataStore(initial);
      final gateway = NativeGateway(store: store, isIos: false);
      final controller = AppController(gateway: gateway)
        ..snapshot = LocalSnapshot(
          generations: initial.generations,
          preferences: const AppPreferences(),
          hasApiKey: false,
          storage: const StorageStats(path: 'memory', bytes: 0, records: 2),
        );

      final write = controller.toggleGenerationFavorite(
        controller.generations.first,
      );
      expect(controller.generations.first.favorite, isTrue);
      await write;
      expect((await gateway.load()).generations.first.favorite, isTrue);
      expect(
        StoredData.decode(store.data.encode()).generations.last.hidden,
        isTrue,
      );

      expect(
        controller.filteredGenerations.map((item) => item.localId),
        <String>['visible'],
      );
      controller.setLibraryVisibilityFilter(VisibilityFilter.hidden);
      expect(
        controller.filteredGenerations.map((item) => item.localId),
        <String>['hidden'],
      );
      controller.dispose();
    },
  );

  test('persists folders and tags while removing a folder safely', () async {
    final now = DateTime.utc(2026, 8, 17, 12);
    final store = _MemoryLocalDataStore(
      StoredData(
        generations: <Generation>[
          Generation(
            localId: 'organized-film',
            status: 'Ready',
            prompt: 'A brass robot walking through a gallery.',
            mode: VideoMode.t2v,
            config: const GenerationConfig(
              aspectRatio: '16:9',
              duration: 8,
              resolution: 'hd',
              generateAudio: true,
              safetyTolerance: 2,
              draft: false,
            ),
            createdAt: now,
            updatedAt: now,
          ),
        ],
      ),
    );
    final gateway = NativeGateway(store: store, isIos: false);
    final folder = LibraryFolder(
      id: 'folder-client',
      name: 'Client work',
      createdAt: now,
    );
    final subfolder = LibraryFolder(
      id: 'folder-deliverables',
      name: 'Deliverables',
      createdAt: now.add(const Duration(seconds: 1)),
      parentId: folder.id,
    );

    await gateway.saveLibraryFolder(folder);
    await gateway.saveLibraryFolder(subfolder);
    final organized = await gateway.setGenerationOrganization(
      'organized-film',
      folderId: folder.id,
      tags: const <String>[' Favorite ', '#Vertical', 'favorite'],
    );

    expect(organized.folders, hasLength(2));
    expect(
      organized.folders.singleWhere((item) => item.id == subfolder.id).parentId,
      folder.id,
    );
    expect(organized.generations.single.folderId, folder.id);
    expect(organized.generations.single.tags, <String>['Favorite', 'Vertical']);
    final decoded = StoredData.decode(store.data.encode());
    expect(decoded.folders, hasLength(2));
    expect(decoded.generations.single.tags, <String>['Favorite', 'Vertical']);

    final controller = AppController();
    controller.snapshot = LocalSnapshot(
      generations: <Generation>[
        organized.generations.single.copyWith(folderId: subfolder.id),
      ],
      folders: organized.folders,
      preferences: const AppPreferences(),
      hasApiKey: false,
      storage: const StorageStats(path: 'memory', bytes: 0, records: 1),
    );
    controller.setLibraryFolderView(folder.id);
    expect(controller.folderDepth(subfolder.id), 1);
    expect(controller.folderPath(subfolder.id), 'Client work / Deliverables');
    expect(controller.folderCount(folder.id), 1);
    expect(controller.filteredGenerations.single.localId, 'organized-film');
    controller.dispose();

    final removed = await gateway.deleteLibraryFolder(folder.id);
    expect(removed.folders.single.id, subfolder.id);
    expect(removed.folders.single.parentId, isNull);
    expect(removed.generations.single.folderId, isNull);
    expect(removed.generations.single.tags, <String>['Favorite', 'Vertical']);
  });

  test(
    'persists saved references in an independent nested folder hierarchy',
    () async {
      final now = DateTime.utc(2026, 8, 19, 12);
      final store = _MemoryLocalDataStore();
      final gateway = NativeGateway(store: store, isIos: false);
      final folder = LibraryFolder(
        id: 'reference-characters',
        name: 'Characters',
        createdAt: now,
        collection: LibraryCollection.references,
      );
      final subfolder = LibraryFolder(
        id: 'reference-heroes',
        name: 'Heroes',
        createdAt: now.add(const Duration(seconds: 1)),
        parentId: folder.id,
        collection: LibraryCollection.references,
      );
      await gateway.saveLibraryFolder(folder);
      await gateway.saveLibraryFolder(subfolder);
      final reference = SavedReference(
        id: 'saved-hero',
        name: 'Brass hero',
        kind: MediaReferenceKind.image,
        asset: const AssetReference(
          kind: 'remote',
          value: 'https://cdn.test/hero.png',
          label: 'hero.png',
          contentType: 'image/png',
        ),
        createdAt: now,
        updatedAt: now,
        folderId: subfolder.id,
        tags: const <String>[' Character ', '#Favorite', 'character'],
      );

      final saved = await gateway.saveReference(reference);

      expect(saved.savedReferences.single.name, 'Brass hero');
      expect(saved.savedReferences.single.tags, <String>[
        'Character',
        'Favorite',
      ]);
      expect(
        saved.folders.where(
          (item) => item.collection == LibraryCollection.references,
        ),
        hasLength(2),
      );
      final decoded = StoredData.decode(store.data.encode());
      expect(decoded.toJson()['schemaVersion'], 18);
      expect(
        decoded.savedReferences.single.asset.value,
        'https://cdn.test/hero.png',
      );

      final controller = AppController();
      controller.snapshot = saved;
      controller.setReferenceFolderView(folder.id);
      controller.setReferenceSearch('favorite');
      expect(controller.filteredSavedReferences.single.id, 'saved-hero');
      expect(
        controller.folderPath(
          subfolder.id,
          collection: LibraryCollection.references,
        ),
        'Characters / Heroes',
      );
      controller.dispose();

      final removed = await gateway.deleteLibraryFolder(subfolder.id);
      expect(removed.savedReferences.single.folderId, isNull);
      expect(
        removed.folders.singleWhere((item) => item.id == folder.id).collection,
        LibraryCollection.references,
      );
    },
  );

  test(
    'adds saved and generated media candidates to the create form',
    () async {
      final controller = AppController()
        ..selectedProviderId = 'atlas'
        ..selectedModelId = 'bytedance/seedance-2.5/reference-to-video';
      final now = DateTime.utc(2026, 8, 19);
      await controller.addReferenceCandidates(
        MediaReferenceKind.image,
        <ReferenceCandidate>[
          ReferenceCandidate(
            id: 'saved-character',
            name: 'Character turnaround',
            kind: MediaReferenceKind.image,
            asset: const AssetReference(
              kind: 'remote',
              value: 'https://cdn.test/character.png',
              label: 'character.png',
              contentType: 'image/png',
            ),
            createdAt: now,
          ),
        ],
      );
      await controller.addReferenceCandidates(
        MediaReferenceKind.video,
        <ReferenceCandidate>[
          ReferenceCandidate(
            id: 'generated-motion',
            name: 'Generated motion study',
            kind: MediaReferenceKind.video,
            asset: const AssetReference(
              kind: 'remote',
              value: 'https://cdn.test/motion.mp4',
              label: 'motion.mp4',
              contentType: 'video/mp4',
            ),
            createdAt: now,
            generated: true,
          ),
        ],
      );

      expect(controller.form.references, hasLength(2));
      expect(
        controller.form.references.first.savedReferenceId,
        'saved-character',
      );
      expect(controller.form.references.last.savedReferenceId, isNull);
      final input = controller.buildInputForTesting();
      expect(input['reference_images'], <String>[
        'https://cdn.test/character.png',
      ]);
      expect(input['reference_videos'], <String>[
        'https://cdn.test/motion.mp4',
      ]);
      controller.dispose();
    },
  );

  test(
    'uses and invalidates an iOS-only review key without persisting it',
    () async {
      const reviewKey = 'review-key-that-must-not-be-persisted';
      final store = _MemoryLocalDataStore();
      final gateway = NativeGateway(
        store: store,
        api: _RejectedCreditsApi(),
        iosReviewApiKey: reviewKey,
        iosReviewApiKeyId: 'review-key-id',
        isIos: true,
      );

      expect((await gateway.load()).hasApiKey, isTrue);
      expect(store.data.apiKey, isEmpty);
      expect(store.data.encode(), isNot(contains(reviewKey)));

      await expectLater(
        gateway.getCredits(),
        throwsA(isA<ProviderException>()),
      );
      final invalidated = await gateway.load();
      expect(invalidated.hasApiKey, isFalse);
      expect(store.data.rejectedIosReviewApiKeyId, 'review-key-id');
      expect(store.data.encode(), isNot(contains(reviewKey)));
    },
  );

  test(
    'clears a rejected saved key before falling back to iOS review access',
    () async {
      final store = _MemoryLocalDataStore(
        const StoredData(apiKey: 'saved-user-key'),
      );
      final gateway = NativeGateway(
        store: store,
        api: _RejectedCreditsApi(),
        iosReviewApiKey: 'review-key',
        iosReviewApiKeyId: 'review-key-id',
        isIos: true,
      );

      await expectLater(
        gateway.getCredits(),
        throwsA(isA<ProviderException>()),
      );
      final fallback = await gateway.load();
      expect(fallback.hasApiKey, isTrue);
      expect(store.data.apiKey, isEmpty);
      expect(store.data.rejectedIosReviewApiKeyId, isEmpty);

      await expectLater(
        gateway.getCredits(),
        throwsA(isA<ProviderException>()),
      );
      final exhausted = await gateway.load();
      expect(exhausted.hasApiKey, isFalse);
      expect(store.data.rejectedIosReviewApiKeyId, 'review-key-id');
    },
  );

  test('isolates and invalidates an LTX iOS review key', () async {
    const reviewKey = 'ltx-review-key-that-must-not-be-persisted';
    final store = _MemoryLocalDataStore();
    final gateway = NativeGateway(
      store: store,
      providerRouter: ProviderApiRouter(
        ltx: LtxApi(
          client: MockClient(
            (_) async => http.Response(
              jsonEncode(<String, String>{'error': 'unauthorized'}),
              401,
            ),
          ),
        ),
      ),
      iosReviewLtxApiKey: reviewKey,
      iosReviewLtxApiKeyId: 'ltx-review-key-id',
      isIos: true,
    );

    expect((await gateway.load()).hasApiKeyFor('ltx'), isTrue);
    expect(store.data.encode(), isNot(contains(reviewKey)));
    await expectLater(
      gateway.getProviderAccount('ltx'),
      throwsA(isA<ProviderException>()),
    );
    expect((await gateway.load()).hasApiKeyFor('ltx'), isFalse);
    expect(store.data.rejectedReviewKeyIdFor('ltx'), 'ltx-review-key-id');
    expect(store.data.encode(), isNot(contains(reviewKey)));
  });

  test('does not use the iOS review key on another native platform', () async {
    final gateway = NativeGateway(
      store: _MemoryLocalDataStore(),
      iosReviewApiKey: 'review-key',
      iosReviewApiKeyId: 'review-key-id',
      isIos: false,
    );

    expect((await gateway.load()).hasApiKey, isFalse);
  });

  test('does not advertise retired Apple Local generation on iOS', () async {
    final store = _MemoryLocalDataStore();
    final gateway = NativeGateway(store: store, isIos: true);

    final snapshot = await gateway.load();

    expect(snapshot.preferences.provider, 'bfl');
    expect(snapshot.availableProviders, isNot(contains('apple-local')));
    expect(snapshot.connectedProviders, isNot(contains('apple-local')));
    expect(store.data.apiKey, isEmpty);
  });

  test('rejects legacy Apple Local submissions without a runtime', () async {
    final gateway = NativeGateway(store: _MemoryLocalDataStore(), isIos: true);
    final now = DateTime.utc(2026, 8, 19);
    final image = Generation(
      localId: 'retired-image',
      provider: 'apple-local',
      model: 'apple-local-image',
      billingUnit: 'local',
      outputKind: GenerationOutputKind.image,
      status: 'submitting',
      prompt: 'A painted lighthouse',
      mode: VideoMode.t2v,
      config: const GenerationConfig(
        aspectRatio: '1:1',
        duration: 1,
        resolution: 'hd',
        generateAudio: false,
        safetyTolerance: 2,
        draft: false,
      ),
      createdAt: now,
      updatedAt: now,
    );

    await expectLater(
      gateway.submit(
        GenerationSubmission(record: image, input: const <String, Object?>{}),
      ),
      throwsA(
        isA<StateError>().having(
          (error) => error.message,
          'message',
          contains('retired'),
        ),
      ),
    );
  });

  test(
    'retires active Apple Local jobs without deleting saved media',
    () async {
      final now = DateTime.utc(2026, 8, 19);
      const savedImage = AssetReference(
        kind: 'local',
        value: 'saved-apple-image',
        label: 'saved.png',
        contentType: 'image/png',
      );
      final store = _MemoryLocalDataStore(
        StoredData(
          generations: <Generation>[
            Generation(
              localId: 'pending-apple-image',
              provider: 'apple-local',
              model: 'apple-local-image',
              billingUnit: 'local',
              outputKind: GenerationOutputKind.image,
              status: 'Pending',
              prompt: 'A pending image',
              mode: VideoMode.t2v,
              config: const GenerationConfig(
                aspectRatio: '1:1',
                duration: 1,
                resolution: 'hd',
                generateAudio: false,
                safetyTolerance: 2,
                draft: false,
              ),
              createdAt: now,
              updatedAt: now,
            ),
            Generation(
              localId: 'saved-apple-image',
              provider: 'apple-local',
              model: 'apple-local-image',
              billingUnit: 'local',
              outputKind: GenerationOutputKind.image,
              status: 'Ready',
              prompt: 'A saved image',
              mode: VideoMode.t2v,
              config: const GenerationConfig(
                aspectRatio: '1:1',
                duration: 1,
                resolution: 'hd',
                generateAudio: false,
                safetyTolerance: 2,
                draft: false,
              ),
              createdAt: now,
              updatedAt: now,
              resultAsset: savedImage,
            ),
          ],
        ),
      );

      final snapshot = await NativeGateway(store: store, isIos: true).load();

      final pending = snapshot.generations.first;
      expect(pending.status, 'Error');
      expect(pending.error, contains('retired'));
      final saved = snapshot.generations.last;
      expect(saved.status, 'Ready');
      expect(saved.resultAsset, savedImage);
    },
  );

  test(
    'startup validation clears rejected access and requires another key',
    () async {
      final gateway = _MemoryGateway(
        const LocalSnapshot(
          generations: <Generation>[],
          preferences: AppPreferences(),
          hasApiKey: true,
          storage: StorageStats(path: 'memory', bytes: 0, records: 0),
        ),
        creditError: const ProviderException(
          'BFL rejected this API key.',
          status: 401,
        ),
      );
      final controller = AppController(gateway: gateway);

      await controller.initialize();
      await Future<void>.delayed(Duration.zero);

      expect(gateway.invalidationCount, 1);
      expect(controller.hasApiKey, isFalse);
      expect(controller.section, AppSection.providers);
      expect(controller.creditError, contains('rejected'));
      controller.dispose();
    },
  );

  test('companion-backed access clears a rejected saved key', () async {
    var cleared = false;
    final gateway = WebGateway(
      baseUrl: Uri.parse('http://127.0.0.1:8787'),
      client: MockClient((request) async {
        if (request.url.path == '/account') {
          return http.Response(
            jsonEncode(<String, Object?>{
              'error': 'BFL rejected this API key.',
            }),
            401,
            headers: const <String, String>{'content-type': 'application/json'},
          );
        }
        if (request.method == 'PATCH' && request.url.path == '/state') {
          cleared = true;
          return http.Response(
            jsonEncode(
              const LocalSnapshot(
                generations: <Generation>[],
                preferences: AppPreferences(),
                hasApiKey: false,
                storage: StorageStats(path: 'memory', bytes: 0, records: 0),
              ).toJson(),
            ),
            200,
            headers: const <String, String>{'content-type': 'application/json'},
          );
        }
        return http.Response('not found', 404);
      }),
    );

    await expectLater(gateway.getCredits(), throwsA(isA<ProviderException>()));
    expect(cleared, isTrue);
  });

  test('maps first, middle, and last frame layouts to the BFL contract', () {
    const firstUrl = 'https://cdn.bfl.ai/first.png';
    const middleUrl = 'https://cdn.bfl.ai/middle.png';
    const lastUrl = 'https://cdn.bfl.ai/last.png';

    final endOnly = AppController();
    endOnly.form.durationSeconds = 12;
    endOnly.addUrlFrame(KeyframeRole.end);
    endOnly.updateFrame(endOnly.form.keyframes.single.id, source: lastUrl);
    expect(endOnly.form.autoDuration, isFalse);
    expect(endOnly.form.usesTimedKeyframes, isTrue);
    expect(endOnly.buildInputForTesting()['keyframes'], <Object?>[
      <Object?>[12.0, lastUrl],
    ]);

    final bothEnds = AppController();
    bothEnds.addUrlFrame(KeyframeRole.end);
    bothEnds.updateFrame(bothEnds.form.keyframes.single.id, source: lastUrl);
    bothEnds.addUrlFrame(KeyframeRole.start);
    bothEnds.updateFrame(
      bothEnds.form.keyframes
          .singleWhere((frame) => frame.role == KeyframeRole.start)
          .id,
      source: firstUrl,
    );
    expect(bothEnds.form.usesTimedKeyframes, isFalse);
    expect(bothEnds.buildInputForTesting()['keyframes'], <Object?>[
      firstUrl,
      lastUrl,
    ]);

    final middleOnly = AppController();
    middleOnly.form.durationSeconds = 10;
    middleOnly.addUrlFrame(KeyframeRole.middle);
    middleOnly.updateFrame(
      middleOnly.form.keyframes.single.id,
      source: middleUrl,
    );
    expect(middleOnly.form.usesTimedKeyframes, isTrue);
    expect(middleOnly.buildInputForTesting()['keyframes'], <Object?>[
      <Object?>[5.0, middleUrl],
    ]);
  });

  test(
    'builds model-aware mixed media references without keyframe semantics',
    () {
      final controller = AppController()
        ..selectedProviderId = 'atlas'
        ..selectedModelId = 'bytedance/seedance-2.5/reference-to-video';
      controller.addUrlReference(MediaReferenceKind.image);
      controller.addUrlReference(MediaReferenceKind.video);
      controller.addUrlReference(MediaReferenceKind.audio);
      final references = controller.form.references;
      controller.updateReference(
        references
            .singleWhere((item) => item.kind == MediaReferenceKind.image)
            .id,
        'https://cdn.test/character.png',
      );
      controller.updateReference(
        references
            .singleWhere((item) => item.kind == MediaReferenceKind.video)
            .id,
        'https://cdn.test/motion.mp4',
      );
      controller.updateReference(
        references
            .singleWhere((item) => item.kind == MediaReferenceKind.audio)
            .id,
        'https://cdn.test/voice.mp3',
      );

      final input = controller.buildInputForTesting();
      expect(controller.form.mode, VideoMode.i2v);
      expect(input.containsKey('keyframes'), isFalse);
      expect(input['reference_images'], <String>[
        'https://cdn.test/character.png',
      ]);
      expect(input['reference_videos'], <String>[
        'https://cdn.test/motion.mp4',
      ]);
      expect(input['reference_audios'], <String>['https://cdn.test/voice.mp3']);
      expect(controller.form.referenceCount(MediaReferenceKind.image), 1);
      expect(controller.selectedModel.maxImageReferences, 30);
    },
  );

  test(
    'restores duration and frame settings from the previous generation',
    () async {
      final now = DateTime.utc(2026, 8, 15);
      final gateway = _MemoryGateway(
        LocalSnapshot(
          generations: <Generation>[
            Generation(
              localId: 'previous',
              status: 'Ready',
              prompt: 'Do not restore this prompt.',
              mode: VideoMode.i2v,
              config: const GenerationConfig(
                aspectRatio: '21:9',
                duration: 14,
                resolution: 'fhd',
                generateAudio: false,
                safetyTolerance: 1,
                draft: false,
                exactTiming: true,
                keyframes: <KeyframeLabel>[
                  KeyframeLabel(
                    label: 'ending.png',
                    role: KeyframeRole.end,
                    seconds: 14,
                    source: AssetReference(
                      kind: 'remote',
                      value: 'https://cdn.bfl.ai/ending.png',
                      label: 'ending.png',
                    ),
                  ),
                ],
              ),
              createdAt: now,
              updatedAt: now,
            ),
          ],
          preferences: const AppPreferences(),
          hasApiKey: false,
          storage: const StorageStats(path: 'memory', bytes: 1, records: 1),
        ),
      );
      final controller = AppController(gateway: gateway);

      await controller.initialize();

      expect(controller.form.prompt, isEmpty);
      expect(controller.form.mode, VideoMode.i2v);
      expect(controller.form.aspectRatio, '21:9');
      expect(controller.form.autoDuration, isFalse);
      expect(controller.form.durationSeconds, 14);
      expect(controller.form.keyframes.single.role, KeyframeRole.end);
      expect(controller.form.keyframes.single.seconds, 14);
      controller.dispose();
    },
  );

  test('restoring a model constrains the form like selecting it', () async {
    final now = DateTime.utc(2026, 8, 19);
    final gateway = _MemoryGateway(
      LocalSnapshot(
        generations: <Generation>[
          Generation(
            localId: 'legacy-auto',
            status: 'Ready',
            prompt: 'A legacy setting that the selected model cannot use.',
            mode: VideoMode.t2v,
            config: const GenerationConfig(
              aspectRatio: '16:9',
              duration: 'auto',
              resolution: 'qhd',
              generateAudio: true,
              safetyTolerance: 2,
              draft: false,
              exactTiming: true,
            ),
            createdAt: now,
            updatedAt: now,
          ),
        ],
        // LTX 2.3 Fast supports neither Auto duration nor timed keyframes.
        preferences: const AppPreferences(
          provider: 'ltx',
          model: 'ltx-2-3-fast',
        ),
        hasApiKey: false,
        storage: const StorageStats(path: 'memory', bytes: 0, records: 0),
      ),
    );
    final controller = AppController(gateway: gateway);
    await controller.initialize();
    expect(controller.selectedModelId, 'ltx-2-3-fast');
    expect(controller.form.autoDuration, isFalse);
    expect(controller.form.exactTiming, isFalse);
    expect(controller.form.durationSeconds, 8);
    controller.dispose();
  });

  test('Seedance pinned frames and references are either-or', () async {
    final gateway = _MemoryGateway(
      const LocalSnapshot(
        generations: <Generation>[],
        preferences: AppPreferences(
          provider: 'artcraft',
          model: 'seedance_2p5',
        ),
        hasApiKey: true,
        connectedProviders: <String>{'artcraft'},
        storage: StorageStats(path: 'memory', bytes: 0, records: 0),
      ),
    );
    final controller = AppController(gateway: gateway);
    await controller.initialize();
    expect(controller.selectedModelId, 'seedance_2p5');

    // Attaching a reference sets pinned frames aside.
    controller.addUrlReference(MediaReferenceKind.image);
    expect(controller.form.references, hasLength(1));
    expect(controller.framesBlockedByReferences, isTrue);
    expect(controller.canAddFrame(KeyframeRole.start), isFalse);
    controller.addUrlFrame(KeyframeRole.start);
    expect(controller.form.keyframes, isEmpty);

    // Removing the reference restores frames, and pinning a frame then
    // sets references aside.
    controller.removeReference(controller.form.references.single.id);
    expect(controller.canAddFrame(KeyframeRole.start), isTrue);
    controller.addUrlFrame(KeyframeRole.start);
    expect(controller.form.keyframes, hasLength(1));
    expect(controller.referencesBlockedByFrames, isTrue);
    expect(controller.canAddReference(MediaReferenceKind.image), isFalse);
    controller.addUrlReference(MediaReferenceKind.image);
    expect(controller.form.references, isEmpty);

    // A conflicted form (possible through reuse or model switches) cannot
    // be submitted.
    controller.form.prompt = 'A machinist polishes a knob.';
    controller.updateFrame(
      controller.form.keyframes.single.id,
      source: 'https://example.com/first.png',
    );
    controller.form.references = <MediaReferenceDraft>[
      MediaReferenceDraft(
        id: 'ref-1',
        kind: MediaReferenceKind.image,
        label: 'style.png',
        source: 'https://example.com/style.png',
      ),
    ];
    expect(
      controller.validate(),
      contains('takes pinned frames or creative references'),
    );
    // Let the startup credit refresh settle before tearing down.
    await Future<void>.delayed(const Duration(milliseconds: 10));
    controller.dispose();
  });

  test('provider guidance caps normalize totals and duration', () {
    final h3 = AppController()
      ..selectedProviderId = 'artcraft'
      ..selectedModelId = 'minimax_h3';
    for (var index = 0; index < 9; index += 1) {
      h3.addUrlReference(MediaReferenceKind.image);
    }
    for (var index = 0; index < 3; index += 1) {
      h3.addUrlReference(MediaReferenceKind.video);
    }
    expect(h3.form.references, hasLength(12));
    expect(h3.canAddReference(MediaReferenceKind.audio), isFalse);
    expect(h3.canAddFrame(KeyframeRole.start), isFalse);
    h3.dispose();

    final grok = AppController()
      ..selectedProviderId = 'artcraft'
      ..selectedModelId = 'grok_imagine_video';
    grok.form.durationSeconds = 15;
    grok.addUrlReference(MediaReferenceKind.image);
    expect(grok.selectedDurationRange.maximumSeconds, 10);
    expect(grok.form.durationSeconds, 10);
    grok.dispose();
  });

  test('reuse recreates the exact stored request for every mode', () async {
    final gateway = _MemoryGateway(
      const LocalSnapshot(
        generations: <Generation>[],
        preferences: AppPreferences(),
        hasApiKey: false,
        storage: StorageStats(path: 'memory', bytes: 0, records: 0),
      ),
    );
    final controller = AppController(gateway: gateway);
    final now = DateTime.utc(2026, 8, 15);
    const config = GenerationConfig(
      aspectRatio: '21:9',
      duration: 12,
      resolution: 'fhd',
      generateAudio: false,
      safetyTolerance: 1,
      draft: false,
    );
    Generation generation(
      VideoMode mode, {
      GenerationConfig generationConfig = config,
    }) => Generation(
      localId: mode.name,
      status: 'Ready',
      prompt: 'Restore this exact direction.',
      mode: mode,
      config: generationConfig,
      createdAt: now,
      updatedAt: now,
    );
    const common = <String, Object?>{
      'prompt': 'Restore this exact direction.',
      'aspect_ratio': '21:9',
      'duration': 12,
      'resolution': 'fhd',
      'version': 'latest',
      'generate_audio': false,
      'safety_tolerance': 1,
      'draft': false,
    };

    controller.updateForm((form) => form.prompt = 'Stale editor text.');
    await controller.reuse(generation(VideoMode.t2v));
    expect(controller.form.prompt, 'Restore this exact direction.');
    expect(controller.buildInputForTesting(), <String, Object?>{
      ...common,
      'mode': 't2v',
    });

    const firstFrame = 'https://cdn.bfl.ai/first.png';
    const lastFrame = 'https://cdn.bfl.ai/last.png';
    await controller.reuse(
      generation(
        VideoMode.i2v,
        generationConfig: const GenerationConfig(
          aspectRatio: '21:9',
          duration: 12,
          resolution: 'fhd',
          generateAudio: false,
          safetyTolerance: 1,
          draft: false,
          exactTiming: true,
          keyframes: <KeyframeLabel>[
            KeyframeLabel(
              label: 'first.png',
              role: KeyframeRole.start,
              seconds: 0,
              source: AssetReference(
                kind: 'remote',
                value: firstFrame,
                label: 'first.png',
              ),
            ),
            KeyframeLabel(
              label: 'last.png',
              role: KeyframeRole.end,
              seconds: 12,
              source: AssetReference(
                kind: 'remote',
                value: lastFrame,
                label: 'last.png',
              ),
            ),
          ],
        ),
      ),
    );
    expect(controller.buildInputForTesting(), <String, Object?>{
      ...common,
      'mode': 'i2v',
      'keyframes': <Object?>[
        <Object?>[0.0, firstFrame],
        <Object?>[12.0, lastFrame],
      ],
    });

    const sourceVideo = 'https://cdn.bfl.ai/source.mp4';
    await controller.reuse(
      generation(
        VideoMode.v2v,
        generationConfig: const GenerationConfig(
          aspectRatio: '21:9',
          duration: 12,
          resolution: 'fhd',
          generateAudio: false,
          safetyTolerance: 1,
          draft: false,
          source: AssetReference(
            kind: 'remote',
            value: sourceVideo,
            label: 'source.mp4',
          ),
        ),
      ),
    );
    expect(controller.buildInputForTesting(), <String, Object?>{
      ...common,
      'mode': 'v2v',
      'start_video': sourceVideo,
    });

    const draftCache = 'https://cdn.bfl.ai/draft-cache.zip';
    await controller.reuse(
      generation(
        VideoMode.draftEnhance,
        generationConfig: const GenerationConfig(
          aspectRatio: '16:9',
          duration: 8,
          resolution: 'fhd',
          generateAudio: true,
          safetyTolerance: 3,
          draft: false,
          source: AssetReference(
            kind: 'remote',
            value: draftCache,
            label: 'draft-cache.zip',
          ),
        ),
      ),
    );
    expect(controller.form.mode, VideoMode.draftEnhance);
    expect(controller.buildInputForTesting(), <String, Object?>{
      'mode': 'draft_enhance',
      'draft_cache': draftCache,
      'resolution': 'fhd',
      'safety_tolerance': 3,
    });
    controller.dispose();
  });

  testWidgets('Reuse inputs replaces the visible prompt on desktop', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1400, 1000));
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.binding.setSurfaceSize(null);
    });
    final now = DateTime.utc(2026, 8, 15);
    final item = Generation(
      localId: 'desktop-reuse',
      status: 'Ready',
      prompt: 'The restored desktop prompt.',
      mode: VideoMode.t2v,
      config: const GenerationConfig(
        aspectRatio: '21:9',
        duration: 17,
        resolution: 'fhd',
        generateAudio: false,
        safetyTolerance: 1,
        draft: false,
      ),
      createdAt: now,
      updatedAt: now,
    );
    final controller = AppController(
      gateway: _MemoryGateway(
        LocalSnapshot(
          generations: <Generation>[item],
          preferences: const AppPreferences(),
          hasApiKey: false,
          storage: const StorageStats(path: 'memory', bytes: 1, records: 1),
        ),
      ),
    );
    await controller.initialize();
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

    Finder promptField() => find.byKey(
      ValueKey<String>('generation-prompt-${controller.formRevision}'),
    );
    await tester.enterText(promptField(), 'Stale visible desktop prompt.');
    // Recent work renders the Library's full cards, whose reuse button
    // carries the shared 'Reuse' label.
    await tester.ensureVisible(find.text('Reuse'));
    await tester.tap(find.text('Reuse'));
    await tester.pumpAndSettle();

    final editable = tester.widget<EditableText>(
      find.descendant(of: promptField(), matching: find.byType(EditableText)),
    );
    expect(editable.controller.text, 'The restored desktop prompt.');
    expect(controller.form.prompt, 'The restored desktop prompt.');
    expect(controller.form.mode, VideoMode.t2v);
    expect(controller.form.aspectRatio, '21:9');
    expect(controller.form.durationSeconds, 17);
    expect(controller.form.resolution, 'fhd');
    expect(controller.form.generateAudio, isFalse);
    expect(controller.form.safetyTolerance, 1);
    controller.dispose();
  });

  testWidgets('duration control follows model Auto support and range', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1400, 1200));
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.binding.setSurfaceSize(null);
    });
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

    expect(controller.form.autoDuration, isFalse);
    expect(find.byKey(const ValueKey('duration-mode-switch')), findsOneWidget);
    expect(find.byKey(const ValueKey('duration-slider')), findsOneWidget);
    expect(find.byKey(const ValueKey('auto-duration-range')), findsNothing);

    final auto = find.byKey(const ValueKey('duration-mode-auto'));
    await tester.ensureVisible(auto);
    await tester.tap(auto);
    await tester.pumpAndSettle();
    expect(controller.form.autoDuration, isTrue);
    expect(find.byKey(const ValueKey('duration-slider')), findsNothing);
    expect(find.byKey(const ValueKey('auto-duration-range')), findsOneWidget);
    expect(find.textContaining('5–20 seconds'), findsOneWidget);

    await controller.selectProvider('ltx');
    controller.updateForm((form) => form.resolution = 'qhd');
    await tester.pumpAndSettle();
    expect(controller.form.autoDuration, isFalse);
    expect(find.byKey(const ValueKey('duration-mode-switch')), findsNothing);
    final slider = tester.widget<HardwareSlider>(
      find.byKey(const ValueKey('duration-slider')),
    );
    expect((slider.min, slider.max, slider.divisions), (6, 10, 2));
    controller.dispose();
  });

  testWidgets('duration readout accepts typed seconds and clamps to range', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1400, 1200));
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.binding.setSurfaceSize(null);
    });
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

    final input = find.byKey(const ValueKey('duration-input'));
    expect(input, findsOneWidget);

    // Typing commits on submit and snaps into the model's range.
    await tester.enterText(input, '999');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();
    expect(controller.form.durationSeconds, 20);

    await tester.enterText(input, '2');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();
    expect(controller.form.durationSeconds, 5);

    // Starting to type while AUTO is active takes manual control, exactly
    // like touching the slider.
    await tester.tap(find.byKey(const ValueKey('duration-mode-auto')));
    await tester.pumpAndSettle();
    expect(controller.form.autoDuration, isTrue);
    await tester.enterText(input, '7');
    await tester.pumpAndSettle();
    expect(controller.form.autoDuration, isFalse);
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();
    expect(controller.form.durationSeconds, 7);
    expect(find.byKey(const ValueKey('duration-slider')), findsOneWidget);
    controller.dispose();
  });

  testWidgets('frame and finish dropdowns choose ratio and resolution', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1400, 1200));
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.binding.setSurfaceSize(null);
    });
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

    // The trigger wears the drawn glyph for the current ratio.
    final ratioTrigger = find.byKey(const ValueKey('ratio-dropdown'));
    await tester.ensureVisible(ratioTrigger);
    await tester.tap(ratioTrigger);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('ratio-21:9')));
    await tester.pumpAndSettle();
    expect(controller.form.aspectRatio, '21:9');

    final resolutionTrigger = find.byKey(const ValueKey('resolution-dropdown'));
    await tester.ensureVisible(resolutionTrigger);
    await tester.tap(resolutionTrigger);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('resolution-fhd')));
    await tester.pumpAndSettle();
    expect(controller.form.resolution, 'fhd');

    // Draft mode dims every choice but the provider's HD draft tier.
    controller.updateForm((form) => form.draft = true);
    await tester.pumpAndSettle();
    await tester.tap(resolutionTrigger);
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<PopupMenuItem<String>>(
            find.byKey(const ValueKey('resolution-fhd')),
          )
          .enabled,
      isFalse,
    );
    expect(
      tester
          .widget<PopupMenuItem<String>>(
            find.byKey(const ValueKey('resolution-hd')),
          )
          .enabled,
      isTrue,
    );
    controller.dispose();
  });

  testWidgets('seed control appears only for Wan and survives reuse', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1400, 1600));
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.binding.setSurfaceSize(null);
    });
    final controller = AppController(
      gateway: _MemoryGateway(
        const LocalSnapshot(
          generations: <Generation>[],
          preferences: AppPreferences(
            provider: 'atlas',
            model: 'alibaba/wan-2.7/text-to-video',
          ),
          hasApiKey: false,
          storage: StorageStats(path: 'memory', bytes: 0, records: 0),
        ),
      ),
    );
    await controller.initialize();
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

    final seedInput = find.byKey(const ValueKey('seed-input'));
    expect(seedInput, findsOneWidget);
    await tester.ensureVisible(seedInput);
    await tester.enterText(seedInput, '424242');
    await tester.pump();
    expect(controller.form.seed, 424242);
    expect(controller.buildInputForTesting()['seed'], 424242);

    // The dice rolls a fresh explicit seed; clearing returns to random.
    await tester.ensureVisible(find.byTooltip('New random seed'));
    await tester.tap(find.byTooltip('New random seed'));
    await tester.pump();
    expect(controller.form.seed, isNotNull);
    await tester.enterText(seedInput, '');
    await tester.pump();
    expect(controller.form.seed, isNull);
    expect(controller.buildInputForTesting(), isNot(contains('seed')));

    // Reuse restores a stored seed with the rest of the request.
    final now = DateTime.utc(2026, 8, 20);
    await controller.reuse(
      Generation(
        localId: 'wan-seeded',
        provider: 'atlas',
        model: 'alibaba/wan-2.7/text-to-video',
        status: 'Ready',
        prompt: 'Same take again.',
        mode: VideoMode.t2v,
        config: const GenerationConfig(
          aspectRatio: '16:9',
          duration: 8,
          resolution: 'hd',
          generateAudio: true,
          safetyTolerance: 2,
          draft: false,
          seed: 90210,
        ),
        createdAt: now,
        updatedAt: now,
      ),
    );
    await tester.pumpAndSettle();
    expect(controller.selectedModelId, 'alibaba/wan-2.7/text-to-video');
    expect(controller.form.seed, 90210);
    expect(controller.buildInputForTesting()['seed'], 90210);

    // A model without seed support hides the control and clears the value.
    await controller.selectModel('google/veo3.1-fast/text-to-video');
    await tester.pumpAndSettle();
    expect(controller.form.seed, isNull);
    expect(find.byKey(const ValueKey('seed-input')), findsNothing);

    // The stored config round-trips seed through JSON, tolerating absence.
    const seeded = GenerationConfig(
      aspectRatio: '16:9',
      duration: 8,
      resolution: 'hd',
      generateAudio: true,
      safetyTolerance: 2,
      draft: false,
      seed: 90210,
    );
    expect(GenerationConfig.fromJson(seeded.toJson()).seed, 90210);
    expect(
      GenerationConfig.fromJson(
        const GenerationConfig(
          aspectRatio: '16:9',
          duration: 8,
          resolution: 'hd',
          generateAudio: true,
          safetyTolerance: 2,
          draft: false,
        ).toJson(),
      ).seed,
      isNull,
    );
    controller.dispose();
  });

  testWidgets('create screen fits above the fold at 1440x900', (tester) async {
    tester.view.physicalSize = const Size(1440, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
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

    // Short viewports drop the heading description and tighten spacing.
    expect(find.textContaining('Direct one continuous moment'), findsNothing);

    // Cost and save-destination share one row at desktop widths.
    expect(find.byKey(const ValueKey('cost-destination-row')), findsOneWidget);

    // Every generation option through Generate sits above the fold, with
    // the Recent work header peeking in below — all without scrolling.
    final generate = find.text('Generate video');
    expect(generate, findsOneWidget);
    expect(tester.getBottomLeft(generate).dy, lessThan(900));
    final recentHeader = find.text('Recent work');
    expect(recentHeader, findsOneWidget);
    expect(tester.getTopLeft(recentHeader).dy, lessThan(900));
    controller.dispose();
  });

  testWidgets('console-only balances stay off the cost panel', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1400, 1200));
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.binding.setSurfaceSize(null);
    });
    final controller = AppController(
      gateway: _ProviderMemoryGateway(
        const LocalSnapshot(
          generations: <Generation>[],
          preferences: AppPreferences(
            provider: 'artcraft',
            model: 'seedance_2p0',
          ),
          hasApiKey: true,
          connectedProviders: <String>{'artcraft'},
          storage: StorageStats(path: 'memory', bytes: 0, records: 0),
        ),
        const ProviderAccountStatus(
          provider: 'artcraft',
          currency: 'credits',
          balanceLabel: 'Open ArtCraft to view balance ↗',
        ),
      ),
    );
    await controller.initialize();
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

    // The felt carries only the estimate; the top-right balance pill owns
    // "open the provider console to view the balance".
    expect(find.text('ESTIMATED CHARGE'), findsOneWidget);
    expect(find.text('Rate card ↗'), findsOneWidget);
    expect(find.text('Open ArtCraft to view balance ↗'), findsNothing);
    expect(find.text('AVAILABLE NOW'), findsNothing);
    expect(find.text('ESTIMATED AFTER'), findsNothing);
    expect(find.byTooltip('Open provider console'), findsNothing);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
    controller.dispose();

    // A numeric balance keeps the estimated-after line.
    final bflController = AppController(
      gateway: _ProviderMemoryGateway(
        const LocalSnapshot(
          generations: <Generation>[],
          preferences: AppPreferences(),
          hasApiKey: true,
          storage: StorageStats(path: 'memory', bytes: 0, records: 0),
        ),
        const ProviderAccountStatus(
          provider: 'bfl',
          balance: 125,
          currency: 'credits',
        ),
      ),
    );
    await bflController.initialize();
    await tester.pumpWidget(
      MaterialApp(
        theme: buildClawnsoleTheme(Brightness.light),
        home: Scaffold(
          body: AnimatedBuilder(
            animation: bflController,
            builder: (context, _) => CreateScreen(controller: bflController),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('ESTIMATED AFTER'), findsOneWidget);
    expect(find.text('AVAILABLE NOW'), findsNothing);
    bflController.dispose();
  });

  testWidgets('mobile provider plaque and estimate align to the right edge', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(390, 1000));
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.binding.setSurfaceSize(null);
    });
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
    await controller.selectProviderModel('artcraft', 'seedance_2p5');
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

    expect(find.text('Model & Provider:'), findsNothing);
    expect(find.text('Make it move.'), findsNothing);
    expect(find.text('VIDEO STUDIO'), findsNothing);
    final plaque = find.byKey(const ValueKey('provider-plaque'));
    expect(tester.getTopRight(plaque).dx, closeTo(374, .1));

    expect(find.text('REFERENCES'), findsOneWidget);
    expect(find.textContaining('REQUIRED'), findsNothing);
    expect(find.text('Or continue a video'), findsNothing);
    expect(find.text('Or enhance a saved draft'), findsNothing);
    expect(
      tester.getTopLeft(find.byKey(const ValueKey('add-image-reference'))).dy,
      greaterThan(tester.getBottomLeft(find.text('REFERENCES')).dy),
    );

    final panel = find.byKey(const ValueKey('estimated-charge-panel'));
    final rate = find.byKey(const ValueKey('estimate-rate'));
    final credits = find.byKey(const ValueKey('estimate-provider-units'));
    final rateRight = tester.getTopRight(rate).dx;
    final creditsRight = tester.getTopRight(credits).dx;
    expect(rateRight, closeTo(creditsRight, .1));
    expect(tester.getTopRight(panel).dx - rateRight, inInclusiveRange(13, 16));
    controller.dispose();
  });

  testWidgets('mobile Save To right-aligns the storage choices', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(390, 1400));
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.binding.setSurfaceSize(null);
    });
    const snapshot = LocalSnapshot(
      generations: <Generation>[],
      preferences: AppPreferences(),
      hasApiKey: false,
      storage: StorageStats(path: 'memory', bytes: 0, records: 0),
    );
    final gateway = _ResumableDriveGateway(
      snapshot,
      configured: true,
      resumed: snapshot,
    );
    await gateway.connectGoogleDrive('Clawnsole');
    final controller = AppController(gateway: gateway);
    await controller.initialize();
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

    final panel = find.byKey(const ValueKey('generation-destination-panel'));
    final drive = find.widgetWithText(ChoiceChip, 'Drive');
    expect(find.widgetWithText(ChoiceChip, 'Local'), findsOneWidget);
    expect(drive, findsOneWidget);
    expect(
      tester.getTopRight(panel).dx - tester.getTopRight(drive).dx,
      inInclusiveRange(11, 13),
    );
    controller.dispose();
  });

  testWidgets('desktop estimate gives more room to save controls', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1400, 1000));
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.binding.setSurfaceSize(null);
    });
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

    expect(
      tester
          .getSize(find.byKey(const ValueKey('estimated-charge-panel')))
          .width,
      lessThanOrEqualTo(
        tester
            .getSize(find.byKey(const ValueKey('generation-destination-panel')))
            .width,
      ),
    );
    controller.dispose();
  });

  testWidgets('provider picker collapses and expands provider models', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1400, 1000));
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.binding.setSurfaceSize(null);
    });
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

    // The label sits beside the plaque card rather than inside it.
    final plaqueLabel = find.text('Model & Provider:');
    expect(plaqueLabel, findsOneWidget);
    expect(
      find.ancestor(of: plaqueLabel, matching: find.byType(TexturePanel)),
      findsNothing,
    );
    await tester.tap(find.byTooltip('Choose provider and model'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('provider-model-search')), findsOneWidget);

    const bflOption = ValueKey('provider-model-option-bfl-flux-3-video');
    const artcraftOption = ValueKey(
      'provider-model-option-artcraft-seedance_2p0',
    );
    const artcraftHeading = ValueKey('provider-model-heading-artcraft');
    expect(find.byKey(bflOption), findsOneWidget);
    expect(find.byKey(artcraftOption), findsNothing);

    await tester.ensureVisible(find.byKey(artcraftHeading));
    await tester.tap(find.byKey(artcraftHeading));
    await tester.pumpAndSettle();
    expect(find.byKey(artcraftOption), findsOneWidget);

    await tester.tap(find.byKey(artcraftHeading));
    await tester.pumpAndSettle();
    expect(find.byKey(artcraftOption), findsNothing);

    await tester.tap(find.byKey(artcraftHeading));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byKey(artcraftOption));
    await tester.tap(find.byKey(artcraftOption));
    await tester.pumpAndSettle();
    expect(controller.selectedProviderId, 'artcraft');
    expect(controller.selectedModelId, 'seedance_2p0');
    controller.dispose();
  });

  testWidgets('cross-provider model taps apply before the preference write', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1400, 1000));
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.binding.setSurfaceSize(null);
    });
    final gateway = _DelayedPreferencesGateway(
      const LocalSnapshot(
        generations: <Generation>[],
        preferences: AppPreferences(),
        hasApiKey: false,
        storage: StorageStats(path: 'memory', bytes: 0, records: 0),
      ),
    );
    final controller = AppController(gateway: gateway);
    await controller.initialize();
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
    expect(controller.selectedProviderId, 'bfl');

    await tester.tap(find.byTooltip('Choose provider and model'));
    await tester.pumpAndSettle();
    const artcraftHeading = ValueKey('provider-model-heading-artcraft');
    const artcraftOption = ValueKey(
      'provider-model-option-artcraft-seedance_2p0',
    );
    await tester.ensureVisible(find.byKey(artcraftHeading));
    await tester.tap(find.byKey(artcraftHeading));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byKey(artcraftOption));
    await tester.tap(find.byKey(artcraftOption));
    await tester.pumpAndSettle();

    // The tapped model is active immediately: the store write is still
    // pending, and the form already offers that model's options.
    expect(gateway.pendingPreferences, hasLength(1));
    expect(controller.selectedProviderId, 'artcraft');
    expect(controller.selectedModelId, 'seedance_2p0');
    final tapped = modelById('artcraft', 'seedance_2p0');
    expect(
      controller.availableResolutions.map((item) => item.id).toList(),
      tapped.resolutions.map((item) => item.id).toList(),
    );
    expect(
      controller.availableAspectRatios,
      tapped.aspectRatiosFor(controller.form.resolution, withFrames: false),
    );

    // The preference write still lands once the store catches up.
    while (gateway.pendingPreferences.isNotEmpty) {
      await gateway.completeNextPreference();
    }
    await tester.pumpAndSettle();
    expect(gateway.snapshot.preferences.provider, 'artcraft');
    expect(gateway.snapshot.preferences.model, 'seedance_2p0');
    expect(controller.selectedProviderId, 'artcraft');
    expect(controller.selectedModelId, 'seedance_2p0');
    controller.dispose();
  });

  testWidgets('provider picker filters models and provider sections', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1400, 1000));
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.binding.setSurfaceSize(null);
    });
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

    await tester.tap(find.byTooltip('Choose provider and model'));
    await tester.pumpAndSettle();
    final search = find.byKey(const ValueKey('provider-model-search'));

    await tester.enterText(search, 'Veo 3.1 Fast');
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('provider-model-heading-artcraft')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('provider-model-heading-atlas')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('provider-model-heading-bfl')),
      findsNothing,
    );
    expect(
      find.byKey(const ValueKey('provider-model-option-artcraft-veo_3p1_fast')),
      findsOneWidget,
    );

    await tester.enterText(search, 'LTX Studio');
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('provider-model-heading-ltx')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('provider-model-heading-artcraft')),
      findsNothing,
    );
    expect(
      find.byKey(const ValueKey('provider-model-option-ltx-ltx-2-3-fast')),
      findsOneWidget,
    );

    await tester.enterText(search, 'no such model');
    await tester.pumpAndSettle();
    expect(find.text('No models or providers match.'), findsOneWidget);
    controller.dispose();
  });

  testWidgets(
    'provider section headings stay dark and readable in both themes',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(1400, 1000));
      addTearDown(() async {
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.binding.setSurfaceSize(null);
      });

      for (final brightness in Brightness.values) {
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
        await tester.pumpWidget(
          MaterialApp(
            theme: buildClawnsoleTheme(brightness),
            home: Scaffold(body: CreateScreen(controller: controller)),
          ),
        );
        await tester.pumpAndSettle();
        await tester.tap(find.byTooltip('Choose provider and model'));
        await tester.pumpAndSettle();

        final backgroundFinder = find.byKey(
          const ValueKey('provider-model-heading-background-bfl'),
        );
        final background = tester.widget<ColoredBox>(backgroundFinder).color;
        final heading = tester.widget<Text>(find.text('BLACK FOREST LABS'));
        final foreground = heading.style!.color!;
        final surface = Theme.of(
          tester.element(backgroundFinder),
        ).colorScheme.surface;
        final lighter =
            foreground.computeLuminance() > background.computeLuminance()
            ? foreground
            : background;
        final darker = identical(lighter, foreground) ? background : foreground;
        final contrast =
            (lighter.computeLuminance() + .05) /
            (darker.computeLuminance() + .05);

        expect(
          background.computeLuminance(),
          lessThan(surface.computeLuminance()),
        );
        expect(contrast, greaterThanOrEqualTo(4.5));
        Navigator.of(tester.element(backgroundFinder)).pop();
        await tester.pumpAndSettle();
        controller.dispose();
      }
    },
  );

  testWidgets('either-or models set the unused input side aside on Create', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1400, 1600));
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.binding.setSurfaceSize(null);
    });
    final controller = AppController()
      ..selectedProviderId = 'artcraft'
      ..selectedModelId = 'seedance_2p5';
    Future<void> pump() => tester.pumpWidget(
      MaterialApp(
        theme: buildClawnsoleTheme(Brightness.light),
        home: Scaffold(
          body: SingleChildScrollView(
            child: CreateScreen(controller: controller),
          ),
        ),
      ),
    );

    // Empty form: both sections are offered with one compact either-or note.
    await pump();
    expect(find.textContaining('2 frames max · first + last'), findsOneWidget);
    expect(
      find.textContaining(
        'use first/last frames or creative references, not both',
      ),
      findsOneWidget,
    );
    expect(find.textContaining('Guide identity'), findsNothing);
    expect(find.textContaining('Type @'), findsNothing);
    expect(find.text('First frame'), findsOneWidget);
    expect(find.byKey(const ValueKey('add-image-reference')), findsOneWidget);

    // A pinned frame sets the references side aside.
    controller.addUrlFrame(KeyframeRole.start);
    await pump();
    await tester.pump();
    expect(
      find.textContaining(
        'Frames attached — remove them to add creative references',
      ),
      findsOneWidget,
    );
    expect(find.byKey(const ValueKey('add-image-reference')), findsNothing);

    // A reference sets the frames side aside instead.
    controller.removeFrame(controller.form.keyframes.single.id);
    controller.addUrlReference(MediaReferenceKind.image);
    await pump();
    await tester.pump();
    expect(
      find.textContaining('References attached — remove them to add frames'),
      findsOneWidget,
    );
    expect(find.text('First frame'), findsNothing);

    // A conflicted form (through reuse or a model switch) warns on both
    // sections.
    controller.form.keyframes = <KeyframeDraft>[
      const KeyframeDraft(
        id: 'frame-1',
        role: KeyframeRole.start,
        label: 'first.png',
        source: 'https://example.com/first.png',
        seconds: 0,
      ),
    ];
    await pump();
    await tester.pump();
    expect(
      find.textContaining(
        'cannot combine first/last frames or creative references',
      ),
      findsOneWidget,
    );
    controller.dispose();
  });

  testWidgets(
    'Atlas reference models expose separate image video and audio inputs',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(1400, 1200));
      addTearDown(() async {
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.binding.setSurfaceSize(null);
      });
      final controller = AppController()
        ..selectedProviderId = 'atlas'
        ..selectedModelId = 'bytedance/seedance-2.5/reference-to-video';
      await tester.pumpWidget(
        MaterialApp(
          theme: buildClawnsoleTheme(Brightness.light),
          home: Scaffold(body: CreateScreen(controller: controller)),
        ),
      );

      expect(
        find.byKey(const ValueKey('media-references-section')),
        findsOneWidget,
      );
      expect(find.byKey(const ValueKey('add-image-reference')), findsOneWidget);
      expect(find.byKey(const ValueKey('add-video-reference')), findsOneWidget);
      expect(find.byKey(const ValueKey('add-audio-reference')), findsOneWidget);
      expect(find.textContaining('30 images'), findsOneWidget);
      expect(find.textContaining('10 videos'), findsOneWidget);
      expect(find.textContaining('10 audio clips'), findsOneWidget);
      expect(
        find.byKey(const ValueKey('reference-task-reference')),
        findsOneWidget,
      );
      expect(find.byKey(const ValueKey('reference-task-edit')), findsOneWidget);
      expect(
        find.byKey(const ValueKey('reference-task-extend')),
        findsOneWidget,
      );
      await tester.tap(find.byKey(const ValueKey('reference-task-edit')));
      controller.addUrlReference(MediaReferenceKind.video);
      controller.addUrlReference(MediaReferenceKind.video);
      expect(controller.form.referenceTask, MediaReferenceTask.edit);
      expect(controller.form.aspectRatio, 'auto');
      expect(controller.form.autoDuration, isTrue);
      expect(controller.form.referenceCount(MediaReferenceKind.video), 1);
      expect(controller.buildInputForTesting()['reference_task'], 'edit');
      controller.dispose();
    },
  );

  testWidgets('prompt reference tags autocomplete and highlight', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1400, 1400));
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.binding.setSurfaceSize(null);
    });
    final controller = AppController()
      ..selectedProviderId = 'atlas'
      ..selectedModelId = 'bytedance/seedance-2.5/reference-to-video';
    controller.form.references = const <MediaReferenceDraft>[
      MediaReferenceDraft(
        id: 'image-reference',
        label: 'hero.png',
        kind: MediaReferenceKind.image,
        source: 'https://cdn.test/hero.png',
      ),
      MediaReferenceDraft(
        id: 'video-reference',
        label: 'camera-move.mp4',
        kind: MediaReferenceKind.video,
        source: 'https://cdn.test/camera-move.mp4',
      ),
    ];
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      MaterialApp(
        theme: buildClawnsoleTheme(Brightness.light),
        home: Scaffold(body: CreateScreen(controller: controller)),
      ),
    );

    final prompt = find.byKey(
      ValueKey<String>('generation-prompt-${controller.formRevision}'),
    );
    await tester.enterText(prompt, 'Follow @');
    await tester.pump();

    expect(
      find.byKey(const ValueKey('prompt-reference-suggestions')),
      findsOneWidget,
    );
    expect(find.text('@Image 1'), findsOneWidget);
    expect(find.text('@Video 1'), findsOneWidget);
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('prompt-reference-suggestions')),
        matching: find.text('camera-move.mp4'),
      ),
      findsOneWidget,
    );

    await tester.tap(find.byKey(const ValueKey('prompt-reference-video1')));
    await tester.pump();

    final editable = tester.widget<EditableText>(
      find.descendant(of: prompt, matching: find.byType(EditableText)),
    );
    expect(editable.controller.text, 'Follow @Video 1');
    expect(controller.form.prompt, 'Follow @Video 1');
    expect(
      find.byKey(const ValueKey('prompt-reference-suggestions')),
      findsNothing,
    );

    final span = editable.controller.buildTextSpan(
      context: tester.element(
        find.descendant(of: prompt, matching: find.byType(EditableText)),
      ),
      withComposing: false,
    );
    final highlighted = span.children!
        .whereType<TextSpan>()
        .where((child) => child.text == '@Video 1')
        .single;
    expect(highlighted.style?.backgroundColor, isNotNull);
    expect(highlighted.style?.fontWeight, FontWeight.w700);

    await tester.enterText(prompt, 'Use @image1 for the subject');
    await tester.pump();
    final typedSpan = editable.controller.buildTextSpan(
      context: tester.element(
        find.descendant(of: prompt, matching: find.byType(EditableText)),
      ),
      withComposing: false,
    );
    expect(
      typedSpan.children!
          .whereType<TextSpan>()
          .singleWhere((child) => child.text == '@image1')
          .style
          ?.backgroundColor,
      isNotNull,
    );

    controller.form.prompt = 'Use @Image 1, then @Image 2.';
    controller.form.references = <MediaReferenceDraft>[
      ...controller.form.references,
      const MediaReferenceDraft(
        id: 'second-image-reference',
        label: 'location.png',
        kind: MediaReferenceKind.image,
        source: 'https://cdn.test/location.png',
      ),
    ];
    controller.removeReference('image-reference');
    expect(controller.form.prompt, 'Use hero.png, then @Image 1.');
  });

  testWidgets('saved video picker renders selectable thumbnail cards', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1200, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final now = DateTime.utc(2026, 8, 19);
    final thumbnail = base64Decode(
      'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII=',
    );
    SavedReference reference(String id, String name) => SavedReference(
      id: id,
      name: name,
      kind: MediaReferenceKind.video,
      asset: AssetReference(
        kind: 'remote',
        value: 'https://cdn.test/$id.mp4',
        label: '$id.mp4',
        contentType: 'video/mp4',
      ),
      thumbnailAsset: AssetReference(
        kind: 'local',
        value: '$id-thumbnail',
        label: '$id-thumbnail.jpg',
        contentType: 'image/jpeg',
      ),
      createdAt: now,
      updatedAt: now,
      tags: const <String>['skate'],
    );
    final snapshot = LocalSnapshot(
      generations: const <Generation>[],
      savedReferences: <SavedReference>[
        reference('saved-video-1', 'Revised skatepark prompt'),
        reference('saved-video-2', 'Sloth trip storyboard'),
        reference('saved-video-3', 'LES half-pipe study'),
      ],
      preferences: const AppPreferences(),
      hasApiKey: false,
      storage: const StorageStats(path: 'memory', bytes: 0, records: 3),
    );
    final controller = AppController(
      gateway: _MemoryGateway(
        snapshot,
        assets: <String, Uint8List>{
          'saved-video-1-thumbnail': thumbnail,
          'saved-video-2-thumbnail': thumbnail,
          'saved-video-3-thumbnail': thumbnail,
        },
      ),
    );
    controller.snapshot = snapshot;
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      MaterialApp(
        theme: buildClawnsoleTheme(Brightness.light),
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () => unawaited(
              showReferencePicker(
                context,
                controller,
                kind: MediaReferenceKind.video,
                maximum: 2,
              ),
            ),
            child: const Text('Open picker'),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Open picker'));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.text('Add saved videos'), findsOneWidget);
    expect(find.text('References'), findsOneWidget);
    expect(find.text('Generated'), findsOneWidget);
    expect(find.byKey(const ValueKey('reference-picker-card-grid')), findsOne);
    expect(find.byType(CheckboxListTile), findsNothing);
    expect(
      find.byKey(const ValueKey('media-thumbnail-video-frame')),
      findsNWidgets(3),
    );
    expect(find.text('0/2 selected'), findsOneWidget);

    final first = find.byKey(
      const ValueKey('reference-picker-card-saved-video-1'),
    );
    final second = find.byKey(
      const ValueKey('reference-picker-card-saved-video-2'),
    );
    final third = find.byKey(
      const ValueKey('reference-picker-card-saved-video-3'),
    );
    expect(tester.getTopLeft(first).dy, tester.getTopLeft(second).dy);
    expect(tester.getTopLeft(second).dy, tester.getTopLeft(third).dy);
    expect(tester.getTopLeft(first).dx, lessThan(tester.getTopLeft(second).dx));
    expect(tester.getTopLeft(second).dx, lessThan(tester.getTopLeft(third).dx));

    await tester.tap(first);
    await tester.pumpAndSettle();
    expect(find.text('1/2 selected'), findsOneWidget);
    expect(find.byIcon(Icons.check_rounded), findsOneWidget);

    await tester.tap(second);
    await tester.pumpAndSettle();
    expect(find.text('2/2 selected'), findsOneWidget);
    expect(find.byIcon(Icons.check_rounded), findsNWidgets(2));
    expect(tester.widget<InkWell>(third).onTap, isNull);

    await tester.tap(first);
    await tester.pumpAndSettle();
    expect(find.text('1/2 selected'), findsOneWidget);
    expect(tester.widget<InkWell>(third).onTap, isNotNull);
  });

  test('an empty reference endpoint stays selected while writing a prompt', () {
    final controller = AppController()
      ..selectedProviderId = 'atlas'
      ..selectedModelId = 'bytedance/seedance-2.5/reference-to-video';

    controller.updateForm((form) => form.prompt = 'Follow @Video1.');

    expect(
      controller.selectedModelId,
      'bytedance/seedance-2.5/reference-to-video',
    );
    controller.dispose();
  });

  test('update checks compare releases and read the shell summary', () {
    expect(compareSemanticVersions('0.4.1', '0.4.0'), greaterThan(0));
    expect(compareSemanticVersions('v0.10.0', '0.9.0'), greaterThan(0));
    expect(compareSemanticVersions('0.4.0', '0.4.0'), 0);
    expect(compareSemanticVersions('not-a-version', '0.4.0'), isNull);
    expect(isMajorVersionUpgrade('1.0.0', '0.10.1'), isTrue);
    expect(isMajorVersionUpgrade('2.0.0', '1.9.9'), isTrue);
    expect(isMajorVersionUpgrade('0.11.0', '0.10.1'), isFalse);
    expect(isMajorVersionUpgrade('invalid', '0.10.1'), isFalse);

    final installable = UpdateCheckResult.fromShell(<String, Object?>{
      'ok': true,
      'current': '0.4.0',
      'latest': '0.4.1',
      'available': true,
      'installable': true,
      'htmlUrl':
          'https://github.com/heresalexandria/clawnsole/releases/tag/v0.4.1',
    });
    expect(installable.available, isTrue);
    expect(installable.installable, isTrue);
    expect(installable.latest, '0.4.1');

    // A shell that declines an in-place install must not claim it can.
    final development = UpdateCheckResult.fromShell(<String, Object?>{
      'ok': true,
      'current': '0.4.0',
      'latest': '0.4.1',
      'available': true,
      'installable': false,
    });
    expect(development.installable, isFalse);
    expect(development.releaseUrl, clawnsoleReleasePage);
  });

  test('macOS update checks honor background and explicit modes', () async {
    final updater = _MemoryShellUpdater(
      result: const <String, Object?>{
        'ok': true,
        'current': '0.10.1',
        'latest': '0.11.0',
        'available': true,
        'installable': true,
      },
    );
    final status = UpdateStatus.forTesting(updater);

    await status.autoCheck();
    await status.autoCheck();
    await status.backgroundCheck();
    await status.refresh();

    expect(updater.forcedChecks, <bool>[true, false, true]);
    expect(status.updateAvailable, isTrue);
    expect(status.canSelfUpdate, isTrue);
    expect(status.requiresMajorUpdate, isFalse);
  });

  test('only a detected installable major release requires updating', () async {
    final majorStatus = UpdateStatus.forTesting(
      _MemoryShellUpdater(
        result: const <String, Object?>{
          'ok': true,
          'current': '0.10.1',
          'latest': '1.0.0',
          'available': true,
          'installable': true,
        },
      ),
    );
    await majorStatus.refresh(force: false);
    expect(majorStatus.requiresMajorUpdate, isTrue);

    final offlineStatus = UpdateStatus.forTesting(
      _MemoryShellUpdater(
        result: const <String, Object?>{
          'ok': false,
          'current': '0.10.1',
          'available': false,
          'installable': false,
          'error': 'The network is unavailable.',
        },
      ),
    );
    await offlineStatus.refresh(force: false);
    expect(offlineStatus.requiresMajorUpdate, isFalse);
  });

  test('mobile major releases require a store update', () async {
    final status = UpdateStatus.forMobileTesting(
      () async => const UpdateCheckResult(
        current: '0.10.1',
        latest: '1.0.0',
        available: true,
      ),
    );
    await status.refresh(force: false);

    expect(status.supportsAutomaticChecks, isTrue);
    expect(status.canSelfUpdate, isFalse);
    expect(status.requiresStoreUpdate, isTrue);
    expect(status.requiresMajorUpdate, isTrue);

    final sameMajor = UpdateStatus.forMobileTesting(
      () async => const UpdateCheckResult(
        current: '1.0.0',
        latest: '1.1.0',
        available: true,
      ),
    );
    await sameMajor.refresh(force: false);
    expect(sameMajor.requiresMajorUpdate, isFalse);

    final offline = UpdateStatus.forMobileTesting(
      () async => const UpdateCheckResult(
        current: '0.10.1',
        error: 'The network is unavailable.',
      ),
    );
    await offline.refresh(force: false);
    expect(offline.requiresMajorUpdate, isFalse);
  });

  test(
    'mobile store links target the native app with an HTTPS fallback',
    () async {
      final ios = clawnsoleStoreDestination(TargetPlatform.iOS)!;
      expect(ios.name, 'App Store');
      expect(ios.appUri.toString(), contains('id6801916362'));
      expect(ios.webUri.host, 'apps.apple.com');

      final android = clawnsoleStoreDestination(TargetPlatform.android)!;
      expect(android.name, 'Google Play');
      expect(android.appUri.queryParameters['id'], 'app.clawnsole.clawnsole');
      expect(android.webUri.host, 'play.google.com');

      final attempts = <Uri>[];
      final opened = await openClawnsoleStore(
        TargetPlatform.android,
        launch: (uri) async {
          attempts.add(uri);
          return attempts.length == 2;
        },
      );
      expect(opened, isTrue);
      expect(attempts, <Uri>[android.appUri, android.webUri]);
    },
  );

  testWidgets('macOS checks on startup and every 24 hours', (tester) async {
    final updater = _MemoryShellUpdater(
      result: const <String, Object?>{
        'ok': true,
        'current': '0.10.1',
        'latest': '0.10.1',
        'available': false,
        'installable': false,
      },
    );
    final status = UpdateStatus.forTesting(updater);
    final gateway = _MemoryGateway(
      const LocalSnapshot(
        generations: <Generation>[],
        preferences: AppPreferences(),
        hasApiKey: false,
        storage: StorageStats(path: 'memory', bytes: 0, records: 0),
      ),
    );

    await tester.pumpWidget(
      ClawnsoleApp(gateway: gateway, updateStatus: status),
    );
    await tester.pump();
    expect(updater.forcedChecks, <bool>[true]);

    await tester.pump(const Duration(hours: 24));
    await tester.pump();
    expect(updater.forcedChecks, <bool>[true, false]);

    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('mobile checks on startup and every 24 hours', (tester) async {
    var checks = 0;
    final status = UpdateStatus.forMobileTesting(() async {
      checks += 1;
      return const UpdateCheckResult(current: '0.10.1', latest: '0.10.1');
    });
    final gateway = _MemoryGateway(
      const LocalSnapshot(
        generations: <Generation>[],
        preferences: AppPreferences(),
        hasApiKey: false,
        storage: StorageStats(path: 'memory', bytes: 0, records: 0),
      ),
    );

    await tester.pumpWidget(
      ClawnsoleApp(gateway: gateway, updateStatus: status),
    );
    await tester.pump();
    expect(checks, 1);

    await tester.pump(const Duration(hours: 24));
    await tester.pump();
    expect(checks, 2);

    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('web and Windows check on startup and every 24 hours', (
    tester,
  ) async {
    var checks = 0;
    final status = UpdateStatus.forReleaseTesting(() async {
      checks += 1;
      return const UpdateCheckResult(current: '0.10.1', latest: '0.10.1');
    });
    final gateway = _MemoryGateway(
      const LocalSnapshot(
        generations: <Generation>[],
        preferences: AppPreferences(),
        hasApiKey: false,
        storage: StorageStats(path: 'memory', bytes: 0, records: 0),
      ),
    );

    await tester.pumpWidget(
      ClawnsoleApp(gateway: gateway, updateStatus: status),
    );
    await tester.pump();
    expect(checks, 1);

    await tester.pump(const Duration(hours: 24));
    await tester.pump();
    expect(checks, 2);

    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('desktop keeps the version beside the installable update chip', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1200, 800);
    addTearDown(() {
      tester.view.resetDevicePixelRatio();
      tester.view.resetPhysicalSize();
    });
    final updater = _MemoryShellUpdater(
      result: const <String, Object?>{
        'ok': true,
        'current': '0.10.1',
        'latest': '0.11.0',
        'available': true,
        'installable': true,
      },
    );
    final status = UpdateStatus.forTesting(updater);
    await status.refresh(force: false);
    final gateway = _MemoryGateway(
      const LocalSnapshot(
        generations: <Generation>[],
        preferences: AppPreferences(),
        hasApiKey: false,
        storage: StorageStats(path: 'memory', bytes: 0, records: 0),
      ),
    );

    await tester.pumpWidget(
      ClawnsoleApp(
        gateway: gateway,
        checkForUpdates: false,
        updateStatus: status,
      ),
    );
    await tester.pump();

    expect(status.updateAvailable, isTrue);
    expect(
      MediaQuery.sizeOf(tester.element(find.byType(Scaffold))).width,
      1200,
    );
    expect(find.byType(UpdateAvailableChip), findsOneWidget);
    expect(find.text('Update Available'), findsOneWidget);
    expect(find.text('v$clawnsoleVersion'), findsOneWidget);
    final label = tester.widget<Text>(find.text('Update Available'));
    expect(label.style?.color, Colors.white);

    final ink = tester.widget<Ink>(
      find.ancestor(
        of: find.byKey(const Key('update-available-chip')),
        matching: find.byType(Ink),
      ),
    );
    final before =
        (ink.decoration! as BoxDecoration).gradient! as RadialGradient;
    await tester.pump(const Duration(seconds: 1));
    final animatedInk = tester.widget<Ink>(
      find.ancestor(
        of: find.byKey(const Key('update-available-chip')),
        matching: find.byType(Ink),
      ),
    );
    final after =
        (animatedInk.decoration! as BoxDecoration).gradient! as RadialGradient;
    expect(after.center, isNot(before.center));

    await tester.tap(find.byKey(const Key('update-available-chip')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 20));
    expect(updater.startCount, 1);
    expect(find.text('Update failed'), findsOneWidget);
    await tester.tap(find.text('Close'));
    await tester.pump();
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('desktop shows non-installable updates beside the version', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1200, 800);
    addTearDown(() {
      tester.view.resetDevicePixelRatio();
      tester.view.resetPhysicalSize();
    });
    final status = UpdateStatus.forReleaseTesting(
      () async => const UpdateCheckResult(
        current: '0.10.1',
        latest: '0.11.0',
        available: true,
      ),
    );
    await status.refresh(force: false);
    final gateway = _MemoryGateway(
      const LocalSnapshot(
        generations: <Generation>[],
        preferences: AppPreferences(),
        hasApiKey: false,
        storage: StorageStats(path: 'memory', bytes: 0, records: 0),
      ),
    );

    await tester.pumpWidget(
      ClawnsoleApp(
        gateway: gateway,
        checkForUpdates: false,
        updateStatus: status,
      ),
    );
    await tester.pump();

    expect(status.updateAvailable, isTrue);
    expect(
      MediaQuery.sizeOf(tester.element(find.byType(Scaffold))).width,
      1200,
    );
    expect(find.text('v$clawnsoleVersion'), findsOneWidget);
    expect(find.byType(UpdateAvailableChip), findsOneWidget);
    final chip = tester.widget<UpdateAvailableChip>(
      find.byType(UpdateAvailableChip),
    );
    expect(chip.installable, isFalse);

    await tester.tap(find.byKey(const Key('update-available-chip')));
    await tester.pump();
    expect(find.byType(AlertDialog), findsOneWidget);

    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('compact mobile surfaces flash an update notification', (
    tester,
  ) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(390, 844);
    addTearDown(() {
      tester.view.resetDevicePixelRatio();
      tester.view.resetPhysicalSize();
    });
    var storeOpenCount = 0;
    final status = UpdateStatus.forMobileTesting(
      () async => const UpdateCheckResult(
        current: '0.10.1',
        latest: '0.11.0',
        available: true,
      ),
    );
    final gateway = _MemoryGateway(
      const LocalSnapshot(
        generations: <Generation>[],
        preferences: AppPreferences(),
        hasApiKey: false,
        storage: StorageStats(path: 'memory', bytes: 0, records: 0),
      ),
    );

    await tester.pumpWidget(
      ClawnsoleApp(
        gateway: gateway,
        updateStatus: status,
        storeUpdateOpener: (platform) async {
          expect(platform, TargetPlatform.iOS);
          storeOpenCount += 1;
          return true;
        },
      ),
    );
    await tester.pump();
    await tester.pump();

    expect(find.text('v$clawnsoleVersion'), findsOneWidget);
    expect(find.byType(UpdateAvailableChip), findsNothing);
    expect(find.text('Clawnsole 0.11.0 is available.'), findsOneWidget);

    tester.widget<SnackBarAction>(find.byType(SnackBarAction)).onPressed();
    await tester.pump();
    expect(storeOpenCount, 1);

    await tester.pumpWidget(const SizedBox.shrink());
    debugDefaultTargetPlatformOverride = null;
  });

  testWidgets('major macOS update blocks the app until installation', (
    tester,
  ) async {
    final updater = _MemoryShellUpdater(
      result: const <String, Object?>{
        'ok': true,
        'current': '0.10.1',
        'latest': '1.0.0',
        'available': true,
        'installable': true,
      },
    );
    final status = UpdateStatus.forTesting(updater);
    await status.refresh(force: false);
    final gateway = _MemoryGateway(
      const LocalSnapshot(
        generations: <Generation>[],
        preferences: AppPreferences(),
        hasApiKey: false,
        storage: StorageStats(path: 'memory', bytes: 0, records: 0),
      ),
    );

    await tester.pumpWidget(
      ClawnsoleApp(
        gateway: gateway,
        checkForUpdates: false,
        updateStatus: status,
      ),
    );
    await tester.pump();
    expect(find.text('Required update'), findsOneWidget);
    expect(find.text('Clawnsole 1.0.0 is required.'), findsOneWidget);

    await tester.tapAt(const Offset(4, 4));
    await tester.pump();
    expect(find.text('Required update'), findsOneWidget);
    final navigator = tester.state<NavigatorState>(find.byType(Navigator));
    await navigator.maybePop();
    await tester.pump();
    expect(find.text('Required update'), findsOneWidget);

    await tester.tap(find.byKey(const Key('required-major-update-button')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 20));
    expect(updater.startCount, 1);
    expect(find.text('Update failed'), findsOneWidget);
    await tester.tap(find.text('Close'));
    await tester.pump();
    expect(find.text('Required update'), findsOneWidget);

    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('major mobile update blocks the app and opens its store', (
    tester,
  ) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);
    final status = UpdateStatus.forMobileTesting(
      () async => const UpdateCheckResult(
        current: '0.10.1',
        latest: '1.0.0',
        available: true,
      ),
    );
    await status.refresh(force: false);
    var storeOpenCount = 0;
    final gateway = _MemoryGateway(
      const LocalSnapshot(
        generations: <Generation>[],
        preferences: AppPreferences(),
        hasApiKey: false,
        storage: StorageStats(path: 'memory', bytes: 0, records: 0),
      ),
    );

    await tester.pumpWidget(
      ClawnsoleApp(
        gateway: gateway,
        checkForUpdates: false,
        updateStatus: status,
        storeUpdateOpener: (platform) async {
          expect(platform, TargetPlatform.iOS);
          storeOpenCount += 1;
          return false;
        },
      ),
    );
    await tester.pump();

    expect(find.text('Required update'), findsOneWidget);
    expect(find.text('Open App Store'), findsOneWidget);
    expect(
      find.text('Install the update from App Store, then reopen Clawnsole.'),
      findsOneWidget,
    );

    await tester.tap(find.byKey(const Key('required-major-update-button')));
    await tester.pump();
    expect(storeOpenCount, 1);
    expect(find.text('Required update'), findsOneWidget);
    expect(
      find.byKey(const Key('required-major-update-store-error')),
      findsOneWidget,
    );

    await tester.tapAt(const Offset(4, 4));
    await tester.pump();
    expect(find.text('Required update'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
    debugDefaultTargetPlatformOverride = null;
  });

  testWidgets('offline update detection never blocks the app', (tester) async {
    final updater = _MemoryShellUpdater(
      result: const <String, Object?>{
        'ok': false,
        'current': '0.10.1',
        'available': false,
        'installable': false,
        'error': 'The network is unavailable.',
      },
    );
    final status = UpdateStatus.forTesting(updater);
    await status.refresh(force: false);
    final gateway = _MemoryGateway(
      const LocalSnapshot(
        generations: <Generation>[],
        preferences: AppPreferences(),
        hasApiKey: false,
        storage: StorageStats(path: 'memory', bytes: 0, records: 0),
      ),
    );

    await tester.pumpWidget(
      ClawnsoleApp(
        gateway: gateway,
        checkForUpdates: false,
        updateStatus: status,
      ),
    );
    await tester.pump();

    expect(find.text('Required update'), findsNothing);
    expect(find.text('Clawnsole'), findsWidgets);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  test('retained videos keep an AVPlayer-compatible extension', () {
    expect(retainedAssetExtension('video/mp4', 'result'), '.mp4');
    expect(retainedAssetExtension(null, 'clawnsole.mov'), '.mov');
    expect(retainedAssetExtension('image/png', 'frame'), '.png');
  });

  testWidgets('mobile Add key shortcut opens providers', (tester) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.binding.setSurfaceSize(null);
    });
    final gateway = _MemoryGateway(
      const LocalSnapshot(
        generations: <Generation>[],
        preferences: AppPreferences(),
        hasApiKey: false,
        storage: StorageStats(path: 'memory', bytes: 0, records: 0),
      ),
    );
    await tester.pumpWidget(
      ClawnsoleApp(gateway: gateway, checkForUpdates: false),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Add key'));
    await tester.pumpAndSettle();

    expect(find.text('Providers.'), findsOneWidget);
    expect(gateway.snapshot.preferences.activeSection, AppSection.providers);
  });

  testWidgets('top bar always identifies the selected provider balance', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1200, 900));
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.binding.setSurfaceSize(null);
    });
    final artcraftGateway = _ProviderMemoryGateway(
      const LocalSnapshot(
        generations: <Generation>[],
        preferences: AppPreferences(
          provider: 'artcraft',
          model: 'seedance_2p0',
        ),
        hasApiKey: false,
        connectedProviders: <String>{'artcraft'},
        storage: StorageStats(path: 'memory', bytes: 0, records: 0),
      ),
      const ProviderAccountStatus(
        provider: 'artcraft',
        currency: 'credits',
        balanceLabel: 'Open ArtCraft to view balance ↗',
      ),
    );
    await tester.pumpWidget(
      ClawnsoleApp(gateway: artcraftGateway, checkForUpdates: false),
    );
    await tester.pumpAndSettle();

    final artcraftBalance = find.byKey(
      const ValueKey<String>('selected-provider-balance'),
    );
    expect(artcraftBalance, findsOneWidget);
    expect(tester.widget<Text>(artcraftBalance).data, 'ArtCraft ↗');
    expect(find.byTooltip('Open ArtCraft to view the balance'), findsOneWidget);

    final bflGateway = _ProviderMemoryGateway(
      const LocalSnapshot(
        generations: <Generation>[],
        preferences: AppPreferences(),
        hasApiKey: true,
        storage: StorageStats(path: 'memory', bytes: 0, records: 0),
      ),
      const ProviderAccountStatus(
        provider: 'bfl',
        balance: 125,
        currency: 'credits',
      ),
    );
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
    await tester.pumpWidget(
      ClawnsoleApp(gateway: bflGateway, checkForUpdates: false),
    );
    await tester.pumpAndSettle();

    expect(find.text('125 cr'), findsOneWidget);
    expect(
      find.byTooltip('Refresh the Black Forest Labs balance'),
      findsOneWidget,
    );
  });

  testWidgets('complete provider names fit compact chrome and Create', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    for (final provider in videoProviders) {
      final gateway = _ProviderMemoryGateway(
        LocalSnapshot(
          generations: const <Generation>[],
          preferences: AppPreferences(
            provider: provider.id,
            model: provider.defaultModel.id,
          ),
          hasApiKey: false,
          connectedProviders: <String>{provider.id},
          storage: const StorageStats(path: 'memory', bytes: 0, records: 0),
        ),
        ProviderAccountStatus(
          provider: provider.id,
          currency: 'credits',
          balanceLabel: 'Open ${provider.name} to view balance ↗',
        ),
      );
      await tester.pumpWidget(
        ClawnsoleApp(gateway: gateway, checkForUpdates: false),
      );
      await tester.pumpAndSettle();

      final balance = find.byKey(
        const ValueKey<String>('selected-provider-balance'),
      );
      expect(tester.widget<Text>(balance).data, '${provider.name} ↗');
      expect(find.text(provider.name), findsAtLeastNWidgets(1));
      expect(
        tester.takeException(),
        isNull,
        reason: '${provider.name} should fit compact app chrome',
      );

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
    }
  });

  testWidgets('renders the Clawnsole Flutter shell', (tester) async {
    await tester.pumpWidget(const ClawnsoleApp(checkForUpdates: false));
    expect(find.text('Clawnsole'), findsWidgets);
    expect(find.text('Create'), findsWidgets);
    final app = tester.widget<MaterialApp>(find.byType(MaterialApp));
    expect(app.themeMode, ThemeMode.system);
    expect(app.darkTheme, isNotNull);

    await tester.tap(find.byTooltip('Appearance: system'));
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.text('System'), findsOneWidget);
    expect(find.text('Light'), findsOneWidget);
    expect(find.text('Dark'), findsOneWidget);
  });

  testWidgets('iOS touch outside a text field dismisses the keyboard', (
    tester,
  ) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.binding.setSurfaceSize(null);
    });
    final gateway = _MemoryGateway(
      const LocalSnapshot(
        generations: <Generation>[],
        preferences: AppPreferences(),
        hasApiKey: false,
        storage: StorageStats(path: 'memory', bytes: 0, records: 0),
      ),
    );

    await tester.pumpWidget(
      ClawnsoleApp(gateway: gateway, checkForUpdates: false),
    );
    await tester.pumpAndSettle();

    final prompt = find.byWidgetPredicate((widget) {
      final key = widget.key;
      return key is ValueKey<String> &&
          key.value.startsWith('generation-prompt-');
    });
    final editable = find.descendant(
      of: prompt,
      matching: find.byType(EditableText),
    );

    await tester.tap(prompt, kind: PointerDeviceKind.touch);
    await tester.pump();
    expect(tester.widget<EditableText>(editable).focusNode.hasFocus, isTrue);

    final promptTopLeft = tester.getTopLeft(prompt);
    await tester.tapAt(
      Offset(promptTopLeft.dx + 10, promptTopLeft.dy - 5),
      kind: PointerDeviceKind.touch,
    );
    await tester.pump();
    expect(tester.widget<EditableText>(editable).focusNode.hasFocus, isFalse);
    debugDefaultTargetPlatformOverride = null;
  });

  testWidgets('desktop brand icon has no decorative border or background', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1200, 800);
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox.shrink());
      tester.view.resetDevicePixelRatio();
      tester.view.resetPhysicalSize();
    });
    final gateway = _MemoryGateway(
      const LocalSnapshot(
        generations: <Generation>[],
        preferences: AppPreferences(),
        hasApiKey: false,
        storage: StorageStats(path: 'memory', bytes: 0, records: 0),
      ),
    );

    await tester.pumpWidget(
      ClawnsoleApp(gateway: gateway, checkForUpdates: false),
    );
    await tester.pumpAndSettle();

    final brandIcon = find.byKey(
      const ValueKey<String>('side-rail-brand-icon'),
    );
    expect(brandIcon, findsOneWidget);
    expect(
      find.descendant(of: brandIcon, matching: find.byType(DecoratedBox)),
      findsNothing,
    );
  });

  testWidgets('opens the saved References tab from desktop navigation', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1440, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final gateway = _MemoryGateway(
      const LocalSnapshot(
        generations: <Generation>[],
        preferences: AppPreferences(),
        hasApiKey: false,
        storage: StorageStats(path: 'memory', bytes: 0, records: 0),
      ),
    );
    await tester.pumpWidget(
      ClawnsoleApp(gateway: gateway, checkForUpdates: false),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('References'));
    await tester.pumpAndSettle();

    expect(find.text('Your creative ingredients.'), findsOneWidget);
    final search = find.byKey(const ValueKey('reference-library-search'));
    expect(search, findsOneWidget);
    expect(tester.getSize(search).width, greaterThanOrEqualTo(300));
    expect(gateway.snapshot.preferences.activeSection, AppSection.references);
  });

  test(
    'keeps the latest tab selected while preference writes finish',
    () async {
      final gateway = _DelayedPreferencesGateway(
        const LocalSnapshot(
          generations: <Generation>[],
          preferences: AppPreferences(),
          hasApiKey: false,
          storage: StorageStats(path: 'memory', bytes: 0, records: 0),
        ),
      );
      final controller = AppController(gateway: gateway);
      addTearDown(controller.dispose);
      await controller.initialize();

      final libraryNavigation = controller.navigate(AppSection.library);
      await Future<void>.delayed(Duration.zero);
      final referencesNavigation = controller.navigate(AppSection.references);
      await Future<void>.delayed(Duration.zero);

      expect(controller.section, AppSection.references);
      expect(gateway.pendingPreferences, <AppSection>[AppSection.library]);

      await gateway.completeNextPreference();
      await libraryNavigation;
      await Future<void>.delayed(Duration.zero);

      expect(controller.section, AppSection.references);
      expect(gateway.pendingPreferences, <AppSection>[AppSection.references]);

      await gateway.completeNextPreference();
      await referencesNavigation;

      expect(controller.section, AppSection.references);
      expect(gateway.snapshot.preferences.activeSection, AppSection.references);
    },
  );

  test('stale state responses do not restore an earlier tab', () async {
    final gateway = _DelayedHistoryGateway(
      const LocalSnapshot(
        generations: <Generation>[],
        preferences: AppPreferences(),
        hasApiKey: false,
        storage: StorageStats(path: 'memory', bytes: 0, records: 0),
      ),
    );
    final controller = AppController(gateway: gateway);
    addTearDown(controller.dispose);
    await controller.initialize();

    final clearing = controller.clearHistory();
    await controller.navigate(AppSection.library);
    gateway.completeHistoryClear();
    await clearing;

    expect(controller.section, AppSection.library);
    expect(controller.snapshot!.preferences.activeSection, AppSection.library);
  });

  testWidgets('reference search and sort stack cleanly on mobile', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final gateway = _MemoryGateway(
      const LocalSnapshot(
        generations: <Generation>[],
        preferences: AppPreferences(activeSection: AppSection.references),
        hasApiKey: false,
        storage: StorageStats(path: 'memory', bytes: 0, records: 0),
      ),
    );
    await tester.pumpWidget(
      ClawnsoleApp(gateway: gateway, checkForUpdates: false),
    );
    await tester.pumpAndSettle();

    final search = find.byKey(const ValueKey('reference-library-search'));
    final sort = find.byKey(const ValueKey('reference-library-sort'));
    expect(tester.getSize(search).width, greaterThanOrEqualTo(300));
    expect(
      tester.getTopLeft(sort).dy,
      greaterThan(tester.getBottomLeft(search).dy),
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('primary screens fit desktop, tablet, and mobile viewports', (
    tester,
  ) async {
    const sizes = <Size>[Size(1440, 1000), Size(1024, 768), Size(390, 844)];
    addTearDown(() => tester.binding.setSurfaceSize(null));

    for (final size in sizes) {
      await tester.binding.setSurfaceSize(size);
      for (final section in AppSection.values) {
        final gateway = _MemoryGateway(
          LocalSnapshot(
            generations: const <Generation>[],
            preferences: AppPreferences(activeSection: section),
            hasApiKey: false,
            storage: const StorageStats(path: 'memory', bytes: 0, records: 0),
          ),
        );
        await tester.pumpWidget(
          ClawnsoleApp(gateway: gateway, checkForUpdates: false),
        );
        await tester.pumpAndSettle();

        expect(
          tester.takeException(),
          isNull,
          reason: '${section.name} should fit ${size.width}×${size.height}',
        );
      }
    }
  });

  testWidgets('dense library metadata keeps the complete provider name', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(320, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final gateway = _MemoryGateway(
      LocalSnapshot(
        generations: <Generation>[
          _viewModeGeneration(
            0,
            provider: atlasProvider.id,
            model: atlasProvider.defaultModel.id,
          ),
        ],
        preferences: const AppPreferences(
          activeSection: AppSection.library,
          libraryViewMode: GenerationViewMode.compact,
        ),
        hasApiKey: false,
        storage: const StorageStats(path: 'memory', bytes: 0, records: 1),
      ),
    );

    await tester.pumpWidget(
      ClawnsoleApp(gateway: gateway, checkForUpdates: false),
    );
    await tester.pumpAndSettle();

    expect(find.text('Atlas Cloud'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('library dense views hide status badges', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1440, 1000));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final gateway = _MemoryGateway(
      LocalSnapshot(
        generations: List<Generation>.generate(4, _viewModeGeneration),
        preferences: const AppPreferences(activeSection: AppSection.library),
        hasApiKey: false,
        storage: const StorageStats(path: 'memory', bytes: 0, records: 4),
      ),
    );
    await tester.pumpWidget(
      ClawnsoleApp(gateway: gateway, checkForUpdates: false),
    );
    await tester.pumpAndSettle();

    expect(find.byTooltip('Compact'), findsOneWidget);
    expect(find.byTooltip('Mini'), findsOneWidget);
    expect(find.byTooltip('Full'), findsOneWidget);
    expect(find.byType(StatusBadge), findsNWidgets(4));

    await tester.tap(find.byTooltip('Mini'));
    await tester.pumpAndSettle();

    expect(find.byType(StatusBadge), findsNothing);
    expect(
      find.byKey(const ValueKey('generation-mini-view-generation-0')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('generation-mini-view-generation-1')),
      findsOneWidget,
    );
    final firstMini = tester.getTopLeft(
      find.byKey(const ValueKey('generation-mini-view-generation-0')),
    );
    final secondMini = tester.getTopLeft(
      find.byKey(const ValueKey('generation-mini-view-generation-1')),
    );
    expect((firstMini.dy - secondMini.dy).abs(), lessThan(1));
    expect(secondMini.dx, greaterThan(firstMini.dx));
    expect(
      gateway.snapshot.preferences.libraryViewMode,
      GenerationViewMode.mini,
    );

    await tester.tap(find.byTooltip('Compact'));
    await tester.pumpAndSettle();

    expect(find.byType(StatusBadge), findsNothing);
    final firstCompact = find.byKey(
      const ValueKey('generation-compact-view-generation-0'),
    );
    final secondCompact = find.byKey(
      const ValueKey('generation-compact-view-generation-1'),
    );
    expect(firstCompact, findsOneWidget);
    expect(secondCompact, findsOneWidget);
    expect(
      tester.getTopLeft(secondCompact).dy,
      greaterThan(tester.getTopLeft(firstCompact).dy),
    );
    expect(
      tester.getSize(
        find.byKey(
          const ValueKey('generation-compact-thumbnail-view-generation-0'),
        ),
      ),
      const Size(92, 68),
    );
    expect(
      gateway.snapshot.preferences.libraryViewMode,
      GenerationViewMode.compact,
    );

    await tester.tap(find.byTooltip('Full'));
    await tester.pumpAndSettle();

    expect(find.byType(StatusBadge), findsNWidgets(4));
    expect(
      gateway.snapshot.preferences.libraryViewMode,
      GenerationViewMode.full,
    );
  });

  testWidgets('library Filters popover narrows and resets the view', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1440, 1000));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final gateway = _MemoryGateway(
      LocalSnapshot(
        generations: List<Generation>.generate(3, _viewModeGeneration),
        preferences: const AppPreferences(activeSection: AppSection.library),
        hasApiKey: false,
        storage: const StorageStats(path: 'memory', bytes: 0, records: 3),
      ),
    );
    await tester.pumpWidget(
      ClawnsoleApp(gateway: gateway, checkForUpdates: false),
    );
    await tester.pumpAndSettle();

    // Status controls live inside the Filters popover rather than consuming
    // permanent toolbar space.
    expect(find.textContaining('Ready'), findsNothing);

    await tester.tap(find.byKey(const ValueKey('library-filter-button')));
    await tester.pumpAndSettle();
    expect(find.text('STATUS'), findsOneWidget);
    expect(find.textContaining('Ready'), findsOneWidget);
    expect(find.text('FAVORITES'), findsOneWidget);

    await tester.tap(find.text('Starred'));
    await tester.pumpAndSettle();
    expect(find.text('Nothing in this view.'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('library-filter-reset')));
    await tester.pumpAndSettle();
    expect(find.text('Nothing in this view.'), findsNothing);
  });

  test('startup quietly resumes a configured Drive connection', () async {
    final driveFilm = _viewModeGeneration(
      0,
    ).copyWith(storage: LibraryStorage.drive);
    final gateway = _ResumableDriveGateway(
      const LocalSnapshot(
        generations: <Generation>[],
        preferences: AppPreferences(),
        hasApiKey: false,
        storage: StorageStats(path: 'memory', bytes: 0, records: 0),
      ),
      configured: true,
      resumed: LocalSnapshot(
        generations: <Generation>[driveFilm],
        preferences: const AppPreferences(),
        hasApiKey: false,
        storage: const StorageStats(path: 'memory', bytes: 0, records: 1),
      ),
    );
    final controller = AppController(gateway: gateway);
    addTearDown(controller.dispose);

    await controller.initialize();
    await Future<void>.delayed(Duration.zero);

    expect(gateway.resumeCalls, 1);
    expect(controller.generations.single.storage, LibraryStorage.drive);
  });

  test('startup does not resume Drive for never-connected libraries', () async {
    final gateway = _ResumableDriveGateway(
      const LocalSnapshot(
        generations: <Generation>[],
        preferences: AppPreferences(),
        hasApiKey: false,
        storage: StorageStats(path: 'memory', bytes: 0, records: 0),
      ),
      configured: false,
      resumed: null,
    );
    final controller = AppController(gateway: gateway);
    addTearDown(controller.dispose);

    await controller.initialize();
    await Future<void>.delayed(Duration.zero);

    expect(gateway.resumeCalls, 0);
  });

  test(
    'tab preference writes silently renew an expired Drive session',
    () async {
      final gateway = _ExpiringPreferenceDriveGateway(
        const LocalSnapshot(
          generations: <Generation>[],
          preferences: AppPreferences(),
          hasApiKey: false,
          storage: StorageStats(path: 'memory', bytes: 0, records: 0),
        ),
      );
      final controller = AppController(gateway: gateway);
      addTearDown(controller.dispose);

      await controller.initialize();
      await controller.navigate(AppSection.library);

      expect(gateway.preferenceCalls, 2);
      expect(gateway.forcedResumeCalls, 1);
      expect(controller.section, AppSection.library);
      expect(controller.notice, isNull);
    },
  );

  testWidgets('library explains signed-out Drive work and reconnects', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1440, 1000));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final localFilm = _viewModeGeneration(0);
    final driveFilm = Generation.fromJson(<String, Object?>{
      ..._viewModeGeneration(1).toJson(),
      'localId': 'drive-film',
      'prompt': 'A film that lives in Drive.',
      'storage': LibraryStorage.drive.name,
    });
    final gateway = _ResumableDriveGateway(
      LocalSnapshot(
        generations: <Generation>[localFilm],
        preferences: const AppPreferences(activeSection: AppSection.library),
        hasApiKey: false,
        storage: const StorageStats(path: 'memory', bytes: 0, records: 1),
      ),
      configured: true,
      resumed: null,
      refreshed: LocalSnapshot(
        generations: <Generation>[localFilm, driveFilm],
        preferences: const AppPreferences(activeSection: AppSection.library),
        hasApiKey: false,
        storage: const StorageStats(path: 'memory', bytes: 0, records: 2),
      ),
    );
    await tester.pumpWidget(
      ClawnsoleApp(gateway: gateway, checkForUpdates: false),
    );
    await tester.pumpAndSettle();

    // The sidebar carries the storage rows now.
    expect(find.text('Storage'), findsOneWidget);
    expect(find.text('All storage'), findsOneWidget);
    expect(find.text('On this device'), findsOneWidget);
    expect(find.text('Google Drive'), findsOneWidget);
    // Signed-out Drive work is explained, never silently hidden.
    expect(find.textContaining('Google Drive is signed out'), findsOneWidget);
    expect(find.text('A film that lives in Drive.'), findsNothing);

    await tester.tap(find.byKey(const ValueKey('drive-reconnect-films')));
    await tester.pumpAndSettle();

    expect(gateway.refreshCalls, 1);
    expect(find.textContaining('Google Drive is signed out'), findsNothing);
    expect(find.text('A film that lives in Drive.'), findsOneWidget);

    await tester.tap(find.text('On this device'));
    await tester.pumpAndSettle();
    expect(find.text('A film that lives in Drive.'), findsNothing);

    await tester.tap(find.text('All storage'));
    await tester.pumpAndSettle();
    expect(find.text('A film that lives in Drive.'), findsOneWidget);
  });

  testWidgets('primary media views refresh their connected Drive library', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1440, 1000));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    const views = <(AppSection, String)>[
      (AppSection.library, 'library'),
      (AppSection.references, 'references'),
      (AppSection.create, 'recent-work'),
    ];

    for (final view in views) {
      final snapshot = LocalSnapshot(
        generations: const <Generation>[],
        preferences: AppPreferences(activeSection: view.$1),
        hasApiKey: false,
        storage: const StorageStats(path: 'memory', bytes: 0, records: 0),
      );
      final gateway = _ResumableDriveGateway(
        snapshot,
        configured: true,
        resumed: snapshot,
        refreshed: snapshot,
      );
      await tester.pumpWidget(
        ClawnsoleApp(gateway: gateway, checkForUpdates: false),
      );
      await tester.pumpAndSettle();

      final refresh = find.byKey(ValueKey('${view.$2}-drive-refresh'));
      expect(refresh, findsOneWidget);
      await tester.ensureVisible(refresh);
      await tester.tap(refresh);
      await tester.pumpAndSettle();
      expect(gateway.refreshCalls, 1);

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
    }
  });

  testWidgets('recent work shows at most the newest 100 items', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1440, 1000));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final gateway = _MemoryGateway(
      LocalSnapshot(
        generations: List<Generation>.generate(101, _viewModeGeneration),
        preferences: const AppPreferences(
          recentWorkViewMode: GenerationViewMode.compact,
        ),
        hasApiKey: false,
        storage: const StorageStats(path: 'memory', bytes: 0, records: 101),
      ),
    );
    await tester.pumpWidget(
      ClawnsoleApp(gateway: gateway, checkForUpdates: false),
    );
    await tester.pumpAndSettle();

    expect(find.byType(CompactGenerationRow), findsNWidgets(100));
    expect(
      find.byKey(const ValueKey('generation-compact-view-generation-99')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('generation-compact-view-generation-100')),
      findsNothing,
    );
  });

  testWidgets('recent work dense views hide status badges', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1440, 1000));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final gateway = _MemoryGateway(
      LocalSnapshot(
        generations: List<Generation>.generate(4, _viewModeGeneration),
        preferences: const AppPreferences(),
        hasApiKey: false,
        storage: const StorageStats(path: 'memory', bytes: 0, records: 4),
      ),
    );
    await tester.pumpWidget(
      ClawnsoleApp(gateway: gateway, checkForUpdates: false),
    );
    await tester.pumpAndSettle();

    expect(find.byType(StatusBadge), findsNWidgets(4));

    // Recent work sits below the full-width composer, so bring its view
    // toggle on screen before tapping.
    await tester.ensureVisible(find.byTooltip('Mini'));
    await tester.tap(find.byTooltip('Mini'));
    await tester.pumpAndSettle();

    expect(find.byType(StatusBadge), findsNothing);
    final first = find.byKey(
      const ValueKey('generation-mini-view-generation-0'),
    );
    final second = find.byKey(
      const ValueKey('generation-mini-view-generation-1'),
    );
    expect(first, findsOneWidget);
    expect(second, findsOneWidget);
    expect(
      (tester.getTopLeft(first).dy - tester.getTopLeft(second).dy).abs(),
      lessThan(1),
    );
    expect(
      tester.getTopLeft(second).dx,
      greaterThan(tester.getTopLeft(first).dx),
    );
    expect(
      gateway.snapshot.preferences.recentWorkViewMode,
      GenerationViewMode.mini,
    );

    await tester.ensureVisible(find.byTooltip('Compact'));
    await tester.tap(find.byTooltip('Compact'));
    await tester.pumpAndSettle();

    expect(find.byType(StatusBadge), findsNothing);
    expect(
      find.byKey(const ValueKey('generation-compact-view-generation-0')),
      findsOneWidget,
    );
    expect(
      gateway.snapshot.preferences.recentWorkViewMode,
      GenerationViewMode.compact,
    );

    await tester.ensureVisible(find.byTooltip('Full'));
    await tester.tap(find.byTooltip('Full'));
    await tester.pumpAndSettle();

    expect(find.byType(StatusBadge), findsNWidgets(4));
    expect(
      gateway.snapshot.preferences.recentWorkViewMode,
      GenerationViewMode.full,
    );
  });

  testWidgets('settings credits Alexandria with a linked portrait', (
    tester,
  ) async {
    final controller = AppController();
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      MaterialApp(
        theme: buildClawnsoleTheme(Brightness.light),
        home: Scaffold(body: SettingsScreen(controller: controller)),
      ),
    );

    expect(find.text('Made by Alexandria'), findsOneWidget);
    expect(find.text('Visit heresalexandria.com'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('alexandria-profile-link')),
      findsOneWidget,
    );
    final portrait = tester.widget<CircleAvatar>(
      find.byType(CircleAvatar).last,
    );
    expect(
      portrait.backgroundImage,
      const AssetImage('assets/profile-alexandria.jpg'),
    );
    expect(find.text('ArtCraft documentation'), findsOneWidget);
    expect(find.text('Atlas Cloud documentation'), findsOneWidget);
    expect(find.text('FLUX 3 documentation'), findsOneWidget);
    expect(find.text('LTX Studio documentation'), findsOneWidget);
    for (final provider in videoProviders) {
      expect(
        find.byKey(ValueKey('provider-documentation-${provider.id}')),
        findsOneWidget,
      );
    }
  });

  testWidgets('settings persists the selected generation placeholder', (
    tester,
  ) async {
    final gateway = _MemoryGateway(
      const LocalSnapshot(
        generations: <Generation>[],
        preferences: AppPreferences(),
        hasApiKey: false,
        storage: StorageStats(path: 'memory', bytes: 0, records: 0),
      ),
    );
    final controller = AppController(gateway: gateway);
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      MaterialApp(
        theme: buildClawnsoleTheme(Brightness.light),
        home: Scaffold(body: SettingsScreen(controller: controller)),
      ),
    );

    expect(find.text('Generation Placeholder'), findsOneWidget);
    expect(find.text('Static'), findsOneWidget);
    await tester.tap(
      find.byKey(const ValueKey('generation-placeholder-style')),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Cyclone').last);
    await tester.pumpAndSettle();

    expect(
      controller.generationPlaceholderStyle,
      GenerationPlaceholderStyle.cyclone,
    );
    expect(
      gateway.snapshot.preferences.generationPlaceholderStyle,
      GenerationPlaceholderStyle.cyclone,
    );
  });

  test('form infers every FLUX 3 generation mode from its inputs', () {
    expect(VideoMode.values, hasLength(5));
    expect(modelById('bfl', 'flux-3-video').modes, <VideoMode>[
      VideoMode.t2v,
      VideoMode.i2v,
      VideoMode.v2v,
      VideoMode.draftEnhance,
    ]);
    final controller = AppController();
    expect(controller.form.mode, VideoMode.t2v);
    controller.addUrlFrame(KeyframeRole.start);
    expect(controller.form.mode, VideoMode.i2v);
    controller.updateForm(
      (form) => form.videoUrl = 'https://cdn.bfl.ai/start.mp4',
    );
    expect(controller.form.mode, VideoMode.v2v);
    controller.updateForm(
      (form) => form.draftUrl = 'https://cdn.bfl.ai/cache.zip',
    );
    expect(controller.form.mode, VideoMode.draftEnhance);
    controller.updateForm(
      (form) => form
        ..draftUrl = ''
        ..videoUrl = ''
        ..keyframes = <KeyframeDraft>[],
    );
    expect(controller.form.mode, VideoMode.t2v);
    controller.dispose();
  });

  test('video upscale builds the standalone BFL request contract', () async {
    final gateway = _MemoryGateway(
      const LocalSnapshot(
        generations: <Generation>[],
        preferences: AppPreferences(),
        hasApiKey: true,
        connectedProviders: <String>{'bfl'},
        storage: StorageStats(path: 'memory', bytes: 0, records: 0),
      ),
    );
    final controller = AppController(gateway: gateway);
    await controller.initialize();
    await controller.selectModel('flux-tools-video-upscale-v1');
    controller.rememberVideoSourceMetadata(
      const VideoSourceMetadata(width: 1920, height: 1080, durationSeconds: 10),
    );
    expect(controller.form.mode, VideoMode.upscale);
    expect(controller.validate(), contains('video you want to upscale'));

    controller.updateVideoSourceUrl('https://cdn.bfl.ai/source.mp4');
    controller.updateForm(
      (form) => form
        ..prompt = ''
        ..upscaleFactor = 2.5
        ..upscaleCreativity = 0
        ..safetyTolerance = 3,
    );

    expect(controller.validate(), isNull);
    expect(controller.buildInputForTesting(), <String, Object?>{
      'input_video': 'https://cdn.bfl.ai/source.mp4',
      'upscale_factor': 2.5,
      'creativity': 0,
      'safety_tolerance': 3,
    });
    expect(controller.currentConfig.sourceLabel, contains('source.mp4'));
    expect(controller.currentConfig.upscaleFactor, 2.5);

    controller.updateVideoSourceUrl('http://cdn.bfl.ai/source.mp4');
    expect(controller.validate(), isNull);
    controller.updateForm(
      (form) => form
        ..videoUrl = ''
        ..videoAsset = PickedAsset(
          name: 'source.mov',
          bytes: Uint8List.fromList(<int>[1, 2, 3]),
          mimeType: 'video/quicktime',
        ),
    );
    expect(controller.validate(), contains('local uploads as MP4'));
    controller.updateForm(
      (form) => form
        ..videoAsset = null
        ..videoUrl = 'https://cdn.bfl.ai/source.mp4',
    );

    await controller.selectProvider('ltx');
    await controller.reuse(
      Generation(
        localId: 'saved-upscale',
        provider: 'bfl',
        model: 'flux-tools-video-upscale-v1',
        status: 'Ready',
        prompt: 'Bring out the feathers.',
        mode: VideoMode.upscale,
        config: const GenerationConfig(
          aspectRatio: 'auto',
          duration: 'source',
          resolution: 'source',
          generateAudio: false,
          safetyTolerance: 1,
          draft: false,
          upscaleFactor: 3,
          upscaleCreativity: 1,
          source: AssetReference(
            kind: 'remote',
            value: 'https://cdn.bfl.ai/bird.mp4',
            label: 'bird.mp4',
          ),
        ),
        createdAt: DateTime.utc(2026, 8, 20),
        updatedAt: DateTime.utc(2026, 8, 20),
      ),
    );
    expect(controller.selectedProviderId, 'bfl');
    expect(controller.selectedModelId, 'flux-tools-video-upscale-v1');
    expect(controller.buildInputForTesting(), <String, Object?>{
      'input_video': 'https://cdn.bfl.ai/bird.mp4',
      'upscale_factor': 3.0,
      'creativity': 1,
      'prompt': 'Bring out the feathers.',
      'safety_tolerance': 1,
    });
    controller.dispose();
  });

  testWidgets('video upscale exposes finishing controls on Create', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1400, 1000));
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.binding.setSurfaceSize(null);
    });
    final controller = AppController(
      gateway: _MemoryGateway(
        const LocalSnapshot(
          generations: <Generation>[],
          preferences: AppPreferences(),
          hasApiKey: true,
          connectedProviders: <String>{'bfl'},
          storage: StorageStats(path: 'memory', bytes: 0, records: 0),
        ),
      ),
    );
    await controller.initialize();
    await controller.selectModel('flux-tools-video-upscale-v1');
    controller.rememberVideoSourceMetadata(
      const VideoSourceMetadata(width: 1920, height: 1080, durationSeconds: 10),
    );
    expect(controller.currentEstimate.minimumUsd, 7.91);

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

    expect(find.text('Make it sharper.'), findsOneWidget);
    expect(find.text('Video to upscale'), findsOneWidget);
    expect(find.byKey(const ValueKey('upscale-factor-slider')), findsOneWidget);
    expect(find.text('PRECISE'), findsOneWidget);
    expect(find.text('CREATIVE'), findsOneWidget);
    expect(find.text('ESTIMATED CHARGE'), findsOneWidget);
    expect(find.textContaining(r'$7.91'), findsOneWidget);
    expect(find.textContaining(r'$0.10 / megapixel-second'), findsOneWidget);
    expect(find.text('791 credits'), findsOneWidget);
    expect(find.textContaining('1920×1080 × 2.0×'), findsOneWidget);
    expect(find.text('Upscale video'), findsOneWidget);
    controller.dispose();
  });

  test('saves a delivered generation directly to Photos', () async {
    final gateway = _MemoryGateway(
      const LocalSnapshot(
        generations: <Generation>[],
        preferences: AppPreferences(),
        hasApiKey: false,
        storage: StorageStats(path: 'memory', bytes: 0, records: 0),
      ),
      supportsPhotoLibrarySave: true,
    );
    final controller = AppController(gateway: gateway);
    final now = DateTime.utc(2026, 8, 15);
    final item = Generation(
      localId: 'photo-save',
      status: 'Ready',
      prompt: 'A sloth checks the camera roll.',
      mode: VideoMode.t2v,
      config: const GenerationConfig(
        aspectRatio: '16:9',
        duration: 8,
        resolution: 'hd',
        generateAudio: true,
        safetyTolerance: 2,
        draft: false,
      ),
      createdAt: now,
      updatedAt: now,
      resultUrl: 'https://example.com/video.mp4',
    );

    await controller.saveVideo(item, destination: VideoSaveDestination.photos);

    expect(gateway.photoLibraryBytes, <int>[1, 2, 3]);
    expect(gateway.photoLibraryFileName, 'clawnsole-2026-08-15-photo-.mp4');
    expect(controller.notice, 'Video saved to Photos.');
    controller.dispose();
  });

  testWidgets('an identical repeated notice surfaces both times', (
    tester,
  ) async {
    final gateway = _MemoryGateway(
      const LocalSnapshot(
        generations: <Generation>[],
        preferences: AppPreferences(),
        hasApiKey: false,
        storage: StorageStats(path: 'memory', bytes: 0, records: 0),
      ),
    );
    await tester.pumpWidget(
      ClawnsoleApp(gateway: gateway, checkForUpdates: false),
    );
    await tester.pumpAndSettle();
    final controller =
        // ignore: avoid_dynamic_calls
        (tester.state(find.byType(ClawnsoleApp)) as dynamic).controller
            as AppController;
    const message = 'The saved video file is missing.';

    controller.showNotice(message);
    await tester.pump();
    await tester.pump();
    expect(find.text(message), findsOneWidget);

    // The notice auto-clears after four seconds. The snack bar's own display
    // timer only starts once its entrance animation completes, so finish the
    // entrance, let both timers fire, then settle the exit animation.
    await tester.pump(const Duration(seconds: 1));
    await tester.pump(const Duration(seconds: 5));
    await tester.pumpAndSettle();
    expect(find.text(message), findsNothing);

    // A second identical failure must surface again, not be deduplicated.
    controller.showNotice(message);
    await tester.pump();
    await tester.pump();
    expect(find.text(message), findsOneWidget);
    expect(controller.noticeSequence, 2);

    await tester.pump(const Duration(seconds: 1));
    await tester.pump(const Duration(seconds: 5));
    await tester.pumpAndSettle();
    await tester.pumpWidget(const SizedBox.shrink());
  });
}

Generation _viewModeGeneration(
  int index, {
  String provider = 'bfl',
  String model = 'flux-3-video',
}) {
  final createdAt = DateTime.utc(
    2026,
    8,
    20,
    12,
  ).subtract(Duration(minutes: index));
  return Generation(
    localId: 'view-generation-$index',
    provider: provider,
    model: model,
    status: 'Ready',
    prompt: 'A compact generation preview number $index.',
    mode: VideoMode.t2v,
    config: const GenerationConfig(
      aspectRatio: '16:9',
      duration: 8,
      resolution: 'hd',
      generateAudio: true,
      safetyTolerance: 2,
      draft: false,
    ),
    createdAt: createdAt,
    updatedAt: createdAt,
  );
}

Generation _deliveredGeneration(
  String id, {
  String aspect = '16:9',
  String thumbnail = 'aspect-thumb.png',
  String? timeline,
}) {
  final createdAt = DateTime.utc(2026, 8, 21, 12);
  return Generation(
    localId: 'delivered-$id',
    status: 'Ready',
    prompt: 'A delivered film with a cached preview.',
    mode: VideoMode.t2v,
    config: GenerationConfig(
      aspectRatio: aspect,
      duration: 8,
      resolution: 'hd',
      generateAudio: true,
      safetyTolerance: 2,
      draft: false,
    ),
    createdAt: createdAt,
    updatedAt: createdAt,
    resultAsset: AssetReference(
      kind: 'local',
      value: 'film-$id.mp4',
      label: 'film-$id.mp4',
      contentType: 'video/mp4',
    ),
    thumbnailAsset: AssetReference(
      kind: 'local',
      value: thumbnail,
      label: thumbnail,
      contentType: 'image/png',
    ),
    timelineThumbnailAsset: timeline == null
        ? null
        : AssetReference(
            kind: 'local',
            value: timeline,
            label: timeline,
            contentType: 'image/png',
          ),
  );
}

class _ResumableDriveGateway extends _MemoryGateway
    implements GoogleDriveGateway {
  _ResumableDriveGateway(
    super.snapshot, {
    required this.configured,
    required this.resumed,
    this.refreshed,
  });

  final bool configured;
  final LocalSnapshot? resumed;
  final LocalSnapshot? refreshed;
  int resumeCalls = 0;
  int refreshCalls = 0;
  bool _connected = false;

  @override
  bool get supportsLocalLibrary => true;

  @override
  GoogleDriveConnection get googleDriveConnection => GoogleDriveConnection(
    state: _connected
        ? GoogleDriveConnectionState.connected
        : GoogleDriveConnectionState.disconnected,
    folderName: configured ? 'Clawnsole' : '',
    folderId: configured ? 'folder-1' : '',
  );

  @override
  Future<LocalSnapshot?> resumeGoogleDrive({bool force = false}) async {
    resumeCalls += 1;
    final value = resumed;
    if (value == null) return null;
    _connected = true;
    snapshot = value;
    return value;
  }

  @override
  Future<LocalSnapshot> refreshGoogleDrive() async {
    refreshCalls += 1;
    _connected = true;
    snapshot = refreshed ?? snapshot;
    return snapshot;
  }

  @override
  Future<LocalSnapshot> connectGoogleDrive(String folderName) =>
      refreshGoogleDrive();

  @override
  Future<LocalSnapshot> disconnectGoogleDrive() async {
    _connected = false;
    return snapshot;
  }

  @override
  Future<GoogleDriveCopyResult> copyLocalLibraryToGoogleDrive({
    Set<String> generationIds = const <String>{},
    Set<String> referenceIds = const <String>{},
  }) async =>
      GoogleDriveCopyResult(snapshot: snapshot, generations: 0, references: 0);

  @override
  Future<GoogleDriveCopyResult> moveLocalLibraryToGoogleDrive() async =>
      GoogleDriveCopyResult(snapshot: snapshot, generations: 0, references: 0);
}

class _ExpiringPreferenceDriveGateway extends _MemoryGateway
    implements GoogleDriveGateway {
  _ExpiringPreferenceDriveGateway(super.snapshot);

  int preferenceCalls = 0;
  int forcedResumeCalls = 0;

  @override
  bool get supportsLocalLibrary => true;

  @override
  GoogleDriveConnection get googleDriveConnection =>
      const GoogleDriveConnection(
        state: GoogleDriveConnectionState.connected,
        folderName: 'Clawnsole',
        folderId: 'folder-1',
      );

  @override
  Future<LocalSnapshot> setPreferences(AppPreferences preferences) async {
    preferenceCalls += 1;
    if (preferenceCalls == 1) {
      throw StateError(
        'Connect Google Drive before changing Drive generations, folders, or references.',
      );
    }
    return super.setPreferences(preferences);
  }

  @override
  Future<LocalSnapshot?> resumeGoogleDrive({bool force = false}) async {
    if (!force) return null;
    forcedResumeCalls += 1;
    return snapshot;
  }

  @override
  Future<LocalSnapshot> connectGoogleDrive(String folderName) async => snapshot;

  @override
  Future<LocalSnapshot> disconnectGoogleDrive() async => snapshot;

  @override
  Future<LocalSnapshot> refreshGoogleDrive() async => snapshot;

  @override
  Future<GoogleDriveCopyResult> copyLocalLibraryToGoogleDrive({
    Set<String> generationIds = const <String>{},
    Set<String> referenceIds = const <String>{},
  }) async =>
      GoogleDriveCopyResult(snapshot: snapshot, generations: 0, references: 0);

  @override
  Future<GoogleDriveCopyResult> moveLocalLibraryToGoogleDrive() async =>
      GoogleDriveCopyResult(snapshot: snapshot, generations: 0, references: 0);
}

class _MemoryGateway implements AppGateway {
  _MemoryGateway(
    this.snapshot, {
    this.supportsPhotoLibrarySave = false,
    this.creditError,
    this.assets = const <String, Uint8List>{},
  });

  LocalSnapshot snapshot;
  @override
  final bool supportsPhotoLibrarySave;
  final Object? creditError;
  final Map<String, Uint8List> assets;
  int invalidationCount = 0;
  Uint8List? photoLibraryBytes;
  String? photoLibraryFileName;

  @override
  bool get usesCompanion => false;

  @override
  String get persistenceDescription => 'Memory';

  @override
  Future<LocalSnapshot> load() async => snapshot;

  @override
  Future<LocalSnapshot> setPreferences(AppPreferences preferences) async {
    snapshot = LocalSnapshot(
      generations: snapshot.generations,
      folders: snapshot.folders,
      savedReferences: snapshot.savedReferences,
      preferences: preferences,
      hasApiKey: snapshot.hasApiKey,
      connectedProviders: snapshot.connectedProviders,
      availableProviders: snapshot.availableProviders,
      storage: snapshot.storage,
    );
    return snapshot;
  }

  @override
  Future<LocalSnapshot> setApiKey(String value) async => snapshot;

  @override
  Future<double> verifyKey([String? candidate]) async => 0;

  @override
  Future<double> getCredits() async {
    if (creditError != null) {
      invalidationCount += 1;
      snapshot = LocalSnapshot(
        generations: snapshot.generations,
        folders: snapshot.folders,
        savedReferences: snapshot.savedReferences,
        preferences: snapshot.preferences,
        hasApiKey: false,
        connectedProviders: snapshot.connectedProviders,
        availableProviders: snapshot.availableProviders,
        storage: snapshot.storage,
      );
      throw creditError!;
    }
    return 0;
  }

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
  Future<Uint8List> readAsset(AssetReference reference) async =>
      assets[reference.value] ?? Uint8List(0);

  @override
  Uri mediaUri(String source) => Uri.parse(source);

  @override
  Future<Uint8List> downloadMedia(String source) async =>
      Uint8List.fromList(<int>[1, 2, 3]);

  @override
  Future<void> saveMediaToPhotoLibrary(
    Uint8List bytes,
    String fileName,
    String contentType,
  ) async {
    photoLibraryBytes = bytes;
    photoLibraryFileName = fileName;
  }
}

class _PendingPreferenceWrite {
  const _PendingPreferenceWrite(this.preferences, this.completer);

  final AppPreferences preferences;
  final Completer<LocalSnapshot> completer;
}

class _DelayedPreferencesGateway extends _MemoryGateway {
  _DelayedPreferencesGateway(super.snapshot);

  final List<_PendingPreferenceWrite> _pending = <_PendingPreferenceWrite>[];

  List<AppSection> get pendingPreferences => _pending
      .map((request) => request.preferences.activeSection)
      .toList(growable: false);

  @override
  Future<LocalSnapshot> setPreferences(AppPreferences preferences) {
    final completer = Completer<LocalSnapshot>();
    _pending.add(_PendingPreferenceWrite(preferences, completer));
    return completer.future;
  }

  Future<void> completeNextPreference() async {
    final request = _pending.removeAt(0);
    request.completer.complete(await super.setPreferences(request.preferences));
  }
}

class _DelayedHistoryGateway extends _MemoryGateway {
  _DelayedHistoryGateway(super.snapshot);

  Completer<LocalSnapshot>? _historyClear;
  LocalSnapshot? _historySnapshot;

  @override
  Future<LocalSnapshot> clearHistory() {
    _historySnapshot = snapshot;
    return (_historyClear = Completer<LocalSnapshot>()).future;
  }

  void completeHistoryClear() {
    _historyClear!.complete(_historySnapshot!);
  }
}

class _ProviderMemoryGateway extends _MemoryGateway implements ProviderGateway {
  _ProviderMemoryGateway(super.snapshot, [this.account]);

  final List<String> quotedResolutions = <String>[];
  final List<Map<String, Object?>> quotedInputs = <Map<String, Object?>>[];
  final ProviderAccountStatus? account;

  @override
  Future<CostEstimate?> quoteProviderCost(
    String provider,
    String model,
    Map<String, Object?> input,
  ) async {
    final resolution = input['resolution']?.toString() ?? '';
    quotedResolutions.add(resolution);
    quotedInputs.add(Map<String, Object?>.from(input));
    final credits = input['prompt'] == 'Premium prompt'
        ? 700.0
        : resolution == 'fhd'
        ? 466.0
        : 185.0;
    return CostEstimate(
      minimumUsd: credits / 100,
      maximumUsd: credits / 100,
      basis: 'artcraft-live-quote',
      providerUnitsMinimum: credits,
      providerUnitsMaximum: credits,
      providerUnitLabel: 'credits',
    );
  }

  @override
  Future<LocalSnapshot> setProviderApiKey(
    String provider,
    String value,
  ) async => snapshot;

  @override
  Future<ProviderAccountStatus> verifyProviderKey(
    String provider, [
    String? candidate,
  ]) async => account ?? ProviderAccountStatus(provider: provider);

  @override
  Future<ProviderAccountStatus> getProviderAccount(String provider) async =>
      account ?? ProviderAccountStatus(provider: provider);

  @override
  Future<LocalSnapshot> clearProviderApiKey(String provider) async => snapshot;

  @override
  Future<List<ProviderModelPrice>> listProviderModels(String provider) async =>
      publishedProviderPrices(provider);
}

class _MemoryLocalDataStore extends LocalDataStore {
  _MemoryLocalDataStore([this.data = const StoredData()]);

  StoredData data;
  bool fileExists = false;

  @override
  Future<bool> exists() async => fileExists;

  @override
  Future<StoredData> read() async => data;

  @override
  Future<void> write(StoredData value) async {
    data = value;
    fileExists = true;
  }

  @override
  Future<StorageStats> stats(int records) async => StorageStats(
    path: 'memory',
    bytes: data.encode().length,
    records: records,
  );
}

class _RejectedCreditsApi extends BflApi {
  @override
  Future<double> getCredits(String apiKey) async {
    throw const ProviderException('BFL rejected this API key.', status: 401);
  }
}

class _StatusWithoutProgressApi extends BflApi {
  @override
  Future<Map<String, Object?>> poll(String apiKey, String pollingUrl) async =>
      <String, Object?>{'status': 'Pending'};
}

class _MemoryShellUpdater implements ShellUpdater {
  _MemoryShellUpdater({required this.result});

  final Map<String, Object?> result;
  final List<bool> forcedChecks = <bool>[];
  final StreamController<ShellUpdateEvent> _events =
      StreamController<ShellUpdateEvent>.broadcast();
  int startCount = 0;

  @override
  Future<Map<String, Object?>> check({bool force = false}) async {
    forcedChecks.add(force);
    return result;
  }

  @override
  Stream<ShellUpdateEvent> get events => _events.stream;

  @override
  Future<Map<String, Object?>> start() async {
    startCount += 1;
    await Future<void>.delayed(const Duration(milliseconds: 10));
    return const <String, Object?>{
      'started': false,
      'error': 'Test update stopped before download.',
    };
  }
}
