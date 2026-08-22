import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:crypto/crypto.dart';

import 'bfl_api.dart';
import 'models.dart';
import 'provider_catalog.dart';

const int _maxReferenceVideoBytes = 512 * 1024 * 1024;
const int _maxReferenceImageBytes = 128 * 1024 * 1024;
const int _maxNormalizationCacheBytes = 512 * 1024 * 1024;
const Duration _referenceVideoConnectTimeout = Duration(seconds: 20);
const Duration _referenceVideoIdleTimeout = Duration(seconds: 20);
const Duration _referenceVideoDownloadTimeout = Duration(minutes: 5);

enum ReferenceVideoNormalizationAction { none, remux, audio, transcode }

enum ReferenceVideoFraming { fill, fit }

String _profileVersion(ReferenceVideoCompatibilityProfile profile) =>
    switch (profile) {
      ReferenceVideoCompatibilityProfile.generic => 'generic-v1',
      ReferenceVideoCompatibilityProfile.seedance => 'seedance-v1',
    };

class ReferenceVideoCanvas {
  const ReferenceVideoCanvas(this.width, this.height);

  final int width;
  final int height;

  static ReferenceVideoCanvas forDisplaySize(int width, int height) {
    final ratio = width / height;
    if (ratio < .75) return const ReferenceVideoCanvas(720, 1280);
    if (ratio > 1.3333333333) {
      return const ReferenceVideoCanvas(1280, 720);
    }
    return const ReferenceVideoCanvas(720, 720);
  }
}

ReferenceVideoFraming referenceVideoFraming({
  required int width,
  required int height,
  required ReferenceVideoCanvas canvas,
}) {
  final sourceRatio = width / height;
  final targetRatio = canvas.width / canvas.height;
  final retained = sourceRatio < targetRatio
      ? sourceRatio / targetRatio
      : targetRatio / sourceRatio;
  return retained >= .92
      ? ReferenceVideoFraming.fill
      : ReferenceVideoFraming.fit;
}

class ReferenceVideoToolResult {
  const ReferenceVideoToolResult({
    required this.exitCode,
    required this.output,
  });

  final int exitCode;
  final String output;

  bool get succeeded => exitCode == 0;
}

class ReferenceVideoEncoderAttempt {
  const ReferenceVideoEncoderAttempt({
    required this.encoder,
    this.inputPixelFormat = 'yuv420p',
  });

  final String encoder;
  final String inputPixelFormat;
}

abstract interface class ReferenceVideoToolBackend {
  List<ReferenceVideoEncoderAttempt> get h264EncoderAttempts;

  Future<ReferenceVideoToolResult> runFfmpeg(List<String> arguments);

  Future<ReferenceVideoToolResult> runFfprobe(List<String> arguments);
}

class ProcessReferenceVideoToolBackend implements ReferenceVideoToolBackend {
  ProcessReferenceVideoToolBackend({
    required this.ffmpegPath,
    required this.ffprobePath,
    String h264Encoder = 'h264_videotoolbox',
    List<ReferenceVideoEncoderAttempt>? h264EncoderAttempts,
  }) : h264EncoderAttempts =
           h264EncoderAttempts ??
           <ReferenceVideoEncoderAttempt>[
             ReferenceVideoEncoderAttempt(encoder: h264Encoder),
           ];

  final String ffmpegPath;
  final String ffprobePath;

  @override
  final List<ReferenceVideoEncoderAttempt> h264EncoderAttempts;

  @override
  Future<ReferenceVideoToolResult> runFfmpeg(List<String> arguments) =>
      _run(ffmpegPath, arguments);

  @override
  Future<ReferenceVideoToolResult> runFfprobe(List<String> arguments) =>
      _run(ffprobePath, arguments);

  Future<ReferenceVideoToolResult> _run(
    String executable,
    List<String> arguments,
  ) async {
    try {
      final result = await Process.run(executable, arguments);
      return ReferenceVideoToolResult(
        exitCode: result.exitCode,
        output: '${result.stdout}${result.stderr}',
      );
    } on ProcessException {
      throw StateError(
        'Reference compatibility tools are unavailable in this build.',
      );
    }
  }
}

class PreparedReferenceVideos {
  const PreparedReferenceVideos({
    required this.sources,
    this.changedIndexes = const <int>{},
  });

  final List<String> sources;
  final Set<int> changedIndexes;
}

class PreparedReferenceImages {
  const PreparedReferenceImages({
    required this.sources,
    this.changedIndexes = const <int>{},
  });

  final List<String> sources;
  final Set<int> changedIndexes;
}

abstract interface class ReferenceVideoNormalizationService {
  Future<PreparedReferenceVideos> normalize(
    List<String> sources, {
    required ReferenceVideoCompatibilityProfile profile,
  });
}

abstract interface class ReferenceImageNormalizationService {
  Future<PreparedReferenceImages> normalizeImages(List<String> sources);
}

class DisabledReferenceVideoNormalizationService
    implements
        ReferenceVideoNormalizationService,
        ReferenceImageNormalizationService {
  const DisabledReferenceVideoNormalizationService();

  @override
  Future<PreparedReferenceVideos> normalize(
    List<String> sources, {
    required ReferenceVideoCompatibilityProfile profile,
  }) async => PreparedReferenceVideos(sources: List<String>.of(sources));

  @override
  Future<PreparedReferenceImages> normalizeImages(List<String> sources) async =>
      PreparedReferenceImages(sources: List<String>.of(sources));
}

class PreparedGenerationReferences {
  const PreparedGenerationReferences({
    required this.input,
    required this.config,
  });

  final Map<String, Object?> input;
  final GenerationConfig config;
}

String _keyframeImageSource(Object? value) {
  if (value is String) return value;
  if (value is List<Object?> && value.length > 1) {
    return value[1]?.toString() ?? '';
  }
  return '';
}

Object? _replaceKeyframeImageSource(Object? value, String source) {
  if (value is List<Object?> && value.length > 1) {
    return <Object?>[value.first, source, ...value.skip(2)];
  }
  return source;
}

