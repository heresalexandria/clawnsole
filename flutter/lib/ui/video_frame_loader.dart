import 'dart:typed_data';

import 'video_frame_loader_io.dart'
    if (dart.library.html) 'video_frame_loader_web.dart'
    as platform;

typedef VideoFrameLoader =
    Future<Uint8List?> Function(Uri uri, Duration position);

Future<Uint8List?> loadVideoFrame(Uri uri, Duration position) =>
    platform.loadVideoFrame(uri, position);
