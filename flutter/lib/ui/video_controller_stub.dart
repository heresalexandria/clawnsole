import 'package:video_player/video_player.dart';

VideoPlayerController createVideoController(
  Uri uri, {
  VideoPlayerOptions? videoPlayerOptions,
}) => VideoPlayerController.networkUrl(
  uri,
  videoPlayerOptions: videoPlayerOptions,
);
