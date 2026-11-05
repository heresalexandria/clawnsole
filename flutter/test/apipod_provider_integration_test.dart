import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:clawnsole/core/bfl_api.dart';
import 'package:clawnsole/core/apipod_api.dart';
import 'package:clawnsole/core/gateway.dart';
import 'package:clawnsole/core/generation_status.dart';
import 'package:clawnsole/core/hybrid_data_store.dart';
import 'package:clawnsole/core/local_data_store_io.dart';
import 'package:clawnsole/core/models.dart';
import 'package:clawnsole/core/native_gateway.dart';
import 'package:clawnsole/core/provider_api.dart';
import 'package:clawnsole/core/provider_catalog.dart';
import 'package:clawnsole/core/reference_video_normalizer.dart';
import 'package:clawnsole/core/secure_value_store.dart';
import 'package:clawnsole/core/settings_vault_data_store.dart';
import 'package:clawnsole/core/web_gateway.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import '../tool/clawnsole_companion.dart';

const _model = 'seedance-2.5-t2v';
const _queueRoot = 'https://api.apipod.ai/v1/videos/status';
const _requestId = 'apipod-integration-request';
const _key = 'fixture-apipod-secret';
const _config = GenerationConfig(
  aspectRatio: '16:9',
  duration: 5,
  resolution: 'hd',
  generateAudio: true,
  safetyTolerance: 2,
  draft: false,
);

