import 'dart:io';

import 'package:video_player/video_player.dart';

VideoPlayerController createVideoController(Uri uri) => uri.scheme == 'file'
    ? VideoPlayerController.file(File(uri.toFilePath()))
    : VideoPlayerController.networkUrl(uri);
