import 'dart:convert';
import 'dart:io';

import 'package:clawnsole/core/artcraft_api.dart';
import 'package:clawnsole/core/bfl_api.dart';
import 'package:clawnsole/core/provider_catalog.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  test(
    'Wan models share current capabilities and fallback prices with Pages',
    () {
      for (final variant in ['', '_prime']) {
        final model = modelById('artcraft', 'wan_3p0$variant');
        final manifest =
            jsonDecode(
                  File(
                    '../docs/models/models/artcraft/wan-3p0${variant.replaceAll('_', '-')}.yaml',
                  ).readAsStringSync(),
                )
                as Map<String, dynamic>;
        expect(model.maxCombinedVideoSeconds, 30);
        expect(model.maxPromptCharacters, 20000);
        expect(model.usdPerSecond, manifest['usd_per_second']);
        expect(
          model.maxCombinedVideoSeconds,
          manifest['max_combined_video_seconds'],
        );
        expect(manifest['availability'], {'min_version': '0.61.0'});
      }
    },
  );

  test(
    'Seedance 2.5 estimates price measured video inputs from published rates',
    () async {
      final api = ArtCraftApi(
        client: MockClient((request) async {
          fail(
            'The public endpoint cannot price URL references without media tokens.',
          );
        }),
      );
      final estimate = await api.estimate('seedance_2p5', {
        'duration': 5,
        'resolution': 'hd',
        'reference_video_duration_seconds': 12.55,
        'reference_video_duration_pending': 0,
      });
      expect(estimate?.minimumUsd, 2.86);
      expect(estimate?.maximumUsd, 2.86);
      expect(estimate?.basis, 'artcraft-published-reference-rate');
    },
  );

  test(
    'unknown billable input durations produce a bounded published range',
    () async {
      final api = ArtCraftApi(
        client: MockClient((request) async {
          fail('A quote cannot measure an unuploaded reference video.');
        }),
      );
      final estimate = await api.estimate('seedance_2p5_u', {
        'duration': 5,
        'reference_video_duration_pending': 1,
      });
      expect(estimate?.minimumUsd, 1.69);
      expect(estimate?.maximumUsd, 6.56);
      expect(estimate?.basis, 'artcraft-published-reference-duration-range');
    },
  );

  test(
    'reference pricing retains resolution tiers and rounds up once',
    () async {
      final api = ArtCraftApi(
        client: MockClient((request) async {
          fail('Use published reference pricing before upload.');
        }),
      );
      for (final fixture in <(String, String, int, double)>[
        ('seedance_2p0', 'hd', 5, 1.11),
        ('seedance_2p0', '4k', 5, 5.69),
        ('seedance_2p0_fast', 'sd', 5, .43),
        ('seedance_2p0_bp', 'fhd', 5, 2.89),
        ('seedance_2p0_bpu_fast', 'hd', 5, 1.03),
        ('seedance_2p0_mini', 'sd', 5, .22),
        ('seedance_2p0_bp_mini', 'hd', 5, .55),
        ('seedance_2p5', 'fhd', 10, 7.70),
        ('seedance_2p5_u', 'fhd', 10, 8.37),
      ]) {
        final estimate = await api.estimate(fixture.$1, {
          'duration': fixture.$3,
          'resolution': fixture.$2,
          'reference_video_duration_seconds': 10,
        });
        expect(
          estimate?.minimumUsd,
          fixture.$4,
          reason: '${fixture.$1}/${fixture.$2}',
        );
      }
    },
  );

  test(
    'URL reference estimates are never attached as provider receipt charges',
    () async {
      final api = ArtCraftApi(
        client: MockClient((request) async {
          expect(request.url.path, '/v1/omni_api/generate/video');
          return http.Response('{"inference_job_token":"jinf_reference"}', 200);
        }),
      );
      final receipt = await api.submit('key', 'seedance_2p5', {
        'duration': 5,
        'reference_videos': ['https://example.com/reference.mp4'],
        'reference_video_duration_seconds': 12.55,
      });
      expect(receipt.containsKey('cost'), isFalse);
    },
  );

  test(
    'uploaded video quotes preserve fractional-second billing boundaries',
    () async {
      final api = ArtCraftApi(
        client: MockClient((request) async {
          if (request.url.path == '/v1/omni_api/upload/video') {
            return http.Response('{"media_file_token":"m_fixture"}', 200);
          }
          final payload = jsonDecode(request.body) as Map<String, dynamic>;
          expect(payload['reference_video_media_tokens'], ['m_fixture']);
          if (request.url.path == '/v1/omni_gen/cost/video') {
            expect(payload['estimate_only'], {
              'total_input_video_duration_millis': 4001,
            });
            return http.Response('{"cost_in_credits":159}', 200);
          }
          expect(payload.containsKey('estimate_only'), isFalse);
          return http.Response('{"inference_job_token":"jinf_uploaded"}', 200);
        }),
      );
      final receipt = await api.submit('key', 'seedance_2p5', {
        'duration': 5,
        'reference_videos': ['data:video/mp4;base64,AA=='],
        'reference_video_duration_seconds': 4.0004,
      });
      expect(receipt['cost'], 159);
      expect(receipt['cost_source'], 'provider-quote');
    },
  );

  test(
    'Wan submits pinned frames, resolution, and audio through Omni API',
    () async {
      final api = ArtCraftApi(
        client: MockClient((request) async {
          final payload = jsonDecode(request.body) as Map<String, dynamic>;
          expect(payload['model'], 'wan_3p0_prime');
          expect(
            payload['start_frame_image_url'],
            'https://example.com/start.png',
          );
          expect(payload['end_frame_image_url'], 'https://example.com/end.png');
          expect(payload['resolution'], 'ten_eighty_p');
          expect(payload['generate_audio'], false);
          if (request.url.path == '/v1/omni_gen/cost/video') {
            return http.Response(
              '{"cost_in_credits":188,"cost_in_usd_cents":188}',
              200,
            );
          }
          expect(request.url.path, '/v1/omni_api/generate/video');
          expect(payload.containsKey('estimate_only'), isFalse);
          return http.Response('{"inference_job_token":"jinf_wan"}', 200);
        }),
      );
      final receipt = await api.submit('key', 'wan_3p0_prime', {
        'duration': 5,
        'resolution': 'fhd',
        'aspect_ratio': '16:9',
        'generate_audio': false,
        'keyframes': [
          'https://example.com/start.png',
          'https://example.com/end.png',
        ],
      });
      expect(receipt['cost'], 188);
    },
  );

  test(
    'Wan rejects combined video duration before any provider request',
    () async {
      final api = ArtCraftApi(
        client: MockClient((request) async {
          fail('Over-budget media must not reach the provider.');
        }),
      );
      await expectLater(
        api.submit('key', 'wan_3p0', {
          'duration': 20,
          'reference_video_duration_seconds': 10.01,
        }),
        throwsA(
          isA<ProviderException>().having(
            (error) => error.status,
            'status',
            400,
          ),
        ),
      );
    },
  );
}
