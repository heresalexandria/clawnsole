import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:clawnsole/core/artcraft_api.dart';
import 'package:clawnsole/core/direct_gateway.dart';
import 'package:clawnsole/core/durable_data_store.dart';
import 'package:clawnsole/core/models.dart';
import 'package:clawnsole/core/provider_api.dart';
import 'package:clawnsole/core/provider_catalog.dart';
import 'package:clawnsole/core/reference_video_normalizer.dart';
import 'package:clawnsole/core/reference_video_normalizer_mobile.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('every video-reference model declares a compatibility profile', () {
    for (final provider in videoProviders) {
      for (final model in provider.models) {
        final profile = model.referenceVideoCompatibilityProfile;
        final reason = '${provider.id}/${model.id}';
        if (model.maxVideoReferences == 0) {
          expect(profile, isNull, reason: reason);
          continue;
        }
        final isSeedance =
            model.canonicalId.startsWith('seedance-') ||
            model.id.startsWith('seedance_');
        expect(
          profile,
          isSeedance
              ? ReferenceVideoCompatibilityProfile.seedance
              : ReferenceVideoCompatibilityProfile.generic,
          reason: reason,
        );
      }
    }
  });

  test('canvas selection preserves the compatibility thresholds', () {
    expect(ReferenceVideoCanvas.forDisplaySize(749, 1000).width, 720);
    expect(ReferenceVideoCanvas.forDisplaySize(749, 1000).height, 1280);
    expect(ReferenceVideoCanvas.forDisplaySize(750, 1000).height, 720);
    expect(ReferenceVideoCanvas.forDisplaySize(640, 480).width, 1280);
    expect(ReferenceVideoCanvas.forDisplaySize(1334, 1000).width, 1280);
  });

  test('compatible reference images pass through without ffmpeg', () async {
    final cache = await Directory.systemTemp.createTemp(
      'clawnsole-image-normalizer-',
    );
    addTearDown(() => cache.delete(recursive: true));
    final backend = _ImageBackend();
    final jpeg = Uint8List.fromList(<int>[0xff, 0xd8, 0xff, 0xd9]);
    final source = 'data:image/jpeg;base64,${base64Encode(jpeg)}';
    final normalizer = ReferenceVideoNormalizer(
      backend: backend,
      cacheDirectory: () async => cache,
    );

    final result = await normalizer.normalizeImages(<String>[source]);

    expect(result.sources, <String>[source]);
    expect(result.changedIndexes, isEmpty);
    expect(backend.ffmpegArguments, isEmpty);
  });

  test('HEIF reference images are converted to JPEG and cached', () async {
    final cache = await Directory.systemTemp.createTemp(
      'clawnsole-image-normalizer-',
    );
    addTearDown(() => cache.delete(recursive: true));
    final backend = _ImageBackend();
    final heif = Uint8List.fromList(<int>[
      0,
      0,
      0,
      24,
      ...ascii.encode('ftyp'),
      ...ascii.encode('heic'),
      0,
      0,
      0,
      0,
      ...ascii.encode('mif1'),
    ]);
    final source = 'data:image/heif;base64,${base64Encode(heif)}';
    final untyped =
        'data:application/octet-stream;base64,${base64Encode(heif)}';
    final normalizer = ReferenceVideoNormalizer(
      backend: backend,
      cacheDirectory: () async => cache,
    );

    final first = await normalizer.normalizeImages(<String>[source, untyped]);
    final second = await normalizer.normalizeImages(<String>[source]);

    expect(first.changedIndexes, <int>{0, 1});
    expect(first.sources, everyElement(startsWith('data:image/jpeg;base64,')));
    expect(second.sources.single, first.sources.first);
    expect(backend.ffmpegArguments, hasLength(1));
    expect(backend.ffmpegArguments.single, isNot(contains('-map')));
    expect(backend.ffmpegArguments.single.last, contains('image-jpeg-v2'));
  });

  test(
    'image normalization updates frames and creative image references',
    () async {
      const retained = AssetReference(
        kind: 'local',
        value: 'original.heic',
        label: 'Original',
      );
      final config = GenerationConfig(
        aspectRatio: '16:9',
        duration: 5,
        resolution: 'hd',
        generateAudio: true,
        safetyTolerance: 2,
        draft: false,
        keyframes: const <KeyframeLabel>[
          KeyframeLabel(
            label: 'Opening',
            role: KeyframeRole.start,
            seconds: 0,
            source: retained,
          ),
        ],
        references: const <MediaReferenceLabel>[
          MediaReferenceLabel(
            label: 'Style',
            kind: MediaReferenceKind.image,
            source: retained,
            thumbnailAsset: retained,
          ),
        ],
      );
      final prepared = await prepareGenerationReferences(
        input: <String, Object?>{
          'keyframes': <Object?>[
            <Object?>[0, 'frame-original'],
          ],
          'reference_images': <String>['reference-original'],
        },
        config: config,
        videoNormalizer: const DisabledReferenceVideoNormalizationService(),
        imageNormalizer: _ChangedImageNormalizer(),
      );

      expect(prepared.input['keyframes'], <Object?>[
        <Object?>[0, 'image-fixed'],
      ]);
      expect(prepared.input['reference_images'], <String>['image-fixed']);
      expect(prepared.config.keyframes!.single.source, isNull);
      expect(prepared.config.references!.single.source, isNull);
      expect(prepared.config.references!.single.thumbnailAsset, isNull);
    },
  );

  test(
    'canonical references are returned byte-for-byte without ffmpeg',
    () async {
      final cache = await Directory.systemTemp.createTemp(
        'clawnsole-normalizer-',
      );
      addTearDown(() => cache.delete(recursive: true));
      final backend = _FakeBackend(<Map<String, Object?>>[_canonicalProbe()]);
      final bytes = _minimalFastStartMp4();
      final source = 'data:video/mp4;base64,${base64Encode(bytes)}';
      final normalizer = ReferenceVideoNormalizer(
        backend: backend,
        cacheDirectory: () async => cache,
      );

      final result = await normalizer.normalize(<String>[
        source,
      ], profile: ReferenceVideoCompatibilityProfile.seedance);

      expect(result.sources, <String>[source]);
      expect(result.changedIndexes, isEmpty);
      expect(backend.ffmpegArguments, isEmpty);
    },
  );

  test('iOS numeric codec profiles pass post-repair validation', () async {
    final cache = await Directory.systemTemp.createTemp(
      'clawnsole-normalizer-',
    );
    addTearDown(() => cache.delete(recursive: true));
    final backend = _FakeBackend(<Map<String, Object?>>[
      _canonicalProbe(
        videoOverrides: const <String, Object?>{'codec_name': 'hevc'},
        additionalStreams: <Map<String, Object?>>[
          _audioProbe(profile: 1, sampleRate: '44100', channels: 1),
        ],
      ),
      _canonicalProbe(
        videoOverrides: const <String, Object?>{'profile': 100},
        additionalStreams: <Map<String, Object?>>[_audioProbe(profile: 1)],
      ),
    ]);
    final source =
        'data:video/quicktime;base64,${base64Encode(_minimalFastStartMp4())}';
    final normalizer = ReferenceVideoNormalizer(
      backend: backend,
      cacheDirectory: () async => cache,
    );

    final result = await normalizer.normalize(<String>[
      source,
    ], profile: ReferenceVideoCompatibilityProfile.seedance);

    expect(result.changedIndexes, <int>{0});
    expect(backend.ffmpegArguments, hasLength(1));
  });

  test('iOS numeric codec profiles avoid unnecessary repair', () async {
    final cache = await Directory.systemTemp.createTemp(
      'clawnsole-normalizer-',
    );
    addTearDown(() => cache.delete(recursive: true));
    final backend = _FakeBackend(<Map<String, Object?>>[
      _canonicalProbe(
        videoOverrides: const <String, Object?>{'profile': 100},
        additionalStreams: <Map<String, Object?>>[_audioProbe(profile: 1)],
      ),
    ]);
    final source =
        'data:video/mp4;base64,${base64Encode(_minimalFastStartMp4())}';
    final normalizer = ReferenceVideoNormalizer(
      backend: backend,
      cacheDirectory: () async => cache,
    );

    final result = await normalizer.normalize(<String>[
      source,
    ], profile: ReferenceVideoCompatibilityProfile.seedance);

    expect(result.sources, <String>[source]);
    expect(result.changedIndexes, isEmpty);
    expect(backend.ffmpegArguments, isEmpty);
  });

  test('healthy generic 1080p 24fps references are byte-identical', () async {
    final cache = await Directory.systemTemp.createTemp(
      'clawnsole-normalizer-',
    );
    addTearDown(() => cache.delete(recursive: true));
    final backend = _FakeBackend(
      <Map<String, Object?>>[
        _canonicalProbe(
          videoOverrides: const <String, Object?>{
            'profile': 'Main',
            'level': 40,
            'width': 1920,
            'height': 1080,
            'r_frame_rate': '24/1',
            'avg_frame_rate': '24/1',
            'time_base': '1/24000',
            'has_b_frames': 2,
          },
        ),
      ],
      packetOutputs: <String>[
        _packetCsv(frameCount: 24, keyframes: const <int>{0}, fps: 24),
      ],
    );
    final source =
        'data:video/mp4;base64,${base64Encode(_minimalFastStartMp4())}';
    final normalizer = ReferenceVideoNormalizer(
      backend: backend,
      cacheDirectory: () async => cache,
    );

    final result = await normalizer.normalize(<String>[
      source,
    ], profile: ReferenceVideoCompatibilityProfile.generic);

    expect(result.sources, <String>[source]);
    expect(result.changedIndexes, isEmpty);
    expect(backend.ffmpegArguments, isEmpty);
  });

  test('generic repairs preserve native resolution, aspect, and fps', () async {
    final cache = await Directory.systemTemp.createTemp(
      'clawnsole-normalizer-',
    );
    addTearDown(() => cache.delete(recursive: true));
    final backend = _FakeBackend(
      <Map<String, Object?>>[
        _canonicalProbe(
          videoOverrides: const <String, Object?>{
            'codec_name': 'hevc',
            'level': 153,
            'width': 3840,
            'height': 2160,
            'r_frame_rate': '24/1',
            'avg_frame_rate': '24/1',
            'time_base': '1/24000',
          },
        ),
        _canonicalProbe(
          videoOverrides: const <String, Object?>{
            'profile': 'Main',
            'level': 51,
            'width': 3840,
            'height': 2160,
            'r_frame_rate': '24/1',
            'avg_frame_rate': '24/1',
            'time_base': '1/90000',
          },
        ),
      ],
      packetOutputs: <String>[
        _packetCsv(frameCount: 24, keyframes: const <int>{0}, fps: 24),
        _packetCsv(frameCount: 24, keyframes: const <int>{0}, fps: 24),
      ],
    );
    final source =
        'data:video/quicktime;base64,${base64Encode(_minimalFastStartMp4())}';
    final normalizer = ReferenceVideoNormalizer(
      backend: backend,
      cacheDirectory: () async => cache,
    );

    final result = await normalizer.normalize(<String>[
      source,
    ], profile: ReferenceVideoCompatibilityProfile.generic);

    expect(result.changedIndexes, <int>{0});
    final arguments = backend.ffmpegArguments.single;
    final filter = arguments[arguments.indexOf('-vf') + 1];
    expect(filter, contains('fps=24/1'));
    expect(filter, contains('scale=w=3840:h=2160'));
    expect(filter, contains('force_original_aspect_ratio=decrease'));
    expect(filter, isNot(contains('crop=')));
    expect(filter, isNot(contains('pad=')));
    expect(arguments, containsAllInOrder(<String>['-r', '24/1']));
    expect(arguments, isNot(contains('-level:v')));
  });

  test(
    'HDR incompatible references use the full compatibility filter',
    () async {
      final cache = await Directory.systemTemp.createTemp(
        'clawnsole-normalizer-',
      );
      addTearDown(() => cache.delete(recursive: true));
      final backend = _FakeBackend(<Map<String, Object?>>[
        _canonicalProbe(
          videoOverrides: <String, Object?>{
            'codec_name': 'hevc',
            'color_transfer': 'smpte2084',
          },
        ),
        _canonicalProbe(),
      ]);
      final source =
          'data:video/quicktime;base64,${base64Encode(_minimalFastStartMp4())}';
      final normalizer = ReferenceVideoNormalizer(
        backend: backend,
        cacheDirectory: () async => cache,
      );

      final result = await normalizer.normalize(<String>[
        source,
      ], profile: ReferenceVideoCompatibilityProfile.seedance);

      expect(result.changedIndexes, <int>{0});
      final arguments = backend.ffmpegArguments.single;
      expect(arguments, containsAllInOrder(<String>['-c:v', 'test_h264']));
      final filter = arguments[arguments.indexOf('-vf') + 1];
      expect(filter, contains('zscale=t=linear:npl=100'));
      expect(filter, contains('tonemap=tonemap=hable:desat=0'));
      expect(filter, contains('fps=30'));
      expect(filter, contains('force_original_aspect_ratio=decrease'));
      expect(filter, contains('pad='));
      expect(filter, isNot(contains('crop=')));
      expect(filter, contains('setsar=1'));
      expect(filter, contains('setparams=range=limited'));
    },
  );

  test('a long GOP tail after the opening keyframe is repaired', () async {
    final cache = await Directory.systemTemp.createTemp(
      'clawnsole-normalizer-',
    );
    addTearDown(() => cache.delete(recursive: true));
    final backend = _FakeBackend(
      <Map<String, Object?>>[_canonicalProbe(), _canonicalProbe()],
      packetOutputs: <String>[
        _packetCsv(frameCount: 91, keyframes: const <int>{0}),
        _packetCsv(frameCount: 31, keyframes: const <int>{0}),
      ],
    );
    final source =
        'data:video/quicktime;base64,${base64Encode(_minimalFastStartMp4())}';
    final normalizer = ReferenceVideoNormalizer(
      backend: backend,
      cacheDirectory: () async => cache,
    );

    final result = await normalizer.normalize(<String>[
      source,
    ], profile: ReferenceVideoCompatibilityProfile.seedance);

    expect(result.changedIndexes, <int>{0});
    expect(backend.ffmpegArguments, hasLength(1));
  });

  test('nominal 30 fps metadata does not let VFR packets pass', () async {
    final cache = await Directory.systemTemp.createTemp(
      'clawnsole-normalizer-',
    );
    addTearDown(() => cache.delete(recursive: true));
    final backend = _FakeBackend(
      <Map<String, Object?>>[_canonicalProbe(), _canonicalProbe()],
      packetOutputs: <String>[
        '0,0.000000,0.000000,K_\n'
            '0,0.020000,0.020000,__\n'
            '0,0.066667,0.066667,__\n',
        _packetCsv(frameCount: 3, keyframes: const <int>{0}),
      ],
    );
    final source =
        'data:video/quicktime;base64,${base64Encode(_minimalFastStartMp4())}';
    final normalizer = ReferenceVideoNormalizer(
      backend: backend,
      cacheDirectory: () async => cache,
    );

    final result = await normalizer.normalize(<String>[
      source,
    ], profile: ReferenceVideoCompatibilityProfile.seedance);

    expect(result.changedIndexes, <int>{0});
    expect(backend.ffmpegArguments, hasLength(1));
  });

  test('QuickTime major brand is remuxed even with canonical codecs', () async {
    final cache = await Directory.systemTemp.createTemp(
      'clawnsole-normalizer-',
    );
    addTearDown(() => cache.delete(recursive: true));
    final backend = _FakeBackend(<Map<String, Object?>>[
      _canonicalProbe(majorBrand: 'qt  '),
      _canonicalProbe(),
    ]);
    final source =
        'data:video/quicktime;base64,${base64Encode(_minimalFastStartMp4())}';
    final normalizer = ReferenceVideoNormalizer(
      backend: backend,
      cacheDirectory: () async => cache,
    );

    final result = await normalizer.normalize(<String>[
      source,
    ], profile: ReferenceVideoCompatibilityProfile.seedance);

    expect(result.changedIndexes, <int>{0});
    final arguments = backend.ffmpegArguments.single;
    expect(arguments, containsAllInOrder(<String>['-c:v', 'copy']));
  });

  test('non-video and non-audio streams are removed by remuxing', () async {
    final cache = await Directory.systemTemp.createTemp(
      'clawnsole-normalizer-',
    );
    addTearDown(() => cache.delete(recursive: true));
    final backend = _FakeBackend(<Map<String, Object?>>[
      _canonicalProbe(
        additionalStreams: const <Map<String, Object?>>[
          <String, Object?>{'codec_type': 'attachment', 'index': 1},
        ],
      ),
      _canonicalProbe(),
    ]);
    final source =
        'data:video/quicktime;base64,${base64Encode(_minimalFastStartMp4())}';
    final normalizer = ReferenceVideoNormalizer(
      backend: backend,
      cacheDirectory: () async => cache,
    );

    final result = await normalizer.normalize(<String>[
      source,
    ], profile: ReferenceVideoCompatibilityProfile.seedance);

    expect(result.changedIndexes, <int>{0});
    expect(
      backend.ffmpegArguments.single,
      containsAllInOrder(<String>['-c:v', 'copy']),
    );
  });

  test(
    'Android fallback validates output and accepts generated Main H.264',
    () async {
      final cache = await Directory.systemTemp.createTemp(
        'clawnsole-normalizer-',
      );
      addTearDown(() => cache.delete(recursive: true));
      final attempts = referenceVideoEncoderAttemptsForPlatform('android');
      final backend = _FakeBackend(
        <Map<String, Object?>>[
          _canonicalProbe(
            videoOverrides: const <String, Object?>{'profile': 'Main'},
          ),
          _canonicalProbe(
            videoOverrides: const <String, Object?>{'codec_name': 'hevc'},
          ),
          _canonicalProbe(
            videoOverrides: const <String, Object?>{'profile': 'Main'},
          ),
          _canonicalProbe(
            videoOverrides: const <String, Object?>{'profile': 'Main'},
          ),
        ],
        encoderAttempts: attempts,
        ffmpegExitCodes: const <int>[0, 0],
      );
      final source =
          'data:video/quicktime;base64,${base64Encode(_minimalFastStartMp4())}';
      final normalizer = ReferenceVideoNormalizer(
        backend: backend,
        cacheDirectory: () async => cache,
      );

      final result = await normalizer.normalize(<String>[
        source,
      ], profile: ReferenceVideoCompatibilityProfile.seedance);
      await normalizer.normalize(<String>[
        source,
      ], profile: ReferenceVideoCompatibilityProfile.seedance);

      expect(result.changedIndexes, <int>{0});
      expect(
        backend.ffmpegArguments.map(
          (arguments) => arguments[arguments.indexOf('-c:v') + 1],
        ),
        <String>['h264_mediacodec', 'h264_mediacodec'],
      );
      expect(
        backend.ffmpegArguments.map(
          (arguments) => arguments[arguments.indexOf('-pix_fmt') + 1],
        ),
        <String>['yuv420p', 'nv12'],
      );
      expect(backend.outputExistedBeforeFfmpeg, everyElement(isFalse));
      expect(backend.ffmpegArguments, hasLength(2));
    },
  );

  test('Windows encoder attempts fall back from Media Foundation', () async {
    final cache = await Directory.systemTemp.createTemp(
      'clawnsole-normalizer-',
    );
    addTearDown(() => cache.delete(recursive: true));
    final attempts = referenceVideoEncoderAttemptsForPlatform('windows');
    final backend = _FakeBackend(
      <Map<String, Object?>>[
        _canonicalProbe(
          videoOverrides: const <String, Object?>{'codec_name': 'hevc'},
        ),
        _canonicalProbe(
          videoOverrides: const <String, Object?>{'profile': 'Baseline'},
        ),
      ],
      encoderAttempts: attempts,
      ffmpegExitCodes: const <int>[1, 0],
    );
    final source =
        'data:video/quicktime;base64,${base64Encode(_minimalFastStartMp4())}';
    final normalizer = ReferenceVideoNormalizer(
      backend: backend,
      cacheDirectory: () async => cache,
    );

    await normalizer.normalize(<String>[
      source,
    ], profile: ReferenceVideoCompatibilityProfile.seedance);

    expect(
      backend.ffmpegArguments.map(
        (arguments) => arguments[arguments.indexOf('-c:v') + 1],
      ),
      <String>['h264_mf', 'libopenh264'],
    );
    expect(backend.outputExistedBeforeFfmpeg, everyElement(isFalse));
  });

  test('changed derivatives clear retained originals and thumbnails', () async {
    final retained = const AssetReference(
      kind: 'local',
      value: 'asset.mp4',
      label: 'Original',
    );
    final config = GenerationConfig(
      aspectRatio: '16:9',
      duration: 5,
      resolution: 'hd',
      generateAudio: true,
      safetyTolerance: 2,
      draft: false,
      references: <MediaReferenceLabel>[
        MediaReferenceLabel(
          label: 'Still',
          kind: MediaReferenceKind.image,
          source: retained,
        ),
        MediaReferenceLabel(
          label: 'Clip',
          kind: MediaReferenceKind.video,
          source: retained,
          thumbnailAsset: retained,
        ),
      ],
    );
    final prepared = await prepareGenerationReferenceVideos(
      input: <String, Object?>{
        'reference_videos': <String>['original'],
      },
      config: config,
      normalizer: _ChangedNormalizer(),
      profile: ReferenceVideoCompatibilityProfile.seedance,
    );

    expect(prepared.input['reference_videos'], <String>['fixed']);
    expect(prepared.config.references![0].source, same(retained));
    expect(prepared.config.references![1].source, isNull);
    expect(prepared.config.references![1].thumbnailAsset, isNull);
  });

  test(
    'direct non-Seedance submit selects generic repair and derivative',
    () async {
      final store = _MemoryStore(
        const StoredData(apiKeys: <String, String>{'artcraft': 'secret'}),
      );
      final api = _CapturingArtCraftApi();
      final normalizer = _ChangedNormalizer();
      final gateway = DirectGateway(
        store: store,
        providerRouter: ProviderApiRouter(artcraft: api),
        referenceVideoNormalizer: normalizer,
      );
      final now = DateTime.utc(2026, 8, 21);
      const original = AssetReference(
        kind: 'local',
        value: 'original.mp4',
        label: 'Original',
      );
      final record = Generation(
        localId: 'generic-reference-submit',
        provider: 'artcraft',
        model: 'minimax_h3',
        status: 'submitting',
        prompt: 'Follow the movement',
        mode: VideoMode.i2v,
        config: const GenerationConfig(
          aspectRatio: '16:9',
          duration: 5,
          resolution: 'hd',
          generateAudio: true,
          safetyTolerance: 2,
          draft: false,
          references: <MediaReferenceLabel>[
            MediaReferenceLabel(
              label: 'Original',
              kind: MediaReferenceKind.video,
              source: original,
            ),
          ],
        ),
        createdAt: now,
        updatedAt: now,
      );

      final submitted = await gateway.submit(
        GenerationSubmission(
          record: record,
          input: <String, Object?>{
            'mode': 'i2v',
            'reference_videos': <String>['original'],
          },
        ),
      );

      expect(api.input['reference_videos'], <String>['fixed']);
      expect(normalizer.profile, ReferenceVideoCompatibilityProfile.generic);
      expect(store.persistedSources, <String>['fixed']);
      expect(submitted.config.references!.single.source!.value, 'fixed');
    },
  );

  test(
    'direct submit normalizes image frames without a video profile',
    () async {
      final store = _MemoryStore(
        const StoredData(apiKeys: <String, String>{'artcraft': 'secret'}),
      );
      final api = _CapturingArtCraftApi();
      final normalizer = _ChangedMediaNormalizer();
      final gateway = DirectGateway(
        store: store,
        providerRouter: ProviderApiRouter(artcraft: api),
        referenceVideoNormalizer: normalizer,
      );
      final now = DateTime.utc(2026, 8, 22);
      const original = AssetReference(
        kind: 'local',
        value: 'original.heic',
        label: 'Original',
      );
      final submitted = await gateway.submit(
        GenerationSubmission(
          record: Generation(
            localId: 'image-reference-submit',
            provider: 'artcraft',
            model: 'veo_3_fast',
            status: 'submitting',
            prompt: 'Animate the frame',
            mode: VideoMode.i2v,
            config: const GenerationConfig(
              aspectRatio: '16:9',
              duration: 5,
              resolution: 'hd',
              generateAudio: true,
              safetyTolerance: 2,
              draft: false,
              keyframes: <KeyframeLabel>[
                KeyframeLabel(
                  label: 'Original',
                  role: KeyframeRole.start,
                  source: original,
                ),
              ],
            ),
            createdAt: now,
            updatedAt: now,
          ),
          input: <String, Object?>{
            'mode': 'i2v',
            'keyframes': <String>['image-original'],
          },
        ),
      );

      expect(modelById('artcraft', 'veo_3_fast').maxVideoReferences, 0);
      expect(api.input['keyframes'], <String>['image-fixed']);
      expect(store.persistedSources, <String>['image-fixed']);
      expect(submitted.config.keyframes!.single.source!.value, 'image-fixed');
    },
  );

  test('submission toggle bypasses image normalization', () async {
    final store = _MemoryStore(
      const StoredData(apiKeys: <String, String>{'artcraft': 'secret'}),
    );
    final api = _CapturingArtCraftApi();
    final gateway = DirectGateway(
      store: store,
      providerRouter: ProviderApiRouter(artcraft: api),
      referenceVideoNormalizer: _FailingMediaNormalizer(),
    );
    final now = DateTime.utc(2026, 8, 22);
    await gateway.submit(
      GenerationSubmission(
        record: Generation(
          localId: 'image-normalization-disabled',
          provider: 'artcraft',
          model: 'veo_3_fast',
          status: 'submitting',
          prompt: 'Keep the original',
          mode: VideoMode.i2v,
          config: const GenerationConfig(
            aspectRatio: '16:9',
            duration: 5,
            resolution: 'hd',
            generateAudio: true,
            safetyTolerance: 2,
            draft: false,
            keyframes: <KeyframeLabel>[
              KeyframeLabel(label: 'Original', role: KeyframeRole.start),
            ],
          ),
          createdAt: now,
          updatedAt: now,
        ),
        input: <String, Object?>{
          'mode': 'i2v',
          'keyframes': <String>['image-original'],
        },
        autoFixReferenceVideos: false,
      ),
    );

    expect(api.input['keyframes'], <String>['image-original']);
  });

  test('submission toggle overrides a not-yet-persisted preference', () async {
    final store = _MemoryStore(
      const StoredData(apiKeys: <String, String>{'artcraft': 'secret'}),
    );
    final api = _CapturingArtCraftApi();
    final gateway = DirectGateway(
      store: store,
      providerRouter: ProviderApiRouter(artcraft: api),
      referenceVideoNormalizer: _FailingNormalizer(),
    );
    final now = DateTime.utc(2026, 8, 21);
    await gateway.submit(
      GenerationSubmission(
        record: Generation(
          localId: 'seedance-disabled',
          provider: 'artcraft',
          model: 'seedance_2p0',
          status: 'submitting',
          prompt: 'Original',
          mode: VideoMode.i2v,
          config: const GenerationConfig(
            aspectRatio: '16:9',
            duration: 5,
            resolution: 'hd',
            generateAudio: true,
            safetyTolerance: 2,
            draft: false,
            references: <MediaReferenceLabel>[
              MediaReferenceLabel(
                label: 'Original',
                kind: MediaReferenceKind.video,
              ),
            ],
          ),
          createdAt: now,
          updatedAt: now,
        ),
        input: <String, Object?>{
          'mode': 'i2v',
          'reference_videos': <String>['original'],
        },
        autoFixReferenceVideos: false,
      ),
    );

    expect(api.input['reference_videos'], <String>['original']);
  });

  test('packaged tools repair a real clip with audio', () async {
    final toolsDirectory =
        Platform.environment['CLAWNSOLE_TEST_MEDIA_TOOLS_DIR'];
    if (toolsDirectory == null || toolsDirectory.isEmpty) return;
    final temporary = await Directory.systemTemp.createTemp(
      'clawnsole-real-normalizer-',
    );
    addTearDown(() => temporary.delete(recursive: true));
    final backend = ProcessReferenceVideoToolBackend(
      ffmpegPath: '$toolsDirectory${Platform.pathSeparator}ffmpeg',
      ffprobePath: '$toolsDirectory${Platform.pathSeparator}ffprobe',
    );
    final sourceFile = File('${temporary.path}/source.mov');
    final generated = await backend.runFfmpeg(<String>[
      '-hide_banner',
      '-loglevel',
      'error',
      '-f',
      'lavfi',
      '-i',
      'testsrc2=size=640x480:rate=24',
      '-f',
      'lavfi',
      '-i',
      'sine=frequency=1000:sample_rate=44100',
      '-t',
      '0.5',
      '-c:v',
      'h264_videotoolbox',
      '-allow_sw',
      '1',
      '-pix_fmt',
      'yuv420p',
      '-c:a',
      'aac',
      '-shortest',
      sourceFile.path,
    ]);
    expect(generated.succeeded, isTrue, reason: generated.output);
    final source =
        'data:video/quicktime;base64,'
        '${base64Encode(await sourceFile.readAsBytes())}';
    final normalizer = ReferenceVideoNormalizer(
      backend: backend,
      cacheDirectory: () async => Directory('${temporary.path}/cache'),
    );

    final normalized = await normalizer.normalize(<String>[
      source,
    ], profile: ReferenceVideoCompatibilityProfile.seedance);

    expect(normalized.changedIndexes, <int>{0});
    expect(normalized.sources.single, startsWith('data:video/mp4;base64,'));
  });

  test('packaged tools convert a real HEIF image', () async {
    final toolsDirectory =
        Platform.environment['CLAWNSOLE_TEST_MEDIA_TOOLS_DIR'];
    final heifPath = Platform.environment['CLAWNSOLE_TEST_HEIF_PATH'];
    if (toolsDirectory == null ||
        toolsDirectory.isEmpty ||
        heifPath == null ||
        heifPath.isEmpty) {
      return;
    }
    final temporary = await Directory.systemTemp.createTemp(
      'clawnsole-real-image-normalizer-',
    );
    addTearDown(() => temporary.delete(recursive: true));
    final backend = ProcessReferenceVideoToolBackend(
      ffmpegPath: '$toolsDirectory${Platform.pathSeparator}ffmpeg',
      ffprobePath: '$toolsDirectory${Platform.pathSeparator}ffprobe',
    );
    final source =
        'data:image/heif;base64,'
        '${base64Encode(await File(heifPath).readAsBytes())}';
    final normalizer = ReferenceVideoNormalizer(
      backend: backend,
      cacheDirectory: () async => Directory('${temporary.path}/cache'),
    );

    final normalized = await normalizer.normalizeImages(<String>[source]);

    expect(normalized.changedIndexes, <int>{0});
    expect(normalized.sources.single, startsWith('data:image/jpeg;base64,'));
    final jpeg = base64Decode(normalized.sources.single.split(',').last);
    expect(jpeg.sublist(0, 3), <int>[0xff, 0xd8, 0xff]);

    // Tiled iPhone HEIC photos expose each tile as a video stream and the
    // actual photo as the default presentation group. The normalized JPEG
    // must retain that presentation size rather than extracting stream 0.
    final sourceProbe = await backend.runFfprobe(<String>[
      '-v',
      'error',
      '-show_stream_groups',
      '-of',
      'json',
      heifPath,
    ]);
    final sourceJson = jsonDecode(sourceProbe.output) as Map<String, Object?>;
    final defaultGroup =
        (sourceJson['stream_groups'] as List<Object?>? ?? const <Object?>[])
            .whereType<Map<String, Object?>>()
            .where(
              (group) =>
                  (group['disposition'] as Map<String, Object?>?)?['default'] ==
                  1,
            )
            .firstOrNull;
    final component =
        (defaultGroup?['components'] as List<Object?>? ?? const <Object?>[])
            .whereType<Map<String, Object?>>()
            .firstOrNull;
    if (component != null) {
      final jpegFile = File('${temporary.path}/normalized.jpg');
      await jpegFile.writeAsBytes(jpeg);
      final outputProbe = await backend.runFfprobe(<String>[
        '-v',
        'error',
        '-show_streams',
        '-of',
        'json',
        jpegFile.path,
      ]);
      final outputJson = jsonDecode(outputProbe.output) as Map<String, Object?>;
      final outputStream =
          (outputJson['streams'] as List<Object?>).single
              as Map<String, Object?>;
      expect(outputStream['width'], component['width']);
      expect(outputStream['height'], component['height']);
    }
  });
}

