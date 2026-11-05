import 'dart:convert';
import 'dart:io';

import 'package:clawnsole/core/apipod_catalog.dart';
import 'package:clawnsole/core/apipod_model_contracts.dart';
import 'package:clawnsole/core/models.dart';
import 'package:clawnsole/core/pricing.dart';
import 'package:clawnsole/core/provider_catalog.dart';
import 'package:clawnsole/core/provider_manifest.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  test('all 103 active routes map every advertised scalar option', () {
    expect(apipodProvider.models, hasLength(103));
    expect(apipodProvider.models.map((m) => m.id).toSet(), hasLength(103));
    final coverage =
        jsonDecode(
              File('../docs/models/apipod-coverage.json').readAsStringSync(),
            )
            as Map<String, dynamic>;
    expect(
      apipodProvider.models.map((model) => model.id).toSet(),
      (coverage['active_video_routes'] as List)
          .map((route) => (route as Map)['id'])
          .toSet(),
    );
    for (final family in [
      'seedance-1.0',
      'seedance-2.0',
      'seedance-2.5',
      'veo3-1',
      'kling-3.0',
      'kling-4.0',
      'wan2.7',
      'wan3.0',
      'grok-imagine',
      'minimax-h3',
      'gemini-omni',
      'muse-video',
      'motion-control',
    ]) {
      expect(
        apipodProvider.models.any((model) => model.id.startsWith(family)),
        true,
        reason: family,
      );
    }
    for (final model in apipodProvider.models) {
      for (final mode in model.modes) {
        for (final resolution in model.resolutions) {
          if (!(model.resolutionsByMode[mode] ??
                  model.resolutions.map((r) => r.id).toList())
              .contains(resolution.id)) {
            continue;
          }
          for (final ratio in model.aspectRatios) {
            for (final duration
                in model.durationOptions.isEmpty
                    ? [model.minDuration, model.maxDuration]
                    : model.durationOptions) {
              final input = <String, Object?>{
                'prompt': 'A fox walking through a quiet forest.',
                'mode': mode.wireValue,
                'resolution': resolution.id,
                'duration': duration,
                'aspect_ratio': ratio,
                'generate_audio': model.supportsAudio,
                if (mode == VideoMode.draftEnhance)
                  'draft_cache': 'draft-task-123',
                if (mode == VideoMode.v2v)
                  'start_video': 'https://example.com/source.mp4',
                if ((mode == VideoMode.i2v || mode == VideoMode.v2v) &&
                    model.supportsStartFrame)
                  'keyframes': ['https://example.com/start.png'],
                if (mode == VideoMode.i2v &&
                    !model.supportsStartFrame &&
                    model.maxImageReferences > 0)
                  'reference_images': ['https://example.com/reference.png'],
              };
              final reason =
                  '${model.id}/${mode.wireValue}/${resolution.id}/$ratio/$duration';
              final payload = apipodGenerationPayload(
                model.id,
                mode == VideoMode.draftEnhance
                    ? <String, Object?>{
                        'mode': mode.wireValue,
                        'resolution': resolution.id,
                        'draft_cache': 'draft-task-123',
                      }
                    : input,
              );
              expect(payload['model'], model.id, reason: reason);
              if (mode == VideoMode.draftEnhance) {
                expect(payload.keys.toSet(), {
                  'model',
                  'draft_task_id',
                  'resolution',
                }, reason: reason);
              }
            }
          }
        }
      }
    }
  });

  test('APIPod rates include input video and never count images as video', () {
    for (final resolution in ['sd', 'hd']) {
      final rate = resolution == 'sd' ? .098 : .2205;
      final videoRate = resolution == 'sd' ? .0588 : .1323;
      CostEstimate estimate(List<MediaReferenceLabel> references) =>
          estimateCost(
            'apipod',
            'seedance-2.5-r2v',
            VideoMode.i2v,
            _config(resolution, references),
          );
      expect(estimate([]).minimumUsd, closeTo(rate * 10, .00001));
      expect(
        estimate(const [
          MediaReferenceLabel(
            label: 'portrait',
            kind: MediaReferenceKind.image,
          ),
        ]).minimumUsd,
        closeTo(rate * 10, .00001),
      );
      final withVideo = estimate(const [
        MediaReferenceLabel(
          label: 'clip 1',
          kind: MediaReferenceKind.video,
          durationSeconds: 4,
        ),
        MediaReferenceLabel(
          label: 'clip 2',
          kind: MediaReferenceKind.video,
          durationSeconds: 6,
        ),
      ]);
      expect(withVideo.minimumUsd, closeTo(videoRate * 20, .00001));
      expect(withVideo.maximumUsd, withVideo.minimumUsd);
      final pending = estimate(const [
        MediaReferenceLabel(
          label: 'unmeasured',
          kind: MediaReferenceKind.video,
        ),
      ]);
      expect(pending.isAvailable, false);
      expect(pending.quotedMinimumUsd, isNull);
    }
    expect(
      publishedProviderPrices(
        'apipod',
      ).map((p) => p.model.split(':').first).toSet(),
      apipodProvider.models.map((m) => m.id).toSet(),
    );
  });

  test('route-specific quotes match independent APIPod pricing examples', () {
    CostEstimate quote(
      String id,
      int duration,
      String resolution, {
      bool audio = true,
    }) => estimateCost(
      'apipod',
      id,
      VideoMode.t2v,
      GenerationConfig(
        aspectRatio: '16:9',
        duration: duration,
        resolution: resolution,
        generateAudio: audio,
        safetyTolerance: 2,
        draft: false,
      ),
    );
    expect(quote('veo3-1-lite', 8, 'hd').minimumUsd, .08);
    expect(quote('veo3-1-lite', 8, 'fhd').minimumUsd, .12);
    expect(quote('muse-video-t2v', 10, 'hd').minimumUsd, .20);
    expect(quote('muse-video-t2v', 20, 'hd').minimumUsd, .30);
    expect(quote('muse-video-t2v', 30, 'hd').minimumUsd, .30);
    expect(quote('seedance-2.0-mini-t2v', 4, 'sd').minimumUsd, .10);
    expect(quote('minimax-h3-lite-t2v', 5, 'qhd').minimumUsd, .31);
    expect(quote('wan3.0-t2v', 2, 'sd').minimumUsd, .09);
    expect(quote('kling-3.0-t2v', 5, 'hd', audio: false).minimumUsd, .40);
    expect(quote('kling-3.0-t2v', 5, 'hd').minimumUsd, .60);
    final tierRange = quote('kling-4.0-r2v', 3, 'hd');
    expect(tierRange.minimumUsd, .255);
    expect(tierRange.maximumUsd, .4284);
    for (final price in publishedProviderPrices('apipod')) {
      expect(
        price.durationPrices.values,
        everyElement(greaterThan(0)),
        reason: price.model,
      );
    }
  });

  test('APIPod manifests require the release with its adapter', () async {
    final catalog = ProviderCatalogClient(
      client: MockClient((request) async {
        final path = request.url.path == '/models/'
            ? 'index.html'
            : request.url.path.replaceFirst('/models/', '');
        final body = File('../docs/models/$path').readAsStringSync();
        return http.Response(
          path == 'index.html'
              ? jsonEncode({
                  ...jsonDecode(body) as Map<String, dynamic>,
                  'catalog_version': '0.64.0',
                })
              : body,
          200,
          headers: {'content-type': 'application/json; charset=utf-8'},
        );
      }),
    );
    final old = await catalog.fetch(appVersion: '0.62.0');
    expect(old.providers.map((p) => p.id), isNot(contains('apipod')));
    final previous = await catalog.fetch(appVersion: '0.63.0');
    expect(
      previous.providers.singleWhere((p) => p.id == 'apipod').models,
      hasLength(3),
    );
    final next = await catalog.fetch(appVersion: '0.64.0');
    final provider = next.providers.singleWhere((p) => p.id == 'apipod');
    expect(provider.progressReporting, ProviderProgressReporting.reported);
    expect(provider.models, hasLength(103));
    expect(
      provider.models.map((model) => model.id).toSet(),
      apipodProvider.models.map((model) => model.id).toSet(),
    );
    catalog.close();
  });
}

GenerationConfig _config(
  String resolution,
  List<MediaReferenceLabel> references,
) => GenerationConfig(
  aspectRatio: '16:9',
  duration: 10,
  resolution: resolution,
  generateAudio: true,
  safetyTolerance: 2,
  draft: false,
  references: references,
);
