import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:clawnsole/core/artcraft_api.dart';
import 'package:clawnsole/core/bfl_api.dart';
import 'package:clawnsole/core/direct_gateway.dart';
import 'package:clawnsole/core/gateway.dart';
import 'package:clawnsole/core/generation_status.dart';
import 'package:clawnsole/core/models.dart';
import 'package:clawnsole/core/provider_submission.dart';
import 'package:clawnsole/core/web_gateway.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import '../tool/clawnsole_companion.dart';

void main() {
  for (final companion in [false, true]) {
    for (final outcome in [
      'timeout',
      'offline',
      '503',
      '408',
      '409',
      'malformed',
      'empty receipt',
      '400',
      '429',
      'accepted',
    ]) {
      test(
        '${companion ? 'companion' : 'native'} preserves the POST boundary after $outcome',
        () async {
          final temporary = await Directory.systemTemp.createTemp(
            'clawnsole-submit-boundary.',
          );
          final file = File('${temporary.path}/history.json');
          final store = CompanionStore(file);
          var posts = 0;
          final api = BflApi(
            client: MockClient((request) async {
              if (request.method == 'GET') {
                return http.Response('{"credits":100}', 200);
              }
              posts += 1;
              // Inspect the physical file before the fake provider sees a POST.
              final persisted = StoredData.decode(
                await file.readAsString(),
              ).generations;
              expect(
                persisted.any(
                  (item) =>
                      item.isSubmissionUnknown &&
                      !item.isFailed &&
                      !item.isWorking,
                ),
                isTrue,
              );
              switch (outcome) {
                case 'timeout':
                  throw TimeoutException('FAKE timeout');
                case 'offline':
                  throw const SocketException('FAKE offline');
                case 'malformed':
                  return http.Response('{"unexpected":true}', 200);
                case 'empty receipt':
                  return http.Response('{"id":"","polling_url":""}', 200);
                case 'accepted':
                  return http.Response(
                    '{"id":"receipt-$posts","polling_url":"https://api.bfl.ai/v1/get_result?id=receipt-$posts"}',
                    200,
                  );
                default:
                  return http.Response(
                    '{"detail":"Generation not confirmed"}',
                    int.parse(outcome),
                  );
              }
            }),
          );
          HttpServer? server;
          StreamSubscription<HttpRequest>? subscription;
          late AppGateway gateway;
          if (companion) {
            server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
            final app = CompanionApp(
              store: store,
              api: api,
              fallbackApiKeys: {'bfl': 'FAKE_PROVIDER_KEY'},
            );
            subscription = server.listen(app.handle);
            gateway = WebGateway(
              baseUrl: Uri.parse('http://127.0.0.1:${server.port}'),
            );
          } else {
            gateway = _FixtureGateway(store, api);
          }
          addTearDown(() async {
            await subscription?.cancel();
            await server?.close(force: true);
            await temporary.delete(recursive: true);
          });
          final submission = _submission('operation-one');
          if (outcome == '400' || outcome == '429') {
            await expectLater(
              gateway.submit(submission),
              throwsA(isA<ProviderException>()),
            );
            expect((await store.read()).generations.single.isFailed, isTrue);
            expect(posts, 1);
            return;
          }
          final result = await gateway.submit(submission);
          expect(result.isSubmissionUnknown, outcome != 'accepted');
          expect(result.isFailed, isFalse);
          if (outcome == 'accepted') {
            expect(result.error, isNull);
            expect(result.canCheckStatus, isTrue);
          } else {
            expect(result.error, submissionUnknownMessage);
            expect(result.canCheckStatus, isFalse);
          }
          // Reopening the gateway cannot turn an unknown/accepted operation into
          // another POST. A deliberate fresh local ID is a distinct operation.
          final AppGateway reopened = companion
              ? WebGateway(
                  baseUrl: Uri.parse('http://127.0.0.1:${server!.port}'),
                )
              : _FixtureGateway(CompanionStore(file), api);
          final recovered = await reopened.submit(submission);
          expect(recovered.status, result.status);
          expect(posts, 1);
          await reopened.submit(_submission('operation-two'));
          expect(posts, 2);
        },
      );
    }
    test(
      '${companion ? 'companion' : 'native'} does not POST when durable boundary write fails',
      () async {
        final temporary = await Directory.systemTemp.createTemp(
          'clawnsole-submit-write-failure.',
        );
        final store = _FailingBoundaryStore(
          File('${temporary.path}/history.json'),
        );
        var posts = 0;
        final api = BflApi(
          client: MockClient((request) async {
            if (request.method == 'POST') posts += 1;
            return http.Response('{"credits":100}', 200);
          }),
        );
        HttpServer? server;
        StreamSubscription<HttpRequest>? subscription;
        late AppGateway gateway;
        if (companion) {
          server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
          subscription = server.listen(
            CompanionApp(
              store: store,
              api: api,
              fallbackApiKeys: {'bfl': 'FAKE_KEY'},
            ).handle,
          );
          gateway = WebGateway(
            baseUrl: Uri.parse('http://127.0.0.1:${server.port}'),
          );
        } else {
          gateway = _FixtureGateway(store, api);
        }
        addTearDown(() async {
          await subscription?.cancel();
          await server?.close(force: true);
          await temporary.delete(recursive: true);
        });
        await expectLater(
          gateway.submit(_submission('failed-write')),
          throwsA(anything),
        );
        expect(posts, 0);
        expect((await store.read()).generations.single.isFailed, isTrue);
      },
    );
  }

  test(
    'ArtCraft idempotency is stable per operation and distinct for identical intentional generations',
    () async {
      final tokens = <String>[];
      var armed = false;
      final api = ArtCraftApi(
        client: MockClient((request) async {
          if (request.url.path == '/v1/omni_gen/cost/video') {
            expect(armed, isFalse);
            return http.Response('{"cost_in_credits":10}', 200);
          }
          expect(armed, isTrue);
          armed = false;
          tokens.add(
            (jsonDecode(request.body)
                    as Map<String, Object?>)['idempotency_token']!
                as String,
          );
          return http.Response('{"inference_job_token":"job-one"}', 200);
        }),
      );
      const input = {
        'prompt': 'same exact prompt',
        'duration': 5,
        'resolution': 'hd',
        'aspect_ratio': '16:9',
      };
      for (final operationId in [
        'operation-one',
        'operation-one',
        'operation-two',
      ]) {
        await api.submit(
          'FAKE_KEY',
          'seedance_2p5',
          input,
          operationId: operationId,
          beforeSend: () async {
            armed = true;
          },
        );
      }
      expect(tokens[0], tokens[1]);
      expect(tokens[0], isNot(tokens[2]));
      expect(tokens[0], submissionIdempotencyToken('operation-one'));
      expect(
        tokens[0],
        matches(
          r'^[0-9a-f]{8}-[0-9a-f]{4}-5[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$',
        ),
      );
      await expectLater(
        api.submit(
          'FAKE_KEY',
          'seedance_2p5',
          input,
          beforeSend: () async {
            throw StateError('FAKE disk failure');
          },
        ),
        throwsStateError,
      );
      expect(tokens, hasLength(3));
    },
  );
}

