import 'dart:io';

import 'package:video_player/video_player.dart';

VideoPlayerController createVideoController(
  Uri uri, {
  VideoPlayerOptions? videoPlayerOptions,
}) => uri.scheme == 'file'
    ? VideoPlayerController.file(
        File(uri.toFilePath()),
        videoPlayerOptions: videoPlayerOptions,
      )
    : VideoPlayerController.networkUrl(
        uri,
        videoPlayerOptions: videoPlayerOptions,
      );
