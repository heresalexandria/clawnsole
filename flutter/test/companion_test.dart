import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:clawnsole/core/artcraft_api.dart';
import 'package:clawnsole/core/bfl_api.dart';
import 'package:clawnsole/core/google_drive.dart';
import 'package:clawnsole/core/google_drive_store.dart';
import 'package:clawnsole/core/hybrid_data_store.dart';
import 'package:clawnsole/core/models.dart';
import 'package:clawnsole/core/provider_api.dart';
import 'package:clawnsole/core/provider_catalog.dart';
import 'package:clawnsole/core/reference_video_normalizer.dart';
import 'package:clawnsole/core/secure_value_store.dart';
import 'package:clawnsole/core/settings_vault.dart';
import 'package:clawnsole/core/settings_vault_data_store.dart';
import 'package:clawnsole/core/settings_vault_remote.dart';
import 'package:clawnsole/core/video_cache.dart';
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
      '--media-tools-dir',
      'build/media-tools',
    ], const <String, String>{});
    expect(config.port, 0);
    expect(config.dataFile, endsWith('data.json'));
    expect(config.webRoot, endsWith('build/web'));
    expect(config.mediaToolsDir, endsWith('build/media-tools'));
  });

  test(
    'companion bootstrap accepts packaged stdin and development env',
    () async {
      final requestToken = _bootstrapKey(1);
      final deviceKey = _bootstrapKey(2);
      final packaged = await CompanionBootstrap.load(
        const <String, String>{},
        Stream<List<int>>.value(
          utf8.encode(
            '${jsonEncode(<String, String>{'deviceKey': deviceKey, 'requestToken': requestToken})}\n',
          ),
        ),
        requireInput: true,
      );
      expect(packaged.requestToken, requestToken);
      expect(packaged.deviceKey, deviceKey);

      final development = await CompanionBootstrap.load(<String, String>{
        'CLAWNSOLE_COMPANION_TOKEN': requestToken,
      }, const Stream<List<int>>.empty());
      expect(development.requestToken, requestToken);
      expect(development.deviceKey, isNull);
      final localDevelopment = await CompanionBootstrap.load(
        const <String, String>{},
        const Stream<List<int>>.empty(),
      );
      expect(localDevelopment.requestToken, isEmpty);
      expect(
        () => CompanionBootstrap.fromJsonLine(
          '{"deviceKey":"plaintext","requestToken":"plaintext"}',
        ),
        throwsStateError,
      );
    },
  );

  test('development device keys are stable and protected', () async {
    final temporary = await Directory.systemTemp.createTemp(
      'clawnsole-development-key.',
    );
    addTearDown(() => temporary.delete(recursive: true));
    final file = File('${temporary.path}/device.key');

    final first = await DevelopmentDeviceKey.loadOrCreate(file);
    final second = await DevelopmentDeviceKey.loadOrCreate(file);

    expect(first, second);
    expect(first, hasLength(43));
    if (!Platform.isWindows) {
      expect((await file.stat()).modeString(), endsWith('rw-------'));
    }
  });

  test(
    'companion enforces the launch token and exact renderer origin',
    () async {
      final temporary = await Directory.systemTemp.createTemp(
        'clawnsole-session-test.',
      );
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      final base = Uri.parse('http://127.0.0.1:${server.port}');
      final token = _bootstrapKey(3);
      final application = CompanionApp(
        store: CompanionStore(File('${temporary.path}/clawnsole.json')),
        api: BflApi(),
        requestToken: token,
        allowedOrigin: base.origin,
      );
      final subscription = server.listen(application.handle);

      try {
        final health = await http.get(base.resolve('/health'));
        expect(health.statusCode, 200);

        final missingToken = await http.get(base.resolve('/state'));
        expect(missingToken.statusCode, 403);

        final authenticated = await http.get(
          base.resolve('/state'),
          headers: <String, String>{'X-Clawnsole-Session': token},
        );
        expect(authenticated.statusCode, 200);

        final exactOrigin = await http.get(
          base.resolve('/state'),
          headers: <String, String>{
            'Origin': base.origin,
            'X-Clawnsole-Session': token,
          },
        );
        expect(exactOrigin.statusCode, 200);
        expect(
          exactOrigin.headers[HttpHeaders.accessControlAllowOriginHeader],
          base.origin,
        );

        final otherLocalOrigin = await http.get(
          base.resolve('/state'),
          headers: <String, String>{
            'Origin': 'http://127.0.0.1:${server.port + 1}',
            'X-Clawnsole-Session': token,
          },
        );
        expect(otherLocalOrigin.statusCode, 403);

        final preflight = await http.Client().send(
          http.Request('OPTIONS', base.resolve('/state'))
            ..headers.addAll(<String, String>{
              'Origin': base.origin,
              'X-Clawnsole-Session': token,
            }),
        );
        expect(preflight.statusCode, HttpStatus.noContent);
        expect(
          preflight.headers[HttpHeaders.accessControlAllowHeadersHeader],
          contains('X-Clawnsole-Session'),
        );
      } finally {
        await subscription.cancel();
        await server.close(force: true);
        await temporary.delete(recursive: true);
      }
    },
  );

  test(
    'companion vault route returns only the scalar shell contract',
    () async {
      final temporary = await Directory.systemTemp.createTemp(
        'clawnsole-vault-route-test.',
      );
      final local = CompanionStore(File('${temporary.path}/clawnsole.json'));
      final hybrid = HybridDataStore(local: local);
      final remote = _MemorySettingsVaultRemote();
      final vault = SettingsVaultDataStore(
        delegate: hybrid,
        secureStore: MemorySecureValueStore(),
        remote: remote,
        codec: SettingsVaultCodec(
          kdfParameters: const SettingsVaultKdfParameters(
            memoryKiB: settingsVaultMinimumMemoryKiB,
            iterations: 1,
          ),
        ),
      );
      await vault.connectRemote('access-token', 'folder-id');
      final application = CompanionApp.hybrid(
        store: CompanionHybridStore(hybrid, vault: vault),
        api: BflApi(),
      );
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      final subscription = server.listen(application.handle);
      final base = Uri.parse('http://127.0.0.1:${server.port}');

      try {
        final response = await http.post(
          base.resolve('/vault/setup'),
          headers: const <String, String>{'Content-Type': 'application/json'},
          body: jsonEncode(<String, String>{
            'value': 'correct horse battery staple',
          }),
        );
        expect(response.statusCode, 200);
        final payload = jsonDecode(response.body) as Map<String, Object?>;
        expect(payload['ok'], isTrue);
        expect(payload['state'], SettingsVaultState.ready.name);
        expect(payload['recoveryCode'], isA<String>());
        expect(payload.keys, <String>{
          'ok',
          'state',
          'message',
          'syncedAt',
          'recoveryCode',
        });

        final sync = await http.post(
          base.resolve('/vault/sync'),
          headers: const <String, String>{'Content-Type': 'application/json'},
          body: jsonEncode(<String, String>{'value': ''}),
        );
        final syncPayload = jsonDecode(sync.body) as Map<String, Object?>;
        expect(sync.statusCode, 200);
        expect(syncPayload['ok'], isTrue);
        expect(syncPayload, isNot(contains('recoveryCode')));
      } finally {
        await subscription.cancel();
        await server.close(force: true);
        await temporary.delete(recursive: true);
      }
    },
  );

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

  test(
    'companion stores typed asset extensions and resolves drifted names',
    () async {
      final temporary = await Directory.systemTemp.createTemp(
        'clawnsole-asset-name-test.',
      );
      final store = CompanionStore(File('${temporary.path}/clawnsole.json'));
      try {
        final written = await store.writeAsset(
          Uint8List.fromList(<int>[1, 2, 3]),
          label: 'result.mp4',
          contentType: 'video/mp4',
        );
        final files = store.assets.listSync().whereType<File>().toList();
        expect(files.single.path, endsWith('${written.value}.mp4'));
        expect(await store.readAsset(written), <int>[1, 2, 3]);

        // A library written by an older companion keeps the generic name.
        const legacy = AssetReference(
          kind: 'local',
          value: 'aaaaaaaaaaaaaaaa',
          label: 'legacy.mp4',
          contentType: 'video/mp4',
        );
        File(
          '${store.assets.path}/aaaaaaaaaaaaaaaa.asset',
        ).writeAsBytesSync(<int>[4, 5]);
        expect(await store.readAsset(legacy), <int>[4, 5]);

        // A file whose on-disk extension no longer matches the reference's
        // contentType mapping is still found by its id stem.
        const drifted = AssetReference(
          kind: 'local',
          value: 'bbbbbbbbbbbbbbbb',
          label: 'drifted',
          contentType: 'video/mp4',
        );
        File(
          '${store.assets.path}/bbbbbbbbbbbbbbbb.mov',
        ).writeAsBytesSync(<int>[6, 7]);
        expect(await store.readAsset(drifted), <int>[6, 7]);

        const missing = AssetReference(
          kind: 'local',
          value: 'cccccccccccccccc',
          label: 'missing',
          contentType: 'video/mp4',
        );
        await expectLater(
          store.readAsset(missing),
          throwsA(
            isA<StateError>().having(
              (error) => error.message,
              'message',
              contains("missing from this device's library storage"),
            ),
          ),
        );
      } finally {
        await temporary.delete(recursive: true);
      }
    },
  );

  test('prune keeps local files referenced by Drive-tagged records', () async {
    final temporary = await Directory.systemTemp.createTemp(
      'clawnsole-prune-safety-test.',
    );
    final store = CompanionStore(File('${temporary.path}/clawnsole.json'));
    final hybrid = HybridDataStore(local: store);
    try {
      final asset = await store.writeAsset(
        Uint8List.fromList(<int>[1, 2, 3]),
        label: 'result.mp4',
        contentType: 'video/mp4',
      );
      final now = DateTime.utc(2026, 8, 21, 12);
      // The record's storage tag drifted to Drive while its asset is still
      // stored locally. Pruning must never delete the referenced file.
      final mismatched = Generation(
        localId: 'drive-tagged',
        status: 'Ready',
        prompt: 'A record whose storage tag says Drive.',
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
        resultAsset: asset,
        storage: LibraryStorage.drive,
      );

      await hybrid.pruneAssets(<Generation>[mismatched]);
      expect(await store.readAsset(asset), <int>[1, 2, 3]);

      // Once nothing references the asset, pruning removes the typed file.
      await hybrid.pruneAssets(const <Generation>[]);
      expect(store.assets.listSync().whereType<File>(), isEmpty);
    } finally {
      await temporary.delete(recursive: true);
    }
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

  test('companion normalizes image frames without a video profile', () async {
    final temporary = await Directory.systemTemp.createTemp(
      'clawnsole-image-normalization-test.',
    );
    final store = CompanionStore(File('${temporary.path}/clawnsole.json'));
    final originalBytes = Uint8List.fromList(<int>[1, 2, 3]);
    final derivativeBytes = Uint8List.fromList(<int>[0xff, 0xd8, 0xff, 0xd9]);
    final originalSource =
        'data:image/heif;base64,${base64Encode(originalBytes)}';
    final derivativeSource =
        'data:image/jpeg;base64,${base64Encode(derivativeBytes)}';
    final retainedOriginal = await store.writeAsset(
      originalBytes,
      label: 'original.heic',
      contentType: 'image/heif',
    );
    final api = _CapturingArtCraftApi();
    final normalizer = _ChangedReferenceMediaNormalizer(derivativeSource);
    final application = CompanionApp(
      store: store,
      api: BflApi(),
      providerRouter: ProviderApiRouter(artcraft: api),
      fallbackApiKeys: const <String, String>{'artcraft': 'secret'},
      referenceVideoNormalizer: normalizer,
    );
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final subscription = server.listen(application.handle);
    final base = Uri.parse('http://127.0.0.1:${server.port}');
    final now = DateTime.utc(2026, 8, 22, 12);
    final record = Generation(
      localId: 'companion-image-reference-submit',
      provider: 'artcraft',
      model: 'veo_3_fast',
      status: 'submitting',
      prompt: 'Animate the frame.',
      mode: VideoMode.i2v,
      config: GenerationConfig(
        aspectRatio: '16:9',
        duration: 5,
        resolution: 'hd',
        generateAudio: true,
        safetyTolerance: 2,
        draft: false,
        keyframes: <KeyframeLabel>[
          KeyframeLabel(
            label: 'Original frame',
            role: KeyframeRole.start,
            source: retainedOriginal,
          ),
        ],
      ),
      createdAt: now,
      updatedAt: now,
    );

    try {
      final response = await http.post(
        base.resolve('/generations'),
        headers: const <String, String>{'Content-Type': 'application/json'},
        body: jsonEncode(<String, Object?>{
          'input': <String, Object?>{
            'mode': 'i2v',
            'keyframes': <String>[originalSource],
          },
          'record': record.toJson(),
          'autoFixReferenceVideos': true,
        }),
      );

      expect(response.statusCode, 201, reason: response.body);
      expect(normalizer.sources, <String>[originalSource]);
      expect(api.input['keyframes'], <String>[derivativeSource]);
      final persisted = (await store.read()).generations.single;
      final persistedSource = persisted.config.keyframes!.single.source!;
      expect(persistedSource.value, isNot(retainedOriginal.value));
      expect(await store.readAsset(persistedSource), derivativeBytes);
      expect(await store.readAsset(retainedOriginal), originalBytes);
    } finally {
      await subscription.cancel();
      await server.close(force: true);
      await temporary.delete(recursive: true);
    }
  });

  test(
    'companion non-Seedance submit selects generic repair and derivative',
    () async {
      final temporary = await Directory.systemTemp.createTemp(
        'clawnsole-reference-normalization-test.',
      );
      final store = CompanionStore(File('${temporary.path}/clawnsole.json'));
      final originalBytes = Uint8List.fromList(<int>[1, 2, 3]);
      final derivativeBytes = Uint8List.fromList(<int>[9, 8, 7]);
      final originalSource =
          'data:video/mp4;base64,${base64Encode(originalBytes)}';
      final derivativeSource =
          'data:video/mp4;base64,${base64Encode(derivativeBytes)}';
      final retainedOriginal = await store.writeAsset(
        originalBytes,
        label: 'original.mp4',
        contentType: 'video/mp4',
      );
      await store.replace(
        const StoredData(
          preferences: AppPreferences(autoFixReferenceVideos: true),
        ),
      );
      final api = _CapturingArtCraftApi();
      final normalizer = _ChangedReferenceVideoNormalizer(derivativeSource);
      final application = CompanionApp(
        store: store,
        api: BflApi(),
        providerRouter: ProviderApiRouter(artcraft: api),
        fallbackApiKeys: const <String, String>{'artcraft': 'secret'},
        referenceVideoNormalizer: normalizer,
      );
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      final subscription = server.listen(application.handle);
      final base = Uri.parse('http://127.0.0.1:${server.port}');
      final now = DateTime.utc(2026, 8, 21, 12);
      final record = Generation(
        localId: 'companion-generic-reference-submit',
        provider: 'artcraft',
        model: 'minimax_h3',
        status: 'submitting',
        prompt: 'Follow the reference motion.',
        mode: VideoMode.i2v,
        config: GenerationConfig(
          aspectRatio: '16:9',
          duration: 5,
          resolution: 'hd',
          generateAudio: true,
          safetyTolerance: 2,
          draft: false,
          references: <MediaReferenceLabel>[
            MediaReferenceLabel(
              label: 'Original clip',
              kind: MediaReferenceKind.video,
              source: retainedOriginal,
            ),
          ],
        ),
        createdAt: now,
        updatedAt: now,
      );

      try {
        final response = await http.post(
          base.resolve('/generations'),
          headers: const <String, String>{'Content-Type': 'application/json'},
          body: jsonEncode(<String, Object?>{
            'input': <String, Object?>{
              'mode': 'i2v',
              'reference_videos': <String>[originalSource],
            },
            'record': record.toJson(),
            'autoFixReferenceVideos': true,
          }),
        );

        expect(response.statusCode, 201, reason: response.body);
        expect(normalizer.sources, <String>[originalSource]);
        expect(normalizer.profile, ReferenceVideoCompatibilityProfile.generic);
        expect(api.input['reference_videos'], <String>[derivativeSource]);

        final persisted = (await store.read()).generations.single;
        final persistedSource = persisted.config.references!.single.source!;
        expect(persistedSource.value, isNot(retainedOriginal.value));
        expect(await store.readAsset(persistedSource), derivativeBytes);
        expect(await store.readAsset(retainedOriginal), originalBytes);
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
    final application = CompanionApp(
      store: store,
      api: _Terminal503Api(),
      fallbackApiKeys: const <String, String>{'bfl': 'test-key'},
    );
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

  test('companion migrates the local library to Drive entirely', () async {
    final temporary = await Directory.systemTemp.createTemp(
      'clawnsole-migrate-test.',
    );
    final local = CompanionStore(File('${temporary.path}/clawnsole.json'));
    final drive = _MemoryDriveStore();
    final store = CompanionHybridStore(
      HybridDataStore(local: local, drive: drive),
    );
    final asset = await local.writeAsset(
      Uint8List.fromList(<int>[1, 2, 3]),
      label: 'clip.mp4',
      contentType: 'video/mp4',
    );
    final now = DateTime.utc(2026, 8, 20);
    await local.write(
      StoredData(
        generations: <Generation>[
          Generation(
            localId: 'generation-one',
            status: 'Ready',
            prompt: 'a local clip',
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
            resultAsset: asset,
          ),
        ],
      ),
    );
    await store.connectDrive('token', 'Portable Studio');
    final application = CompanionApp.hybrid(store: store, api: BflApi());
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final subscription = server.listen(application.handle);
    final base = Uri.parse('http://127.0.0.1:${server.port}');

    try {
      final response = await http.post(base.resolve('/drive/migrate'));
      expect(response.statusCode, 200);
      final payload = jsonDecode(response.body) as Map<String, Object?>;
      expect(payload['generations'], 1);
      expect(payload['references'], 0);
      final snapshot = payload['snapshot']! as Map<String, Object?>;
      final generations = (snapshot['generations']! as List<Object?>)
          .whereType<Map<Object?, Object?>>()
          .toList();
      expect(generations, hasLength(1));
      expect(generations.single['localId'], 'drive-generation-one');
      expect(generations.single['storage'], 'drive');
      expect(drive.assets.values.single, <int>[1, 2, 3]);

      // The local file lost its records but keeps the Drive linkage, and
      // the now-unreferenced retained asset was pruned from disk.
      final persisted = StoredData.decode(
        File('${temporary.path}/clawnsole.json').readAsStringSync(),
      );
      expect(persisted.generations, isEmpty);
      expect(persisted.driveFolderName, 'Portable Studio');
      final assetsDirectory = Directory('${temporary.path}/assets');
      expect(
        assetsDirectory.existsSync()
            ? assetsDirectory.listSync().whereType<File>().toList()
            : const <File>[],
        isEmpty,
      );
    } finally {
      await subscription.cancel();
      await server.close(force: true);
      await temporary.delete(recursive: true);
    }
  });

  test(
    'companion serves Drive films from its disk cache with ranges',
    () async {
      final temporary = await Directory.systemTemp.createTemp(
        'clawnsole-video-cache-test.',
      );
      final local = CompanionStore(File('${temporary.path}/clawnsole.json'));
      final drive = _StreamingDriveStore();
      final filmOne = Uint8List.fromList(<int>[1, 2, 3, 4, 5, 6, 7, 8]);
      final filmTwo = Uint8List.fromList(<int>[9, 8, 7, 6, 5, 4]);
      drive.assets['drive-film-one'] = filmOne;
      drive.assets['drive-film-two'] = filmTwo;
      final now = DateTime.utc(2026, 8, 21);
      Generation generation(String id, String assetId, Uint8List bytes) =>
          Generation(
            localId: id,
            status: 'Ready',
            prompt: 'a cached clip',
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
            resultAsset: AssetReference(
              kind: 'drive',
              value: assetId,
              label: 'clip.mp4',
              contentType: 'video/mp4',
              bytes: bytes.length,
            ),
          );
      drive.data = StoredData(
        generations: <Generation>[
          generation('one', 'drive-film-one', filmOne),
          generation('two', 'drive-film-two', filmTwo),
        ],
      );
      final store = CompanionHybridStore(
        HybridDataStore(local: local, drive: drive),
      );
      await store.connectDrive('token', 'Cached Studio');
      final cache = VideoCache(
        directory: () async => Directory('${temporary.path}/video-cache'),
      );
      final application = CompanionApp.hybrid(
        store: store,
        api: BflApi(),
        videoCache: cache,
      );
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      final subscription = server.listen(application.handle);
      final base = Uri.parse('http://127.0.0.1:${server.port}');

      try {
        // A cold open-from-zero request fills the cache exactly once while
        // answering the range, and allows private browser caching.
        final first = await http.get(
          base.resolve('/assets?id=drive-film-one&kind=drive'),
          headers: const <String, String>{'Range': 'bytes=0-'},
        );
        expect(first.statusCode, 206);
        expect(first.bodyBytes, filmOne);
        expect(first.headers['content-range'], 'bytes 0-7/8');
        expect(first.headers['cache-control'], contains('max-age'));
        expect(drive.streamDownloads, 1);

        // A later seek is served from the cached file: no new Drive traffic.
        final seek = await http.get(
          base.resolve('/assets?id=drive-film-one&kind=drive'),
          headers: const <String, String>{'Range': 'bytes=2-5'},
        );
        expect(seek.statusCode, 206);
        expect(seek.bodyBytes, filmOne.sublist(2, 6));
        expect(seek.headers['content-range'], 'bytes 2-5/8');
        expect(drive.streamDownloads, 1);
        expect(drive.rangeReads, 0);

        // A cold seek on an uncached film answers straight from Drive's Range
        // support instead of waiting behind a full download.
        final coldSeek = await http.get(
          base.resolve('/assets?id=drive-film-two&kind=drive'),
          headers: const <String, String>{'Range': 'bytes=1-3'},
        );
        expect(coldSeek.statusCode, 206);
        expect(coldSeek.bodyBytes, filmTwo.sublist(1, 4));
        expect(coldSeek.headers['content-range'], 'bytes 1-3/6');
        expect(drive.rangeReads, 1);
        expect(drive.streamDownloads, 1);

        final usage = await http.get(base.resolve('/video-cache'));
        final usagePayload = jsonDecode(usage.body) as Map<String, Object?>;
        expect(usagePayload['usedBytes'], filmOne.length);
        expect(usagePayload['capBytes'], 100 * 1024 * 1024);

        // Prefetch queues a background fill for the second film.
        final prefetch = await http.post(
          base.resolve('/video-cache/prefetch'),
          headers: const <String, String>{'Content-Type': 'application/json'},
          body: jsonEncode(<String, Object?>{'id': 'drive-film-two'}),
        );
        expect(prefetch.statusCode, 202);
        expect(
          (jsonDecode(prefetch.body) as Map<String, Object?>)['queued'],
          true,
        );
        final deadline = DateTime.now().add(const Duration(seconds: 5));
        while (await cache.lookup('drive-film-two') == null &&
            DateTime.now().isBefore(deadline)) {
          await Future<void>.delayed(const Duration(milliseconds: 20));
        }
        expect(await cache.lookup('drive-film-two'), isNotNull);
        expect(drive.streamDownloads, 2);

        // Turning the preference off through the synced state clears the disk
        // cache and returns /assets to direct serving.
        final patched = await http.patch(
          base.resolve('/state'),
          headers: const <String, String>{'Content-Type': 'application/json'},
          body: jsonEncode(<String, Object?>{
            'action': 'setPreferences',
            'value': const AppPreferences(localVideoCacheMb: 0).toJson(),
          }),
        );
        expect(patched.statusCode, 200);
        final off = await http.get(base.resolve('/video-cache'));
        final offPayload = jsonDecode(off.body) as Map<String, Object?>;
        expect(offPayload['capBytes'], 0);
        expect(offPayload['usedBytes'], 0);

        final direct = await http.get(
          base.resolve('/assets?id=drive-film-one&kind=drive'),
        );
        expect(direct.statusCode, 200);
        expect(direct.bodyBytes, filmOne);
        expect(drive.fullReads, 1);
      } finally {
        await subscription.cancel();
        await server.close(force: true);
        await temporary.delete(recursive: true);
      }
    },
  );
}

class _StreamingDriveStore extends _MemoryDriveStore {
  int streamDownloads = 0;
  int rangeReads = 0;
  int fullReads = 0;

  @override
  Future<Uint8List> readAsset(AssetReference reference) {
    fullReads += 1;
    return super.readAsset(reference);
  }

  @override
  Future<GoogleDriveByteStream> readAssetStream(
    AssetReference reference,
  ) async {
    streamDownloads += 1;
    final bytes = assets[reference.value] ?? Uint8List(0);
    return GoogleDriveByteStream(
      Stream<List<int>>.value(bytes),
      contentLength: bytes.length,
    );
  }

  @override
  Future<Uint8List> readAssetRange(
    AssetReference reference,
    int start,
    int end,
  ) async {
    rangeReads += 1;
    final bytes = assets[reference.value] ?? Uint8List(0);
    return Uint8List.sublistView(
      bytes,
      start.clamp(0, bytes.length),
      (end + 1).clamp(0, bytes.length),
    );
  }
}

class _MemoryDriveStore extends GoogleDriveStore {
  StoredData data = const StoredData();
  final Map<String, Uint8List> assets = <String, Uint8List>{};
  int _assetCounter = 0;
  GoogleDriveConnection _memoryConnection = const GoogleDriveConnection(
    state: GoogleDriveConnectionState.disconnected,
  );

  @override
  GoogleDriveConnection get connection => _memoryConnection;

  @override
  Future<StoredData> connect(String accessToken, String folderName) async {
    _memoryConnection = GoogleDriveConnection(
      state: GoogleDriveConnectionState.connected,
      folderName: folderName,
      folderId: 'drive-root',
    );
    return data;
  }

  @override
  Future<void> disconnect() async {
    _memoryConnection = const GoogleDriveConnection(
      state: GoogleDriveConnectionState.disconnected,
    );
  }

  @override
  Future<StoredData> read() async => data;

  @override
  Future<void> write(StoredData value) async =>
      data = googleDrivePortableData(value);

  @override
  Future<AssetReference> writeAsset(
    Uint8List bytes, {
    required String label,
    required String contentType,
    LibraryStorage storage = LibraryStorage.drive,
  }) async {
    final id = 'drive-asset-${_assetCounter++}';
    assets[id] = bytes;
    return AssetReference(
      kind: 'drive',
      value: id,
      label: label,
      contentType: contentType,
      bytes: bytes.length,
    );
  }

  @override
  Future<Uint8List> readAsset(AssetReference reference) async =>
      assets[reference.value] ?? Uint8List(0);

  @override
  Future<void> pruneAssets(
    List<Generation> generations, [
    List<SavedReference> savedReferences = const <SavedReference>[],
  ]) async {}

  @override
  Future<StorageStats> stats(int records) async => StorageStats(
    path: 'drive',
    bytes: data.encode().length,
    records: records,
  );
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

class _ChangedReferenceVideoNormalizer
    implements ReferenceVideoNormalizationService {
  _ChangedReferenceVideoNormalizer(this.derivative);

  final String derivative;
  List<String> sources = const <String>[];
  ReferenceVideoCompatibilityProfile? profile;

  @override
  Future<PreparedReferenceVideos> normalize(
    List<String> sources, {
    required ReferenceVideoCompatibilityProfile profile,
  }) async {
    this.sources = List<String>.of(sources);
    this.profile = profile;
    return PreparedReferenceVideos(
      sources: <String>[derivative],
      changedIndexes: const <int>{0},
    );
  }
}

class _ChangedReferenceMediaNormalizer
    implements
        ReferenceVideoNormalizationService,
        ReferenceImageNormalizationService {
  _ChangedReferenceMediaNormalizer(this.derivative);

  final String derivative;
  List<String> sources = const <String>[];

  @override
  Future<PreparedReferenceImages> normalizeImages(List<String> sources) async {
    this.sources = List<String>.of(sources);
    return PreparedReferenceImages(
      sources: <String>[derivative],
      changedIndexes: const <int>{0},
    );
  }

  @override
  Future<PreparedReferenceVideos> normalize(
    List<String> sources, {
    required ReferenceVideoCompatibilityProfile profile,
  }) => throw StateError('Video normalization should not run.');
}

class _CapturingArtCraftApi extends ArtCraftApi {
  Map<String, Object?> input = const <String, Object?>{};

  @override
  Future<ProviderAccountStatus> verify(String key) async =>
      const ProviderAccountStatus(provider: 'artcraft', currency: 'credits');

  @override
  Future<Map<String, Object?>> submit(
    String key,
    String model,
    Map<String, Object?> input,
  ) async {
    this.input = input;
    return <String, Object?>{
      'id': 'seedance-job',
      'polling_url': 'https://api.storyteller.ai/v1/job/seedance-job',
    };
  }
}

String _bootstrapKey(int seed) => base64UrlEncode(
  Uint8List.fromList(List<int>.generate(32, (index) => seed + index)),
).replaceAll('=', '');

class _MemorySettingsVaultRemote implements SettingsVaultRemote {
  bool _connected = false;
  SettingsVaultRemoteDocument? _document;
  var _version = 0;

  @override
  bool get isConnected => _connected;

  @override
  Future<SettingsVaultRemoteDocument?> connect(
    String accessToken,
    String folderId,
  ) async {
    _connected = accessToken.isNotEmpty && folderId.isNotEmpty;
    return _document;
  }

  @override
  Future<void> delete() async {
    _document = null;
  }

  @override
  Future<void> disconnect() async {
    _connected = false;
  }

  @override
  Future<SettingsVaultRemoteDocument?> read() async => _document;

  @override
  Future<SettingsVaultRemoteDocument> write(
    Uint8List bytes, {
    String? expectedEtag,
  }) async {
    _version += 1;
    return _document = SettingsVaultRemoteDocument(
      Uint8List.fromList(bytes),
      etag: 'version-$_version',
    );
  }
}