GenerationSubmission _submission(String id) => GenerationSubmission(
  record: Generation(
    localId: id,
    status: 'submitting',
    prompt: 'same prompt',
    mode: VideoMode.t2v,
    config: const GenerationConfig(
      aspectRatio: '16:9',
      duration: 5,
      resolution: 'hd',
      generateAudio: true,
      safetyTolerance: 2,
      draft: false,
    ),
    createdAt: DateTime.utc(2026, 9, 5),
    updatedAt: DateTime.now().toUtc(),
  ),
  input: const {
    'prompt': 'same prompt',
    'duration': 5,
    'resolution': 'hd',
    'aspect_ratio': '16:9',
  },
  autoFixReferenceVideos: false,
);

class _FixtureGateway extends DirectGateway {
  _FixtureGateway(CompanionStore store, BflApi api)
    : super(store: store, api: api);
  @override
  ActiveApiKey? activeApiKey(String provider, StoredData data) =>
      const ActiveApiKey('FAKE_PROVIDER_KEY', ApiKeySource.saved);
}

class _FailingBoundaryStore extends CompanionStore {
  _FailingBoundaryStore(super.file);
  @override
  Future<void> write(StoredData data) {
    if (data.generations.any((item) => item.isSubmissionUnknown)) {
      throw StateError('FAKE disk failure');
    }
    return super.write(data);
  }
}
