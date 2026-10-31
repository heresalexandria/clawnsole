import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:clawnsole/core/bfl_api.dart';
import 'package:clawnsole/core/fal_catalog.dart';
import 'package:clawnsole/core/fal_model_contracts.dart';
import 'package:clawnsole/core/models.dart';
import 'package:clawnsole/core/pricing.dart';

void main() {
  final fixture =
      jsonDecode(
            File(
              'test/fixtures/fal_october_2026_schemas.json',
            ).readAsStringSync(),
          )
          as Map<String, dynamic>;
  final schemas = fixture['routes'] as Map<String, dynamic>;

  test(
    'every advertised fal combination satisfies its official input schema',
    () {
      expect(
        falProvider.models.map((model) => model.id).toSet(),
        schemas.keys.toSet(),
      );
      expect(falRouteSpecs, hasLength(16));
      for (final spec in falRouteSpecs.values) {
        final schema = schemas[spec.id]['input'] as Map<String, dynamic>;
        for (final resolution in spec.resolutions) {
          final durations = <Object>[
            for (
              var seconds = spec.minDuration;
              seconds <= spec.maxDurationFor(resolution.id);
              seconds += spec.durationStep
            )
              seconds,
            if (spec.supportsAutoDuration) 'auto',
          ];
          for (final duration in durations) {
            for (final ratio in spec.aspectRatios) {
              final payload = spec.buildPayload(<String, Object?>{
                'mode': spec.modes.single.wireValue,
                'prompt': 'A bird flies over a forest.',
                'duration': duration,
                'resolution': resolution.id,
                'aspect_ratio': ratio,
                'generate_audio': false,
                if (spec.supportsSeed) 'seed': 42,
                'keyframes': <Object>[
                  for (var frame = 0; frame < spec.maxKeyframes; frame++)
                    <Object>[frame, 'https://example.com/frame$frame.png'],
                ],
              });
              expect(
                _valid(schema, payload),
                isTrue,
                reason: '${spec.id}: $payload',
              );
            }
          }
        }
      }
    },
  );

  test('fal frame mappings preserve ordered endpoints and middle frames', () {
    final payload = falRouteByModel('kling/v4/image-to-video')!.buildPayload({
      'prompt': '',
      'duration': 10,
      'aspect_ratio': 'auto',
      'keyframes': <Object>[
        [0, 'first'],
        [3, 'middle1'],
        [6, 'middle2'],
        [10, 'last'],
      ],
    });
    expect(payload['start_image_url'], 'first');
    expect(payload['middle_image_urls'], ['middle1', 'middle2']);
    expect(payload['end_image_url'], 'last');
    expect(payload, isNot(contains('aspect_ratio')));
    expect(payload, isNot(contains('generate_audio')));
    final h3 = falRouteByModel('minimax/h3-max/image-to-video')!.buildPayload({
      'prompt': 'Move',
      'duration': 1,
      'resolution': 'hd',
      'keyframes': ['first', 'last'],
    });
    expect(h3['resolution'], '768P');
    expect(h3['prompt_expansion_mode'], 'balanced');
    expect(h3['image_url'], 'first');
    expect(h3['end_image_url'], 'last');
    expect(h3, isNot(contains('aspect_ratio')));
  });

  test('fal automatic duration follows each API contract', () {
    final wan = falRouteByModel('alibaba/wan-3.0/text-to-video')!.buildPayload({
      'prompt': 'Move',
      'duration': 'auto',
      'aspect_ratio': 'auto',
      'generate_audio': false,
    });
    expect(wan, containsPair('duration', null));
    expect(wan['aspect_ratio'], 'adaptive');
    expect(wan['audio'], false);
    final ltx = falRouteByModel(
      'lightricks/ltx-2.5/text-to-video/fast',
    )!.buildPayload({'prompt': 'Move', 'duration': 'auto', 'resolution': '4k'});
    expect(ltx['duration'], 'auto');
    expect(ltx['fps'], 25);
    expect(ltx['resolution'], '2160p');
  });

  test('fal rejects unsupported requests before a generation can be sent', () {
    final text = falRouteByModel('blackforestlabs/flux-3-max/text-to-video')!;
    final valid = <String, Object?>{'prompt': 'Move', 'duration': 5};
    for (final invalid in <Map<String, Object?>>[
      {'mode': 'i2v'},
      {'prompt': ''},
      {'duration': 'auto'},
      {'duration': 4},
      {'duration': 20.5},
      {'resolution': '4k'},
      {'aspect_ratio': '3:2'},
      {
        'keyframes': ['frame'],
      },
      {
        'reference_images': ['image'],
      },
      {
        'reference_videos': ['video'],
      },
      {
        'reference_audios': ['audio'],
      },
      {'start_video': 'video'},
      {'input_video': 'video'},
      {'seed': 2.5},
    ]) {
      expect(
        () => text.buildPayload({...valid, ...invalid}),
        throwsA(isA<ProviderException>()),
      );
    }
    final image = falRouteByModel('blackforestlabs/flux-3/image-to-video')!;
    expect(() => image.buildPayload(valid), throwsA(isA<ProviderException>()));
    expect(
      () => image.buildPayload({
        ...valid,
        'keyframes': ['a', 'b'],
      }),
      throwsA(isA<ProviderException>()),
    );
    final ltx = falRouteByModel('lightricks/ltx-2.5/text-to-video/fast')!;
    expect(
      () => ltx.buildPayload({
        'prompt': 'Move',
        'duration': 12,
        'resolution': 'qhd',
      }),
      throwsA(isA<ProviderException>()),
    );
    final wan = falRouteByModel('alibaba/wan-3.0/text-to-video')!;
    expect(
      () => wan.buildPayload({...valid, 'seed': 2147483648}),
      throwsA(isA<ProviderException>()),
    );
  });

  test('every supported tier has the independently audited list rate', () {
    const expected = <String, Map<String, double>>{
      'flux-3-max': {'hd': .17, 'fhd': .29},
      'flux-3': {'hd': .17, 'fhd': .29, 'qhd': .32, '4k': .47},
      'minimax-h3-max': {'sd': .05, 'hd': .08, 'fhd': .16},
      'minimax-h3-max-turbo': {'sd': .025, 'hd': .04, 'fhd': .08},
      'kling-4.0': {'hd': .157, 'fhd': .235},
      'wan-3.0': {'sd': .05, 'hd': .10, 'fhd': .20},
      'ltx-2.5-fast': {'hd': .09, 'fhd': .13, 'qhd': .19, '4k': .30},
      'ltx-2.5-pro': {'hd': .12, 'fhd': .17},
    };
    final prices = falPublishedPrices();
    expect(prices, hasLength(46));
    for (final price in prices) {
      final split = price.model.lastIndexOf(':');
      final spec = falRouteByModel(price.model.substring(0, split))!;
      final resolution = price.model.substring(split + 1);
      expect(price.usdPerSecond, expected[spec.canonicalId]![resolution]);
      expect(price.source, contains('list rates'));
      expect(price.maxDuration, spec.maxDurationFor(resolution));
      expect(
        price.priceFor(spec.minDuration),
        closeTo(
          expected[spec.canonicalId]![resolution]! * spec.minDuration,
          1e-10,
        ),
      );
      if (spec.modes.single == VideoMode.i2v) {
        expect(price.referenceUsdPerSecond, price.usdPerSecond);
      }
      // Exercise the shared estimator's neutral hd/fhd/qhd/4k suffix lookup,
      // including its fallback when only another tier was loaded previously.
      final config = GenerationConfig(
        aspectRatio: spec.aspectRatios.first,
        duration: spec.minDuration,
        resolution: resolution,
        generateAudio: true,
        safetyTolerance: 2,
        draft: false,
      );
      for (final availablePrices in <List<ProviderModelPrice>>[
        prices,
        prices.take(1).toList(),
        const <ProviderModelPrice>[],
      ]) {
        final estimate = estimateCost(
          'fal',
          spec.id,
          spec.modes.single,
          config,
          const <Generation>[],
          availablePrices,
        );
        expect(estimate.isAvailable, isTrue);
        expect(
          estimate.minimumUsd,
          closeTo(price.usdPerSecond * spec.minDuration, 1e-10),
          reason: price.model,
        );
        expect(estimate.maximumUsd, estimate.minimumUsd);
      }
    }
  });
}