/// Normalizes visual guidance before provider mapping. Changed derivatives
/// deliberately drop retained pointers so persistence saves the compatible
/// derivative while leaving saved references and generated originals intact.
Future<PreparedGenerationReferences> prepareGenerationReferences({
  required Map<String, Object?> input,
  required GenerationConfig config,
  required ReferenceVideoNormalizationService videoNormalizer,
  required ReferenceImageNormalizationService imageNormalizer,
  ReferenceVideoCompatibilityProfile? videoProfile,
}) async {
  var nextInput = input;
  var nextConfig = config;

  final rawFrames = input['keyframes'];
  if (rawFrames is List<Object?> && rawFrames.isNotEmpty) {
    final frameSources = rawFrames.map(_keyframeImageSource).toList();
    final prepared = await imageNormalizer.normalizeImages(frameSources);
    if (prepared.changedIndexes.isNotEmpty) {
      nextInput = Map<String, Object?>.of(nextInput)
        ..['keyframes'] = rawFrames
            .asMap()
            .entries
            .map(
              (entry) => _replaceKeyframeImageSource(
                entry.value,
                prepared.sources[entry.key],
              ),
            )
            .toList();
      final frames = nextConfig.keyframes?.asMap().entries.map((entry) {
        final frame = entry.value;
        if (!prepared.changedIndexes.contains(entry.key)) return frame;
        return KeyframeLabel(
          label: frame.label,
          role: frame.role,
          seconds: frame.seconds,
        );
      }).toList();
      nextConfig = nextConfig.copyWith(keyframes: frames);
    }
  }

  final rawImages = input['reference_images'];
  if (rawImages is List<Object?> && rawImages.isNotEmpty) {
    final sources = rawImages.map((source) => source.toString()).toList();
    final prepared = await imageNormalizer.normalizeImages(sources);
    if (prepared.changedIndexes.isNotEmpty) {
      nextInput = Map<String, Object?>.of(nextInput)
        ..['reference_images'] = prepared.sources;
      var imageIndex = 0;
      final references = nextConfig.references?.map((reference) {
        if (reference.kind != MediaReferenceKind.image) return reference;
        final changed = prepared.changedIndexes.contains(imageIndex++);
        if (!changed) return reference;
        return MediaReferenceLabel(
          label: reference.label,
          kind: reference.kind,
        );
      }).toList();
      nextConfig = nextConfig.copyWith(references: references);
    }
  }

  final rawVideos = input['reference_videos'];
  if (videoProfile != null &&
      rawVideos is List<Object?> &&
      rawVideos.isNotEmpty) {
    final sources = rawVideos.map((source) => source.toString()).toList();
    final prepared = await videoNormalizer.normalize(
      sources,
      profile: videoProfile,
    );
    if (prepared.changedIndexes.isNotEmpty) {
      nextInput = Map<String, Object?>.of(nextInput)
        ..['reference_videos'] = prepared.sources;
      var videoIndex = 0;
      final references = nextConfig.references?.map((reference) {
        if (reference.kind != MediaReferenceKind.video) return reference;
        final changed = prepared.changedIndexes.contains(videoIndex++);
        if (!changed) return reference;
        return MediaReferenceLabel(
          label: reference.label,
          kind: reference.kind,
        );
      }).toList();
      nextConfig = nextConfig.copyWith(references: references);
    }
  }

  return PreparedGenerationReferences(input: nextInput, config: nextConfig);
}

class PreparedGenerationReferenceVideos {
  const PreparedGenerationReferenceVideos({
    required this.input,
    required this.config,
  });

  final Map<String, Object?> input;
  final GenerationConfig config;
}

/// Normalizes only creative-reference videos. Changed clips deliberately drop
/// retained pointers so persistence stores a repaired derivative without ever
/// replacing the saved reference or generated original.
Future<PreparedGenerationReferenceVideos> prepareGenerationReferenceVideos({
  required Map<String, Object?> input,
  required GenerationConfig config,
  required ReferenceVideoNormalizationService normalizer,
  required ReferenceVideoCompatibilityProfile profile,
}) async {
  final prepared = await prepareGenerationReferences(
    input: input,
    config: config,
    videoNormalizer: normalizer,
    imageNormalizer: const DisabledReferenceVideoNormalizationService(),
    videoProfile: profile,
  );
  return PreparedGenerationReferenceVideos(
    input: prepared.input,
    config: prepared.config,
  );
}

