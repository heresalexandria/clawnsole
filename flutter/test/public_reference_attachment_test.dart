import 'dart:async';

import 'package:clawnsole/app/app_controller.dart';
import 'package:clawnsole/app/app_theme.dart';
import 'package:clawnsole/core/apipod_model_contracts.dart';
import 'package:clawnsole/core/gateway.dart';
import 'package:clawnsole/core/models.dart';
import 'package:clawnsole/core/provider_catalog.dart';
import 'package:clawnsole/ui/references_screen.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

const hosted = 'https://cdn.example.com/original.mp4';
const retained = AssetReference(
  kind: 'local',
  value: 'original.mp4',
  label: 'Motion',
  contentType: 'video/mp4',
);
final now = DateTime.utc(2026, 11, 5);

SavedReference saved({
  String? url,
  DateTime? expires,
  AssetReference asset = retained,
}) => SavedReference(
  id: 'saved-motion',
  name: 'Motion',
  kind: MediaReferenceKind.video,
  asset: asset,
  createdAt: now,
  updatedAt: now,
  durationSeconds: 4,
  publicSourceUrl: url,
  publicSourceExpiresAt: expires,
);

Generation generation({GenerationConfig? config, DateTime? expires}) =>
    Generation(
      localId: 'generated-motion',
      provider: 'apipod',
      model: 'seedance-2.5-r2v',
      status: 'Ready',
      prompt: 'A moving camera.',
      mode: VideoMode.i2v,
      config:
          config ??
          const GenerationConfig(
            aspectRatio: '16:9',
            duration: 4,
            resolution: 'hd',
            generateAudio: true,
            safetyTolerance: 2,
            draft: false,
          ),
      resultAsset: retained,
      resultUrl: hosted,
      deliveryExpiresAt: expires,
      createdAt: now,
      updatedAt: now,
    );

LocalSnapshot snapshot({
  List<SavedReference> references = const [],
  List<Generation> generations = const [],
}) => LocalSnapshot(
  savedReferences: references,
  generations: generations,
  preferences: const AppPreferences(provider: 'apipod'),
  hasApiKey: true,
  connectedProviders: const {'apipod'},
  availableProviders: const {'apipod'},
  storage: const StorageStats(path: 'memory', bytes: 0, records: 0),
);

AppController _controller(_Gateway gateway) => AppController(gateway: gateway)
  ..snapshot = gateway.snapshot
  ..loading = false
  ..selectedProviderId = 'apipod'
  ..selectedModelId = 'seedance-2.5-r2v';

