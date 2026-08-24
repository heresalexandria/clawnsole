import 'dart:async';

import 'video_controller.dart';

typedef MediaDurationLoader = Future<double?> Function(Uri uri);

/// Reads duration through the platform media backend, including audio-only
/// files supported by the registered native or web video_player plugin.
Future<double?> loadMediaDuration(Uri uri) async {
  final controller = createVideoController(uri);
  try {
    await controller.initialize().timeout(const Duration(seconds: 15));
    final seconds =
        controller.value.duration.inMicroseconds /
        Duration.microsecondsPerSecond;
    return seconds.isFinite && seconds > 0 ? seconds : null;
  } on Object {
    return null;
  } finally {
    await controller.dispose();
  }
}
