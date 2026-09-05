import 'dart:convert';

import 'package:clawnsole/core/artcraft_api.dart';
import 'package:clawnsole/core/atlas_cloud_api.dart';
import 'package:clawnsole/core/bfl_api.dart';
import 'package:clawnsole/core/krea_api.dart';
import 'package:clawnsole/core/ltx_api.dart';
import 'package:clawnsole/core/provider_api.dart';
import 'package:clawnsole/core/runway_api.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  for (final route in [
    ('bfl', 'flux-3-video', '/v1/flux-3-video'),
    ('ltx', 'ltx-2-3-fast', '/v2/text-to-video'),
    ('artcraft', 'seedance_2p5', '/v1/omni_api/generate/video'),
    (
      'atlas',
      'bytedance/seedance-2.0-mini/text-to-video',
      '/api/v1/model/generateVideo',
    ),
    ('runway', 'veo3.1_fast', '/v1/text_to_video'),
    ('krea', 'google/veo-3.1', '/generate/video/google/veo-3.1'),
  ]) {
    test(
      '${route.$1} awaits durable intent after preparation and before POST',
      () async {
        var armed = false;
        var posts = 0;
        final client = MockClient((request) async {
          if (request.url.path == route.$3) {
            expect(armed, isTrue);
            posts += 1;
          } else {
            // Optional quotes must not yet cross the generation boundary.
            expect(armed, isFalse);
          }
          return http.Response(
            jsonEncode({
              'id': 'job-one',
              'polling_url': 'https://api.bfl.ai/v1/get_result?id=job-one',
              'job_id': 'job-one',
              'inference_job_token': 'job-one',
              'cost_in_credits': 10,
              'data': {'id': 'job-one', 'price': .10},
            }),
            200,
          );
        });
        final router = ProviderApiRouter(
          bfl: BflApi(client: client),
          ltx: LtxApi(client: client),
          artcraft: ArtCraftApi(client: client),
          atlas: AtlasCloudApi(client: client),
          runway: RunwayApi(client: client),
          krea: KreaApi(client: client),
        );
        const input = <String, Object?>{
          'prompt': 'fixture',
          'duration': 5,
          'resolution': 'hd',
          'aspect_ratio': '16:9',
        };
        final receipt = await router.submit(
          route.$1,
          'FAKE_KEY',
          route.$2,
          input,
          operationId: 'operation-one',
          beforeSend: () async {
            await Future<void>.delayed(Duration.zero);
            armed = true;
          },
        );
        expect(receipt['id'], 'job-one');
        expect(posts, 1);
        armed = false;
        await expectLater(
          router.submit(
            route.$1,
            'FAKE_KEY',
            route.$2,
            input,
            operationId: 'operation-two',
            beforeSend: () async {
              throw StateError('FAKE persistence failure');
            },
          ),
          throwsStateError,
        );
        expect(posts, 1);
      },
    );
  }

  test(
    'failed reference uploads never reach the generation POST boundary',
    () async {
      var boundaryCalls = 0;
      var uploads = 0;
      final api = KreaApi(
        client: MockClient((request) async {
          expect(request.url.path, isNot(startsWith('/generate/')));
          uploads += 1;
          return http.Response('{"message":"FAKE upload unavailable"}', 503);
        }),
      );
      await expectLater(
        api.submit(
          'FAKE_KEY',
          'bytedance/seedance-2-mini',
          {
            'prompt': 'fixture',
            'duration': 4,
            'resolution': 'hd',
            'aspect_ratio': '16:9',
            'keyframes': [
              'data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII=',
            ],
          },
          beforeSend: () async {
            boundaryCalls += 1;
          },
        ),
        throwsA(isA<ProviderException>()),
      );
      expect(uploads, 1);
      expect(boundaryCalls, 0);
    },
  );
}
