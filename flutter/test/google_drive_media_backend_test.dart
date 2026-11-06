import 'dart:convert';

import 'package:clawnsole/core/asset_stream.dart';
import 'package:clawnsole/core/google_drive.dart';
import 'package:clawnsole/core/google_drive_media_backend.dart';
import 'package:clawnsole/core/models.dart';
import 'package:clawnsole/core/temporary_media_host.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

final _bytes = List<int>.generate(96, (index) => index);
final _lease = TemporaryMediaLease(
  id: 'lease-one',
  operationId: 'operation-one',
  scopeId: 'library-one',
  provider: 'apipod',
  model: 'seedance-2.5',
  createdAt: DateTime.utc(2026, 11, 5),
  updatedAt: DateTime.utc(2026, 11, 5),
);
const _source = TemporaryMediaSource(
  source: 'file:///private/original.mp4',
  label: 'Private original.mp4',
  kind: MediaReferenceKind.video,
  contentType: 'video/mp4',
);

void main() {
  test(
    'streamed copy uses isolated private root, unlisted link, and exact anonymous bytes',
    () async {
      final drive = _FakeDrive();
      final staged = _Staged();
      final backend = _backend(drive, staged: staged);
      final copy = await backend.createCopy(_lease, _source);
      expect(staged.disposed, isTrue);
      final file = drive.files[copy.fileId]!;
      final root = drive.files[(file['parents'] as List).single]!;
      expect(root['parents'], ['root']);
      expect(root['parents'], isNot(contains('library-one')));
      expect(file['name'], isNot(contains('Private original')));
      final tags = file['appProperties'] as Map;
      expect(
        tags.keys,
        containsAll([
          'clawnsoleMediaLease',
          'clawnsoleMediaOperation',
          'clawnsoleMediaScope',
        ]),
      );
      final share = await backend.shareCopy(_lease, copy);
      expect(share.url, contains('resourcekey=keep-this-key'));
      expect(share.permissionId, 'public');
      expect(drive.lastPermissionBody, {
        'type': 'anyone',
        'role': 'reader',
        'allowFileDiscovery': false,
      });
      expect(drive.lastPermissionQuery, {
        'fields': 'id,type,role,allowFileDiscovery',
      });
      await backend.releaseCopy(_lease, copy);
      expect(drive.permissions[copy.fileId], [_owner]);
      expect(file['trashed'], isTrue);
      expect(drive.files['original']!['trashed'], isFalse);
      expect(drive.permissions['original'], [_owner]);
      expect(root['trashed'], isFalse);
    },
  );

  test('scope mismatch and original file IDs never mutate Drive', () async {
    final drive = _FakeDrive();
    final wrong = _backend(drive, scope: 'another-library');
    await expectLater(wrong.createCopy(_lease, _source), throwsStateError);
    expect(drive.calls, 0);
    final backend = _backend(drive);
    await expectLater(
      backend.releaseCopy(_lease, const TemporaryMediaCopy(fileId: 'original')),
      throwsStateError,
    );
    expect(drive.files.length, 1);
    expect(drive.files['original']!['trashed'], isFalse);
  });

  test(
    'lost upload response is recovered by lease tags and disposed locally',
    () async {
      final drive = _FakeDrive()..loseUploadResponse = true;
      final staged = _Staged();
      final backend = _backend(drive, staged: staged);
      await expectLater(
        backend.createCopy(_lease, _source),
        throwsA(isA<http.ClientException>()),
      );
      expect(staged.disposed, isTrue);
      final copies = await backend.findCopies(_lease);
      expect(copies, hasLength(1));
      await backend.releaseCopy(_lease, copies.single);
      expect(drive.files[copies.single.fileId]!['trashed'], isTrue);
      expect(await backend.findCopies(_lease), isEmpty);
    },
  );

  test(
    'lost permission response is revoked without a persisted permission ID',
    () async {
      final drive = _FakeDrive()..losePermissionResponse = true;
      final backend = _backend(drive);
      final copy = await backend.createCopy(_lease, _source);
      await expectLater(
        backend.shareCopy(_lease, copy),
        throwsA(isA<http.ClientException>()),
      );
      expect(_lease.permissionId, isNull);
      expect(drive.permissions[copy.fileId], hasLength(2));
      await backend.releaseCopy(_lease, copy);
      expect(drive.permissions[copy.fileId], [_owner]);
      expect(drive.files[copy.fileId]!['trashed'], isTrue);
    },
  );

  test(
    'public login HTML and corrupt media cannot become provider inputs',
    () async {
      for (final html in [true, false]) {
        final drive = _FakeDrive();
        final backend = _backend(
          drive,
          publicClient: MockClient(
            (_) async => http.Response(
              html ? '<html>Sign in</html>' : 'wrong video bytes',
              200,
              headers: {'content-type': html ? 'text/html' : 'video/mp4'},
            ),
          ),
        );
        final copy = await backend.createCopy(_lease, _source);
        await expectLater(backend.shareCopy(_lease, copy), throwsA(anything));
        await backend.releaseCopy(_lease, copy);
        expect(drive.permissions[copy.fileId], [_owner]);
      }
    },
  );

  test(
    'shared staging folder blocks further uploads without changing its ACL',
    () async {
      final drive = _FakeDrive();
      final backend = _backend(drive);
      final first = await backend.createCopy(_lease, _source);
      final root =
          (drive.files[first.fileId]!['parents'] as List).single as String;
      drive.permissions[root]!.add(_public);
      final before = drive.files.length;
      await expectLater(backend.createCopy(_lease, _source), throwsStateError);
      expect(drive.files.length, before);
      expect(drive.permissions[root], [_owner, _public]);
    },
  );

  test(
    'failed privacy verification retains the copy for cleanup retry',
    () async {
      final drive = _FakeDrive()..ignorePermissionDeletion = true;
      final backend = _backend(drive);
      final copy = await backend.createCopy(_lease, _source);
      await backend.shareCopy(_lease, copy);
      await expectLater(backend.releaseCopy(_lease, copy), throwsStateError);
      expect(drive.files[copy.fileId]!['trashed'], isFalse);
      drive.ignorePermissionDeletion = false;
      await backend.releaseCopy(_lease, copy);
      expect(drive.files[copy.fileId]!['trashed'], isTrue);
    },
  );

  test(
    'cleanup handles deleted copy and a moved private staging copy',
    () async {
      final drive = _FakeDrive();
      final backend = _backend(drive);
      await backend.releaseCopy(
        _lease,
        const TemporaryMediaCopy(fileId: 'gone'),
      );
      final copy = await backend.createCopy(_lease, _source);
      await backend.shareCopy(_lease, copy);
      drive.files[copy.fileId]!['parents'] = ['a-different-private-folder'];
      await backend.releaseCopy(_lease, copy);
      expect(drive.files[copy.fileId]!['trashed'], isTrue);
    },
  );

  test(
    'permission listing follows every page before determining privacy',
    () async {
      final urls = <Uri>[];
      final api = GoogleDriveApi(
        accessToken: 'test-token',
        client: MockClient((request) async {
          urls.add(request.url);
          return http.Response(
            jsonEncode(
              request.url.queryParameters['pageToken'] == null
                  ? {
                      'permissions': [_owner],
                      'nextPageToken': 'next',
                    }
                  : {
                      'permissions': [_public],
                    },
            ),
            200,
          );
        }),
      );
      expect(await api.listPermissions('file'), hasLength(2));
      expect(urls.last.queryParameters['pageToken'], 'next');
    },
  );

  test(
    'cleanup finds externally trashed copies after a lost response',
    () async {
      final drive = _FakeDrive();
      final backend = _backend(drive);
      final copy = await backend.createCopy(_lease, _source);
      await backend.shareCopy(_lease, copy);
      drive.files[copy.fileId]!['trashed'] = true;
      final cleanup = _lease.copyWith(
        state: TemporaryMediaLeaseState.cleanupPending,
        updatedAt: DateTime.utc(2026, 11, 6),
      );
      final recovered = await backend.findCopies(cleanup);
      expect(recovered.single.fileId, copy.fileId);
      await backend.releaseCopy(cleanup, recovered.single);
      expect(drive.permissions[copy.fileId], [_owner]);
    },
  );
  test(
    'returns verified final download URI with resource parameters intact',
    () async {
      final drive = _FakeDrive();
      final finalUri = Uri.parse(
        'https://drive.usercontent.google.com/download?id=file-2&export=download&resourcekey=keep-this-key',
      );
      final backend = _backend(
        drive,
        publicClient: MockClient(
          (_) async => http.Response.bytes(
            _bytes,
            200,
            headers: {'content-type': 'video/mp4'},
            request: http.Request('GET', finalUri),
          ),
        ),
      );
      final copy = await backend.createCopy(_lease, _source);
      final share = await backend.shareCopy(_lease, copy);
      expect(share.url, finalUri.toString());
    },
  );
}

