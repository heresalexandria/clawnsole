import 'dart:typed_data';

import 'video_frame_loader_io.dart'
    if (dart.library.html) 'video_frame_loader_web.dart'
    as platform;

typedef VideoFrameLoader =
    Future<Uint8List?> Function(Uri uri, Duration position);

/// A frame loader that can also be asked for a wider frame than the card
/// filmstrip needs. [loadVideoFrame] satisfies this and [VideoFrameLoader],
/// so timeline callers keep the shorter signature.
typedef SizedVideoFrameLoader =
    Future<Uint8List?> Function(Uri uri, Duration position, {int maxWidth});

/// Reads one JPEG frame at [position], scaled so the image is at most
/// [maxWidth] wide. The default matches the filmstrip thumbnails; callers
/// that hand frames to a model ask for more detail than that.
Future<Uint8List?> loadVideoFrame(
  Uri uri,
  Duration position, {
  int maxWidth = 180,
}) => platform.loadVideoFrame(uri, position, maxWidth: maxWidth);
