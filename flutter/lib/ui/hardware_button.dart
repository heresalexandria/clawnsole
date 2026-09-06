// The transport key: a wide translucent plum acrylic push key seated in a
// dark bezel, the way the Play key sits on a 1970s receiver.
//
// Everything is drawn in code — body gradient, inner glow, specular cap,
// refraction line, grain — so it renders identically at 1×, 2× and 3× and on
// every platform. The plastic is the same plum in both appearance modes (a
// button is one of the two things allowed to stay dark on paper); only the
// bezel shadow and the bloom alphas change with the room.

import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../app/app_theme.dart';
import 'hardware.dart';

/// Radius of the bezel's outer corner.
const double _outerRadius = 14;

/// Thickness of the dark bezel ring around the cap.
const double _bezelWidth = 2.6;

/// Radius of the acrylic cap inside the bezel.
const double _capRadius = 11.4;

/// How far the cap sinks into its bezel while held.
const double _pressDepth = 1;

/// Narrowest a key ever draws, so a short label still reads as a key.
const double _minKeyWidth = 170;

// ---------------------------------------------------------------------------
// Colour anchors for the plastic. Plum in both modes, never blue.
// ---------------------------------------------------------------------------

// Bezel: warm near-black, the moulded frame the key is seated in.
const _bezelTop = Color(0xFF1A1210);
const _bezelBottom = Color(0xFF0E0907);

// Body of the cap, light passing down through the block.
const _bodyTopIdle = Color(0xFF643760);
const _bodyMidIdle = Color(0xFF532B4E);
const _bodyBottomIdle = Color(0xFF341831);
const _bodyTopLit = Color(0xFF8E3E86);
const _bodyMidLit = Color(0xFF7A3572);
const _bodyBottomLit = Color(0xFF5A2A55);

// The lamp behind the plastic.
const _glowIdle = Color(0xFF7A4270);
const _glowLit = Color(0xFFB85AA6);

// Light refracting out along the bottom lip.
const _refractIdle = Color(0xFF9A4C8C);
const _refractLit = Color(0xFFE264C9);

// Spill onto the faceplate around a lit key.
const _bloom = Color(0xFFB85AA6);

// Warm black for edge shading; a neutral black would cool the plum.
const _shade = Color(0xFF160C13);
const _keyShadow = Color(0xFF120C08);

/// Cream ink, matching `onPrimary`.
const _keyInk = Color(0xFFFBF3E6);

/// A fixed speckle pattern in unit space, so the moulded plastic has a little
/// tooth instead of reading as flat vector art. Generated once, mapped onto
/// whatever size the key ends up.
final List<Offset> _grain = () {
  final random = math.Random(0x5C0A7);
  return List<Offset>.generate(
    360,
    (_) => Offset(random.nextDouble(), random.nextDouble()),
  );
}();

/// A wide, lit, translucent plum push key.
///
/// [lit] is the studio's "working" signal: the key stays lit while a render is
/// in flight even though [onPressed] is null, so nothing has to spin.
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

  /// The engraved legend. Rendered as a plain [Text].
  final String label;

  /// Null disables the key: it dims and stops taking taps and hover.
  final VoidCallback? onPressed;

  /// A leading mark, usually the claw.
  final Widget? icon;

  /// Holds the lamp on regardless of [onPressed].
  final bool lit;

  /// Drawn height. Matches the model plaque so the faceplate lines up.
  final double height;

  /// Defaults to [label].
  final String? semanticLabel;

  @override
  State<HardwareLitButton> createState() => HardwareLitButtonState();
}

