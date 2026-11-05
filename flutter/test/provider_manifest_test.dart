import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:clawnsole/app/app_controller.dart';
import 'package:clawnsole/core/app_version.dart';
import 'package:clawnsole/core/gateway.dart';
import 'package:clawnsole/core/models.dart';
import 'package:clawnsole/core/provider_catalog.dart';
import 'package:clawnsole/core/provider_manifest.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  tearDown(resetProviderCatalog);

  test(
    'generation notices survive remote manifests and mobile constraints',
    () {
      const notice = 'This route may return a different output duration.';
      final bundle = ProviderCatalogBundle.fromCache(
        _cache([
          _provider([
            {..._model('notice-model'), 'generation_notice': notice},
          ]),
        ]),
        appVersion: '0.64.0',
      );
      final model = bundle.providers.single.models.single;
      expect(model.generationNotice, notice);
      expect(
        model
            .constrainedForMobileTest(model.resolutions.first)
            .generationNotice,
        notice,
      );
      final fallback = ProviderCatalogBundle.fromCache(
        _cache([
          _provider([_model('gemini-omni-t2v')], id: 'apipod'),
        ]),
        appVersion: '0.64.0',
      );
      final bundledNotice = bundledVideoProviders
          .singleWhere((provider) => provider.id == 'apipod')
          .models
          .singleWhere((model) => model.id == 'gemini-omni-t2v')
          .generationNotice;
      expect(bundledNotice, isNotNull);
      expect(
        fallback.providers.single.models.single.generationNotice,
        bundledNotice,
      );
    },
  );

  test('the complete Pages manifest graph is valid for this build', () async {
    final root = Directory('../docs/models').absolute;
    final client = MockClient((request) async {
      final relative = request.url.path == '/models/'
          ? 'index.html'
          : request.url.path.replaceFirst('/models/', '');
      final file = File('${root.path}/$relative');
      if (!await file.exists()) return http.Response('missing', 404);
      return http.Response.bytes(await file.readAsBytes(), 200);
    });
    final bundle = await ProviderCatalogClient(
      client: client,
      siteUrl: Uri.parse('https://clawnsole.app/'),
    ).fetch(appVersion: clawnsoleVersion);

    expect(bundle.cache['catalog_version'], clawnsoleVersion);
    expect(bundle.providers, isNotEmpty);
    expect(
      bundle.providers.map((provider) => provider.id).toSet(),
      hasLength(bundle.providers.length),
    );
    for (final provider in bundle.providers) {
      expect(supportedProviderAdapters, contains(provider.adapter));
      expect(provider.models, isNotEmpty, reason: provider.id);
      expect(
        provider.models.map((model) => model.id).toSet(),
        hasLength(provider.models.length),
        reason: provider.id,
      );
      for (final model in provider.models) {
        expect(model.modes, isNotEmpty, reason: model.id);
        expect(model.resolutions, isNotEmpty, reason: model.id);
        expect(model.aspectRatios, isNotEmpty, reason: model.id);
        expect(model.minDuration, greaterThan(0), reason: model.id);
        expect(
          model.maxDuration,
          greaterThanOrEqualTo(model.minDuration),
          reason: model.id,
        );
      }
    }
  });

  test(
    'the next minor catalog matches the bundled cross-platform contracts',
    () async {
      final root = Directory('../docs/models').absolute;
      final bundle = await ProviderCatalogClient(
        client: MockClient((request) async {
          final relative = request.url.path == '/models/'
              ? 'index.html'
              : request.url.path.replaceFirst('/models/', '');
          final body = await File('${root.path}/$relative').readAsString();
          return http.Response(
            relative == 'index.html'
                ? jsonEncode({
                    ...jsonDecode(body) as Map<String, dynamic>,
                    'catalog_version': '0.64.0',
                  })
                : body,
            200,
            headers: {'content-type': 'application/json; charset=utf-8'},
          );
        }),
        siteUrl: Uri.parse('https://clawnsole.app/'),
      ).fetch(appVersion: '0.64.0');
      expect(
        bundle.providers.map((p) => p.id).toSet(),
        bundledVideoProviders.map((p) => p.id).toSet(),
      );
      for (final bundled in bundledVideoProviders) {
        final remote = bundle.providers.singleWhere((p) => p.id == bundled.id);
        expect(
          remote.models.map((m) => m.id).toSet(),
          bundled.models.map((m) => m.id).toSet(),
          reason: bundled.id,
        );
        for (final model in bundled.models) {
          final fetched = remote.models.singleWhere((m) => m.id == model.id);
          final reason = '${bundled.id}/${model.id}';
          expect(fetched.canonicalId, model.canonicalId, reason: reason);
          expect(fetched.usdPerSecond, model.usdPerSecond, reason: reason);
          expect(
            fetched.referenceUsdPerSecond,
            model.referenceUsdPerSecond,
            reason: reason,
          );
          expect(
            fetched.resolutions.map((r) => r.id),
            model.resolutions.map((r) => r.id),
            reason: reason,
          );
          expect(fetched.aspectRatios, model.aspectRatios, reason: reason);
          expect(fetched.modes, model.modes, reason: reason);
          expect(fetched.minDuration, model.minDuration, reason: reason);
          expect(fetched.maxDuration, model.maxDuration, reason: reason);
          expect(fetched.supportsAudio, model.supportsAudio, reason: reason);
          expect(
            fetched.supportsOrderedMiddleFrames,
            model.supportsOrderedMiddleFrames,
            reason: reason,
          );
          expect(
            fetched.maxMiddleFrames,
            model.maxMiddleFrames,
            reason: reason,
          );
          expect(
            fetched.maxKeyframesPerSecond,
            model.maxKeyframesPerSecond,
            reason: reason,
          );
          expect(
            fetched.minReferenceVideoSeconds,
            model.minReferenceVideoSeconds,
            reason: reason,
          );
          expect(
            fetched.minReferenceAudioSeconds,
            model.minReferenceAudioSeconds,
            reason: reason,
          );
          expect(
            fetched.requiresStartFrameWhenUsingFrames,
            model.requiresStartFrameWhenUsingFrames,
            reason: reason,
          );
          expect(
            fetched.requiresPublicMediaUrls,
            model.requiresPublicMediaUrls,
            reason: reason,
          );
          expect(
            fetched.maxCombinedVideoSeconds,
            model.maxCombinedVideoSeconds,
            reason: reason,
          );
        }
      }
    },
  );

  test('public media URL restrictions survive incomplete cached manifests', () {
    final bundle = ProviderCatalogBundle.fromCache(
      _cache(<Map<String, Object?>>[
        _provider(<Map<String, Object?>>[
          _model('seedance-2.5-i2v'),
          <String, Object?>{
            ..._model('new-hosted-route'),
            'requires_public_media_urls': true,
          },
          _model('upload-route'),
        ], id: 'apipod'),
      ]),
    );
    final models = bundle.providers.single.models;
    expect(models[0].requiresPublicMediaUrls, isTrue);
    expect(models[1].requiresPublicMediaUrls, isTrue);
    expect(models[2].requiresPublicMediaUrls, isFalse);
  });

  test('provider and model version constraints are independently applied', () {
    final cache = _cache(<Map<String, Object?>>[
      _provider(<Map<String, Object?>>[
        _model('always'),
        _model('exact', availability: <String, Object?>{'version': '1.2.3'}),
        _model(
          'range',
          availability: <String, Object?>{
            'min_version': '1.2.0',
            'max_version': '1.9.0',
          },
        ),
        _model(
          'future',
          availability: <String, Object?>{'min_version': '2.0.0'},
        ),
      ]),
    ]);

    final bundle = ProviderCatalogBundle.fromCache(cache, appVersion: '1.2.3');
    expect(bundle.providers.single.models.map((model) => model.id), <String>[
      'always',
      'exact',
      'range',
    ]);
  });

  test(
    'discrete duration choices and mode-specific inputs survive manifests',
    () {
      final bundle = ProviderCatalogBundle.fromCache(
        _cache(<Map<String, Object?>>[
          _provider(<Map<String, Object?>>[
            <String, Object?>{
              ..._model('draft', minDuration: 5, maxDuration: 30),
              'modes': <String>['t2v', 'draft_enhance'],
              'resolutions': <Map<String, String>>[
                <String, String>{'id': 'sd', 'label': '480p', 'detail': '480p'},
                <String, String>{
                  'id': 'fhd',
                  'label': '1080p',
                  'detail': '1080p',
                },
              ],
              'duration_options': <int>[5, 10, 20, 30],
              'draft_source_is_task_id': true,
              'resolutions_by_mode': <String, Object?>{
                't2v': <String>['sd'],
                'draft_enhance': <String>['fhd'],
              },
            },
          ]),
        ]),
      );
      final model = bundle.providers.single.models.single;
      expect(model.durationOptions, <int>[5, 10, 20, 30]);
      expect(model.draftSourceIsTaskId, isTrue);
      expect(model.resolutionsByMode, <VideoMode, List<String>>{
        VideoMode.t2v: <String>['sd'],
        VideoMode.draftEnhance: <String>['fhd'],
      });
    },
  );

  test('invalid discrete duration choices cannot enter the catalog', () {
    for (final values in <List<num>>[
      <int>[0, 5],
      <int>[4, 10],
      <int>[5, 31],
      <int>[10, 5],
      <int>[5, 5],
      <num>[5, 7.5],
    ]) {
      expect(
        () => ProviderCatalogBundle.fromCache(
          _cache(<Map<String, Object?>>[
            _provider(<Map<String, Object?>>[
              <String, Object?>{
                ..._model('limited', minDuration: 5, maxDuration: 30),
                'duration_options': values,
              },
            ]),
          ]),
        ),
        throwsA(isA<ProviderCatalogManifestException>()),
        reason: '$values',
      );
    }
  });

  test('a stale normal catalog cannot replace newer bundled capabilities', () {
    expect(
      () => ProviderCatalogBundle.fromCache(
        _cache(<Map<String, Object?>>[
          _provider(<Map<String, Object?>>[_model('old-model')]),
        ], catalogVersion: '0.62.0'),
        appVersion: '0.63.0',
        mobileTestBuild: false,
      ),
      throwsA(isA<ProviderCatalogManifestException>()),
    );
  });

  test(
    'current and newer catalogs can intentionally remove bundled models',
    () {
      for (final version in <String>['0.63.0', '0.64.0']) {
        final bundle = ProviderCatalogBundle.fromCache(
          _cache(<Map<String, Object?>>[
            _provider(<Map<String, Object?>>[_model('replacement-model')]),
          ], catalogVersion: version),
          appVersion: '0.63.0',
          mobileTestBuild: false,
        );
        expect(bundle.providers.map((provider) => provider.id), <String>[
          'bfl',
        ]);
        expect(bundle.providers.single.models.single.id, 'replacement-model');
      }
    },
  );

  test('model image pixel ceilings must be positive', () {
    final cache = _cache(<Map<String, Object?>>[
      _provider(<Map<String, Object?>>[
        _model('invalid-image-cap', maxInputImagePixels: 0),
      ]),
    ]);

    expect(
      () => ProviderCatalogBundle.fromCache(cache, appVersion: '1.2.3'),
      throwsA(isA<ProviderCatalogManifestException>()),
    );

    final byteCache = _cache(<Map<String, Object?>>[
      _provider(<Map<String, Object?>>[
        _model('invalid-image-byte-cap', maxInputImageBytes: -1),
      ]),
    ]);
    expect(
      () => ProviderCatalogBundle.fromCache(byteCache, appVersion: '1.2.3'),
      throwsA(isA<ProviderCatalogManifestException>()),
    );
  });

  test('mobile test versions keep constrained Seedance and Apple local', () {
    final cache = _cache(
      <Map<String, Object?>>[
        _provider(
          <Map<String, Object?>>[
            _model(
              mobileTestModelId,
              resolutions: const <Map<String, String>>[
                <String, String>{
                  'id': 'fhd',
                  'label': 'Full HD',
                  'detail': '1920 × 1080',
                },
                <String, String>{
                  'id': 'sd',
                  'label': '480p',
                  'detail': '854 × 480',
                },
              ],
              minDuration: 4,
              maxDuration: 12,
            ),
            _model('another-model'),
          ],
          id: mobileTestProviderId,
          adapter: mobileTestProviderId,
        ),
        _provider(<Map<String, Object?>>[_model('another-provider-model')]),
        _provider(
          <Map<String, Object?>>[
            _model('apple-local-image'),
            _model('apple-local-animation'),
          ],
          id: 'apple-local',
          adapter: 'apple-local',
          requiresApiKey: false,
          isLocal: true,
        ),
      ],
      catalogVersion: '1.2.3',
      testVersions: const <String>['1.2.3'],
    );

    final bundle = ProviderCatalogBundle.fromCache(
      cache,
      appVersion: '1.2.3',
      mobileTestBuild: true,
    );

    expect(bundle.isMobileTest, isTrue);
    expect(bundle.providers.map((provider) => provider.id).toList(), <String>[
      mobileTestProviderId,
      'apple-local',
    ]);
    final model = bundle.providers.first.models.single;
    expect(model.id, mobileTestModelId);
    expect(model.resolutions.single.id, mobileTestResolutionId);
    expect(model.minDuration, mobileTestDurationSeconds);
    expect(model.maxDuration, mobileTestDurationSeconds);
    expect(model.supportsAutoDuration, isFalse);
  });

  test('a stale catalog cannot unlock a mobile test build', () {
    final cache = _cache(<Map<String, Object?>>[
      _provider(
        <Map<String, Object?>>[
          _model(
            mobileTestModelId,
            resolutions: const <Map<String, String>>[
              <String, String>{
                'id': 'sd',
                'label': '480p',
                'detail': '854 × 480',
              },
            ],
          ),
        ],
        id: mobileTestProviderId,
        adapter: mobileTestProviderId,
      ),
    ], catalogVersion: '1.2.2');

    final bundle = ProviderCatalogBundle.fromCache(
      cache,
      appVersion: '1.2.3',
      mobileTestBuild: true,
    );

    expect(bundle.isMobileTest, isTrue);
  });

  test('a current catalog removal unlocks the same mobile app version', () {
    final cache = _cache(<Map<String, Object?>>[
      _provider(
        <Map<String, Object?>>[
          _model(
            mobileTestModelId,
            resolutions: const <Map<String, String>>[
              <String, String>{
                'id': 'sd',
                'label': '480p',
                'detail': '854 × 480',
              },
            ],
          ),
          _model('restored-model'),
        ],
        id: mobileTestProviderId,
        adapter: mobileTestProviderId,
      ),
      _provider(<Map<String, Object?>>[_model('restored-provider-model')]),
    ], catalogVersion: '1.2.3');

    final bundle = ProviderCatalogBundle.fromCache(
      cache,
      appVersion: '1.2.3',
      mobileTestBuild: true,
    );

    expect(bundle.isMobileTest, isFalse);
    expect(bundle.providers, hasLength(2));
  });

  test('a catalog with no compatible provider leaves the fallback intact', () {
    final cache = _cache(<Map<String, Object?>>[
      _provider(
        <Map<String, Object?>>[_model('future')],
        availability: <String, Object?>{'min_version': '2.0.0'},
      ),
    ]);

    expect(
      () => ProviderCatalogBundle.fromCache(cache, appVersion: '1.0.0'),
      throwsA(isA<ProviderCatalogManifestException>()),
    );
    expect(videoProviders, bundledVideoProviders);
  });

  test('the catalog cache survives local data serialization', () {
    final cache = _cache(<Map<String, Object?>>[
      _provider(<Map<String, Object?>>[_model('cached')]),
    ]);

    final decoded = StoredData.decode(
      StoredData(providerCatalogCache: cache).encode(),
    );

    expect(decoded.toJson()['schemaVersion'], 26);
    expect(decoded.providerCatalogCache, cache);
  });

  test(
    'startup installs a valid cached catalog when the endpoint is down',
    () async {
      final cache = _cache(<Map<String, Object?>>[
        _provider(<Map<String, Object?>>[
          _model('cached', label: 'Cached model'),
        ]),
      ]);
      final gateway = _CatalogGateway(cache);
      final controller = AppController(
        gateway: gateway,
        providerCatalogClient: ProviderCatalogClient(
          client: MockClient((_) async => http.Response('offline', 503)),
          siteUrl: Uri.parse('https://clawnsole.app/'),
        ),
      );

      await controller.initialize();

      expect(controller.providers.single.models.single.label, 'Cached model');
      expect(gateway.saved, isNull);
      controller.dispose();
    },
  );

  test(
    'stale cached and live catalogs preserve newly shipped providers',
    () async {
      final staleCache = _cache(<Map<String, Object?>>[
        _provider(<Map<String, Object?>>[_model('cached')]),
      ], catalogVersion: '0.0.1');
      final gateway = _CatalogGateway(staleCache);
      final responses = <String, String>{
        '/models/': jsonEncode(<String, Object?>{
          'schema_version': 1,
          'catalog_version': '0.0.1',
          'providers': <String>['providers/bfl.yaml'],
        }),
        '/models/providers/bfl.yaml': jsonEncode(<String, Object?>{
          ..._provider(const <Map<String, Object?>>[]),
          'models': <String>['models/bfl/remote.yaml'],
        }),
        '/models/models/bfl/remote.yaml': jsonEncode(_model('old-remote')),
      };
      var offline = true;
      final controller = AppController(
        gateway: gateway,
        providerCatalogClient: ProviderCatalogClient(
          client: MockClient((request) async {
            if (offline) return http.Response('offline', 503);
            return http.Response(responses[request.url.path] ?? 'missing', 200);
          }),
          siteUrl: Uri.parse('https://clawnsole.app/'),
        ),
        mobileTestBuild: false,
      );
      addTearDown(controller.dispose);

      await controller.initialize();
      expect(
        controller.providers.any((provider) => provider.id == 'apipod'),
        isTrue,
      );
      offline = false;
      await controller.refreshProviderCatalog();
      expect(
        controller.providers.map((provider) => provider.id).toSet(),
        bundledVideoProviders.map((provider) => provider.id).toSet(),
      );
      expect(gateway.saved, isNull);
    },
  );

  test(
    'an offline mobile test build starts with the restricted form',
    () async {
      final controller = AppController(
        gateway: _CatalogGateway(null),
        providerCatalogClient: ProviderCatalogClient(
          client: MockClient((_) async => http.Response('offline', 503)),
          siteUrl: Uri.parse('https://clawnsole.app/'),
        ),
        mobileTestBuild: true,
      );

      await controller.initialize();

      expect(
        controller.providers.map((provider) => provider.id).toSet(),
        <String>{mobileTestProviderId, 'apple-local'},
      );
      expect(controller.selectedProviderId, mobileTestProviderId);
      expect(controller.selectedModelId, mobileTestModelId);
      expect(controller.form.resolution, mobileTestResolutionId);
      expect(controller.form.durationSeconds, mobileTestDurationSeconds);
      controller.dispose();
    },
  );

  test(
    'a complete remote catalog replaces and persists the cached one',
    () async {
      final gateway = _CatalogGateway(
        _cache(<Map<String, Object?>>[
          _provider(<Map<String, Object?>>[_model('cached')]),
        ]),
      );
      final responses = <String, String>{
        '/models/': '{"schema_version":1,"providers":["providers/bfl.yaml"]}',
        '/models/providers/bfl.yaml':
            '{"schema_version":1,"id":"bfl","adapter":"bfl","name":"BFL","description":"Remote","console_url":"https://example.com/console","docs_url":"https://example.com/docs","pricing_url":"https://example.com/pricing","models":["models/bfl/remote.yaml"]}',
        '/models/models/bfl/remote.yaml': _yaml(
          _model('remote', label: 'Remote model'),
        ),
      };
      final controller = AppController(
        gateway: gateway,
        providerCatalogClient: ProviderCatalogClient(
          client: MockClient(
            (request) async => http.Response.bytes(
              utf8.encode(responses[request.url.path] ?? 'missing'),
              responses.containsKey(request.url.path) ? 200 : 404,
            ),
          ),
          siteUrl: Uri.parse('https://clawnsole.app/'),
        ),
      );
      await controller.initialize();

      await controller.refreshProviderCatalog();

      expect(controller.providers.single.models.single.label, 'Remote model');
      expect(gateway.saved, isNotNull);
      expect(
        (gateway.saved!['providers']! as List<Object?>).single,
        isA<Map<Object?, Object?>>(),
      );
      controller.dispose();
    },
  );
}

