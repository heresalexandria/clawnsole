import 'dart:convert';
import 'dart:io';

import 'package:clawnsole/core/models.dart';
import 'package:clawnsole/core/provider_catalog.dart';
import 'package:clawnsole/core/provider_manifest.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Krea Seedance 2.5 has the same fallback offline and in Pages', () {
    final bundled = bundledVideoProviders
        .singleWhere((provider) => provider.id == 'krea')
        .models
        .singleWhere((model) => model.id == 'bytedance/seedance-2-5');
    final page =
        jsonDecode(
              File(
                '../docs/models/models/krea/seedance-2-5.yaml',
              ).readAsStringSync(),
            )
            as Map<String, dynamic>;
    expect(bundled.maxReferenceVideoSeconds, 30);
    expect(page['max_reference_video_seconds'], 30);
    expect(bundled.maxReferenceAudioSeconds, isNull);
  });

  test('omitted duration budgets recover the exact bundled route limits', () {
    for (final route in <(String, String, int)>[
      ('krea', 'bytedance/seedance-2-5', 30),
      ('runway', 'seedance2_5', 30),
      ('runway', 'seedance2', 15),
      ('atlas', 'bytedance/seedance-2.5/reference-to-video', 30),
      ('artcraft', 'seedance_2p5', 30),
    ]) {
      final model = _parse(route.$1, route.$2);
      expect(model.maxReferenceVideoSeconds, route.$3, reason: '$route');
      // Input limits are independent of the manifest's output duration.
      expect(model.maxDuration, 2);
    }
    expect(_parse('runway', 'seedance2_5').maxReferenceAudioSeconds, 30);
    expect(
      _parse('krea', 'bytedance/seedance-2-5').maxReferenceAudioSeconds,
      isNull,
    );
  });

  test('incoming global and resolution-specific budgets take precedence', () {
    final model = _parse(
      'runway',
      'seedance2_5',
      fields: <String, Object?>{
        'max_reference_video_seconds': 24,
        'max_reference_audio_seconds': 18,
        'max_reference_video_seconds_by_resolution': <String, int>{'sd': 12},
        'max_reference_audio_seconds_by_resolution': <String, int>{'sd': 9},
      },
    );
    expect(model.maxReferenceSeconds(MediaReferenceKind.video, 'hd'), 24);
    expect(model.maxReferenceSeconds(MediaReferenceKind.video, 'sd'), 12);
    expect(model.maxReferenceSeconds(MediaReferenceKind.audio, 'hd'), 18);
    expect(model.maxReferenceSeconds(MediaReferenceKind.audio, 'sd'), 9);

    final partial = _parse(
      'krea',
      'bytedance/seedance-2-5',
      fields: <String, Object?>{
        'max_reference_video_seconds_by_resolution': <String, int>{'sd': 20},
      },
    );
    expect(partial.maxReferenceSeconds(MediaReferenceKind.video, 'sd'), 20);
    expect(partial.maxReferenceSeconds(MediaReferenceKind.video, 'hd'), 30);
  });

  test('omitted resolution budgets survive and explicit maps replace them', () {
    final missing = _parse('ltx', 'ltx-2-3-pro');
    expect(missing.maxReferenceSeconds(MediaReferenceKind.audio, 'hd'), 20);
    expect(missing.maxReferenceSeconds(MediaReferenceKind.audio, 'qhd'), 10);
    expect(missing.maxReferenceSeconds(MediaReferenceKind.audio, '4k'), 10);

    final replaced = _parse(
      'ltx',
      'ltx-2-3-pro',
      fields: <String, Object?>{
        'max_reference_audio_seconds_by_resolution': <String, int>{'qhd': 8},
      },
    );
    expect(replaced.maxReferenceSeconds(MediaReferenceKind.audio, 'qhd'), 8);
    expect(replaced.maxReferenceSeconds(MediaReferenceKind.audio, '4k'), 20);

    final removed = _parse(
      'ltx',
      'ltx-2-3-pro',
      fields: <String, Object?>{
        'max_reference_audio_seconds_by_resolution': <String, int>{},
      },
    );
    expect(removed.maxReferenceSeconds(MediaReferenceKind.audio, '4k'), 20);
    expect(removed.maxReferenceAudioSecondsByResolution, isEmpty);

    final disabled = _parse(
      'ltx',
      'ltx-2-3-pro',
      fields: <String, Object?>{'max_audio_references': 0},
    );
    expect(disabled.maxReferenceAudioSecondsByResolution, isEmpty);
  });

  test(
    'fallback never crosses provider, alias, family, or disabled inputs',
    () {
      for (final route in <(String, String)>[
        ('krea', 'bytedance/seedance-2-5-new'),
        ('krea', 'bytedance/seedance-2'),
        ('krea', 'alibaba/wan-3.0'),
        ('custom-krea', 'bytedance/seedance-2-5'),
      ]) {
        final model = _parse(route.$1, route.$2, adapter: 'krea');
        expect(model.maxReferenceVideoSeconds, isNull, reason: '$route');
        expect(model.maxReferenceAudioSeconds, isNull, reason: '$route');
      }
      final disabled = _parse(
        'runway',
        'seedance2_5',
        fields: <String, Object?>{
          'max_video_references': 0,
          'max_audio_references': 0,
        },
      );
      expect(disabled.maxReferenceVideoSeconds, isNull);
      expect(disabled.maxReferenceAudioSeconds, isNull);
    },
  );
}

VideoModelDefinition _parse(
  String provider,
  String model, {
  String? adapter,
  Map<String, Object?> fields = const <String, Object?>{},
}) => ProviderCatalogBundle.fromCache(<String, Object?>{
  'schema_version': 1,
  'providers': <Map<String, Object?>>[
    <String, Object?>{
      'schema_version': 1,
      'id': provider,
      'adapter': adapter ?? provider,
      'name': 'Synthetic provider',
      'description': 'Synthetic provider.',
      'console_url': 'https://example.com/console',
      'docs_url': 'https://example.com/docs',
      'pricing_url': 'https://example.com/pricing',
      'models': <Map<String, Object?>>[
        <String, Object?>{
          'schema_version': 1,
          'id': model,
          'canonical_model_id': 'seedance-2.5',
          'label': 'Seedance 2.5',
          'description': 'Synthetic model.',
          'modes': <String>['t2v'],
          'aspect_ratios': <String>['16:9'],
          'resolutions': <Map<String, String>>[
            <String, String>{'id': 'hd', 'label': 'HD', 'detail': '720p'},
          ],
          'min_duration': 1,
          'max_duration': 2,
          'duration_step': 1,
          'max_keyframes': 0,
          'max_video_references': 1,
          'max_audio_references': 1,
          'usd_per_second': .1,
          ...fields,
        },
      ],
    },
  ],
}, mobileTestBuild: false).providers.single.models.single;
