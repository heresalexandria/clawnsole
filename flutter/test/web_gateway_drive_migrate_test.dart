import 'dart:convert';

import 'package:clawnsole/core/models.dart';
import 'package:clawnsole/core/web_gateway.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  test(
    'WebGateway migrates the local library through /drive/migrate',
    () async {
      final requests = <http.Request>[];
      final gateway = WebGateway(
        baseUrl: Uri.parse('http://127.0.0.1:8787'),
        client: MockClient((request) async {
          requests.add(request);
          return http.Response(
            jsonEncode(<String, Object?>{
              'snapshot': <String, Object?>{
                ...const LocalSnapshot(
                  generations: <Generation>[],
                  preferences: AppPreferences(),
                  hasApiKey: false,
                  storage: StorageStats(
                    path: 'companion',
                    bytes: 0,
                    records: 0,
                  ),
                ).toJson(),
                'driveConnection': <String, Object?>{
                  'state': 'connected',
                  'folderName': 'Portable Studio',
                  'folderId': 'drive-root',
                  'message': '',
                },
              },
              'generations': 2,
              'references': 1,
            }),
            200,
            headers: const <String, String>{'content-type': 'application/json'},
          );
        }),
      );

      final moved = await gateway.moveLocalLibraryToGoogleDrive();

      expect(requests.single.method, 'POST');
      expect(requests.single.url.path, '/drive/migrate');
      expect(moved.generations, 2);
      expect(moved.references, 1);
      expect(gateway.googleDriveConnection.folderName, 'Portable Studio');
    },
  );

  test('data-folder capabilities stay off outside the desktop shell', () {
    final gateway = WebGateway(baseUrl: Uri.parse('http://127.0.0.1:8787'));
    expect(gateway.supportsRevealDataFolder, isFalse);
    expect(gateway.supportsDataRelocation, isFalse);
    expect(gateway.shellManagesDataRelocation, isFalse);
  });
}
