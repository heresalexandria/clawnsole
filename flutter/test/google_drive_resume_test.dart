import 'dart:convert';

import 'package:clawnsole/core/google_drive.dart';
import 'package:clawnsole/core/google_drive_auth_base.dart';
import 'package:clawnsole/core/web_gateway.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  Map<String, Object?> statePayload({
    required String folderName,
    String state = 'disconnected',
    List<Map<String, Object?>> generations = const <Map<String, Object?>>[],
  }) => <String, Object?>{
    'generations': generations,
    'preferences': <String, Object?>{},
    'hasBflApiKey': false,
    'storage': <String, Object?>{'path': 'memory', 'bytes': 0, 'records': 0},
    'driveConnection': <String, Object?>{
      'state': state,
      'folderName': folderName,
      'folderId': folderName.isEmpty ? '' : 'folder-1',
    },
  };

  Map<String, Object?> driveGeneration() => <String, Object?>{
    'localId': 'drive-film',
    'status': 'Ready',
    'prompt': 'A film that lives in Drive.',
    'mode': 't2v',
    'storage': 'drive',
    'config': <String, Object?>{
      'aspectRatio': '16:9',
      'duration': 8,
      'resolution': 'hd',
      'generateAudio': true,
      'safetyTolerance': 2,
      'draft': false,
    },
    'createdAt': '2026-08-20T12:00:00Z',
    'updatedAt': '2026-08-20T12:00:00Z',
  };

  test(
    'resume reattaches a configured Drive session without prompting',
    () async {
      final refreshBodies = <Map<String, Object?>>[];
      final authorizer = _FakeAuthorizer(silentToken: 'silent-token');
      final gateway = WebGateway(
        baseUrl: Uri.parse('http://127.0.0.1:9999/'),
        driveAuthorizer: authorizer,
        settingsVaultInvoker: (_, _) async => <String, Object?>{'ok': true},
        client: MockClient((request) async {
          if (request.url.path == '/state') {
            return http.Response(
              jsonEncode(statePayload(folderName: 'Clawnsole')),
              200,
            );
          }
          if (request.url.path == '/drive/refresh') {
            refreshBodies.add(
              (jsonDecode(request.body) as Map<Object?, Object?>).map(
                (key, value) => MapEntry(key.toString(), value),
              ),
            );
            return http.Response(
              jsonEncode(
                statePayload(
                  folderName: 'Clawnsole',
                  state: 'connected',
                  generations: <Map<String, Object?>>[driveGeneration()],
                ),
              ),
              200,
            );
          }
          return http.Response('{}', 404);
        }),
      );

      await gateway.load();
      final resumed = await gateway.resumeGoogleDrive();

      expect(resumed, isNotNull);
      expect(refreshBodies.single['accessToken'], 'silent-token');
      expect(authorizer.interactiveCalls, 0);
      expect(gateway.googleDriveConnection.isConnected, isTrue);
      expect(resumed!.generations.single.localId, 'drive-film');
    },
  );

  test('resume stays quiet when no silent grant exists', () async {
    var refreshCalls = 0;
    final authorizer = _FakeAuthorizer(silentToken: null);
    final gateway = WebGateway(
      baseUrl: Uri.parse('http://127.0.0.1:9999/'),
      driveAuthorizer: authorizer,
      settingsVaultInvoker: (_, _) async => <String, Object?>{'ok': true},
      client: MockClient((request) async {
        if (request.url.path == '/state') {
          return http.Response(
            jsonEncode(statePayload(folderName: 'Clawnsole')),
            200,
          );
        }
        if (request.url.path == '/drive/refresh') refreshCalls += 1;
        return http.Response('{}', 404);
      }),
    );

    await gateway.load();

    expect(await gateway.resumeGoogleDrive(), isNull);
    expect(refreshCalls, 0);
    expect(authorizer.silentCalls, 1);
    expect(authorizer.interactiveCalls, 0);
  });

  test('resume skips libraries that never connected Drive', () async {
    final authorizer = _FakeAuthorizer(silentToken: 'silent-token');
    final gateway = WebGateway(
      baseUrl: Uri.parse('http://127.0.0.1:9999/'),
      driveAuthorizer: authorizer,
      settingsVaultInvoker: (_, _) async => <String, Object?>{'ok': true},
      client: MockClient(
        (request) async =>
            http.Response(jsonEncode(statePayload(folderName: '')), 200),
      ),
    );

    await gateway.load();

    expect(await gateway.resumeGoogleDrive(), isNull);
    expect(authorizer.silentCalls, 0);
  });
}

class _FakeAuthorizer implements GoogleDriveAuthorizer {
  _FakeAuthorizer({required this.silentToken});

  final String? silentToken;
  int silentCalls = 0;
  int interactiveCalls = 0;

  @override
  bool get isAvailable => true;

  @override
  String get unavailableMessage => '';

  @override
  Future<String> authorize() async {
    interactiveCalls += 1;
    return 'interactive-token';
  }

  @override
  Future<String?> authorizeSilently() async {
    silentCalls += 1;
    return silentToken;
  }

  @override
  Future<void> disconnect() async {}
}
