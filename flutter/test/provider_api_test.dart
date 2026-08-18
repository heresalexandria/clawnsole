import 'dart:convert';

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

    await expectLater(
      ltx.poll('secret', 'https://example.com/v2/text-to-video/job'),
      throwsA(isA<ProviderException>()),
    );
    await expectLater(
      atlas.poll('secret', 'https://example.com/api/v1/model/prediction/job'),
      throwsA(isA<ProviderException>()),
    );
    expect(requests, 0);
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

  test('provider keys round-trip independently through schema 7', () {
    final encoded = const StoredData()
        .withApiKey('bfl', 'bfl-secret')
        .withApiKey('ltx', 'ltx-secret')
        .withApiKey('atlas', 'atlas-secret')
        .encode();
    final decoded = StoredData.decode(encoded);

    expect(decoded.apiKeyFor('bfl'), 'bfl-secret');
    expect(decoded.apiKeyFor('ltx'), 'ltx-secret');
    expect(decoded.apiKeyFor('atlas'), 'atlas-secret');
    expect(decoded.toJson()['schemaVersion'], 8);
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

    expect(ltx.minimumUsd, 1.3);
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