class _ChangedNormalizer implements ReferenceVideoNormalizationService {
  ReferenceVideoCompatibilityProfile? profile;

  @override
  Future<PreparedReferenceVideos> normalize(
    List<String> sources, {
    required ReferenceVideoCompatibilityProfile profile,
  }) async {
    this.profile = profile;
    return const PreparedReferenceVideos(
      sources: <String>['fixed'],
      changedIndexes: <int>{0},
    );
  }
}

class _FailingNormalizer implements ReferenceVideoNormalizationService {
  @override
  Future<PreparedReferenceVideos> normalize(
    List<String> sources, {
    required ReferenceVideoCompatibilityProfile profile,
  }) => throw StateError('Normalizer should not run.');
}

class _ChangedImageNormalizer implements ReferenceImageNormalizationService {
  @override
  Future<PreparedReferenceImages> normalizeImages(List<String> sources) async =>
      PreparedReferenceImages(
        sources: List<String>.filled(sources.length, 'image-fixed'),
        changedIndexes: Set<int>.from(
          List<int>.generate(sources.length, (index) => index),
        ),
      );
}

class _ChangedMediaNormalizer
    implements
        ReferenceVideoNormalizationService,
        ReferenceImageNormalizationService {
  @override
  Future<PreparedReferenceImages> normalizeImages(List<String> sources) async =>
      PreparedReferenceImages(
        sources: List<String>.filled(sources.length, 'image-fixed'),
        changedIndexes: Set<int>.from(
          List<int>.generate(sources.length, (index) => index),
        ),
      );

  @override
  Future<PreparedReferenceVideos> normalize(
    List<String> sources, {
    required ReferenceVideoCompatibilityProfile profile,
  }) => throw StateError('Video normalization should not run.');
}

