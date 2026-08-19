import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:clawnsole/app/app_controller.dart';
import 'package:clawnsole/app/app_theme.dart';
import 'package:clawnsole/app/clawnsole_app.dart';
import 'package:clawnsole/core/bfl_api.dart';
import 'package:clawnsole/core/generation_status.dart';
import 'package:clawnsole/core/gateway.dart';
import 'package:clawnsole/core/local_data_store.dart';
import 'package:clawnsole/core/local_data_store_io.dart'
    show retainedAssetExtension;
import 'package:clawnsole/core/ltx_api.dart';
import 'package:clawnsole/core/models.dart';
import 'package:clawnsole/core/native_gateway.dart';
import 'package:clawnsole/core/pricing.dart';
import 'package:clawnsole/core/provider_api.dart';
import 'package:clawnsole/core/shell_bridge.dart';
import 'package:clawnsole/core/store_update.dart';
import 'package:clawnsole/core/update_check.dart';
import 'package:clawnsole/core/update_status.dart';
import 'package:clawnsole/core/web_gateway.dart';
import 'package:clawnsole/ui/common_widgets.dart';
import 'package:clawnsole/ui/create_screen.dart';
import 'package:clawnsole/ui/generation_loading_placeholder.dart';
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
    expect(estimateCredits(VideoMode.v2v, hdEightSeconds).minimum, 328);
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
    expect(autoEstimate.minimum, 265);
    expect(autoEstimate.maximum, 1060);
  });

  test('uses exact matching BFL history as the next estimate', () {
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
    expect(estimate.minimum, 130);
    expect(estimate.maximum, 130);
    expect(estimate.basis, 'provider-history');
  });

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
    'shows a particle video placeholder at the generation aspect ratio',
    (tester) async {
      final now = DateTime.utc(2026, 8, 19, 12);
      final item = Generation(
        localId: 'portrait-video',
        status: 'Pending',
        progress: 42,
        prompt: 'A neon figure moving through a particle field.',
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
      expect(find.text('Saved generation'), findsNothing);
      expect(find.text('RENDERING  •  42%'), findsOneWidget);
      final size = tester.getSize(find.byType(GenerationLoadingPlaceholder));
      expect(size.width / size.height, closeTo(9 / 16, .01));

      await tester.pumpWidget(const SizedBox.shrink());
      controller.dispose();
    },
  );

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
      expect(decoded.apiKey, 'secret');
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
    expect(decoded.toJson()['schemaVersion'], 12);
  });

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
      expect(decoded.toJson()['schemaVersion'], 12);
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
    await tester.ensureVisible(find.text('Reuse inputs'));
    await tester.tap(find.text('Reuse inputs'));
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

    expect(find.text('MODEL & PROVIDER'), findsOneWidget);
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

  testWidgets('saved reference picker renders search and collection tabs', (
    tester,
  ) async {
    final now = DateTime.utc(2026, 8, 19);
    final controller = AppController();
    controller.snapshot = LocalSnapshot(
      generations: const <Generation>[],
      savedReferences: <SavedReference>[
        SavedReference(
          id: 'saved-image',
          name: 'Hero turnaround',
          kind: MediaReferenceKind.image,
          asset: const AssetReference(
            kind: 'remote',
            value: 'https://cdn.test/hero.png',
            label: 'hero.png',
            contentType: 'image/png',
          ),
          createdAt: now,
          updatedAt: now,
          tags: const <String>['hero'],
        ),
      ],
      preferences: const AppPreferences(),
      hasApiKey: false,
      storage: const StorageStats(path: 'memory', bytes: 0, records: 1),
    );
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
                kind: MediaReferenceKind.image,
                maximum: 3,
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
    expect(find.text('Add saved images'), findsOneWidget);
    expect(find.text('References'), findsOneWidget);
    expect(find.text('Generated'), findsOneWidget);
    expect(find.text('Hero turnaround'), findsOneWidget);
    expect(find.text('0/3 selected'), findsOneWidget);
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

    expect(updater.forcedChecks, <bool>[false, false, true]);
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
    await tester.pump(const Duration(seconds: 4));
    await tester.pump();
    expect(updater.forcedChecks, <bool>[false]);

    await tester.pump(const Duration(hours: 24));
    await tester.pump();
    expect(updater.forcedChecks, <bool>[false, false]);

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
    await tester.pump(const Duration(seconds: 4));
    await tester.pump();
    expect(checks, 1);

    await tester.pump(const Duration(hours: 24));
    await tester.pump();
    expect(checks, 2);

    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('update chip animates and starts the macOS installer', (
    tester,
  ) async {
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

    expect(find.byType(UpdateAvailableChip), findsOneWidget);
    expect(find.text('Update Available'), findsOneWidget);
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
  });

  test('form infers every FLUX 3 generation mode from its inputs', () {
    expect(VideoMode.values, hasLength(4));
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
}

class _MemoryGateway implements AppGateway {
  _MemoryGateway(
    this.snapshot, {
    this.supportsPhotoLibrarySave = false,
    this.creditError,
  });

  LocalSnapshot snapshot;
  @override
  final bool supportsPhotoLibrarySave;
  final Object? creditError;
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
  Future<Uint8List> readAsset(AssetReference reference) async => Uint8List(0);

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