void main() {
  for (final surface in ['native iOS', 'native Android/Windows', 'companion']) {
    final companion = surface == 'companion';
    final isIos = surface == 'native iOS';

    test('$surface APIPod keys and queue receipts survive restart', () async {
      final fixture = await _ApipodFixture.create(
        companion: companion,
        isIos: isIos,
      );
      addTearDown(fixture.dispose);
      final provider = fixture.provider;
      final initial = await fixture.gateway.load();
      expect(initial.availableProviders, contains('apipod'));
      expect(initial.hasApiKeyFor('apipod'), isFalse);

      await provider.setProviderApiKey('bfl', 'unrelated-key');
      final saved = await provider.setProviderApiKey('apipod', '  $_key  ');
      expect(saved.hasApiKeyFor('apipod'), isTrue);
      expect((await provider.verifyProviderKey('apipod')).provider, 'apipod');
      expect((await provider.getProviderAccount('apipod')).balance, isNull);
      await expectLater(
        provider.verifyProviderKey('apipod', 'invalid-candidate'),
        throwsA(isA<ProviderException>()),
      );
      expect((await fixture.gateway.load()).hasApiKeyFor('apipod'), isTrue);

      final pending = await fixture.gateway.submit(_submission());
      expect(pending.provider, 'apipod');
      expect(pending.model, _model);
      expect(pending.billingUnit, 'usd');
      expect(pending.status, 'Pending');
      expect(pending.requestId, _requestId);
      expect(pending.pollingUrl, '$_queueRoot/$_requestId');
      expect(pending.quotedCostUsdMin, 1.1025);
      expect(pending.quotedCostUsdMax, 1.1025);
      expect(pending.realizedCostUsd, isNull);
      expect(fixture.submitCount, 1);

      // A fresh gateway/server and settings vault must recover both the
      // credential and accepted receipt without submitting another job.
      await fixture.restart();
      final restored = await fixture.gateway.load();
      expect(restored.hasApiKeyFor('apipod'), isTrue);
      var generation = restored.generations.single;
      expect(generation.requestId, _requestId);
      expect(generation.pollingUrl, pending.pollingUrl);
      generation = await fixture.delivery.pollStatus(generation);
      expect(generation.status, 'Pending');
      expect(generation.isWorking, isTrue);
      fixture.queueStatus = 'processing';
      generation = await fixture.delivery.pollStatus(generation);
      expect(generation.status, 'Pending');
      fixture.queueStatus = 'completed';
      generation = await fixture.delivery.pollStatus(generation);
      expect(generation.status, 'Ready');
      expect(generation.resultUrl, 'https://media.apipod.ai/fixture.mp4');
      expect(generation.resultAsset, isNull);
      expect(generation.quotedCostUsdMin, 1.1025);
      expect(generation.quotedCostUsdMax, 1.1025);
      expect(generation.realizedCostUsd, 1.09);
      expect(generation.cost, 1.09);
      expect(fixture.resultCount, 1);
      expect(fixture.submitCount, 1);

      final disk = await fixture.local.read();
      expect(disk.generations.single.resultUrl, generation.resultUrl);
      expect(
        await File(
          '${fixture.directory.path}/Clawnsole/clawnsole.json',
        ).readAsString(),
        isNot(contains(_key)),
      );
      expect(
        jsonEncode((await fixture.gateway.load()).toJson()),
        isNot(contains(_key)),
      );

      await fixture.restart();
      final completed = (await fixture.gateway.load()).generations.single;
      expect(completed.status, 'Ready');
      expect(completed.quotedCostUsdMin, 1.1025);
      expect(completed.realizedCostUsd, 1.09);
      expect(completed.cost, 1.09);
      expect(fixture.submitCount, 1);

      // Testing a rejected candidate never erases the saved key. A saved
      // credential rejected by the provider is removed on both surfaces.
      fixture.rejectSavedKey = true;
      await expectLater(
        fixture.provider.verifyProviderKey('apipod'),
        throwsA(isA<ProviderException>()),
      );
      final rejected = await fixture.gateway.load();
      expect(rejected.hasApiKeyFor('apipod'), isFalse);
      expect(rejected.hasApiKeyFor('bfl'), isTrue);
      await fixture.restart();
      expect((await fixture.gateway.load()).hasApiKeyFor('apipod'), isFalse);
    });

    test(
      '$surface APIPod completion without usage never settles the estimate',
      () async {
        final fixture = await _ApipodFixture.create(
          companion: companion,
          isIos: isIos,
        );
        addTearDown(fixture.dispose);
        await fixture.provider.setProviderApiKey('apipod', _key);
        final pending = await fixture.gateway.submit(_submission());
        fixture.queueStatus = 'completed';
        fixture.includeUsage = false;
        final completed = await fixture.delivery.pollStatus(pending);
        expect(completed.status, 'Ready');
        expect(completed.resultUrl, 'https://media.apipod.ai/fixture.mp4');
        expect(completed.quotedCostUsdMin, 1.1025);
        expect(completed.quotedCostUsdMax, 1.1025);
        expect(completed.cost, isNull);
        expect(completed.realizedCostUsd, isNull);
        expect(completed.realizedCostSource, isNull);

        await fixture.restart();
        final restored = (await fixture.gateway.load()).generations.single;
        expect(restored.status, 'Ready');
        expect(restored.quotedCostUsdMin, 1.1025);
        expect(restored.cost, isNull);
        expect(restored.realizedCostUsd, isNull);
        expect(restored.realizedCostSource, isNull);
      },
    );

    for (final model in ['seedance-2.5-i2v', 'seedance-2.5-r2v']) {
      test(
        '$surface $model preserves hosted media with auto-fix enabled',
        () async {
          final fixture = await _ApipodFixture.create(
            companion: companion,
            isIos: isIos,
          );
          addTearDown(fixture.dispose);
          await fixture.provider.setProviderApiKey('apipod', _key);
          fixture.expectedModel = model;
          final pending = await fixture.gateway.submit(
            _referenceSubmission(model),
          );
          expect(pending.status, 'Pending');
          expect(fixture.normalizer.calls, 0);
          expect(fixture.submitCount, 1);
          final payload = fixture.submittedPayload!;
          expect(payload['image_urls'], ['https://cdn.example.com/fox.png']);
          if (model.endsWith('-r2v')) {
            expect(payload['video_urls'], [
              'https://cdn.example.com/motion.mp4',
            ]);
            expect(payload['audio_urls'], [
              'https://cdn.example.com/voice.mp3',
            ]);
            expect(pending.quotedCostUsdMin, 1.0584);
            expect(
              pending.config.references!.first.source!.value,
              'https://cdn.example.com/fox.png',
            );
          } else {
            expect(
              pending.config.keyframes!.single.source!.value,
              'https://cdn.example.com/fox.png',
            );
          }
          expect(
            (await fixture.local.read()).encode(),
            isNot(contains('base64')),
          );
        },
      );
    }

    for (final finalization in [false, true]) {
      final model = finalization ? 'seedance-2.5-draft' : 'seedance-2.5-edit';
      test(
        '$surface $model preserves task IDs and source media through restart',
        () async {
          final fixture = await _ApipodFixture.create(
            companion: companion,
            isIos: isIos,
          );
          addTearDown(fixture.dispose);
          await fixture.provider.setProviderApiKey('apipod', _key);
          fixture.expectedModel = model;
          final pending = await fixture.gateway.submit(
            _sourceSubmission(finalization: finalization),
          );
          expect(pending.status, 'Pending');
          expect(pending.requestId, _requestId);
          expect(fixture.normalizer.calls, 0);
          expect(fixture.submitCount, 1);
          if (finalization) {
            expect(fixture.submittedPayload, {
              'model': model,
              'draft_task_id': 'completed-preview-task',
              'resolution': '1080p',
            });
            expect(pending.config.source, isNull);
            expect(pending.config.sourceLabel, 'completed-preview-task');
            expect(pending.draftCacheUrl, isNull);
          } else {
            expect(fixture.submittedPayload!['video_urls'], [
              'https://cdn.example.com/source.mp4',
              'https://cdn.example.com/reference.mp4',
            ]);
            expect(
              fixture.submittedPayload!['prompt'],
              'Restyle the fox using @video2.',
            );
            expect(fixture.submittedPayload!.containsKey('duration'), isFalse);
            expect(
              pending.config.source!.value,
              'https://cdn.example.com/source.mp4',
            );
            expect(
              pending.config.references!.single.source!.value,
              'https://cdn.example.com/reference.mp4',
            );
          }
          await fixture.restart();
          final restored = (await fixture.gateway.load()).generations.single;
          expect(restored.mode, pending.mode);
          expect(restored.config.toJson(), pending.config.toJson());
          expect(restored.draftCacheUrl, isNull);
          expect(fixture.submitCount, 1);
          fixture.queueStatus = 'completed';
          final completed = await fixture.delivery.pollStatus(restored);
          expect(completed.status, 'Ready');
          expect(completed.realizedCostUsd, 1.09);
        },
      );
    }

    test(
      '$surface APIPod uncertain submission is persisted and never resent',
      () async {
        final fixture = await _ApipodFixture.create(
          companion: companion,
          isIos: isIos,
        );
        addTearDown(fixture.dispose);
        await fixture.provider.setProviderApiKey('apipod', _key);
        fixture.failSubmission = true;
        final uncertain = await fixture.gateway.submit(_submission());
        expect(uncertain.status, submissionUnknownStatus);
        expect(uncertain.requestId, isNull);
        expect(uncertain.realizedCostUsd, isNull);
        expect(fixture.submitCount, 1);
        await fixture.restart();
        final restored = (await fixture.gateway.load()).generations.single;
        expect(restored.status, submissionUnknownStatus);
        expect(restored.canCheckStatus, isFalse);
        expect(fixture.submitCount, 1);
      },
    );
  }
}

