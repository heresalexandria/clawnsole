import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'motion_clock.dart';
import 'motion_isolate.dart';

/// A determinate-looking bar for work that has a trustworthy duration estimate
/// but no byte or stage progress signal.
///
/// It advances to 90% over [expectedDuration] and waits there until the owning
/// future replaces it. Loading surfaces pair it with a spinner, so overdue work
/// never looks frozen and the bar never falsely announces completion.
///
/// The bar advances on a [MotionClock] — at most 24 updates a second, and
/// none while the app is inactive, the route is covered, or the bar is
/// scrolled out of view — rather than on a vsync ticker that would ask the
/// engine for a frame every 8 ms for the whole load. It sits in a
/// [MotionIsolate], so give it a parent that fixes its width.
class EstimatedProgressBar extends StatefulWidget {
  const EstimatedProgressBar({
    required this.expectedDuration,
    required this.startedAt,
    super.key,
    this.color,
    this.backgroundColor,
    this.minHeight = 3,
  });

  final Duration expectedDuration;
  final DateTime startedAt;
  final Color? color;
  final Color? backgroundColor;
  final double minHeight;

  @override
  State<EstimatedProgressBar> createState() => _EstimatedProgressBarState();
}

class _EstimatedProgressBarState extends State<EstimatedProgressBar> {
  static const double _waitingPoint = .9;

  // The bar has nothing left to animate once it reaches the waiting point,
  // so the tick that paints that frame also parks the clock.
  late final MotionClock _clock = MotionClock(
    onTick: (_) {
      if (_value >= _waitingPoint) _clock.suspend();
    },
  );
  Duration _elapsedAtAttach = Duration.zero;
  Duration _clockAtAttach = Duration.zero;

  @override
  void initState() {
    super.initState();
    _restart();
  }

  @override
  void didUpdateWidget(covariant EstimatedProgressBar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.expectedDuration != widget.expectedDuration ||
        oldWidget.startedAt != widget.startedAt) {
      _restart();
      _syncClock();
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _syncClock();
  }

  /// Work that is already overdue never starts the pacer: its pinned value
  /// is painted by the ordinary build.
  void _syncClock() {
    if (_value >= _waitingPoint) {
      _clock.suspend();
    } else {
      _clock.attach(context);
    }
  }

  @override
  void dispose() {
    _clock.dispose();
    super.dispose();
  }

  void _restart() {
    _elapsedAtAttach = DateTime.now().difference(widget.startedAt);
    _clockAtAttach = _clock.elapsed;
  }

  /// How far along the work is: the wall clock in the app, the animation
  /// clock in a test where wall time stands still — whichever is further.
  double get _value {
    final expectedMicros = widget.expectedDuration.inMicroseconds;
    if (expectedMicros <= 0) return _waitingPoint;
    final wall = DateTime.now().difference(widget.startedAt);
    final ticked = _elapsedAtAttach + (_clock.elapsed - _clockAtAttach);
    final elapsed = wall > ticked ? wall : ticked;
    final fraction =
        elapsed.inMicroseconds.clamp(0, expectedMicros) / expectedMicros;
    return math.min(_waitingPoint, fraction * _waitingPoint);
  }

  @override
  Widget build(BuildContext context) => MotionIsolate(
    height: widget.minHeight,
    child: ValueListenableBuilder<int>(
      valueListenable: _clock.frame,
      builder: (context, _, _) {
        final value = _value;
        return LinearProgressIndicator(
          value: value,
          color: widget.color,
          backgroundColor: widget.backgroundColor,
          minHeight: widget.minHeight,
          borderRadius: BorderRadius.circular(99),
          semanticsLabel: 'Estimated loading progress',
          semanticsValue: '${(value * 100).round()}%',
        );
      },
    ),
  );
}
