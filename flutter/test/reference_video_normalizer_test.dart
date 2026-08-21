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
  test('only Seedance models with video references declare the profile', () {
    expect(
      modelById('artcraft', 'seedance_2p0').referenceVideoCompatibilityProfile,
      ReferenceVideoCompatibilityProfile.seedance,
    );
    expect(
      modelById(
        'atlas',
        'bytedance/seedance-2.5/reference-to-video',
      ).referenceVideoCompatibilityProfile,
      ReferenceVideoCompatibilityProfile.seedance,
    );
    expect(
      modelById(
        'atlas',
        'bytedance/seedance-2.5/text-to-video',
      ).referenceVideoCompatibilityProfile,
      isNull,
    );
    expect(
      modelById('artcraft', 'flux_3').referenceVideoCompatibilityProfile,
      isNull,
    );
  });

  test('canvas and framing preserve the script thresholds', () {
    expect(ReferenceVideoCanvas.forDisplaySize(749, 1000).width, 720);
    expect(ReferenceVideoCanvas.forDisplaySize(749, 1000).height, 1280);
    expect(ReferenceVideoCanvas.forDisplaySize(750, 1000).height, 720);
    expect(ReferenceVideoCanvas.forDisplaySize(640, 480).width, 1280);
    expect(ReferenceVideoCanvas.forDisplaySize(1334, 1000).width, 1280);
    expect(
      referenceVideoFraming(
        width: 920,
        height: 1000,
        canvas: const ReferenceVideoCanvas(1000, 1000),
      ),
      ReferenceVideoFraming.fill,
    );
    expect(
      referenceVideoFraming(
        width: 919,
        height: 1000,
        canvas: const ReferenceVideoCanvas(1000, 1000),
      ),
      ReferenceVideoFraming.fit,
    );
  });

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

      final result = await normalizer.normalize(<String>[source]);

      expect(result.sources, <String>[source]);
      expect(result.changedIndexes, isEmpty);
      expect(backend.ffmpegArguments, isEmpty);
    },
  );

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

      final result = await normalizer.normalize(<String>[source]);

      expect(result.changedIndexes, <int>{0});
      final arguments = backend.ffmpegArguments.single;
      expect(arguments, containsAllInOrder(<String>['-c:v', 'test_h264']));
      final filter = arguments[arguments.indexOf('-vf') + 1];
      expect(filter, contains('zscale=t=linear:npl=100'));
      expect(filter, contains('tonemap=tonemap=hable:desat=0'));
      expect(filter, contains('fps=30'));
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

    final result = await normalizer.normalize(<String>[source]);

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

    final result = await normalizer.normalize(<String>[source]);

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

    final result = await normalizer.normalize(<String>[source]);

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

    final result = await normalizer.normalize(<String>[source]);

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

      final result = await normalizer.normalize(<String>[source]);
      await normalizer.normalize(<String>[source]);

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

    await normalizer.normalize(<String>[source]);

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
    );

    expect(prepared.input['reference_videos'], <String>['fixed']);
    expect(prepared.config.references![0].source, same(retained));
    expect(prepared.config.references![1].source, isNull);
    expect(prepared.config.references![1].thumbnailAsset, isNull);
  });

  test(
    'direct Seedance submit persists and uploads the repaired derivative',
    () async {
      final store = _MemoryStore(
        const StoredData(apiKeys: <String, String>{'artcraft': 'secret'}),
      );
      final api = _CapturingArtCraftApi();
      final gateway = DirectGateway(
        store: store,
        providerRouter: ProviderApiRouter(artcraft: api),
        referenceVideoNormalizer: _ChangedNormalizer(),
      );
      final now = DateTime.utc(2026, 8, 21);
      const original = AssetReference(
        kind: 'local',
        value: 'original.mp4',
        label: 'Original',
      );
      final record = Generation(
        localId: 'seedance-submit',
        provider: 'artcraft',
        model: 'seedance_2p0',
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
      expect(store.persistedSources, <String>['fixed']);
      expect(submitted.config.references!.single.source!.value, 'fixed');
    },
  );

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

  test('packaged process tools repair and validate a real clip', () async {
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
      '-t',
      '0.5',
      '-c:v',
      'h264_videotoolbox',
      '-allow_sw',
      '1',
      '-pix_fmt',
      'yuv420p',
      '-an',
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

    final normalized = await normalizer.normalize(<String>[source]);

    expect(normalized.changedIndexes, <int>{0});
    expect(normalized.sources.single, startsWith('data:video/mp4;base64,'));
  });
}

class _ChangedNormalizer implements ReferenceVideoNormalizationService {
  @override
  Future<PreparedReferenceVideos> normalize(List<String> sources) async =>
      const PreparedReferenceVideos(
        sources: <String>['fixed'],
        changedIndexes: <int>{0},
      );
}

class _FailingNormalizer implements ReferenceVideoNormalizationService {
  @override
  Future<PreparedReferenceVideos> normalize(List<String> sources) =>
      throw StateError('Normalizer should not run.');
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

String _packetCsv({required int frameCount, required Set<int> keyframes}) =>
    List<String>.generate(frameCount, (index) {
      final timestamp = (index / 30).toStringAsFixed(6);
      final flags = keyframes.contains(index) ? 'K_' : '__';
      return '0,$timestamp,$timestamp,$flags';
    }).join('\n');
