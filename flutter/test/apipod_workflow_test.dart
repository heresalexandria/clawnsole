import 'dart:typed_data';

import 'package:clawnsole/app/app_controller.dart';
import 'package:clawnsole/core/apipod_model_contracts.dart';
import 'package:clawnsole/core/gateway.dart';
import 'package:clawnsole/core/models.dart';
import 'package:clawnsole/core/provider_catalog.dart';
import 'package:clawnsole/core/provider_model_selection.dart';
import 'package:flutter_test/flutter_test.dart';

const _url = 'https://cdn.example.com/camera.mp4';
final _saved = SavedReference(
  id: 'saved-motion',
  name: 'Camera',
  kind: MediaReferenceKind.video,
  asset: const AssetReference(
    kind: 'local',
    value: 'camera.mp4',
    label: 'Camera',
  ),
  publicSourceUrl: _url,
  durationSeconds: 4,
  createdAt: DateTime.utc(2026),
  updatedAt: DateTime.utc(2026),
);

void main() {
  tearDown(resetProviderCatalog);
  for (final companion in [false, true]) {
    test(
      '${companion ? 'companion' : 'native'} Seedance choice adapts to saved video, frames and empty prompt inputs',
      () async {
        final gateway = _WorkflowGateway(companion);
        final app = _controller(gateway);
        addTearDown(app.dispose);
        await app.selectProviderModel('apipod', 'seedance-2.5-t2v');
        app.updateForm((form) => form.prompt = 'A camera pans.');
        expect(app.selectedModel.selectionId, 'seedance-2.5');
        expect(app.supportsMediaReferences, isTrue);
        expect(app.canAddFrame(KeyframeRole.start), isTrue);
        expect(app.canAddReference(MediaReferenceKind.video), isTrue);
        expect(app.referenceLimit(MediaReferenceKind.video), greaterThan(0));
        await app.addReferenceCandidates(MediaReferenceKind.video, [
          app.savedReferenceCandidate(_saved),
        ]);
        expect(app.selectedModel.id, 'seedance-2.5-r2v');
        expect(app.selectedModel.selectionId, 'seedance-2.5');
        expect(app.form.references.single.requestSource, _url);
        expect(gateway.mediaReads, 0);
        final payload = apipodGenerationPayload(
          app.selectedModel.id,
          app.buildInputForTesting(),
        );
        expect(payload['model'], 'seedance-2.5-r2v');
        expect(payload['video_urls'], [_url]);
        app.removeReference(app.form.references.single.id);
        expect(app.selectedModel.id, 'seedance-2.5-t2v');
        app.addUrlFrame(KeyframeRole.start);
        app.updateFrame(
          app.form.keyframes.single.id,
          source: 'https://cdn.example.com/frame.png',
        );
        expect(app.selectedModel.id, 'seedance-2.5-i2v');
        expect(
          apipodGenerationPayload(
            app.selectedModel.id,
            app.buildInputForTesting(),
          )['model'],
          'seedance-2.5-i2v',
        );
        app.removeFrame(app.form.keyframes.single.id);
        expect(app.selectedModel.id, 'seedance-2.5-t2v');
      },
    );
  }

  test(
    'automatic guidance routing remains inside the chosen Seedance variant',
    () async {
      final app = _controller(_WorkflowGateway(false));
      addTearDown(app.dispose);
      await app.selectProviderModel('apipod', 'seedance-2.5-spicy-t2v');
      await app.addReferenceCandidates(MediaReferenceKind.video, [
        app.savedReferenceCandidate(_saved),
      ]);
      expect(app.selectedModel.id, 'seedance-2.5-spicy-r2v');
      app.removeReference(app.form.references.single.id);
      expect(app.selectedModel.id, 'seedance-2.5-spicy-t2v');
      app.addUrlFrame(KeyframeRole.start);
      expect(app.selectedModel.id, 'seedance-2.5-spicy-i2v');
      app.removeFrame(app.form.keyframes.single.id);
      await app.selectProviderModel('apipod', 'seedance-1.0-pro-fast-t2v');
      expect(app.canAddReference(MediaReferenceKind.video), isFalse);
      await app.addReferenceCandidates(MediaReferenceKind.video, [
        app.savedReferenceCandidate(_saved),
      ]);
      expect(app.form.references, isEmpty);
      expect(app.selectedModel.selectionId, 'seedance-1.0-pro-fast');
    },
  );

  test(
    'switching back from a no-reference choice restores references and resolves R2V',
    () async {
      final app = _controller(_WorkflowGateway(false));
      addTearDown(app.dispose);
      await app.selectProviderModel('apipod', 'seedance-2.5-t2v');
      await app.addReferenceCandidates(MediaReferenceKind.video, [
        app.savedReferenceCandidate(_saved),
      ]);
      await app.selectProviderModel('apipod', 'seedance-1.0-pro-fast-t2v');
      expect(app.form.references, isEmpty);
      await app.selectProviderModel('apipod', 'seedance-2.5-t2v');
      expect(app.form.references.single.requestSource, _url);
      expect(app.selectedModel.id, 'seedance-2.5-r2v');
    },
  );

  test(
    'group routing and reselecting preserve edited duration and resolution',
    () async {
      final app = _controller(_WorkflowGateway(false));
      addTearDown(app.dispose);
      await app.selectProviderModel('apipod', 'seedance-2.5-t2v');
      app.updateForm((form) {
        form.resolution = 'fhd';
        form.durationSeconds = 12;
      });
      await app.addReferenceCandidates(MediaReferenceKind.video, [
        app.savedReferenceCandidate(_saved),
      ]);
      expect(app.selectedModel.id, 'seedance-2.5-r2v');
      await app.selectProviderModel('apipod', 'seedance-2.5-t2v');
      expect(app.selectedModel.id, 'seedance-2.5-r2v');
      expect(app.form.resolution, 'fhd');
      expect(app.form.durationSeconds, 12);
      app.removeReference(app.form.references.single.id);
      expect(app.selectedModel.id, 'seedance-2.5-t2v');
      expect(app.form.resolution, 'fhd');
      expect(app.form.durationSeconds, 12);
      await app.selectProviderModel('apipod', 'seedance-2.5-spicy-t2v');
      app.updateForm((form) {
        form.resolution = 'sd';
        form.durationSeconds = 5;
      });
      await app.selectProviderModel('apipod', 'seedance-2.5-t2v');
      expect(app.form.resolution, 'fhd');
      expect(app.form.durationSeconds, 12);
    },
  );

  test(
    'unfavoriting a group removes legacy sibling stars and preserves other variants',
    () async {
      final gateway = _WorkflowGateway(false);
      final app = _controller(gateway);
      addTearDown(app.dispose);
      final unrelated = modelFavoriteKey('apipod', 'seedance-2.5-spicy-r2v');
      app.favoriteModelKeys = [
        modelFavoriteKey('apipod', 'seedance-2.5-i2v'),
        modelFavoriteKey('apipod', 'seedance-2.5-r2v'),
        unrelated,
      ];
      expect(app.isFavoriteModel('apipod', 'seedance-2.5-t2v'), isTrue);
      await app.toggleFavoriteModel('apipod', 'seedance-2.5-t2v');
      expect(app.favoriteModelKeys, [unrelated]);
      expect(gateway.snapshot.preferences.favoriteModels, [unrelated]);
      await app.toggleFavoriteModel('apipod', 'seedance-2.5-i2v');
      expect(
        app.favoriteModelKeys.where((key) => key != unrelated),
        hasLength(1),
      );
      expect(app.isFavoriteModel('apipod', 'seedance-2.5-r2v'), isTrue);
    },
  );

  test(
    'grouped picker choices preserve every exact route in the pricing list',
    () async {
      final app = _controller(_WorkflowGateway(true));
      addTearDown(app.dispose);
      await app.refreshProviderModels('apipod');
      final routes = providerById('apipod').models;
      expect(routes, hasLength(103));
      expect(
        providerModelSelections(
          providerById('apipod'),
        ).where((model) => model.selectionId == 'seedance-2.5'),
        hasLength(1),
      );
      final prices = app.providerPrices['apipod']!;
      expect(
        prices.map((price) => price.model.split(':').first).toSet(),
        containsAll(routes.map((model) => model.id)),
      );
      await app.selectProviderModel('apipod', 'seedance-2.5-t2v');
      expect(app.currentEstimate.maximumUsd, greaterThan(0));
      await app.addReferenceCandidates(MediaReferenceKind.video, [
        app.savedReferenceCandidate(_saved),
      ]);
      expect(app.selectedModel.id, 'seedance-2.5-r2v');
      expect(app.currentEstimate.maximumUsd, greaterThan(0));
    },
  );
}