class ReferenceVideoNormalizer
    implements
        ReferenceVideoNormalizationService,
        ReferenceImageNormalizationService {
  ReferenceVideoNormalizer({
    required ReferenceVideoToolBackend backend,
    required Future<Directory> Function() cacheDirectory,
  }) : _backend = backend,
       _cacheDirectory = cacheDirectory;

  final ReferenceVideoToolBackend _backend;
  final Future<Directory> Function() _cacheDirectory;

  final Map<String, Future<String>> _inFlight = <String, Future<String>>{};
  final Map<String, Future<String>> _imageInFlight = <String, Future<String>>{};

  @override
  Future<PreparedReferenceImages> normalizeImages(List<String> sources) async {
    final prepared = <String>[];
    final changed = <int>{};
    for (var index = 0; index < sources.length; index += 1) {
      final original = sources[index];
      final normalized = await _normalizeImage(original);
      prepared.add(normalized);
      if (normalized != original) changed.add(index);
    }
    return PreparedReferenceImages(sources: prepared, changedIndexes: changed);
  }

  Future<String> _normalizeImage(String source) async {
    if (!_imageSourceNeedsInspection(source)) return source;
    final sourceKey = sha256.convert(utf8.encode(source)).toString();
    final existing = _imageInFlight[sourceKey];
    if (existing != null) return existing;
    final operation = _normalizeImageUncached(source);
    _imageInFlight[sourceKey] = operation;
    try {
      return await operation;
    } finally {
      _imageInFlight.remove(sourceKey);
    }
  }

  Future<String> _normalizeImageUncached(String source) async {
    final cache = await _cacheDirectory();
    await cache.create(recursive: true);
    final working = await cache.createTemp('working-image-');
    try {
      final materialized = await _materializeImage(source, working);
      final compatibleMime = _compatibleImageMime(materialized.bytes);
      if (compatibleMime != null) {
        final expectedPrefix = 'data:$compatibleMime;base64,';
        return source.startsWith(expectedPrefix)
            ? source
            : '$expectedPrefix${base64Encode(materialized.bytes)}';
      }
      final cacheFile = File(
        '${cache.path}${Platform.pathSeparator}'
        '${materialized.digest}-image-jpeg-v1.jpg',
      );
      if (await cacheFile.exists()) {
        final bytes = await cacheFile.readAsBytes();
        if (_isJpeg(bytes)) {
          await cacheFile.setLastModified(DateTime.now().toUtc());
          return _imageDataUrl(bytes);
        }
        await cacheFile.delete();
      }
      final temporary = File(
        '${cacheFile.path}.tmp-$pid-${DateTime.now().microsecondsSinceEpoch}',
      );
      try {
        final result = await _backend.runFfmpeg(<String>[
          '-hide_banner',
          '-loglevel',
          'warning',
          '-nostdin',
          '-y',
          '-i',
          materialized.file.path,
          '-map',
          '0:v:0',
          '-frames:v',
          '1',
          '-c:v',
          'mjpeg',
          '-q:v',
          '2',
          '-pix_fmt',
          'yuvj420p',
          '-map_metadata',
          '-1',
          '-update',
          '1',
          '-f',
          'image2',
          temporary.path,
        ]);
        final valid =
            result.succeeded &&
            await temporary.exists() &&
            _isJpeg(await temporary.readAsBytes());
        if (!valid) {
          final detail = _lastToolLine(result.output);
          throw StateError(
            detail.isEmpty
                ? 'The reference image could not be converted to JPEG.'
                : 'The reference image could not be converted to JPEG: $detail',
          );
        }
        await temporary.rename(cacheFile.path);
      } finally {
        if (await temporary.exists()) await temporary.delete();
      }
      await _sweepCache(cache, keep: cacheFile);
      return _imageDataUrl(await cacheFile.readAsBytes());
    } finally {
      if (await working.exists()) await working.delete(recursive: true);
    }
  }

  @override
  Future<PreparedReferenceVideos> normalize(
    List<String> sources, {
    required ReferenceVideoCompatibilityProfile profile,
  }) async {
    final prepared = <String>[];
    final changed = <int>{};
    for (var index = 0; index < sources.length; index += 1) {
      final original = sources[index];
      final normalized = await _normalizeOne(original, profile);
      prepared.add(normalized);
      if (normalized != original) changed.add(index);
    }
    return PreparedReferenceVideos(sources: prepared, changedIndexes: changed);
  }

  Future<String> _normalizeOne(
    String source,
    ReferenceVideoCompatibilityProfile profile,
  ) async {
    final sourceKey = sha256
        .convert(utf8.encode('${profile.name}:$source'))
        .toString();
    final existing = _inFlight[sourceKey];
    if (existing != null) return existing;
    final operation = _normalizeUncached(source, profile);
    _inFlight[sourceKey] = operation;
    try {
      return await operation;
    } finally {
      _inFlight.remove(sourceKey);
    }
  }

  Future<String> _normalizeUncached(
    String source,
    ReferenceVideoCompatibilityProfile profile,
  ) async {
    final cache = await _cacheDirectory();
    await cache.create(recursive: true);
    final working = await cache.createTemp('working-');
    try {
      final materialized = await _materialize(source, working);
      final cacheFile = File(
        '${cache.path}${Platform.pathSeparator}'
        '${materialized.digest}-${_profileVersion(profile)}.mp4',
      );
      if (await cacheFile.exists()) {
        try {
          final cachedProbe = await _probe(
            cacheFile,
            profile: profile,
            requireHighProfile: false,
          );
          if (cachedProbe.action == ReferenceVideoNormalizationAction.none) {
            await cacheFile.setLastModified(DateTime.now().toUtc());
            return _dataUrl(await cacheFile.readAsBytes());
          }
        } on Object {
          // A partial or stale cache entry is replaced below.
        }
        await cacheFile.delete();
      }

      final probe = await _probe(
        materialized.file,
        profile: profile,
        requireHighProfile:
            profile == ReferenceVideoCompatibilityProfile.seedance,
      );
      if (probe.action == ReferenceVideoNormalizationAction.none) return source;

      final temporary = File(
        '${cacheFile.path}.tmp-$pid-${DateTime.now().microsecondsSinceEpoch}',
      );
      try {
        var action = probe.action;
        if (action == ReferenceVideoNormalizationAction.transcode) {
          await _transcodeWithFallback(
            input: materialized.file,
            output: temporary,
            probe: probe,
            profile: profile,
          );
        } else {
          await _encode(
            input: materialized.file,
            output: temporary,
            probe: probe,
            action: action,
            profile: profile,
          );
          final outputProbe = await _probe(
            temporary,
            profile: profile,
            requireHighProfile: false,
          );
          if (outputProbe.action != ReferenceVideoNormalizationAction.none) {
            await temporary.delete();
            action = ReferenceVideoNormalizationAction.transcode;
            await _transcodeWithFallback(
              input: materialized.file,
              output: temporary,
              probe: probe,
              profile: profile,
            );
          }
        }
        await temporary.rename(cacheFile.path);
      } finally {
        if (await temporary.exists()) await temporary.delete();
      }
      await _sweepCache(cache, keep: cacheFile);
      return _dataUrl(await cacheFile.readAsBytes());
    } finally {
      if (await working.exists()) await working.delete(recursive: true);
    }
  }

  Future<_MaterializedReferenceVideo> _materialize(
    String source,
    Directory directory,
  ) async {
    final target = File(
      '${directory.path}${Platform.pathSeparator}reference-video.input',
    );
    final digestSink = _SingleValueSink<Digest>();
    final hashSink = sha256.startChunkedConversion(digestSink);
    final output = target.openWrite();
    var length = 0;
    try {
      if (source.startsWith('data:')) {
        final comma = source.indexOf(',');
        if (comma < 0) {
          throw StateError('A reference video upload is malformed.');
        }
        final metadata = source.substring(5, comma).split(';');
        Uint8List bytes;
        try {
          bytes = metadata.contains('base64')
              ? base64Decode(source.substring(comma + 1))
              : Uint8List.fromList(
                  utf8.encode(Uri.decodeComponent(source.substring(comma + 1))),
                );
        } on FormatException {
          throw StateError('A reference video upload is malformed.');
        }
        length = bytes.length;
        if (length > _maxReferenceVideoBytes) {
          throw StateError('Reference videos must be 512 MB or smaller.');
        }
        output.add(bytes);
        hashSink.add(bytes);
      } else {
        final url = validatedProviderUrl(source);
        final client = HttpClient()
          ..connectionTimeout = _referenceVideoConnectTimeout;
        try {
          length = await (() async {
            final request = await client
                .getUrl(url)
                .timeout(_referenceVideoConnectTimeout);
            final response = await request.close().timeout(
              _referenceVideoConnectTimeout,
            );
            if (response.statusCode < 200 || response.statusCode >= 300) {
              throw StateError(
                'The reference video URL could not be downloaded.',
              );
            }
            if (response.contentLength > _maxReferenceVideoBytes) {
              throw StateError('Reference videos must be 512 MB or smaller.');
            }
            var downloaded = 0;
            await for (final chunk in response.timeout(
              _referenceVideoIdleTimeout,
            )) {
              downloaded += chunk.length;
              if (downloaded > _maxReferenceVideoBytes) {
                throw StateError('Reference videos must be 512 MB or smaller.');
              }
              output.add(chunk);
              hashSink.add(chunk);
            }
            return downloaded;
          })().timeout(_referenceVideoDownloadTimeout);
        } on TimeoutException {
          throw StateError('The reference video download timed out.');
        } finally {
          client.close(force: true);
        }
      }
    } finally {
      await output.close();
      hashSink.close();
    }
    if (length == 0 || digestSink.value == null) {
      throw StateError('The reference video is empty.');
    }
    return _MaterializedReferenceVideo(
      file: target,
      digest: digestSink.value.toString(),
    );
  }

  Future<_MaterializedReferenceImage> _materializeImage(
    String source,
    Directory directory,
  ) async {
    final target = File(
      '${directory.path}${Platform.pathSeparator}reference-image.input',
    );
    Uint8List bytes;
    if (source.startsWith('data:')) {
      final comma = source.indexOf(',');
      if (comma < 0) {
        throw StateError('A reference image upload is malformed.');
      }
      final metadata = source.substring(5, comma).split(';');
      try {
        bytes = metadata.contains('base64')
            ? base64Decode(source.substring(comma + 1))
            : Uint8List.fromList(
                utf8.encode(Uri.decodeComponent(source.substring(comma + 1))),
              );
      } on FormatException {
        throw StateError('A reference image upload is malformed.');
      }
    } else {
      final url = validatedProviderUrl(source);
      final client = HttpClient()
        ..connectionTimeout = _referenceVideoConnectTimeout;
      try {
        bytes = await (() async {
          final request = await client
              .getUrl(url)
              .timeout(_referenceVideoConnectTimeout);
          final response = await request.close().timeout(
            _referenceVideoConnectTimeout,
          );
          if (response.statusCode < 200 || response.statusCode >= 300) {
            throw StateError(
              'The reference image URL could not be downloaded.',
            );
          }
          if (response.contentLength > _maxReferenceImageBytes) {
            throw StateError('Reference images must be 128 MB or smaller.');
          }
          final output = BytesBuilder(copy: false);
          var downloaded = 0;
          await for (final chunk in response.timeout(
            _referenceVideoIdleTimeout,
          )) {
            downloaded += chunk.length;
            if (downloaded > _maxReferenceImageBytes) {
              throw StateError('Reference images must be 128 MB or smaller.');
            }
            output.add(chunk);
          }
          return output.takeBytes();
        })().timeout(_referenceVideoDownloadTimeout);
      } on TimeoutException {
        throw StateError('The reference image download timed out.');
      } finally {
        client.close(force: true);
      }
    }
    if (bytes.isEmpty) throw StateError('The reference image is empty.');
    if (bytes.length > _maxReferenceImageBytes) {
      throw StateError('Reference images must be 128 MB or smaller.');
    }
    await target.writeAsBytes(bytes, flush: true);
    return _MaterializedReferenceImage(
      file: target,
      bytes: bytes,
      digest: sha256.convert(bytes).toString(),
    );
  }

  Future<_ReferenceVideoProbe> _probe(
    File file, {
    required ReferenceVideoCompatibilityProfile profile,
    bool requireHighProfile = true,
  }) async {
    final information = await _backend.runFfprobe(<String>[
      '-v',
      'error',
      '-print_format',
      'json',
      '-show_format',
      '-show_streams',
      '-show_chapters',
      file.path,
    ]);
    if (!information.succeeded) {
      throw StateError('The reference video could not be inspected.');
    }
    final packets = await _backend.runFfprobe(<String>[
      '-v',
      'error',
      '-show_entries',
      'packet=stream_index,pts_time,dts_time,flags',
      '-of',
      'csv=p=0',
      file.path,
    ]);
    if (!packets.succeeded) {
      throw StateError(
        'The reference video timestamps could not be inspected.',
      );
    }
    Object? decoded;
    try {
      decoded = jsonDecode(information.output);
    } on FormatException {
      throw StateError('The reference video information is invalid.');
    }
    if (decoded is! Map<Object?, Object?>) {
      throw StateError('The reference video information is invalid.');
    }
    return _ReferenceVideoProbe.from(
      decoded.map((key, value) => MapEntry(key.toString(), value)),
      packets.output,
      profile: profile,
      fastStart: await _hasFastStart(file),
      requireHighProfile: requireHighProfile,
    );
  }

  Future<void> _encode({
    required File input,
    required File output,
    required _ReferenceVideoProbe probe,
    required ReferenceVideoNormalizationAction action,
    required ReferenceVideoCompatibilityProfile profile,
    ReferenceVideoEncoderAttempt? encoderAttempt,
  }) async {
    final arguments = <String>[
      '-hide_banner',
      '-loglevel',
      'warning',
      '-nostdin',
      '-y',
      '-fflags',
      '+genpts+discardcorrupt',
      '-i',
      input.path,
      '-map',
      '0:v:0',
      if (probe.hasAudio) ...<String>['-map', '0:a:0'],
    ];

    if (action == ReferenceVideoNormalizationAction.transcode) {
      final attempt = encoderAttempt;
      if (attempt == null) {
        throw StateError('No compatible H.264 encoder is configured.');
      }
      arguments.addAll(<String>[
        '-vf',
        probe.videoFilter(profile),
        '-c:v',
        attempt.encoder,
        ..._videoEncoderArguments(attempt.encoder),
        '-profile:v',
        'high',
        if (profile == ReferenceVideoCompatibilityProfile.seedance) ...<String>[
          '-level:v',
          '3.1',
        ],
        '-pix_fmt',
        attempt.inputPixelFormat,
        '-g',
        '${(probe.outputFrameRate * 2).round()}',
        '-bf',
        '0',
        '-tag:v',
        'avc1',
        '-r',
        probe.outputFrameRateArgument,
        '-fps_mode',
        'cfr',
      ]);
    } else {
      arguments.addAll(<String>['-c:v', 'copy']);
    }

    if (probe.hasAudio) {
      if (action == ReferenceVideoNormalizationAction.remux) {
        arguments.addAll(<String>['-c:a', 'copy']);
      } else {
        arguments.addAll(<String>[
          '-af',
          'aresample=48000:async=1:first_pts=0,asetpts=PTS+1024/SR/TB',
          '-c:a',
          'aac',
          '-profile:a',
          'aac_low',
          '-b:a',
          '128k',
          '-ar',
          '48000',
          '-ac',
          '2',
        ]);
      }
    }

    arguments.addAll(<String>[
      '-video_track_timescale',
      profile == ReferenceVideoCompatibilityProfile.seedance
          ? '30000'
          : '90000',
      '-colorspace',
      'bt709',
      '-color_primaries',
      'bt709',
      '-color_trc',
      'bt709',
      '-color_range',
      'tv',
      '-movflags',
      '+faststart',
      '-brand',
      'isom',
      '-avoid_negative_ts',
      'make_zero',
      '-map_metadata',
      '-1',
      '-map_chapters',
      '-1',
      '-sn',
      '-dn',
      '-max_muxing_queue_size',
      '2048',
      '-f',
      'mp4',
      output.path,
    ]);
    final result = await _backend.runFfmpeg(arguments);
    if (!result.succeeded || !await output.exists()) {
      final detail = _lastToolLine(result.output);
      throw StateError(
        detail.isEmpty
            ? 'The reference video could not be repaired.'
            : 'The reference video could not be repaired: $detail',
      );
    }
  }

  Future<void> _transcodeWithFallback({
    required File input,
    required File output,
    required _ReferenceVideoProbe probe,
    required ReferenceVideoCompatibilityProfile profile,
  }) async {
    Object? lastError;
    for (final attempt in _backend.h264EncoderAttempts) {
      var valid = false;
      try {
        if (await output.exists()) await output.delete();
        await _encode(
          input: input,
          output: output,
          probe: probe,
          action: ReferenceVideoNormalizationAction.transcode,
          profile: profile,
          encoderAttempt: attempt,
        );
        // Seedance inputs retain the script's strict High-profile requirement.
        // Hardware encoders may legitimately negotiate Baseline or Main, so
        // generated outputs accept any H.264 profile while retaining the
        // selected profile's other compatibility checks.
        final outputProbe = await _probe(
          output,
          profile: profile,
          requireHighProfile: false,
        );
        if (outputProbe.action == ReferenceVideoNormalizationAction.none) {
          valid = true;
          return;
        }
        lastError = StateError(
          'The repaired reference video did not pass compatibility checks.',
        );
      } on Object catch (error) {
        lastError = error;
      } finally {
        if (!valid && await output.exists()) await output.delete();
      }
    }
    if (lastError != null) throw lastError;
    throw StateError('No compatible H.264 encoder is configured.');
  }

  List<String> _videoEncoderArguments(String encoder) {
    if (encoder == 'libx264') {
      return const <String>[
        '-preset',
        'medium',
        '-crf',
        '18',
        '-x264-params',
        'bframes=0:keyint=60:min-keyint=30:scenecut=40:open-gop=0',
      ];
    }
    if (encoder == 'h264_videotoolbox') {
      return const <String>[
        '-allow_sw',
        '1',
        '-realtime',
        '0',
        '-b:v',
        '6M',
        '-maxrate',
        '8M',
        '-bufsize',
        '12M',
      ];
    }
    return const <String>['-b:v', '6M', '-maxrate', '8M', '-bufsize', '12M'];
  }

  Future<void> _sweepCache(Directory cache, {required File keep}) async {
    final files = <File>[];
    await for (final entity in cache.list()) {
      if (entity is File &&
          (entity.path.endsWith('.mp4') || entity.path.endsWith('.jpg'))) {
        files.add(entity);
      }
    }
    files.sort(
      (left, right) =>
          left.lastModifiedSync().compareTo(right.lastModifiedSync()),
    );
    var total = 0;
    for (final file in files) {
      total += await file.length();
    }
    for (final file in files) {
      if (total <= _maxNormalizationCacheBytes) break;
      if (file.path == keep.path) continue;
      final length = await file.length();
      await file.delete();
      total -= length;
    }
  }
}