void main() {
  tearDown(resetProviderCatalog);

  for (final companion in [false, true]) {
    test(
      '${companion ? 'companion' : 'native'} submits hosted saved video without hydrating its retained file',
      () async {
        final reference = saved(url: hosted);
        final gateway = _Gateway(
          snapshot(references: [reference]),
          usesCompanion: companion,
        )..creditGate = Completer<double>();
        final app = _controller(gateway);
        addTearDown(app.dispose);
        await app.selectProviderModel('apipod', 'seedance-2.5-t2v');
        app.updateForm((form) => form.prompt = 'Follow the camera.');
        await app.addReferenceCandidates(MediaReferenceKind.video, [
          app.savedReferenceCandidate(reference),
        ]);
        expect(app.validate(), isNull);
        final submitting = app.submit(providerRetentionRiskAcknowledged: true);
        await gateway.creditStarted.future.timeout(const Duration(seconds: 2));
        // A selection change during the awaited account lookup must not
        // change the captured route, reference URL, or quote attribution.
        await app.selectProviderModel('apipod', 'seedance-2.5-spicy-t2v');
        gateway.creditGate!.complete(100);
        await submitting;
        final submitted = gateway.submissions.single;
        expect(submitted.record.model, 'seedance-2.5-r2v');
        expect(submitted.input['reference_videos'], [hosted]);
        expect(submitted.record.config.references!.single.source, retained);
        expect(
          apipodGenerationPayload(
            submitted.record.model,
            submitted.input,
          )['video_urls'],
          [hosted],
        );
        expect(gateway.reads, 0);
      },
    );
  }

  test(
    'hosted restored frame submits without reading its retained preview',
    () async {
      final gateway = _Gateway(snapshot());
      final app = _controller(gateway);
      addTearDown(app.dispose);
      await app.selectProviderModel('apipod', 'seedance-2.5-t2v');
      app.updateForm((form) {
        form.prompt = 'A calm camera move.';
        form.keyframes = [
          const KeyframeDraft(
            id: 'first',
            label: 'First frame',
            role: KeyframeRole.start,
            source: 'https://cdn.example.com/frame.png',
            retained: AssetReference(
              kind: 'local',
              value: 'frame.png',
              label: 'First frame',
            ),
            seconds: 0,
          ),
        ];
      });
      expect(app.validate(), isNull);
      await app.submit(providerRetentionRiskAcknowledged: true);
      expect(gateway.submissions.single.input['keyframes'], [
        'https://cdn.example.com/frame.png',
      ]);
      expect(gateway.reads, 0);
    },
  );

  test(
    'task draft finalization does not hydrate hidden preview references',
    () async {
      final gateway = _Gateway(snapshot());
      final app = _controller(gateway);
      addTearDown(app.dispose);
      await app.selectProviderModel('apipod', 'seedance-2.5-draft');
      app.updateForm((form) {
        form.draftUrl = 'completed-draft-task';
        form.resolution = 'fhd';
        form.references = [
          const MediaReferenceDraft(
            id: 'preview',
            label: 'Retained draft preview',
            kind: MediaReferenceKind.video,
            source: '',
            retained: retained,
          ),
        ];
      });
      expect(app.validate(), isNull);
      await app.submit(providerRetentionRiskAcknowledged: true);
      expect(gateway.submissions.single.input, {
        'mode': 'draft_enhance',
        'draft_task_id': 'completed-draft-task',
        'resolution': 'fhd',
      });
      expect(gateway.reads, 0);
    },
  );

  test(
    'retained generated film attaches its hosted original without hydration',
    () async {
      final gateway = _Gateway(snapshot(generations: [generation()]));
      final app = _controller(gateway);
      addTearDown(app.dispose);
      await app.addReferenceCandidates(
        MediaReferenceKind.video,
        app.generatedReferenceCandidates(MediaReferenceKind.video),
      );
      expect(app.form.references.single.requestSource, hosted);
      expect(app.form.references.single.retained, retained);
      expect(gateway.reads, 0);
      expect(app.buildInputForTesting()['reference_videos'], [hosted]);
      expect(app.currentConfig.references!.single.source, retained);
      expect(app.currentConfig.references!.single.publicSourceUrl, hosted);
    },
  );

  test(
    'saved hosted provenance and legacy generation asset match both attach',
    () async {
      for (final legacy in [false, true]) {
        final reference = saved(url: legacy ? null : hosted);
        final gateway = _Gateway(
          snapshot(
            references: [reference],
            generations: legacy ? [generation()] : [],
          ),
        );
        final app = _controller(gateway);
        addTearDown(app.dispose);
        await app.addReferenceCandidates(MediaReferenceKind.video, [
          app.savedReferenceCandidate(reference),
        ]);
        expect(app.form.references.single.requestSource, hosted);
        expect(app.form.references.single.savedReferenceId, reference.id);
        expect(gateway.reads, 0);
      }
    },
  );

  test(
    'private, unsafe and expired references give a reason before any read',
    () async {
      for (final reference in [
        saved(),
        saved(url: 'https://127.0.0.1/private.mp4'),
        saved(url: hosted, expires: DateTime.utc(2000)),
        saved(
          asset: const AssetReference(
            kind: 'drive',
            value: 'private-file-id',
            label: 'Motion',
          ),
        ),
      ]) {
        final gateway = _Gateway(snapshot(references: [reference]));
        final app = _controller(gateway);
        addTearDown(app.dispose);
        final candidate = app.savedReferenceCandidate(reference);
        expect(
          app.referenceCandidateProblem(candidate),
          contains('no available public HTTPS URL'),
        );
        await app.addReferenceCandidates(MediaReferenceKind.video, [candidate]);
        expect(app.form.references, isEmpty);
        expect(app.notice, contains('paste its URL'));
        expect(gateway.reads, 0);
      }
      final gateway = _Gateway(
        snapshot(generations: [generation(expires: DateTime.utc(2000))]),
      );
      final app = _controller(gateway);
      addTearDown(app.dispose);
      expect(
        app.referenceCandidatePublicUrl(
          app.generatedReferenceCandidates(MediaReferenceKind.video).single,
        ),
        isNull,
      );
    },
  );

  test(
    'schema27 preserves media and provenance through storage and reuse',
    () async {
      final reference = saved(url: hosted, expires: DateTime.utc(2100));
      final gateway = _Gateway(snapshot(references: [reference]));
      final app = _controller(gateway);
      addTearDown(app.dispose);
      await app.addReferenceCandidates(MediaReferenceKind.video, [
        app.savedReferenceCandidate(reference),
      ]);
      final output = generation(config: app.currentConfig);
      final data = StoredData(
        savedReferences: [reference],
        generations: [output],
      );
      final decoded = StoredData.fromJson(data.toJson());
      expect(decoded.toJson()['schemaVersion'], 27);
      expect(decoded.savedReferences.single.publicSourceUrl, hosted);
      expect(
        decoded.generations.single.config.references!.single.publicSourceUrl,
        hosted,
      );
      expect(
        decoded.generations.single.config.references!.single.source!.toJson(),
        retained.toJson(),
      );
      final legacy = data.toJson()..['schemaVersion'] = 26;
      final migrated = StoredData.fromJson(legacy);
      expect(migrated.savedReferences.single.asset.toJson(), retained.toJson());
      final restoredGateway = _Gateway(
        snapshot(references: decoded.savedReferences),
      );
      final restored = _controller(restoredGateway);
      addTearDown(restored.dispose);
      await restored.reuse(decoded.generations.single);
      expect(restored.form.references.single.requestSource, hosted);
      expect(
        restored.form.references.single.retained!.toJson(),
        retained.toJson(),
      );
      expect(restoredGateway.reads, 0);
    },
  );

  testWidgets(
    'iOS saved picker explains local-only media and adds hosted saved video',
    (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      try {
        await tester.binding.setSurfaceSize(const Size(430, 932));
        final good = saved(url: hosted);
        final bad = SavedReference(
          id: 'private',
          name: 'Private clip',
          kind: MediaReferenceKind.video,
          asset: retained,
          createdAt: now,
          updatedAt: now,
          durationSeconds: 4,
        );
        final gateway = _Gateway(snapshot(references: [bad, good]));
        final app = _controller(gateway);
        addTearDown(app.dispose);
        await tester.pumpWidget(
          MaterialApp(
            theme: buildClawnsoleTheme(Brightness.light),
            home: Scaffold(
              body: Builder(
                builder: (context) => TextButton(
                  onPressed: () async {
                    final picked = await showReferencePicker(
                      context,
                      app,
                      kind: MediaReferenceKind.video,
                      maximum: 3,
                    );
                    if (picked != null) {
                      await app.addReferenceCandidates(
                        MediaReferenceKind.video,
                        picked,
                      );
                    }
                  },
                  child: const Text('Choose saved videos'),
                ),
              ),
            ),
          ),
        );
        await tester.tap(find.text('Choose saved videos'));
        await tester.pumpAndSettle();
        expect(
          find.byKey(const ValueKey('reference-picker-public-url-hint')),
          findsOneWidget,
        );
        expect(find.text('Public HTTPS URL required'), findsOneWidget);
        expect(
          tester
              .widget<InkWell>(
                find.byKey(const ValueKey('reference-picker-card-private')),
              )
              .onTap,
          isNull,
        );
        final card = find.byKey(
          const ValueKey('reference-picker-card-saved-motion'),
        );
        await tester.scrollUntilVisible(
          card,
          160,
          scrollable: find
              .descendant(
                of: find.byKey(const ValueKey('reference-picker-card-grid')),
                matching: find.byType(Scrollable),
              )
              .first,
        );
        await tester.tapAt(tester.getTopLeft(card) + const Offset(20, 20));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Add 1'));
        await tester.pumpAndSettle();
        expect(app.form.references.single.requestSource, hosted);
        expect(app.form.references.single.savedReferenceId, good.id);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.binding.setSurfaceSize(null);
      } finally {
        debugDefaultTargetPlatformOverride = null;
      }
    },
  );
}

class _Gateway implements AppGateway {
  _Gateway(this.snapshot, {this.usesCompanion = false});
  LocalSnapshot snapshot;
  int reads = 0;
  Completer<double>? creditGate;
  final creditStarted = Completer<void>();
  final submissions = <GenerationSubmission>[];
  @override
  final bool usesCompanion;
  @override
  bool get supportsPhotoLibrarySave => false;
  @override
  String get persistenceDescription => 'Memory';
  @override
  Uri mediaUri(String source) => Uri.parse(source);
  @override
  Future<LocalSnapshot> setPreferences(AppPreferences preferences) async =>
      snapshot;
  @override
  Future<double> getCredits() async {
    if (!creditStarted.isCompleted) creditStarted.complete();
    return creditGate?.future ?? 100;
  }

  @override
  Future<Generation> submit(GenerationSubmission submission) async {
    submissions.add(submission);
    return submission.record.copyWith(status: 'Pending', requestId: 'accepted');
  }

  @override
  Future<Uint8List> readAsset(AssetReference reference) async {
    reads++;
    throw StateError('No hydration expected');
  }

  @override
  Future<Uri> assetUri(AssetReference reference) async =>
      Uri.parse('https://cdn.example.com/preview.mp4');
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