Map<String, Object?> _cache(
  List<Map<String, Object?>> providers, {
  String? catalogVersion,
  List<String> testVersions = const <String>[],
}) => <String, Object?>{
  'schema_version': 1,
  if (catalogVersion != null) 'catalog_version': catalogVersion,
  'test_versions': testVersions,
  'providers': providers,
};

Map<String, Object?> _provider(
  List<Map<String, Object?>> models, {
  Map<String, Object?>? availability,
  String id = 'bfl',
  String? adapter,
  bool requiresApiKey = true,
  bool isLocal = false,
}) => <String, Object?>{
  'schema_version': 1,
  'id': id,
  'adapter': adapter ?? id,
  'name': 'Black Forest Labs',
  'description': 'Video generation.',
  'console_url': 'https://example.com/console',
  'docs_url': 'https://example.com/docs',
  'pricing_url': 'https://example.com/pricing',
  'requires_api_key': requiresApiKey,
  'is_local': isLocal,
  if (availability != null) 'availability': availability,
  'models': models,
};

Map<String, Object?> _model(
  String id, {
  String? label,
  Map<String, Object?>? availability,
  List<Map<String, String>> resolutions = const <Map<String, String>>[
    <String, String>{'id': 'hd', 'label': 'HD', 'detail': '1280 × 720'},
  ],
  int minDuration = 1,
  int maxDuration = 2,
  int? maxInputImagePixels,
  int? maxInputImageBytes,
}) => <String, Object?>{
  'schema_version': 1,
  'id': id,
  'label': label ?? id,
  'description': 'A test model.',
  'modes': <String>['t2v'],
  'aspect_ratios': <String>['16:9'],
  'resolutions': resolutions,
  'min_duration': minDuration,
  'max_duration': maxDuration,
  'duration_step': 1,
  'max_keyframes': 0,
  if (maxInputImagePixels != null)
    'max_input_image_pixels': maxInputImagePixels,
  if (maxInputImageBytes != null) 'max_input_image_bytes': maxInputImageBytes,
  'usd_per_second': .1,
  if (availability != null) 'availability': availability,
};

