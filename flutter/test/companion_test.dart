import 'dart:convert';
import 'dart:io';

import 'package:clawnsole/core/bfl_api.dart';
import 'package:clawnsole/core/models.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

import '../tool/clawnsole_companion.dart';

void main() {
  test('companion config accepts an embedded Flutter web root', () {
    final config = CompanionConfig.from(<String>[
      '--port',
      '0',
      '--data-file',
      'data.json',
      '--web-root',
      'build/web',
    ], const <String, String>{});
    expect(config.port, 0);
    expect(config.dataFile, endsWith('data.json'));
    expect(config.webRoot, endsWith('build/web'));
  });

  test('companion serves the Flutter bundle and API on one origin', () async {
    final temporary = await Directory.systemTemp.createTemp(
      'clawnsole-companion-test.',
    );
    final webRoot = Directory('${temporary.path}/web')..createSync();
    File('${webRoot.path}/index.html').writeAsStringSync('<h1>Clawnsole</h1>');
    File('${webRoot.path}/main.dart.js').writeAsStringSync('void 0;');
    final application = CompanionApp(
      store: CompanionStore(File('${temporary.path}/clawnsole.json')),
      api: BflApi(),
      webRoot: webRoot,
    );
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final subscription = server.listen(application.handle);
    final base = Uri.parse('http://127.0.0.1:${server.port}');

    try {
      final index = await http.get(base.resolve('/'));
      expect(index.statusCode, 200);
      expect(index.body, contains('Clawnsole'));
      expect(
        index.headers[HttpHeaders.cacheControlHeader],
        'private, no-store',
      );

      final script = await http.get(base.resolve('/main.dart.js'));
      expect(script.statusCode, 200);
      expect(
        script.headers[HttpHeaders.contentTypeHeader],
        contains('javascript'),
      );
      expect(
        script.headers[HttpHeaders.cacheControlHeader],
        'private, no-store',
      );

      final scriptHead = await http.head(base.resolve('/main.dart.js'));
      expect(scriptHead.statusCode, 200);
      expect(scriptHead.body, isEmpty);

      final health = await http.get(base.resolve('/health'));
      expect(health.statusCode, 200);
      expect(health.body, contains('"ok":true'));
    } finally {
      await subscription.cancel();
      await server.close(force: true);
      await temporary.delete(recursive: true);
    }
  });

  test('companion turns a 503 Error payload into a terminal record', () async {
    final temporary = await Directory.systemTemp.createTemp(
      'clawnsole-status-test.',
    );
    final store = CompanionStore(File('${temporary.path}/clawnsole.json'));
    final now = DateTime.utc(2026, 8, 15, 12);
    await store.replace(
      StoredData(
        apiKey: 'test-key',
        generations: <Generation>[
          Generation(
            localId: 'generation-one',
            status: 'Pending',
            prompt: 'A slow pan across a brass control room.',
            mode: VideoMode.t2v,
            config: const GenerationConfig(
              aspectRatio: '16:9',
              duration: 8,
              resolution: 'hd',
              generateAudio: true,
              safetyTolerance: 2,
              draft: false,
            ),
            createdAt: now,
            updatedAt: now,
            requestId: 'provider-one',
            pollingUrl: 'https://api.bfl.ai/v1/get_result?id=provider-one',
          ),
        ],
      ),
    );
    final application = CompanionApp(store: store, api: _Terminal503Api());
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final subscription = server.listen(application.handle);
    final base = Uri.parse('http://127.0.0.1:${server.port}');

    try {
      final response = await http.post(
        base.resolve('/generations/status'),
        headers: const <String, String>{'Content-Type': 'application/json'},
        body: jsonEncode(<String, Object?>{
          'provider': 'bfl',
          'localId': 'generation-one',
          'pollingUrl': 'https://api.bfl.ai/v1/get_result?id=provider-one',
        }),
      );
      expect(response.statusCode, 200);
      final payload = jsonDecode(response.body) as Map<String, Object?>;
      final generation = Generation.fromJson(
        (payload['generation']! as Map<Object?, Object?>).map(
          (key, value) => MapEntry(key.toString(), value),
        ),
      );
      expect(generation.status, 'Error');
      expect(generation.isWorking, isFalse);
      expect(generation.lastProviderStatusCode, 503);
      expect(generation.error, 'Generation dependency unavailable');
      expect(generation.lastProviderResponse, contains('"status": "Error"'));
      expect((await store.read()).generations.single.status, 'Error');
    } finally {
      await subscription.cancel();
      await server.close(force: true);
      await temporary.delete(recursive: true);
    }
  });
}

class _Terminal503Api extends BflApi {
  @override
  Future<Map<String, Object?>> poll(String apiKey, String pollingUrl) async {
    throw const ProviderException(
      'BFL is temporarily unavailable (HTTP 503). Retry shortly.',
      status: 503,
      details: <String, Object?>{
        'status': 'Error',
        'details': <String, Object?>{
          'message': 'Generation dependency unavailable',
        },
      },
    );
  }
}
