import 'dart:async';

import 'package:clawnsole/ui/media_duration_loader.dart';
import 'package:clawnsole/ui/video_probe.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:video_player_platform_interface/video_player_platform_interface.dart';

void main() {
  final binding = _ProbeBinding();
  testWidgets('failed platform creation does not wedge duration work', (
    tester,
  ) async {
    final previous = VideoPlayerPlatform.instance;
    VideoPlayerPlatform.instance = _UnavailablePlayer();
    addTearDown(() => VideoPlayerPlatform.instance = previous);
    var completed = false;
    double? duration;
    final observersBefore = binding.observers.length;
    loadMediaDuration(Uri.parse('https://media.test/audio.mp3')).then((value) {
      completed = true;
      duration = value;
    });
    await tester.pump();
    expect(completed, isTrue);
    expect(duration, isNull);
    expect(binding.observers.length, observersBefore);
    expect(tester.takeException(), isNull);
  });

  test(
    'timed out probe keeps its slot until native disposal finishes',
    () async {
      final previous = VideoPlayerPlatform.instance;
      final player = _DelayedPlayer();
      VideoPlayerPlatform.instance = player;
      addTearDown(() => VideoPlayerPlatform.instance = previous);
      var completed = false;
      final observersBefore = binding.observers.length;
      final operation = readVideoProbe<int>(
        Uri.parse('https://media.test/delayed.mp4'),
        (_) => 1,
        timeout: const Duration(milliseconds: 10),
      ).then((_) => completed = true);
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(completed, isFalse);
      player.created.complete(1);
      await player.disposeStarted.future.timeout(const Duration(seconds: 2));
      expect(player.disposals, 1);
      expect(completed, isFalse);
      player.disposed.complete();
      await operation;
      expect(completed, isTrue);
      expect(binding.observers.length, observersBefore);
    },
  );

  testWidgets('late creation failure releases a timed out probe', (
    tester,
  ) async {
    final previous = VideoPlayerPlatform.instance;
    final player = _DelayedPlayer();
    VideoPlayerPlatform.instance = player;
    addTearDown(() => VideoPlayerPlatform.instance = previous);
    var completed = false;
    final observersBefore = binding.observers.length;
    readVideoProbe<int>(
      Uri.parse('https://media.test/failed.mp4'),
      (_) => 1,
      timeout: const Duration(milliseconds: 10),
    ).then((_) => completed = true);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 20));
    expect(completed, isFalse);
    player.created.completeError(StateError('creation failed'));
    await tester.pump();
    expect(completed, isTrue);
    expect(binding.observers.length, observersBefore);
    expect(tester.takeException(), isNull);
  });
}

class _UnavailablePlayer extends VideoPlayerPlatform {
  @override
  Future<void> init() async {}

  @override
  Future<void> setMixWithOthers(bool mixWithOthers) async {}

  @override
  Future<int?> createWithOptions(VideoCreationOptions options) async =>
      throw StateError('Media backend unavailable');
}

class _DelayedPlayer extends _UnavailablePlayer {
  final created = Completer<int?>();
  final disposed = Completer<void>();
  final disposeStarted = Completer<void>();
  int disposals = 0;

  @override
  Future<int?> createWithOptions(VideoCreationOptions options) =>
      created.future;

  @override
  Stream<VideoEvent> videoEventsFor(int playerId) => const Stream.empty();

  @override
  Future<void> dispose(int playerId) {
    disposals++;
    disposeStarted.complete();
    return disposed.future;
  }
}

class _ProbeBinding extends AutomatedTestWidgetsFlutterBinding {
  final observers = <WidgetsBindingObserver>{};

  @override
  void addObserver(WidgetsBindingObserver observer) {
    observers.add(observer);
    super.addObserver(observer);
  }

  @override
  bool removeObserver(WidgetsBindingObserver observer) {
    observers.remove(observer);
    return super.removeObserver(observer);
  }
}
