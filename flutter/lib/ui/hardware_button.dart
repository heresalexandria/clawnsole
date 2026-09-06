// The Generate key: a backlit push-button indicator of the kind that filled
// 1960s command-center consoles — a frosted translucent plum lens seated in
// a thin charcoal bezel, with an engraved uppercase legend, lit from behind
// by incandescent lamps when the console is working.
//
// Everything is drawn in code — bezel, gap, frosted lens, lamps, grain — so
// it renders identically at 1×, 2× and 3× and on every platform. The lens is
// matte: no specular band, no gloss, no bloom. Its plastic is the same plum
// in both appearance modes (a button is one of the two things allowed to
// stay dark on paper); only the bezel shadow alphas change with the room.

import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import '../app/app_theme.dart';
import 'hardware.dart';

/// Radius of the bezel's outer corner: nearly square, like the real thing.
const double _outerRadius = 5;

/// Thickness of the charcoal bezel that seats the lens.
const double _bezelWidth = 3.2;

/// The dark gap between bezel and lens, where the cap sits a little recessed.
const double _gapWidth = 1.3;

/// Radius of the lens's own corners.
const double _lensRadius = 3.4;

/// How far the lens sinks into its bezel while held.
const double _pressDepth = 1;

/// Narrowest a key ever draws, so a short legend still reads as a key.
const double _minKeyWidth = 170;

// ---------------------------------------------------------------------------
// Colour anchors. Plum in both modes, never blue.
// ---------------------------------------------------------------------------

// The bezel: matte charcoal, a shade warmer than neutral.
const _bezelTop = Color(0xFF34302E);
const _bezelBottom = Color(0xFF211E1C);

// The gap between bezel and lens.
const _gap = Color(0xFF0C0A09);

// The frosted lens with the lamps off: dusty plum, lit only by the room.
const _lensTopIdle = Color(0xFF6B4B6A);
const _lensBottomIdle = Color(0xFF503653);

// The lens with the lamps on: the whole block glows plum-magenta.
const _lensTopLit = Color(0xFF9E4B90);
const _lensBottomLit = Color(0xFF7E3B76);

// The incandescent lamps behind the diffuser.
const _lamp = Color(0xFFEFAFDB);

// What a lit lens throws onto the panel around it: very little.
const _spill = Color(0xFFC468B2);

// Warm black for edge shading; a neutral black would cool the plum.
const _shade = Color(0xFF160C13);
const _keyShadow = Color(0xFF120C08);

/// Cream ink for the legend: white-filled engraving on a coloured lens.
const _legendInk = Color(0xFFF3EAD9);
const _legendInkLit = Color(0xFFFFF8EE);

/// A fixed speckle pattern in unit space: the frosted diffuser's tooth.
/// Generated once, mapped onto whatever size the lens ends up.
final List<Offset> _frost = () {
  final random = math.Random(0x5C0A7);
  return List<Offset>.generate(
    720,
    (_) => Offset(random.nextDouble(), random.nextDouble()),
  );
}();

/// A wide backlit push-button indicator with a frosted plum lens.
///
/// [lit] is the studio's "working" signal: the lamps stay on while a render
/// is in flight even though [onPressed] is null, so nothing has to spin.
class HardwareLitButton extends StatefulWidget {
  const HardwareLitButton({
    required this.label,
    required this.onPressed,
    super.key,
    this.icon,
    this.lit = false,
    this.height = kConsoleControlHeight,
    this.semanticLabel,
  });

  /// The legend, engraved in capitals on the lens. Rendered as a plain
  /// [Text] carrying the upper-cased string; the semantics keep [label].
  final String label;

  /// Null disables the key: it dims and stops taking taps and hover.
  final VoidCallback? onPressed;

  /// A leading mark, usually the claw, inked like the legend.
  final Widget? icon;

  /// Holds the lamps on regardless of [onPressed].
  final bool lit;

  /// Drawn height. Matches the model selector so the faceplate lines up.
  final double height;

  /// Defaults to [label].
  final String? semanticLabel;

  /// The legend as it is engraved: capitals, letter-spaced.
  static String engrave(String label) => label.toUpperCase();

  @override
  State<HardwareLitButton> createState() => HardwareLitButtonState();
}

