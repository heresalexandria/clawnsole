import 'dart:convert';
import 'dart:io';

import 'package:clawnsole/core/bfl_api.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

import '../tool/clawnsole_companion.dart';

void main() {
  for (final providerError in [true, false]) {
    test(
      'companion sanitizes ${providerError ? 'provider' : 'unexpected'} errors',
      () async {
        final temporary = await Directory.systemTemp.createTemp(
          'clawnsole-diagnostic-rpc.',
        );
        final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
        final application = CompanionApp(
          store: CompanionStore(File('${temporary.path}/history.json')),
          api: _FailingApi(providerError),
        );
        final subscription = server.listen(application.handle);
        addTearDown(() async {
          await subscription.cancel();
          await server.close(force: true);
          await temporary.delete(recursive: true);
        });
        final response = await http.post(
          Uri.parse('http://127.0.0.1:${server.port}/credits'),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({'apiKey': 'FAKE_LOCAL_REQUEST_KEY'}),
        );
        expect(response.statusCode, providerError ? 429 : 500);
        expect(response.body, isNot(contains('FAKE_')));
        expect(response.body, isNot(contains('RkFLRV')));
        final body = jsonDecode(response.body) as Map<String, Object?>;
        expect(body['error'], contains('Try again later'));
        if (providerError) {
          final details = body['details'] as Map<String, Object?>;
          expect(details['status'], 'Error');
          expect(details['retry_after'], 30);
        }
      },
    );
  }
}

class _FailingApi extends BflApi {
  _FailingApi(this.providerError);
  final bool providerError;

  @override
  Future<double> getCredits(String apiKey) async {
    const message =
        'Try again later. Bearer FAKE_AUTH https://example.com/file?sig=FAKE_SIGNED_QUERY';
    if (!providerError) throw StateError(message);
    throw const ProviderException(
      message,
      status: 429,
      details: {
        'status': 'Error',
        'retry_after': 30,
        'message': 'token=FAKE_ERROR_TOKEN',
        'input': 'data:video/mp4;base64,RkFLRV9NRURJQV9CWVRFUw==',
        'unknown': {'secret': 'FAKE_NESTED_SECRET'},
      },
    );
  }
}