class _ReferenceVideoProbe {
  const _ReferenceVideoProbe({
    required this.action,
    required this.canvas,
    required this.genericCanvas,
    required this.framing,
    required this.hasAudio,
    required this.isHdr,
    required this.outputFrameRate,
    required this.outputFrameRateArgument,
  });

  final ReferenceVideoNormalizationAction action;
  final ReferenceVideoCanvas canvas;
  final ReferenceVideoCanvas genericCanvas;
  final ReferenceVideoFraming framing;
  final bool hasAudio;
  final bool isHdr;
  final double outputFrameRate;
  final String outputFrameRateArgument;

  String videoFilter(ReferenceVideoCompatibilityProfile profile) {
    final hdr = isHdr
        ? 'zscale=t=linear:npl=100,format=gbrpf32le,'
              'zscale=p=bt709,tonemap=tonemap=hable:desat=0,'
              'zscale=t=bt709:m=bt709:r=tv,format=yuv420p,'
        : '';
    final seedanceGeometry = framing == ReferenceVideoFraming.fill
        ? 'scale=w=${canvas.width}:h=${canvas.height}:'
              'force_original_aspect_ratio=increase:force_divisible_by=2:'
              'flags=lanczos,crop=${canvas.width}:${canvas.height}:'
              '(iw-ow)/2:(ih-oh)/2'
        : 'scale=w=${canvas.width}:h=${canvas.height}:'
              'force_original_aspect_ratio=decrease:force_divisible_by=2:'
              'flags=lanczos,pad=${canvas.width}:${canvas.height}:'
              '(ow-iw)/2:(oh-ih)/2:color=black';
    final geometry = switch (profile) {
      ReferenceVideoCompatibilityProfile.generic =>
        'scale=w=${genericCanvas.width}:h=${genericCanvas.height}:'
            'force_original_aspect_ratio=decrease:force_divisible_by=2:'
            'flags=lanczos',
      ReferenceVideoCompatibilityProfile.seedance => seedanceGeometry,
    };
    final frameRate = profile == ReferenceVideoCompatibilityProfile.seedance
        ? '30'
        : outputFrameRateArgument;
    return '${hdr}fps=$frameRate,$geometry,setsar=1,'
        'setparams=range=limited:color_primaries=bt709:'
        'color_trc=bt709:colorspace=bt709,setpts=N/($frameRate*TB)';
  }