/// Public so tests can read the lamp without screen-scraping pixels.
class HardwareLitButtonState extends State<HardwareLitButton>
    with TickerProviderStateMixin {
  late final AnimationController _lamp = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 140),
    reverseDuration: const Duration(milliseconds: 280),
    value: widget.lit ? 1 : 0,
  );
  late final AnimationController _hoverLift = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 140),
    reverseDuration: const Duration(milliseconds: 200),
  );

  bool _pressed = false;
  bool _focused = false;

  bool get _enabled => widget.onPressed != null;

  /// How lit the plastic is right now, 0 (dark) to 1 (full lamp).
  @visibleForTesting
  double get litAmount => _lamp.value;

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
    _lamp.dispose();
    _hoverLift.dispose();
    super.dispose();
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
    final label = Text(
      widget.label,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      textAlign: TextAlign.center,
      style: (Theme.of(context).textTheme.labelLarge ?? const TextStyle())
          .copyWith(
            fontSize: 13.5,
            fontWeight: FontWeight.w700,
            letterSpacing: .1,
            height: 1.05,
            color: _keyInk,
            // A whisper of shadow so the legend sits *in* the plastic.
            shadows: const <Shadow>[
              Shadow(color: Color(0x73170C15), offset: Offset(0, 1)),
            ],
          ),
    );

    final content = Padding(
      padding: const EdgeInsets.symmetric(horizontal: 22),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        mainAxisAlignment: MainAxisAlignment.center,
        children: <Widget>[
          if (widget.icon != null) ...<Widget>[
            widget.icon!,
            const SizedBox(width: 9),
          ],
          Flexible(child: label),
        ],
      ),
    );

    final face = AnimatedBuilder(
      animation: Listenable.merge(<Listenable>[_lamp, _hoverLift]),
      builder: (context, child) => CustomPaint(
        painter: _HardwareKeyPainter(
          dark: dark,
          lit: _lamp.value,
          hover: _hoverLift.value,
          pressed: _pressed,
          focusGlow: _focused ? context.tokens.brass : null,
        ),
        child: child,
      ),
      // widthFactor 1 hugs the legend when the parent leaves room, and still
      // fills a stretched column, where the incoming width is tight.
      child: Center(
        widthFactor: 1,
        child: Transform.translate(
          offset: Offset(0, _pressed ? _pressDepth : 0),
          child: content,
        ),
      ),
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

class _HardwareKeyPainter extends CustomPainter {
  const _HardwareKeyPainter({
    required this.dark,
    required this.lit,
    required this.hover,
    required this.pressed,
    required this.focusGlow,
  });

  final bool dark;
  final double lit;
  final double hover;
  final bool pressed;
  final Color? focusGlow;

  /// Hover is a 5 % lift in the plastic, not a colour change.
  Color _lift(Color color) => Color.lerp(color, Colors.white, .06 * hover)!;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final outer = RRect.fromRectAndRadius(
      rect,
      const Radius.circular(_outerRadius),
    );

    _paintFocusHalo(canvas, rect, outer);
    _paintSeating(canvas, rect, outer);
    _paintBezel(canvas, rect, outer);

    final capRect = rect
        .deflate(_bezelWidth)
        .translate(0, pressed ? _pressDepth : 0);
    final cap = RRect.fromRectAndRadius(
      capRect,
      const Radius.circular(_capRadius),
    );
    canvas.save();
    canvas.clipRRect(cap);
    _paintBody(canvas, capRect);
    _paintLamp(canvas, capRect);
    _paintVignette(canvas, capRect);
    _paintMoulding(canvas, capRect);
    _paintRefraction(canvas, capRect);
    _paintGloss(canvas, capRect);
    _paintGrain(canvas, capRect);
    canvas.restore();
  }

  // A brass halo around the bezel, the same lamp-on-metal catch the machined
  // knob uses for keyboard focus.
  void _paintFocusHalo(Canvas canvas, Rect rect, RRect outer) {
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

  // The warm shadow the key casts on the composer card, and the plum spill a
  // lit key throws back onto the faceplate.
  void _paintSeating(Canvas canvas, Rect rect, RRect outer) {
    canvas.drawRRect(
      outer.shift(Offset(0, pressed ? 1.6 : 3.4)),
      Paint()
        ..color = _keyShadow.withValues(alpha: dark ? .5 : .28)
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, pressed ? 4.5 : 8),
    );
    if (lit <= 0) return;
    final bloom = (dark ? .5 : .35) * lit;
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        rect.inflate(2),
        const Radius.circular(_outerRadius + 2),
      ),
      Paint()
        ..color = _bloom.withValues(alpha: bloom)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 14),
    );
    canvas.drawRRect(
      outer,
      Paint()
        ..color = _bloom.withValues(alpha: bloom * .65)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6),
    );
  }

  // The moulded frame: near-black, with a hairline catch along its bottom lip
  // where the room light grazes it.
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
    canvas.drawRRect(
      outer.deflate(.5),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: <Color>[
            Colors.transparent,
            Colors.white.withValues(alpha: dark ? .13 : .2),
          ],
          stops: const <double>[.62, 1],
        ).createShader(rect),
    );
  }

  // Light passing down through the block: brighter at the top face, deeper at
  // the bottom where the plastic is thickest.
  void _paintBody(Canvas canvas, Rect capRect) {
    canvas.drawRect(
      capRect,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: <Color>[
            _lift(Color.lerp(_bodyTopIdle, _bodyTopLit, lit)!),
            _lift(Color.lerp(_bodyMidIdle, _bodyMidLit, lit)!),
            _lift(Color.lerp(_bodyBottomIdle, _bodyBottomLit, lit)!),
          ],
          stops: const <double>[0, .55, 1],
        ).createShader(capRect),
    );
  }

  // The lamp itself, sitting a little below centre inside the plastic.
  void _paintLamp(Canvas canvas, Rect capRect) {
    final color = Color.lerp(_glowIdle, _glowLit, lit)!;
    final alpha = ui.lerpDouble(.2, .95, lit)! * (1 + .08 * hover);
    final center = capRect.center.translate(0, capRect.height * .16);
    final radiusY = capRect.height * .95;
    final radiusX = math.max(radiusY, capRect.width * .58);
    canvas.save();
    canvas.translate(center.dx, center.dy);
    canvas.scale(radiusX / radiusY, 1);
    canvas.translate(-center.dx, -center.dy);
    canvas.drawRect(
      Rect.fromCenter(center: center, width: 4000, height: 4000),
      Paint()
        ..shader = RadialGradient(
          colors: <Color>[
            color.withValues(alpha: alpha.clamp(0, 1)),
            color.withValues(alpha: (alpha * .42).clamp(0, 1)),
            color.withValues(alpha: 0),
          ],
          stops: const <double>[0, .46, 1],
        ).createShader(Rect.fromCircle(center: center, radius: radiusY)),
    );
    canvas.restore();
  }

  // Edge darkening: the block is thick, so its sides swallow the light, and
  // the last sliver above the bottom edge falls away before the refraction
  // line picks the light back up.
  void _paintVignette(Canvas canvas, Rect capRect) {
    canvas.drawRect(
      capRect,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: <Color>[
            _shade.withValues(alpha: 0),
            _shade.withValues(alpha: 0),
            _shade.withValues(alpha: .3),
          ],
          stops: const <double>[0, .84, 1],
        ).createShader(capRect),
    );
    final edge = math.min(.26, 24 / capRect.width);
    canvas.drawRect(
      capRect,
      Paint()
        ..shader = LinearGradient(
          colors: <Color>[
            _shade.withValues(alpha: .46),
            _shade.withValues(alpha: 0),
            _shade.withValues(alpha: 0),
            _shade.withValues(alpha: .46),
          ],
          stops: <double>[0, edge, 1 - edge, 1],
        ).createShader(capRect),
    );
  }

  // The inner face of the moulding, a step in from the cap's edge.
  void _paintMoulding(Canvas canvas, Rect capRect) {
    canvas.drawRRect(
      RRect.fromRectAndRadius(capRect.deflate(4.5), const Radius.circular(8.5)),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: <Color>[
            Colors.white.withValues(alpha: .09),
            Colors.white.withValues(alpha: 0),
            Color.lerp(
              _refractIdle,
              _refractLit,
              lit,
            )!.withValues(alpha: .12 + .16 * lit),
          ],
          stops: const <double>[0, .5, 1],
        ).createShader(capRect),
    );
  }

  // Light finding its way out along the bottom lip and wrapping the corners.
  void _paintRefraction(Canvas canvas, Rect capRect) {
    final color = Color.lerp(_refractIdle, _refractLit, lit)!;
    final alpha = ui.lerpDouble(.5, 1, lit)!;
    final line = RRect.fromRectAndRadius(
      capRect.deflate(2.2),
      const Radius.circular(_capRadius - 2.2),
    );
    LinearGradient bottomOnly(double a) => LinearGradient(
      begin: Alignment.topCenter,
      end: Alignment.bottomCenter,
      colors: <Color>[
        color.withValues(alpha: 0),
        color.withValues(alpha: 0),
        color.withValues(alpha: a.clamp(0, 1)),
      ],
      stops: const <double>[0, .68, 1],
    );
    canvas.drawRRect(
      line,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.4
        ..shader = bottomOnly(alpha * .32).createShader(capRect)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 2.2),
    );
    canvas.drawRRect(
      line,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.4
        ..shader = bottomOnly(alpha).createShader(capRect),
    );
  }

  // The glossy top face: a soft sheen over the upper third and the hard
  // white line where the cap's crown catches the room light.
  void _paintGloss(Canvas canvas, Rect capRect) {
    final sheenRect = Rect.fromLTWH(
      capRect.left + 4,
      capRect.top + .8,
      capRect.width - 8,
      capRect.height * .34,
    );
    canvas.drawRRect(
      RRect.fromRectAndCorners(
        sheenRect,
        topLeft: const Radius.circular(9),
        topRight: const Radius.circular(9),
        bottomLeft: const Radius.circular(11),
        bottomRight: const Radius.circular(11),
      ),
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: <Color>[
            Colors.white.withValues(alpha: .42),
            Colors.white.withValues(alpha: .16),
            Colors.white.withValues(alpha: .04),
            Colors.white.withValues(alpha: 0),
          ],
          stops: const <double>[0, .38, .78, 1],
        ).createShader(sheenRect)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 2),
    );

    // The crown: the hard white line where the moulded top face turns over.
    final crown = Rect.fromLTWH(
      capRect.left + 5,
      capRect.top + .9,
      capRect.width - 10,
      1.9,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(crown, const Radius.circular(1)),
      Paint()
        ..shader = LinearGradient(
          colors: <Color>[
            Colors.white.withValues(alpha: .1),
            Colors.white.withValues(alpha: .9),
            Colors.white.withValues(alpha: .96),
            Colors.white.withValues(alpha: .1),
          ],
          stops: const <double>[0, .09, .91, 1],
        ).createShader(crown)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, .55),
    );
  }

  // Moulded plastic has tooth. A fixed speckle keeps it off the vector shelf.
  void _paintGrain(Canvas canvas, Rect capRect) {
    final light = <Offset>[];
    final deep = <Offset>[];
    for (var i = 0; i < _grain.length; i++) {
      final point = capRect.topLeft.translate(
        _grain[i].dx * capRect.width,
        _grain[i].dy * capRect.height,
      );
      (i.isEven ? light : deep).add(point);
    }
    canvas.drawPoints(
      ui.PointMode.points,
      light,
      Paint()
        ..color = Colors.white.withValues(alpha: .035)
        ..strokeWidth = .8,
    );
    canvas.drawPoints(
      ui.PointMode.points,
      deep,
      Paint()
        ..color = _shade.withValues(alpha: .04)
        ..strokeWidth = .8,
    );
  }

  @override
  bool shouldRepaint(_HardwareKeyPainter old) =>
      old.dark != dark ||
      old.lit != lit ||
      old.hover != hover ||
      old.pressed != pressed ||
      old.focusGlow != focusGlow;
}
