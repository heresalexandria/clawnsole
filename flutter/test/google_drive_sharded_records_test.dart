import 'dart:convert';
import 'dart:typed_data';

import 'package:clawnsole/core/google_drive.dart';
import 'package:clawnsole/core/google_drive_store.dart';
import 'package:clawnsole/core/models.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  final created = DateTime.utc(2026, 8, 26, 9);

  Generation generation(
    String id, {
    String status = 'Pending',
    DateTime? updatedAt,
    int statusCheckCount = 0,
    DateTime? lastCheckedAt,
    AssetReference? resultAsset,
  }) => Generation(
    localId: id,
    status: status,
    prompt: id,
    mode: VideoMode.t2v,
    config: const GenerationConfig(
      aspectRatio: '16:9',
      duration: 8,
      resolution: 'hd',
      generateAudio: true,
      safetyTolerance: 2,
      draft: false,
    ),
    createdAt: created,
    updatedAt: updatedAt ?? created,
    pollingUrl: 'https://provider.example/poll/$id',
    statusCheckCount: statusCheckCount,
    lastCheckedAt: lastCheckedAt,
    resultAsset: resultAsset,
  );

  (GoogleDriveStore, _Clock) storeFor(_FakeDrive drive) {
    final clock = _Clock(created);
    final client = drive.client();
    return (
      GoogleDriveStore(
        client: client,
        clock: () => clock.now,
        apiFactory: (token) => GoogleDriveApi(
          accessToken: token,
          apiBase: Uri.parse('https://drive.test/drive/v3/'),
          uploadBase: Uri.parse('https://drive.test/upload/drive/v3/'),
          client: client,
        ),
      ),
      clock,
    );
  }

  test('generations publish as record files with a legacy mirror', () async {
    final drive = _FakeDrive();
    final (store, _) = storeFor(drive);
    await store.connect('token', 'Shared Studio');

    final reference = SavedReference(
      id: 'ref-1',
      name: 'Subject',
      kind: MediaReferenceKind.image,
      asset: const AssetReference(kind: 'drive', value: 'file-1', label: 's'),
      createdAt: created,
      updatedAt: created,
      storage: LibraryStorage.drive,
    );
    await store.write(
      StoredData(
        generations: <Generation>[generation('gen-1')],
        savedReferences: <SavedReference>[reference],
      ),
    );

    final records = drive.filesWithProperty('clawnsoleGeneration');
    expect(records, hasLength(1));
    expect(records.single.name, 'gen-1.json');
    final stateBody = StoredData.decode(utf8.decode(drive.stateFile!.bytes));
    expect(
      stateBody.generations.single.localId,
      'gen-1',
      reason: 'older clients keep reading generations from the state file',
    );
    expect(stateBody.savedReferences.single.id, 'ref-1');
  });

  test('poll bookkeeping updates only the record file', () async {
    final drive = _FakeDrive();
    final (store, _) = storeFor(drive);
    await store.connect('token', 'Shared Studio');
    await store.write(StoredData(generations: <Generation>[generation('g')]));
    final stateVersion = drive.stateFile!.version;
    final recordVersion = drive
        .filesWithProperty('clawnsoleGeneration')
        .single
        .version;

    await store.write(
      StoredData(
        generations: <Generation>[
          generation(
            'g',
            statusCheckCount: 3,
            lastCheckedAt: created.add(const Duration(seconds: 30)),
            updatedAt: created.add(const Duration(seconds: 30)),
          ),
        ],
      ),
    );

    expect(
      drive.stateFile!.version,
      stateVersion,
      reason: 'bookkeeping churn must not rewrite the shared state file',
    );
    expect(
      drive.filesWithProperty('clawnsoleGeneration').single.version,
      greaterThan(recordVersion),
    );
  });

  test('a second device sees records published by the first', () async {
    final drive = _FakeDrive();
    final (first, _) = storeFor(drive);
    final (second, secondClock) = storeFor(drive);
    await first.connect('token', 'Shared Studio');
    await second.connect('token', 'Shared Studio');

    await first.write(StoredData(generations: <Generation>[generation('a')]));
    secondClock.advance(const Duration(seconds: 20));
    expect((await second.read()).generations.single.localId, 'a');

    await first.write(
      StoredData(generations: <Generation>[generation('a'), generation('b')]),
    );
    secondClock.advance(const Duration(seconds: 20));
    expect((await second.read()).generations, hasLength(2));

    // Deleting on the first device removes the record file and the mirror
    // entry, so the second device converges to the deletion too.
    await first.write(StoredData(generations: <Generation>[generation('b')]));
    secondClock.advance(const Duration(seconds: 20));
    expect((await second.read()).generations.single.localId, 'b');
    expect(drive.filesWithProperty('clawnsoleGeneration'), hasLength(1));
  });

  test('concurrent updates to one record keep the delivered film', () async {
    final drive = _FakeDrive();
    final (first, _) = storeFor(drive);
    final (second, secondClock) = storeFor(drive);
    await first.connect('token', 'Shared Studio');
    await second.connect('token', 'Shared Studio');
    await first.write(StoredData(generations: <Generation>[generation('g')]));
    secondClock.advance(const Duration(seconds: 20));
    await second.read();

    const film = AssetReference(kind: 'drive', value: 'film-1', label: 'f');
    // The first device lands the result; its updatedAt is OLDER than the
    // second device's later bookkeeping poll (clock skew shape).
    await first.write(
      StoredData(
        generations: <Generation>[
          generation(
            'g',
            status: 'Ready',
            resultAsset: film,
            updatedAt: created.add(const Duration(seconds: 5)),
          ),
        ],
      ),
    );
    await second.write(
      StoredData(
        generations: <Generation>[
          generation(
            'g',
            statusCheckCount: 2,
            updatedAt: created.add(const Duration(minutes: 1)),
          ),
        ],
      ),
    );

    final record = drive.filesWithProperty('clawnsoleGeneration').single;
    final persisted = Generation.fromJson(
      (jsonDecode(utf8.decode(record.bytes)) as Map<Object?, Object?>).map(
        (key, value) => MapEntry(key.toString(), value),
      ),
    );
    expect(
      persisted.resultAsset,
      isNotNull,
      reason: 'the losing bookkeeping write must adopt the delivered record',
    );
    expect((await second.read()).generations.single.resultAsset, isNotNull);
  });

  test('a legacy single-file library is absorbed and published', () async {
    final drive = _FakeDrive();
    // A schema-2 library: generations only exist inside the state file.
    drive.seedStateFile(
      StoredData(generations: <Generation>[generation('legacy-1')]).encode(),
    );
    final (store, _) = storeFor(drive);

    final connected = await store.connect('token', 'Shared Studio');
    expect(connected.generations.single.localId, 'legacy-1');
    expect(drive.filesWithProperty('clawnsoleGeneration'), isEmpty);

    // The first write migrates: the legacy generation gains a record file.
    await store.write(connected);
    expect(
      drive.filesWithProperty('clawnsoleGeneration').single.name,
      'legacy-1.json',
    );
  });

  test('duplicate record files for one generation are reconciled', () async {
    final drive = _FakeDrive();
    final (store, _) = storeFor(drive);
    await store.connect('token', 'Shared Studio');
    final recordsFolder = drive.filesWithProperty('clawnsoleRecords').single.id;
    // Two devices raced to publish the same absorbed generation; the newer
    // duplicate carries the delivered result.
    const film = AssetReference(kind: 'drive', value: 'film-1', label: 'f');
    for (final version in <Generation>[
      generation('dup'),
      generation('dup', status: 'Ready', resultAsset: film),
    ]) {
      drive.addRecord(recordsFolder, jsonEncode(version.toJson()));
    }

    final data = await store.read();

    expect(data.generations.single.resultAsset, isNotNull);
    expect(
      drive.filesWithProperty('clawnsoleGeneration'),
      hasLength(1),
      reason: 'the losing duplicate file is cleared',
    );
  });

  test('a legacy client writing the state file is absorbed', () async {
    final drive = _FakeDrive();
    final (store, clock) = storeFor(drive);
    await store.connect('token', 'Shared Studio');
    await store.write(StoredData(generations: <Generation>[generation('a')]));

    // An old client rewrites the whole state file, adding a generation the
    // sharded layout has never seen.
    final legacy = StoredData(
      generations: <Generation>[generation('a'), generation('from-legacy')],
    );
    drive.seedStateFile(legacy.encode(), replace: true);

    clock.advance(const Duration(seconds: 20));
    final data = await store.read();
    expect(
      data.generations.map((item) => item.localId),
      containsAll(<String>['a', 'from-legacy']),
    );

    // The next write publishes the absorbed record as its own file.
    await store.write(data);
    expect(
      drive.filesWithProperty('clawnsoleGeneration').map((file) => file.name),
      containsAll(<String>['a.json', 'from-legacy.json']),
    );
  });
}