  factory _ReferenceVideoProbe.from(
    Map<String, Object?> json,
    String packetCsv, {
    required ReferenceVideoCompatibilityProfile profile,
    required bool fastStart,
    bool requireHighProfile = true,
  }) {
    final streams = (json['streams'] as List<Object?>? ?? const <Object?>[])
        .whereType<Map<Object?, Object?>>()
        .map(
          (item) => item.map((key, value) => MapEntry(key.toString(), value)),
        )
        .toList();
    final videos = streams
        .where((item) => item['codec_type'] == 'video')
        .toList();
    if (videos.isEmpty) {
      throw StateError('The selected reference does not contain a video.');
    }
    final video = videos.first;
    final width = (video['width'] as num?)?.toInt() ?? 0;
    final height = (video['height'] as num?)?.toInt() ?? 0;
    if (width <= 0 || height <= 0) {
      throw StateError('The reference video dimensions are invalid.');
    }
    final rotation = _rotation(video);
    final rotated = rotation.abs() == 90 || rotation.abs() == 270;
    final sampleAspectRatio = _ratio(video['sample_aspect_ratio']) ?? 1;
    final unrotatedDisplayWidth = math.max(
      1,
      (width * sampleAspectRatio).round(),
    );
    final displayWidth = rotated ? height : unrotatedDisplayWidth;
    final displayHeight = rotated ? unrotatedDisplayWidth : height;
    final canvas = ReferenceVideoCanvas.forDisplaySize(
      displayWidth,
      displayHeight,
    );
    final genericCanvas = _genericCanvasForDisplaySize(
      displayWidth,
      displayHeight,
    );
    final framing = referenceVideoFraming(
      width: displayWidth,
      height: displayHeight,
      canvas: canvas,
    );
    final audio = streams
        .where((item) => item['codec_type'] == 'audio')
        .toList();
    final unexpectedStreams = streams.any(
      (item) => item['codec_type'] != 'video' && item['codec_type'] != 'audio',
    );
    final packetInfo = _PacketInfo.parse(
      packetCsv,
      videoStreamIndex: (video['index'] as num?)?.toInt() ?? 0,
    );
    final transfer = video['color_transfer']?.toString().toLowerCase() ?? '';
    final isHdr = transfer == 'smpte2084' || transfer == 'arib-std-b67';
    final rFrameRate = _frameRate(video['r_frame_rate']);
    final averageFrameRate = _frameRate(video['avg_frame_rate']);
    final genericFrameRate = averageFrameRate ?? rFrameRate;
    final outputFrameRate = switch (profile) {
      ReferenceVideoCompatibilityProfile.generic => genericFrameRate ?? 30,
      ReferenceVideoCompatibilityProfile.seedance => 30.0,
    };
    final outputFrameRateArgument = switch (profile) {
      ReferenceVideoCompatibilityProfile.generic
          when averageFrameRate != null =>
        video['avg_frame_rate']!.toString(),
      ReferenceVideoCompatibilityProfile.generic when rFrameRate != null =>
        video['r_frame_rate']!.toString(),
      _ => '30',
    };
    final commonExactVideo =
        video['codec_name'] == 'h264' &&
        (!requireHighProfile || _isH264HighProfile(video['profile'])) &&
        video['pix_fmt'] == 'yuv420p' &&
        rotation == 0 &&
        (video['sample_aspect_ratio'] == null ||
            video['sample_aspect_ratio'] == '1:1') &&
        video['codec_tag_string'] == 'avc1' &&
        video['color_space'] == 'bt709' &&
        video['color_primaries'] == 'bt709' &&
        video['color_transfer'] == 'bt709' &&
        (video['color_range'] == 'tv' || video['color_range'] == 'mpeg');
    final level = (video['level'] as num?)?.toInt();
    final exactVideo = switch (profile) {
      ReferenceVideoCompatibilityProfile.generic =>
        commonExactVideo &&
            width == genericCanvas.width &&
            height == genericCanvas.height &&
            rFrameRate != null &&
            averageFrameRate != null &&
            (rFrameRate - averageFrameRate).abs() < .001 &&
            packetInfo.matchesFrameRate(averageFrameRate),
      ReferenceVideoCompatibilityProfile.seedance =>
        commonExactVideo &&
            level == 31 &&
            width == canvas.width &&
            height == canvas.height &&
            _rateIs30(video['r_frame_rate']) &&
            _rateIs30(video['avg_frame_rate']) &&
            (video['has_b_frames'] as num?)?.toInt() == 0 &&
            packetInfo.firstIsKeyframe &&
            packetInfo.matchesFrameRate(30) &&
            packetInfo.maximumKeyframeGap <= 2.05,
    };
    final firstAudio = audio.firstOrNull;
    final exactAudio =
        firstAudio == null ||
        (firstAudio['codec_name'] == 'aac' &&
            _isAacLowComplexityProfile(firstAudio['profile']) &&
            firstAudio['sample_rate']?.toString() == '48000' &&
            (firstAudio['channels'] as num?)?.toInt() == 2);
    final format = json['format'] is Map<Object?, Object?>
        ? (json['format']! as Map<Object?, Object?>).map(
            (key, value) => MapEntry(key.toString(), value),
          )
        : const <String, Object?>{};
    final formatTags = format['tags'] is Map<Object?, Object?>
        ? (format['tags']! as Map<Object?, Object?>).map(
            (key, value) => MapEntry(key.toString(), value),
          )
        : const <String, Object?>{};
    final startTime =
        double.tryParse(video['start_time']?.toString() ?? '') ??
        double.tryParse(format['start_time']?.toString() ?? '') ??
        0;
    final chapters = json['chapters'] as List<Object?>? ?? const <Object?>[];
    final exactContainer =
        format['format_name']?.toString().split(',').contains('mp4') == true &&
        formatTags['major_brand']?.toString().trim() == 'isom' &&
        startTime >= 0 &&
        startTime < .001 &&
        !packetInfo.hasNegativeTimestamp &&
        (profile == ReferenceVideoCompatibilityProfile.generic
            ? _validTimeBase(video['time_base'])
            : video['time_base'] == '1/30000') &&
        videos.length == 1 &&
        audio.length <= 1 &&
        !unexpectedStreams &&
        chapters.isEmpty &&
        fastStart;

    final action = !exactVideo
        ? ReferenceVideoNormalizationAction.transcode
        : !exactAudio
        ? ReferenceVideoNormalizationAction.audio
        : !exactContainer
        ? ReferenceVideoNormalizationAction.remux
        : ReferenceVideoNormalizationAction.none;
    return _ReferenceVideoProbe(
      action: action,
      canvas: canvas,
      genericCanvas: genericCanvas,
      framing: framing,
      hasAudio: firstAudio != null,
      isHdr: isHdr,
      outputFrameRate: outputFrameRate,
      outputFrameRateArgument: outputFrameRateArgument,
    );
  }
}

