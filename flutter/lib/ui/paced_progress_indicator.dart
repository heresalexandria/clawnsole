import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'motion_clock.dart';

// Material's progress indicators, redrawn to Material's own geometry, but
// paced by a [MotionClock] instead of a vsync ticker.
//
// The stock widgets rebuild themselves on every vsync for as long as they are
// indeterminate — a card that renders for twenty minutes keeps the engine
// producing 120 frames a second the whole time, and a rebuild under a
// LayoutBuilder dirties the layout above it as well. These paint the same
// arcs and bars (the `year2023` Material 3 look the studio's theme uses:
// square caps on the ring, no track gap on the bar) from a painter that only
// repaints when the clock ticks, at most 24 times a second, and not at all
// while the app is inactive, the route is covered, the indicator is scrolled
// away, or motion is held still by policy. Held still, they show one
// recognisable frame rather than a dot.

/// Where in Material's cycle a held-still indicator sits: far enough in for
/// a visible arc or bar.
const double _restingPhase = .25;

/// Material's `Curves.fastOutSlowIn`.
const Curve _fastOutSlowIn = Cubic(0.4, 0.0, 0.2, 1.0);

/// The indeterminate ring, as Material draws it: a sweep whose head and tail
/// chase each other every 1333 ms while the whole thing turns every 2222 ms.
class PacedCircularProgressIndicator extends StatefulWidget {
  const PacedCircularProgressIndicator({
    super.key,
    this.color,
    this.strokeWidth = 4,
    this.semanticsLabel,
  });

  final Color? color;
  final double strokeWidth;
  final String? semanticsLabel;

  /// Material's arc for [elapsed] into the animation, as (start, sweep).
  @visibleForTesting
  static (double, double) arcAt(Duration elapsed) {
    final ms = elapsed.inMicroseconds / 1000;
    final saw = (ms / 1333) % 1;
    final rotation = (ms / 2222) % 1;
    return _arc(saw, rotation);
  }

  static (double, double) _arc(double saw, double rotation) {
    final head = const Interval(0, .5, curve: _fastOutSlowIn).transform(saw);
    final tail = const Interval(.5, 1, curve: _fastOutSlowIn).transform(saw);
    final start =
        -math.pi / 2 +
        tail * 3 / 2 * math.pi +
        rotation * math.pi * 2 +
        saw * .5 * math.pi;
    final sweep = math.max(
      head * 3 / 2 * math.pi - tail * 3 / 2 * math.pi,
      .001,
    );
    return (start, sweep);
  }

  @override
  State<PacedCircularProgressIndicator> createState() =>
      _PacedCircularProgressIndicatorState();
}

class _PacedCircularProgressIndicatorState
    extends State<PacedCircularProgressIndicator> {
  // Progress is state, not decoration: it keeps turning under reduce motion
  // and stops only for the renderer's memory brake.
  final MotionClock _clock = MotionClock(essential: true);

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _clock.attach(context);
  }

  @override
  void dispose() {
    _clock.dispose();
    super.dispose();
  }

  (double, double) _arc() {
    if (_clock.isStatic) {
      return PacedCircularProgressIndicator._arc(_restingPhase, 0);
    }
    return PacedCircularProgressIndicator.arcAt(_clock.elapsed);
  }

  @override
  Widget build(BuildContext context) {
    final color =
        widget.color ??
        ProgressIndicatorTheme.of(context).color ??
        Theme.of(context).colorScheme.primary;
    Widget ring = RepaintBoundary(
      child: ConstrainedBox(
        constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
        child: CustomPaint(
          painter: _PacedRingPainter(
            frame: _clock.frame,
            arc: _arc,
            color: color,
            strokeWidth: widget.strokeWidth,
          ),
        ),
      ),
    );
    if (widget.semanticsLabel != null) {
      ring = Semantics(label: widget.semanticsLabel, child: ring);
    }
    return ring;
  }
}

