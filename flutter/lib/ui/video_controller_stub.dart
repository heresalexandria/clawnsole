import 'package:video_player/video_player.dart';

VideoPlayerController createVideoController(Uri uri) =>
    VideoPlayerController.networkUrl(uri);
