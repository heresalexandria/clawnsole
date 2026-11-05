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
  test('all exposed APIPod settings map to documented standard routes', () {
    for (final model in apipodProvider.models) {
      for (final resolution in model.resolutions) {
        for (final ratio in model.aspectRatios) {
          for (final duration in [model.minDuration, model.maxDuration]) {
            final payload = apipodGenerationPayload(model.id, {
              'prompt': 'A fox in the forest.',
              'mode': model.modes.single.wireValue,
              'resolution': resolution.id,
              'duration': duration,
              'aspect_ratio': ratio,
              'generate_audio': false,
              if (model.supportsStartFrame)
                'keyframes': ['https://example.com/start.png'],
              if (model.maxImageReferences > 0)
                'reference_images': ['https://example.com/reference.png'],
            });
            expect(payload['model'], model.id);
            expect(payload['resolution'], isIn(['480p', '720p']));
            expect(payload['duration'], duration);
            expect(payload['generate_audio'], false);
            expect(
              payload.containsKey('aspect_ratio'),
              !model.supportsStartFrame,
            );
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
    expect(publishedProviderPrices('apipod'), hasLength(8));
  });

  test('APIPod manifests require the release with its adapter', () async {
    final catalog = ProviderCatalogClient(
      client: MockClient((request) async {
        final path = request.url.path == '/models/'
            ? 'index.html'
            : request.url.path.replaceFirst('/models/', '');
        return http.Response.bytes(
          File('../docs/models/$path').readAsBytesSync(),
          200,
        );
      }),
    );
    final old = await catalog.fetch(appVersion: '0.62.0');
    expect(old.providers.map((p) => p.id), isNot(contains('apipod')));
    final next = await catalog.fetch(appVersion: '0.63.0');
    final provider = next.providers.singleWhere((p) => p.id == 'apipod');
    expect(provider.progressReporting, ProviderProgressReporting.reported);
    expect(provider.models, hasLength(3));
    for (final model in provider.models) {
      expect(model.requiresPublicMediaUrls, model.id != 'seedance-2.5-t2v');
      expect(model.maxPromptCharacters, 30000);
    }
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
