import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../app/app_theme.dart';
import 'video_frame_loader.dart';

class VideoFrameTimeline extends StatefulWidget {
  const VideoFrameTimeline({
    required this.uri,
    required this.duration,
    required this.position,
    required this.fullscreen,
    required this.frameLoader,
    required this.onSeek,
    required this.onInteract,
    super.key,
  });

  final Uri uri;
  final Duration duration;
  final Duration position;
  final bool fullscreen;
  final VideoFrameLoader frameLoader;
  final ValueChanged<double> onSeek;
  final VoidCallback onInteract;

  @override
  State<VideoFrameTimeline> createState() => _VideoFrameTimelineState();
}

class _VideoFrameTimelineState extends State<VideoFrameTimeline> {
  late List<Duration> _positions;
  late List<Uint8List?> _frames;
  late List<bool> _attempted;
  int _loadToken = 0;

  int get _frameCount => widget.fullscreen ? 10 : 6;

  @override
  void initState() {
    super.initState();
    _resetFrames();
  }

  @override
  void didUpdateWidget(covariant VideoFrameTimeline oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.uri != widget.uri ||
        oldWidget.duration != widget.duration ||
        oldWidget.fullscreen != widget.fullscreen) {
      _resetFrames();
    }
  }

  void _resetFrames() {
    final token = ++_loadToken;
    _positions = videoTimelinePositions(widget.duration, _frameCount);
    _frames = List<Uint8List?>.filled(_positions.length, null);
    _attempted = List<bool>.filled(_positions.length, false);
    unawaited(_loadFrames(token));
  }

  Future<void> _loadFrames(int token) async {
    for (var index = 0; index < _positions.length; index += 1) {
      Uint8List? frame;
      try {
        frame = await widget.frameLoader(widget.uri, _positions[index]);
      } on Object {
        frame = null;
      }
      if (!mounted || token != _loadToken) return;
      setState(() {
        _frames[index] = frame;
        _attempted[index] = true;
      });
    }
  }

  void _seek(double localX, double width) {
    if (width <= 0) return;
    widget.onInteract();
    widget.onSeek((localX / width).clamp(0.0, 1.0));
  }

  @override
  void dispose() {
    _loadToken += 1;
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final durationMicros = widget.duration.inMicroseconds;
    final fraction = durationMicros <= 0
        ? 0.0
        : (widget.position.inMicroseconds / durationMicros).clamp(0.0, 1.0);
    final height = widget.fullscreen ? 68.0 : 46.0;

    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        final playhead = math.max(
          0.0,
          math.min(width - 2, width * fraction - 1),
        );
        return Semantics(
          slider: true,
          label: 'Video timeline',
          value:
              '${formatVideoTime(widget.position)} of '
              '${formatVideoTime(widget.duration)}',
          increasedValue: formatVideoTime(
            _positionAtFraction(
              widget.duration,
              (fraction + .05).clamp(0.0, 1.0),
            ),
          ),
          decreasedValue: formatVideoTime(
            _positionAtFraction(
              widget.duration,
              (fraction - .05).clamp(0.0, 1.0),
            ),
          ),
          onIncrease: () => widget.onSeek((fraction + .05).clamp(0.0, 1.0)),
          onDecrease: () => widget.onSeek((fraction - .05).clamp(0.0, 1.0)),
          child: MouseRegion(
            cursor: SystemMouseCursors.click,
            child: GestureDetector(
              key: const ValueKey('video-frame-timeline'),
              behavior: HitTestBehavior.opaque,
              onTapDown: (details) => _seek(details.localPosition.dx, width),
              onHorizontalDragStart: (details) =>
                  _seek(details.localPosition.dx, width),
              onHorizontalDragUpdate: (details) =>
                  _seek(details.localPosition.dx, width),
              child: SizedBox(
                height: height,
                child: Stack(
                  clipBehavior: Clip.hardEdge,
                  children: <Widget>[
                    Positioned.fill(
                      child: Row(
                        children: List<Widget>.generate(
                          _positions.length,
                          (index) => Expanded(
                            child: Padding(
                              padding: EdgeInsets.only(
                                right: index == _positions.length - 1 ? 0 : 1,
                              ),
                              child: _TimelineFrame(
                                bytes: _frames[index],
                                attempted: _attempted[index],
                                position: _positions[index],
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                    Positioned(
                      left: playhead,
                      top: 0,
                      bottom: 0,
                      child: Container(
                        key: const ValueKey('video-timeline-playhead'),
                        width: 2,
                        color: context.colors.tertiary,
                      ),
                    ),
                    Positioned(
                      left: math.max(0, math.min(width - 16, playhead - 7)),
                      top: -5,
                      child: Icon(
                        Icons.arrow_drop_down_rounded,
                        size: 16,
                        color: context.colors.tertiary,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

class _TimelineFrame extends StatelessWidget {
  const _TimelineFrame({
    required this.bytes,
    required this.attempted,
    required this.position,
  });

  final Uint8List? bytes;
  final bool attempted;
  final Duration position;

  @override
  Widget build(BuildContext context) => ColoredBox(
    color: ClawnsoleColors.plumInk,
    child: Stack(
      fit: StackFit.expand,
      children: <Widget>[
        if (bytes != null)
          Image.memory(bytes!, fit: BoxFit.cover, gaplessPlayback: true)
        else if (!attempted)
          const Center(
            child: SizedBox.square(
              dimension: 11,
              child: CircularProgressIndicator(
                strokeWidth: 1.4,
                color: Colors.white38,
              ),
            ),
          )
        else
          const Icon(
            Icons.movie_filter_outlined,
            size: 15,
            color: Colors.white30,
          ),
        Positioned(
          left: 3,
          bottom: 2,
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: .62),
              borderRadius: BorderRadius.circular(3),
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 3, vertical: 1),
              child: Text(
                formatVideoTime(position),
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 7,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ),
        ),
      ],
    ),
  );
}

List<Duration> videoTimelinePositions(Duration duration, int frameCount) {
  if (frameCount <= 0) return const <Duration>[];
  if (frameCount == 1 || duration <= Duration.zero) {
    return List<Duration>.filled(frameCount, Duration.zero);
  }
  final lastMicrosecond = math.max(0, duration.inMicroseconds - 40000);
  return List<Duration>.generate(
    frameCount,
    (index) => Duration(
      microseconds: (lastMicrosecond * index / (frameCount - 1)).round(),
    ),
  );
}

String formatVideoTime(Duration duration) {
  final totalSeconds = math.max(0, duration.inSeconds);
  final hours = totalSeconds ~/ 3600;
  final minutes = (totalSeconds % 3600) ~/ 60;
  final seconds = totalSeconds % 60;
  if (hours > 0) {
    return '$hours:${minutes.toString().padLeft(2, '0')}:'
        '${seconds.toString().padLeft(2, '0')}';
  }
  return '${minutes.toString().padLeft(2, '0')}:'
      '${seconds.toString().padLeft(2, '0')}';
}

Duration _positionAtFraction(Duration duration, double fraction) =>
    Duration(microseconds: (duration.inMicroseconds * fraction).round());
