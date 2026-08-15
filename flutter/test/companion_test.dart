import 'dart:io';

import 'package:clawnsole/core/bfl_api.dart';
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
}
