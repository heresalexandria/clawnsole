import 'dart:async';

import 'package:clawnsole/app/app_controller.dart';
import 'package:clawnsole/ui/generation_video.dart';
import 'package:clawnsole/ui/video_frame_timeline.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:video_player_platform_interface/video_player_platform_interface.dart';

void main() {
  late VideoPlayerPlatform originalPlatform;
  late _FakeVideoPlayerPlatform videoPlatform;

  setUp(() {
    originalPlatform = VideoPlayerPlatform.instance;
    videoPlatform = _FakeVideoPlayerPlatform();
    VideoPlayerPlatform.instance = videoPlatform;
  });

  tearDown(() {
    VideoPlayerPlatform.instance = originalPlatform;
  });

  test('timeline positions span the playable duration', () {
    final positions = videoTimelinePositions(const Duration(seconds: 10), 6);

    expect(positions, hasLength(6));
    expect(positions.first, Duration.zero);
    expect(positions.last, const Duration(milliseconds: 9960));
    expect(positions[3], const Duration(milliseconds: 5976));
  });

  testWidgets('tap and Space toggle playback while the timeline scrubs', (
    tester,
  ) async {
    await tester.pumpWidget(_testApp());
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('video-frame-timeline')), findsOneWidget);
    final playsBeforeTap = videoPlatform.calls
        .where((call) => call == 'play')
        .length;
    await tester.tap(find.byKey(const ValueKey('video-play-surface')));
    await tester.pump();
    expect(
      videoPlatform.calls.where((call) => call == 'play').length,
      playsBeforeTap + 1,
    );

    final pausesBeforeSpace = videoPlatform.calls
        .where((call) => call == 'pause')
        .length;
    await tester.sendKeyEvent(LogicalKeyboardKey.space);
    await tester.pump();
    expect(
      videoPlatform.calls.where((call) => call == 'pause').length,
      pausesBeforeSpace + 1,
    );

    final playsBeforeSpace = videoPlatform.calls
        .where((call) => call == 'play')
        .length;
    await tester.sendKeyEvent(LogicalKeyboardKey.space);
    await tester.pump();
    expect(
      videoPlatform.calls.where((call) => call == 'play').length,
      playsBeforeSpace + 1,
    );

    final timeline = tester.getRect(
      find.byKey(const ValueKey('video-frame-timeline')),
    );
    await tester.tapAt(
      Offset(timeline.left + timeline.width * .75, timeline.center.dy),
    );
    await tester.pump();
    expect(videoPlatform.seekPositions.last.inMilliseconds, closeTo(7500, 20));

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
  });

  testWidgets('Escape exits the fullscreen video player', (tester) async {
    await tester.pumpWidget(_testApp());
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Enter fullscreen'));
    await tester.pumpAndSettle();
    expect(find.byTooltip('Exit fullscreen (Esc)'), findsOneWidget);

    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(find.byTooltip('Enter fullscreen'), findsOneWidget);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
  });

  testWidgets('download offers Photos first and returns that destination', (
    tester,
  ) async {
    VideoSaveDestination? destination;
    await tester.pumpWidget(
      _testApp(
        supportsPhotos: true,
        onDownload: (value) async => destination = value,
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Download video…'));
    await tester.pumpAndSettle();

    expect(find.text('Save to Photos'), findsOneWidget);
    expect(find.text('Add the video to your camera roll'), findsOneWidget);
    expect(find.text('Save to Files'), findsOneWidget);
    expect(
      tester.getTopLeft(find.text('Save to Photos')).dy,
      lessThan(tester.getTopLeft(find.text('Save to Files')).dy),
    );

    await tester.tap(find.text('Save to Photos'));
    await tester.pumpAndSettle();
    expect(destination, VideoSaveDestination.photos);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
  });
}

Widget _testApp({
  bool supportsPhotos = false,
  Future<void> Function(VideoSaveDestination)? onDownload,
}) => MaterialApp(
  home: Scaffold(
    body: SizedBox(
      width: 640,
      height: 360,
      child: GenerationVideo(
        uri: Uri.parse('https://example.com/test.mp4'),
        onDownload: onDownload ?? (_) async {},
        supportsPhotos: supportsPhotos,
        frameLoader: (_, _) async => null,
      ),
    ),
  ),
);

class _FakeVideoPlayerPlatform extends VideoPlayerPlatform {
  final List<String> calls = <String>[];
  final List<Duration> seekPositions = <Duration>[];
  final Map<int, StreamController<VideoEvent>> _events =
      <int, StreamController<VideoEvent>>{};
  final Map<int, Duration> _positions = <int, Duration>{};
  int _nextPlayerId = 0;

  @override
  Future<void> init() async {
    calls.add('init');
  }

  @override
  Future<int?> createWithOptions(VideoCreationOptions options) async {
    calls.add('create');
    final id = _nextPlayerId++;
    final events = StreamController<VideoEvent>();
    _events[id] = events;
    events.add(
      VideoEvent(
        eventType: VideoEventType.initialized,
        size: const Size(1920, 1080),
        duration: const Duration(seconds: 10),
      ),
    );
    return id;
  }

  @override
  Stream<VideoEvent> videoEventsFor(int playerId) => _events[playerId]!.stream;

  @override
  Future<void> dispose(int playerId) async {
    calls.add('dispose');
    await _events.remove(playerId)?.close();
  }

  @override
  Future<void> play(int playerId) async {
    calls.add('play');
  }

  @override
  Future<void> pause(int playerId) async {
    calls.add('pause');
  }

  @override
  Future<Duration> getPosition(int playerId) async =>
      _positions[playerId] ?? Duration.zero;

  @override
  Future<void> seekTo(int playerId, Duration position) async {
    calls.add('seekTo');
    seekPositions.add(position);
    _positions[playerId] = position;
  }

  @override
  Future<void> setLooping(int playerId, bool looping) async {
    calls.add('setLooping');
  }

  @override
  Future<void> setVolume(int playerId, double volume) async {
    calls.add('setVolume');
  }

  @override
  Future<void> setPlaybackSpeed(int playerId, double speed) async {
    calls.add('setPlaybackSpeed');
  }

  @override
  Future<void> setMixWithOthers(bool mixWithOthers) async {
    calls.add('setMixWithOthers');
  }

  @override
  Widget buildViewWithOptions(VideoViewOptions options) =>
      ColoredBox(key: ValueKey<int>(options.playerId), color: Colors.black);
}
