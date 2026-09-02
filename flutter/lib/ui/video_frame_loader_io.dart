import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:fc_native_video_thumbnail/fc_native_video_thumbnail.dart';
import 'package:video_thumbnail/video_thumbnail.dart';

Future<Uint8List?> loadVideoFrame(
  Uri uri,
  Duration position, {
  int maxWidth = 180,
}) async {
  if (Platform.isWindows) return _loadWindowsVideoFrame(uri, maxWidth);
  final source = uri.scheme == 'file' ? uri.toFilePath() : uri.toString();
  return VideoThumbnail.thumbnailData(
    video: source,
    imageFormat: ImageFormat.JPEG,
    maxWidth: math.max(1, maxWidth),
    timeMs: position.inMilliseconds,
    quality: 68,
  );
}

/// video_thumbnail ships no Windows implementation. The shell thumbnail API
/// behind fc_native_video_thumbnail reads local files only and cannot seek,
/// so every requested position receives the same representative frame.
Future<Uint8List?> _loadWindowsVideoFrame(Uri uri, int maxWidth) async {
  if (uri.scheme != 'file') return null;
  // The shell reads into a square bounding box; 256 has always been the
  // floor here so the one representative frame stays legible.
  final edge = math.max(256, maxWidth);
  try {
    return await FcNativeVideoThumbnail().saveThumbnailToBytes(
      srcFile: uri.toFilePath(),
      width: edge,
      height: edge,
      quality: 68,
    );
  } on Object {
    return null;
  }
}
