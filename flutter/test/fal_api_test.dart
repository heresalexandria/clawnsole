import 'dart:async';
import 'dart:convert';

import 'package:clawnsole/core/api_transcript.dart';
import 'package:clawnsole/core/bfl_api.dart';
import 'package:clawnsole/core/fal_api.dart';
import 'package:clawnsole/core/provider_submission.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

const _textModel = 'blackforestlabs/flux-3-max/text-to-video';
const _imageModel = 'blackforestlabs/flux-3-max/image-to-video';
const _root = 'https://queue.fal.run/blackforestlabs/flux-3-max/requests/job-1';
const _statusUrl = '$_root/status';
const _key = 'test-key-id:test-key-secret';

http.Response _json(Object body, [int status = 200]) => http.Response(
  jsonEncode(body),
  status,
  headers: const {'content-type': 'application/json'},
);

Map<String, Object?> _receipt() => <String, Object?>{
  'request_id': 'job-1',
  'status_url': _statusUrl,
  'response_url': _root,
  'cancel_url': '$_root/cancel',
};

Map<String, Object?> _input() => <String, Object?>{
  'mode': 't2v',
  'prompt': 'A fox runs through dawn mist.',
  'duration': 5,
  'resolution': 'hd',
  'aspect_ratio': '16:9',
  'generate_audio': true,
};

