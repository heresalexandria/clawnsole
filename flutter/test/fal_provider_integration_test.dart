import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:clawnsole/core/bfl_api.dart';
import 'package:clawnsole/core/fal_api.dart';
import 'package:clawnsole/core/gateway.dart';
import 'package:clawnsole/core/generation_status.dart';
import 'package:clawnsole/core/hybrid_data_store.dart';
import 'package:clawnsole/core/local_data_store_io.dart';
import 'package:clawnsole/core/models.dart';
import 'package:clawnsole/core/native_gateway.dart';
import 'package:clawnsole/core/provider_api.dart';
import 'package:clawnsole/core/secure_value_store.dart';
import 'package:clawnsole/core/settings_vault_data_store.dart';
import 'package:clawnsole/core/web_gateway.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import '../tool/clawnsole_companion.dart';

const _model = 'blackforestlabs/flux-3-max/text-to-video';
const _queueRoot = 'https://queue.fal.run/blackforestlabs/flux-3-max';
const _requestId = 'fal-integration-request';
const _key = 'fixture-id:fixture-secret';
const _config = GenerationConfig(
  aspectRatio: '16:9',
  duration: 5,
  resolution: 'hd',
  generateAudio: true,
  safetyTolerance: 2,
  draft: false,
);

void main() {
  for (final companion in [false, true]) {
    final surface = companion ? 'companion' : 'native';

    test('$surface FAL keys and queue receipts survive restart', () async {
      final fixture = await _FalFixture.create(companion: companion);
      addTearDown(fixture.dispose);
      final provider = fixture.provider;
      final initial = await fixture.gateway.load();
      expect(initial.availableProviders, contains('fal'));
      expect(initial.hasApiKeyFor('fal'), isFalse);

      await provider.setProviderApiKey('bfl', 'unrelated-key');
      final saved = await provider.setProviderApiKey('fal', '  $_key  ');
      expect(saved.hasApiKeyFor('fal'), isTrue);
      expect((await provider.verifyProviderKey('fal')).provider, 'fal');
      expect((await provider.getProviderAccount('fal')).balance, isNull);
      await expectLater(
        provider.verifyProviderKey('fal', 'invalid-candidate'),
        throwsA(isA<ProviderException>()),
      );
      expect((await fixture.gateway.load()).hasApiKeyFor('fal'), isTrue);

      final pending = await fixture.gateway.submit(_submission());
      expect(pending.provider, 'fal');
      expect(pending.model, _model);
      expect(pending.billingUnit, 'usd');
      expect(pending.status, 'Pending');
      expect(pending.requestId, _requestId);
      expect(pending.pollingUrl, '$_queueRoot/requests/$_requestId/status');
      expect(pending.quotedCostUsdMin, .85);
      expect(pending.quotedCostUsdMax, .85);
      expect(pending.realizedCostUsd, isNull);
      expect(fixture.submitCount, 1);

      // A fresh gateway/server and settings vault must recover both the
      // credential and accepted receipt without submitting another job.
      await fixture.restart();
      final restored = await fixture.gateway.load();
      expect(restored.hasApiKeyFor('fal'), isTrue);
      var generation = restored.generations.single;
      expect(generation.requestId, _requestId);
      expect(generation.pollingUrl, pending.pollingUrl);
      generation = await fixture.delivery.pollStatus(generation);
      expect(generation.status, 'Pending');
      expect(generation.isWorking, isTrue);
      fixture.queueStatus = 'IN_PROGRESS';
      generation = await fixture.delivery.pollStatus(generation);
      expect(generation.status, 'Pending');
      fixture.queueStatus = 'COMPLETED';
      generation = await fixture.delivery.pollStatus(generation);
      expect(generation.status, 'Ready');
      expect(generation.resultUrl, 'https://v3.fal.media/files/fixture.mp4');
      expect(generation.resultAsset, isNull);
      expect(generation.quotedCostUsdMin, .85);
      expect(generation.quotedCostUsdMax, .85);
      expect(generation.realizedCostUsd, isNull);
      expect(generation.cost, isNull);
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
      expect(completed.quotedCostUsdMin, .85);
      expect(completed.realizedCostUsd, isNull);
      expect(completed.cost, isNull);
      expect(fixture.submitCount, 1);

      // Testing a rejected candidate never erases the saved key. A saved
      // credential rejected by the provider is removed on both surfaces.
      fixture.rejectSavedKey = true;
      await expectLater(
        fixture.provider.verifyProviderKey('fal'),
        throwsA(isA<ProviderException>()),
      );
      final rejected = await fixture.gateway.load();
      expect(rejected.hasApiKeyFor('fal'), isFalse);
      expect(rejected.hasApiKeyFor('bfl'), isTrue);
      await fixture.restart();
      expect((await fixture.gateway.load()).hasApiKeyFor('fal'), isFalse);
    });

    test(
      '$surface FAL uncertain submission is persisted and never resent',
      () async {
        final fixture = await _FalFixture.create(companion: companion);
        addTearDown(fixture.dispose);
        await fixture.provider.setProviderApiKey('fal', _key);
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
    localId: 'fal-integration',
    provider: 'fal',
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

class _FalFixture {
  _FalFixture(this.directory, this.companion);

  static Future<_FalFixture> create({required bool companion}) async {
    final fixture = _FalFixture(
      await Directory.systemTemp.createTemp('clawnsole-fal-integration.'),
      companion,
    );
    fixture.client = MockClient(fixture.handleProviderRequest);
    await fixture.open();
    return fixture;
  }

  final Directory directory;
  final bool companion;
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
  String queueStatus = 'IN_QUEUE';

  ProviderGateway get provider => gateway as ProviderGateway;
  GenerationDeliveryGateway get delivery =>
      gateway as GenerationDeliveryGateway;

  Future<http.Response> handleProviderRequest(http.Request request) async {
    final authorization = request.headers['authorization'];
    if (request.url.host == 'api.fal.ai') {
      expect(request.method, 'GET');
      expect(request.url.path, '/v1/models/requests/by-endpoint');
      expect(request.url.queryParameters['endpoint_id'], _model);
      if (authorization == 'Key invalid-candidate' || rejectSavedKey) {
        return http.Response('{"detail":"Invalid API key"}', 401);
      }
      expect(authorization, 'Key $_key');
      return http.Response('{"requests":[]}', 200);
    }
    expect(request.url.host, 'queue.fal.run');
    expect(authorization, 'Key $_key');
    if (request.method == 'POST') {
      expect(request.url.path, '/$_model');
      final payload = jsonDecode(request.body) as Map<String, dynamic>;
      expect(payload['prompt'], contains('fox'));
      // The durable marker must precede the chargeable queue POST.
      final marker = (await local.read()).generations.single;
      expect(marker.status, submissionUnknownStatus);
      submitCount += 1;
      if (failSubmission) {
        return http.Response('{"detail":"Upstream unavailable"}', 503);
      }
      return http.Response(
        jsonEncode({
          'request_id': _requestId,
          'status': 'IN_QUEUE',
          'status_url': '$_queueRoot/requests/$_requestId/status',
          'response_url': '$_queueRoot/requests/$_requestId',
          'cancel_url': '$_queueRoot/requests/$_requestId/cancel',
          'queue_position': 1,
        }),
        200,
      );
    }
    if (request.url.path.endsWith('/status')) {
      return http.Response(
        jsonEncode({
          'status': queueStatus,
          'request_id': _requestId,
          'response_url': '$_queueRoot/requests/$_requestId',
        }),
        200,
      );
    }
    expect(request.url.toString(), '$_queueRoot/requests/$_requestId');
    resultCount += 1;
    return http.Response(
      '{"video":{"url":"https://v3.fal.media/files/fixture.mp4",'
      '"content_type":"video/mp4"}}',
      200,
    );
  }

  Future<void> open() async {
    local = LocalDataStore(documentsDirectory: directory);
    final hybrid = HybridDataStore(local: local);
    final vault = SettingsVaultDataStore(delegate: hybrid, secureStore: secure);
    final router = ProviderApiRouter(fal: FalApi(client: client));
    if (companion) {
      companionStore = CompanionHybridStore(hybrid, vault: vault);
      final app = CompanionApp.hybrid(
        store: companionStore!,
        api: BflApi(client: client),
        providerRouter: router,
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
        isIos: false,
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