// Validate the JSON Schema subset used by the captured input contracts. This
// checks the actual generated wire values rather than duplicating the mapper.
bool _valid(Map<String, dynamic> schema, Object? value) {
  if (schema['anyOf'] case final List<dynamic> alternatives) {
    return alternatives.any(
      (item) => _valid(item as Map<String, dynamic>, value),
    );
  }
  if (schema['enum'] case final List<dynamic> values) {
    if (!values.contains(value)) return false;
  }
  if (schema.containsKey('const') && value != schema['const']) return false;
  switch (schema['type']) {
    case 'null':
      return value == null;
    case 'boolean':
      return value is bool;
    case 'integer':
      if (value is! num || value != value.roundToDouble()) return false;
    case 'number':
      if (value is! num) return false;
    case 'string':
      if (value is! String) return false;
      if (schema['minLength'] case final num minimum) {
        if (value.length < minimum) return false;
      }
      if (schema['maxLength'] case final num maximum) {
        if (value.length > maximum) return false;
      }
    case 'array':
      if (value is! List) return false;
      if (schema['maxItems'] case final num maximum) {
        if (value.length > maximum) return false;
      }
      if (schema['items'] case final Map<String, dynamic> items) {
        if (!value.every((item) => _valid(items, item))) {
          return false;
        }
      }
    case 'object':
      if (value is! Map) return false;
      final properties = schema['properties'] as Map<String, dynamic>;
      for (final required in schema['required'] as List<dynamic>? ?? []) {
        if (!value.containsKey(required)) return false;
      }
      for (final entry in value.entries) {
        if (!properties.containsKey(entry.key) ||
            !_valid(
              properties[entry.key] as Map<String, dynamic>,
              entry.value,
            )) {
          return false;
        }
      }
  }
  if (value is num) {
    if (schema['minimum'] case final num minimum) {
      if (value < minimum) return false;
    }
    if (schema['maximum'] case final num maximum) {
      if (value > maximum) return false;
    }
  }
  return true;
}