class _PacedRingPainter extends CustomPainter {
  _PacedRingPainter({
    required this.frame,
    required this.arc,
    required this.color,
    required this.strokeWidth,
  }) : super(repaint: frame);

  final ValueListenable<int> frame;
  final (double, double) Function() arc;
  final Color color;
  final double strokeWidth;

  @override
  void paint(Canvas canvas, Size size) {
    final (start, sweep) = arc();
    canvas.drawArc(
      Offset.zero & size,
      start,
      sweep,
      false,
      Paint()
        ..color = color
        ..strokeWidth = strokeWidth
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.square,
    );
  }

  @override
  bool shouldRepaint(_PacedRingPainter oldDelegate) =>
      oldDelegate.frame != frame ||
      oldDelegate.color != color ||
      oldDelegate.strokeWidth != strokeWidth;
}

/// Material's linear indicator: determinate with [value], or two chasing
/// bars on an 1800 ms cycle without it.
class PacedLinearProgressIndicator extends StatefulWidget {
  const PacedLinearProgressIndicator({
    super.key,
    this.value,
    this.color,
    this.backgroundColor,
    this.minHeight = 4,
    this.borderRadius,
    this.semanticsLabel,
    this.semanticsValue,
  });

  final double? value;
  final Color? color;
  final Color? backgroundColor;
  final double minHeight;
  final BorderRadiusGeometry? borderRadius;
  final String? semanticsLabel;
  final String? semanticsValue;

  static const Curve _line1Head = Interval(
    0,
    750 / 1800,
    curve: Cubic(0.2, 0.0, 0.8, 1.0),
  );
  static const Curve _line1Tail = Interval(
    333 / 1800,
    (333 + 750) / 1800,
    curve: Cubic(0.4, 0.0, 1.0, 1.0),
  );
  static const Curve _line2Head = Interval(
    1000 / 1800,
    (1000 + 567) / 1800,
    curve: Cubic(0.0, 0.0, 0.65, 1.0),
  );
  static const Curve _line2Tail = Interval(
    1267 / 1800,
    (1267 + 533) / 1800,
    curve: Cubic(0.10, 0.0, 0.45, 1.0),
  );

  /// Material's cycle position for [elapsed] into the animation, 0 to 1.
  @visibleForTesting
  static double phaseAt(Duration elapsed) =>
      (elapsed.inMicroseconds / 1000 / 1800) % 1;

  @override
  State<PacedLinearProgressIndicator> createState() =>
      _PacedLinearProgressIndicatorState();
}

