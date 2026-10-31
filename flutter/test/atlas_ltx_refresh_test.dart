import 'dart:convert';
import 'dart:io';

import 'package:clawnsole/core/atlas_cloud_api.dart';
import 'package:clawnsole/core/bfl_api.dart';
import 'package:clawnsole/core/ltx_api.dart';
import 'package:clawnsole/core/models.dart';
import 'package:clawnsole/core/pricing.dart';
import 'package:clawnsole/core/provider_catalog.dart';
import 'package:clawnsole/core/provider_manifest.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  test(
    'new manifests validate and remain hidden from older adapters',
    () async {
      final client = MockClient((request) async {
        final path = request.url.path == '/models/'
            ? 'index.html'
            : request.url.path.replaceFirst('/models/', '');
        return http.Response.bytes(
          File('../docs/models/$path').readAsBytesSync(),
          200,
        );
      });
      final catalog = ProviderCatalogClient(
        client: client,
        siteUrl: Uri.parse('https://clawnsole.app/'),
      );
      final previous = await catalog.fetch(appVersion: '0.60.1');
      final updated = await catalog.fetch(appVersion: '0.61.0');
      for (final providerId in <String>['atlas', 'ltx']) {
        final before = previous.providers.firstWhere((p) => p.id == providerId);
        final after = updated.providers.firstWhere((p) => p.id == providerId);
        final added = after.models.where(
          (model) => !before.models.any((old) => old.id == model.id),
        );
        expect(added, hasLength(providerId == 'atlas' ? 25 : 2));
      }
    },
  );

  test(
    'Atlas inventory quotes cannot price a different resolution or audio mode',
    () async {
      final api = AtlasCloudApi(
        client: MockClient((request) async {
          if (request.url.path.endsWith('/calculate')) {
            final body = jsonDecode(request.body) as Map<String, dynamic>;
            return http.Response(
              jsonEncode(<String, Object?>{
                'data': <String, Object?>{
                  'price': (body['duration'] as num) * .08,
                },
              }),
              200,
            );
          }
          return http.Response(
            jsonEncode(<String, Object?>{
              'data': <Object?>[
                <String, Object?>{
                  'model': 'bytedance/seedance-2.0/text-to-video',
                  'type': 'Video',
                  'categories': <String>['TEXT-TO-VIDEO'],
                  'price': <String, Object?>{
                    'actual': <String, Object?>{'base_price': '.09'},
                  },
                },
              ],
            }),
            200,
          );
        }),
      );
      final prices = await api.listVideoModels();
      expect(
        prices.single.model,
        'bytedance/seedance-2.0/text-to-video:720p:audio',
      );
      expect(
        estimateCost(
          'atlas',
          'bytedance/seedance-2.0/text-to-video',
          VideoMode.t2v,
          _config('hd'),
          const <Generation>[],
          prices,
        ).minimumUsd,
        .8,
      );
      expect(
        estimateCost(
          'atlas',
          'bytedance/seedance-2.0/text-to-video',
          VideoMode.t2v,
          _config('fhd'),
          const <Generation>[],
          prices,
        ).basis,
        'published-fallback',
      );
      const silent = GenerationConfig(
        aspectRatio: '16:9',
        duration: 10,
        resolution: 'hd',
        generateAudio: false,
        safetyTolerance: 2,
        draft: false,
      );
      expect(
        estimateCost(
          'atlas',
          'bytedance/seedance-2.0/text-to-video',
          VideoMode.t2v,
          silent,
          const <Generation>[],
          prices,
        ).basis,
        'published-fallback',
      );
    },
  );

  test('new Atlas routes obey the provider-published request schemas', () {
    // Snapshot of Input.required and validation fields from the official
    // static.atlascloud.ai schemas, retrieved October 30, 2026.
    final schemas =
        jsonDecode(
              File(
                'test/fixtures/atlas_october_2026_schemas.json',
              ).readAsStringSync(),
            )
            as Map<String, dynamic>;
    final api = AtlasCloudApi();
    for (final entry in schemas.entries) {
      final model = modelById('atlas', entry.key);
      final schema = entry.value as Map<String, dynamic>;
      final properties = schema['properties'] as Map<String, dynamic>;
      for (final resolution in model.resolutions) {
        for (final ratio in model.aspectRatios) {
          for (final duration in <int>{
            model.minDuration,
            model.maxDurationFor(resolution.id),
          }) {
            final input = <String, Object?>{
              'prompt': 'A waterfall in the forest',
              'resolution': resolution.id,
              'aspect_ratio': ratio,
              'duration': duration,
              'generate_audio': false,
              if (model.supportsSeed) 'seed': 42,
              if (model.maxKeyframes > 0)
                'keyframes': List<String>.generate(
                  model.maxKeyframes,
                  (index) => 'https://example.com/frame-$index.png',
                ),
            };
            final payload = api.generationPayload(model.id, input);
            for (final required in schema['required'] as List<dynamic>) {
              expect(payload, contains(required), reason: model.id);
            }
            for (final field in payload.entries) {
              expect(properties, contains(field.key), reason: model.id);
              final rule = properties[field.key] as Map<String, dynamic>;
              if (rule['enum'] != null) {
                expect(
                  rule['enum'],
                  contains(field.value),
                  reason: '${model.id} ${field.key}',
                );
              }
              if (rule['minimum'] != null) {
                expect(
                  field.value,
                  greaterThanOrEqualTo(rule['minimum'] as num),
                );
              }
              if (rule['maximum'] != null) {
                expect(field.value, lessThanOrEqualTo(rule['maximum'] as num));
              }
            }
          }
        }
      }
    }
  });

  test('Wan 3 uploads local first and last frames before submitting', () async {
    final submitted = <Map<String, dynamic>>[];
    var uploads = 0;
    final api = AtlasCloudApi(
      client: MockClient((request) async {
        if (request.url.path.endsWith('/uploadMedia')) {
          uploads++;
          return http.Response(
            jsonEncode(<String, Object?>{
              'data': <String, Object?>{
                'url': 'https://example.com/upload-$uploads.png',
              },
            }),
            200,
          );
        }
        final payload = jsonDecode(request.body) as Map<String, dynamic>;
        if (request.url.path.endsWith('/calculate')) {
          return http.Response('{"data":{"price":0.5}}', 200);
        }
        submitted.add(payload);
        return http.Response('{"data":{"id":"wan-job"}}', 200);
      }),
    );
    await api.submit(
      'secret',
      'alibaba/wan-3.0/image-to-video',
      <String, Object?>{
        'prompt': 'A tree in the wind',
        'duration': 5,
        'resolution': 'hd',
        'keyframes': <Object?>[
          <Object?>[0, 'data:image/png;base64,aGVsbG8='],
          <Object?>[5, 'data:image/png;base64,aGVsbG8='],
        ],
      },
    );
    expect(uploads, 2);
    expect(submitted.single['image'], 'https://example.com/upload-1.png');
    expect(submitted.single['last_image'], 'https://example.com/upload-2.png');
  });

  test('LTX 2.5 sends square and 3:2 dimensions with auto duration', () async {
    final requests = <Map<String, dynamic>>[];
    final api = LtxApi(
      client: MockClient((request) async {
        requests.add(jsonDecode(request.body) as Map<String, dynamic>);
        return http.Response('{"id":"ltx-job"}', 200);
      }),
    );
    for (final ratio in <String>['1:1', '3:2', '2:3']) {
      await api.submit('secret', 'ltx-2-5-pro', <String, Object?>{
        'prompt': 'A bird flies',
        'mode': 't2v',
        'resolution': 'fhd',
        'aspect_ratio': ratio,
        'duration': 'auto',
      });
    }
    expect(requests.map((request) => request['resolution']), <String>[
      '1080x1080',
      '1620x1080',
      '1080x1620',
    ]);
    for (final request in requests) {
      expect(request, contains('duration'));
      expect(request['duration'], isNull);
    }
    await expectLater(
      api.submit('secret', 'ltx-2-5-pro', <String, Object?>{
        'mode': 'i2v',
        'duration': 'auto',
        'keyframes': <String>[
          'https://example.com/a.png',
          'https://example.com/b.png',
        ],
      }),
      throwsA(isA<ProviderException>()),
    );
    expect(requests, hasLength(3));
  });

  test('LTX prices every model resolution and bills driving audio length', () {
    const rates = <String, List<double>>{
      'ltx-2-5-fast': <double>[.09, .13, .19, .30],
      'ltx-2-5-pro': <double>[.12, .17, .25, .39],
      'ltx-2-3-fast': <double>[.03, .06, .12, .24],
      'ltx-2-3-pro': <double>[.04, .08, .16, .32],
    };
    const resolutions = <String>['hd', 'fhd', 'qhd', '4k'];
    for (final entry in rates.entries) {
      for (var index = 0; index < resolutions.length; index++) {
        final resolution = resolutions[index];
        for (final prices in <List<ProviderModelPrice>>[
          <ProviderModelPrice>[],
          publishedProviderPrices('ltx'),
        ]) {
          expect(
            estimateCost(
              'ltx',
              entry.key,
              VideoMode.t2v,
              _config(resolution),
              const <Generation>[],
              prices,
            ).minimumUsd,
            closeTo(entry.value[index] * 10, .0001),
          );
          if (entry.key == 'ltx-2-3-fast') continue;
          final audioRate = entry.key == 'ltx-2-3-pro'
              ? <double>[.06, .10, .18, .34][index]
              : entry.value[index];
          final estimate = estimateCost(
            'ltx',
            entry.key,
            VideoMode.i2v,
            _config(resolution, audio: true),
            const <Generation>[],
            prices,
          );
          expect(estimate.minimumUsd, closeTo(audioRate * 7, .0001));
          expect(estimate.maximumUsd, estimate.minimumUsd);
        }
      }
    }
    final auto = estimateCost(
      'ltx',
      'ltx-2-5-fast',
      VideoMode.t2v,
      _config('4k', duration: 'auto'),
    );
    expect(auto.minimumUsd, 1.8);
    expect(auto.maximumUsd, 3);
  });

  test('Atlas Hailuo clip prices are not multiplied as per-second prices', () {
    for (final duration in <int>[6, 10]) {
      final expected = duration == 6 ? .28 : .56;
      for (final model in <String>[
        'minimax/hailuo-2.3/t2v-standard',
        'minimax/hailuo-2.3/i2v-standard',
      ]) {
        expect(
          estimateCost(
            'atlas',
            model,
            VideoMode.t2v,
            _config('hd', duration: duration),
          ).minimumUsd,
          expected,
        );
        expect(
          publishedProviderPrices(
            'atlas',
          ).firstWhere((row) => row.model == model).priceFor(duration),
          expected,
        );
      }
    }
  });
}

GenerationConfig _config(
  String resolution, {
  Object duration = 10,
  bool audio = false,
}) => GenerationConfig(
  aspectRatio: '16:9',
  duration: duration,
  resolution: resolution,
  generateAudio: true,
  safetyTolerance: 2,
  draft: false,
  references: audio
      ? const <MediaReferenceLabel>[
          MediaReferenceLabel(
            label: 'Dialogue',
            kind: MediaReferenceKind.audio,
            durationSeconds: 7,
          ),
        ]
      : null,
);
