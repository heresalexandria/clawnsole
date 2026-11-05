import 'dart:async';
import 'dart:convert';

import 'package:clawnsole/core/api_transcript.dart';
import 'package:clawnsole/core/apipod_api.dart';
import 'package:clawnsole/core/apipod_model_contracts.dart';
import 'package:clawnsole/core/bfl_api.dart';
import 'package:clawnsole/core/provider_submission.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

const _key = 'apipod-test-secret';
const _statusUrl = 'https://api.apipod.ai/v1/videos/status/vid_job-1';
const _image = 'https://cdn.example.com/frame.png';
const _video = 'https://cdn.example.com/reference.mp4';
const _audio = 'https://cdn.example.com/reference.mp3';

http.Response _json(Object value, [int status = 200]) =>
    http.Response(jsonEncode(value), status);

Map<String, Object?> _envelope(Object data) => {
  'code': 200,
  'message': 'success',
  'data': data,
};

Map<String, Object?> _input() => {
  'prompt': 'A fox crosses a meadow.',
  'duration': 5,
  'resolution': 'hd',
  'aspect_ratio': '16:9',
  'generate_audio': true,
};

void main() {
  test(
    'verify uses authenticated account probe without storing account data',
    () async {
      final sink = _Sink();
      final api = ApipodApi(
        client: MockClient((request) async {
          expect(request.method, 'GET');
          expect(
            request.url.toString(),
            'https://api.apipod.ai/v1/account/status',
          );
          expect(request.headers['Authorization'], 'Bearer $_key');
          expect(request.followRedirects, isFalse);
          return _json(_envelope({'unpublished_balance_field': 'private'}));
        }),
      );
      final result = await ApiTranscriptScope.run(
        () => api.verify(_key),
        sink: sink,
        operationId: 'verify',
        provider: 'apipod',
        purpose: ApiRequestPurpose.balance,
      );
      expect(result.provider, 'apipod');
      expect(result.balance, isNull);
      expect(sink.records, isEmpty);
    },
  );

  test(
    'submission maps input and records intent before idempotent POST',
    () async {
      final events = <String>[];
      final api = ApipodApi(
        client: MockClient((request) async {
          events.add('post');
          expect(request.method, 'POST');
          expect(request.url.path, '/v1/videos/generations');
          expect(request.followRedirects, isFalse);
          expect(request.headers['Authorization'], 'Bearer $_key');
          expect(
            request.headers['Idempotency-Key'],
            submissionIdempotencyToken('local-job'),
          );
          expect(jsonDecode(request.body), {
            'model': 'seedance-2.5-t2v',
            'prompt': 'A fox crosses a meadow.',
            'duration': 5,
            'resolution': '720p',
            'aspect_ratio': '16:9',
            'generate_audio': true,
          });
          return _json(
            _envelope({'task_id': 'vid_job-1', 'unrelated': 'ignored'}),
          );
        }),
      );
      final result = await api.submit(
        _key,
        'seedance-2.5-t2v',
        _input(),
        operationId: 'local-job',
        beforeSend: () async {
          events.add('intent');
        },
      );
      expect(events, ['intent', 'post']);
      expect(result, {'id': 'vid_job-1', 'polling_url': _statusUrl});
    },
  );

  test(
    'all documented text controls and duration boundaries map without extras',
    () {
      for (final resolution in ['sd', 'hd', 'fhd']) {
        for (final duration in [4, 30]) {
          for (final ratio in [
            'auto',
            '16:9',
            '4:3',
            '1:1',
            '3:4',
            '9:16',
            '21:9',
          ]) {
            final payload = apipodGenerationPayload('seedance-2.5-t2v', {
              ..._input(),
              'mode': 't2v',
              'resolution': resolution,
              'duration': duration,
              'aspect_ratio': ratio,
              'generate_audio': false,
            });
            expect(payload.keys.toSet(), {
              'model',
              'prompt',
              'resolution',
              'duration',
              'aspect_ratio',
              'generate_audio',
            });
            expect(
              payload['resolution'],
              {'sd': '480p', 'hd': '720p', 'fhd': '1080p'}[resolution],
            );
            expect(payload['duration'], duration);
            expect(
              payload['aspect_ratio'],
              ratio == 'auto' ? 'adaptive' : ratio,
            );
            expect(payload['generate_audio'], false);
          }
        }
      }
    },
  );

  test(
    'image route preserves first and last frames with adaptive aspect ratio',
    () {
      final payload = apipodGenerationPayload('seedance-2.5-i2v', {
        ..._input(),
        'mode': 'i2v',
        'aspect_ratio': 'auto',
        'keyframes': [_image, 'https://cdn.example.com/end.png'],
      });
      expect(payload['image_urls'], [
        _image,
        'https://cdn.example.com/end.png',
      ]);
      expect(payload['aspect_ratio'], 'adaptive');
      expect(payload.containsKey('keyframes'), false);
    },
  );

  test(
    'reference route maps ordered visual and audio media with prompt mentions',
    () {
      final payload = apipodGenerationPayload('seedance-2.5-r2v', {
        ..._input(),
        'mode': 'i2v',
        'prompt': '@Image 1 moves like @Video 1 with @Audio 1.',
        'reference_images': [_image],
        'reference_videos': [_video],
        'reference_audios': [_audio],
        'reference_task': 'reference',
      });
      expect(payload['image_urls'], [_image]);
      expect(payload['video_urls'], [_video]);
      expect(payload['audio_urls'], [_audio]);
      expect(payload['prompt'], '@image1 moves like @video1 with @audio1.');
      expect(payload.containsKey('reference_task'), false);
    },
  );

  test(
    'invalid or unsupported settings are rejected before durable intent and network',
    () async {
      var sends = 0;
      var intents = 0;
      final api = ApipodApi(
        client: MockClient((_) async {
          sends++;
          return _json(_envelope({'task_id': 'unused'}));
        }),
      );
      final inputs = <Map<String, Object?>>[
        {..._input(), 'duration': 3},
        {..._input(), 'duration': 31},
        {..._input(), 'duration': 4.5},
        {..._input(), 'duration': 'auto'},
        {..._input(), 'duration': double.infinity},
        {..._input(), 'resolution': '4k'},
        {..._input(), 'aspect_ratio': '2:1'},
        {..._input(), 'prompt': ''},
        {..._input(), 'prompt': 'x' * 30001},
        {..._input(), 'seed': 10},
        {..._input(), 'draft': true},
        {..._input(), 'generate_audio': 'yes'},
        {..._input(), 'reference_task': 'edit'},
        {
          ..._input(),
          'reference_images': [_image],
        },
        {
          ..._input(),
          'keyframes': [_image],
        },
        {..._input(), 'start_video': _video},
        {..._input(), 'mode': 'v2v'},
      ];
      for (final input in inputs) {
        await expectLater(
          api.submit(
            _key,
            'seedance-2.5-t2v',
            input,
            beforeSend: () async {
              intents++;
            },
          ),
          throwsA(
            isA<ProviderException>().having((e) => e.status, 'status', 400),
          ),
        );
      }
      await expectLater(
        api.submit(_key, 'seedance-2.5-edit', _input()),
        throwsA(isA<ProviderException>()),
      );
      expect(sends, 0);
      expect(intents, 0);
    },
  );

  test(
    'reference constraints and local media are enforced before dispatch',
    () {
      for (final references in <Map<String, Object?>>[
        {
          'reference_audios': [_audio],
        },
        {'reference_images': List.filled(31, _image)},
        {
          'reference_images': [_image],
          'reference_videos': List.filled(11, _video),
        },
        {
          'reference_images': [_image],
          'reference_audios': List.filled(11, _audio),
        },
        {
          'reference_images': ['data:image/png;base64,aGk='],
        },
        {
          'reference_images': ['http://cdn.example.com/frame.png'],
        },
        {
          'reference_images': ['https://127.0.0.1/frame.png'],
        },
        {
          'reference_images': [
            'https://user:password@cdn.example.com/frame.png',
          ],
        },
        {
          'reference_images': ['https://cdn.example.com/frame.png#part'],
        },
        {'reference_images': 'not-a-list'},
        {
          'reference_images': [42],
        },
      ]) {
        expect(
          () => apipodGenerationPayload('seedance-2.5-r2v', {
            ..._input(),
            ...references,
          }),
          throwsA(isA<ProviderException>()),
        );
      }
      expect(
        () => apipodGenerationPayload('seedance-2.5-i2v', {
          ..._input(),
          'aspect_ratio': 'auto',
        }),
        throwsA(isA<ProviderException>()),
      );
      expect(
        () => apipodGenerationPayload('seedance-2.5-i2v', {
          ..._input(),
          'aspect_ratio': 'auto',
          'keyframes': List.filled(3, _image),
        }),
        throwsA(isA<ProviderException>()),
      );
      final maximum = apipodGenerationPayload('seedance-2.5-r2v', {
        ..._input(),
        'reference_images': List.filled(30, _image),
        'reference_videos': List.filled(10, _video),
        'reference_audios': List.filled(10, _audio),
      });
      expect(maximum['image_urls'], hasLength(30));
    },
  );

  test(
    'a failed durable-intent callback prevents the chargeable POST',
    () async {
      var sent = false;
      final api = ApipodApi(
        client: MockClient((_) async {
          sent = true;
          return _json(_envelope({'task_id': 'unused'}));
        }),
      );
      await expectLater(
        api.submit(
          _key,
          'seedance-2.5-t2v',
          _input(),
          beforeSend: () async {
            throw StateError('disk full');
          },
        ),
        throwsStateError,
      );
      expect(sent, false);
    },
  );

  test('receipts lacking a safe task ID remain ambiguous', () async {
    for (final data in <Object?>[
      null,
      {},
      {'task_id': ''},
      {'task_id': '../other'},
      {'task_id': 'x/y'},
      {'task_id': 42},
    ]) {
      final api = ApipodApi(
        client: MockClient((_) async => _json(_envelope(data ?? {}))),
      );
      try {
        await api.submit(_key, 'seedance-2.5-t2v', _input());
        fail('invalid receipt accepted');
      } on ProviderException catch (error) {
        expect(error.status, 502);
        expect(isDefinitiveSubmissionRejection(error), false);
      }
    }
  });

  test(
    'polling maps pending, progress, outputs and only completed USD cost',
    () async {
      for (final status in ['pending', 'processing', 'completed']) {
        final api = ApipodApi(
          client: MockClient((request) async {
            expect(request.url.toString(), _statusUrl);
            expect(request.headers['Authorization'], 'Bearer $_key');
            expect(request.followRedirects, false);
            return _json(
              _envelope({
                'task_id': 'vid_job-1',
                'status': status,
                'progress': 1,
                'result': ['https://cdn.example.com/output.mp4'],
                'usage': {'cost': 0.2205},
              }),
            );
          }),
        );
        final result = await api.poll(_key, _statusUrl);
        expect(result['status'], status);
        expect(findProviderProgress(result), 1);
        expect(result['cost'], status == 'completed' ? 0.2205 : null);
        expect(
          result['outputs'],
          status == 'completed' ? ['https://cdn.example.com/output.mp4'] : null,
        );
      }
    },
  );

  test(
    'terminal failures retain provider message without fabricating moderation',
    () async {
      for (final status in ['failed', 'cancelled']) {
        final api = ApipodApi(
          client: MockClient(
            (_) async => _json(
              _envelope({
                'task_id': 'vid_job-1',
                'status': status,
                'error_message': 'Upstream capacity exhausted for $_key',
                'error_code': 'UPSTREAM_CAPACITY_EXHAUSTED',
              }),
            ),
          ),
        );
        final result = await api.poll(_key, _statusUrl);
        expect(result['status'], status);
        expect(result['error'], contains('Upstream capacity exhausted'));
        expect(result['error'], isNot(contains(_key)));
        expect(result['error_code'], 'UPSTREAM_CAPACITY_EXHAUSTED');
      }
    },
  );

  test(
    'missing tasks and completed tasks without output are terminal failures',
    () async {
      for (final status in [404, 410]) {
        final api = ApipodApi(
          client: MockClient((_) async => _json({}, status)),
        );
        expect((await api.poll(_key, _statusUrl))['status'], 'Task not found');
      }
      final api = ApipodApi(
        client: MockClient(
          (_) async => _json(
            _envelope({
              'task_id': 'vid_job-1',
              'status': 'completed',
              'result': [],
            }),
          ),
        ),
      );
      expect((await api.poll(_key, _statusUrl))['status'], 'Failed');
    },
  );

  test('status identity and output URLs are validated', () async {
    for (final data in [
      {'task_id': 'other', 'status': 'pending'},
      {'task_id': 'vid_job-1', 'status': 'made-up'},
      {
        'task_id': 'vid_job-1',
        'status': 'completed',
        'result': ['https://127.0.0.1/video.mp4'],
      },
      {
        'task_id': 'vid_job-1',
        'status': 'completed',
        'result': [42],
      },
    ]) {
      final api = ApipodApi(
        client: MockClient((_) async => _json(_envelope(data))),
      );
      await expectLater(
        api.poll(_key, _statusUrl),
        throwsA(isA<ProviderException>()),
      );
    }
  });

  test(
    'polling URLs cannot move credentials outside the exact canonical route',
    () async {
      var sends = 0;
      final api = ApipodApi(
        client: MockClient((_) async {
          sends++;
          return _json({});
        }),
      );
      for (final url in [
        'http://api.apipod.ai/v1/videos/status/vid_job-1',
        'https://api.apipod.ai.evil.test/v1/videos/status/vid_job-1',
        'https://api.apipod.ai:444/v1/videos/status/vid_job-1',
        'https://user@api.apipod.ai/v1/videos/status/vid_job-1',
        'https://@api.apipod.ai/v1/videos/status/vid_job-1',
        '$_statusUrl?key=secret',
        '$_statusUrl#fragment',
        '$_statusUrl/extra',
        'https://api.apipod.ai/v1/videos/status/vid%2Fjob-1',
        'https://api.apipod.ai/v1/account/status',
      ]) {
        await expectLater(
          api.poll(_key, url),
          throwsA(isA<ProviderException>()),
        );
      }
      expect(sends, 0);
    },
  );

  test(
    'HTTP failures preserve classification and scrub echoed keys everywhere',
    () async {
      for (final status in [401, 402, 403, 409, 429, 500, 503]) {
        final sink = _Sink();
        final api = ApipodApi(
          client: MockClient(
            (_) async => _json({
              'error': {'message': 'APIPod rejected $_key'},
            }, status),
          ),
        );
        await expectLater(
          ApiTranscriptScope.run(
            () => api.submit(_key, 'seedance-2.5-t2v', _input()),
            sink: sink,
            operationId: 'test',
            provider: 'apipod',
            purpose: ApiRequestPurpose.submit,
          ),
          throwsA(
            isA<ProviderException>()
                .having((e) => e.status, 'status', status)
                .having(
                  (e) => jsonEncode(e.details),
                  'details',
                  isNot(contains(_key)),
                )
                .having((e) => e.message, 'message', isNot(contains(_key))),
          ),
        );
        expect(
          jsonEncode(sink.records.map((e) => e.toJson()).toList()),
          isNot(contains(_key)),
        );
      }
    },
  );

  test(
    'redirects, malformed responses and contradictory success remain ambiguous',
    () async {
      for (final response in [
        http.Response('', 302, headers: {'location': 'https://evil.test/'}),
        http.Response('not JSON', 200),
        _json({'code': 400, 'message': 'bad settings'}, 200),
        _json({
          'error': {'message': 'error'},
        }, 200),
      ]) {
        final api = ApipodApi(
          client: MockClient((request) async {
            expect(request.followRedirects, false);
            return response;
          }),
        );
        await expectLater(
          api.submit(_key, 'seedance-2.5-t2v', _input()),
          throwsA(
            isA<ProviderException>().having(
              isDefinitiveSubmissionRejection,
              'definitive',
              false,
            ),
          ),
        );
      }
    },
  );

  test(
    'transport failures remain ambiguous and never expose credentials',
    () async {
      for (final timeout in [false, true]) {
        final sink = _Sink();
        final api = ApipodApi(
          client: MockClient((_) async {
            if (timeout) throw TimeoutException('Echo $_key');
            throw http.ClientException('Echo $_key');
          }),
        );
        await expectLater(
          ApiTranscriptScope.run(
            () => api.submit(_key, 'seedance-2.5-t2v', _input()),
            sink: sink,
            operationId: 'test',
            provider: 'apipod',
            purpose: ApiRequestPurpose.submit,
          ),
          throwsA(
            isA<ProviderException>()
                .having(isDefinitiveSubmissionRejection, 'definitive', false)
                .having((e) => e.message, 'message', isNot(contains(_key))),
          ),
        );
        expect(
          jsonEncode(sink.records.map((e) => e.toJson()).toList()),
          isNot(contains(_key)),
        );
      }
    },
  );
}

class _Sink implements ApiTranscriptSink {
  final records = <ApiRequestRecord>[];
  @override
  void addApiRequest(ApiRequestRecord record) => records.add(record);
}