class _FailingMediaNormalizer
    implements
        ReferenceVideoNormalizationService,
        ReferenceImageNormalizationService {
  @override
  Future<PreparedReferenceImages> normalizeImages(List<String> sources) =>
      throw StateError('Image normalization should not run.');

  @override
  Future<PreparedReferenceVideos> normalize(
    List<String> sources, {
    required ReferenceVideoCompatibilityProfile profile,
  }) => throw StateError('Video normalization should not run.');
}

class _ImageBackend implements ReferenceVideoToolBackend {
  final List<List<String>> ffmpegArguments = <List<String>>[];

  @override
  List<ReferenceVideoEncoderAttempt> get h264EncoderAttempts => const [];

  @override
  Future<ReferenceVideoToolResult> runFfmpeg(List<String> arguments) async {
    ffmpegArguments.add(List<String>.of(arguments));
    await File(arguments.last).writeAsBytes(<int>[0xff, 0xd8, 0xff, 0xd9]);
    return const ReferenceVideoToolResult(exitCode: 0, output: '');
  }

  @override
  Future<ReferenceVideoToolResult> runFfprobe(List<String> arguments) =>
      throw StateError('Image normalization does not use ffprobe.');
}

class _FakeBackend implements ReferenceVideoToolBackend {
  _FakeBackend(
    this.probes, {
    this.packetOutputs = const <String>[
      '0,0.000000,0.000000,K_\n0,0.033333,0.033333,__\n',
    ],
    List<ReferenceVideoEncoderAttempt>? encoderAttempts,
    this.ffmpegExitCodes = const <int>[],
  }) : h264EncoderAttempts =
           encoderAttempts ??
           const <ReferenceVideoEncoderAttempt>[
             ReferenceVideoEncoderAttempt(encoder: 'test_h264'),
           ];

