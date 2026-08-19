import 'dart:convert';

import 'package:clawnsole/core/artcraft_api.dart';
import 'package:clawnsole/core/atlas_cloud_api.dart';
import 'package:clawnsole/core/bfl_api.dart';
import 'package:clawnsole/core/ltx_api.dart';
import 'package:clawnsole/core/models.dart';
import 'package:clawnsole/core/pricing.dart';
import 'package:clawnsole/core/provider_catalog.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  test('LTX maps canonical form values to the async API contract', () async {
    late Map<String, Object?> requestBody;
    final api = LtxApi(
      client: MockClient((request) async {
        expect(request.url.path, '/v2/text-to-video');
        expect(request.headers['authorization'], 'Bearer secret');
        requestBody = (jsonDecode(request.body) as Map<Object?, Object?>).map(
          (key, value) => MapEntry(key.toString(), value),
        );
        return http.Response(
          jsonEncode(<String, Object?>{
            'id': 'ltx-job',
            'created_at': '2026-08-17T00:00:00Z',
          }),
          202,
        );
      }),
      baseUrl: Uri.parse('https://api.ltx.io'),
    );

    final receipt = await api
        .submit('secret', 'ltx-2-3-fast', <String, Object?>{
          'mode': 't2v',
          'prompt': 'A quiet test shot',
          'duration': 6,
          'resolution': 'hd',
          'aspect_ratio': '9:16',
          'generate_audio': false,
        });

    expect(requestBody['resolution'], '720x1280');
    expect(requestBody.containsKey('aspect_ratio'), isFalse);
    expect(requestBody['generate_audio'], isFalse);
    expect(
      receipt['polling_url'],
      'https://api.ltx.io/v2/text-to-video/ltx-job',
    );
  });

  test('LTX maps first and last references to image-to-video', () async {
    late Map<String, Object?> requestBody;
    final api = LtxApi(
      client: MockClient((request) async {
        expect(request.url.path, '/v2/image-to-video');
        requestBody = (jsonDecode(request.body) as Map<Object?, Object?>).map(
          (key, value) => MapEntry(key.toString(), value),
        );
        return http.Response(
          jsonEncode(<String, String>{'id': 'ltx-i2v'}),
          202,
        );
      }),
    );

    await api.submit('secret', 'ltx-2-3-fast', <String, Object?>{
      'mode': 'i2v',
      'prompt': 'A referenced test shot',
      'duration': 6,
      'resolution': 'hd',
      'aspect_ratio': '16:9',
      'keyframes': <String>[
        'data:image/png;base64,first',
        'https://cdn.test/last.png',
      ],
    });

    expect(requestBody['image_uri'], 'data:image/png;base64,first');
    expect(requestBody['last_frame_uri'], 'https://cdn.test/last.png');
  });

  test(
    'LTX accepts an authenticated not-found response as a key probe',
    () async {
      final api = LtxApi(
        client: MockClient(
          (_) async => http.Response(
            jsonEncode(<String, Object?>{'error': 'not found'}),
            404,
          ),
        ),
      );

      final account = await api.verify('secret');
      expect(account.provider, 'ltx');
      expect(account.balance, isNull);
    },
  );

  test('LTX does not treat an upstream failure as a valid key', () async {
    final api = LtxApi(
      client: MockClient(
        (_) async => http.Response(
          jsonEncode(<String, Object?>{'error': 'service unavailable'}),
          503,
        ),
      ),
    );

    await expectLater(api.verify('secret'), throwsA(isA<ProviderException>()));
  });

  test('provider polling never forwards a key to another origin', () async {
    var requests = 0;
    final ltx = LtxApi(
      client: MockClient((_) async {
        requests += 1;
        return http.Response('{}', 200);
      }),
    );
    final atlas = AtlasCloudApi(
      client: MockClient((_) async {
        requests += 1;
        return http.Response('{}', 200);
      }),
    );
    final artcraft = ArtCraftApi(
      client: MockClient((_) async {
        requests += 1;
        return http.Response('{}', 200);
      }),
    );

    await expectLater(
      ltx.poll('secret', 'https://example.com/v2/text-to-video/job'),
      throwsA(isA<ProviderException>()),
    );
    await expectLater(
      atlas.poll('secret', 'https://example.com/api/v1/model/prediction/job'),
      throwsA(isA<ProviderException>()),
    );
    await expectLater(
      artcraft.poll(
        'secret',
        'https://example.com/v1/omni_api/job_status/job/job',
      ),
      throwsA(isA<ProviderException>()),
    );
    expect(requests, 0);
  });

  test('ArtCraft exposes every enabled live video model', () {
    expect(artCraftProvider.models.map((model) => model.id).toSet(), <String>{
      'flux_3',
      'flux_3_draft',
      'grok_imagine_video',
      'grok_imagine_video_1p5',
      'happy_horse_1p0',
      'kling_1p6_pro',
      'kling_2p5_turbo_pro',
      'kling_2p6_pro',
      'minimax_h3',
      'seedance_1p5_pro',
      'seedance_2p0',
      'seedance_2p0_fast',
      'seedance_2p0_bp',
      'seedance_2p0_bp_fast',
      'seedance_2p0_bpu',
      'seedance_2p0_bpu_fast',
      'seedance_2p0_mini',
      'seedance_2p0_bp_mini',
      'seedance_2p0_bpu_mini',
      'seedance_2p5',
      'seedance_2p5_u',
      'seedance_2p5_preview',
      'veo_3_fast',
      'veo_3p1',
      'veo_3p1_fast',
      'veo_3p1_lite',
      'vidu_q3',
      'vidu_q3_turbo',
    });
    expect(modelById('artcraft', 'seedance_2p5_preview').modes, <VideoMode>[
      VideoMode.i2v,
    ]);
    expect(modelById('artcraft', 'seedance_2p0').maxKeyframes, 11);
    expect(modelById('artcraft', 'kling_2p6_pro').supportsAudio, isTrue);
  });

  test('ArtCraft maps generation input and retains its quoted cost', () async {
    final requestBodies = <String, Map<String, Object?>>{};
    final api = ArtCraftApi(
      client: MockClient((request) async {
        final payload = (jsonDecode(request.body) as Map<Object?, Object?>).map(
          (key, value) => MapEntry(key.toString(), value),
        );
        requestBodies[request.url.path] = payload;
        if (request.url.path == '/v1/omni_gen/cost/video') {
          expect(request.headers['authorization'], isNull);
          return http.Response(
            jsonEncode(<String, Object?>{'cost_in_credits': 93}),
            200,
          );
        }
        expect(request.url.path, '/v1/omni_api/generate/video');
        expect(request.headers['authorization'], 'Bearer secret');
        return http.Response(
          jsonEncode(<String, Object?>{
            'success': true,
            'inference_job_token': 'jinf_test',
          }),
          200,
        );
      }),
    );

    final receipt = await api.submit(
      'secret',
      'seedance_2p0',
      <String, Object?>{
        'prompt': 'A continuous blue-hour tracking shot',
        'duration': 5,
        'resolution': 'fhd',
        'aspect_ratio': '16:9',
        'keyframes': <String>[
          'https://cdn.test/first.png',
          'https://cdn.test/reference.png',
          'https://cdn.test/last.png',
        ],
      },
    );

    final quote = requestBodies['/v1/omni_gen/cost/video']!;
    final generation = requestBodies['/v1/omni_api/generate/video']!;
    expect(quote.containsKey('idempotency_token'), isFalse);
    expect(generation['model'], 'seedance_2p0');
    expect(generation['duration_seconds'], 5);
    expect(generation['resolution'], 'ten_eighty_p');
    expect(generation['aspect_ratio'], 'wide_sixteen_by_nine');
    expect(generation['start_frame_image_url'], 'https://cdn.test/first.png');
    expect(generation['end_frame_image_url'], 'https://cdn.test/last.png');
    expect(generation['reference_image_urls'], <String>[
      'https://cdn.test/reference.png',
    ]);
    expect(
      generation['idempotency_token'],
      matches(
        RegExp(
          r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$',
        ),
      ),
    );
    expect(receipt['id'], 'jinf_test');
    expect(
      receipt['polling_url'],
      'https://api.storyteller.ai/v1/omni_api/job_status/job/jinf_test',
    );
    expect(receipt['cost'], 93.0);
  });

  test('ArtCraft maps a completed Omni API status response', () async {
    final api = ArtCraftApi(
      client: MockClient((request) async {
        expect(request.headers['authorization'], 'Bearer secret');
        return http.Response(
          jsonEncode(<String, Object?>{
            'state': <String, Object?>{
              'status': <String, Object?>{
                'status': 'complete_success',
                'progress_percentage': 100,
              },
              'maybe_result': <String, Object?>{
                'media': <Object?>[
                  <String, Object?>{'cdn_url': 'https://cdn.test/result.mp4'},
                ],
              },
            },
          }),
          200,
        );
      }),
    );

    final result = await api.poll(
      'secret',
      'https://api.storyteller.ai/v1/omni_api/job_status/job/jinf_test',
    );

    expect(result['status'], 'Ready');
    expect(result['progress'], 100);
    expect(result['result'], isA<Map<String, Object?>>());
  });

  test('ArtCraft live catalog filters disabled and unknown models', () async {
    final api = ArtCraftApi(
      client: MockClient(
        (_) async => http.Response(
          jsonEncode(<String, Object?>{
            'models': <Object?>[
              <String, Object?>{'model': 'flux_3', 'full_name': 'FLUX 3 Live'},
              <String, Object?>{'model': 'seedance_2p0', 'is_disabled': true},
              <String, Object?>{
                'model': 'future_model',
                'text_to_video_supported': true,
              },
            ],
          }),
          200,
        ),
      ),
    );

    final models = await api.listVideoModels();
    expect(models.map((model) => model.model), <String>[
      'flux_3',
      'future_model',
    ]);
    expect(models.first.createReady, isTrue);
    expect(models.last.createReady, isFalse);
  });

  test('ArtCraft accepts authenticated not-found as a key probe', () async {
    final api = ArtCraftApi(
      client: MockClient((request) async {
        expect(request.url.path, '/v1/omni_api/job_status/job/None');
        expect(request.headers['authorization'], 'Bearer secret');
        return http.Response('{"detail":"not found"}', 404);
      }),
    );

    final account = await api.verify('secret');
    expect(account.provider, 'artcraft');
    expect(account.balance, isNull);
  });

  test('Atlas reads live video prices and marks supported models', () async {
    final api = AtlasCloudApi(
      client: MockClient((request) async {
        if (request.url.path == '/api/v1/model/calculate') {
          final payload = jsonDecode(request.body) as Map<Object?, Object?>;
          final duration = (payload['duration'] as num).toDouble();
          return http.Response(
            jsonEncode(<String, Object?>{
              'code': 200,
              'data': <String, Object?>{'price': duration * .08},
            }),
            200,
          );
        }
        return http.Response(
          jsonEncode(<String, Object?>{
            'code': 200,
            'data': <Object?>[
              <String, Object?>{
                'model': 'bytedance/seedance-2.0-mini/text-to-video',
                'displayName': 'Seedance Mini',
                'type': 'Video',
                'categories': <String>['TEXT-TO-VIDEO'],
                'price': <String, Object?>{
                  'actual': <String, Object?>{'base_price': '0.039'},
                },
              },
              <String, Object?>{'model': 'image/not-video', 'type': 'Image'},
            ],
          }),
          200,
        );
      }),
    );

    final models = await api.listVideoModels();
    expect(models, hasLength(1));
    expect(models.single.usdPerSecond, .08);
    expect(models.single.createReady, isTrue);
    expect(models.single.modes, <VideoMode>[VideoMode.t2v]);
    expect(models.single.source, contains('preflight'));
    expect(models.single.priceFor(10), .8);
  });

  test('Atlas maps reference models to the documented reference payload', () {
    final api = AtlasCloudApi();
    final payload = api.generationPayload(
      'bytedance/seedance-2.5/reference-to-video',
      <String, Object?>{
        'prompt': 'Keep the character consistent',
        'duration': 10,
        'aspect_ratio': '16:9',
        'generate_audio': false,
        'keyframes': <String>[
          'data:image/png;base64,one',
          'data:image/png;base64,two',
        ],
      },
    );

    expect(payload['reference_images'], hasLength(2));
    expect(payload['generate_audio'], isFalse);
    expect(payload['ratio'], '16:9');
  });

  test('provider keys round-trip independently through schema 9', () {
    final encoded = const StoredData()
        .withApiKey('bfl', 'bfl-secret')
        .withApiKey('ltx', 'ltx-secret')
        .withApiKey('artcraft', 'artcraft-secret')
        .withApiKey('atlas', 'atlas-secret')
        .encode();
    final decoded = StoredData.decode(encoded);

    expect(decoded.apiKeyFor('bfl'), 'bfl-secret');
    expect(decoded.apiKeyFor('ltx'), 'ltx-secret');
    expect(decoded.apiKeyFor('artcraft'), 'artcraft-secret');
    expect(decoded.apiKeyFor('atlas'), 'atlas-secret');
    expect(decoded.toJson()['schemaVersion'], 9);
  });

  test('ArtCraft resolutions survive history serialization', () {
    for (final resolution in <String>['sd', 'fhd', 'qhd', '4k']) {
      final decoded = GenerationConfig.fromJson(<String, Object?>{
        'resolution': resolution,
      });
      expect(decoded.resolution, resolution);
    }
  });

  test('published provider pricing uses the selected tier', () {
    const config = GenerationConfig(
      aspectRatio: '16:9',
      duration: 10,
      resolution: 'fhd',
      generateAudio: true,
      safetyTolerance: 2,
      draft: false,
    );

    final ltx = estimateCost('ltx', 'ltx-2-5-fast', VideoMode.t2v, config);
    final atlas = estimateCost(
      'atlas',
      'bytedance/seedance-2.0-mini/text-to-video',
      VideoMode.t2v,
      config,
    );
    final artcraft = estimateCost(
      'artcraft',
      'seedance_2p0',
      VideoMode.t2v,
      config,
    );

    expect(ltx.minimumUsd, 1.3);
    expect(artcraft.minimumUsd, 1.86);
    expect(atlas.minimumUsd, .39);
    final ltxRows = publishedProviderPrices('ltx');
    expect(ltxRows.first.supportsDuration(15), isFalse);
    expect(ltxRows.first.supportsDuration(20), isTrue);
  });

  test('Atlas live catalog prices override the published fallback', () {
    const config = GenerationConfig(
      aspectRatio: '16:9',
      duration: 10,
      resolution: 'hd',
      generateAudio: true,
      safetyTolerance: 2,
      draft: false,
    );
    final estimate = estimateCost(
      'atlas',
      'bytedance/seedance-2.0-mini/text-to-video',
      VideoMode.t2v,
      config,
      const <Generation>[],
      const <ProviderModelPrice>[
        ProviderModelPrice(
          provider: 'atlas',
          model: 'bytedance/seedance-2.0-mini/text-to-video',
          label: 'Seedance Mini',
          usdPerSecond: .041,
          modes: <VideoMode>[VideoMode.t2v],
          source: 'atlas-live',
        ),
      ],
    );

    expect(estimate.minimumUsd, .41);
    expect(estimate.basis, 'atlas-live');
  });
}