String _yaml(Map<String, Object?> value) {
  String encode(Object? item) => switch (item) {
    final String text =>
      '"${text.replaceAll('\\', '\\\\').replaceAll('"', '\\"')}"',
    final num number => '$number',
    final bool flag => '$flag',
    final List<Object?> values => '[${values.map(encode).join(',')}]',
    final Map<Object?, Object?> values =>
      '{${values.entries.map((entry) => '${encode(entry.key.toString())}:${encode(entry.value)}').join(',')}}',
    null => 'null',
    _ => throw StateError('Unsupported test YAML value.'),
  };
  return encode(value);
}

class _CatalogGateway implements AppGateway, ProviderCatalogCacheGateway {
  _CatalogGateway(this.cache);

  Map<String, Object?>? cache;
  Map<String, Object?>? saved;

  LocalSnapshot get _snapshot => const LocalSnapshot(
    generations: <Generation>[],
    preferences: AppPreferences(provider: 'bfl', model: 'cached'),
    hasApiKey: false,
    availableProviders: <String>{...remoteProviderIds, 'apple-local'},
    storage: StorageStats(path: '', bytes: 0, records: 0),
  );

  @override
  bool get supportsPhotoLibrarySave => false;
  @override
  bool get usesCompanion => false;
  @override
  String get persistenceDescription => 'test';
  @override
  Future<Map<String, Object?>?> loadProviderCatalogCache() async => cache;
  @override
  Future<void> saveProviderCatalogCache(Map<String, Object?> value) async {
    cache = value;
    saved = value;
  }

