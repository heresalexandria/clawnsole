import 'dart:convert';

import 'package:clawnsole/core/krea_api.dart';
import 'package:clawnsole/core/models.dart';
import 'package:clawnsole/core/pricing.dart';
import 'package:clawnsole/core/provider_catalog.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

GenerationConfig config({
  String resolution = 'hd',
  int duration = 5,
  bool audio = false,
  List<MediaReferenceLabel>? references,
}) => GenerationConfig(
  aspectRatio: '16:9',
  duration: duration,
  resolution: resolution,
  generateAudio: audio,
  safetyTolerance: 2,
  draft: false,
  references: references,
);

void main() {
  test(
    'new Krea routes send audited fields and upload-independent metadata',
    () async {
      final bodies = <String, Map<String, dynamic>>{};
      final api = KreaApi(
        client: MockClient((request) async {
          bodies[request.url.path] =
              jsonDecode(request.body) as Map<String, dynamic>;
          return http.Response('{"job_id":"job"}', 200);
        }),
      );
      final ids = <String>[
        'black-forest-labs/flux-3-max',
        'kling/kling-4',
        'minimax/h3-max-turbo',
        'alibaba/wan-3.0-prime',
        'google/gemini-omni-flash',
        'google/gemini-omni-flash-1.1',
        'black-forest-labs/flux-video-edit',
      ];
      for (final id in ids) {
        await api.submit('fake', id, <String, Object?>{
          'prompt': 'A crane takes flight.',
          'mode': id.endsWith('flux-video-edit') ? 'v2v' : 'i2v',
          'duration': 5,
          'resolution': 'fhd',
          'aspect_ratio': '16:9',
          'generate_audio': true,
          'seed': 42,
          'start_video': 'https://example.test/source.mp4',
          'keyframes': <String>[
            'https://example.test/first.png',
            'https://example.test/last.png',
          ],
          'reference_images': <String>['https://example.test/ref.png'],
          'reference_videos': <String>['https://example.test/ref.mp4'],
          'reference_video_duration_seconds': 2.5,
          'reference_video_duration_pending': 0,
        });
      }
      Map<String, dynamic> body(String id) => bodies['/generate/video/$id']!;
      expect(body(ids[0])['resolution'], '1080p');
      expect(body(ids[0])['seed'], 42);
      expect(body(ids[0])['end_image'], 'https://example.test/last.png');
      expect(body(ids[0]), isNot(contains('reference_images')));
      expect(
        body(ids[1]),
        containsPair('reference_videos', ['https://example.test/ref.mp4']),
      );
      expect(body(ids[1]), isNot(contains('generate_audio')));
      expect(body(ids[2])['resolution'], '1080p');
      expect(body(ids[3])['reference_video_seconds'], 2.5);
      expect(body(ids[3]), isNot(contains('reference_video_duration_seconds')));
      expect(body(ids[4]), isNot(contains('resolution')));
      expect(body(ids[5]), isNot(contains('generate_audio')));
      expect(
        body(ids[6]),
        containsPair('start_video', 'https://example.test/source.mp4'),
      );
      expect(body(ids[6]), isNot(contains('duration')));
      expect(body(ids[6]), isNot(contains('aspect_ratio')));
    },
  );

  test('all Seedance 2 routes omit the expired audio field', () async {
    final api = KreaApi(
      client: MockClient((request) async {
        expect(jsonDecode(request.body), isNot(contains('generate_audio')));
        return http.Response('{"job_id":"job"}', 200);
      }),
    );
    for (final id in [
      'bytedance/seedance-2',
      'bytedance/seedance-2-fast',
      'bytedance/seedance-2-mini',
      'bytedance/seedance-2-5',
    ]) {
      expect(modelById('krea', id).supportsAudio, isFalse);
      await api.submit('fake', id, {'prompt': 'test', 'generate_audio': true});
    }
  });

  test('current Krea prices select resolution, audio and exact duration', () {
    CostEstimate price(
      String id,
      GenerationConfig recipe, [
      VideoMode mode = VideoMode.t2v,
    ]) => estimateCost('krea', id, mode, recipe);
    expect(price('black-forest-labs/flux-3-max', config()).minimumUsd, .85);
    expect(
      price(
        'black-forest-labs/flux-3-max',
        config(resolution: 'fhd'),
      ).minimumUsd,
      1.45,
    );
    expect(price('kling/kling-4', config()).minimumUsd, .785);
    expect(
      price('minimax/h3-max-turbo', config(resolution: 'sd')).minimumUsd,
      .125,
    );
    expect(price('minimax/h3-max', config(resolution: 'fhd')).minimumUsd, .56);
    expect(
      price('alibaba/wan-3.0-prime', config(resolution: 'sd')).minimumUsd,
      .34,
    );
    expect(price('google/veo-3.1', config(duration: 4)).minimumUsd, .8);
    expect(
      price('google/veo-3.1', config(duration: 4, audio: true)).minimumUsd,
      1.6,
    );
    expect(price('minimax/hailuo-2.3', config(duration: 10)).minimumUsd, .56);
    expect(
      price(
        'minimax/hailuo-2.3',
        config(duration: 10, resolution: 'fhd'),
      ).minimumUsd,
      .49,
    );
    expect(
      price(
        'black-forest-labs/flux-3-video',
        config(resolution: '4k'),
        VideoMode.v2v,
      ).minimumUsd,
      4.75,
    );
    expect(price('runway/gen-4.5', config()).minimumUsd, .6);
    expect(price('luma/ray-2', config()).minimumUsd, .4);
  });

  test(
    'variable Krea pricing cannot become a free quote or realized charge',
    () {
      for (final id in [
        'bytedance/seedance-2-5',
        'google/gemini-omni-flash',
        'google/gemini-omni-flash-1.1',
        'black-forest-labs/flux-video-edit',
      ]) {
        final estimate = estimateCost('krea', id, VideoMode.t2v, config());
        expect(estimate.isAvailable, isFalse);
        expect(estimate.quotedMinimumUsd, isNull);
        expect(estimate.quotedMaximumUsd, isNull);
        final row = publishedProviderPrices(
          'krea',
        ).singleWhere((row) => row.model == id);
        expect(row.pricingUnit, 'variable');
        expect(row.hasPriceFor(5), isFalse);
      }
    },
  );
}
