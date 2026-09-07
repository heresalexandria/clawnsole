import 'dart:async';

import 'package:video_player/video_player.dart';

import 'video_controller.dart';

/// Reads metadata from a player that never plays. Its lifecycle observer is
/// unnecessary and, when platform creation fails, video_player cannot dispose
/// that observer because its internal creation completer never completes.
Future<T?> readVideoProbe<T>(
  Uri uri,
  T? Function(VideoPlayerValue value) read, {
  Duration timeout = const Duration(seconds: 15),
}) async {
  final controller = createVideoController(
    uri,
    videoPlayerOptions: VideoPlayerOptions(allowBackgroundPlayback: true),
  );
  final failed = Completer<void>();
  final initializing = controller.initialize().catchError((
    Object error,
    StackTrace stack,
  ) {
    failed.complete();
    Error.throwWithStackTrace(error, stack);
  });
  try {
    await initializing.timeout(timeout);
    return read(controller.value);
  } on Object {
    return null;
  } finally {
    // A timeout does not cancel native creation: retain the decoder slot
    // until disposal finishes. Only a confirmed initialization failure may
    // release it while dispose awaits the plugin's broken create completer.
    try {
      await Future.any<void>([controller.dispose(), failed.future]);
    } on Object {
      // Backend cleanup is best effort, like metadata extraction itself.
    }
  }
}
