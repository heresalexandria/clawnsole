import 'dart:async';
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

  test(
    'local companion copies a retained Drive input into local storage',
    () async {
      final temporary = await Directory.systemTemp.createTemp(
        'clawnsole-cross-store-test.',
      );
      final store = CompanionStore(File('${temporary.path}/clawnsole.json'));
      try {
        final retained = await store.persistSource(
          'data:image/png;base64,AQID',
          label: 'reference.png',
          retained: const AssetReference(
            kind: 'drive',
            value: 'drive-file-id',
            label: 'reference.png',
            contentType: 'image/png',
          ),
        );

        expect(retained?.kind, 'local');
        expect(await store.readAsset(retained!), <int>[1, 2, 3]);
      } finally {
        await temporary.delete(recursive: true);
      }
    },
  );

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

  test('companion persists library folders and generation tags', () async {
    final temporary = await Directory.systemTemp.createTemp(
      'clawnsole-library-test.',
    );
    final store = CompanionStore(File('${temporary.path}/clawnsole.json'));
    final now = DateTime.utc(2026, 8, 17, 12);
    await store.replace(
      StoredData(
        generations: <Generation>[
          Generation(
            localId: 'film-one',
            status: 'Ready',
            prompt: 'A clean catalog shot.',
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
          ),
        ],
      ),
    );
    final application = CompanionApp(store: store, api: BflApi());
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final subscription = server.listen(application.handle);
    final base = Uri.parse('http://127.0.0.1:${server.port}');
    const headers = <String, String>{'Content-Type': 'application/json'};

    try {
      final folderResponse = await http.patch(
        base.resolve('/state'),
        headers: headers,
        body: jsonEncode(<String, Object?>{
          'action': 'saveLibraryFolder',
          'value': <String, Object?>{
            'id': 'folder-one',
            'name': 'Favorites',
            'createdAt': now.toIso8601String(),
          },
        }),
      );
      expect(folderResponse.statusCode, 200);

      final subfolderResponse = await http.patch(
        base.resolve('/state'),
        headers: headers,
        body: jsonEncode(<String, Object?>{
          'action': 'saveLibraryFolder',
          'value': <String, Object?>{
            'id': 'folder-child',
            'name': 'Portraits',
            'parentId': 'folder-one',
            'createdAt': now.add(const Duration(seconds: 1)).toIso8601String(),
          },
        }),
      );
      expect(subfolderResponse.statusCode, 200);

      final organizeResponse = await http.patch(
        base.resolve('/state'),
        headers: headers,
        body: jsonEncode(<String, Object?>{
          'action': 'setGenerationOrganization',
          'value': <String, Object?>{
            'localId': 'film-one',
            'folderId': 'folder-one',
            'tags': <String>['favorite', 'portrait'],
          },
        }),
      );
      expect(organizeResponse.statusCode, 200);
      final snapshot = LocalSnapshot.fromJson(
        (jsonDecode(organizeResponse.body) as Map<Object?, Object?>).map(
          (key, value) => MapEntry(key.toString(), value),
        ),
      );
      expect(snapshot.folders, hasLength(2));
      expect(
        snapshot.folders
            .singleWhere((folder) => folder.id == 'folder-child')
            .parentId,
        'folder-one',
      );
      expect(snapshot.generations.single.folderId, 'folder-one');
      expect(snapshot.generations.single.tags, <String>[
        'favorite',
        'portrait',
      ]);
    } finally {
      await subscription.cancel();
      await server.close(force: true);
      await temporary.delete(recursive: true);
    }
  });

  test('companion serves persisted preview assets after a restart', () async {
    final temporary = await Directory.systemTemp.createTemp(
      'clawnsole-preview-restart-test.',
    );
    final store = CompanionStore(File('${temporary.path}/clawnsole.json'));
    final now = DateTime.utc(2026, 8, 19, 12);
    final inputVideo = await store.writeAsset(
      base64Decode('CQ=='),
      label: 'input.mp4',
      contentType: 'video/mp4',
    );
    await store.replace(
      StoredData(
        generations: <Generation>[
          Generation(
            localId: 'preview-film',
            status: 'Ready',
            prompt: 'A retained film.',
            mode: VideoMode.i2v,
            config: GenerationConfig(
              aspectRatio: '16:9',
              duration: 8,
              resolution: 'hd',
              generateAudio: true,
              safetyTolerance: 2,
              draft: false,
              references: <MediaReferenceLabel>[
                MediaReferenceLabel(
                  label: 'input.mp4',
                  kind: MediaReferenceKind.video,
                  source: inputVideo,
                ),
              ],
            ),
            createdAt: now,
            updatedAt: now,
          ),
        ],
        savedReferences: <SavedReference>[
          SavedReference(
            id: 'preview-reference',
            name: 'Preview reference',
            kind: MediaReferenceKind.video,
            asset: inputVideo,
            createdAt: now,
            updatedAt: now,
          ),
        ],
      ),
    );

    HttpServer? server;
    StreamSubscription<HttpRequest>? subscription;
    try {
      final firstApp = CompanionApp(store: store, api: BflApi());
      server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      subscription = server.listen(firstApp.handle);
      var base = Uri.parse('http://127.0.0.1:${server.port}');
      final cached = await http.patch(
        base.resolve('/state'),
        headers: const <String, String>{'Content-Type': 'application/json'},
        body: jsonEncode(<String, Object?>{
          'action': 'saveGenerationPreviews',
          'value': <String, Object?>{
            'localId': 'preview-film',
            'thumbnail': base64Encode(<int>[1, 2, 3]),
            'timeline': base64Encode(<int>[4, 5, 6]),
          },
        }),
      );
      expect(cached.statusCode, 200);
      final outputSnapshot = LocalSnapshot.fromJson(
        (jsonDecode(cached.body) as Map<Object?, Object?>).map(
          (key, value) => MapEntry(key.toString(), value),
        ),
      );
      final thumbnail = outputSnapshot.generations.single.thumbnailAsset!;
      final timeline =
          outputSnapshot.generations.single.timelineThumbnailAsset!;
      final referenceCached = await http.patch(
        base.resolve('/state'),
        headers: const <String, String>{'Content-Type': 'application/json'},
        body: jsonEncode(<String, Object?>{
          'action': 'saveReferencePreview',
          'value': <String, Object?>{
            'referenceId': 'preview-reference',
            'thumbnail': base64Encode(<int>[7, 8]),
          },
        }),
      );
      expect(referenceCached.statusCode, 200);
      final inputCached = await http.patch(
        base.resolve('/state'),
        headers: const <String, String>{'Content-Type': 'application/json'},
        body: jsonEncode(<String, Object?>{
          'action': 'saveGenerationInputPreview',
          'value': <String, Object?>{
            'localId': 'preview-film',
            'sourceAssetValue': inputVideo.value,
            'thumbnail': base64Encode(<int>[9, 10]),
          },
        }),
      );
      expect(inputCached.statusCode, 200);
      final mediaSnapshot = LocalSnapshot.fromJson(
        (jsonDecode(inputCached.body) as Map<Object?, Object?>).map(
          (key, value) => MapEntry(key.toString(), value),
        ),
      );
      final referenceThumbnail =
          mediaSnapshot.savedReferences.single.thumbnailAsset!;
      final inputThumbnail = mediaSnapshot
          .generations
          .single
          .config
          .references!
          .single
          .thumbnailAsset!;

      await subscription.cancel();
      subscription = null;
      await server.close(force: true);
      server = null;

      final restartedApp = CompanionApp(store: store, api: BflApi());
      server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      subscription = server.listen(restartedApp.handle);
      base = Uri.parse('http://127.0.0.1:${server.port}');

      final thumbnailResponse = await http.get(
        base.resolve('/assets?id=${thumbnail.value}'),
      );
      final timelineResponse = await http.get(
        base.resolve('/assets?id=${timeline.value}'),
      );
      final referenceResponse = await http.get(
        base.resolve('/assets?id=${referenceThumbnail.value}'),
      );
      final inputResponse = await http.get(
        base.resolve('/assets?id=${inputThumbnail.value}'),
      );
      expect(thumbnailResponse.statusCode, 200);
      expect(thumbnailResponse.bodyBytes, <int>[1, 2, 3]);
      expect(timelineResponse.statusCode, 200);
      expect(timelineResponse.bodyBytes, <int>[4, 5, 6]);
      expect(referenceResponse.statusCode, 200);
      expect(referenceResponse.bodyBytes, <int>[7, 8]);
      expect(inputResponse.statusCode, 200);
      expect(inputResponse.bodyBytes, <int>[9, 10]);
    } finally {
      await subscription?.cancel();
      await server?.close(force: true);
      await temporary.delete(recursive: true);
    }
  });

  test(
    'companion stores uploaded saved references and scoped folders',
    () async {
      final temporary = await Directory.systemTemp.createTemp(
        'clawnsole-reference-test.',
      );
      final store = CompanionStore(File('${temporary.path}/clawnsole.json'));
      final application = CompanionApp(store: store, api: BflApi());
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      final subscription = server.listen(application.handle);
      final base = Uri.parse('http://127.0.0.1:${server.port}');
      const headers = <String, String>{'Content-Type': 'application/json'};
      final now = DateTime.utc(2026, 8, 19, 12);

      try {
        final folder = await http.patch(
          base.resolve('/state'),
          headers: headers,
          body: jsonEncode(<String, Object?>{
            'action': 'saveLibraryFolder',
            'value': <String, Object?>{
              'id': 'reference-characters',
              'name': 'Characters',
              'collection': 'references',
              'createdAt': now.toIso8601String(),
            },
          }),
        );
        expect(folder.statusCode, 200);

        final response = await http.patch(
          base.resolve('/state'),
          headers: headers,
          body: jsonEncode(<String, Object?>{
            'action': 'saveReference',
            'value': <String, Object?>{
              'reference': <String, Object?>{
                'id': 'saved-character',
                'name': 'Hero portrait',
                'kind': 'image',
                'asset': <String, Object?>{
                  'kind': 'remote',
                  'value': '',
                  'label': 'hero.png',
                  'contentType': 'image/png',
                },
                'createdAt': now.toIso8601String(),
                'updatedAt': now.toIso8601String(),
                'folderId': 'reference-characters',
                'tags': <String>['hero', 'favorite'],
              },
              'source': 'data:image/png;base64,AQID',
            },
          }),
        );
        expect(response.statusCode, 200);
        final snapshot = LocalSnapshot.fromJson(
          (jsonDecode(response.body) as Map<Object?, Object?>).map(
            (key, value) => MapEntry(key.toString(), value),
          ),
        );
        expect(snapshot.savedReferences.single.name, 'Hero portrait');
        expect(snapshot.savedReferences.single.asset.isLocal, isTrue);
        expect(
          snapshot.savedReferences.single.folderId,
          'reference-characters',
        );
        expect(
          snapshot.folders.single.collection,
          LibraryCollection.references,
        );

        final media = await http.get(
          base.resolve(
            '/assets?id=${snapshot.savedReferences.single.asset.value}',
          ),
        );
        expect(media.statusCode, 200);
        expect(media.bodyBytes, <int>[1, 2, 3]);

        final cleared = await http.patch(
          base.resolve('/state'),
          headers: headers,
          body: jsonEncode(<String, Object?>{'action': 'clearHistory'}),
        );
        expect(cleared.statusCode, 200);
        final retained = await http.get(
          base.resolve(
            '/assets?id=${snapshot.savedReferences.single.asset.value}',
          ),
        );
        expect(retained.statusCode, 200);
        expect(retained.bodyBytes, <int>[1, 2, 3]);
      } finally {
        await subscription.cancel();
        await server.close(force: true);
        await temporary.delete(recursive: true);
      }
    },
  );

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
