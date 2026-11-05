import 'package:clawnsole/core/apipod_model_contracts.dart';
import 'package:clawnsole/core/apipod_model_groups.dart';
import 'package:clawnsole/core/apipod_models.dart';
import 'package:clawnsole/core/apipod_schema_data.dart';
import 'package:clawnsole/core/bfl_api.dart';
import 'package:clawnsole/core/models.dart';
import 'package:flutter_test/flutter_test.dart';

const _image = 'https://media.example.com/image.png';
const _video = 'https://media.example.com/video.mp4';
const _audio = 'https://media.example.com/audio.mp3';

void main() {
  test(
    '49 explicit logical choices retain all 103 audited wire identities',
    () {
      expect(apipodModels, hasLength(103));
      expect(
        apipodModels.map((model) => model.id).toSet(),
        apipodRouteSchemas.keys.toSet(),
      );
      expect(
        apipodModels.map((model) => model.selectionId).toSet(),
        hasLength(49),
      );
      for (final model in apipodModels) {
        expect(model.selectionGroupId, isNotNull);
        expect(model.selectionLabel, isNot(contains(' · Text')));
        expect(model.selectionLabel, isNot(contains(' · Frames')));
        expect(model.selectionLabel, isNot(contains(' · References')));
        expect(
          model.constrainedForMobileTest(model.resolutions.first).selectionId,
          model.selectionId,
        );
      }
    },
  );

  test(
    'Seedance automatically chooses text, pinned frame, and reference routes',
    () {
      expect(resolveApipodRoute('seedance-2.5'), 'seedance-2.5-t2v');
      expect(
        resolveApipodRoute('seedance-2.5', keyframeCount: 1),
        'seedance-2.5-i2v',
      );
      expect(
        resolveApipodRoute('seedance-2.5', imageReferenceCount: 1),
        'seedance-2.5-r2v',
      );
      expect(
        resolveApipodRoute('seedance-2.5', videoReferenceCount: 1),
        'seedance-2.5-r2v',
      );
      expect(
        resolveApipodRoute(
          'seedance-2.5-t2v',
          imageReferenceCount: 1,
          audioReferenceCount: 1,
        ),
        'seedance-2.5-r2v',
      );
      expect(resolveApipodRoute('seedance-2.5-r2v'), 'seedance-2.5-t2v');
      expect(
        () => resolveApipodRoute(
          'seedance-2.5',
          keyframeCount: 1,
          imageReferenceCount: 1,
        ),
        throwsA(isA<ProviderException>()),
      );
    },
  );

  test(
    'logical payload aliases dispatch without changing explicit saved wire contracts',
    () {
      const base = {
        'prompt': 'A fox walks.',
        'resolution': 'hd',
        'duration': 5,
        'aspect_ratio': 'auto',
      };
      for (final (guidance, expected) in <(Map<String, Object?>, String)>[
        ({}, 'seedance-2.5-t2v'),
        (
          {
            'keyframes': [_image],
          },
          'seedance-2.5-i2v',
        ),
        (
          {
            'reference_images': [_image],
          },
          'seedance-2.5-r2v',
        ),
        (
          {
            'reference_videos': [_video],
            'reference_audios': [_audio],
          },
          'seedance-2.5-r2v',
        ),
      ]) {
        expect(
          apipodGenerationPayload('seedance-2.5', {
            ...base,
            ...guidance,
          })['model'],
          expected,
        );
      }
      expect(
        () => apipodGenerationPayload('seedance-2.5-t2v', {
          ...base,
          'keyframes': [_image],
        }),
        throwsA(isA<ProviderException>()),
      );
    },
  );

  test('variants and dedicated workflows never silently change tier', () {
    expect(
      resolveApipodRoute('seedance-1.0-lite', imageReferenceCount: 1),
      'seedance-1.0-lite-i2v-ref',
    );
    expect(
      resolveApipodRoute('seedance-1.0-pro-fast', keyframeCount: 1),
      'seedance-1.0-pro-fast-i2v',
    );
    expect(
      resolveApipodRoute('seedance-2.5-draft', mode: VideoMode.draftEnhance),
      'seedance-2.5-draft',
    );
    expect(
      resolveApipodRoute('seedance-2.5-extend', hasSourceVideo: true),
      'seedance-2.5-extend',
    );
    expect(
      resolveApipodRoute('seedance-2.5-edit', hasSourceVideo: true),
      'seedance-2.5-edit',
    );
    for (final model in ['seedance-1.0-pro-fast', 'seedance-2.5-t2v']) {
      expect(
        () => resolveApipodRoute(model, hasSourceVideo: true),
        throwsA(isA<ProviderException>()),
      );
    }
    expect(
      () => resolveApipodRoute('seedance-2.0-mini', imageReferenceCount: 30),
      throwsA(isA<ProviderException>()),
    );
  });

  test(
    'draft finalization ignores retained preview attachments when selecting its route',
    () {
      expect(
        resolveApipodRoute(
          'seedance-2.5-draft',
          mode: VideoMode.draftEnhance,
          resolution: 'fhd',
          hasSourceVideo: true,
          keyframeCount: 2,
          imageReferenceCount: 30,
          videoReferenceCount: 10,
          audioReferenceCount: 10,
        ),
        'seedance-2.5-draft',
      );
    },
  );

  test(
    'Veo Fast references share a choice while 4K remains a separate tier',
    () {
      expect(
        resolveApipodRoute('veo3-1-fast', imageReferenceCount: 1),
        'veo3-1-fast-ref',
      );
      expect(
        resolveApipodRoute('veo3-1-fast-ref', keyframeCount: 1),
        'veo3-1-fast',
      );
      expect(
        resolveApipodRoute('veo3-1-fast-4k', keyframeCount: 1),
        'veo3-1-fast-4k',
      );
      expect(
        () => resolveApipodRoute('veo3-1-fast', resolution: '4k'),
        throwsA(isA<ProviderException>()),
      );
    },
  );

  test(
    'audio-only Wan guidance selects its text route, not a frame-required route',
    () {
      expect(
        resolveApipodRoute('wan2.7', audioReferenceCount: 1),
        'wan2.7-t2v',
      );
      expect(
        resolveApipodRouteForInput('wan2.7-i2v', {
          'reference_audios': [_audio],
        }),
        'wan2.7-t2v',
      );
      final payload = apipodGenerationPayload('wan2.7', {
        'prompt': 'A fox walks to the music.',
        'resolution': 'hd',
        'aspect_ratio': '16:9',
        'duration': 5,
        'reference_audios': [_audio],
      });
      expect(payload['model'], 'wan2.7-t2v');
      expect(payload['audio_url'], _audio);
      expect(payload.containsKey('image_urls'), isFalse);
    },
  );
}