AppController _controller(_WorkflowGateway gateway) =>
    AppController(gateway: gateway)
      ..snapshot = gateway.snapshot
      ..loading = false
      ..selectedProviderId = 'apipod'
      ..selectedModelId = 'seedance-2.5-t2v';

class _WorkflowGateway implements AppGateway, ProviderGateway {
  _WorkflowGateway(this.usesCompanion);
  @override
  final bool usesCompanion;
  int mediaReads = 0;
  LocalSnapshot snapshot = LocalSnapshot(
    generations: const [],
    savedReferences: [_saved],
    preferences: const AppPreferences(provider: 'apipod'),
    hasApiKey: false,
    availableProviders: const {'apipod'},
    storage: const StorageStats(path: 'memory', bytes: 0, records: 0),
  );
  @override
  bool get supportsPhotoLibrarySave => false;
  @override
  String get persistenceDescription => 'Memory';
  @override
  Uri mediaUri(String source) => Uri.parse(source);
  @override
  Future<LocalSnapshot> setPreferences(AppPreferences preferences) async =>
      snapshot = snapshot.copyWith(preferences: preferences);
  @override
  Future<List<ProviderModelPrice>> listProviderModels(String provider) async =>
      publishedProviderPrices(provider);
  @override
  Future<CostEstimate?> quoteProviderCost(
    String provider,
    String model,
    Map<String, Object?> input,
  ) async => null;
  @override
  Future<Uint8List> readAsset(AssetReference reference) async {
    mediaReads++;
    throw StateError('Hosted reference must not hydrate');
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