  final List<Map<String, Object?>> probes;
  final List<String> packetOutputs;
  final List<int> ffmpegExitCodes;
  final List<List<String>> ffmpegArguments = <List<String>>[];
  final List<bool> outputExistedBeforeFfmpeg = <bool>[];
  var probeIndex = 0;
  var packetIndex = 0;

  @override
  final List<ReferenceVideoEncoderAttempt> h264EncoderAttempts;

  @override
  Future<ReferenceVideoToolResult> runFfmpeg(List<String> arguments) async {
    ffmpegArguments.add(List<String>.of(arguments));
    final output = File(arguments.last);
    outputExistedBeforeFfmpeg.add(await output.exists());
    await output.writeAsBytes(_minimalFastStartMp4());
    final index = ffmpegArguments.length - 1;
    final exitCode = index < ffmpegExitCodes.length
        ? ffmpegExitCodes[index]
        : 0;
    return ReferenceVideoToolResult(exitCode: exitCode, output: 'failed');
  }

  @override
  Future<ReferenceVideoToolResult> runFfprobe(List<String> arguments) async {
    if (arguments.contains('-print_format')) {
      return ReferenceVideoToolResult(
        exitCode: 0,
        output: jsonEncode(probes[probeIndex++]),
      );
    }
    final output =
        packetOutputs[packetIndex < packetOutputs.length
            ? packetIndex++
            : packetOutputs.length - 1];
    return ReferenceVideoToolResult(exitCode: 0, output: output);
  }
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
      'id': 'job',
      'polling_url': 'https://api.storyteller.ai/v1/job/job',
    };
  }
}

