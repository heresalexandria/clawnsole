import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

/// Extracts a seekable thumbnail using the system FFmpeg on native Linux.
/// Neither of the mobile/Windows thumbnail plugins implements Linux.
class FfmpegVideoFrameLoader {
  const FfmpegVideoFrameLoader({
    this.executable = 'ffmpeg',
    this.timeout = const Duration(seconds: 15),
  });

  final String executable;
  final Duration timeout;

  Future<Uint8List?> load(
    Uri uri,
    Duration position, {
    int maxWidth = 180,
  }) async {
    if (!const {'file', 'http', 'https'}.contains(uri.scheme)) return null;
    final width = maxWidth.clamp(1, 2048);
    final seconds = math.max(0, position.inMicroseconds) / 1000000;
    Process? process;
    try {
      final source = uri.scheme == 'file' ? uri.toFilePath() : uri.toString();
      process = await Process.start(executable, <String>[
        '-nostdin',
        '-hide_banner',
        '-loglevel',
        'error',
        '-ss',
        seconds.toStringAsFixed(6),
        '-i',
        source,
        '-frames:v',
        '1',
        '-an',
        '-vf',
        'scale=$width:$width:force_original_aspect_ratio=decrease',
        '-threads',
        '1',
        '-c:v',
        'mjpeg',
        '-q:v',
        '5',
        '-f',
        'image2pipe',
        'pipe:1',
      ]);
      final running = process;
      final bytes = BytesBuilder(copy: false);
      var exceededLimit = false;
      final output = running.stdout.forEach((chunk) {
        if (exceededLimit) return;
        if (bytes.length + chunk.length > 4 * 1024 * 1024) {
          exceededLimit = true;
          running.kill(ProcessSignal.sigkill);
          return;
        }
        bytes.add(chunk);
      });
      // Consume both pipes while waiting, without retaining FFmpeg diagnostics
      // or credential-bearing source URLs in thumbnail errors.
      final completion = Future.wait<Object?>([
        running.exitCode,
        output,
        running.stderr.drain<void>(),
      ]);
      final result = await completion.timeout(timeout);
      if (result.first != 0 || exceededLimit || bytes.isEmpty) return null;
      return bytes.takeBytes();
    } on Object {
      return null;
    } finally {
      process?.kill(ProcessSignal.sigkill);
    }
  }
}
