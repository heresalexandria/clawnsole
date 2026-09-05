import 'dart:async';
import 'dart:io';

import 'package:clawnsole/core/google_drive_auth_io.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

const _tokenKey = 'clawnsole.googleDrive.refreshToken.v1';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const storage = FlutterSecureStorage();

  setUp(() {
    FlutterSecureStorage.setMockInitialValues({_tokenKey: 'fake-refresh'});
  });

  final failures = <String, Future<http.Response> Function()>{
    'offline': () async => throw const SocketException('offline fixture'),
    'timeout': () async => throw TimeoutException('timeout fixture'),
    'server error': () async =>
        http.Response('{"error":"temporarily_unavailable"}', 503),
    'rate limit': () async =>
        http.Response('{"error":"rate_limit_exceeded"}', 429),
    'client configuration': () async =>
        http.Response('{"error":"invalid_client"}', 400),
    'malformed JSON': () async => http.Response('not JSON', 502),
    'invalid-grant body on a server failure': () async =>
        http.Response('{"error":"invalid_grant"}', 503),
  };
  for (final failure in failures.entries) {
    for (final silent in [true, false]) {
      test(
        '${silent ? 'silent' : 'interactive'} refresh preserves token after ${failure.key}',
        () async {
          var recovered = false;
          final client = MockClient((request) async {
            expect(
              Uri.splitQueryString(request.body)['refresh_token'],
              'fake-refresh',
            );
            return recovered
                ? http.Response('{"access_token":"recovered-access"}', 200)
                : failure.value();
          });
          addTearDown(client.close);
          final auth = DesktopGoogleDriveAuthorizer(
            secureStorage: storage,
            client: client,
            clientId: 'fake-client',
          );
          if (silent) {
            expect(await auth.authorizeSilently(), isNull);
          } else {
            await expectLater(auth.authorize(), throwsA(isA<Object>()));
          }
          expect(await storage.read(key: _tokenKey), 'fake-refresh');
          recovered = true;
          expect(
            await (silent ? auth.authorizeSilently() : auth.authorize()),
            'recovered-access',
          );
        },
      );
    }
  }

  test(
    'explicit invalid_grant forgets rejected refresh token without prompting',
    () async {
      final client = MockClient(
        (_) async => http.Response(
          '{"error":"invalid_grant","error_description":"revoked fixture"}',
          400,
        ),
      );
      addTearDown(client.close);
      final auth = DesktopGoogleDriveAuthorizer(
        secureStorage: storage,
        client: client,
        clientId: 'fake-client',
      );
      expect(await auth.authorizeSilently(), isNull);
      expect(await storage.read(key: _tokenKey), isNull);
    },
  );

  test('explicit disconnect still removes the token while offline', () async {
    final client = MockClient(
      (_) async => throw const SocketException('offline fixture'),
    );
    addTearDown(client.close);
    final auth = DesktopGoogleDriveAuthorizer(
      secureStorage: storage,
      client: client,
      clientId: 'fake-client',
    );
    await auth.disconnect();
    expect(await storage.read(key: _tokenKey), isNull);
  });
}
