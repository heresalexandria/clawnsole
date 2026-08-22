import 'dart:io';

import 'package:reference_video_tools/reference_video_tools.dart';

import 'reference_video_normalizer.dart';

ReferenceVideoToolBackend nativeReferenceVideoToolBackend() {
  if (Platform.isWindows) {
    final directory = Directory(
      '${File(Platform.resolvedExecutable).parent.path}'
      '${Platform.pathSeparator}media-tools',
    );
    return ProcessReferenceVideoToolBackend(
      ffmpegPath: '${directory.path}${Platform.pathSeparator}ffmpeg.exe',
      ffprobePath: '${directory.path}${Platform.pathSeparator}ffprobe.exe',
      h264EncoderAttempts: referenceVideoEncoderAttemptsForPlatform('windows'),
    );
  }
  return const MobileReferenceVideoToolBackend();
}

List<ReferenceVideoEncoderAttempt> referenceVideoEncoderAttemptsForPlatform(
  String operatingSystem,
) => switch (operatingSystem) {
  'ios' => const <ReferenceVideoEncoderAttempt>[
    ReferenceVideoEncoderAttempt(encoder: 'h264_videotoolbox'),
  ],
  'android' => const <ReferenceVideoEncoderAttempt>[
    ReferenceVideoEncoderAttempt(encoder: 'h264_mediacodec'),
    ReferenceVideoEncoderAttempt(
      encoder: 'h264_mediacodec',
      inputPixelFormat: 'nv12',
    ),
  ],
  'windows' => const <ReferenceVideoEncoderAttempt>[
    ReferenceVideoEncoderAttempt(encoder: 'h264_mf'),
    ReferenceVideoEncoderAttempt(encoder: 'libopenh264'),
  ],
  _ => throw UnsupportedError(
    'Reference video repair is not available on $operatingSystem.',
  ),
};

class MobileReferenceVideoToolBackend implements ReferenceVideoToolBackend {
  const MobileReferenceVideoToolBackend();

  @override
  List<ReferenceVideoEncoderAttempt> get h264EncoderAttempts =>
      referenceVideoEncoderAttemptsForPlatform(Platform.operatingSystem);

  @override
  Future<ReferenceVideoToolResult> runFfmpeg(List<String> arguments) async {
    final result = await ReferenceVideoTools.execute(arguments, probe: false);
    return ReferenceVideoToolResult(
      exitCode: result.exitCode,
      output: result.output,
    );
  }

  @override
  Future<ReferenceVideoToolResult> runFfprobe(List<String> arguments) async {
    final result = await ReferenceVideoTools.execute(arguments, probe: true);
    return ReferenceVideoToolResult(
      exitCode: result.exitCode,
      output: result.output,
    );
  }
}
