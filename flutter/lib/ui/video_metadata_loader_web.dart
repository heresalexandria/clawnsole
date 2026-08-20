import 'dart:async';
import 'dart:js_interop';

import 'package:web/web.dart' as web;

import '../core/models.dart';

Future<VideoSourceMetadata?> loadVideoMetadata(Uri uri) async {
  final video = web.HTMLVideoElement()
    ..muted = true
    ..preload = 'metadata';
  try {
    final metadataLoaded = _waitForEvent(video, 'loadedmetadata');
    video.src = uri.toString();
    video.load();
    await metadataLoaded;
    final metadata = VideoSourceMetadata(
      width: video.videoWidth,
      height: video.videoHeight,
      durationSeconds: video.duration,
    );
    return metadata.durationSeconds.isFinite && metadata.isUsable
        ? metadata
        : null;
  } on Object {
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
    completer.completeError(StateError('Unable to read video metadata.'));
  }).toJS;

  target
    ..addEventListener(eventName, success)
    ..addEventListener('error', failure);
  return completer.future.timeout(
    const Duration(seconds: 12),
    onTimeout: () {
      cleanUp();
      throw TimeoutException('Timed out while reading video metadata.');
    },
  );
}
