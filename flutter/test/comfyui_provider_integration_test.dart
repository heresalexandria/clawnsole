import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:clawnsole/app/app_controller.dart';
import 'package:clawnsole/core/bfl_api.dart';
import 'package:clawnsole/core/comfyui_api.dart';
import 'package:clawnsole/core/comfyui_settings.dart';
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

import '../tool/clawnsole_companion.dart';
import 'comfyui_api_test.dart' show workflowJson;

void main() {
  for (final companion in [false, true]) {
    test(
      '${companion ? 'companion' : 'native'} ComfyUI resumes original server and retains HTTP output',
      () async {
        final fixture = await _Fixture.create(companion);
        addTearDown(fixture.dispose);
        final initial = await fixture.gateway.load();
        expect(initial.availableProviders, contains('comfyui'));
        expect(initial.connectedProviders, isNot(contains('comfyui')));
        final settings = ComfyUiSettings(
          serverUrl: fixture.serverUrl,
          workflows: {
            'comfyui-video': const ComfyUiWorkflow(
              json: workflowJson,
              outputNodeId: '9',
            ),
          },
        );
        final account = await (fixture.gateway as ProviderConfigurationGateway)
            .verifyProviderConfiguration('comfyui', settings.toJson());
        expect(account.provider, 'comfyui');
        final saved = await fixture.gateway.setPreferences(
          initial.preferences.copyWith(
            providerConfigurations: {'comfyui': settings.toJson()},
          ),
        );
        expect(saved.connectedProviders, contains('comfyui'));
        expect((await fixture.local.read()).apiKeys, isEmpty);

        final now = DateTime.utc(2026, 11, 17);
        final pending = await fixture.gateway.submit(
          GenerationSubmission(
            record: Generation(
              localId: 'comfyui-integration',
              provider: 'comfyui',
              model: 'comfyui-video',
              status: 'submitting',
              prompt: 'A fox walks through the forest.',
              mode: VideoMode.t2v,
              config: const GenerationConfig(
                aspectRatio: '16:9',
                duration: 5,
                resolution: 'hd',
                generateAudio: false,
                safetyTolerance: 2,
                draft: false,
              ),
              createdAt: now,
              updatedAt: now,
            ),
            input: const {
              'prompt': 'A fox walks through the forest.',
              'duration': 5,
              'resolution': 'hd',
              'aspect_ratio': '16:9',
            },
            autoFixReferenceVideos: false,
          ),
        );
        expect(pending.status, 'Pending');
        expect(pending.requestId, 'job-1');
        expect(fixture.submissions, 1);
        expect(jsonEncode(pending.toJson()), isNot(contains('class_type')));
        // Editing the server/graph must not redirect an accepted job or send it
        // twice. Only its original compact receipt is used after restart.
        await fixture.gateway.setPreferences(
          saved.preferences.copyWith(
            providerConfigurations: {
              'comfyui': ComfyUiSettings(
                serverUrl: 'http://different-machine.invalid:8188',
                workflows: settings.workflows,
              ).toJson(),
            },
          ),
        );
        await fixture.restart();
        var generation = (await fixture.gateway.load()).generations.single;
        expect(generation.pollingUrl, pending.pollingUrl);
        final delivery = fixture.gateway as GenerationDeliveryGateway;
        generation = await delivery.pollStatus(generation);
        expect(generation.isWorking, isTrue);
        fixture.completed = true;
        generation = await delivery.pollStatus(generation);
        expect(generation.status, 'Ready');
        expect(generation.resultUrl, startsWith('${fixture.serverUrl}/view?'));
        expect(generation.resultAsset, isNull);

        final controller = AppController(gateway: fixture.gateway);
        expect(await controller.generationMediaUri(generation), isNull);
        expect(await controller.generationPreviewSourceUri(generation), isNull);
        await expectLater(
          controller.saveMedia(generation),
          throwsA(
            isA<StateError>().having(
              (error) => error.message,
              'actionable state',
              contains('still saving'),
            ),
          ),
        );
        if (!companion) {
          final sharing = NativeGateway(
            hybridStore: HybridDataStore(local: fixture.local),
            isIos: true,
          );
          try {
            await expectLater(
              sharing.shareMedia(generation),
              throwsA(
                isA<StateError>().having(
                  (error) => error.message,
                  'actionable state',
                  contains('still saving'),
                ),
              ),
            );
          } finally {
            sharing.dispose();
          }
        }
        expect(fixture.downloads, 0);
        controller.dispose();

        generation = await delivery.retainResult(generation);
        expect(
          generation.resultAsset,
          isNotNull,
          reason: generation.resultRetentionError,
        );
        expect(
          await fixture.gateway.readAsset(generation.resultAsset!),
          _Fixture.videoBytes,
        );
        expect(fixture.downloads, 1);
        expect(fixture.submissions, 1);
        await fixture.restart();
        final restored = (await fixture.gateway.load()).generations.single;
        expect(restored.resultAsset, isNotNull);
        expect(
          await fixture.gateway.readAsset(restored.resultAsset!),
          _Fixture.videoBytes,
        );
        if (companion) {
          final file = File.fromUri(
            await fixture.local.assetUri(restored.resultAsset!),
          );
          await file.delete();
          await expectLater(
            fixture.gateway.readAsset(restored.resultAsset!),
            throwsA(
              isA<ProviderException>().having(
                (error) => error.status,
                'missing asset',
                404,
              ),
            ),
          );
          expect(
            fixture.downloads,
            1,
            reason:
                'A missing local asset must not proxy private /view through the public-media route.',
          );
        }
      },
    );
  }
}

