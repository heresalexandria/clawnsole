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
    'LTX Pro maps audio guidance and an optional frame to audio-to-video',
    () async {
      late Map<String, Object?> requestBody;
      final api = LtxApi(
        client: MockClient((request) async {
          expect(request.url.path, '/v2/audio-to-video');
          requestBody = (jsonDecode(request.body) as Map<Object?, Object?>).map(
            (key, value) => MapEntry(key.toString(), value),
          );
          return http.Response(
            jsonEncode(<String, String>{'id': 'ltx-a2v'}),
            202,
          );
        }),
      );

      await api.submit('secret', 'ltx-2-3-pro', <String, Object?>{
        'mode': 'i2v',
        'prompt': 'Cut the scene to @Audio 1',
        'duration': 8,
        'resolution': 'fhd',
        'aspect_ratio': '16:9',
        'keyframes': <String>['https://cdn.test/opening.png'],
        'reference_audios': <String>['data:audio/mpeg;base64,audio'],
      });

      expect(requestBody['audio_uri'], 'data:audio/mpeg;base64,audio');
      expect(requestBody['image_uri'], 'https://cdn.test/opening.png');
      expect(requestBody['prompt'], 'Cut the scene to audio 1');
    },
  );

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
    final seedance = modelById('artcraft', 'seedance_2p0');
    expect(seedance.maxKeyframes, 2);
    expect(seedance.maxImageReferences, 9);
    expect(seedance.maxVideoReferences, 3);
    expect(seedance.maxAudioReferences, 3);
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

  test(
    'ArtCraft forwards independent image, video, and audio references',
    () async {
      late Map<String, Object?> generation;
      final api = ArtCraftApi(
        client: MockClient((request) async {
          if (request.url.path == '/v1/omni_gen/cost/video') {
            return http.Response('{"cost_in_credits": 10}', 200);
          }
          generation = (jsonDecode(request.body) as Map<Object?, Object?>).map(
            (key, value) => MapEntry(key.toString(), value),
          );
          return http.Response(
            '{"inference_job_token":"jinf_references"}',
            200,
          );
        }),
      );

      await api.submit('secret', 'seedance_2p0', <String, Object?>{
        'prompt': 'Use @Image 1, motion from @Video1, and @Audio 1',
        'duration': 5,
        'resolution': 'hd',
        'aspect_ratio': '16:9',
        'reference_images': <String>['https://cdn.test/character.png'],
        'reference_videos': <String>['https://cdn.test/motion.mp4'],
        'reference_audios': <String>['https://cdn.test/voice.mp3'],
      });

      expect(generation['reference_image_urls'], <String>[
        'https://cdn.test/character.png',
      ]);
      expect(generation['reference_video_urls'], <String>[
        'https://cdn.test/motion.mp4',
      ]);
      expect(generation['reference_audio_urls'], <String>[
        'https://cdn.test/voice.mp3',
      ]);
      expect(
        generation['prompt'],
        'Use @image1, motion from @video1, and @audio1',
      );
    },
  );

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

  test(
    'ArtCraft maps nested percentage strings while a job is running',
    () async {
      final api = ArtCraftApi(
        client: MockClient(
          (_) async => http.Response(
            jsonEncode(<String, Object?>{
              'state': <String, Object?>{
                'status': <String, Object?>{
                  'status': 'started',
                  'progressPercentage': '37.5%',
                },
              },
            }),
            200,
          ),
        ),
      );

      final result = await api.poll(
        'secret',
        'https://api.storyteller.ai/v1/omni_api/job_status/job/jinf_test',
      );

      expect(result['status'], 'Pending');
      expect(result['progress'], 37.5);
    },
  );

  test('normalizes provider progress across response shapes', () {
    expect(normalizedProgress(.42), 42);
    expect(normalizedProgress('1%'), 1);
    expect(normalizedProgress('42.5%'), 42.5);
    expect(
      findProviderProgress(<String, Object?>{
        'state': <String, Object?>{
          'status': <String, Object?>{'progress': '0.73'},
        },
      }),
      73,
    );
    expect(
      findProviderProgress(<String, Object?>{
        'state': <String, Object?>{
          'status': <String, Object?>{'progress_percentage': 1},
        },
      }),
      1,
    );
    expect(
      findProviderProgress(<String, Object?>{
        'discount_percentage': 80,
        'duration': 10,
      }),
      isNull,
    );
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

  test(
    'ArtCraft accepts authenticated not-found as an API key probe',
    () async {
      final api = ArtCraftApi(
        client: MockClient((request) async {
          expect(request.url.path, '/v1/omni_api/job_status/job/None');
          expect(request.headers['authorization'], 'Bearer secret');
          return http.Response('{"success":false}', 404);
        }),
      );

      final account = await api.verify('secret');
      expect(account.provider, 'artcraft');
      expect(account.balance, isNull);
      expect(account.currency, 'credits');
      expect(account.balanceLabel, 'Open ArtCraft to view balance ↗');
    },
  );

  test('ArtCraft rejects an unauthorized API key probe', () async {
    final api = ArtCraftApi(
      client: MockClient((request) async {
        expect(request.url.path, '/v1/omni_api/job_status/job/None');
        return http.Response('{"success":false}', 401);
      }),
    );

    await expectLater(
      api.verify('invalid'),
      throwsA(
        isA<ProviderException>()
            .having((error) => error.status, 'status', 401)
            .having(
              (error) => error.message,
              'message',
              'ArtCraft rejected this API key.',
            ),
      ),
    );
  });

  test('ArtCraft returns its exact resolution-aware cost quote', () async {
    late Map<String, Object?> requestBody;
    final api = ArtCraftApi(
      client: MockClient((request) async {
        expect(request.url.path, '/v1/omni_gen/cost/video');
        expect(request.headers['authorization'], isNull);
        requestBody = (jsonDecode(request.body) as Map<Object?, Object?>).map(
          (key, value) => MapEntry(key.toString(), value),
        );
        return http.Response(
          '{"success":true,"cost_in_credits":466,'
          '"cost_in_usd_cents":466}',
          200,
        );
      }),
    );

    final estimate = await api.estimate('seedance_2p0', <String, Object?>{
      'prompt': 'A precise quote',
      'duration': 10,
      'resolution': 'fhd',
      'aspect_ratio': '16:9',
      'generate_audio': true,
    });

    expect(requestBody['duration_seconds'], 10);
    expect(requestBody['resolution'], 'ten_eighty_p');
    expect(requestBody['aspect_ratio'], 'wide_sixteen_by_nine');
    expect(estimate?.minimumUsd, 4.66);
    expect(estimate?.providerUnitsMinimum, 466);
    expect(estimate?.basis, 'artcraft-live-quote');
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

  test('Atlas maps every supported reference kind and selected quality', () {
    final api = AtlasCloudApi();
    final payload = api.generationPayload(
      'bytedance/seedance-2.5/reference-to-video',
      <String, Object?>{
        'prompt': 'Keep @Image 2 consistent with @Video 1 and @Audio1',
        'duration': 10,
        'aspect_ratio': '16:9',
        'generate_audio': false,
        'resolution': 'fhd',
        'reference_task': 'extend',
        'reference_images': <String>[
          'data:image/png;base64,one',
          'data:image/png;base64,two',
        ],
        'reference_videos': <String>['https://cdn.test/motion.mp4'],
        'reference_audios': <String>['data:audio/mpeg;base64,audio'],
      },
    );

    expect(payload['reference_images'], hasLength(2));
    expect(payload['reference_videos'], <String>[
      'https://cdn.test/motion.mp4',
    ]);
    expect(payload['reference_audios'], <String>[
      'data:audio/mpeg;base64,audio',
    ]);
    expect(payload['generate_audio'], isFalse);
    expect(payload['ratio'], '16:9');
    expect(payload['resolution'], '1080p');
    expect(payload['omni_reference_task_type'], 'extend');
    expect(
      payload['prompt'],
      'Keep @image2 consistent with @video1 and @audio1',
    );
  });

  test('Atlas records the exact accepted route quote on submission', () async {
    final api = AtlasCloudApi(
      client: MockClient((request) async {
        final payload = jsonDecode(request.body) as Map<Object?, Object?>;
        expect(payload['model'], 'kwaivgi/kling-v3.0-pro/text-to-video');
        expect(payload['sound'], isTrue);
        if (request.url.path == '/api/v1/model/calculate') {
          return http.Response('{"code":200,"data":{"price":"0.714"}}', 200);
        }
        return http.Response('{"data":{"id":"kling-job"}}', 200);
      }),
    );

    final receipt = await api.submit(
      'secret',
      'kwaivgi/kling-v3.0-pro/text-to-video',
      <String, Object?>{
        'prompt': 'A cinematic reveal',
        'duration': 5,
        'resolution': 'fhd',
        'aspect_ratio': '16:9',
        'generate_audio': true,
      },
    );

    expect(receipt['cost'], .714);
    expect(receipt['cost_unit'], 'usd');
  });

  test(
    'Atlas uploads local video and audio references before generation',
    () async {
      var uploads = 0;
      late Map<String, Object?> generation;
      final api = AtlasCloudApi(
        client: MockClient((request) async {
          if (request.url.path == '/api/v1/model/uploadMedia') {
            uploads += 1;
            return http.Response(
              jsonEncode(<String, Object?>{
                'url': 'https://storage.atlascloud.ai/ref-$uploads',
              }),
              200,
            );
          }
          generation = (jsonDecode(request.body) as Map<Object?, Object?>).map(
            (key, value) => MapEntry(key.toString(), value),
          );
          return http.Response(
            jsonEncode(<String, Object?>{
              'data': <String, Object?>{'id': 'atlas-job'},
            }),
            200,
          );
        }),
      );

      await api.submit(
        'secret',
        'bytedance/seedance-2.5/reference-to-video',
        <String, Object?>{
          'prompt': 'Follow the references',
          'duration': 8,
          'reference_videos': <String>['data:video/mp4;base64,dmlkZW8='],
          'reference_audios': <String>['data:audio/mpeg;base64,YXVkaW8='],
        },
      );

      expect(uploads, 2);
      expect(generation['reference_videos'], <String>[
        'https://storage.atlascloud.ai/ref-1',
      ]);
      expect(generation['reference_audios'], <String>[
        'https://storage.atlascloud.ai/ref-2',
      ]);
    },
  );

  test('provider keys round-trip independently through schema 14', () {
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
    expect(decoded.toJson()['schemaVersion'], 14);
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

    final ltx = estimateCost('ltx', 'ltx-2-3-fast', VideoMode.t2v, config);
    final ltxHd = estimateCost(
      'ltx',
      'ltx-2-3-fast',
      VideoMode.t2v,
      const GenerationConfig(
        aspectRatio: '16:9',
        duration: 10,
        resolution: 'hd',
        generateAudio: true,
        safetyTolerance: 2,
        draft: false,
      ),
    );
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

    expect(ltx.minimumUsd, .6);
    expect(ltxHd.minimumUsd, .3);
    expect(artcraft.minimumUsd, 1.86);
    expect(artcraft.providerUnitsMinimum, 186);
    expect(artcraft.providerUnitLabel, 'credits');
    expect(atlas.minimumUsd, .39);
    final ltxRows = publishedProviderPrices('ltx');
    expect(ltxRows.first.model, 'ltx-2-3-fast:720p');
    expect(ltxRows.first.priceFor(10), .3);
    expect(ltxRows.first.supportsDuration(15), isFalse);
    expect(ltxRows.first.supportsDuration(20), isTrue);
  });

  test('catalog applies resolution-dependent provider capabilities', () {
    final ltxFast = modelById('ltx', 'ltx-2-3-fast');
    final ltxPro = modelById('ltx', 'ltx-2-3-pro');
    final seedance4k = modelById(
      'atlas',
      'bytedance/seedance-2.0/reference-to-video',
    );

    expect(ltxFast.resolutions.map((item) => item.id), <String>[
      'hd',
      'fhd',
      'qhd',
      '4k',
    ]);
    expect(ltxFast.maxDurationFor('fhd'), 20);
    expect(ltxFast.maxDurationFor('qhd'), 10);
    expect(seedance4k.aspectRatiosFor('4k'), <String>['16:9']);
    expect(
      ltxPro.supportsResolutionForReferences('fhd', <MediaReferenceKind>[
        MediaReferenceKind.audio,
      ]),
      isTrue,
    );
    expect(
      ltxPro.supportsResolutionForReferences('4k', <MediaReferenceKind>[
        MediaReferenceKind.audio,
      ]),
      isFalse,
    );
  });

  test('LTX audio-to-video uses the dedicated published rate', () {
    const config = GenerationConfig(
      aspectRatio: '16:9',
      duration: 10,
      resolution: 'fhd',
      generateAudio: true,
      safetyTolerance: 2,
      draft: false,
      references: <MediaReferenceLabel>[
        MediaReferenceLabel(label: 'Dialogue', kind: MediaReferenceKind.audio),
      ],
    );

    final estimate = estimateCost('ltx', 'ltx-2-3-pro', VideoMode.i2v, config);
    expect(estimate.minimumUsd, 1);
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

  test('provider selector order and canonical routes are stable', () {
    final names = videoProviders.map((provider) => provider.name).toList();
    expect(names, List<String>.from(names)..sort());

    expect(modelById('bfl', 'flux-3-video').canonicalId, 'flux-3');
    expect(modelById('artcraft', 'flux_3').canonicalId, 'flux-3');
    expect(
      modelById('atlas', 'black-forest-labs/flux-3/text-to-video').canonicalId,
      'flux-3',
    );
    expect(
      modelById('artcraft', 'veo_3p1_fast').canonicalId,
      modelById('atlas', 'google/veo3.1-fast/text-to-video').canonicalId,
    );
  });

  test(
    'Atlas uses each model family schema instead of one generic payload',
    () {
      final api = AtlasCloudApi();
      const common = <String, Object?>{
        'prompt': 'Animate this',
        'duration': 6,
        'resolution': 'fhd',
        'aspect_ratio': '9:16',
        'generate_audio': true,
        'keyframes': <String>['first', 'last'],
      };

      final grok = api.generationPayload(
        'xai/grok-imagine-video-v1.5/image-to-video',
        common,
      );
      expect(grok['image_url'], 'first');
      expect(grok['aspect_ratio'], '9:16');
      expect(grok, isNot(contains('ratio')));

      final wan = api.generationPayload(
        'alibaba/wan-2.7/text-to-video',
        common,
      );
      expect(wan['resolution'], '1080P');
      expect(wan['ratio'], '9:16');
      expect(wan, isNot(contains('generate_audio')));

      final veo = api.generationPayload(
        'google/veo3.1-fast/image-to-video',
        common,
      );
      expect(veo['image'], 'first');
      expect(veo['last_image'], 'last');

      final kling = api.generationPayload(
        'kwaivgi/kling-v3.0-pro/image-to-video',
        common,
      );
      expect(kling['end_image'], 'last');
      expect(kling['sound'], isTrue);
      expect(kling, isNot(contains('aspect_ratio')));

      final vidu = api.generationPayload(
        'vidu/q3-turbo/text-to-video',
        <String, Object?>{...common, 'resolution': 'sd'},
      );
      expect(vidu['resolution'], '540p');
      expect(vidu['style'], 'general');

      final pixverse = api.generationPayload(
        'pixverse/v6/text-to-video',
        common,
      );
      expect(pixverse['quality'], '1080p');
      expect(pixverse['sound'], isTrue);
      expect(pixverse, isNot(contains('resolution')));

      final hailuo = api.generationPayload(
        'minimax/hailuo-2.3/t2v-standard',
        common,
      );
      expect(hailuo['enable_prompt_expansion'], isTrue);
      expect(hailuo, isNot(contains('resolution')));

      final flux = api.generationPayload(
        'black-forest-labs/flux-3/image-to-video',
        common,
      );
      expect(flux['image_url'], 'first');
      expect(flux['resolution'], '1080p');
    },
  );

  test('realized costs persist and compare with their route quote', () {
    final now = DateTime.utc(2026, 8, 19);
    const config = GenerationConfig(
      aspectRatio: '16:9',
      duration: 10,
      resolution: 'hd',
      generateAudio: true,
      safetyTolerance: 2,
      draft: false,
    );
    final generation = Generation(
      localId: 'cost-route',
      provider: 'atlas',
      model: 'black-forest-labs/flux-3/text-to-video',
      canonicalModelId: 'flux-3',
      billingUnit: 'usd',
      status: 'Ready',
      prompt: 'A route quote',
      mode: VideoMode.t2v,
      config: config,
      createdAt: now,
      updatedAt: now,
      quotedCostUsdMin: 1.70,
      quotedCostUsdMax: 1.70,
      realizedCostUsd: 1.75,
      realizedCostSource: 'provider-reported',
      cost: 1.75,
    );
    final decoded = Generation.fromJson(generation.toJson());
    expect(decoded.canonicalModelId, 'flux-3');
    expect(decoded.realizedCostUsd, 1.75);
    expect(decoded.realizedCostSource, 'provider-reported');

    const route = ProviderModelPrice(
      provider: 'atlas',
      model: 'black-forest-labs/flux-3/text-to-video',
      canonicalModelId: 'flux-3',
      label: 'FLUX 3 · Text',
      usdPerSecond: .17,
      modes: <VideoMode>[VideoMode.t2v],
    );
    final observation = routeCostObservation(route, <Generation>[decoded]);
    expect(observation?.realizedUsd, 1.75);
    expect(observation?.quotedUsd, 1.70);
    expect(observation?.variancePercent, closeTo(2.941, .001));
  });
}