class _Clock {
  _Clock(this.now);

  DateTime now;

  void advance(Duration by) => now = now.add(by);
}

class _FakeFile {
  _FakeFile({
    required this.id,
    required this.name,
    required this.mimeType,
    required this.bytes,
    this.parent,
    this.appProperties = const <String, String>{},
  });

  final String id;
  String name;
  final String mimeType;
  final String? parent;
  final Map<String, String> appProperties;
  Uint8List bytes;
  int version = 1;

  String get etag => '$id-v$version';
  String get md5Hash => md5.convert(bytes).toString();

  Map<String, Object?> toListing() => <String, Object?>{
    'id': id,
    'name': name,
    'mimeType': mimeType,
    'size': '${bytes.length}',
    'modifiedTime': '2026-08-26T09:00:00Z',
    'md5Checksum': md5Hash,
    'appProperties': appProperties,
  };
}

/// An in-memory Drive backend covering the REST subset GoogleDriveApi emits:
/// query listings, multipart create, media update with If-Match, media get
/// with If-None-Match, and delete.
class _FakeDrive {
  final Map<String, _FakeFile> files = <String, _FakeFile>{};
  int _counter = 0;

  _FakeFile? get stateFile => files.values
      .where((file) => file.appProperties.containsKey('clawnsoleState'))
      .firstOrNull;