bool _isH264HighProfile(Object? value) {
  final profile = value?.toString().trim().toLowerCase();
  return profile == 'high' || int.tryParse(profile ?? '') == 100;
}

bool _isAacLowComplexityProfile(Object? value) {
  final profile = value?.toString().trim().toLowerCase();
  return profile == 'lc' || int.tryParse(profile ?? '') == 1;
}

ReferenceVideoCanvas _genericCanvasForDisplaySize(int width, int height) {
  int evenDimension(int value) {
    final positive = math.max(2, value);
    return positive.isEven ? positive : positive - 1;
  }

  return ReferenceVideoCanvas(evenDimension(width), evenDimension(height));
}

double? _ratio(Object? value) {
  final parts = value?.toString().split(':') ?? const <String>[];
  if (parts.length != 2) return null;
  final numerator = double.tryParse(parts[0]);
  final denominator = double.tryParse(parts[1]);
  if (numerator == null || denominator == null || denominator <= 0) return null;
  return numerator / denominator;
}

double? _frameRate(Object? value) {
  final source = value?.toString() ?? '';
  final parts = source.split('/');
  final rate = parts.length == 2
      ? (() {
          final numerator = double.tryParse(parts[0]);
          final denominator = double.tryParse(parts[1]);
          return numerator != null && denominator != null && denominator != 0
              ? numerator / denominator
              : null;
        })()
      : double.tryParse(source);
  return rate != null && rate >= 1 && rate <= 120 ? rate : null;
}