  @override
  Future<LocalSnapshot> load() async => _snapshot;
  @override
  Future<LocalSnapshot> setApiKey(String value) async => _snapshot;
  @override
  Future<double> verifyKey([String? candidate]) async => 0;
  @override
  Future<double> getCredits() async => 0;
  @override
  Future<LocalSnapshot> setPreferences(AppPreferences preferences) async =>
      _snapshot;
  @override
  Future<Generation> submit(GenerationSubmission submission) =>
      throw UnimplementedError();
  @override
  Future<Generation> poll(Generation generation) => throw UnimplementedError();
  @override
  Future<LocalSnapshot> deleteGeneration(String localId) async => _snapshot;
  @override
  Future<LocalSnapshot> clearHistory() async => _snapshot;
  @override
  Future<LocalSnapshot> clearPreferences() async => _snapshot;
  @override
  Future<LocalSnapshot> clearApiKey() async => _snapshot;
  @override
  Future<LocalSnapshot> clearAll() async => _snapshot;
  @override
  Future<Uri> assetUri(AssetReference reference) => throw UnimplementedError();
  @override
  Future<Uint8List> readAsset(AssetReference reference) =>
      throw UnimplementedError();
  @override
  Uri mediaUri(String source) => Uri.parse(source);
  @override
  Future<Uint8List> downloadMedia(String source) => throw UnimplementedError();
  @override
  Future<void> saveMediaToPhotoLibrary(
    Uint8List bytes,
    String fileName,
    String contentType,
  ) => throw UnimplementedError();
}