void main() {
  test(
    'verify uses authenticated request listing without recording history',
    () async {
      final requests = <http.Request>[];
      final sink = _Sink();
      final api = FalApi(
        client: MockClient((request) async {
          requests.add(request);
          return _json({
            'requests': [
              {'request_id': 'someone-elses-job'},
            ],
          });
        }),
      );
      final account = await ApiTranscriptScope.run(
        () => api.verify(_key),
        sink: sink,
        operationId: 'verify',
        provider: 'fal',
        purpose: ApiRequestPurpose.balance,
      );
      expect(account.provider, 'fal');
      expect(account.balance, isNull);
      expect(requests.single.method, 'GET');
      expect(requests.single.url.host, 'api.fal.ai');
      expect(requests.single.url.path, '/v1/models/requests/by-endpoint');
      expect(requests.single.url.queryParameters, {
        'endpoint_id': _textModel,
        'limit': '1',
      });
      expect(requests.single.headers['Authorization'], 'Key $_key');
      expect(sink.records, isEmpty);
    },
  );

  test(
    'auth errors retain HTTP status and redact echoed credentials',
    () async {
      final api = FalApi(
        client: MockClient(
          (_) async => _json({
            'error': {'message': 'Invalid Key $_key'},
          }, 401),
        ),
      );
      await expectLater(
        api.verify(_key),
        throwsA(
          isA<ProviderException>()
              .having((error) => error.status, 'status', 401)
              .having(
                (error) => error.message,
                'redacted message',
                isNot(contains(_key)),
              )
              .having(
                (error) => jsonEncode(error.details),
                'redacted details',
                isNot(contains(_key)),
              ),
        ),
      );
    },
  );

  test(
    'submit maps the route, records durable intent, and stores canonical status',
    () async {
      final events = <String>[];
      final api = FalApi(
        client: MockClient((request) async {
          events.add('post');
          expect(request.method, 'POST');
          expect(request.url.toString(), 'https://queue.fal.run/$_textModel');
          expect(request.followRedirects, isFalse);
          expect(request.headers['Authorization'], 'Key $_key');
          expect(request.headers.containsKey('X-Fal-Store-IO'), isFalse);
          final payload = jsonDecode(request.body) as Map<String, Object?>;
          expect(payload['resolution'], '720p');
          expect(payload['prompt'], _input()['prompt']);
          expect(payload.containsKey('mode'), isFalse);
          return _json(_receipt());
        }),
      );
      final result = await api.submit(
        _key,
        _textModel,
        _input(),
        beforeSend: () async {
          events.add('persist');
        },
      );
      expect(events, ['persist', 'post']);
      expect(result, {'id': 'job-1', 'polling_url': _statusUrl});
    },
  );

  test(
    'media upload precedes durable dispatch and never forwards key to CDN',
    () async {
      final events = <String>[];
      final sink = _Sink();
      final api = FalApi(
        client: MockClient((request) async {
          if (request.url.host == 'rest.fal.ai') {
            events.add('init');
            expect(request.url.path, '/storage/upload/initiate');
            expect(request.url.queryParameters['storage_type'], 'fal-cdn-v3');
            expect(request.headers['Authorization'], 'Key $_key');
            return _json({
              'upload_url':
                  'https://v3.fal.media/upload/presigned?token=upload-secret',
              'file_url': 'https://v3.fal.media/files/input.png',
            });
          }
          if (request.url.host == 'v3.fal.media') {
            events.add('upload');
            expect(request.method, 'PUT');
            expect(
              request.headers.keys.map((key) => key.toLowerCase()),
              isNot(contains('authorization')),
            );
            expect(request.headers['content-type'], 'image/png');
            expect(request.bodyBytes, [1, 2, 3]);
            expect(request.followRedirects, isFalse);
            return http.Response('', 200);
          }
          events.add('submit');
          expect(request.url.path, '/$_imageModel');
          final payload = jsonDecode(request.body) as Map<String, Object?>;
          expect(payload['image_url'], 'https://v3.fal.media/files/input.png');
          return _json(_receipt());
        }),
      );
      await ApiTranscriptScope.run(
        () => api.submit(
          _key,
          _imageModel,
          {
            ..._input(),
            'mode': 'i2v',
            'keyframes': ['data:image/png;base64,AQID'],
          },
          beforeSend: () async {
            events.add('persist');
          },
        ),
        sink: sink,
        operationId: 'upload',
        provider: 'fal',
        purpose: ApiRequestPurpose.submit,
      );
      expect(events, ['init', 'upload', 'persist', 'submit']);
      expect(sink.records, hasLength(1));
      final transcript = jsonEncode(sink.records.single.toJson());
      expect(transcript, isNot(contains(_key)));
      expect(transcript, isNot(contains('upload-secret')));
    },
  );

  test(
    'hosted inputs bypass uploads and beforeSend failures prevent chargeable POST',
    () async {
      var calls = 0;
      final api = FalApi(
        client: MockClient((_) async {
          calls++;
          return _json(_receipt());
        }),
      );
      await expectLater(
        api.submit(
          _key,
          _imageModel,
          {
            ..._input(),
            'mode': 'i2v',
            'keyframes': ['https://example.com/frame.png'],
          },
          beforeSend: () async {
            throw StateError('could not persist');
          },
        ),
        throwsStateError,
      );
      expect(calls, 0);
    },
  );

  test('unknown models and invalid keys fail before side effects', () async {
    var calls = 0;
    var marked = false;
    final api = FalApi(
      client: MockClient((_) async {
        calls++;
        return _json(_receipt());
      }),
    );
    await expectLater(
      api.submit(_key, 'other/model', _input()),
      throwsA(
        isA<ProviderException>().having((error) => error.status, 'status', 400),
      ),
    );
    await expectLater(
      api.submit(
        '',
        _textModel,
        _input(),
        beforeSend: () async {
          marked = true;
        },
      ),
      throwsA(
        isA<ProviderException>().having((error) => error.status, 'status', 401),
      ),
    );
    expect(calls, 0);
    expect(marked, isFalse);
  });

  test(
    'resume uses persisted URL alone and retrieves completed video separately',
    () async {
      final paths = <String>[];
      var stage = 0;
      final client = MockClient((request) async {
        paths.add(request.url.path);
        expect(request.headers['Authorization'], 'Key $_key');
        expect(request.followRedirects, isFalse);
        if (!request.url.path.endsWith('/status')) {
          return _json({
            'video': {'url': 'https://v3.fal.media/files/output.mp4'},
          });
        }
        return _json({
          'request_id': 'job-1',
          'status': ['IN_QUEUE', 'IN_PROGRESS', 'COMPLETED'][stage++],
          'queue_position': 2,
          'response_url': _root,
        });
      });
      expect(
        (await FalApi(client: client).poll(_key, _statusUrl))['status'],
        'queued',
      );
      expect(
        (await FalApi(client: client).poll(_key, _statusUrl))['status'],
        'processing',
      );
      final result = await FalApi(client: client).poll(_key, _statusUrl);
      expect(result['status'], 'Ready');
      expect(result['outputs'], ['https://v3.fal.media/files/output.mp4']);
      expect(paths, [
        '/blackforestlabs/flux-3-max/requests/job-1/status',
        '/blackforestlabs/flux-3-max/requests/job-1/status',
        '/blackforestlabs/flux-3-max/requests/job-1/status',
        '/blackforestlabs/flux-3-max/requests/job-1',
      ]);
    },
  );

  test(
    'status rejects hostile or malformed saved URLs before sending credentials',
    () async {
      var calls = 0;
      final api = FalApi(
        client: MockClient((_) async {
          calls++;
          return _json({});
        }),
      );
      for (final url in [
        'http://queue.fal.run/blackforestlabs/flux-3-max/requests/job-1/status',
        'https://queue.fal.run.evil.test/blackforestlabs/flux-3-max/requests/job-1/status',
        'https://evil.test/blackforestlabs/flux-3-max/requests/job-1/status',
        'https://user@queue.fal.run/blackforestlabs/flux-3-max/requests/job-1/status',
        'https://@queue.fal.run/blackforestlabs/flux-3-max/requests/job-1/status',
        'https://queue.fal.run:444/blackforestlabs/flux-3-max/requests/job-1/status',
        '$_statusUrl?key=other',
        '$_statusUrl#fragment',
        'https://queue.fal.run/$_textModel/requests/job-1/status',
        'https://queue.fal.run/blackforestlabs/flux-3-max/requests/job%2F1/status',
      ]) {
        await expectLater(
          api.poll(_key, url),
          throwsA(
            isA<ProviderException>().having(
              (error) => error.status,
              'status',
              400,
            ),
          ),
          reason: url,
        );
      }
      expect(calls, 0);
    },
  );

  test(
    'receipt and status cannot redirect result authentication elsewhere',
    () async {
      var calls = 0;
      final api = FalApi(
        client: MockClient((request) async {
          calls++;
          if (request.method == 'POST') {
            return _json({
              ..._receipt(),
              'response_url': 'https://evil.test/result',
            });
          }
          return _json({
            'status': 'COMPLETED',
            'response_url': 'https://evil.test/result',
          });
        }),
      );
      await expectLater(
        api.submit(_key, _textModel, _input()),
        throwsA(
          isA<ProviderException>().having(
            (error) => isDefinitiveSubmissionRejection(error),
            'uncertain receipt',
            isFalse,
          ),
        ),
      );
      await expectLater(
        api.poll(_key, _statusUrl),
        throwsA(isA<ProviderException>()),
      );
      expect(calls, 2);
    },
  );

  test(
    'queue infrastructure failure is terminal without a result fetch',
    () async {
      var calls = 0;
      final api = FalApi(
        client: MockClient((_) async {
          calls++;
          return _json({
            'status': 'COMPLETED',
            'error': 'Runner failed',
            'error_type': 'runner_server_error',
          });
        }),
      );
      final result = await api.poll(_key, _statusUrl);
      expect(result['status'], 'Failed');
      expect(result['error'], 'Runner failed');
      expect(calls, 1);
    },
  );

  test('typed moderation result is terminal and drops echoed input', () async {
    final api = FalApi(
      client: MockClient((request) async {
        if (request.url.path.endsWith('/status')) {
          return _json({'status': 'COMPLETED'});
        }
        return _json({
          'detail': [
            {
              'type': 'content_policy_violation',
              'msg': 'Content was moderated.',
              'input': 'data:image/png;base64,AQID',
            },
          ],
        }, 422);
      }),
    );
    final result = await api.poll(_key, _statusUrl);
    expect(result['status'], 'Content Moderated');
    expect(result['error'], 'Content was moderated.');
    expect(jsonEncode(result), isNot(contains('base64')));
  });

  test(
    'result errors distinguish terminal failure from temporary HTTP failure',
    () async {
      for (final structured in [false, true]) {
        final api = FalApi(
          client: MockClient((request) async {
            if (request.url.path.endsWith('/status')) {
              return _json({'status': 'COMPLETED'});
            }
            return _json({
              'detail': 'Runner connection lost',
              if (structured) 'error_type': 'runner_connection_error',
            }, 503);
          }),
        );
        if (structured) {
          expect((await api.poll(_key, _statusUrl))['status'], 'Failed');
        } else {
          await expectLater(
            api.poll(_key, _statusUrl),
            throwsA(
              isA<ProviderException>().having(
                (error) => error.status,
                'status',
                503,
              ),
            ),
          );
        }
      }
    },
  );

  test('expired queue requests map to terminal task-not-found', () async {
    final api = FalApi(
      client: MockClient((_) async => _json({'detail': 'Gone'}, 404)),
    );
    expect((await api.poll(_key, _statusUrl))['status'], 'Task not found');
  });

  test(
    'result completion without video is a failure, never a ready empty film',
    () async {
      final api = FalApi(
        client: MockClient(
          (request) async => _json(
            request.url.path.endsWith('/status') ? {'status': 'COMPLETED'} : {},
          ),
        ),
      );
      expect((await api.poll(_key, _statusUrl))['status'], 'Failed');
    },
  );

  test(
    'transport timeouts stay uncertain and never trigger a second submission',
    () async {
      var calls = 0;
      final api = FalApi(
        client: MockClient((_) async {
          calls++;
          throw TimeoutException('private $_key');
        }),
      );
      await expectLater(
        api.submit(_key, _textModel, _input()),
        throwsA(
          isA<ProviderException>()
              .having(
                isDefinitiveSubmissionRejection,
                'uncertain submission',
                isFalse,
              )
              .having(
                (error) => error.message,
                'safe message',
                isNot(contains(_key)),
              ),
        ),
      );
      expect(calls, 1);
    },
  );

  test('redirect responses are rejected without following them', () async {
    final api = FalApi(
      client: MockClient((request) async {
        expect(request.followRedirects, isFalse);
        return http.Response(
          '',
          307,
          headers: {'location': 'https://evil.test/steal'},
        );
      }),
    );
    await expectLater(
      api.submit(_key, _textModel, _input()),
      throwsA(
        isA<ProviderException>().having((error) => error.status, 'status', 502),
      ),
    );
  });

  test(
    'recorded provider and transport errors never retain echoed API keys',
    () async {
      for (final transportError in [false, true]) {
        final sink = _Sink();
        final api = FalApi(
          client: MockClient((_) async {
            if (transportError) {
              throw http.ClientException('Connection failed with $_key');
            }
            return _json({'detail': 'Rejected key $_key'}, 401);
          }),
        );
        await expectLater(
          ApiTranscriptScope.run(
            () => api.submit(_key, _textModel, _input()),
            sink: sink,
            operationId: 'failed-submit',
            provider: 'fal',
            purpose: ApiRequestPurpose.submit,
          ),
          throwsA(isA<ProviderException>()),
        );
        expect(sink.records, hasLength(1));
        expect(jsonEncode(sink.records.single.toJson()), isNot(contains(_key)));
      }
    },
  );

  test(
    'malformed media and untrusted upload receipts fail before dispatch',
    () async {
      var marked = false;
      var calls = 0;
      final api = FalApi(
        client: MockClient((_) async {
          calls++;
          return _json({
            'upload_url': 'https://evil.test/upload',
            'file_url': 'https://v3.fal.media/files/input.png',
          });
        }),
      );
      for (final source in [
        'data:image/png,abc',
        'data:image/png;base64,%%%%',
        'http://localhost/private',
      ]) {
        await expectLater(
          api.submit(
            _key,
            _imageModel,
            {
              ..._input(),
              'mode': 'i2v',
              'keyframes': [source],
            },
            beforeSend: () async {
              marked = true;
            },
          ),
          throwsA(isA<ProviderException>()),
        );
      }
      expect(calls, 0);
      await expectLater(
        api.submit(
          _key,
          _imageModel,
          {
            ..._input(),
            'mode': 'i2v',
            'keyframes': ['data:image/png;base64,AQID'],
          },
          beforeSend: () async {
            marked = true;
          },
        ),
        throwsA(isA<ProviderException>()),
      );
      expect(calls, 1);
      expect(marked, isFalse);
    },
  );
}

class _Sink implements ApiTranscriptSink {
  final records = <ApiRequestRecord>[];
  @override
  void addApiRequest(ApiRequestRecord record) => records.add(record);
}