bool _validTimeBase(Object? value) {
  final parts = value?.toString().split('/') ?? const <String>[];
  if (parts.length != 2) return false;
  final numerator = int.tryParse(parts[0]);
  final denominator = int.tryParse(parts[1]);
  return numerator != null &&
      denominator != null &&
      numerator > 0 &&
      denominator > 0;
}

class _PacketInfo {
  const _PacketInfo({
    required this.firstIsKeyframe,
    required this.hasNegativeTimestamp,
    required this.frameDuration,
    required this.hasConstantFrameDuration,
    required this.maximumKeyframeGap,
  });

  final bool firstIsKeyframe;
  final bool hasNegativeTimestamp;
  final double? frameDuration;
  final bool hasConstantFrameDuration;
  final double maximumKeyframeGap;

  bool matchesFrameRate(double frameRate) =>
      hasConstantFrameDuration &&
      frameDuration != null &&
      (frameDuration! - (1 / frameRate)).abs() <= .001;

  factory _PacketInfo.parse(String source, {required int videoStreamIndex}) {
    var firstIsKeyframe = false;
    var hasNegativeTimestamp = false;
    double? previousKeyframe;
    double? previousVideoTimestamp;
    double? lastVideoTimestamp;
    double? frameDuration;
    var maximumKeyframeGap = 0.0;
    var hasConstantFrameDuration = true;
    var sawPacket = false;
    for (final line in const LineSplitter().convert(source)) {
      final fields = line.split(',');
      if (fields.length < 4) continue;
      final streamIndex = int.tryParse(fields[0]);
      final pts = double.tryParse(fields[1]);
      final dts = double.tryParse(fields[2]);
      final flags = fields.sublist(3).join(',');
      if (pts == null && dts == null) continue;
      final timestamp = pts ?? dts!;
      if ((pts != null && pts < 0) || (dts != null && dts < 0)) {
        hasNegativeTimestamp = true;
      }
      if (streamIndex != videoStreamIndex) continue;
      if (!sawPacket) firstIsKeyframe = flags.contains('K');
      sawPacket = true;
      if (previousVideoTimestamp case final previous?) {
        final duration = timestamp - previous;
        frameDuration ??= duration;
        if (duration <= 0 || (duration - frameDuration).abs() > .001) {
          hasConstantFrameDuration = false;
        }
      }
      previousVideoTimestamp = timestamp;
      if (lastVideoTimestamp == null || timestamp > lastVideoTimestamp) {
        lastVideoTimestamp = timestamp;
      }
      if (flags.contains('K')) {
        if (previousKeyframe != null) {
          final gap = timestamp - previousKeyframe;
          if (gap > maximumKeyframeGap) maximumKeyframeGap = gap;
        }
        previousKeyframe = timestamp;
      }
    }
    if (previousKeyframe != null && lastVideoTimestamp != null) {
      final trailingGap = lastVideoTimestamp - previousKeyframe;
      if (trailingGap > maximumKeyframeGap) {
        maximumKeyframeGap = trailingGap;
      }
    }
    return _PacketInfo(
      firstIsKeyframe: sawPacket && firstIsKeyframe,
      hasNegativeTimestamp: hasNegativeTimestamp,
      frameDuration: frameDuration,
      hasConstantFrameDuration: hasConstantFrameDuration,
      maximumKeyframeGap: maximumKeyframeGap,
    );
  }
}

