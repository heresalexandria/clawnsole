import 'dart:async';
import 'dart:io';

import 'package:clawnsole/core/bfl_api.dart';
import 'package:clawnsole/core/direct_gateway.dart';
import 'package:clawnsole/core/gateway.dart';
import 'package:clawnsole/core/krea_api.dart';
import 'package:clawnsole/core/models.dart';
import 'package:clawnsole/core/pricing.dart';
import 'package:clawnsole/core/provider_api.dart';
import 'package:clawnsole/core/provider_catalog.dart';
import 'package:clawnsole/core/web_gateway.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import '../tool/clawnsole_companion.dart';

const _config = GenerationConfig(
  aspectRatio: '16:9',
  duration: 5,
  resolution: 'hd',
  generateAudio: true,
  safetyTolerance: 2,
  draft: false,
  references: [
    MediaReferenceLabel(
      label: 'video',
      kind: MediaReferenceKind.video,
      durationSeconds: 2,
    ),
  ],
);

void main() {
  test(
    'a partial price list does not turn a variable model into a zero rate',
    () {
      final estimate = estimateCost(
        'krea',
        'bytedance/seedance-2-5',
        VideoMode.t2v,
        _config,
        [],
        [publishedProviderPrices('krea').first],
      );
      expect(estimate.isAvailable, isFalse);
      expect(estimate.quotedMinimumUsd, isNull);
      expect(estimate.quotedMaximumUsd, isNull);
    },
  );

  for (final companion in [false, true]) {
    for (final model in ['bytedance/seedance-2-5', 'minimax/hailuo-3']) {
      test(
        '${companion ? 'companion' : 'native'} persists $model pricing without losing measured duration',
        () async {
          final temporary = await Directory.systemTemp.createTemp(
            'clawnsole-price-persistence.',
          );
          final file = File('${temporary.path}/history.json');
          final store = CompanionStore(file);
          final client = MockClient((request) async {
            if (request.url.path == '/jobs') {
              return http.Response('{"jobs":[]}', 200);
            }
            expect(request.url.path, '/generate/video/$model');
            return http.Response('{"job_id":"fixture-job"}', 200);
          });
          final router = ProviderApiRouter(krea: KreaApi(client: client));
          HttpServer? server;
          StreamSubscription<HttpRequest>? listener;
          late AppGateway gateway;
          if (companion) {
            server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
            final app = CompanionApp(
              store: store,
              api: BflApi(client: client),
              providerRouter: router,
              fallbackApiKeys: {'krea': 'FAKE_KEY'},
            );
            listener = server.listen(app.handle);
            gateway = WebGateway(
              baseUrl: Uri.parse('http://127.0.0.1:${server.port}'),
            );
          } else {
            gateway = _FixtureGateway(store, router);
          }
          addTearDown(() async {
            await listener?.cancel();
            await server?.close(force: true);
            await temporary.delete(recursive: true);
          });
          final result = await gateway.submit(
            GenerationSubmission(
              record: Generation(
                localId: 'variable-fixture',
                provider: 'krea',
                model: model,
                billingUnit: 'usd',
                status: 'submitting',
                prompt: 'A slow pan.',
                mode: VideoMode.i2v,
                config: _config,
                createdAt: DateTime.utc(2026, 10, 30),
                updatedAt: DateTime.utc(2026, 10, 30),
              ),
              input: {
                'prompt': 'A slow pan.',
                'mode': 'i2v',
                'duration': 5,
                'resolution': 'hd',
                'aspect_ratio': '16:9',
                'reference_videos': ['https://example.com/reference.mp4'],
                'reference_video_duration_seconds': 2,
                'reference_video_duration_pending': 0,
              },
              autoFixReferenceVideos: false,
            ),
          );
          final persisted = StoredData.decode(
            await file.readAsString(),
          ).generations.single;
          for (final record in [result, persisted]) {
            expect(record.status, 'Pending');
            expect(record.config.references!.single.durationSeconds, 2);
            if (model == 'bytedance/seedance-2-5') {
              expect(record.quotedCostUsdMin, isNull);
              expect(record.quotedCostUsdMax, isNull);
              expect(record.estimatedCreditsMin, isNull);
              expect(record.estimatedCreditsMax, isNull);
            } else {
              expect(record.quotedCostUsdMin, .91);
              expect(record.quotedCostUsdMax, .91);
            }
            expect(record.cost, isNull);
            expect(record.realizedCostUsd, isNull);
          }
        },
      );
    }
  }
}

class _FixtureGateway extends DirectGateway {
  _FixtureGateway(CompanionStore store, ProviderApiRouter router)
    : super(store: store, providerRouter: router);
  @override
  ActiveApiKey? activeApiKey(String provider, StoredData data) =>
      const ActiveApiKey('FAKE_KEY', ApiKeySource.saved);
}