  List<_FakeFile> filesWithProperty(String key) => files.values
      .where((file) => file.appProperties.containsKey(key))
      .toList();

  void addRecord(String recordsFolderId, String body) {
    _create(
      name: 'record.json',
      mimeType: 'application/json',
      parent: recordsFolderId,
      appProperties: const <String, String>{'clawnsoleGeneration': 'true'},
      bytes: Uint8List.fromList(utf8.encode(body)),
    );
  }

  void seedStateFile(String body, {bool replace = false}) {
    final existing = stateFile;
    if (existing != null) {
      if (!replace) throw StateError('State file already seeded.');
      existing.bytes = Uint8List.fromList(utf8.encode(body));
      existing.version += 1;
      return;
    }
    final root = _create(
      name: 'Shared Studio',
      mimeType: 'application/vnd.google-apps.folder',
      appProperties: const <String, String>{'clawnsoleRoot': 'true'},
      bytes: Uint8List(0),
    );
    _create(
      name: clawnsoleDriveStateFile,
      mimeType: 'application/json',
      parent: root.id,
      appProperties: const <String, String>{'clawnsoleState': 'true'},
      bytes: Uint8List.fromList(utf8.encode(body)),
    );
  }

  _FakeFile _create({
    required String name,
    required String mimeType,
    required Uint8List bytes,
    String? parent,
    Map<String, String> appProperties = const <String, String>{},
  }) {
    final file = _FakeFile(
      id: 'file-${_counter++}',
      name: name,
      mimeType: mimeType,
      parent: parent,
      appProperties: Map<String, String>.from(appProperties),
      bytes: bytes,
    );
    files[file.id] = file;
    return file;
  }

  MockClient client() => MockClient((request) async {
    final path = request.url.path;
    final method = request.method;
    if (method == 'GET' && path.endsWith('/drive/v3/files')) {
      return _list(request);
    }
    if (method == 'POST' && path.endsWith('/upload/drive/v3/files')) {
      return _createUpload(request);
    }
    if (method == 'POST' && path.endsWith('/drive/v3/files')) {
      return _createFolder(request);
    }
    if (method == 'PATCH' && path.contains('/upload/drive/v3/files/')) {
      return _updateUpload(request);
    }
    final fileId = path.split('/').last;
    if (method == 'GET' && request.url.queryParameters['alt'] == 'media') {
      final file = files[fileId];
      if (file == null) return _error(404, 'notFound', 'File not found');
      if (request.headers['If-None-Match'] == file.etag) {
        return http.Response('', 304);
      }
      return http.Response.bytes(
        file.bytes,
        200,
        headers: <String, String>{'etag': file.etag},
      );
    }
    if (method == 'DELETE') {
      return files.remove(fileId) == null
          ? _error(404, 'notFound', 'File not found')
          : http.Response('', 204);
    }
    throw StateError('Unexpected Drive request: $method ${request.url}');
  });

