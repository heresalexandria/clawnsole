import 'dart:async';
import 'dart:convert';
import 'dart:js_interop';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:web/web.dart' as web;

Future<Uint8List?> loadVideoFrame(
  Uri uri,
  Duration position, {
  int maxWidth = 180,
}) async {
  final video = web.HTMLVideoElement()
    ..crossOrigin = 'anonymous'
    ..muted = true
    ..preload = 'auto';

  try {
    final metadata = _waitForEvent(video, 'loadedmetadata');
    video.src = uri.toString();
    video.load();
    await metadata;

    final duration = video.duration.isFinite ? video.duration : 0.0;
    final requested = position.inMicroseconds / Duration.microsecondsPerSecond;
    final target = math.max(
      0.0,
      math.min(requested, math.max(0, duration - .04)),
    );
    if (target > .001) {
      final sought = _waitForEvent(video, 'seeked');
      video.currentTime = target;
      await sought;
    } else if (video.readyState < 2) {
      await _waitForEvent(video, 'loadeddata');
    }

    if (video.videoWidth == 0 || video.videoHeight == 0) return null;
    final width = math.min(math.max(1, maxWidth), video.videoWidth);
    final height = math.max(
      1,
      (width * video.videoHeight / video.videoWidth).round(),
    );
    final canvas = web.HTMLCanvasElement()
      ..width = width
      ..height = height;
    final context = canvas.getContext('2d') as web.CanvasRenderingContext2D?;
    if (context == null) return null;
    context.drawImage(video, 0, 0, width, height);

    final dataUrl = canvas.toDataURL('image/jpeg', .72.toJS);
    final separator = dataUrl.indexOf(',');
    if (separator < 0) return null;
    return base64Decode(dataUrl.substring(separator + 1));
  } on Object {
    // Cross-origin videos can remain playable while disallowing canvas reads.
    // The timeline displays a graceful placeholder for those frames.
    return null;
  } finally {
    video
      ..removeAttribute('src')
      ..load();
  }
}

Future<void> _waitForEvent(web.EventTarget target, String eventName) {
  final completer = Completer<void>();
  late web.EventListener success;
  late web.EventListener failure;

  void cleanUp() {
    target
      ..removeEventListener(eventName, success)
      ..removeEventListener('error', failure);
  }

  success = ((web.Event _) {
    if (completer.isCompleted) return;
    cleanUp();
    completer.complete();
  }).toJS;
  failure = ((web.Event _) {
    if (completer.isCompleted) return;
    cleanUp();
    completer.completeError(StateError('Unable to read video frame.'));
  }).toJS;

  target
    ..addEventListener(eventName, success)
    ..addEventListener('error', failure);
  return completer.future.timeout(
    const Duration(seconds: 12),
    onTimeout: () {
      cleanUp();
      throw TimeoutException('Timed out while reading a video frame.');
    },
  );
}
