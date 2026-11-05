import 'package:clawnsole/core/apipod_model_contracts.dart';
import 'package:clawnsole/core/bfl_api.dart';
import 'package:flutter_test/flutter_test.dart';

const _first = 'https://media.example.com/first.png';
const _last = 'https://media.example.com/last.png';
const _middle = 'https://media.example.com/middle.png';
const _source = 'https://media.example.com/source.mp4';
const _reference = 'https://media.example.com/reference.mp4';
const _audio = 'https://media.example.com/audio.mp3';

Map<String, Object?> _input({
  String mode = 't2v',
  String resolution = 'hd',
  String ratio = '16:9',
  Object duration = 5,
}) => {
  'mode': mode,
  'prompt': 'A fox walks through a sunlit meadow.',
  'resolution': resolution,
  'aspect_ratio': ratio,
  'duration': duration,
  'generate_audio': false,
};

void main() {
  test(
    'Seedance edits preserve source-first order and reference numbering',
    () {
      final payload = apipodGenerationPayload('seedance-2.5-edit', {
        ..._input(mode: 'v2v', ratio: 'auto'),
        'prompt':
            'Restyle the source using @Video 1 and @Palette with @Audio 1.',
        'start_video': _source,
        'reference_videos': [_reference],
        'reference_images': [_first],
        'reference_audios': [_audio],
        '_clawnsole_reference_names': {
          'image': ['Palette'],
        },
      });
      expect(payload, {
        'model': 'seedance-2.5-edit',
        'prompt': 'Restyle the source using @video2 and @image1 with @audio1.',
        'resolution': '720p',
        'generate_audio': false,
        'image_urls': [_first],
        'video_urls': [_source, _reference],
        'audio_urls': [_audio],
      });
    },
  );

  test(
    'Seedance extension sends requested duration and accepts source alias',
    () {
      final payload = apipodGenerationPayload('seedance-2.5-spicy-extend', {
        ..._input(mode: 'v2v', resolution: 'fhd', ratio: 'auto', duration: 30),
        'input_video': _source,
      });
      expect(payload['video_urls'], [_source]);
      expect(payload['duration'], 30);
      expect(payload['resolution'], '1080p');
      expect(payload.containsKey('aspect_ratio'), isFalse);
      expect(
        () => apipodGenerationPayload('seedance-2.5-extend', {
          ..._input(mode: 'v2v', ratio: 'auto'),
          'start_video': _source,
          'input_video': _reference,
        }),
        throwsA(isA<ProviderException>()),
      );
    },
  );

  test('draft preview and final are distinct stages on the same model', () {
    final preview = apipodGenerationPayload('seedance-2.5-draft', {
      ..._input(mode: 'i2v', resolution: 'sd'),
      'reference_images': [_first],
      'reference_videos': [_reference],
    });
    expect(preview['resolution'], '480p');
    expect(preview['image_urls'], [_first]);
    expect(preview.containsKey('draft_task_id'), isFalse);
    expect(
      apipodGenerationPayload('seedance-2.5-draft', {
        'mode': 'draft_enhance',
        'draft_task_id': 'completed-draft-task',
        'resolution': 'fhd',
      }),
      {
        'model': 'seedance-2.5-draft',
        'draft_task_id': 'completed-draft-task',
        'resolution': '1080p',
      },
    );
    for (final extra in <Map<String, Object?>>[
      {'resolution': 'sd'},
      {'draft_task_id': 'https://media.example.com/draft.mp4'},
      {'prompt': 'A different scene'},
      {'duration': 5},
      {'generate_audio': false},
      {
        'reference_images': [_first],
      },
    ]) {
      expect(
        () => apipodGenerationPayload('seedance-2.5-draft', {
          'mode': 'draft_enhance',
          'draft_task_id': 'completed-draft-task',
          'resolution': 'fhd',
          ...extra,
        }),
        throwsA(isA<ProviderException>()),
      );
    }
  });

  test('MiniMax H3 uses explicit first and last fields and preserves 768P', () {
    expect(
      apipodGenerationPayload('minimax-h3-i2v', {
        ..._input(mode: 'i2v', resolution: '768p', ratio: 'auto', duration: 4),
        'keyframes': [_first, _last],
      }),
      {
        'model': 'minimax-h3-i2v',
        'prompt': 'A fox walks through a sunlit meadow.',
        'resolution': '768P',
        'duration': 4,
        'first_frame_image': _first,
        'last_frame_image': _last,
      },
    );
  });

  test('live-verified MiniMax Lite text route requires 2K', () {
    final payload = apipodGenerationPayload('minimax-h3-lite-t2v', {
      'prompt': 'A fox walks through a meadow.',
    });
    expect(payload['resolution'], '2K');
    expect(
      () => apipodGenerationPayload(
        'minimax-h3-lite-t2v',
        _input(resolution: '768p'),
      ),
      throwsA(isA<ProviderException>()),
    );
  });

  test(
    'Kling 4 splits middle frames and enforces duration-dependent maximum',
    () {
      final input = {
        ..._input(mode: 'i2v', ratio: 'auto', duration: 3),
        'keyframes': [
          [0, _first],
          [1, _middle],
          [3, _last],
        ],
      };
      final payload = apipodGenerationPayload('kling-4.0-i2v', input);
      expect(payload['image_urls'], [_first, _last]);
      expect(payload['keyframe_urls'], [_middle]);
      expect(payload.containsKey('aspect_ratio'), isFalse);
      expect(
        () => apipodGenerationPayload('kling-4.0-i2v', {
          ...input,
          'keyframes': [_first, _middle, _middle, _middle, _last],
        }),
        throwsA(isA<ProviderException>()),
      );
    },
  );

  test('ordered middle roles never become an accidental last frame', () {
    final input = {
      ..._input(mode: 'i2v', ratio: 'auto', duration: 3),
      'keyframes': [_first, _middle],
      '_clawnsole_keyframe_roles': ['start', 'middle'],
    };
    final payload = apipodGenerationPayload('kling-4.0-i2v', input);
    expect(payload['image_urls'], [_first]);
    expect(payload['keyframe_urls'], [_middle]);
    expect(payload.containsKey('_clawnsole_keyframe_roles'), isFalse);
    final complete = apipodGenerationPayload('kling-4.0-i2v', {
      ...input,
      'keyframes': [_first, _middle, _last],
      '_clawnsole_keyframe_roles': ['start', 'middle', 'end'],
    });
    expect(complete['image_urls'], [_first, _last]);
    expect(complete['keyframe_urls'], [_middle]);
    // Ten total frames fit the catalog and a 30s clip, but nine middle
    // frames exceed the API's independent eight-middle-frame ceiling.
    expect(
      () => apipodGenerationPayload('kling-4.0-i2v', {
        ...input,
        'duration': 30,
        'keyframes': [_first, ...List.filled(9, _middle)],
        '_clawnsole_keyframe_roles': ['start', ...List.filled(9, 'middle')],
      }),
      throwsA(isA<ProviderException>()),
    );
    for (final roles in [
      ['start'],
      ['middle', 'end'],
      ['start', 'start'],
      ['start', 'unknown'],
    ]) {
      expect(
        () => apipodGenerationPayload('kling-4.0-i2v', {
          ...input,
          '_clawnsole_keyframe_roles': roles,
        }),
        throwsA(isA<ProviderException>()),
      );
    }
  });

  test('Kling 4 reference placeholders use documented underscore syntax', () {
    final payload = apipodGenerationPayload('kling-4.0-r2v', {
      ..._input(mode: 'i2v'),
      'prompt': '@Image 1 follows @Video 1.',
      'reference_images': [_first],
      'reference_videos': [_reference],
    });
    expect(payload['prompt'], '@image_1 follows @video_1.');
  });

  test(
    'motion control uses singular URLs and quality without fabricated controls',
    () {
      final input = {
        ..._input(mode: 'v2v', resolution: 'fhd', ratio: 'auto'),
        'start_video': _source,
        'keyframes': [_first],
      };
      expect(apipodGenerationPayload('kling-2.6-motion-control', input), {
        'model': 'kling-2.6-motion-control',
        'prompt': 'A fox walks through a sunlit meadow.',
        'quality': 'pro',
        'image_url': _first,
        'video_url': _source,
      });
      expect(
        apipodGenerationPayload('motion-control-m1', {
          ...input,
          'resolution': 'hd',
          'prompt': '',
        }),
        {
          'model': 'motion-control-m1',
          'image_url': _first,
          'video_url': _source,
        },
      );
      expect(
        () => apipodGenerationPayload('kling-2.6-motion-control', {
          ...input,
          'keyframes': <String>[],
        }),
        throwsA(isA<ProviderException>()),
      );
    },
  );

  test(
    'Wan 2.7 maps frame guidance and singular audio without inventing audio toggle',
    () {
      final payload = apipodGenerationPayload('wan2.7-i2v', {
        ..._input(mode: 'i2v', ratio: 'auto', duration: 2),
        'keyframes': [_first, _last],
        'reference_audios': [_audio],
      });
      expect(payload['resolution'], '720P');
      expect(payload['image_urls'], [_first, _last]);
      expect(payload['audio_url'], _audio);
      expect(payload.containsKey('generate_audio'), isFalse);
    },
  );

  test(
    'source-derived routes omit duration while retaining their other controls',
    () {
      final wan = apipodGenerationPayload('wan2.7-videoedit', {
        ..._input(mode: 'v2v', ratio: 'auto'),
        'start_video': _source,
        'reference_images': [_first],
      });
      expect(wan['video_url'], _source);
      expect(wan['image_urls'], [_first]);
      expect(wan.containsKey('duration'), isFalse);
      final gemini = apipodGenerationPayload('gemini-omni-extend', {
        ..._input(mode: 'v2v'),
        'start_video': _source,
        'reference_images': [_first],
      });
      expect(gemini['video_url'], _source);
      expect(gemini['aspect_ratio'], '16:9');
      expect(gemini.containsKey('duration'), isFalse);
    },
  );

  test('Wan 3 supports automatic duration plus its positive slider range', () {
    for (final duration in <Object>['auto', 2, 30]) {
      final payload = apipodGenerationPayload('wan3.0-t2v', {
        ..._input(resolution: 'sd', duration: duration),
      });
      expect(payload['duration'], duration == 'auto' ? -1 : duration);
      expect(payload['resolution'], '480P');
    }
    for (final duration in [0, 1, 31, -1]) {
      expect(
        () => apipodGenerationPayload('wan3.0-t2v', _input(duration: duration)),
        throwsA(isA<ProviderException>()),
      );
    }
  });

  test('discrete durations do not allow slider gaps', () {
    final input = {
      ..._input(mode: 'i2v', resolution: 'sd', duration: 6),
      'reference_images': [_first],
    };
    expect(apipodGenerationPayload('grok-imagine-i2v', input)['duration'], 6);
    expect(
      () => apipodGenerationPayload('grok-imagine-i2v', {
        ...input,
        'duration': 7,
      }),
      throwsA(isA<ProviderException>()),
    );
  });

  test(
    'Veo fixed routes omit duration and 4K route does not invent resolution',
    () {
      expect(
        apipodGenerationPayload('veo3-1-fast-4k', _input(resolution: '4k')),
        {
          'model': 'veo3-1-fast-4k',
          'prompt': 'A fox walks through a sunlit meadow.',
          'aspect_ratio': '16:9',
        },
      );
    },
  );

  test('every media entry must remain a public HTTPS URL', () {
    for (final source in [
      'file:///tmp/source.mp4',
      'http://media.example.com/source.mp4',
      'data:video/mp4;base64,AAAA',
      'https://media.example.com/source.mp4#fragment',
      'https://user:password@media.example.com/source.mp4',
    ]) {
      expect(
        () => apipodGenerationPayload('seedance-2.5-edit', {
          ..._input(mode: 'v2v', ratio: 'auto'),
          'start_video': source,
        }),
        throwsA(isA<ProviderException>()),
      );
    }
  });
}
