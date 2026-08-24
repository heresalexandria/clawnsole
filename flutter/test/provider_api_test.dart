import 'dart:convert';

import 'package:clawnsole/core/artcraft_api.dart';
import 'package:clawnsole/core/atlas_cloud_api.dart';
import 'package:clawnsole/core/bfl_api.dart';
import 'package:clawnsole/core/generation_status.dart';
import 'package:clawnsole/core/ltx_api.dart';
import 'package:clawnsole/core/models.dart';
import 'package:clawnsole/core/pricing.dart';
import 'package:clawnsole/core/provider_catalog.dart';
import 'package:clawnsole/core/runway_api.dart';
import 'package:clawnsole/core/reference_prompts.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  test(
    'Runway reads the organization credit balance with versioned auth',
    () async {
      final api = RunwayApi(
        client: MockClient((request) async {
          expect(request.url.path, '/v1/organization');
          expect(request.headers['authorization'], 'Bearer runway-secret');
          expect(request.headers['x-runway-version'], RunwayApi.apiVersion);
          return http.Response(
            jsonEncode(<String, Object?>{
              'creditBalance': 321.5,
              'tier': <String, Object?>{},
              'usage': <String, Object?>{},
            }),
            200,
          );
        }),
      );

      final account = await api.verify('runway-secret');
      expect(account.provider, 'runway');
      expect(account.balance, 321.5);
      expect(account.currency, 'credits');
    },
  );

  test(
    'Runway maps a cheap text generation and retains its cost ceiling',
    () async {
      late Map<String, Object?> requestBody;
      final api = RunwayApi(
        client: MockClient((request) async {
          expect(request.url.path, '/v1/text_to_video');
          requestBody = (jsonDecode(request.body) as Map<Object?, Object?>).map(
            (key, value) => MapEntry(key.toString(), value),
          );
          return http.Response(
            jsonEncode(<String, Object?>{
              'id': 'runway-task',
              'estimatedCost': <String, Object?>{'credits': 64},
            }),
            200,
          );
        }),
      );

      final receipt = await api
          .submit('runway-secret', 'seedance2_mini', <String, Object?>{
            'mode': 't2v',
            'prompt': 'A three-toed sloth files a motion. It is tabled.',
            'duration': 4,
            'resolution': 'sd',
            'aspect_ratio': '16:9',
            'generate_audio': false,
          });

      expect(requestBody['model'], 'seedance2_mini');
      expect(requestBody['duration'], 4);
      expect(requestBody['ratio'], '864:496');
      expect(requestBody['audio'], isFalse);
      expect(receipt['estimated_credits'], 64.0);
      expect(
        receipt['polling_url'],
        'https://api.dev.runwayml.com/v1/tasks/runway-task',
      );
    },
  );

  test('Runway maps pinned frames and terminal task accounting', () async {
    final requests = <String, Map<String, Object?>>{};
    final api = RunwayApi(
      client: MockClient((request) async {
        if (request.method == 'POST') {
          requests[request.url.path] =
              (jsonDecode(request.body) as Map<Object?, Object?>).map(
                (key, value) => MapEntry(key.toString(), value),
              );
          return http.Response(
            '{"id":"veo-task","estimatedCost":{"credits":60}}',
            200,
          );
        }
        return http.Response(
          jsonEncode(<String, Object?>{
            'id': 'veo-task',
            'status': 'SUCCEEDED',
            'output': <String>['https://cdn.runway.test/result.mp4'],
            'cost': <String, Object?>{'credits': 59},
          }),
          200,
        );
      }),
    );

    await api.submit('secret', 'veo3.1_fast', <String, Object?>{
      'mode': 'i2v',
      'prompt': '',
      'duration': 4,
      'resolution': 'hd',
      'aspect_ratio': '9:16',
      'generate_audio': true,
      'keyframes': <String>[
        'https://cdn.test/first.png',
        'https://cdn.test/last.png',
      ],
    });
    final generation = requests['/v1/image_to_video']!;
    expect(generation['ratio'], '720:1280');
    expect(generation['audio'], isTrue);
    expect(generation['promptImage'], <Object?>[
      <String, Object?>{
        'uri': 'https://cdn.test/first.png',
        'position': 'first',
      },
      <String, Object?>{'uri': 'https://cdn.test/last.png', 'position': 'last'},
    ]);

    final status = await api.poll(
      'secret',
      'https://api.dev.runwayml.com/v1/tasks/veo-task',
    );
    expect(status['status'], 'SUCCEEDED');
    expect(status['outputs'], <String>['https://cdn.runway.test/result.mp4']);
    expect(status['actual_cost'], 59.0);
  });

  test('Runway sends source video through multimodal video routes', () async {
    late Map<String, Object?> requestBody;
    final api = RunwayApi(
      client: MockClient((request) async {
        expect(request.url.path, '/v1/video_to_video');
        requestBody = (jsonDecode(request.body) as Map<Object?, Object?>).map(
          (key, value) => MapEntry(key.toString(), value),
        );
        return http.Response(
          '{"id":"hailuo-task","estimatedCost":{"credits":50}}',
          200,
        );
      }),
    );

    await api.submit('secret', 'hailuo3', <String, Object?>{
      'mode': 'v2v',
      'prompt': 'A sloth joins the slowcial movement.',
      'start_video': 'https://cdn.test/source.mp4',
      'duration': 5,
      'resolution': 'hd',
      'aspect_ratio': '16:9',
    });

    expect(requestBody['promptVideo'], 'https://cdn.test/source.mp4');
    expect(requestBody, isNot(contains('videoUri')));
  });

  test(
    'Runway uploads local media without forwarding API credentials',
    () async {
      late Map<String, Object?> generation;
      var storageUploadSeen = false;
      final api = RunwayApi(
        client: MockClient((request) async {
          if (request.url.path == '/v1/uploads') {
            expect(request.headers['authorization'], 'Bearer secret');
            return http.Response(
              jsonEncode(<String, Object?>{
                'uploadUrl': 'https://storage.runway.test/upload',
                'runwayUri': 'runway://ephemeral/local-image',
                'fields': <String, String>{'key': 'temporary/object'},
              }),
              200,
            );
          }
          if (request.url.host == 'storage.runway.test') {
            storageUploadSeen = true;
            expect(request.headers['authorization'], isNull);
            expect(
              request.headers['content-type'],
              startsWith('multipart/form-data'),
            );
            return http.Response('', 204);
          }
          generation = (jsonDecode(request.body) as Map<Object?, Object?>).map(
            (key, value) => MapEntry(key.toString(), value),
          );
          return http.Response(
            '{"id":"upload-task","estimatedCost":{"credits":20}}',
            200,
          );
        }),
      );

      await api.submit('secret', 'gen4_turbo', <String, Object?>{
        'mode': 'i2v',
        'prompt': 'Stillness moves quickly. Management called it agile.',
        'duration': 2,
        'resolution': 'hd',
        'aspect_ratio': '16:9',
        'keyframes': <String>['data:image/png;base64,AQID'],
      });

      expect(storageUploadSeen, isTrue);
      expect(generation['promptImage'], 'runway://ephemeral/local-image');
    },
  );

  test('Runway live guide exposes new video models as audited-pending', () async {
    final api = RunwayApi(
      client: MockClient(
        (_) async => http.Response(
          '<h2 id="generate-video">Generate Video</h2><table><tbody>'
          '<tr><td><code>seedance2_mini</code></td><td>Text</td><td>Video</td></tr>'
          '<tr><td><code>gwm1_avatars</code></td><td>Text</td><td>Video + Audio</td></tr>'
          '<tr><td><code>deadpan_future_1</code></td><td>Text</td><td>Video</td></tr>'
          '</tbody></table><h2 id="generate-image">Generate Image</h2>',
          200,
        ),
      ),
    );

    final models = await api.listVideoModels();
    final discovered = models.where(
      (model) => model.model == 'deadpan_future_1',
    );
    expect(discovered, hasLength(1));
    expect(discovered.single.createReady, isFalse);
    expect(discovered.single.pricingUnit, 'catalog-unpriced');
    final avatars = models.where((model) => model.model == 'gwm1_avatars');
    expect(avatars, hasLength(1));
    expect(avatars.single.createReady, isFalse);
    expect(avatars.single.pricingUnit, 'realtime-session');
  });

  test('BFL routes video upscale requests and sends raw base64', () async {
    late http.Request captured;
    final api = BflApi(
      client: MockClient((request) async {
        captured = request;
        return http.Response(
          jsonEncode(<String, Object?>{
            'id': 'upscale-job',
            'polling_url': 'https://api.bfl.ai/v1/get_result?id=upscale-job',
          }),
          200,
        );
      }),
    );

    final receipt = await api.submit('secret', <String, Object?>{
      'input_video': 'data:video/mp4;base64,AQID',
      'upscale_factor': 2.5,
      'creativity': 0,
      'safety_tolerance': 2,
    }, model: 'flux-tools-video-upscale-v1');
    final body = (jsonDecode(captured.body) as Map<Object?, Object?>).map(
      (key, value) => MapEntry(key.toString(), value),
    );

    expect(captured.url.path, '/v1/flux-tools/video-upscale-v1');
    expect(captured.headers['x-key'], 'secret');
    expect(body['input_video'], 'AQID');
    expect(body['upscale_factor'], 2.5);
    expect(body['creativity'], 0);
    expect(receipt['id'], 'upscale-job');
  });

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
        'keyframes': <String>[
          'https://cdn.test/opening.png',
          'https://cdn.test/closing.png',
        ],
        'reference_audios': <String>['data:audio/mpeg;base64,audio'],
      });

      expect(requestBody['audio_uri'], 'data:audio/mpeg;base64,audio');
      expect(requestBody['image_uri'], 'https://cdn.test/opening.png');
      expect(requestBody['last_frame_uri'], 'https://cdn.test/closing.png');
      expect(requestBody.containsKey('duration'), isFalse);
      expect(requestBody.containsKey('generate_audio'), isFalse);
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

  test('every create-ready model keeps its audited guidance constraints', () {
    String constraint(VideoModelDefinition model) => <Object?>[
      model.maxKeyframes,
      model.maxImageReferences,
      model.maxVideoReferences,
      model.maxAudioReferences,
      model.maxTotalReferences ?? '-',
      model.framesExclusiveWithReferences ? 'exclusive' : 'mix',
      model.requiresVisualReferenceForAudio ? 'visual' : 'audio-ok',
    ].join('/');

    const expectedArtCraft = <String, String>{
      'flux_3': '2/0/0/0/-/mix/audio-ok',
      'flux_3_draft': '2/0/0/0/-/mix/audio-ok',
      'grok_imagine_video': '1/7/0/0/-/exclusive/audio-ok',
      'grok_imagine_video_1p5': '1/0/0/0/-/mix/audio-ok',
      'happy_horse_1p0': '1/0/0/0/-/mix/audio-ok',
      'kling_1p6_pro': '2/4/0/0/-/mix/audio-ok',
      'kling_2p5_turbo_pro': '2/0/0/0/-/mix/audio-ok',
      'kling_2p6_pro': '2/0/0/0/-/mix/audio-ok',
      'minimax_h3': '2/9/3/3/12/exclusive/visual',
      'seedance_1p5_pro': '2/0/0/0/-/mix/audio-ok',
      'seedance_2p0': '2/9/3/3/-/exclusive/visual',
      'seedance_2p0_fast': '2/9/3/3/-/exclusive/visual',
      'seedance_2p0_bp': '2/9/3/3/-/exclusive/visual',
      'seedance_2p0_bp_fast': '2/9/3/3/-/exclusive/visual',
      'seedance_2p0_bpu': '2/9/3/3/-/exclusive/visual',
      'seedance_2p0_bpu_fast': '2/9/3/3/-/exclusive/visual',
      'seedance_2p0_mini': '2/9/3/3/-/exclusive/visual',
      'seedance_2p0_bp_mini': '2/9/3/3/-/exclusive/visual',
      'seedance_2p0_bpu_mini': '2/9/3/3/-/exclusive/visual',
      'seedance_2p5': '2/30/10/10/-/exclusive/audio-ok',
      'seedance_2p5_u': '2/30/10/10/-/exclusive/audio-ok',
      'seedance_2p5_preview': '0/30/10/10/-/mix/audio-ok',
      'veo_3_fast': '1/0/0/0/-/mix/audio-ok',
      'veo_3p1': '2/3/1/0/-/exclusive/audio-ok',
      'veo_3p1_fast': '2/3/1/0/-/exclusive/audio-ok',
      'veo_3p1_lite': '2/0/0/0/-/mix/audio-ok',
      'vidu_q3': '2/4/0/0/-/mix/audio-ok',
      'vidu_q3_turbo': '2/0/0/0/-/mix/audio-ok',
    };
    expect(<String, String>{
      for (final model in artCraftProvider.models) model.id: constraint(model),
    }, expectedArtCraft);

    const expectedAtlas = <String, String>{
      'bytedance/seedance-2.5/text-to-video': '0/0/0/0/-/mix/audio-ok',
      'bytedance/seedance-2.5/image-to-video': '2/0/0/0/-/mix/audio-ok',
      'bytedance/seedance-2.5/reference-to-video': '0/30/10/10/-/mix/audio-ok',
      'bytedance/seedance-2.0/text-to-video': '0/0/0/0/-/mix/audio-ok',
      'bytedance/seedance-2.0/image-to-video': '2/0/0/0/-/mix/audio-ok',
      'bytedance/seedance-2.0/reference-to-video': '0/9/3/3/-/mix/visual',
      'bytedance/seedance-2.0-fast/text-to-video': '0/0/0/0/-/mix/audio-ok',
      'bytedance/seedance-2.0-fast/image-to-video': '2/0/0/0/-/mix/audio-ok',
      'bytedance/seedance-2.0-fast/reference-to-video': '0/9/3/3/-/mix/visual',
      'bytedance/seedance-2.0-mini/text-to-video': '0/0/0/0/-/mix/audio-ok',
      'bytedance/seedance-2.0-mini/image-to-video': '2/0/0/0/-/mix/audio-ok',
      'bytedance/seedance-2.0-mini/reference-to-video': '0/9/3/3/-/mix/visual',
      'xai/grok-imagine-video-v1.5/text-to-video': '0/0/0/0/-/mix/audio-ok',
      'xai/grok-imagine-video-v1.5/image-to-video': '1/0/0/0/-/mix/audio-ok',
      'google/veo3.1-fast/text-to-video': '0/0/0/0/-/mix/audio-ok',
      'google/veo3.1-fast/image-to-video': '2/0/0/0/-/mix/audio-ok',
      'alibaba/wan-2.7/text-to-video': '0/0/0/0/-/mix/audio-ok',
      'alibaba/wan-2.7/image-to-video': '2/0/0/0/-/mix/audio-ok',
      'kwaivgi/kling-v3.0-pro/text-to-video': '0/0/0/0/-/mix/audio-ok',
      'kwaivgi/kling-v3.0-pro/image-to-video': '2/0/0/0/-/mix/audio-ok',
      'vidu/q3-turbo/text-to-video': '0/0/0/0/-/mix/audio-ok',
      'vidu/q3-turbo/image-to-video': '1/0/0/0/-/mix/audio-ok',
      'pixverse/v6/text-to-video': '0/0/0/0/-/mix/audio-ok',
      'pixverse/v6/image-to-video': '1/0/0/0/-/mix/audio-ok',
      'minimax/hailuo-2.3/t2v-standard': '0/0/0/0/-/mix/audio-ok',
      'minimax/hailuo-2.3/i2v-standard': '1/0/0/0/-/mix/audio-ok',
      'black-forest-labs/flux-3/text-to-video': '0/0/0/0/-/mix/audio-ok',
      'black-forest-labs/flux-3/image-to-video': '1/0/0/0/-/mix/audio-ok',
    };
    expect(<String, String>{
      for (final model in atlasProvider.models) model.id: constraint(model),
    }, expectedAtlas);

    expect(constraint(bflProvider.defaultModel), '10/0/0/0/-/mix/audio-ok');
    expect(
      <String, String>{
        for (final model in ltxProvider.models) model.id: constraint(model),
      },
      <String, String>{
        'ltx-2-3-fast': '2/0/0/0/-/mix/audio-ok',
        'ltx-2-3-pro': '2/0/0/1/-/mix/audio-ok',
      },
    );
    expect(
      <String, String>{
        for (final model in runwayProvider.models) model.id: constraint(model),
      },
      <String, String>{
        'seedance2_5': '2/30/10/10/-/exclusive/audio-ok',
        'grok_imagine_1_5': '1/7/0/1/8/exclusive/visual',
        'seedance2': '2/9/3/3/-/exclusive/audio-ok',
        'seedance2_fast': '2/9/3/3/-/exclusive/audio-ok',
        'seedance2_mini': '2/9/3/3/-/exclusive/audio-ok',
        'hailuo3': '1/9/3/3/12/exclusive/audio-ok',
        'aleph2': '5/0/0/0/-/mix/audio-ok',
        'gen4.5': '1/0/0/0/-/mix/audio-ok',
        'gen4_turbo': '1/0/0/0/-/mix/audio-ok',
        'act_two': '0/1/1/0/1/mix/audio-ok',
        'veo3.1': '2/0/0/0/-/mix/audio-ok',
        'veo3.1_fast': '2/0/0/0/-/mix/audio-ok',
        'happyhorse_1_0': '1/0/0/0/-/mix/audio-ok',
        'gemini_omni_flash': '1/5/0/0/-/exclusive/audio-ok',
        'magnific_video_upscaler_creative': '0/0/0/0/-/mix/audio-ok',
      },
    );
    expect(
      <String, int?>{
        for (final model in runwayProvider.models)
          model.id: model.maxPromptCharacters,
      },
      <String, int?>{
        'seedance2_5': 15000,
        'grok_imagine_1_5': null,
        'seedance2': 3500,
        'seedance2_fast': 3500,
        'seedance2_mini': 3500,
        'hailuo3': null,
        'aleph2': null,
        'gen4.5': 1000,
        'gen4_turbo': 1000,
        'act_two': null,
        'veo3.1': 1000,
        'veo3.1_fast': 1000,
        'happyhorse_1_0': 2500,
        'gemini_omni_flash': null,
        'magnific_video_upscaler_creative': null,
      },
    );
    expect(
      modelById(
        'runway',
        'gemini_omni_flash',
      ).maxReferences(MediaReferenceKind.image, VideoMode.i2v),
      1,
    );
    expect(
      modelById(
        'runway',
        'gemini_omni_flash',
      ).maxReferences(MediaReferenceKind.image, VideoMode.v2v),
      5,
    );
    expect(modelById('runway', 'seedance2').maxKeyframesFor(VideoMode.v2v), 0);
    expect(
      modelById('runway', 'gen4.5').aspectRatiosFor('hd', mode: VideoMode.t2v),
      <String>['16:9', '9:16'],
    );
    expect(
      modelById(
        'runway',
        'grok_imagine_1_5',
      ).aspectRatiosFor('hd', mode: VideoMode.i2v),
      <String>['auto'],
    );

    final grok = modelById('artcraft', 'grok_imagine_video');
    expect(
      grok.durationRangeFor('hd', withImageGuidance: true).maximumSeconds,
      10,
    );
    expect(
      modelById(
        'artcraft',
        'seedance_2p5',
      ).aspectRatiosFor('hd', withFrames: true),
      <String>['auto'],
    );
    expect(
      modelById('atlas', 'bytedance/seedance-2.5/image-to-video').aspectRatios,
      <String>['auto'],
    );
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
    'ArtCraft Seedance 2.5 keeps pinned frames separate from creative images',
    () async {
      final generations = <Map<String, Object?>>[];
      final api = ArtCraftApi(
        client: MockClient((request) async {
          if (request.url.path == '/v1/omni_gen/cost/video') {
            return http.Response('{"cost_in_credits":10}', 200);
          }
          generations.add(
            (jsonDecode(request.body) as Map<Object?, Object?>).map(
              (key, value) => MapEntry(key.toString(), value),
            ),
          );
          return http.Response(
            '{"inference_job_token":"jinf_seedance_2p5"}',
            200,
          );
        }),
      );

      await api.submit('secret', 'seedance_2p5', <String, Object?>{
        'prompt': 'Animate from the supplied first frame.',
        'duration': 10,
        'resolution': 'hd',
        'aspect_ratio': 'auto',
        'keyframes': <String>['https://cdn.test/first.png'],
      });
      await api.submit('secret', 'seedance_2p5', <String, Object?>{
        'prompt': 'Keep @Image 1 consistent.',
        'duration': 10,
        'resolution': 'hd',
        'aspect_ratio': '9:16',
        'reference_images': <String>['https://cdn.test/creative.png'],
      });

      expect(
        generations.first['start_frame_image_url'],
        'https://cdn.test/first.png',
      );
      expect(generations.first, isNot(contains('reference_image_urls')));
      expect(generations.last, isNot(contains('start_frame_image_url')));
      expect(generations.last['reference_image_urls'], <String>[
        'https://cdn.test/creative.png',
      ]);
      expect(generations.last['prompt'], 'Keep @image1 consistent.');
    },
  );

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
    expect(result['progress'], isNull);
    expect(result['result'], isA<Map<String, Object?>>());
  });

  test(
    'ArtCraft does not promote its binary percentage while a job is running',
    () async {
      final api = ArtCraftApi(
        client: MockClient(
          (_) async => http.Response(
            jsonEncode(<String, Object?>{
              'state': <String, Object?>{
                'status': <String, Object?>{
                  'status': 'started',
                  'progressPercentage': '0%',
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
      expect(result['progress'], isNull);
      expect(findProviderProgress(result), 0);
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

  test('Atlas maps stable and custom reference names by attachment order', () {
    final payload = AtlasCloudApi().generationPayload(
      'bytedance/seedance-2.5/reference-to-video',
      <String, Object?>{
        'prompt': 'Track @Video 2, then cut to @Alexandria. Ignore @Video 1.',
        'duration': 10,
        'aspect_ratio': '16:9',
        'resolution': 'hd',
        'reference_videos': <String>[
          'https://cdn.test/first.mp4',
          'https://cdn.test/second.mp4',
        ],
        referencePromptNamesInputKey: <String, List<String>>{
          'video': <String>['Video 2', 'Alexandria'],
        },
      },
    );

    expect(
      payload['prompt'],
      'Track @video1, then cut to @video2. Ignore @Video 1.',
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

  test('schema 20 strips provider keys while legacy files still decode', () {
    final encoded = const StoredData()
        .withApiKey('bfl', 'bfl-secret')
        .withApiKey('ltx', 'ltx-secret')
        .withApiKey('artcraft', 'artcraft-secret')
        .withApiKey('atlas', 'atlas-secret')
        .encode();
    final decoded = StoredData.decode(encoded);

    expect(encoded, isNot(contains('secret')));
    expect(decoded.apiKeys, isEmpty);
    expect(decoded.toJson()['schemaVersion'], 22);
    final legacy = StoredData.decode(
      '{"schemaVersion":16,"apiKeys":{"bfl":"old-bfl","ltx":"old-ltx"},"generations":[]}',
    );
    expect(legacy.apiKeyFor('bfl'), 'old-bfl');
    expect(legacy.apiKeyFor('ltx'), 'old-ltx');
  });

  test('ArtCraft resolutions survive history serialization', () {
    for (final resolution in <String>['sd', 'fhd', 'qhd', '4k']) {
      final decoded = GenerationConfig.fromJson(<String, Object?>{
        'resolution': resolution,
      });
      expect(decoded.resolution, resolution);
    }
  });

  test('video upscale settings and published rates survive history', () {
    const config = GenerationConfig(
      aspectRatio: 'auto',
      duration: 'source',
      resolution: 'source',
      generateAudio: false,
      safetyTolerance: 3,
      draft: false,
      upscaleFactor: 2.5,
      upscaleCreativity: 0,
    );
    final decoded = GenerationConfig.fromJson(config.toJson());
    final precise = estimateCost(
      'bfl',
      'flux-tools-video-upscale-v1',
      VideoMode.upscale,
      config,
    );
    final creative = estimateCost(
      'bfl',
      'flux-tools-video-upscale-v1',
      VideoMode.upscale,
      config.copyWith(upscaleCreativity: 1),
    );
    const source = VideoSourceMetadata(
      width: 1920,
      height: 1080,
      durationSeconds: 10,
    );
    final inputPrecise = estimateCost(
      'bfl',
      'flux-tools-video-upscale-v1',
      VideoMode.upscale,
      config,
      const <Generation>[],
      const <ProviderModelPrice>[],
      source,
    );
    final inputCreative = estimateCost(
      'bfl',
      'flux-tools-video-upscale-v1',
      VideoMode.upscale,
      config.copyWith(upscaleCreativity: 1),
      const <Generation>[],
      const <ProviderModelPrice>[],
      source,
    );

    expect(decoded.resolution, 'source');
    expect(decoded.duration, 'source');
    expect(decoded.upscaleFactor, 2.5);
    expect(decoded.upscaleCreativity, 0);
    expect(precise.maximumUsd, 19.25);
    expect(precise.providerUnitsMaximum, 1925);
    expect(creative.maximumUsd, 27.5);
    expect(inputPrecise.minimumUsd, closeTo(8.652, .000001));
    expect(inputPrecise.maximumUsd, closeTo(8.652, .000001));
    expect(inputPrecise.rateUsd, .07);
    expect(inputPrecise.rateUnit, 'megapixel-second');
    expect(inputPrecise.calculation, contains('1920×1080 × 2.5×'));
    expect(inputCreative.minimumUsd, 12.36);
    expect(inputCreative.maximumUsd, 12.36);
    expect(inputCreative.rateUsd, .10);
    expect(modelById('bfl', 'flux-tools-video-upscale-v1').modes, <VideoMode>[
      VideoMode.upscale,
    ]);
  });

  test('measured reference duration survives compact history', () {
    const reference = MediaReferenceLabel(
      label: 'Ten seconds of deliberate ambience',
      kind: MediaReferenceKind.audio,
      durationSeconds: 10.25,
    );

    final decoded = MediaReferenceLabel.fromJson(reference.toJson());

    expect(decoded.label, reference.label);
    expect(decoded.kind, reference.kind);
    expect(decoded.durationSeconds, 10.25);
  });

  test('every provider route exposes an input-derived estimate and rate', () {
    for (final provider in videoProviders) {
      for (final model in provider.models) {
        for (final mode in model.modes) {
          final upscale = mode == VideoMode.upscale;
          final estimate = estimateCost(
            provider.id,
            model.id,
            mode,
            GenerationConfig(
              aspectRatio: model.aspectRatios.first,
              duration: upscale ? 'source' : model.minDuration,
              resolution: model.resolutions.first.id,
              generateAudio: model.supportsAudio,
              safetyTolerance: 2,
              draft: false,
            ),
            const <Generation>[],
            publishedProviderPrices(provider.id),
            upscale
                ? const VideoSourceMetadata(
                    width: 1280,
                    height: 720,
                    durationSeconds: 6,
                  )
                : null,
          );

          expect(
            estimate.minimumUsd.isFinite && estimate.minimumUsd >= 0,
            isTrue,
            reason: '${provider.id}/${model.id}/${mode.name}',
          );
          expect(
            estimate.maximumUsd >= estimate.minimumUsd,
            isTrue,
            reason: '${provider.id}/${model.id}/${mode.name}',
          );
          expect(
            estimate.rateUsd,
            isNotNull,
            reason: '${provider.id}/${model.id}/${mode.name}',
          );
          expect(
            estimate.calculation,
            isNotEmpty,
            reason: '${provider.id}/${model.id}/${mode.name}',
          );
        }
      }
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

  test('Runway estimate includes known Seedance input-video credits', () {
    const config = GenerationConfig(
      aspectRatio: '16:9',
      duration: 4,
      resolution: 'sd',
      generateAudio: false,
      safetyTolerance: 2,
      draft: false,
    );

    final estimate = estimateCost(
      'runway',
      'seedance2_5',
      VideoMode.v2v,
      config,
      const <Generation>[],
      publishedProviderPrices('runway'),
      const VideoSourceMetadata(width: 864, height: 496, durationSeconds: 10),
    );

    expect(estimate.minimumUsd, 1.8);
    expect(estimate.maximumUsd, 1.8);
    expect(estimate.providerUnitsMinimum, 180);
    expect(estimate.calculation, contains('100.0 known input credits'));
    expect(estimate.basis, contains('provider receipt settles'));
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
      isTrue,
    );
    expect(ltxPro.maxReferenceSeconds(MediaReferenceKind.audio, 'fhd'), 20);
    expect(ltxPro.maxReferenceSeconds(MediaReferenceKind.audio, '4k'), 10);
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
      expect(wan['seed'], -1);
      expect(wan, isNot(contains('generate_audio')));

      final seededWan = api.generationPayload(
        'alibaba/wan-2.7/text-to-video',
        <String, Object?>{...common, 'seed': 424242},
      );
      expect(seededWan['seed'], 424242);

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

  test('recorded spend counts settled charges only', () {
    final now = DateTime.utc(2026, 8, 20);
    const config = GenerationConfig(
      aspectRatio: '16:9',
      duration: 10,
      resolution: 'hd',
      generateAudio: true,
      safetyTolerance: 2,
      draft: false,
    );
    Generation build({
      required String status,
      double? realizedCostUsd,
      String? realizedCostSource,
      double? cost,
    }) => Generation(
      localId: 'spend-$status-${realizedCostSource ?? 'none'}',
      provider: 'atlas',
      billingUnit: 'usd',
      status: status,
      prompt: 'Spend accounting',
      mode: VideoMode.t2v,
      config: config,
      createdAt: now,
      updatedAt: now,
      realizedCostUsd: realizedCostUsd,
      realizedCostSource: realizedCostSource,
      cost: cost,
    );

    // In-flight work is not settled, even with a submit-time observation.
    expect(
      countsTowardSpend(
        build(
          status: 'Pending',
          realizedCostUsd: 1.2,
          realizedCostSource: 'balance-delta',
          cost: 1.2,
        ),
      ),
      isFalse,
    );
    expect(countsTowardSpend(build(status: 'submitting')), isFalse);
    expect(countsTowardSpend(build(status: 'Unknown')), isFalse);

    // Delivered generations always count, whatever recorded the cost.
    expect(
      countsTowardSpend(
        build(
          status: 'Ready',
          realizedCostUsd: 1.2,
          realizedCostSource: 'balance-delta',
        ),
      ),
      isTrue,
    );
    expect(countsTowardSpend(build(status: 'Ready', cost: 1.2)), isTrue);

    // Failures with only a submit-time observation are commonly refunded.
    for (final status in generationFailureStatuses) {
      expect(
        countsTowardSpend(
          build(
            status: status,
            realizedCostUsd: 1.2,
            realizedCostSource: 'balance-delta',
            cost: 1.2,
          ),
        ),
        isFalse,
        reason: '$status with a submit-time cost must not count',
      );
    }
    expect(
      countsTowardSpend(
        build(
          status: 'Error',
          realizedCostUsd: 1.2,
          realizedCostSource: 'provider-reported',
          cost: 1.2,
        ),
      ),
      isFalse,
    );

    // Failures whose terminal poll confirmed the charge count.
    expect(
      countsTowardSpend(
        build(
          status: 'Failed',
          realizedCostUsd: 1.2,
          realizedCostSource: terminalReportedCostSource,
          cost: 1.2,
        ),
      ),
      isTrue,
    );
    expect(
      countsTowardSpend(
        build(
          status: 'Error',
          realizedCostUsd: 1.2,
          realizedCostSource: terminalBalanceDeltaCostSource,
          cost: 1.2,
        ),
      ),
      isTrue,
    );
  });

  test('terminal polls settle the realized cost and mark its source', () {
    final now = DateTime.utc(2026, 8, 20);
    const config = GenerationConfig(
      aspectRatio: '16:9',
      duration: 10,
      resolution: 'hd',
      generateAudio: true,
      safetyTolerance: 2,
      draft: false,
    );
    final submitted = Generation(
      localId: 'terminal-settle',
      provider: 'atlas',
      billingUnit: 'usd',
      status: 'Pending',
      prompt: 'Terminal settlement',
      mode: VideoMode.t2v,
      config: config,
      createdAt: now,
      updatedAt: now,
      creditsBefore: 10,
      cost: 1.5,
      realizedCostUsd: 1.5,
      realizedCostSource: 'balance-delta',
    );

    final reported = resolveProviderCost(submitted, <String, Object?>{
      'status': 'Failed',
      'actual_cost': .8,
    }, terminal: true);
    expect(reported.usd, .8);
    expect(reported.source, terminalReportedCostSource);

    final measured = resolveProviderCost(
      submitted,
      <String, Object?>{'status': 'Failed'},
      balanceAfter: 8.5,
      terminal: true,
    );
    expect(measured.usd, 1.5);
    expect(measured.source, terminalBalanceDeltaCostSource);

    // A refunded failure leaves only the submit-time observation, which the
    // spend accounting then excludes.
    final refunded = resolveProviderCost(
      submitted,
      <String, Object?>{'status': 'Failed'},
      balanceAfter: 10,
      terminal: true,
    );
    expect(refunded.usd, 1.5);
    expect(refunded.source, 'balance-delta');

    // Non-terminal polls keep the submit-time source untouched.
    final pending = resolveProviderCost(submitted, <String, Object?>{
      'status': 'Pending',
    });
    expect(pending.source, 'balance-delta');
  });
}