class _MemoryStore implements DurableDataStore {
  _MemoryStore(this.data);

  StoredData data;
  final List<String> persistedSources = <String>[];

  @override
  Future<StoredData> read() async => data;

  @override
  Future<void> write(StoredData data) async => this.data = data;

  @override
  Future<void> delete() async => data = const StoredData();

  @override
  Future<AssetReference?> persistSource(
    String source, {
    required String label,
    AssetReference? retained,
    LibraryStorage storage = LibraryStorage.local,
  }) async {
    if (retained != null) return retained;
    persistedSources.add(source);
    return AssetReference(kind: 'local', value: source, label: label);
  }

  @override
  Future<void> pruneAssets(
    List<Generation> generations, [
    List<SavedReference> savedReferences = const <SavedReference>[],
  ]) async {}

  @override
  Future<Uint8List> readAsset(AssetReference reference) async => Uint8List(0);

  @override
  Future<Uri> assetUri(AssetReference reference) async => Uri();

  @override
  Future<StorageStats> stats(int records) async =>
      StorageStats(path: 'memory', bytes: 0, records: records);

  @override
  Future<AssetReference> writeAsset(
    Uint8List bytes, {
    required String label,
    required String contentType,
    LibraryStorage storage = LibraryStorage.local,
  }) async => AssetReference(kind: 'local', value: label, label: label);
}

