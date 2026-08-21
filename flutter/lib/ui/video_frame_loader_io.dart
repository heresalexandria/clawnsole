import 'dart:io';
import 'dart:typed_data';

import 'package:fc_native_video_thumbnail/fc_native_video_thumbnail.dart';
import 'package:video_thumbnail/video_thumbnail.dart';

Future<Uint8List?> loadVideoFrame(Uri uri, Duration position) async {
  if (Platform.isWindows) return _loadWindowsVideoFrame(uri);
  final source = uri.scheme == 'file' ? uri.toFilePath() : uri.toString();
  return VideoThumbnail.thumbnailData(
    video: source,
    imageFormat: ImageFormat.JPEG,
    maxWidth: 180,
    timeMs: position.inMilliseconds,
    quality: 68,
  );
}

/// video_thumbnail ships no Windows implementation. The shell thumbnail API
/// behind fc_native_video_thumbnail reads local files only and cannot seek,
/// so every requested position receives the same representative frame.
Future<Uint8List?> _loadWindowsVideoFrame(Uri uri) async {
  if (uri.scheme != 'file') return null;
  try {
    return await FcNativeVideoThumbnail().saveThumbnailToBytes(
      srcFile: uri.toFilePath(),
      width: 256,
      height: 256,
      quality: 68,
    );
  } on Object {
    return null;
  }
}