class _Fixture {
  _Fixture(this.directory, this.companion);
  final Directory directory;
  final bool companion;
  final secure = MemorySecureValueStore();
  final providerClient = http.Client();
  late HttpServer providerServer;
  StreamSubscription<HttpRequest>? providerSubscription;
  late LocalDataStore local;
  late AppGateway gateway;
  NativeGateway? native;
  CompanionHybridStore? companionStore;
  HttpServer? companionServer;
  StreamSubscription<HttpRequest>? companionSubscription;
  http.Client? rendererClient;
  int submissions = 0;
  int downloads = 0;
  bool completed = false;
  String get serverUrl => 'http://127.0.0.1:${providerServer.port}';
  static final videoBytes = <int>[
    0,
    0,
    0,
    24,
    ...ascii.encode('ftypmp42'),
    ...List<int>.filled(24, 0),
  ];

  static Future<_Fixture> create(bool companion) async {
    final fixture = _Fixture(
      await Directory.systemTemp.createTemp('comfyui-integration.'),
      companion,
    );
    fixture.providerServer = await HttpServer.bind(
      InternetAddress.loopbackIPv4,
      0,
    );
    fixture.providerSubscription = fixture.providerServer.listen(
      fixture.handle,
    );
    await fixture.open();
    return fixture;
  }

  Future<void> handle(HttpRequest request) async {
    Object body;
    switch (request.uri.path) {
      case '/system_stats':
        body = {
          'system': {'os': 'test'},
          'devices': [],
        };
      case '/prompt':
        final graph =
            (jsonDecode(await utf8.decoder.bind(request).join())
                as Map)['prompt'];
        expect(graph['6']['inputs']['text'], contains('fox'));
        expect(
          (await local.read()).generations.single.status,
          submissionUnknownStatus,
        );
        submissions++;
        body = {'prompt_id': 'job-1', 'number': 1};
      case '/history/job-1':
        body = completed
            ? {
                'job-1': {
                  'status': {'status_str': 'success', 'completed': true},
                  'outputs': {
                    '9': {
                      'images': [
                        {
                          'filename': 'film.mp4',
                          'subfolder': '',
                          'type': 'output',
                        },
                      ],
                      'animated': [true],
                    },
                  },
                },
              }
            : {};
      case '/queue':
        body = {
          'queue_running': [
            [1, 'job-1'],
          ],
          'queue_pending': [],
        };
      case '/view':
        expect(request.uri.queryParameters['filename'], 'film.mp4');
        downloads++;
        request.response.headers.contentType = ContentType('video', 'mp4');
        request.response.add(videoBytes);
        await request.response.close();
        return;
      default:
        request.response.statusCode = 404;
        body = {'error': 'Unexpected request'};
    }
    request.response.headers.contentType = ContentType.json;
    request.response.write(jsonEncode(body));
    await request.response.close();
  }

  Future<void> open() async {
    local = LocalDataStore(documentsDirectory: directory);
    final hybrid = HybridDataStore(local: local);
    final vault = SettingsVaultDataStore(delegate: hybrid, secureStore: secure);
    final router = ProviderApiRouter(
      comfyui: ComfyUiApi(client: providerClient),
    );
    if (companion) {
      companionStore = CompanionHybridStore(hybrid, vault: vault);
      final app = CompanionApp.hybrid(
        store: companionStore!,
        api: BflApi(),
        providerRouter: router,
      );
      companionServer = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      companionSubscription = companionServer!.listen(app.handle);
      rendererClient = http.Client();
      gateway = WebGateway(
        baseUrl: Uri.parse('http://127.0.0.1:${companionServer!.port}'),
        client: rendererClient,
      );
    } else {
      native = NativeGateway(
        hybridStore: hybrid,
        settingsVaultStore: vault,
        providerRouter: router,
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
    await companionSubscription?.cancel();
    companionSubscription = null;
    await companionServer?.close(force: true);
    companionServer = null;
  }

  Future<void> restart() async {
    await close();
    await open();
  }

  Future<void> dispose() async {
    await close();
    providerClient.close();
    await providerSubscription?.cancel();
    await providerServer.close(force: true);
    await directory.delete(recursive: true);
  }
}