class _PacedLinearProgressIndicatorState
    extends State<PacedLinearProgressIndicator> {
  final MotionClock _clock = MotionClock(essential: true);

  /// A determinate bar has nothing to animate: the clock runs only while the
  /// value is unknown.
  void _syncClock() {
    if (widget.value == null) {
      _clock.attach(context);
    } else {
      _clock.suspend();
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _syncClock();
  }

  @override
  void didUpdateWidget(covariant PacedLinearProgressIndicator oldWidget) {
    super.didUpdateWidget(oldWidget);
    if ((oldWidget.value == null) != (widget.value == null)) _syncClock();
  }

  @override
  void dispose() {
    _clock.dispose();
    super.dispose();
  }

  double _phase() => _clock.isStatic
      ? _restingPhase
      : PacedLinearProgressIndicator.phaseAt(_clock.elapsed);

  @override
  Widget build(BuildContext context) {
    final theme = ProgressIndicatorTheme.of(context);
    final scheme = Theme.of(context).colorScheme;
    final color = widget.color ?? theme.color ?? scheme.primary;
    final track =
        widget.backgroundColor ??
        theme.linearTrackColor ??
        scheme.surfaceContainerHighest;
    final radius = widget.borderRadius?.resolve(Directionality.of(context));
    Widget bar = ConstrainedBox(
      constraints: BoxConstraints(
        minWidth: double.infinity,
        minHeight: widget.minHeight,
      ),
      child: CustomPaint(
        painter: _PacedBarPainter(
          frame: widget.value == null ? _clock.frame : null,
          phase: _phase,
          isStatic: () => _clock.isStatic,
          value: widget.value,
          color: color,
          track: track,
          textDirection: Directionality.of(context),
          borderRadius: radius,
        ),
      ),
    );
    if (radius != null && widget.value == null) {
      bar = ClipRRect(borderRadius: radius, child: bar);
    }
    bar = RepaintBoundary(child: bar);
    // As Material does: a determinate bar announces its percentage unless
    // the caller supplied a value; an indeterminate one contributes nothing.
    final determinate = widget.value;
    return Semantics(
      label: widget.semanticsLabel,
      value:
          widget.semanticsValue ??
          (determinate == null
              ? null
              : '${(clampDouble(determinate, 0, 1) * 100).round()}%'),
      child: bar,
    );
  }
}

class _PacedBarPainter extends CustomPainter {
  _PacedBarPainter({
    required this.frame,
    required this.phase,
    required this.isStatic,
    required this.value,
    required this.color,
    required this.track,
    required this.textDirection,
    required this.borderRadius,
  }) : super(repaint: frame);

  /// The clock's frames while indeterminate; null once the bar has a value.
  final ValueListenable<int>? frame;
  final double Function() phase;

  /// True while the memory brake holds the bar still. The still frame is a
  /// whole track tinted with the accent, which cannot be read as a value.
  final bool Function() isStatic;
  final double? value;
  final Color color;
  final Color track;
  final TextDirection textDirection;
  final BorderRadius? borderRadius;

  void _segment(Canvas canvas, Size size, double start, double end, Color c) {
    if (end - start <= 0) return;
    final ltr = textDirection == TextDirection.ltr;
    final left = (ltr ? start : 1 - end) * size.width;
    final right = (ltr ? end : 1 - start) * size.width;
    final rect = Rect.fromLTRB(left, 0, right, size.height);
    final paint = Paint()..color = c;
    final radius = borderRadius;
    if (radius != null) {
      canvas.drawRRect(radius.toRRect(rect), paint);
    } else {
      canvas.drawRect(rect, paint);
    }
  }

  @override
  void paint(Canvas canvas, Size size) {
    final determinate = value;
    if (determinate != null) {
      final clamped = clampDouble(determinate, 0, 1);
      _segment(canvas, size, 0, 1, track);
      if (clamped > 0) _segment(canvas, size, 0, clamped, color);
      return;
    }
    if (isStatic()) {
      _segment(canvas, size, 0, 1, track);
      _segment(canvas, size, 0, 1, color.withValues(alpha: .38));
      return;
    }
    final t = phase();
    final firstHead = PacedLinearProgressIndicator._line1Head.transform(t);
    final firstTail = PacedLinearProgressIndicator._line1Tail.transform(t);
    final secondHead = PacedLinearProgressIndicator._line2Head.transform(t);
    final secondTail = PacedLinearProgressIndicator._line2Tail.transform(t);
    if (firstHead < 1) _segment(canvas, size, firstHead, 1, track);
    if (firstHead - firstTail > 0) {
      _segment(canvas, size, firstTail, firstHead, color);
    }
    if (firstTail > 0) _segment(canvas, size, secondHead, firstTail, track);
    if (secondHead - secondTail > 0) {
      _segment(canvas, size, secondTail, secondHead, color);
    }
    if (secondTail > 0) _segment(canvas, size, 0, secondTail, track);
  }

  @override
  bool shouldRepaint(_PacedBarPainter oldDelegate) =>
      oldDelegate.frame != frame ||
      oldDelegate.value != value ||
      oldDelegate.color != color ||
      oldDelegate.track != track ||
      oldDelegate.textDirection != textDirection ||
      oldDelegate.borderRadius != borderRadius;
}
