import 'dart:async';

import 'package:clawnsole/ui/video_frame_loader.dart';
import 'package:flutter_test/flutter_test.dart';

Future<void> testExecutable(FutureOr<void> Function() testMain) async {
  setUp(() {
    // UI tests use placeholder thumbnails unless they inject a frame loader.
    // Linux's FFmpeg subprocess creates real I/O and timers that cannot finish
    // in a widget test's fake async zone. The core FFmpeg integration tests
    // instantiate their loader directly and still exercise the real decoder.
    debugVideoFrameLoaderOverride =
        (uri, position, {int maxWidth = 180}) async => null;
  });
  await testMain();
}
