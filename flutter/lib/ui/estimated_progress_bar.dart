import 'package:flutter/material.dart';

/// A determinate-looking bar for work that has a trustworthy duration estimate
/// but no byte or stage progress signal.
///
/// It advances to 90% over [expectedDuration] and waits there until the owning
/// future replaces it. Loading surfaces pair it with a spinner, so overdue work
/// never looks frozen and the bar never falsely announces completion.
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

class _EstimatedProgressBarState extends State<EstimatedProgressBar>
    with SingleTickerProviderStateMixin {
  static const double _waitingPoint = .9;

  late final AnimationController _progress = AnimationController(vsync: this);

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
    }
  }

  void _restart() {
    _progress.stop();
    final expectedMicros = widget.expectedDuration.inMicroseconds;
    if (expectedMicros <= 0) {
      _progress.value = _waitingPoint;
      return;
    }
    final elapsed = DateTime.now().difference(widget.startedAt);
    final elapsedFraction =
        elapsed.inMicroseconds.clamp(0, expectedMicros) / expectedMicros;
    _progress.value = elapsedFraction * _waitingPoint;
    final remaining = widget.expectedDuration - elapsed;
    if (remaining > Duration.zero) {
      _progress.animateTo(
        _waitingPoint,
        duration: remaining,
        curve: Curves.linear,
      );
    }
  }

  @override
  void dispose() {
    _progress.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: _progress,
    builder: (context, _) => LinearProgressIndicator(
      value: _progress.value,
      color: widget.color,
      backgroundColor: widget.backgroundColor,
      minHeight: widget.minHeight,
      borderRadius: BorderRadius.circular(99),
      semanticsLabel: 'Estimated loading progress',
      semanticsValue: '${(_progress.value * 100).round()}%',
    ),
  );
}
