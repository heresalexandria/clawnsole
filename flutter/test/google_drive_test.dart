import 'dart:convert';
import 'dart:typed_data';

import 'package:clawnsole/core/google_drive.dart';
import 'package:clawnsole/core/models.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  test('portable Drive metadata excludes every provider credential', () {
    final portable = googleDrivePortableData(
      const StoredData(
        apiKey: 'bfl-secret',
        apiKeys: <String, String>{'bfl': 'bfl-secret', 'ltx': 'ltx-secret'},
        rejectedIosReviewApiKeyId: 'review-id',
        rejectedIosReviewApiKeyIds: <String, String>{'ltx': 'review-ltx'},
        preferences: AppPreferences(provider: 'ltx'),
      ),
    );

    expect(portable.apiKeys, isEmpty);
    expect(portable.apiKey, isEmpty);
    expect(portable.rejectedIosReviewApiKeyIds, isEmpty);
    expect(portable.preferences.provider, 'ltx');
    expect(portable.encode(), isNot(contains('secret')));
    expect(portable.encode(), isNot(contains('review-id')));
  });

  test('Drive merge preserves unrelated changes from another device', () {
    final now = DateTime.utc(2026, 8, 19, 12);
    Generation generation(String id, String prompt, [int minutes = 0]) =>
        Generation(
          localId: id,
          status: 'Ready',
          prompt: prompt,
          mode: VideoMode.t2v,
          config: const GenerationConfig(
            aspectRatio: '16:9',
            duration: 8,
            resolution: 'hd',
            generateAudio: true,
            safetyTolerance: 2,
            draft: false,
          ),
          createdAt: now.add(Duration(minutes: minutes)),
          updatedAt: now.add(Duration(minutes: minutes)),
        );

    final original = generation('one', 'Original');
    final localEdit = generation('one', 'Edited here');
    final remoteAddition = generation('two', 'Created elsewhere', 1);
    final merged = mergeGoogleDriveData(
      base: StoredData(
        apiKeys: const <String, String>{'bfl': 'device-key'},
        preferences: const AppPreferences(provider: 'bfl'),
        generations: <Generation>[original],
      ),
      next: StoredData(
        apiKeys: const <String, String>{'bfl': 'device-key'},
        preferences: const AppPreferences(provider: 'bfl'),
        generations: <Generation>[localEdit],
      ),
      remote: StoredData(
        preferences: const AppPreferences(provider: 'ltx'),
        generations: <Generation>[remoteAddition, original],
      ),
    );

    expect(merged.generations.map((item) => item.localId), <String>[
      'two',
      'one',
    ]);
    expect(
      merged.generations.singleWhere((item) => item.localId == 'one').prompt,
      'Edited here',
    );
    expect(merged.preferences.provider, 'ltx');
    expect(merged.apiKeyFor('bfl'), 'device-key');
  });

  test('Drive folder lookup is app-scoped and authenticated', () async {
    late http.Request observed;
    final api = GoogleDriveApi(
      accessToken: 'short-lived-token',
      apiBase: Uri.parse('https://drive.test/drive/v3/'),
      uploadBase: Uri.parse('https://drive.test/upload/drive/v3/'),
      client: MockClient((request) async {
        observed = request;
        return http.Response(
          jsonEncode(<String, Object?>{
            'files': <Object?>[
              <String, Object?>{
                'id': 'folder-one',
                'name': 'Shared Studio',
                'mimeType': 'application/vnd.google-apps.folder',
              },
            ],
          }),
          200,
          headers: const <String, String>{'content-type': 'application/json'},
        );
      }),
    );

    final folder = await api.findRootFolder('Shared Studio');

    expect(folder?.id, 'folder-one');
    expect(observed.headers['Authorization'], 'Bearer short-lived-token');
    expect(observed.url.queryParameters['q'], contains('clawnsoleRoot'));
    expect(observed.url.queryParameters['q'], contains('Shared Studio'));
    expect(observed.url.queryParameters['spaces'], 'drive');
  });

  test(
    'Drive asset upload uses multipart content and its selected parent',
    () async {
      late http.Request observed;
      final api = GoogleDriveApi(
        accessToken: 'token',
        apiBase: Uri.parse('https://drive.test/drive/v3/'),
        uploadBase: Uri.parse('https://drive.test/upload/drive/v3/'),
        client: MockClient((request) async {
          observed = request;
          return http.Response(
            jsonEncode(<String, Object?>{
              'id': 'asset-one',
              'name': 'clip.mp4',
              'mimeType': 'video/mp4',
              'size': '4',
            }),
            200,
            headers: const <String, String>{'etag': 'asset-etag'},
          );
        }),
      );

      final file = await api.createFile(
        parentId: 'assets-folder',
        name: 'clip.mp4',
        bytes: Uint8List.fromList(<int>[0, 1, 2, 3]),
        contentType: 'video/mp4',
        appProperties: const <String, String>{'clawnsoleAsset': 'true'},
      );

      expect(file.id, 'asset-one');
      expect(file.etag, 'asset-etag');
      expect(observed.method, 'POST');
      expect(observed.url.queryParameters['uploadType'], 'multipart');
      expect(observed.headers['Content-Type'], startsWith('multipart/related'));
      final body = latin1.decode(observed.bodyBytes);
      expect(body, contains('assets-folder'));
      expect(body, contains('clawnsoleAsset'));
      expect(body, contains('video/mp4'));
    },
  );

  test('Drive errors retain status for expired-token handling', () async {
    final api = GoogleDriveApi(
      accessToken: 'expired',
      apiBase: Uri.parse('https://drive.test/drive/v3/'),
      client: MockClient(
        (_) async => http.Response(
          jsonEncode(<String, Object?>{
            'error': <String, Object?>{'message': 'Invalid credentials'},
          }),
          401,
        ),
      ),
    );

    await expectLater(
      api.downloadFile('state-file'),
      throwsA(
        isA<GoogleDriveException>()
            .having((error) => error.status, 'status', 401)
            .having((error) => error.message, 'message', 'Invalid credentials'),
      ),
    );
  });
}