GoogleDriveMediaBackend _backend(
  _FakeDrive drive, {
  _Staged? staged,
  String scope = 'library-one',
  http.Client? publicClient,
}) => GoogleDriveMediaBackend(
  scopeId: () => scope,
  api: () => drive.api,
  stageSource: (_) async => staged ?? _Staged(),
  publicClient:
      publicClient ??
      MockClient((request) async {
        expect(
          request.headers.keys.map((key) => key.toLowerCase()),
          isNot(contains('authorization')),
        );
        expect(request.url.queryParameters['resourcekey'], 'keep-this-key');
        return http.Response.bytes(
          _bytes,
          200,
          headers: {'content-type': 'video/mp4'},
        );
      }),
);

class _Staged extends StagedAsset {
  bool disposed = false;
  @override
  String get path => '/private/staging.mp4';
  @override
  int get length => _bytes.length;
  @override
  String get sha256 => sha256Digest;
  String get sha256Digest => sha256Value(_bytes);
  @override
  Stream<List<int>> openRead() => Stream.value(_bytes);
  @override
  Future<void> dispose() async {
    disposed = true;
  }
}

String sha256Value(List<int> bytes) => sha256.convert(bytes).toString();
const _owner = <String, Object?>{
  'id': 'owner',
  'type': 'user',
  'role': 'owner',
};
const _public = <String, Object?>{
  'id': 'public',
  'type': 'anyone',
  'role': 'reader',
  'allowFileDiscovery': false,
};

