import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'motion_clock.dart';

/// The desktop affordance for a newer release.
///
/// Its glow drifts on a [MotionClock]: 24 frames a second at most, and none
/// while the window is inactive, a modal covers the bar, or the person asked
/// for reduced motion. The moving gradient is painted directly, released
/// after every frame, and recorded in its own picture, so a chip that sits in
/// the top bar for hours never re-records the bar around it and never piles
/// up native shaders. The soft shadow beneath it is painted once, at the
/// midpoint of the glow's two hues, because a blurred shadow repainted
/// continuously is a native allocation the web engine never frees.
class UpdateAvailableChip extends StatefulWidget {
  const UpdateAvailableChip({
    required this.onPressed,
    required this.installable,
    super.key,
    this.version,
  });

  final VoidCallback onPressed;
  final bool installable;
  final String? version;

  @override
  State<UpdateAvailableChip> createState() => _UpdateAvailableChipState();
}

class _UpdateAvailableChipState extends State<UpdateAvailableChip> {
  static const Duration _period = Duration(seconds: 6);

  final MotionClock _clock = MotionClock();

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

  /// The glow's place in its six-second drift, 0 to 1. Starts a little way
  /// in so the first frame is not the gradient's dead centre.
  double _cycle() {
    if (_clock.isStatic) return .12;
    final micros = _clock.elapsed.inMicroseconds % _period.inMicroseconds;
    return (.12 + micros / _period.inMicroseconds) % 1;
  }

  @override
  Widget build(BuildContext context) {
    final version = widget.version;
    return Semantics(
      button: true,
      label: version == null
          ? widget.installable
                ? 'Update available. Download and install.'
                : 'Update available. View release.'
          : widget.installable
          ? 'Clawnsole $version is available. Download and install.'
          : 'Clawnsole $version is available. View release.',
      child: Tooltip(
        message: widget.installable
            ? version == null
                  ? 'Download and install the Clawnsole update'
                  : 'Download and install Clawnsole $version'
            : version == null
            ? 'View the Clawnsole update'
            : 'View Clawnsole $version',
        child: DecoratedBox(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(999),
            boxShadow: <BoxShadow>[
              BoxShadow(
                color: UpdateGlowPainter.shadowColor,
                blurRadius: 12,
                spreadRadius: -2,
              ),
            ],
          ),
          child: RepaintBoundary(
            child: CustomPaint(
              key: const Key('update-available-glow'),
              painter: UpdateGlowPainter(frame: _clock.frame, cycle: _cycle),
              child: Material(
                color: Colors.transparent,
                child: InkWell(
                  key: const Key('update-available-chip'),
                  onTap: widget.onPressed,
                  borderRadius: BorderRadius.circular(999),
                  child: const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 11, vertical: 7),
                    child: Text(
                      'Update Available',
                      maxLines: 1,
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        letterSpacing: .15,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// The chip's drifting glow: a radial gradient whose centre wanders and whose
/// hues cross-fade between blue and violet, inside a faint white border.
class UpdateGlowPainter extends CustomPainter {
  UpdateGlowPainter({required this.frame, required this.cycle})
    : super(repaint: frame);

  static const Color _blue = Color(0xFF2563EB);
  static const Color _violet = Color(0xFF8B5CF6);
  static const Color _middleA = Color(0xFF6D28D9);
  static const Color _middleB = Color(0xFF1D4ED8);
  static const Color _edge = Color(0xFF312E81);

  /// The shadow the chip casts, fixed at the midpoint of the glow's drift.
  static final Color shadowColor = Color.lerp(
    _middleA,
    _middleB,
    .5,
  )!.withValues(alpha: .3);

  final ValueListenable<int> frame;
  final double Function() cycle;

  /// The gradient the painter would draw right now, so a test can read the
  /// drift without sampling pixels.
  @visibleForTesting
  RadialGradient gradientAt(double cycle) {
    final phase = cycle * math.pi * 2;
    final blend = (math.sin(phase) + 1) / 2;
    return RadialGradient(
      center: Alignment(math.cos(phase) * .72, math.sin(phase * 1.35) * .58),
      radius: 1.2,
      colors: <Color>[
        Color.lerp(_blue, _violet, blend)!,
        Color.lerp(_middleA, _middleB, blend)!,
        _edge,
      ],
      stops: const <double>[0, .58, 1],
    );
  }

  /// The gradient of the frame being painted.
  RadialGradient get gradient => gradientAt(cycle());

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final pill = RRect.fromRectAndRadius(rect, const Radius.circular(999));
    final shader = gradient.createShader(rect);
    try {
      canvas.drawRRect(pill, Paint()..shader = shader);
    } finally {
      shader.dispose();
    }
    canvas.drawRRect(
      pill.deflate(.5),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1
        ..color = Colors.white.withValues(alpha: .28),
    );
  }

  @override
  bool shouldRepaint(UpdateGlowPainter oldDelegate) =>
      oldDelegate.frame != frame;
}
