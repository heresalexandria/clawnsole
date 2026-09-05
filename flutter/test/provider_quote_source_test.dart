import 'dart:convert';

import 'package:clawnsole/core/artcraft_api.dart';
import 'package:clawnsole/core/atlas_cloud_api.dart';
import 'package:clawnsole/core/pricing.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  for (final provider in ['artcraft', 'atlas']) {
    for (final actual in [false, true]) {
      test(
        '$provider ${actual ? 'preserves task cost instead of substituting' : 'labels'} advisory quote',
        () async {
          final client = MockClient((request) async {
            if (request.url.path == '/v1/omni_gen/cost/video') {
              return http.Response('{"cost_in_credits":90}', 200);
            }
            if (request.url.path == '/api/v1/model/calculate') {
              return http.Response('{"data":{"price":0.9}}', 200);
            }
            final payload = <String, Object?>{
              'id': 'job-one',
              'inference_job_token': 'job-one',
              if (actual) 'cost': .25,
            };
            return http.Response(
              jsonEncode(provider == 'artcraft' ? payload : {'data': payload}),
              200,
            );
          });
          const input = <String, Object?>{
            'prompt': 'fixture',
            'duration': 5,
            'resolution': 'hd',
            'aspect_ratio': '16:9',
          };
          final receipt = provider == 'artcraft'
              ? await ArtCraftApi(
                  client: client,
                ).submit('FAKE_KEY', 'seedance_2p5', input)
              : await AtlasCloudApi(client: client).submit(
                  'FAKE_KEY',
                  'bytedance/seedance-2.0-mini/text-to-video',
                  input,
                );
          if (actual) {
            expect(providerCostFromPayload(receipt), .25);
            expect(receipt['cost_source'], isNot('provider-quote'));
          } else {
            expect(
              providerCostFromPayload(receipt),
              provider == 'artcraft' ? 90 : .9,
            );
            expect(receipt['cost_source'], 'provider-quote');
          }
        },
      );
    }
  }
}
