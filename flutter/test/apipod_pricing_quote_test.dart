import 'dart:convert';

import 'package:clawnsole/core/apipod_api.dart';
import 'package:clawnsole/core/apipod_pricing.dart';
import 'package:clawnsole/core/models.dart';
import 'package:clawnsole/core/provider_api.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

Map<String, Object?> _input() => {
  'mode': 't2v',
  'duration': 5,
  'resolution': 'hd',
  'generate_audio': false,
};

http.Response _quote(
  Object? price, {
  String currency = 'USD',
  int code = 200,
}) => http.Response(
  jsonEncode({
    'code': code,
    'data': {'price': price, 'currency': currency},
  }),
  200,
);

void main() {
  test(
    'router quotes the resolved route without credentials or content',
    () async {
      final api = ApipodApi(
        client: MockClient((request) async {
          expect(request.method, 'POST');
          expect(
            request.url.toString(),
            'https://api.apipod.ai/v1/pricing/estimate',
          );
          expect(request.followRedirects, isFalse);
          expect(request.headers.containsKey('Authorization'), isFalse);
          expect(jsonDecode(request.body), {
            'model_id': 'seedance-2.5-i2v',
            'dimensions': {
              'duration': '5',
              'resolution': '720p',
              'generate_audio': 'false',
            },
          });
          return _quote(1.1025);
        }),
      );
      final result = await ProviderApiRouter(apipod: api).quote(
        'apipod',
        'seedance-2.5',
        {
          ..._input(),
          'mode': 'i2v',
          'keyframe_count': 1,
          'prompt': 'Private direction must not be sent for a price.',
          'keyframes': ['file:///private/frame.png'],
          'api_key': 'never-transmit-this',
        },
      );
      expect(result!.minimumUsd, 1.1025);
      expect(result.maximumUsd, 1.1025);
      expect(result.rateUsd, closeTo(.2205, 1e-8));
      expect(result.basis, 'apipod-live-quote');
      expect(result.calculation, 'Seedance 2.5 · 5 s output');
    },
  );

  test(
    'video references use per-video ceiling, without forwarding URLs',
    () async {
      final api = ApipodApi(
        client: MockClient((request) async {
          expect(jsonDecode(request.body), {
            'model_id': 'seedance-2.5-r2v',
            'dimensions': {
              'duration': '17',
              'resolution': '480p',
              'generate_audio': 'false',
              'video_count': '2',
            },
            'has_video_material': true,
          });
          return _quote(.9996);
        }),
      );
      final result = await api.estimate('seedance-2.5', {
        ..._input(),
        'mode': 'i2v',
        'resolution': 'sd',
        'reference_types': ['video', 'video'],
        'reference_video_durations_seconds': [4.0417, 6.0417],
        'reference_video_duration_seconds': 10.0834,
        'reference_video_duration_pending': 0,
        'reference_videos': ['asset:private-one', 'file:///private/two.mp4'],
      });
      expect(result!.minimumUsd, .9996);
      expect(result.rateUsd, closeTo(.0588, 1e-8));
      expect(
        result.calculation,
        'Seedance 2.5 · 5 s output + 12 s input video (each rounded up) = 17 billable seconds',
      );
    },
  );

  test('source-driven edits count rounded output and input separately', () {
    final quote = apipodQuoteRequest('seedance-2.5-edit', {
      ..._input(),
      'mode': 'v2v',
      'resolution': 'sd',
      'source_duration': 4.0417,
    });
    expect(quote!.dimensions['duration'], '10');
    expect(quote.dimensions['video_count'], '1');
    expect(quote.hasVideo, isTrue);
    final wan = apipodQuoteRequest('wan2.7-videoedit', {
      ..._input(),
      'mode': 'v2v',
      'source_duration': 4.0417,
    });
    expect(wan!.dimensions['duration'], '5');
    final fallback = apipodEstimate(
      'seedance-2.5-edit',
      VideoMode.v2v,
      const GenerationConfig(
        aspectRatio: 'auto',
        duration: 4,
        resolution: 'sd',
        generateAudio: false,
        safetyTolerance: 2,
        draft: false,
      ),
      sourceMetadata: const VideoSourceMetadata(
        width: 854,
        height: 480,
        durationSeconds: 4.0417,
      ),
    );
    expect(fallback.minimumUsd, closeTo(.588, 1e-8));
    expect(
      fallback.calculation,
      '5 s output · 480p + 5 s input video (rounded per clip)',
    );
  });

  test('static fallback resolves the same route and rounds each input', () {
    final estimate = apipodEstimate(
      'seedance-2.5',
      VideoMode.i2v,
      const GenerationConfig(
        aspectRatio: '16:9',
        duration: 5,
        resolution: 'sd',
        generateAudio: false,
        safetyTolerance: 2,
        draft: false,
        references: [
          MediaReferenceLabel(
            label: 'one',
            kind: MediaReferenceKind.video,
            durationSeconds: 4.0417,
          ),
          MediaReferenceLabel(
            label: 'two',
            kind: MediaReferenceKind.video,
            durationSeconds: 6.0417,
          ),
        ],
      ),
    );
    expect(estimate.minimumUsd, .9996);
    expect(estimate.maximumUsd, .9996);
  });

  test('unresolved durations never issue a misleading live quote', () async {
    var calls = 0;
    final api = ApipodApi(
      client: MockClient((request) async {
        calls++;
        return _quote(0);
      }),
    );
    for (final extra in [
      {'duration': 'auto'},
      {'mode': VideoMode.draftEnhance.wireValue},
      {
        'mode': 'i2v',
        'reference_types': ['video'],
        'reference_video_duration_pending': 1,
      },
      {
        'mode': 'i2v',
        'reference_types': ['video', 'video'],
        'reference_video_duration_seconds': 10.0834,
      },
    ]) {
      expect(
        await api.estimate('seedance-2.5', {..._input(), ...extra}),
        isNull,
      );
    }
    expect(calls, 0);
  });

  test(
    'untrusted quote responses fall back instead of displaying zero',
    () async {
      final responses = [
        http.Response('unavailable', 503),
        http.Response('', 302, headers: {'location': 'https://other.example'}),
        http.Response('not JSON', 200),
        _quote(null),
        _quote(-1),
        _quote('NaN'),
        _quote(1, currency: 'CNY'),
        _quote(1, code: 500),
      ];
      for (final response in responses) {
        final api = ApipodApi(client: MockClient((_) async => response));
        expect(await api.estimate('seedance-2.5-t2v', _input()), isNull);
      }
    },
  );

  test(
    'case-sensitive tiers and flat per-generation prices remain exact',
    () async {
      final requests = <Map<String, Object?>>[];
      final api = ApipodApi(
        client: MockClient((request) async {
          requests.add(
            Map<String, Object?>.from(jsonDecode(request.body) as Map),
          );
          return _quote(requests.length == 1 ? .31 : .08, code: 0);
        }),
      );
      await api.estimate('minimax-h3-lite-t2v', {
        ..._input(),
        'resolution': 'qhd',
      });
      final veo = await api.estimate('veo3-1-lite', {
        ..._input(),
        'duration': 8,
      });
      expect((requests.first['dimensions'] as Map)['resolution'], '2K');
      expect(veo!.rateUnit, 'generation');
      expect(veo.rateUsd, .08);
    },
  );
}
