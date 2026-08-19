import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../core/models.dart';

double generationAspectRatio(String value) {
  final parts = value.split(':');
  if (parts.length != 2) return 16 / 9;
  final width = double.tryParse(parts.first);
  final height = double.tryParse(parts.last);
  if (width == null || height == null || width <= 0 || height <= 0) {
    return 16 / 9;
  }
  return width / height;
}

class GenerationLoadingPlaceholder extends StatefulWidget {
  const GenerationLoadingPlaceholder({required this.item, super.key});

  final Generation item;

  @override
  State<GenerationLoadingPlaceholder> createState() =>
      _GenerationLoadingPlaceholderState();
}

class _GenerationLoadingPlaceholderState
    extends State<GenerationLoadingPlaceholder>
    with SingleTickerProviderStateMixin {
  late final AnimationController _animation = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 12),
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (MediaQuery.disableAnimationsOf(context)) {
      _animation.stop();
      _animation.value = .38;
    } else if (!_animation.isAnimating) {
      _animation.repeat();
    }
  }

  @override
  void dispose() {
    _animation.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final progress = widget.item.progress?.clamp(0, 100).toDouble();
    final label = progress == null
        ? 'Rendering video'
        : 'Rendering video, ${progress.round()}% complete';
    return RepaintBoundary(
      child: Semantics(
        label: label,
        liveRegion: true,
        child: Stack(
          fit: StackFit.expand,
          children: <Widget>[
            CustomPaint(
              key: ValueKey(
                'generation-loading-particles-${widget.item.localId}',
              ),
              painter: _ParticleFieldPainter(
                animation: _animation,
                progress: progress,
              ),
            ),
            Positioned(
              left: 12,
              right: 12,
              bottom: 13,
              child: Center(
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 11,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: const Color(0xB30A0D20),
                      borderRadius: BorderRadius.circular(999),
                      border: Border.all(color: const Color(0x668AEFFF)),
                      boxShadow: const <BoxShadow>[
                        BoxShadow(
                          color: Color(0x553B8CFF),
                          blurRadius: 18,
                          spreadRadius: 1,
                        ),
                      ],
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: <Widget>[
                        Container(
                          width: 5,
                          height: 5,
                          decoration: const BoxDecoration(
                            shape: BoxShape.circle,
                            color: Color(0xFF9CFBFF),
                            boxShadow: <BoxShadow>[
                              BoxShadow(
                                color: Color(0xFF31DFFF),
                                blurRadius: 8,
                                spreadRadius: 2,
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 7),
                        Text(
                          progress == null
                              ? 'RENDERING'
                              : 'RENDERING  •  ${progress.round()}%',
                          style: const TextStyle(
                            color: Color(0xFFEAFDFF),
                            fontSize: 9.5,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 1.35,
                            shadows: <Shadow>[
                              Shadow(color: Color(0xFF41E7FF), blurRadius: 10),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ParticleFieldPainter extends CustomPainter {
  _ParticleFieldPainter({required this.animation, required this.progress})
    : super(repaint: animation);

  final Animation<double> animation;
  final double? progress;

  static const _particleColors = <Color>[
    Color(0xFF71F6FF),
    Color(0xFF6788FF),
    Color(0xFFC66CFF),
    Color(0xFFFF65C7),
    Color(0xFFFFD47A),
  ];

  @override
  void paint(Canvas canvas, Size size) {
    final bounds = Offset.zero & size;
    final t = animation.value;
    canvas.drawRect(
      bounds,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: <Color>[
            Color(0xFF050713),
            Color(0xFF11103A),
            Color(0xFF1B0A31),
            Color(0xFF071827),
          ],
          stops: <double>[0, .36, .68, 1],
        ).createShader(bounds),
    );

    _drawGlow(
      canvas,
      size,
      Offset(
        size.width * (.22 + .08 * math.sin(t * math.pi * 2)),
        size.height * .22,
      ),
      const Color(0xFF2E79FF),
      .72,
    );
    _drawGlow(
      canvas,
      size,
      Offset(.82 * size.width, size.height * (.62 + .09 * math.cos(t * 6))),
      const Color(0xFFFF3DC8),
      .62,
    );
    _drawGlow(
      canvas,
      size,
      Offset(.5 * size.width, .5 * size.height),
      const Color(0xFF5C35FF),
      .44,
    );
    _drawGrid(canvas, size, t);
    _drawEnergyRings(canvas, size, t);
    _drawParticles(canvas, size, t);
    _drawSweep(canvas, size, t);
  }

  void _drawGlow(
    Canvas canvas,
    Size size,
    Offset center,
    Color color,
    double scale,
  ) {
    final radius = math.min(size.width, size.height) * scale;
    final rect = Rect.fromCircle(center: center, radius: radius);
    canvas.drawCircle(
      center,
      radius,
      Paint()
        ..shader = RadialGradient(
          colors: <Color>[
            color.withValues(alpha: .27),
            color.withValues(alpha: .08),
            Colors.transparent,
          ],
          stops: const <double>[0, .46, 1],
        ).createShader(rect),
    );
  }

  void _drawGrid(Canvas canvas, Size size, double t) {
    final paint = Paint()
      ..color = const Color(0xFF8DEEFF).withValues(alpha: .055)
      ..strokeWidth = .7
      ..style = PaintingStyle.stroke;
    final drift = (t * 28) % 28;
    for (double x = -size.height + drift; x < size.width; x += 28) {
      canvas.drawLine(
        Offset(x, 0),
        Offset(x + size.height, size.height),
        paint,
      );
    }
    for (double y = 14; y < size.height; y += 28) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), paint);
    }
  }

  void _drawEnergyRings(Canvas canvas, Size size, double t) {
    final center = Offset(size.width * .5, size.height * .46);
    final base = math.min(size.width, size.height) * .16;
    final haloRect = Rect.fromCircle(center: center, radius: base * 1.35);
    canvas.drawCircle(
      center,
      base * .92,
      Paint()
        ..shader = const RadialGradient(
          colors: <Color>[
            Color(0x885EEDFF),
            Color(0x332D62FF),
            Colors.transparent,
          ],
        ).createShader(haloRect),
    );

    for (var i = 0; i < 3; i++) {
      final radius = base * (1 + i * .27);
      final rect = Rect.fromCircle(center: center, radius: radius);
      final phase = t * math.pi * 2 * (i.isEven ? 1 : -1) + i;
      canvas.drawArc(
        rect,
        phase,
        math.pi * (1.05 + i * .12),
        false,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.2 + (2 - i) * .45
          ..strokeCap = StrokeCap.round
          ..shader = SweepGradient(
            transform: GradientRotation(phase),
            colors: <Color>[
              Colors.transparent,
              _particleColors[i].withValues(alpha: .95),
              _particleColors[i + 1].withValues(alpha: .35),
              Colors.transparent,
            ],
          ).createShader(rect),
      );
    }

    if (progress case final value?) {
      final rect = Rect.fromCircle(center: center, radius: base * 1.48);
      canvas.drawArc(
        rect,
        -math.pi / 2,
        math.pi * 2 * value / 100,
        false,
        Paint()
          ..color = const Color(0xFFD1FCFF)
          ..strokeWidth = 2.2
          ..strokeCap = StrokeCap.round
          ..style = PaintingStyle.stroke
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 2),
      );
    }
  }

  void _drawParticles(Canvas canvas, Size size, double t) {
    for (var i = 0; i < 52; i++) {
      final seed = i * 1.61803398875;
      final speed = .34 + (i % 7) * .045;
      final phase = t * math.pi * 2 * speed + seed;
      final lane = i % 4;
      final center = Offset(
        size.width * (.5 + .16 * math.sin(t * 2.1 + lane)),
        size.height * (.46 + .12 * math.cos(t * 1.7 + lane * .8)),
      );
      final radiusX = size.width * (.1 + (i % 11) * .025);
      final radiusY = size.height * (.08 + (i % 9) * .024);
      final wobble = math.sin(phase * 2.3 + seed) * .18;
      final position = Offset(
        center.dx + math.cos(phase + wobble) * radiusX,
        center.dy + math.sin(phase * 1.27) * radiusY,
      );
      final tailPhase = phase - .075 - (i % 3) * .012;
      final tail = Offset(
        center.dx + math.cos(tailPhase + wobble) * radiusX,
        center.dy + math.sin(tailPhase * 1.27) * radiusY,
      );
      final color = _particleColors[i % _particleColors.length];
      final alpha = .34 + (i % 5) * .11;
      canvas.drawLine(
        tail,
        position,
        Paint()
          ..shader = LinearGradient(
            colors: <Color>[
              color.withValues(alpha: 0),
              color.withValues(alpha: alpha),
            ],
          ).createShader(Rect.fromPoints(tail, position))
          ..strokeWidth = .7 + (i % 3) * .45
          ..strokeCap = StrokeCap.round,
      );
      canvas.drawCircle(
        position,
        1 + (i % 4) * .38,
        Paint()
          ..color = color.withValues(alpha: alpha)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 1.2),
      );
      if (i % 9 == 0) {
        canvas.drawCircle(
          position,
          2.3,
          Paint()..color = Colors.white.withValues(alpha: .82),
        );
      }
    }
  }

  void _drawSweep(Canvas canvas, Size size, double t) {
    final x = (t * 1.45 % 1.0) * (size.width * 1.5) - size.width * .25;
    final rect = Rect.fromCenter(
      center: Offset(x, size.height * .5),
      width: size.width * .28,
      height: size.height * 1.7,
    );
    canvas.drawRect(
      rect,
      Paint()
        ..shader = const LinearGradient(
          colors: <Color>[
            Colors.transparent,
            Color(0x0FFFFFFF),
            Color(0x2238E5FF),
            Colors.transparent,
          ],
        ).createShader(rect),
    );
  }

  @override
  bool shouldRepaint(covariant _ParticleFieldPainter oldDelegate) =>
      oldDelegate.progress != progress;
}