  http.Response _list(http.Request request) {
    final query = request.url.queryParameters['q'] ?? '';
    final parent = RegExp(r"'([^']+)' in parents").firstMatch(query)?.group(1);
    final property = RegExp(
      r"appProperties has \{ key='([^']+)'",
    ).firstMatch(query)?.group(1);
    final name = RegExp(r"name = '([^']+)'").firstMatch(query)?.group(1);
    final matches = files.values.where((file) {
      if (parent != null && file.parent != parent) return false;
      if (property != null && !file.appProperties.containsKey(property)) {
        return false;
      }
      if (name != null && file.name != name) return false;
      return true;
    });
    return http.Response(
      jsonEncode(<String, Object?>{
        'files': matches.map((file) => file.toListing()).toList(),
      }),
      200,
      headers: const <String, String>{'content-type': 'application/json'},
    );
  }

  http.Response _createFolder(http.Request request) {
    final metadata = jsonDecode(request.body) as Map<String, dynamic>;
    final file = _create(
      name: metadata['name'] as String,
      mimeType: metadata['mimeType'] as String? ?? 'application/octet-stream',
      parent: (metadata['parents'] as List<dynamic>?)?.first as String?,
      appProperties:
          ((metadata['appProperties'] as Map<String, dynamic>?) ??
                  const <String, dynamic>{})
              .map((key, value) => MapEntry(key, value.toString())),
      bytes: Uint8List(0),
    );
    return _metadataResponse(file);
  }

  http.Response _createUpload(http.Request request) {
    final (metadata, content) = _parseMultipart(request);
    final file = _create(
      name: metadata['name'] as String,
      mimeType: 'application/json',
      parent: (metadata['parents'] as List<dynamic>?)?.first as String?,
      appProperties:
          ((metadata['appProperties'] as Map<String, dynamic>?) ??
                  const <String, dynamic>{})
              .map((key, value) => MapEntry(key, value.toString())),
      bytes: content,
    );
    return _metadataResponse(file);
  }

  http.Response _updateUpload(http.Request request) {
    final fileId = request.url.pathSegments.last;
    final file = files[fileId];
    if (file == null) return _error(404, 'notFound', 'File not found');
    final expected = request.headers['If-Match'];
    if (expected != null && expected != file.etag) {
      return _error(412, 'conditionNotMet', 'Precondition failed');
    }
    file.bytes = request.bodyBytes;
    file.version += 1;
    return _metadataResponse(file);
  }

  (Map<String, dynamic>, Uint8List) _parseMultipart(http.Request request) {
    final contentType =
        request.headers['Content-Type'] ?? request.headers['content-type']!;
    final boundary = contentType.split('boundary=').last;
    final body = utf8.decode(request.bodyBytes);
    final parts = body
        .split('--$boundary')
        .where((part) => part.trim().isNotEmpty && part.trim() != '--')
        .toList();
    String payload(String part) {
      final separator = part.indexOf('\r\n\r\n');
      var value = part.substring(separator + 4);
      if (value.endsWith('\r\n')) {
        value = value.substring(0, value.length - 2);
      }
      return value;
    }

    return (
      jsonDecode(payload(parts[0])) as Map<String, dynamic>,
      Uint8List.fromList(utf8.encode(payload(parts[1]))),
    );
  }

  http.Response _metadataResponse(_FakeFile file) => http.Response(
    jsonEncode(<String, Object?>{
      'id': file.id,
      'name': file.name,
      'mimeType': file.mimeType,
      'size': '${file.bytes.length}',
      'modifiedTime': '2026-08-26T09:00:00Z',
    }),
    200,
    headers: <String, String>{
      'content-type': 'application/json',
      'etag': file.etag,
    },
  );

  http.Response _error(int status, String reason, String message) =>
      http.Response(
        jsonEncode(<String, Object?>{
          'error': <String, Object?>{
            'message': message,
            'errors': <Object?>[
              <String, Object?>{'reason': reason},
            ],
          },
        }),
        status,
        headers: const <String, String>{'content-type': 'application/json'},
      );
}

extension<T> on Iterable<T> {
  T? get firstOrNull => this.isEmpty ? null : first;
}
