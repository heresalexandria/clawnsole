import 'dart:typed_data';

import '../app/app_controller.dart';
import '../core/models.dart';
import '../core/prompt_rewrite.dart';
import 'media_duration_loader.dart';
import 'video_frame_loader.dart';
import 'video_frame_timeline.dart';
import 'video_metadata_loader.dart';

/// Samples evenly spaced frames of a delivered film so AI Rewrite can show
/// the model what the prompt actually produced.
///
/// This never throws and never blocks the dialog: a film with no cheap source,
/// an unreadable container, or a platform that cannot seek simply yields
/// fewer frames (possibly none) and the rewrite goes out as text.
Future<List<RewriteFrame>> sampleGenerationFrames(
  AppController controller,
  Generation item, {
  int count = 8,
  int maxWidth = 640,
  SizedVideoFrameLoader? frameLoader,
  VideoMetadataLoader? metadataLoader,
  MediaDurationLoader? durationLoader,
}) async {
  if (count <= 0) return const <RewriteFrame>[];
  final uri = await _sourceUri(controller, item);
  if (uri == null) return const <RewriteFrame>[];

  final seconds = await _durationSeconds(
    uri,
    item,
    metadataLoader: metadataLoader ?? loadVideoMetadata,
    durationLoader: durationLoader ?? loadMediaDuration,
  );
  final duration = Duration(
    milliseconds: (seconds.clamp(0.2, 600.0) * 1000).round(),
  );
  final positions = videoTimelinePositions(duration, count);

  final load = frameLoader ?? loadVideoFrame;
  final frames = <RewriteFrame>[];
  final seen = <String>{};
  for (final position in positions) {
    Uint8List? bytes;
    try {
      bytes = await load(uri, position, maxWidth: maxWidth);
    } on Object {
      bytes = null;
    }
    if (bytes == null || bytes.isEmpty) continue;
    // Windows answers every position with the same representative frame;
    // sending eight copies of it would only spend tokens.
    if (!seen.add(_fingerprint(bytes))) continue;
    frames.add(
      RewriteFrame(
        bytes: bytes,
        seconds: position.inMicroseconds / Duration.microsecondsPerSecond,
      ),
    );
  }
  return frames;
}

Future<Uri?> _sourceUri(AppController controller, Generation item) async {
  try {
    final cheap = await controller.generationPreviewSourceUri(item);
    if (cheap != null) return cheap;
  } on Object {
    // Fall through to the full delivery below.
  }
  try {
    return await controller.generationMediaDelivery(item).uri;
  } on Object {
    return null;
  }
}

Future<double> _durationSeconds(
  Uri uri,
  Generation item, {
  required VideoMetadataLoader metadataLoader,
  required MediaDurationLoader durationLoader,
}) async {
  try {
    final metadata = await metadataLoader(uri);
    if (metadata != null && metadata.durationSeconds > 0) {
      return metadata.durationSeconds;
    }
  } on Object {
    // A container the metadata reader cannot open still has a configured
    // duration, and failing that a player that can measure it.
  }
  final configured = item.config.duration;
  if (configured is num && configured > 0) return configured.toDouble();
  try {
    final measured = await durationLoader(uri);
    if (measured != null && measured > 0) return measured;
  } on Object {
    // Nothing left to ask; fall back to a plausible film length so the
    // sampler still spreads its requests instead of stacking them at zero.
  }
  return 8;
}

/// Cheap content identity for de-duplication: length plus a sparse sample,
/// which separates real frames without hashing megabytes of JPEG.
String _fingerprint(Uint8List bytes) {
  final buffer = StringBuffer()..write(bytes.length);
  final step = bytes.length <= 64 ? 1 : bytes.length ~/ 64;
  for (var index = 0; index < bytes.length; index += step) {
    buffer
      ..write(':')
      ..write(bytes[index]);
  }
  return buffer.toString();
}
