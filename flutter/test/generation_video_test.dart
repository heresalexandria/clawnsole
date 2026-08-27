import 'dart:async';

import 'package:clawnsole/app/app_controller.dart';
import 'package:clawnsole/ui/generation_video.dart';
import 'package:clawnsole/ui/inline_video.dart';
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
    expect(
      find.byKey(const ValueKey('video-pointer-interceptor')),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('video-play-surface')),
        matching: find.byKey(const ValueKey('video-platform-view')),
      ),
      findsNothing,
      reason: 'the click target must stay in front of the platform video view',
    );
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

  testWidgets('Space plays immediately and arrow keys seek', (tester) async {
    await tester.pumpWidget(_testApp());
    await tester.pumpAndSettle();

    final playsBefore = videoPlatform.calls
        .where((call) => call == 'play')
        .length;
    await tester.sendKeyEvent(LogicalKeyboardKey.space);
    await tester.pump();
    expect(
      videoPlatform.calls.where((call) => call == 'play').length,
      playsBefore + 1,
      reason: 'the player takes focus on its own, so Space works right away',
    );

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pump();
    expect(videoPlatform.seekPositions.last.inMilliseconds, 1000);

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pump();
    expect(videoPlatform.seekPositions.last.inMilliseconds, 2000);

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
    await tester.pump();
    expect(videoPlatform.seekPositions.last.inMilliseconds, 1000);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
  });

  testWidgets('Escape closes a modal player through onClose', (tester) async {
    var closed = 0;
    await tester.pumpWidget(_testApp(onClose: () => closed += 1));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('video-close-button')), findsOneWidget);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pump();
    expect(closed, 1);

    await tester.tap(find.byKey(const ValueKey('video-close-button')));
    await tester.pump();
    expect(closed, 2);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
  });

  testWidgets('wide viewports get an aspect-sized modal, not a takeover', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1280, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(_modalLauncherApp());
    await tester.pumpAndSettle();

    await tester.tap(find.text('Play'));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('video-player-modal')), findsOneWidget);
    final frame = find.byKey(const ValueKey('video-modal-frame'));
    final size = tester.getSize(frame);
    expect(size.width, lessThan(1280));
    expect(size.height, lessThan(800));
    // 1920x1080 media: the video area above the chrome keeps 16:9.
    expect(
      size.width / (size.height - GenerationVideo.chromeHeight),
      closeTo(16 / 9, .05),
    );

    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('video-player-modal')), findsNothing);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
  });

  testWidgets('narrow viewports play fullscreen with a close control', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(_modalLauncherApp());
    await tester.pumpAndSettle();

    await tester.tap(find.text('Play'));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('video-player-modal')), findsNothing);
    final overlay = find.byKey(const ValueKey('video-close-overlay'));
    expect(overlay, findsOneWidget);
    // The standalone fullscreen player closes; it has no separate
    // fullscreen toggle.
    expect(find.byIcon(Icons.fullscreen_exit_rounded), findsNothing);

    await tester.tap(overlay);
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('video-play-surface')), findsNothing);

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

  testWidgets('loading shows an animated loader with determinate progress', (
    tester,
  ) async {
    videoPlatform.holdInitialization = true;
    final progress = ValueNotifier<double?>(null);
    addTearDown(progress.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 640,
            height: 360,
            child: GenerationVideo(
              uri: Uri.parse('https://example.com/test.mp4'),
              onDownload: (_) async {},
              frameLoader: (_, _) async => null,
              progress: progress,
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    expect(find.text('Loading film'), findsOneWidget);
    final bar = find.byKey(const ValueKey('video-loading-progress'));
    expect(tester.widget<LinearProgressIndicator>(bar).value, isNull);

    // The hourglass keeps moving while nothing else changes.
    final hourglass = find
        .ancestor(
          of: find.byIcon(Icons.hourglass_bottom_rounded),
          matching: find.byType(RotationTransition),
        )
        .first;
    final turnsBefore = tester
        .widget<RotationTransition>(hourglass)
        .turns
        .value;
    await tester.pump(const Duration(milliseconds: 200));
    final turnsAfter = tester.widget<RotationTransition>(hourglass).turns.value;
    expect(turnsAfter, isNot(turnsBefore));

    // Byte progress switches the bar to determinate with a percent label.
    progress.value = .42;
    await tester.pump();
    expect(tester.widget<LinearProgressIndicator>(bar).value, .42);
    expect(find.text('42%'), findsOneWidget);

    progress.value = 1;
    await tester.pump();
    expect(find.text('100%'), findsNothing);
    expect(find.text('Preparing film'), findsOneWidget);
    expect(tester.widget<LinearProgressIndicator>(bar).value, isNull);

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

  testWidgets('inline play swaps in an embedded player Escape collapses', (
    tester,
  ) async {
    final registry = InlineVideoRegistry();
    addTearDown(registry.dispose);
    await tester.pumpWidget(_inlineHostApp(registry));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('inline-preview-a')), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('inline-play-a')));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('inline-video-a')), findsOneWidget);
    expect(find.byKey(const ValueKey('inline-preview-a')), findsNothing);
    expect(find.byKey(const ValueKey('video-play-surface')), findsOneWidget);
    expect(registry.value, 'a');

    // The embedded player must not steal keyboard focus from the page.
    final callsBeforeSpace = videoPlatform.calls.length;
    await tester.sendKeyEvent(LogicalKeyboardKey.space);
    await tester.pump();
    expect(videoPlatform.calls.length, callsBeforeSpace);

    // Interacting with the player focuses it; Escape then collapses the
    // card back to its preview.
    await tester.tap(find.byKey(const ValueKey('video-play-surface')));
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('video-play-surface')), findsNothing);
    expect(find.byKey(const ValueKey('inline-preview-a')), findsOneWidget);
    expect(registry.value, isNull);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
  });

  testWidgets('starting another card collapses the first inline player', (
    tester,
  ) async {
    final registry = InlineVideoRegistry();
    addTearDown(registry.dispose);
    await tester.pumpWidget(
      _inlineHostApp(registry, ids: const <String>['a', 'b']),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('inline-play-a')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('inline-video-a')), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('inline-play-b')));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('inline-video-b')), findsOneWidget);
    expect(find.byKey(const ValueKey('inline-video-a')), findsNothing);
    expect(find.byKey(const ValueKey('inline-preview-a')), findsOneWidget);
    expect(find.byType(GenerationVideo), findsOneWidget);
    expect(registry.value, 'b');

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
  });

  testWidgets('inline players reach the shared fullscreen route and back', (
    tester,
  ) async {
    final registry = InlineVideoRegistry();
    addTearDown(registry.dispose);
    await tester.pumpWidget(_inlineHostApp(registry));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('inline-play-a')));
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Enter fullscreen'));
    await tester.pumpAndSettle();
    expect(find.byTooltip('Exit fullscreen (Esc)'), findsOneWidget);

    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();

    expect(find.byTooltip('Enter fullscreen'), findsOneWidget);
    expect(find.byKey(const ValueKey('inline-video-a')), findsOneWidget);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
  });

  testWidgets('the media box keeps stored ratios and caps portrait films', (
    tester,
  ) async {
    final registry = InlineVideoRegistry();
    addTearDown(registry.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: InlineVideoRegistryScope(
            registry: registry,
            child: ListView(
              children: <Widget>[
                Center(
                  child: SizedBox(
                    width: 400,
                    child: InlineVideoMediaBox(
                      key: const ValueKey('inline-box-landscape'),
                      playbackId: 'landscape',
                      aspectRatio: 16 / 9,
                      preview: const ColoredBox(color: Colors.black),
                    ),
                  ),
                ),
                Center(
                  child: SizedBox(
                    width: 400,
                    child: InlineVideoMediaBox(
                      key: const ValueKey('inline-box-portrait'),
                      playbackId: 'portrait',
                      aspectRatio: 9 / 16,
                      preview: const ColoredBox(
                        key: ValueKey('inline-preview-portrait'),
                        color: Colors.black,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    final landscape = tester.getSize(
      find.byKey(const ValueKey('inline-box-landscape')),
    );
    expect(landscape.width, 400);
    expect(landscape.width / landscape.height, closeTo(16 / 9, .01));

    // The default test viewport is 800×600: a 9:16 film would want 711px of
    // height, so the box caps at 70% of the viewport with the whole frame
    // still visible, centered on the dark media surface.
    final portrait = tester.getSize(
      find.byKey(const ValueKey('inline-box-portrait')),
    );
    expect(portrait.height, closeTo(420, .1));
    final film = tester.getSize(
      find.byKey(const ValueKey('inline-preview-portrait')),
    );
    expect(film.width / film.height, closeTo(9 / 16, .01));
    expect(film.height, closeTo(420, .1));
  });
}

Widget _inlineHostApp(
  InlineVideoRegistry registry, {
  List<String> ids = const <String>['a'],
}) => MaterialApp(
  home: Scaffold(
    body: InlineVideoRegistryScope(
      registry: registry,
      child: ListView(
        children: ids
            .map(
              (id) => Center(
                child: SizedBox(
                  width: 320,
                  child: InlineVideoMediaBox(
                    playbackId: id,
                    aspectRatio: 16 / 9,
                    preview: Builder(
                      builder: (context) => ColoredBox(
                        key: ValueKey('inline-preview-$id'),
                        color: Colors.black,
                        child: Center(
                          child: TextButton(
                            key: ValueKey('inline-play-$id'),
                            onPressed: () =>
                                InlineVideoPlayback.of(context)?.call(
                                  InlineVideoRequest(
                                    uri: Uri.parse(
                                      'https://example.com/$id.mp4',
                                    ),
                                    onDownload: (_) async {},
                                    frameLoader: (_, _) async => null,
                                  ),
                                ),
                            child: const Text('Start inline'),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            )
            .toList(),
      ),
    ),
  ),
);

Widget _testApp({
  bool supportsPhotos = false,
  Future<void> Function(VideoSaveDestination)? onDownload,
  VoidCallback? onClose,
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
        onClose: onClose,
      ),
    ),
  ),
);

Widget _modalLauncherApp() => MaterialApp(
  home: Scaffold(
    body: Builder(
      builder: (context) => Center(
        child: TextButton(
          onPressed: () => unawaited(
            showVideoPlayerModal(
              context,
              uri: Uri.parse('https://example.com/test.mp4'),
              onDownload: (_) async {},
              frameLoader: (_, _) async => null,
            ),
          ),
          child: const Text('Play'),
        ),
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

  /// When set, players never report initialization, keeping the loading
  /// placeholder on screen for tests that exercise it.
  bool holdInitialization = false;

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
    if (!holdInitialization) {
      events.add(
        VideoEvent(
          eventType: VideoEventType.initialized,
          size: const Size(1920, 1080),
          duration: const Duration(seconds: 10),
        ),
      );
    }
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