class _MaterializedReferenceVideo {
  const _MaterializedReferenceVideo({required this.file, required this.digest});

  final File file;
  final String digest;
}

class _MaterializedReferenceImage {
  const _MaterializedReferenceImage({
    required this.file,
    required this.bytes,
    required this.digest,
  });

  final File file;
  final Uint8List bytes;
  final String digest;
}

class _SingleValueSink<T> implements Sink<T> {
  T? value;

  @override
  void add(T data) => value = data;

  @override
  void close() {}
}

int _rotation(Map<String, Object?> stream) {
  final tagMap = stream['tags'];
  if (tagMap is Map<Object?, Object?>) {
    final tagged = int.tryParse(tagMap['rotate']?.toString() ?? '');
    if (tagged != null) return tagged;
  }
  for (final item
      in stream['side_data_list'] as List<Object?>? ?? const <Object?>[]) {
    if (item is Map<Object?, Object?>) {
      final rotated = (item['rotation'] as num?)?.round();
      if (rotated != null) return rotated;
    }
  }
  return 0;
}

bool _rateIs30(Object? value) {
  final parts = value?.toString().split('/') ?? const <String>[];
  if (parts.length != 2) return false;
  final numerator = double.tryParse(parts[0]);
  final denominator = double.tryParse(parts[1]);
  return numerator != null &&
      denominator != null &&
      denominator != 0 &&
      (numerator / denominator - 30).abs() < .0001;
}

Future<bool> _hasFastStart(File file) async {
  final handle = await file.open();
  try {
    final length = await handle.length();
    var offset = 0;
    for (var atoms = 0; atoms < 128 && offset + 8 <= length; atoms += 1) {
      await handle.setPosition(offset);
      final header = await handle.read(16);
      if (header.length < 8) return false;
      var size = ByteData.sublistView(
        Uint8List.fromList(header),
        0,
        4,
      ).getUint32(0);
      final type = ascii.decode(header.sublist(4, 8), allowInvalid: true);
      var headerSize = 8;
      if (size == 1) {
        if (header.length < 16) return false;
        size = ByteData.sublistView(
          Uint8List.fromList(header),
          8,
          16,
        ).getUint64(0);
        headerSize = 16;
      } else if (size == 0) {
        size = length - offset;
      }
      if (size < headerSize || offset + size > length) return false;
      if (type == 'moov') return true;
      if (type == 'mdat') return false;
      offset += size;
    }
    return false;
  } finally {
    await handle.close();
  }
}

String _dataUrl(Uint8List bytes) =>
    'data:video/mp4;base64,${base64Encode(bytes)}';

String _imageDataUrl(Uint8List bytes) =>
    'data:image/jpeg;base64,${base64Encode(bytes)}';

bool _imageSourceNeedsInspection(String source) {
  final lower = source.toLowerCase();
  if (lower.startsWith('data:image/') ||
      lower.startsWith('data:application/octet-stream')) {
    return true;
  }
  final uri = Uri.tryParse(source);
  if (uri?.scheme != 'https') return false;
  final path = uri!.path.toLowerCase();
  return const <String>{
    '.heic',
    '.heif',
    '.hif',
    '.avif',
    '.tif',
    '.tiff',
    '.bmp',
    '.dng',
  }.any(path.endsWith);
}

String? _compatibleImageMime(Uint8List bytes) {
  if (_isJpeg(bytes)) return 'image/jpeg';
  if (bytes.length >= 8 &&
      bytes[0] == 0x89 &&
      bytes[1] == 0x50 &&
      bytes[2] == 0x4e &&
      bytes[3] == 0x47 &&
      bytes[4] == 0x0d &&
      bytes[5] == 0x0a &&
      bytes[6] == 0x1a &&
      bytes[7] == 0x0a) {
    return 'image/png';
  }
  if (bytes.length >= 6) {
    final signature = ascii.decode(bytes.sublist(0, 6), allowInvalid: true);
    if (signature == 'GIF87a' || signature == 'GIF89a') return 'image/gif';
  }
  if (bytes.length >= 12 &&
      ascii.decode(bytes.sublist(0, 4), allowInvalid: true) == 'RIFF' &&
      ascii.decode(bytes.sublist(8, 12), allowInvalid: true) == 'WEBP') {
    return 'image/webp';
  }
  return null;
}

bool _isJpeg(List<int> bytes) =>
    bytes.length >= 3 &&
    bytes[0] == 0xff &&
    bytes[1] == 0xd8 &&
    bytes[2] == 0xff;

String _lastToolLine(String output) {
  final lines = const LineSplitter()
      .convert(output)
      .map((line) => line.trim())
      .where((line) => line.isNotEmpty)
      .toList();
  if (lines.isEmpty) return '';
  final value = lines.last;
  return value.length <= 240 ? value : '${value.substring(0, 237)}…';
}
