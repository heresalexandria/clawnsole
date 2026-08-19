import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

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

/// "Cyclone": silk ribbons painted into a slowly rotating feedback field, so
/// every pass leaves a luminous wake that curls and dissolves. The frame wears
/// a chased light border; film grain keeps the gradients from banding.
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
  static const double _stepSeconds = 1 / 30;
  static const int _warmupSteps = 26;
  static const int _staticSteps = 110;

  late final AnimationController _ticker = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 8),
  )..addListener(_onTick);
  final ValueNotifier<int> _frame = ValueNotifier<int>(0);

  static Future<ui.Image>? _grainFuture;
  static ui.Image? _grainCache;
  ui.Image? _grain;

  _CycloneField? _field;
  Duration _lastElapsed = Duration.zero;
  double _clock = 0;
  double _simTime = 0;
  bool _reduceMotion = false;

  @override
  void initState() {
    super.initState();
    _grain = _grainCache;
    if (_grain == null) {
      (_grainFuture ??= _makeGrain()).then((image) {
        _grainCache = image;
        if (mounted) setState(() => _grain = image);
      });
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _reduceMotion = MediaQuery.disableAnimationsOf(context);
    if (_reduceMotion) {
      _ticker.stop();
    } else if (!_ticker.isAnimating) {
      _lastElapsed = Duration.zero;
      _ticker.repeat();
    }
  }

  @override
  void dispose() {
    _ticker.dispose();
    _frame.dispose();
    _field?.dispose();
    super.dispose();
  }

  void _onTick() {
    final elapsed = _ticker.lastElapsedDuration ?? Duration.zero;
    final dt = (elapsed - _lastElapsed).inMicroseconds / 1e6;
    if (dt <= 0) return;
    _lastElapsed = elapsed;
    _clock += dt;
    var steps = 0;
    while (_clock - _simTime >= _stepSeconds && steps < 3) {
      _field?.step(_simTime);
      _simTime += _stepSeconds;
      steps++;
    }
    if (_clock - _simTime >= _stepSeconds) _simTime = _clock;
    if (steps > 0) _frame.value++;
  }

  void _ensureField(double aspect) {
    final current = _field;
    if (current != null && (current.aspect / aspect - 1).abs() < .04) return;
    current?.dispose();
    final field = _CycloneField(aspect);
    final warmup = _reduceMotion ? _staticSteps : _warmupSteps;
    for (var i = 0; i < warmup; i++) {
      field.step(_simTime);
      _simTime += _stepSeconds;
    }
    _field = field;
  }

  double _chaseAngle() => _reduceMotion ? 2.4 : (_clock % 8) / 8 * math.pi * 2;

  static Future<ui.Image> _makeGrain() {
    const side = 96;
    const alpha = 14;
    final random = math.Random(1971);
    final bytes = Uint8List(side * side * 4);
    for (var i = 0; i < bytes.length; i += 4) {
      // Premultiplied: decodeImageFromPixels treats rgba8888 as premultiplied.
      final value = random.nextInt(256) * alpha ~/ 255;
      bytes[i] = value;
      bytes[i + 1] = value;
      bytes[i + 2] = value;
      bytes[i + 3] = alpha;
    }
    final completer = Completer<ui.Image>();
    ui.decodeImageFromPixels(
      bytes,
      side,
      side,
      ui.PixelFormat.rgba8888,
      completer.complete,
    );
    return completer.future;
  }

  @override
  Widget build(BuildContext context) {
    final progress = widget.item.progress?.clamp(0, 100).toDouble();
    final semanticsLabel = progress == null
        ? 'Rendering video'
        : 'Rendering video, ${progress.round()}% complete';
    final statusLabel = progress == null
        ? 'RENDERING'
        : 'RENDERING — ${progress.round()}%';
    return RepaintBoundary(
      child: Semantics(
        label: semanticsLabel,
        liveRegion: true,
        child: LayoutBuilder(
          builder: (context, constraints) {
            final bounded =
                constraints.hasBoundedWidth &&
                constraints.hasBoundedHeight &&
                constraints.maxHeight > 0 &&
                constraints.maxWidth > 0;
            _ensureField(
              bounded
                  ? constraints.maxWidth / constraints.maxHeight
                  : generationAspectRatio(widget.item.config.aspectRatio),
            );
            return Stack(
              fit: StackFit.expand,
              children: <Widget>[
                CustomPaint(
                  key: ValueKey(
                    'generation-loading-cyclone-${widget.item.localId}',
                  ),
                  painter: _CyclonePainter(
                    field: _field!,
                    frame: _frame,
                    chaseAngle: _chaseAngle,
                    grain: _grain,
                  ),
                ),
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: 0,
                  height: 52,
                  child: IgnorePointer(
                    child: Container(
                      alignment: Alignment.bottomCenter,
                      padding: const EdgeInsets.only(
                        left: 12,
                        right: 12,
                        bottom: 14,
                      ),
                      decoration: const BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: <Color>[Color(0x00020206), Color(0xC7020206)],
                        ),
                      ),
                      child: FittedBox(
                        fit: BoxFit.scaleDown,
                        child: Text(
                          statusLabel,
                          style: const TextStyle(
                            color: Color(0xC7EBF0FF),
                            fontSize: 9.5,
                            fontWeight: FontWeight.w600,
                            letterSpacing: 2.8,
                            fontFeatures: <ui.FontFeature>[
                              ui.FontFeature.tabularFigures(),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

/// The low-resolution accumulation buffer: each step smears the previous frame
/// (slight rotation and zoom), fades it toward near-black, and strokes three
/// gradient ribbons additively on top.
class _CycloneField {
  _CycloneField(this.aspect) {
    if (aspect >= 1) {
      height = 150;
      width = math.min(320, (150 * aspect).round());
    } else {
      width = 150;
      height = math.min(320, (150 / aspect).round());
    }
  }

  final double aspect;
  late final int width;
  late final int height;
  ui.Image? image;

  static const List<Color> _colors = <Color>[
    Color(0xFF2B49FF),
    Color(0xFF6C4DFF),
    Color(0xFF8B2FC9),
    Color(0xFF3B8DE0),
    Color(0xFFA44FE8),
  ];

  void step(double t) {
    final w = width.toDouble();
    final h = height.toDouble();
    final bounds = Offset.zero & Size(w, h);
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder, bounds);
    canvas.drawRect(bounds, Paint()..color = const Color(0xFF03040C));
    if (image case final previous?) {
      canvas.save();
      canvas.translate(w / 2, h / 2);
      canvas.rotate(.0028);
      canvas.scale(1.009);
      canvas.drawImage(
        previous,
        Offset(-w / 2, -h / 2),
        Paint()
          ..color = const Color(0xF5FFFFFF)
          ..filterQuality = FilterQuality.low,
      );
      canvas.restore();
    }
    canvas.drawRect(bounds, Paint()..color = const Color(0x0C03040C));

    for (var i = 0; i < 3; i++) {
      final y0 = h * (.5 + .36 * math.sin(t * .06 + i * 2.1));
      final amp1 = h * (.144 + .044 * i);
      final amp2 = h * .055;
      final path = Path();
      final step = w / 44;
      for (var x = -step; x <= w + step; x += step) {
        final y =
            y0 +
            amp1 *
                math.sin(
                  x / w * math.pi * (1.3 + .5 * i) + t * (.3 + .07 * i),
                ) +
            amp2 * math.sin(x / w * math.pi * (3.1 + i) - t * .21);
        if (x == -step) {
          path.moveTo(x, y);
        } else {
          path.lineTo(x, y);
        }
      }
      final c0 = _colors[i % _colors.length];
      final c1 = _colors[(i + 2) % _colors.length];
      canvas.drawPath(
        path,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = h * (.1 + .055 * i)
          ..strokeCap = StrokeCap.round
          ..blendMode = BlendMode.plus
          ..shader = ui.Gradient.linear(
            Offset.zero,
            Offset(w, 0),
            <Color>[
              c0.withValues(alpha: 0),
              c0.withValues(alpha: .05),
              c1.withValues(alpha: .05),
              c1.withValues(alpha: 0),
            ],
            const <double>[0, .3, .7, 1],
          ),
      );
    }

    final picture = recorder.endRecording();
    final next = picture.toImageSync(width, height);
    picture.dispose();
    image?.dispose();
    image = next;
  }

  void dispose() {
    image?.dispose();
    image = null;
  }
}

class _CyclonePainter extends CustomPainter {
  _CyclonePainter({
    required this.field,
    required this.frame,
    required this.chaseAngle,
    required this.grain,
  }) : super(repaint: frame);

  final _CycloneField field;
  final ValueNotifier<int> frame;
  final double Function() chaseAngle;
  final ui.Image? grain;

  @override
  void paint(Canvas canvas, Size size) {
    final bounds = Offset.zero & size;
    canvas.drawRect(bounds, Paint()..color = const Color(0xFF04050D));

    if (field.image case final image?) {
      final cover =
          math.max(size.width / image.width, size.height / image.height) * 1.08;
      final dw = image.width * cover;
      final dh = image.height * cover;
      final dst = Rect.fromLTWH(
        (size.width - dw) / 2,
        (size.height - dh) / 2,
        dw,
        dh,
      );
      canvas.drawImageRect(
        image,
        Rect.fromLTWH(0, 0, image.width.toDouble(), image.height.toDouble()),
        dst,
        Paint()
          ..filterQuality = FilterQuality.medium
          ..imageFilter = ui.ImageFilter.blur(
            sigmaX: 5,
            sigmaY: 5,
            tileMode: TileMode.clamp,
          ),
      );
    }

    canvas.drawRect(
      bounds,
      Paint()
        ..shader = ui.Gradient.radial(
          Offset(size.width * .5, size.height * .44),
          size.longestSide * .72,
          <Color>[
            const Color(0x00000000),
            const Color(0x00000000),
            const Color(0x85000000),
          ],
          const <double>[0, .52, 1],
        ),
    );

    if (grain case final noise?) {
      canvas.drawRect(
        bounds,
        Paint()
          ..blendMode = BlendMode.overlay
          ..shader = ui.ImageShader(
            noise,
            TileMode.repeated,
            TileMode.repeated,
            Matrix4.identity().storage,
          ),
      );
    }

    final ring = RRect.fromRectAndCorners(
      bounds.deflate(1),
      topLeft: const Radius.circular(14),
      topRight: const Radius.circular(14),
    );
    canvas.drawRRect(
      ring,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1
        ..color = const Color(0x218C96FF),
    );
    canvas.drawRRect(
      ring,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.2
        ..shader = SweepGradient(
          transform: GradientRotation(chaseAngle()),
          colors: const <Color>[
            Color(0x004C6BFF),
            Color(0x004C6BFF),
            Color(0x0D4C6BFF),
            Color(0xCC4C6BFF),
            Color(0xF2B278FF),
            Color(0xFFE1CDFF),
            Color(0x00E1CDFF),
          ],
          stops: const <double>[0, .62, .72, .88, .97, .994, 1],
        ).createShader(bounds),
    );
  }

  @override
  bool shouldRepaint(covariant _CyclonePainter oldDelegate) =>
      oldDelegate.field != field || oldDelegate.grain != grain;
}