GenerationSubmission _submission() => GenerationSubmission(
  record: Generation(
    localId: 'apipod-integration',
    provider: 'apipod',
    model: _model,
    billingUnit: 'usd',
    status: 'submitting',
    prompt: 'The camera slowly follows a fox through a forest.',
    mode: VideoMode.t2v,
    config: _config,
    createdAt: DateTime.utc(2026, 10, 30),
    updatedAt: DateTime.utc(2026, 10, 30),
  ),
  input: const {
    'mode': 't2v',
    'prompt': 'The camera slowly follows a fox through a forest.',
    'duration': 5,
    'resolution': 'hd',
    'aspect_ratio': '16:9',
    'generate_audio': true,
  },
  autoFixReferenceVideos: false,
);

GenerationSubmission _referenceSubmission(String model) {
  final references = model.endsWith('-r2v');
  final config = GenerationConfig(
    duration: 5,
    resolution: 'hd',
    generateAudio: true,
    safetyTolerance: 2,
    draft: false,
    aspectRatio: references ? '16:9' : 'auto',
    keyframes: references
        ? null
        : const [KeyframeLabel(label: 'fox', role: KeyframeRole.start)],
    references: references
        ? const [
            MediaReferenceLabel(label: 'fox', kind: MediaReferenceKind.image),
            MediaReferenceLabel(
              label: 'motion',
              kind: MediaReferenceKind.video,
              durationSeconds: 3,
            ),
            MediaReferenceLabel(
              label: 'voice',
              kind: MediaReferenceKind.audio,
              durationSeconds: 3,
            ),
          ]
        : null,
  );
  return GenerationSubmission(
    record: Generation(
      localId: 'apipod-media-integration',
      provider: 'apipod',
      model: model,
      billingUnit: 'usd',
      status: 'submitting',
      prompt: 'A fox follows the motion.',
      mode: VideoMode.i2v,
      config: config,
      createdAt: DateTime.utc(2026, 11, 5),
      updatedAt: DateTime.utc(2026, 11, 5),
    ),
    input: {
      'mode': 'i2v',
      'prompt': 'A fox follows the motion.',
      'duration': 5,
      'resolution': 'hd',
      'aspect_ratio': references ? '16:9' : 'auto',
      'generate_audio': true,
      if (references) ...{
        'reference_images': ['https://cdn.example.com/fox.png'],
        'reference_videos': ['https://cdn.example.com/motion.mp4'],
        'reference_audios': ['https://cdn.example.com/voice.mp3'],
      } else
        'keyframes': ['https://cdn.example.com/fox.png'],
    },
    autoFixReferenceVideos: true,
  );
}