/// Public so tests can read the lamp without screen-scraping pixels.
class HardwareLitButtonState extends State<HardwareLitButton>
    with TickerProviderStateMixin {
  // Incandescent lamps: the filament heats over a quarter second and
  // settles; switched off it drops fast, then the afterglow lingers.
  late final AnimationController _lamp = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 240),
    reverseDuration: const Duration(milliseconds: 420),
    value: widget.lit ? 1 : 0,
  )..addStatusListener(_handleLampStatus);
  late final Animation<double> _glow = CurvedAnimation(
    parent: _lamp,
    curve: Curves.easeOutCubic,
    reverseCurve: Curves.easeInCubic,
  );

  // The filament's wander, ticking only while the lamps are on.
  late final Ticker _filamentTicker = createTicker(_tickFilament);
  final ValueNotifier<double> _filament = ValueNotifier<double>(1);
  final int _seed = math.Random().nextInt(1 << 20);
  late final AnimationController _hoverLift = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 140),
    reverseDuration: const Duration(milliseconds: 200),
  );

  bool _pressed = false;
  bool _focused = false;

  bool get _enabled => widget.onPressed != null;

  /// How lit the lens is right now, 0 (lamps off) to 1 (full lamps).
  @visibleForTesting
  double get litAmount => _glow.value;

  /// The filament's momentary brightness relative to steady, about
  /// 0.9–1.05 while the lamps are on and exactly 1 when they are off.
  @visibleForTesting
  double get filament => _filament.value;

  /// Whether the filament wander is ticking — true only while lit.
  @visibleForTesting
  bool get isFilamentLit => _filamentTicker.isActive;

  @override
  void initState() {
    super.initState();
    if (widget.lit) _filamentTicker.start();
  }

  /// Whether a pointer is currently holding the key down.
  @visibleForTesting
  bool get isPressed => _pressed;

  /// Whether the brass focus halo is showing.
  @visibleForTesting
  bool get isFocused => _focused;

  @override
  void didUpdateWidget(HardwareLitButton oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.lit != oldWidget.lit) _driveLamp();
    if (!_enabled && (_pressed || _focused)) {
      _pressed = false;
      _focused = false;
      _hoverLift.reverse();
      _driveLamp();
    }
  }

  @override
  void dispose() {
    _filamentTicker.dispose();
    _filament.dispose();
    _lamp.dispose();
    _hoverLift.dispose();
    super.dispose();
  }

  // The wander runs exactly as long as any light is in the lens: from the
  // first frame of warm-up to the last of the afterglow, and never once
  // the lamp is cold, so a dark console schedules no frames.
  void _handleLampStatus(AnimationStatus status) {
    if (status == AnimationStatus.dismissed) {
      _filamentTicker.stop();
      _filament.value = 1;
    } else if (!_filamentTicker.isActive) {
      _filamentTicker.start();
    }
  }

  void _tickFilament(Duration elapsed) {
    final next = _filamentAt(
      elapsed.inMicroseconds / Duration.microsecondsPerSecond,
    );
    if ((next - _filament.value).abs() > .0004) _filament.value = next;
  }

  double _phase(int n) => math.Random(_seed + n).nextDouble() * 2 * math.pi;

  double _noise(int n) => math.Random(_seed ^ (n * 7919)).nextDouble();

  /// Incandescent filaments never hold perfectly steady: a few percent of
  /// slow wander from the supply, and now and then a brief sag. Subtle by
  /// design — the eye should feel it before it sees it.
  double _filamentAt(double t) {
    var w =
        1 +
        .02 * math.sin(2 * math.pi * 1.31 * t + _phase(0)) +
        .012 * math.sin(2 * math.pi * 3.07 * t + _phase(1)) +
        .008 * math.sin(2 * math.pi * 5.83 * t + _phase(2));
    // Every so often, in about one window of nine hundred milliseconds in
    // five, the supply sags for a moment.
    const window = .9;
    final k = (t / window).floor();
    if (_noise(k) < .22) {
      final at = (k + .2 + .6 * _noise(k + 1000)) * window;
      final d = (t - at) / .045;
      w -= .07 * math.exp(-d * d);
    }
    return w.clamp(.9, 1.05);
  }

  // One calm pace: 140 ms up, 280 ms down, and never a loop.
  void _driveLamp() {
    if (widget.lit || _pressed) {
      _lamp.forward();
    } else {
      _lamp.reverse();
    }
  }

  // A key clicks as it goes down, the way real hardware does.
  void _setPressed(bool value) {
    if (_pressed == value) return;
    if (value) hardwareSelectionFeedback();
    setState(() => _pressed = value);
    _driveLamp();
  }

  /// [click] is false when the finger already clicked on the way down.
  void _activate({bool click = true}) {
    if (!_enabled) return;
    if (click) hardwareSelectionFeedback();
    widget.onPressed!.call();
  }

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;

    final face = AnimatedBuilder(
      animation: Listenable.merge(<Listenable>[_lamp, _hoverLift, _filament]),
      builder: (context, _) {
        final lit = _glow.value;
        final filament = _filament.value;
        final glow = (lit * filament).clamp(0.0, 1.0);
        final ink = Color.lerp(_legendInk, _legendInkLit, lit)!;
        final legend = Text(
          HardwareLitButton.engrave(widget.label),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          textAlign: TextAlign.center,
          style: (Theme.of(context).textTheme.labelLarge ?? const TextStyle())
              .copyWith(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                letterSpacing: 1.9,
                height: 1.05,
                color: ink,
                // Lit, the white-filled engraving takes a little of the
                // lamp light itself.
                shadows: lit > 0
                    ? <Shadow>[
                        Shadow(
                          color: Colors.white.withValues(alpha: .38 * glow),
                          blurRadius: 4,
                        ),
                      ]
                    : null,
              ),
        );
        final content = Padding(
          padding: const EdgeInsets.symmetric(horizontal: 22),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            children: <Widget>[
              if (widget.icon != null) ...<Widget>[
                IconTheme.merge(
                  data: IconThemeData(color: ink),
                  child: widget.icon!,
                ),
                const SizedBox(width: 9),
              ],
              Flexible(child: legend),
            ],
          ),
        );
        return CustomPaint(
          painter: _IndicatorPainter(
            dark: dark,
            lit: lit,
            filament: filament,
            hover: _hoverLift.value,
            pressed: _pressed,
            focusGlow: _focused ? context.tokens.brass : null,
          ),
          // widthFactor 1 hugs the legend when the parent leaves room, and
          // still fills a stretched column, where the incoming width is tight.
          child: Center(
            widthFactor: 1,
            child: Transform.translate(
              offset: Offset(0, _pressed ? _pressDepth : 0),
              child: content,
            ),
          ),
        );
      },
    );

    final key = ConstrainedBox(
      constraints: BoxConstraints(
        minWidth: _minKeyWidth,
        minHeight: widget.height,
        maxHeight: widget.height,
      ),
      child: face,
    );

    // A dark, unlit key reads as out of service; a lit one is working, so it
    // keeps its full brightness even though it refuses taps.
    final dimmed = !_enabled && !widget.lit;

    // One semantics node for the whole key, outside the detector so screen
    // readers and `getSemantics` find the button at the widget's own root.
    return Semantics(
      button: true,
      enabled: _enabled,
      label: widget.semanticLabel ?? widget.label,
      onTap: _enabled ? () => _activate() : null,
      excludeSemantics: true,
      child: FocusableActionDetector(
        enabled: _enabled,
        includeFocusSemantics: false,
        mouseCursor: _enabled
            ? SystemMouseCursors.click
            : SystemMouseCursors.basic,
        onShowHoverHighlight: (value) =>
            value ? _hoverLift.forward() : _hoverLift.reverse(),
        onShowFocusHighlight: (value) {
          if (_focused != value) setState(() => _focused = value);
        },
        actions: <Type, Action<Intent>>{
          ActivateIntent: CallbackAction<ActivateIntent>(
            onInvoke: (_) {
              _activate();
              return null;
            },
          ),
          ButtonActivateIntent: CallbackAction<ButtonActivateIntent>(
            onInvoke: (_) {
              _activate();
              return null;
            },
          ),
        },
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTapDown: _enabled ? (_) => _setPressed(true) : null,
          // Tap-up is the moment the key releases and the studio starts.
          onTapUp: _enabled
              ? (_) {
                  _setPressed(false);
                  _activate(click: false);
                }
              : null,
          onTapCancel: _enabled ? () => _setPressed(false) : null,
          child: dimmed ? Opacity(opacity: .55, child: key) : key,
        ),
      ),
    );
  }
}

