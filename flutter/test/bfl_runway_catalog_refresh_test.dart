import 'dart:convert';
import 'dart:io';

import 'package:clawnsole/core/bfl_api.dart';
import 'package:clawnsole/core/models.dart';
import 'package:clawnsole/core/pricing.dart';
import 'package:clawnsole/core/provider_catalog.dart';
import 'package:clawnsole/core/provider_manifest.dart';
import 'package:clawnsole/core/runway_api.dart';
import 'package:clawnsole/core/runway_pricing.dart'
    show runwayKling4DurationPrices;
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  tearDown(resetProviderCatalog);

  test(
    'new Runway routes respect the audited OpenAPI fields and geometry',
    () async {
      final fixture =
          jsonDecode(
                File(
                  'test/fixtures/runway-video-contracts-2026-10-30.json',
                ).readAsStringSync(),
              )
              as Map<String, dynamic>;
      final endpoints = fixture['endpoints'] as Map<String, dynamic>;
      final ids = (endpoints['/v1/text_to_video'] as Map<String, dynamic>).keys;
      final api = RunwayApi(
        client: MockClient((request) async {
          final payload = jsonDecode(request.body) as Map<String, dynamic>;
          final schema =
              endpoints[request.url.path][payload['model']]
                  as Map<String, dynamic>;
          final reason = '${payload['model']} ${request.url.path}: $payload';
          expect(
            payload.keys,
            containsAll(schema['required'] as List<dynamic>),
            reason: reason,
          );
          expect(schema['allowed'], containsAll(payload.keys), reason: reason);
          if (payload.containsKey('ratio')) {
            expect(
              schema['ratios'],
              contains(payload['ratio']),
              reason: reason,
            );
          }
          return http.Response('{"id":"contract-checked"}', 200);
        }),
      );
      for (final id in ids) {
        final model = modelById('runway', id);
        for (final mode in model.modes) {
          for (final resolution in model.resolutions) {
            for (final ratio in model.aspectRatiosFor(
              resolution.id,
              mode: mode,
              withFrames: mode == VideoMode.i2v,
            )) {
              await api.submit('test-key', id, <String, Object?>{
                'mode': mode.name,
                'prompt': 'A camera follows a person through a quiet garden.',
                'duration': model.minDuration,
                'resolution': resolution.id,
                'aspect_ratio': ratio,
                'generate_audio': true,
                if (mode == VideoMode.i2v)
                  'keyframes': <String>[
                    'https://example.test/first.png',
                    if (model.supportsEndFrame) 'https://example.test/last.png',
                  ],
                if (mode == VideoMode.v2v)
                  'start_video': 'https://example.test/source.mp4',
              });
            }
          }
        }
      }
    },
  );

  test(
    'Runway creative video references retain route-specific objects',
    () async {
      late Map<String, dynamic> payload;
      final api = RunwayApi(
        client: MockClient((request) async {
          expect(request.url.path, '/v1/text_to_video');
          payload = jsonDecode(request.body) as Map<String, dynamic>;
          return http.Response('{"id":"references"}', 200);
        }),
      );
      for (final model in <String>[
        'wan3',
        'wan3_prime',
        'gemini_omni_flash_1.1',
        'kling_4',
      ]) {
        await api.submit('test-key', model, <String, Object?>{
          'mode': 'i2v',
          'prompt': 'Use the reference motion.',
          'duration': 5,
          'resolution': 'hd',
          'aspect_ratio': '16:9',
          'reference_images': <String>['https://example.test/reference.png'],
          'reference_videos': <String>['https://example.test/reference.mp4'],
        });
        final reference =
            (payload['referenceVideos'] as List<dynamic>).single
                as Map<String, dynamic>;
        expect(reference['uri'], 'https://example.test/reference.mp4');
        expect(reference.containsKey('type'), model.startsWith('wan3'));
        expect(payload, isNot(contains('promptImage')));
      }
    },
  );

  test(
    'BFL routes editing separately and maps 4K to its uhd wire value',
    () async {
      final requests = <http.Request>[];
      final api = BflApi(
        client: MockClient((request) async {
          requests.add(request);
          return http.Response(
            '{"id":"bfl-task","polling_url":"https://api.bfl.ai/v1/get_result?id=bfl-task"}',
            200,
          );
        }),
      );
      await api.submit('test-key', <String, Object?>{
        'mode': 'v2v',
        'prompt': 'Change the coat to blue.',
        'start_video': 'data:video/mp4;base64,dm9pY2U=',
        'duration': 'source',
        'aspect_ratio': 'auto',
        'resolution': 'source',
        'generate_audio': true,
        'safety_tolerance': 2,
        'version': 'latest',
        'draft': false,
      }, model: 'flux-tools-video-edit-v1');
      expect(requests.first.url.path, '/v1/flux-tools/video-edit-v1');
      expect(jsonDecode(requests.first.body), <String, Object?>{
        'video': 'dm9pY2U=',
        'prompt': 'Change the coat to blue.',
        'safety_tolerance': 2,
      });
      await api.submit('test-key', <String, Object?>{
        'mode': 't2v',
        'prompt': 'A landscape.',
        'resolution': '4k',
      });
      expect(jsonDecode(requests.last.body)['resolution'], 'uhd');
    },
  );

  test(
    'BFL current prices cover all resolutions, edits, and upscale units',
    () {
      for (final tier in <(String, double, double)>[
        ('hd', .15, .21),
        ('fhd', .24, .27),
        ('qhd', .28, .31),
        ('4k', .41, .45),
      ]) {
        expect(
          estimateCost(
            'bfl',
            'flux-3-video',
            VideoMode.t2v,
            _config(tier.$1),
          ).minimumUsd,
          closeTo(tier.$2 * 5, .00001),
        );
        expect(
          estimateCost(
            'bfl',
            'flux-3-video',
            VideoMode.v2v,
            _config(tier.$1),
          ).minimumUsd,
          closeTo(tier.$3 * 5, .00001),
        );
      }
      final edit = estimateCost(
        'bfl',
        'flux-tools-video-edit-v1',
        VideoMode.v2v,
        _config('source'),
        const <Generation>[],
        const <ProviderModelPrice>[],
        const VideoSourceMetadata(
          width: 1280,
          height: 720,
          durationSeconds: 10,
        ),
      );
      expect(edit.minimumUsd, .3);
      final upscale = estimateCost(
        'bfl',
        'flux-tools-video-upscale-v1',
        VideoMode.upscale,
        _config('source').copyWith(upscaleCreativity: 0, upscaleFactor: 2),
        const <Generation>[],
        const <ProviderModelPrice>[],
        const VideoSourceMetadata(width: 512, height: 512, durationSeconds: 10),
      );
      expect(upscale.minimumUsd, closeTo(.35, .00001));
    },
  );

  test(
    'Runway prices use current tiers without requiring a model-guide fetch',
    () {
      for (final tier in <(String, String, double)>[
        ('seedance2', 'sd', .14),
        ('seedance2', 'hd', .30),
        ('seedance2_fast', 'sd', .11),
        ('seedance2_fast', 'hd', .24),
        ('seedance2_mini', 'sd', .07),
        ('seedance2_mini', 'hd', .15),
        ('wan3', 'fhd', .20),
        ('wan3_prime', 'sd', .068),
        ('h3_max', 'hd', .08),
        ('grok_imagine_1_5_lite', 'fhd', .14),
        ('gemini_omni_flash_1.1', '360p', .034),
      ]) {
        final estimate = estimateCost(
          'runway',
          tier.$1,
          VideoMode.t2v,
          _config(tier.$2),
        );
        expect(
          estimate.minimumUsd,
          closeTo(tier.$3 * 5, .00001),
          reason: '${tier.$1} ${tier.$2}',
        );
      }
      expect(
        estimateCost(
          'runway',
          'kling3.0_standard',
          VideoMode.t2v,
          _config('hd', audio: false),
        ).minimumUsd,
        .45,
      );
      expect(
        estimateCost(
          'runway',
          'kling3.0_standard',
          VideoMode.t2v,
          _config('hd'),
        ).minimumUsd,
        .65,
      );
    },
  );

  test(
    'Kling 4 rounds twice during its dated promotion and expires in UTC',
    () {
      expect(
        runwayKling4Credits(
          resolution: 'hd',
          outputSeconds: 5,
          inputSeconds: 0,
          hasInputVideo: false,
          asOf: DateTime.utc(2026, 10, 30),
        ),
        64,
      );
      expect(
        runwayKling4Credits(
          resolution: 'hd',
          outputSeconds: 5,
          inputSeconds: 0,
          hasInputVideo: false,
          asOf: DateTime.utc(2026, 12, 1),
        ),
        79,
      );
      expect(
        runwayKling4Credits(
          resolution: 'hd',
          outputSeconds: 5,
          inputSeconds: 10,
          hasInputVideo: true,
          asOf: DateTime.utc(2026, 10, 30),
        ),
        113,
      );
      expect(
        runwayKling4Credits(
          resolution: 'hd',
          outputSeconds: 5,
          inputSeconds: 2,
          hasInputVideo: true,
          asOf: DateTime.utc(2026, 10, 30),
        ),
        76,
      );
    },
  );

  test(
    'Kling 4 bounds unmeasured references and waits for edit source duration',
    () {
      final pending = estimateCost(
        'runway',
        'kling_4',
        VideoMode.t2v,
        _config('hd').copyWith(
          references: const [
            MediaReferenceLabel(
              label: 'measured',
              kind: MediaReferenceKind.video,
              durationSeconds: 10,
            ),
            MediaReferenceLabel(
              label: 'pending',
              kind: MediaReferenceKind.video,
            ),
          ],
        ),
      );
      expect(pending.isAvailable, isTrue);
      expect(
        pending.providerUnitsMinimum,
        runwayKling4Credits(
          resolution: 'hd',
          outputSeconds: 5,
          inputSeconds: 10,
          hasInputVideo: true,
        ),
      );
      expect(
        pending.providerUnitsMaximum,
        runwayKling4Credits(
          resolution: 'hd',
          outputSeconds: 5,
          inputSeconds: 30,
          hasInputVideo: true,
        ),
      );
      expect(pending.maximumUsd, greaterThan(pending.minimumUsd));

      final unmeasuredEdit = estimateCost(
        'runway',
        'kling_4',
        VideoMode.v2v,
        _config('hd'),
      );
      expect(unmeasuredEdit.isAvailable, isFalse);
      expect(unmeasuredEdit.quotedMinimumUsd, isNull);
      expect(unmeasuredEdit.quotedMaximumUsd, isNull);

      final measuredEdit = estimateCost(
        'runway',
        'kling_4',
        VideoMode.v2v,
        _config('hd'),
        const [],
        const [],
        const VideoSourceMetadata(
          width: 1280,
          height: 720,
          durationSeconds: 10,
        ),
      );
      expect(measuredEdit.isAvailable, isTrue);
      expect(measuredEdit.minimumUsd, measuredEdit.maximumUsd);
      expect(
        measuredEdit.providerUnitsMinimum,
        runwayKling4Credits(
          resolution: 'hd',
          outputSeconds: 10,
          inputSeconds: 10,
          hasInputVideo: true,
        ),
      );
    },
  );

  test(
    'Kling 4 cost desk preserves rounded totals before and after expiry',
    () {
      final during = runwayKling4DurationPrices(
        resolution: 'hd',
        asOf: DateTime.utc(2026, 11, 30, 23, 59, 59),
      );
      final expired = runwayKling4DurationPrices(
        resolution: 'hd',
        asOf: DateTime.parse('2026-11-30T19:00:00-05:00'),
      );
      expect(during, hasLength(28));
      expect(during[5], .64);
      expect(during[10], 1.26);
      expect(expired[5], .79);
      expect(expired[10], 1.57);
      expect(
        runwayKling4DurationPrices(
          resolution: 'fhd',
          asOf: DateTime.utc(2026, 10, 30),
        )[5],
        .95,
      );

      final rows = publishedProviderPrices('runway');
      for (final tier in const <(String, String)>[
        ('hd', '720p'),
        ('fhd', '1080p'),
      ]) {
        final row = rows.firstWhere((row) => row.model == 'kling_4:${tier.$2}');
        expect(row.durationPrices, hasLength(28));
        for (var seconds = 3; seconds <= 30; seconds++) {
          final estimate = estimateCost(
            'runway',
            'kling_4',
            VideoMode.t2v,
            GenerationConfig(
              aspectRatio: '16:9',
              duration: seconds,
              resolution: tier.$1,
              generateAudio: true,
              safetyTolerance: 2,
              draft: false,
            ),
          );
          expect(row.priceFor(seconds), closeTo(estimate.minimumUsd, .000001));
          expect(
            row.priceFor(seconds, withReferences: true),
            closeTo(estimate.minimumUsd, .000001),
          );
        }
      }
    },
  );

  test(
    'new routes are version gated and older installs retain FLUX 3',
    () async {
      final client = MockClient((request) async {
        final relative = request.url.path == '/models/'
            ? 'index.html'
            : request.url.path.replaceFirst('/models/', '');
        return http.Response.bytes(
          await File('../docs/models/$relative').readAsBytes(),
          200,
        );
      });
      final api = ProviderCatalogClient(
        client: client,
        siteUrl: Uri.parse('https://clawnsole.app/'),
      );
      final old = await api.fetch(appVersion: '0.60.1');
      final current = await api.fetch(appVersion: '0.61.0');
      final oldBfl = old.providers.singleWhere((p) => p.id == 'bfl');
      final newBfl = current.providers.singleWhere((p) => p.id == 'bfl');
      expect(oldBfl.models.map((m) => m.id), contains('flux-3-video'));
      expect(
        oldBfl.models.map((m) => m.id),
        isNot(contains('flux-tools-video-edit-v1')),
      );
      expect(
        oldBfl.models
            .firstWhere((m) => m.id == 'flux-3-video')
            .resolutions
            .map((r) => r.id),
        <String>['hd', 'fhd'],
      );
      expect(
        newBfl.models
            .firstWhere((m) => m.id == 'flux-3-video')
            .resolutions
            .map((r) => r.id),
        contains('4k'),
      );
      expect(
        current.providers
            .singleWhere((p) => p.id == 'runway')
            .models
            .map((m) => m.id),
        containsAll(<String>[
          'kling_4',
          'wan3',
          'h3_max',
          'gemini_omni_flash_1.1',
        ]),
      );
      expect(
        old.providers
            .singleWhere((p) => p.id == 'runway')
            .models
            .map((m) => m.id),
        isNot(contains('kling_4')),
      );
    },
  );
}

GenerationConfig _config(String resolution, {bool audio = true}) =>
    GenerationConfig(
      aspectRatio: '16:9',
      duration: 5,
      resolution: resolution,
      generateAudio: audio,
      safetyTolerance: 2,
      draft: false,
    );
