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

class GenerationLoadingPlaceholder extends StatelessWidget {
  const GenerationLoadingPlaceholder({
    required this.item,
    this.style = GenerationPlaceholderStyle.broadcastStatic,
    super.key,
  });

  final Generation item;
  final GenerationPlaceholderStyle style;

  @override
  Widget build(BuildContext context) {
    final progress = item.progress?.clamp(0, 100).toDouble();
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
        child: Stack(
          fit: StackFit.expand,
          children: <Widget>[
            switch (style) {
              GenerationPlaceholderStyle.broadcastStatic =>
                _BroadcastStaticSurface(itemId: item.localId),
              GenerationPlaceholderStyle.cyclone => _CycloneSurface(item: item),
            },
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
        ),
      ),
    );
  }
}

/// A live reception chain rather than a flat noise texture. Its snow is new on
/// every frame, then passes through weak-signal gain breathing, RF beat
/// patterns, rolling hum, sync tears, impulse dashes, scanlines, and CRT glass.
class _BroadcastStaticSurface extends StatefulWidget {
  const _BroadcastStaticSurface({required this.itemId});

  final String itemId;

  @override
  State<_BroadcastStaticSurface> createState() =>
      _BroadcastStaticSurfaceState();
}

class _BroadcastStaticSurfaceState extends State<_BroadcastStaticSurface>
    with SingleTickerProviderStateMixin {
  static const int _noiseFrameCount = 16;
  static Future<List<ui.Image>>? _noiseFuture;
  static List<ui.Image>? _noiseCache;

  late final AnimationController _ticker = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 4),
  );
  List<ui.Image> _frames = _noiseCache ?? const <ui.Image>[];
  bool _reduceMotion = false;

  @override
  void initState() {
    super.initState();
    if (_frames.isEmpty) {
      (_noiseFuture ??= _makeNoiseFrames()).then((frames) {
        _noiseCache = frames;
        if (mounted) setState(() => _frames = frames);
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
      _ticker.repeat();
    }
  }

  @override
  void dispose() {
    _ticker.dispose();
    super.dispose();
  }

  static Future<List<ui.Image>> _makeNoiseFrames() => Future.wait(
    List<Future<ui.Image>>.generate(
      _noiseFrameCount,
      _makeNoiseFrame,
      growable: false,
    ),
  );

  static Future<ui.Image> _makeNoiseFrame(int frame) {
    const width = 144;
    const height = 96;
    final random = math.Random(1959 + frame * 7919);
    final bytes = Uint8List(width * height * 4);
    for (var y = 0; y < height; y++) {
      final crushedLine = random.nextDouble() < .035;
      final lineBias = random.nextInt(35) - 17;
      var previous = random.nextInt(256);
      for (var x = 0; x < width; x++) {
        var value = random.nextInt(256);
        value = (value * 4 + previous) ~/ 5;
        previous = value;
        value = (value + lineBias).clamp(0, 255);
        final impulse = random.nextDouble();
        if (impulse < .025) {
          value = 255;
        } else if (impulse < .052 || crushedLine) {
          value = random.nextInt(34);
        }
        final offset = (y * width + x) * 4;
        bytes[offset] = value;
        bytes[offset + 1] = value;
        bytes[offset + 2] = value;
        bytes[offset + 3] = 255;
      }
    }
    final completer = Completer<ui.Image>();
    ui.decodeImageFromPixels(
      bytes,
      width,
      height,
      ui.PixelFormat.rgba8888,
      completer.complete,
    );
    return completer.future;
  }

  @override
  Widget build(BuildContext context) => CustomPaint(
    key: ValueKey('generation-loading-static-${widget.itemId}'),
    painter: _BroadcastStaticPainter(
      frames: _frames,
      ticker: _ticker,
      phase: () => _reduceMotion ? .317 : _ticker.value,
    ),
  );
}

class _BroadcastStaticPainter extends CustomPainter {
  _BroadcastStaticPainter({
    required this.frames,
    required this.ticker,
    required this.phase,
  }) : super(repaint: ticker);

  final List<ui.Image> frames;
  final AnimationController ticker;
  final double Function() phase;

  void _drawNoise(
    Canvas canvas,
    Size size,
    ui.Image image,
    double scale,
    double dx,
    double dy,
  ) {
    final tileWidth = image.width * scale;
    final tileHeight = image.height * scale;
    final source = Rect.fromLTWH(
      0,
      0,
      image.width.toDouble(),
      image.height.toDouble(),
    );
    final paint = Paint()..filterQuality = FilterQuality.none;
    final startX = dx % tileWidth - tileWidth;
    final startY = dy % tileHeight - tileHeight;
    for (var y = startY; y < size.height; y += tileHeight) {
      for (var x = startX; x < size.width; x += tileWidth) {
        canvas.drawImageRect(
          image,
          source,
          Rect.fromLTWH(x, y, tileWidth, tileHeight),
          paint,
        );
      }
    }
  }

  @override
  void paint(Canvas canvas, Size size) {
    final bounds = Offset.zero & size;
    final t = phase();
    canvas.drawRect(bounds, Paint()..color = const Color(0xFF121416));

    if (frames.isNotEmpty) {
      final frameIndex = (t * frames.length * 10).floor() % frames.length;
      final scale = (size.shortestSide / 118).clamp(.72, 2.25).toDouble();
      final jitterX = math.sin(t * math.pi * 173) * scale * 2.4;
      final jitterY = math.cos(t * math.pi * 97) * scale * .7;
      final noise = frames[frameIndex];
      _drawNoise(canvas, size, noise, scale, jitterX, jitterY);

      _drawSyncTears(canvas, size, noise, scale, jitterX, jitterY, t);
    }

    _drawGainBreathing(canvas, size, t);
    _drawCarrierInterference(canvas, size, t);
    _drawHumBar(canvas, size, t);
    _drawImpulseNoise(canvas, size, t);
    _drawRetrace(canvas, size, t);
    _drawRaster(canvas, size, t);
    _drawGlass(canvas, size);
  }

  void _drawSyncTears(
    Canvas canvas,
    Size size,
    ui.Image noise,
    double scale,
    double noiseX,
    double noiseY,
    double t,
  ) {
    for (var i = 0; i < 3; i++) {
      final speed = 1.7 + i * .43;
      final y = ((t * speed + .17 + i * .281) % 1) * size.height;
      final bandHeight = math.max(2.0, size.height * (.012 + i * .006));
      final jitter = math.sin(t * math.pi * (113 + i * 31) + i) * .5 + .5;
      final offset = size.width * (.025 + .035 * jitter) * (i.isEven ? 1 : -1);
      final band = Rect.fromLTWH(0, y - bandHeight / 2, size.width, bandHeight);
      canvas.save();
      canvas.clipRect(band);
      canvas.translate(offset, 0);
      _drawNoise(canvas, size, noise, scale, noiseX, noiseY);
      canvas.restore();
      canvas.drawRect(
        Rect.fromLTWH(0, y - .75, size.width, 1.15),
        Paint()..color = Color.fromRGBO(235, 244, 247, .22 + i * .035),
      );
      canvas.drawRect(
        Rect.fromLTWH(0, y + .55, size.width, math.max(1, bandHeight * .24)),
        Paint()..color = const Color(0x62000000),
      );
    }
  }

  void _drawGainBreathing(Canvas canvas, Size size, double t) {
    final swell = .5 + .5 * math.sin(t * math.pi * 4.2 + .8);
    final flutter = .5 + .5 * math.sin(t * math.pi * 13.7);
    canvas.drawRect(
      Offset.zero & size,
      Paint()
        ..color = Color.fromRGBO(
          214,
          224,
          226,
          .025 + swell * .035 + flutter * .012,
        )
        ..blendMode = BlendMode.screen,
    );
  }

  void _drawCarrierInterference(Canvas canvas, Size size, double t) {
    final spacing = (size.shortestSide / 34).clamp(5.5, 11.0).toDouble();
    final drift = (t * spacing * 18) % (spacing * 2);
    final path = Path();
    for (
      var x = -size.height - spacing + drift;
      x < size.width + size.height;
      x += spacing * 2
    ) {
      path
        ..moveTo(x, 0)
        ..lineTo(x + size.height * .46, size.height)
        ..moveTo(x + spacing, 0)
        ..lineTo(x + spacing - size.height * .46, size.height);
    }
    canvas.save();
    canvas.clipRect(Offset.zero & size);
    canvas.drawPath(
      path,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = math.max(.55, size.shortestSide / 520)
        ..color = const Color(0x16E8F1EE)
        ..blendMode = BlendMode.screen,
    );
    canvas.restore();
  }

  void _drawHumBar(Canvas canvas, Size size, double t) {
    final center = size.height * (1.12 - ((t * .72 + .08) % 1) * 1.28);
    final halfHeight = size.height * .17;
    final rect = Rect.fromLTRB(
      0,
      center - halfHeight,
      size.width,
      center + halfHeight,
    );
    canvas.drawRect(
      rect,
      Paint()
        ..shader = ui.Gradient.linear(
          Offset(0, rect.top),
          Offset(0, rect.bottom),
          const <Color>[
            Color(0x00000000),
            Color(0x28000000),
            Color(0x72000000),
            Color(0x36000000),
            Color(0x00000000),
          ],
          const <double>[0, .22, .5, .72, 1],
        ),
    );
    canvas.drawRect(
      Rect.fromLTWH(0, center - halfHeight * .82, size.width, 1.2),
      Paint()..color = const Color(0x3FFFFFFF),
    );
  }

  void _drawImpulseNoise(Canvas canvas, Size size, double t) {
    final frame = (t * 240).floor();
    final random = math.Random(1966 + frame * 104729);
    final events = 3 + random.nextInt(8);
    final scale = (size.shortestSide / 240).clamp(.65, 1.8).toDouble();
    final paint = Paint()
      ..strokeCap = StrokeCap.square
      ..blendMode = BlendMode.screen;
    for (var i = 0; i < events; i++) {
      final y = random.nextDouble() * size.height;
      final x = random.nextDouble() * size.width * .82;
      final length = size.width * (.025 + random.nextDouble() * .24);
      paint
        ..strokeWidth = scale * (random.nextDouble() < .17 ? 2.4 : .8)
        ..color = Color.fromRGBO(
          237,
          246,
          241,
          .16 + random.nextDouble() * .58,
        );
      canvas.drawLine(
        Offset(x, y),
        Offset(math.min(size.width, x + length), y),
        paint,
      );
    }
  }

  void _drawRetrace(Canvas canvas, Size size, double t) {
    final spacing = size.height / 7.8;
    final drift = (t * spacing * 2.1) % spacing;
    final path = Path();
    for (var y = -spacing + drift; y < size.height + spacing; y += spacing) {
      path
        ..moveTo(-size.width * .08, y + size.height * .17)
        ..lineTo(size.width * 1.08, y - size.height * .17);
    }
    canvas.drawPath(
      path,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = math.max(.65, size.shortestSide / 430)
        ..color = const Color(0x18E2F2F0)
        ..blendMode = BlendMode.screen,
    );
  }

  void _drawRaster(Canvas canvas, Size size, double t) {
    final spacing = (size.height / 150).clamp(2.2, 4.2).toDouble();
    final offset = (t * spacing * 4) % spacing;
    final dark = Path();
    for (var y = offset; y < size.height; y += spacing) {
      dark
        ..moveTo(0, y)
        ..lineTo(size.width, y);
    }
    canvas.drawPath(
      dark,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = math.max(.65, spacing * .28)
        ..color = const Color(0x52000000),
    );

    final fieldParity = (t * 120).floor().isEven ? 0.0 : spacing / 2;
    final fieldLine = (size.height * .07 + fieldParity) % size.height;
    canvas.drawLine(
      Offset(0, fieldLine),
      Offset(size.width, fieldLine),
      Paint()
        ..strokeWidth = math.max(1, spacing * .42)
        ..color = const Color(0x32F2FFFF)
        ..blendMode = BlendMode.screen,
    );
  }

  void _drawGlass(Canvas canvas, Size size) {
    final bounds = Offset.zero & size;
    canvas.drawRect(
      bounds,
      Paint()
        ..color = const Color(0x120A2130)
        ..blendMode = BlendMode.color,
    );
    canvas.drawRect(
      bounds,
      Paint()
        ..shader = ui.Gradient.radial(
          Offset(size.width * .5, size.height * .44),
          size.longestSide * .72,
          const <Color>[
            Color(0x00000000),
            Color(0x00000000),
            Color(0xA8000000),
          ],
          const <double>[0, .52, 1],
        ),
    );
    canvas.drawRect(
      bounds,
      Paint()
        ..shader = ui.Gradient.linear(
          Offset(size.width * .03, 0),
          Offset(size.width * .58, size.height * .68),
          const <Color>[
            Color(0x21EAF7FF),
            Color(0x07EAF7FF),
            Color(0x00FFFFFF),
          ],
          const <double>[0, .38, 1],
        )
        ..blendMode = BlendMode.screen,
    );
    final glass = RRect.fromRectAndRadius(
      bounds.deflate(1),
      const Radius.circular(13),
    );
    canvas.drawRRect(
      glass,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1
        ..color = const Color(0x4A9FAEB2),
    );
  }

  @override
  bool shouldRepaint(covariant _BroadcastStaticPainter oldDelegate) =>
      oldDelegate.frames != frames;
}

/// "Cyclone": silk ribbons painted into a slowly rotating feedback field, so
/// every pass leaves a luminous wake that curls and dissolves. The frame wears
/// a chased light border; film grain keeps the gradients from banding.
class _CycloneSurface extends StatefulWidget {
  const _CycloneSurface({required this.item});

  final Generation item;

  @override
  State<_CycloneSurface> createState() => _CycloneSurfaceState();
}

class _CycloneSurfaceState extends State<_CycloneSurface>
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
  Widget build(BuildContext context) => LayoutBuilder(
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
      return CustomPaint(
        key: ValueKey('generation-loading-cyclone-${widget.item.localId}'),
        painter: _CyclonePainter(
          field: _field!,
          frame: _frame,
          chaseAngle: _chaseAngle,
          grain: _grain,
        ),
      );
    },
  );
}

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
          const <Color>[
            Color(0x00000000),
            Color(0x00000000),
            Color(0x85000000),
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