/// Paints the indicator: bezel, gap, and the frosted lens with its lamps.
class _IndicatorPainter extends CustomPainter {
  const _IndicatorPainter({
    required this.dark,
    required this.lit,
    required this.filament,
    required this.hover,
    required this.pressed,
    required this.focusGlow,
  });

  final bool dark;

  /// How far the lamps have warmed, 0 to 1.
  final double lit;

  /// The filament's momentary brightness relative to steady.
  final double filament;

  /// What the lamps are actually giving right now.
  double get glow => (lit * filament).clamp(0.0, 1.0);

  /// The diffuser smooths the wander before it reaches the whole block, so
  /// the body follows the filament only a little.
  double get body => (lit * (.85 + .15 * filament)).clamp(0.0, 1.0);
  final double hover;
  final bool pressed;
  final Color? focusGlow;

  /// Hover is a small lift in the lens, not a colour change.
  Color _lift(Color color) => Color.lerp(color, Colors.white, .05 * hover)!;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final outer = RRect.fromRectAndRadius(
      rect,
      const Radius.circular(_outerRadius),
    );

    _paintFocusHalo(canvas, rect);
    _paintSeating(canvas, rect, outer);
    _paintBezel(canvas, rect, outer);

    // The gap the lens sits in.
    final gapRect = rect.deflate(_bezelWidth);
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        gapRect,
        const Radius.circular(_lensRadius + _gapWidth),
      ),
      Paint()..color = _gap,
    );

    final lensRect = gapRect
        .deflate(_gapWidth)
        .translate(0, pressed ? _pressDepth : 0);
    final lens = RRect.fromRectAndRadius(
      lensRect,
      const Radius.circular(_lensRadius),
    );
    canvas.save();
    canvas.clipRRect(lens);
    _paintLens(canvas, lensRect);
    _paintLamps(canvas, lensRect);
    _paintFrost(canvas, lensRect);
    canvas.restore();
    _paintLensEdge(canvas, lens, lensRect);
  }

  // A brass halo around the bezel, the same lamp-on-metal catch the machined
  // knob uses for keyboard focus.
  void _paintFocusHalo(Canvas canvas, Rect rect) {
    final glow = focusGlow;
    if (glow == null) return;
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        rect.inflate(3.5),
        const Radius.circular(_outerRadius + 3.5),
      ),
      Paint()
        ..color = glow.withValues(alpha: .5)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 5),
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        rect.inflate(1.7),
        const Radius.circular(_outerRadius + 1.7),
      ),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.6
        ..color = glow.withValues(alpha: .85),
    );
  }

  // The shadow the indicator casts on the panel, and the little light a lit
  // lens throws back onto it — a real lamp behind a diffuser spills, but
  // not much.
  void _paintSeating(Canvas canvas, Rect rect, RRect outer) {
    canvas.drawRRect(
      outer.shift(const Offset(0, 2)),
      Paint()
        ..color = _keyShadow.withValues(alpha: dark ? .55 : .3)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4.5),
    );
    if (lit <= 0) return;
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        rect.inflate(1.5),
        const Radius.circular(_outerRadius + 1.5),
      ),
      Paint()
        ..color = _spill.withValues(alpha: (dark ? .22 : .14) * glow)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 9),
    );
  }

  // Matte charcoal, with the light catching its top and left edges and its
  // bottom and right edges turning away.
  void _paintBezel(Canvas canvas, Rect rect, RRect outer) {
    canvas.drawRRect(
      outer,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: <Color>[_bezelTop, _bezelBottom],
        ).createShader(rect),
    );
    // The bevel: one hairline inside the outer edge, lit at top-left.
    canvas.drawRRect(
      outer.deflate(.6),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1
        ..shader = LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: <Color>[
            Colors.white.withValues(alpha: dark ? .16 : .24),
            Colors.white.withValues(alpha: .03),
            Colors.black.withValues(alpha: .35),
          ],
          stops: const <double>[0, .5, 1],
        ).createShader(rect),
    );
    // The outer keyline where the frame meets the panel.
    canvas.drawRRect(
      outer,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1
        ..color = Colors.black.withValues(alpha: dark ? .6 : .42),
    );
  }

  // The frosted block itself: dusty plum lit by the room, or glowing plum-
  // magenta with the lamps on. A diffuser scatters light evenly, so the
  // body is a gentle top-to-bottom gradient and nothing more.
  void _paintLens(Canvas canvas, Rect lensRect) {
    canvas.drawRect(
      lensRect,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: <Color>[
            _lift(Color.lerp(_lensTopIdle, _lensTopLit, body)!),
            _lift(Color.lerp(_lensBottomIdle, _lensBottomLit, body)!),
          ],
        ).createShader(lensRect),
    );
    // The diffuser lightens toward the middle even with the lamps off.
    canvas.drawRect(
      lensRect,
      Paint()
        ..shader = RadialGradient(
          center: const Alignment(0, .1),
          radius: .9,
          colors: <Color>[
            Colors.white.withValues(alpha: .07),
            Colors.white.withValues(alpha: 0),
          ],
        ).createShader(lensRect),
    );
  }

  // Two incandescent lamps behind the diffuser, a third of the way in from
  // each end and a little below centre, the way the real caps are lit. Wide
  // keys space them further apart; a short key shares one.
  void _paintLamps(Canvas canvas, Rect lensRect) {
    if (lit <= 0) return;
    final width = lensRect.width;
    final height = lensRect.height;
    final centers = width < height * 2.2
        ? <Offset>[lensRect.center.translate(0, height * .08)]
        : <Offset>[
            Offset(lensRect.left + width * .3, lensRect.top + height * .58),
            Offset(lensRect.left + width * .7, lensRect.top + height * .58),
          ];
    // The lamps' glow, wide and soft.
    for (final center in centers) {
      final radius = math.max(height * 1.15, width * .34);
      canvas.drawCircle(
        center,
        radius,
        Paint()
          ..shader = RadialGradient(
            colors: <Color>[
              _lamp.withValues(alpha: .55 * glow),
              _lamp.withValues(alpha: .2 * glow),
              _lamp.withValues(alpha: 0),
            ],
            stops: const <double>[0, .45, 1],
          ).createShader(Rect.fromCircle(center: center, radius: radius)),
      );
    }
    // The hot spots where the filaments sit closest to the diffuser.
    for (final center in centers) {
      final radius = height * .42;
      canvas.drawCircle(
        center,
        radius,
        Paint()
          ..shader = RadialGradient(
            colors: <Color>[
              const Color(0xFFFCE3F4).withValues(alpha: .42 * glow),
              _lamp.withValues(alpha: .26 * glow),
              _lamp.withValues(alpha: 0),
            ],
            stops: const <double>[0, .35, 1],
          ).createShader(Rect.fromCircle(center: center, radius: radius)),
      );
    }
    // The thick edges of the block stay a little darker than its middle.
    canvas.drawRect(
      lensRect,
      Paint()
        ..shader = LinearGradient(
          colors: <Color>[
            _shade.withValues(alpha: .28 * lit),
            _shade.withValues(alpha: 0),
            _shade.withValues(alpha: 0),
            _shade.withValues(alpha: .28 * lit),
          ],
          stops: const <double>[0, .18, .82, 1],
        ).createShader(lensRect),
    );
  }

  // Frosted plastic has tooth: a fine, even speckle over the whole lens.
  void _paintFrost(Canvas canvas, Rect lensRect) {
    final light = <Offset>[];
    final deep = <Offset>[];
    for (var i = 0; i < _frost.length; i++) {
      final point = lensRect.topLeft.translate(
        _frost[i].dx * lensRect.width,
        _frost[i].dy * lensRect.height,
      );
      (i.isEven ? light : deep).add(point);
    }
    canvas.drawPoints(
      ui.PointMode.points,
      light,
      Paint()
        ..color = Colors.white.withValues(alpha: .05 + .03 * lit)
        ..strokeWidth = .9,
    );
    canvas.drawPoints(
      ui.PointMode.points,
      deep,
      Paint()
        ..color = _shade.withValues(alpha: .06)
        ..strokeWidth = .9,
    );
  }

  // The moulded edge of the cap: a small radius that catches the room light
  // along its top and left and falls into shadow along its bottom and right.
  void _paintLensEdge(Canvas canvas, RRect lens, Rect lensRect) {
    canvas.drawRRect(
      lens.deflate(.6),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.1
        ..shader = LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: <Color>[
            Colors.white.withValues(alpha: .26 + .1 * lit),
            Colors.white.withValues(alpha: .04),
            _shade.withValues(alpha: .34),
          ],
          stops: const <double>[0, .55, 1],
        ).createShader(lensRect),
    );
  }

  @override
  bool shouldRepaint(_IndicatorPainter old) =>
      old.dark != dark ||
      old.lit != lit ||
      old.filament != filament ||
      old.hover != hover ||
      old.pressed != pressed ||
      old.focusGlow != focusGlow;
}