GenerationSubmission _sourceSubmission({required bool finalization}) {
  final config = GenerationConfig(
    duration: 5,
    resolution: finalization ? 'fhd' : 'hd',
    generateAudio: true,
    safetyTolerance: 2,
    draft: false,
    aspectRatio: 'auto',
    sourceLabel: finalization ? 'completed-preview-task' : 'source video',
    references: finalization
        ? null
        : const [
            MediaReferenceLabel(
              label: 'reference',
              kind: MediaReferenceKind.video,
              durationSeconds: 4,
              source: AssetReference(
                kind: 'remote',
                value: 'https://cdn.example.com/reference.mp4',
                label: 'reference',
              ),
            ),
          ],
  );
  return GenerationSubmission(
    record: Generation(
      localId: 'apipod-source-integration',
      provider: 'apipod',
      model: finalization ? 'seedance-2.5-draft' : 'seedance-2.5-edit',
      billingUnit: 'usd',
      status: 'submitting',
      prompt: finalization ? '' : 'Restyle the fox using @Video 1.',
      mode: finalization ? VideoMode.draftEnhance : VideoMode.v2v,
      config: config,
      createdAt: DateTime.utc(2026, 11, 5),
      updatedAt: DateTime.utc(2026, 11, 5),
    ),
    input: finalization
        ? {
            'mode': 'draft_enhance',
            'draft_task_id': 'completed-preview-task',
            'resolution': 'fhd',
          }
        : {
            'mode': 'v2v',
            'prompt': 'Restyle the fox using @Video 1.',
            'resolution': 'hd',
            'aspect_ratio': 'auto',
            'duration': 5,
            'generate_audio': true,
            'start_video': 'https://cdn.example.com/source.mp4',
            'reference_videos': ['https://cdn.example.com/reference.mp4'],
          },
    autoFixReferenceVideos: true,
  );
}

class _UnexpectedNormalizer
    implements
        ReferenceVideoNormalizationService,
        ReferenceImageNormalizationService {
  int calls = 0;
  @override
  Future<PreparedReferenceVideos> normalize(
    List<String> sources, {
    required ReferenceVideoCompatibilityProfile profile,
  }) async {
    calls++;
    throw StateError(
      'APIPod hosted videos must not be normalized into local media.',
    );
  }

  @override
  Future<PreparedReferenceImages> normalizeImages(
    List<String> sources, {
    ReferenceImageCompatibilityProfile profile =
        const ReferenceImageCompatibilityProfile(),
  }) async {
    calls++;
    throw StateError(
      'APIPod hosted images must not be normalized into local media.',
    );
  }
}

class _ApipodFixture {
  _ApipodFixture(this.directory, this.companion, this.isIos);

  static Future<_ApipodFixture> create({
    required bool companion,
    bool isIos = false,
  }) async {
    final fixture = _ApipodFixture(
      await Directory.systemTemp.createTemp('clawnsole-apipod-integration.'),
      companion,
      isIos,
    );
    fixture.client = MockClient(fixture.handleProviderRequest);
    await fixture.open();
    return fixture;
  }

