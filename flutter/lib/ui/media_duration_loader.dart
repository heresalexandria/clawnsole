import 'video_probe.dart';

typedef MediaDurationLoader = Future<double?> Function(Uri uri);

/// Reads duration through the platform media backend, including audio-only
/// files supported by the registered native or web video_player plugin.
Future<double?> loadMediaDuration(Uri uri) => readVideoProbe(uri, (value) {
  final seconds =
      value.duration.inMicroseconds / Duration.microsecondsPerSecond;
  return seconds.isFinite && seconds > 0 ? seconds : null;
});
