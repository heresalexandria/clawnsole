import 'dart:io';
import 'dart:ui' as ui;

import 'package:clawnsole/core/ffmpeg_video_frame_loader.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('unsupported thumbnail URIs do not start a process', () async {
    const loader = FfmpegVideoFrameLoader(executable: '/missing/ffmpeg');
    expect(
      await loader.load(Uri.parse('data:video/mp4,abc'), Duration.zero),
      isNull,
    );
  });

  test('missing system FFmpeg leaves the thumbnail unavailable', () async {
    const loader = FfmpegVideoFrameLoader(executable: '/missing/ffmpeg');
    expect(
      await loader.load(Uri.file('/missing/video.mp4'), Duration.zero),
      isNull,
    );
    expect(
      await loader.load(
        Uri.parse('file:///video.mp4?invalid=1'),
        Duration.zero,
      ),
      isNull,
    );
  });

  final mediaTools = Platform.environment['CLAWNSOLE_TEST_MEDIA_TOOLS_DIR'];
  test(
    'system FFmpeg seeks, sizes and rejects unreadable clips',
    () async {
      final temporary = await Directory.systemTemp.createTemp(
        'clawnsole-frames-',
      );
      addTearDown(() => temporary.delete(recursive: true));
      final ffmpeg = '$mediaTools${Platform.pathSeparator}ffmpeg';
      final source = File('${temporary.path}/two colors.mov');
      final generated = await Process.run(ffmpeg, [
        '-hide_banner',
        '-loglevel',
        'error',
        '-f',
        'lavfi',
        '-i',
        'color=c=red:s=320x180:r=10:d=1',
        '-f',
        'lavfi',
        '-i',
        'color=c=blue:s=320x180:r=10:d=1',
        '-filter_complex',
        '[0:v][1:v]concat=n=2:v=1:a=0',
        '-c:v',
        'mpeg4',
        source.path,
      ]);
      expect(generated.exitCode, 0, reason: '${generated.stderr}');

      final loader = FfmpegVideoFrameLoader(executable: ffmpeg);
      for (final sample in [(500, true), (1500, false)]) {
        final bytes = await loader.load(
          source.uri,
          Duration(milliseconds: sample.$1),
          maxWidth: 160,
        );
        expect(bytes, isNotNull);
        final codec = await ui.instantiateImageCodec(bytes!);
        final image = (await codec.getNextFrame()).image;
        expect(image.width, 160);
        expect(image.height, 90);
        final pixel = await image.toByteData(
          format: ui.ImageByteFormat.rawRgba,
        );
        expect(pixel, isNotNull);
        final red = pixel!.getUint8(0);
        final blue = pixel.getUint8(2);
        expect(sample.$2 ? red : blue, greaterThan(200));
        expect(sample.$2 ? blue : red, lessThan(40));
        image.dispose();
        codec.dispose();
      }
      expect(
        await loader.load(
          File('${temporary.path}/missing.mov').uri,
          Duration.zero,
        ),
        isNull,
      );
    },
    skip: mediaTools == null || mediaTools.isEmpty
        ? 'Set CLAWNSOLE_TEST_MEDIA_TOOLS_DIR to exercise installed FFmpeg.'
        : false,
  );

  test(
    'a stalled HTTP thumbnail stops at the process timeout',
    () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(() => server.close(force: true));
      // Keep accepted requests open to exercise a decoder waiting on network
      // bytes. The timeout must kill it and return control to the library.
      server.listen((_) {});
      final loader = FfmpegVideoFrameLoader(
        executable: '$mediaTools${Platform.pathSeparator}ffmpeg',
        timeout: const Duration(milliseconds: 400),
      );
      final elapsed = Stopwatch()..start();
      expect(
        await loader
            .load(
              Uri.parse('http://127.0.0.1:${server.port}/stalled.mp4'),
              Duration.zero,
            )
            .timeout(const Duration(seconds: 5)),
        isNull,
      );
      expect(elapsed.elapsed, lessThan(const Duration(seconds: 3)));
    },
    skip: mediaTools == null || mediaTools.isEmpty
        ? 'Set CLAWNSOLE_TEST_MEDIA_TOOLS_DIR to exercise installed FFmpeg.'
        : false,
  );
}
