import 'dart:typed_data';

import 'package:video_thumbnail/video_thumbnail.dart';

Future<Uint8List?> loadVideoFrame(Uri uri, Duration position) async {
  final source = uri.scheme == 'file' ? uri.toFilePath() : uri.toString();
  return VideoThumbnail.thumbnailData(
    video: source,
    imageFormat: ImageFormat.JPEG,
    maxWidth: 180,
    timeMs: position.inMilliseconds,
    quality: 68,
  );
}