Map<String, Object?> _canonicalProbe({
  Map<String, Object?> videoOverrides = const <String, Object?>{},
  List<Map<String, Object?>> additionalStreams = const <Map<String, Object?>>[],
  String majorBrand = 'isom',
}) {
  final video = <String, Object?>{
    'codec_type': 'video',
    'index': 0,
    'codec_name': 'h264',
    'profile': 'High',
    'level': 31,
    'pix_fmt': 'yuv420p',
    'width': 720,
    'height': 720,
    'r_frame_rate': '30/1',
    'avg_frame_rate': '30/1',
    'sample_aspect_ratio': '1:1',
    'has_b_frames': 0,
    'codec_tag_string': 'avc1',
    'color_space': 'bt709',
    'color_primaries': 'bt709',
    'color_transfer': 'bt709',
    'color_range': 'tv',
    'time_base': '1/30000',
    'start_time': '0.000000',
    ...videoOverrides,
  };
  return <String, Object?>{
    'streams': <Object?>[video, ...additionalStreams],
    'chapters': <Object?>[],
    'format': <String, Object?>{
      'format_name': 'mov,mp4,m4a,3gp,3g2,mj2',
      'start_time': '0.000000',
      'tags': <String, Object?>{'major_brand': majorBrand},
    },
  };
}

Map<String, Object?> _audioProbe({
  Object profile = 'LC',
  String sampleRate = '48000',
  int channels = 2,
}) => <String, Object?>{
  'codec_type': 'audio',
  'index': 1,
  'codec_name': 'aac',
  'profile': profile,
  'sample_rate': sampleRate,
  'channels': channels,
};

Uint8List _minimalFastStartMp4() => Uint8List.fromList(<int>[
  0,
  0,
  0,
  16,
  ...ascii.encode('ftyp'),
  ...ascii.encode('isom0000'),
  0,
  0,
  0,
  8,
  ...ascii.encode('moov'),
  0,
  0,
  0,
  8,
  ...ascii.encode('mdat'),
]);

String _packetCsv({
  required int frameCount,
  required Set<int> keyframes,
  double fps = 30,
}) => List<String>.generate(frameCount, (index) {
  final timestamp = (index / fps).toStringAsFixed(6);
  final flags = keyframes.contains(index) ? 'K_' : '__';
  return '0,$timestamp,$timestamp,$flags';
}).join('\n');