class _FakeDrive {
  _FakeDrive() {
    api = GoogleDriveApi(
      accessToken: 'private-token',
      client: MockClient(_handle),
    );
  }
  late GoogleDriveApi api;
  final files = <String, Map<String, Object?>>{
    'original': {
      'id': 'original',
      'name': 'original.mp4',
      'mimeType': 'video/mp4',
      'ownedByMe': true,
      'trashed': false,
      'parents': ['library-one'],
      'appProperties': <String, Object?>{},
    },
  };
  final permissions = <String, List<Map<String, Object?>>>{
    'original': [_owner],
  };
  int calls = 0;
  bool loseUploadResponse = false;
  bool losePermissionResponse = false;
  bool ignorePermissionDeletion = false;
  Map<String, Object?>? lastPermissionBody;
  Map<String, String>? lastPermissionQuery;

  http.Response _json(Object value, [int status = 200]) =>
      http.Response(jsonEncode(value), status);
  Future<http.Response> _handle(http.Request request) async {
    calls++;
    expect(request.headers['Authorization'], 'Bearer private-token');
    final segments = request.url.pathSegments;
    final fileIndex = segments.indexOf('files');
    final id = segments.length > fileIndex + 1 ? segments[fileIndex + 1] : null;
    if (request.url.path.startsWith('/upload/')) {
      final body = latin1.decode(request.bodyBytes);
      final metadata = Map<String, Object?>.from(
        jsonDecode(body.split('\r\n\r\n')[1].split('\r\n--')[0]) as Map,
      );
      final file = _create(metadata, 'video/mp4');
      if (loseUploadResponse) throw http.ClientException('response lost');
      return _json(file);
    }
    if (id == null) {
      if (request.method == 'POST') {
        return _json(
          _create(
            Map<String, Object?>.from(jsonDecode(request.body) as Map),
            'application/vnd.google-apps.folder',
          ),
        );
      }
      final query = request.url.queryParameters['q']!;
      final tags = RegExp(
        "key='([^']*)' and value='([^']*)'",
      ).allMatches(query);
      return _json({
        'files': files.values.where((file) {
          if (query.contains('trashed = false') && file['trashed'] == true) {
            return false;
          }
          if (query.contains("'root' in parents") &&
              !(file['parents'] as List).contains('root')) {
            return false;
          }
          return tags.every(
            (tag) => (file['appProperties'] as Map)[tag[1]] == tag[2],
          );
        }).toList(),
      });
    }
    final file = files[id];
    if (file == null) {
      return _json({
        'error': {'message': 'missing'},
      }, 404);
    }
    if (segments.contains('permissions')) {
      if (request.method == 'GET') {
        return _json({'permissions': permissions[id]});
      }
      if (request.method == 'POST') {
        lastPermissionBody = Map<String, Object?>.from(
          jsonDecode(request.body) as Map,
        );
        lastPermissionQuery = request.url.queryParameters;
        permissions[id]!.add(_public);
        if (losePermissionResponse) throw http.ClientException('response lost');
        return _json(_public);
      }
      if (request.method == 'DELETE') {
        if (!ignorePermissionDeletion) {
          permissions[id]!.removeWhere(
            (permission) => permission['id'] == segments.last,
          );
        }
        return http.Response('', 204);
      }
    }
    if (request.method == 'PATCH') {
      expect(jsonDecode(request.body), {'trashed': true});
      file['trashed'] = true;
    }
    return _json(file);
  }

  Map<String, Object?> _create(Map<String, Object?> metadata, String type) {
    final id = 'file-${files.length}';
    final file = <String, Object?>{
      ...metadata,
      'id': id,
      'ownedByMe': true,
      'trashed': false,
      'mimeType': type,
      'size': '${_bytes.length}',
      'webContentLink':
          'https://drive.google.com/uc?export=download&id=$id&resourcekey=keep-this-key',
    };
    files[id] = file;
    permissions[id] = [_owner];
    return file;
  }
}