  final Directory directory;
  final bool companion;
  final bool isIos;
  final normalizer = _UnexpectedNormalizer();
  String expectedModel = _model;
  Map<String, dynamic>? submittedPayload;
  final secure = MemorySecureValueStore();
  late final http.Client client;
  late LocalDataStore local;
  late AppGateway gateway;
  NativeGateway? native;
  CompanionHybridStore? companionStore;
  HttpServer? server;
  StreamSubscription<HttpRequest>? subscription;
  http.Client? rendererClient;
  int submitCount = 0;
  int resultCount = 0;
  bool rejectSavedKey = false;
  bool failSubmission = false;
  bool includeUsage = true;
  String queueStatus = 'pending';

  ProviderGateway get provider => gateway as ProviderGateway;
  GenerationDeliveryGateway get delivery =>
      gateway as GenerationDeliveryGateway;

  Future<http.Response> handleProviderRequest(http.Request request) async {
    expect(request.url.host, 'api.apipod.ai');
    final authorization = request.headers['authorization'];
    if (request.url.path == '/v1/account/status') {
      expect(request.method, 'GET');
      if (authorization == 'Bearer invalid-candidate' || rejectSavedKey) {
        return http.Response('{"code":401,"message":"Invalid API key"}', 401);
      }
      expect(authorization, 'Bearer $_key');
      return http.Response('{"code":200,"message":"success","data":{}}', 200);
    }
    expect(authorization, 'Bearer $_key');
    if (request.method == 'POST') {
      expect(request.url.path, '/v1/videos/generations');
      final payload = jsonDecode(request.body) as Map<String, dynamic>;
      expect(payload['model'], expectedModel);
      submittedPayload = payload;
      if (payload.containsKey('draft_task_id')) {
        expect(payload.containsKey('prompt'), isFalse);
      } else {
        expect(payload['prompt'], contains('fox'));
      }
      expect(request.headers['idempotency-key'], isNotEmpty);
      final marker = (await local.read()).generations.single;
      expect(marker.status, submissionUnknownStatus);
      submitCount += 1;
      if (failSubmission) {
        return http.Response(
          '{"code":503,"message":"Upstream unavailable"}',
          503,
        );
      }
      return http.Response(
        jsonEncode({
          'code': 200,
          'message': 'success',
          'data': {'task_id': _requestId},
        }),
        200,
      );
    }
    expect(request.url.toString(), '$_queueRoot/$_requestId');
    if (queueStatus == 'completed') resultCount += 1;
    return http.Response(
      jsonEncode({
        'code': 200,
        'message': 'success',
        'data': {
          'task_id': _requestId,
          'status': queueStatus,
          'progress': queueStatus == 'completed' ? 100 : 20,
          if (queueStatus == 'completed') ...{
            'result': ['https://media.apipod.ai/fixture.mp4'],
            if (includeUsage) 'usage': {'cost': 1.09},
          },
        },
      }),
      200,
    );
  }

  Future<void> open() async {
    local = LocalDataStore(documentsDirectory: directory);
    final hybrid = HybridDataStore(local: local);
    final vault = SettingsVaultDataStore(delegate: hybrid, secureStore: secure);
    final router = ProviderApiRouter(apipod: ApipodApi(client: client));
    if (companion) {
      companionStore = CompanionHybridStore(hybrid, vault: vault);
      final app = CompanionApp.hybrid(
        store: companionStore!,
        api: BflApi(client: client),
        providerRouter: router,
        referenceVideoNormalizer: normalizer,
      );
      server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      subscription = server!.listen(app.handle);
      rendererClient = http.Client();
      gateway = WebGateway(
        baseUrl: Uri.parse('http://127.0.0.1:${server!.port}'),
        client: rendererClient,
      );
    } else {
      native = NativeGateway(
        hybridStore: hybrid,
        settingsVaultStore: vault,
        providerRouter: router,
        client: client,
        isIos: isIos,
        referenceVideoNormalizer: normalizer,
      );
      gateway = native!;
    }
  }

  Future<void> close() async {
    native?.dispose();
    native = null;
    companionStore?.dispose();
    companionStore = null;
    rendererClient?.close();
    rendererClient = null;
    await subscription?.cancel();
    subscription = null;
    await server?.close(force: true);
    server = null;
  }

  Future<void> restart() async {
    await close();
    await open();
  }

  Future<void> dispose() async {
    await close();
    client.close();
    await directory.delete(recursive: true);
  }
}
