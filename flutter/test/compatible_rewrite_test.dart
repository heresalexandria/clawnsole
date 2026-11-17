import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:clawnsole/core/bfl_api.dart';
import 'package:clawnsole/core/compatible_rewrite_api.dart';
import 'package:clawnsole/core/direct_gateway.dart';
import 'package:clawnsole/core/durable_data_store.dart';
import 'package:clawnsole/core/models.dart';
import 'package:clawnsole/core/prompt_rewrite.dart';
import 'package:clawnsole/core/prompt_rewrite_router.dart';
import 'package:clawnsole/core/rewrite_connection.dart';
import 'package:clawnsole/core/web_gateway.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import '../tool/clawnsole_companion.dart';

const request = PromptRewriteRequest(
  providerId: 'custom-rewrite',
  modelId: 'vendor/my-model',
  originalPrompt: 'A red kite.',
  direction: 'Make it blue.',
  effort: 'high',
);

void main() {
  test('versioned connection keeps the API base and key together', () {
    final encoded = RewriteConnection(
      endpoint: ' https://openrouter.ai/api/v1/chat/completions/ ',
      apiKey: ' sk-custom ',
    ).toCredential();
    final restored = RewriteConnection.fromCredential(encoded);
    expect(restored.endpoint.toString(), 'https://openrouter.ai/api/v1/');
    expect(restored.apiKey, 'sk-custom');
    expect(
      normalizeRewriteEndpoint('http://localhost:1234/v1').toString(),
      'http://localhost:1234/v1/',
    );
    for (final url in <String>[
      '',
      'ftp://host/v1',
      'https://user:secret@host/v1',
      'https://host/v1?api_key=secret',
      'https://host/v1#secret',
      'https://bad host/v1',
    ]) {
      expect(
        () => normalizeRewriteEndpoint(url),
        throwsA(isA<PromptRewriteException>()),
      );
    }
    expect(RewriteConnection.tryFromCredential('old-key'), isNull);
    expect(RewriteConnection.tryFromCredential('{"schemaVersion":2}'), isNull);
  });

  test(
    'compatible wire format preserves base path, namespaced model and frames',
    () async {
      final calls = <http.Request>[];
      final api = CompatibleRewriteApi(
        client: MockClient((call) async {
          calls.add(call);
          expect(call.headers['Authorization'], 'Bearer sk-custom');
          if (call.method == 'GET') {
            return http.Response(
              jsonEncode(<String, Object?>{
                'data': <Object?>[
                  <String, String>{'id': 'vendor/my-model', 'name': 'My model'},
                  <String, String>{'id': 'vendor/my-model'},
                  <String, String>{'id': 'local-llama'},
                ],
              }),
              200,
            );
          }
          return _answer();
        }),
      );
      final credential = _credential();
      expect(
        (await api.listModels(credential)).map((model) => model.id),
        <String>['vendor/my-model', 'local-llama'],
      );
      final result = await api.rewrite(
        PromptRewriteRequest(
          providerId: request.providerId,
          modelId: request.modelId,
          originalPrompt: request.originalPrompt,
          direction: request.direction,
          frames: <RewriteFrame>[
            RewriteFrame(bytes: Uint8List.fromList(<int>[1, 2]), seconds: 2),
          ],
        ),
        credential,
      );
      expect(calls.map((call) => call.url.path), <String>[
        '/api/v1/models',
        '/api/v1/chat/completions',
      ]);
      final body = jsonDecode(calls.last.body) as Map<String, dynamic>;
      expect(body['model'], 'vendor/my-model');
      expect(body.keys, isNot(contains('reasoning')));
      expect(body.keys, isNot(contains('response_format')));
      expect(body['max_tokens'], 4096);
      final messages = body['messages'] as List<dynamic>;
      final content = messages.last['content'] as List<dynamic>;
      expect(content[1]['image_url']['url'], 'data:image/jpeg;base64,AQI=');
      expect(calls.last.body, isNot(contains('sk-custom')));
      expect(result.prompt, 'A blue kite.');
      expect(result.providerId, 'custom-rewrite');
      expect(result.modelId, 'vendor/served-model');
    },
  );

  test(
    'absent catalogs permit manual models; auth and malformed catalogs fail',
    () async {
      for (final status in <int>[404, 405, 501]) {
        final api = CompatibleRewriteApi(
          client: MockClient((_) async => http.Response('', status)),
        );
        expect(await api.listModels(_credential()), isEmpty);
      }
      for (final status in <int>[401, 403, 500]) {
        final api = CompatibleRewriteApi(
          client: MockClient(
            (_) async =>
                http.Response('{"error":{"message":"bad sk-custom"}}', status),
          ),
        );
        await expectLater(
          api.listModels(_credential()),
          throwsA(
            isA<PromptRewriteException>().having(
              (error) => error.message,
              'no secret',
              isNot(contains('sk-custom')),
            ),
          ),
        );
      }
      final malformed = CompatibleRewriteApi(
        client: MockClient((_) async => http.Response('{}', 200)),
      );
      await expectLater(
        malformed.listModels(_credential()),
        throwsA(isA<PromptRewriteException>()),
      );
    },
  );

  test(
    'redirects, refusals, truncation, and malformed answers stay typed',
    () async {
      for (final entry in <(http.Response, PromptRewriteFailure)>[
        (
          http.Response(
            '',
            302,
            headers: <String, String>{'location': 'https://elsewhere.test'},
          ),
          PromptRewriteFailure.other,
        ),
        (_answer(finishReason: 'length'), PromptRewriteFailure.invalidResponse),
        (_answer(finishReason: 'content_filter'), PromptRewriteFailure.refused),
        (
          http.Response(
            '{"choices":[{"message":{"content":"not json"}}]}',
            200,
          ),
          PromptRewriteFailure.invalidResponse,
        ),
      ]) {
        final api = CompatibleRewriteApi(
          client: MockClient((call) async {
            expect(call.followRedirects, isFalse);
            return entry.$1;
          }),
        );
        await expectLater(
          api.rewrite(request, _credential()),
          throwsA(
            isA<PromptRewriteException>().having(
              (error) => error.failure,
              'failure',
              entry.$2,
            ),
          ),
        );
      }
    },
  );

  test(
    'native and companion web resolve custom credentials beside the saved key',
    () async {
      final seen = <http.Request>[];
      final client = MockClient((call) async {
        seen.add(call);
        expect(call.url.host, 'openrouter.ai');
        expect(call.headers['Authorization'], 'Bearer sk-custom');
        return call.method == 'GET'
            ? http.Response('{"data":[]}', 200)
            : _answer();
      });
      final data = StoredData(
        apiKeys: <String, String>{
          'openai': 'sk-built-in',
          'custom-rewrite': _credential(),
        },
      );
      final direct = DirectGateway(store: _MemoryStore(data), client: client);
      final directSnapshot = await direct.load();
      expect(
        directSnapshot.rewriteEndpoints['custom-rewrite'],
        'https://openrouter.ai/api/v1/',
      );
      expect(jsonEncode(directSnapshot.toJson()), isNot(contains('sk-custom')));
      expect((await direct.rewritePrompt(request)).prompt, 'A blue kite.');

      final directory = await Directory.systemTemp.createTemp(
        'custom-rewrite-companion.',
      );
      final app = CompanionApp(
        store: CompanionStore(File('${directory.path}/library.json')),
        api: BflApi(),
        fallbackApiKeys: data.apiKeys,
        rewriteRouter: PromptRewriteRouter(client: client),
      );
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      final subscription = server.listen(app.handle);
      final webClient = http.Client();
      final web = WebGateway(
        baseUrl: Uri.parse('http://127.0.0.1:${server.port}'),
        client: webClient,
      );
      try {
        final snapshot = await web.load();
        expect(snapshot.rewriteEndpoints, directSnapshot.rewriteEndpoints);
        expect(snapshot.connectedRewriteProviders, contains('custom-rewrite'));
        expect(jsonEncode(snapshot.toJson()), isNot(contains('sk-custom')));
        expect(await web.listRewriteModels('custom-rewrite'), isEmpty);
        expect((await web.rewritePrompt(request)).prompt, 'A blue kite.');
        expect(seen, hasLength(3));
      } finally {
        webClient.close();
        await subscription.cancel();
        await server.close(force: true);
        await directory.delete(recursive: true);
      }
    },
  );
}

String _credential() => RewriteConnection(
  endpoint: 'https://openrouter.ai/api/v1',
  apiKey: 'sk-custom',
).toCredential();

http.Response _answer({String finishReason = 'stop'}) => http.Response(
  jsonEncode(<String, Object?>{
    'model': 'vendor/served-model',
    'choices': <Object?>[
      <String, Object?>{
        'finish_reason': finishReason,
        'message': <String, Object?>{
          'content': jsonEncode(<String, String>{
            'prompt': 'A blue kite.',
            'summary': 'Changed the color.',
          }),
        },
      },
    ],
  }),
  200,
);

class _MemoryStore implements DurableDataStore {
  _MemoryStore(this.data);
  StoredData data;
  @override
  Future<StoredData> read() async => data;
  @override
  Future<void> write(StoredData value) async => data = value;
  @override
  Future<StorageStats> stats(int records) async =>
      StorageStats(path: 'memory', bytes: 0, records: records);
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
