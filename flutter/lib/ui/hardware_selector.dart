import 'package:flutter/material.dart';

import '../app/app_theme.dart';
import 'hardware.dart';

/// A receiver's input selector: a machined brushed-steel bezel framing a
/// recessed readout window, with a small raised key at its right whose
/// engraved chevron says "press to choose".
///
/// The control paints itself — no bitmaps — so it matches the knobs and
/// switches in [hardware.dart] on every platform. The window follows the
/// mode: smoked glass with backlit cream at night, a shadowed cream well
/// with ink on paper, so light mode never sprouts a dark island. The steel
/// stays steel in both.
///
/// It carries no gesture of its own. The tap belongs to whatever wraps it —
/// typically a [PopupMenuButton] whose `child` this is — so hover and press
/// are read through [MouseRegion] and [Listener], which do not enter the
/// gesture arena.

/// Bezel thickness: the machined lip around the window and the key.
const double _bezel = 7;

/// Outer and inner corner radii of the faceplate.
const double _outerRadius = 12;
const double _windowRadius = 7;

/// Width of the chamfered wall where the window is cut into the plate.
const double _chamfer = 1.2;

/// The chevron key's drawn size and its gap from the readout window. It is
/// taller than it is wide, the way a receiver's step key is.
const double _keyWidth = 30;
const double _keyHeight = 38;
const double _keyGap = 8;
const double _keyRadius = 6;

/// Padding from the window's edges to the readout content.
const double _contentLeft = 12;
const double _contentRight = 11;

/// How long a hover or press takes to settle. One calm pace.
const Duration _settle = Duration(milliseconds: 140);

/// The faceplate's base tone: the average of [brushedSteelStops], settled a
/// little so the plate reads as metal beside paper and does not glare in an
/// evening room. Neutral in both, never blue-cast.
/// Fine straight machining. A repeating gradient rather than drawn lines, so
/// the brushing stays sub-pixel at 1×, 2× and 3× instead of banding into
/// corrugation. [alongX] runs the strokes vertically, the way a small key is
/// finished; the faceplate is brushed the long way instead.
Shader _brushing(Rect rect, {required bool alongX, required double alpha}) {
  const period = 2.4;
  return LinearGradient(
    begin: alongX ? Alignment.centerLeft : Alignment.topCenter,
    end: alongX ? Alignment.centerRight : Alignment.bottomCenter,
    tileMode: TileMode.repeated,
    colors: <Color>[
      Colors.white.withValues(alpha: alpha),
      Colors.white.withValues(alpha: 0),
      Colors.black.withValues(alpha: alpha),
      Colors.black.withValues(alpha: 0),
      Colors.white.withValues(alpha: alpha),
    ],
    stops: const <double>[0, .25, .5, .75, 1],
  ).createShader(
    alongX
        ? Rect.fromLTWH(rect.left, rect.top, period, rect.height)
        : Rect.fromLTWH(rect.left, rect.top, rect.width, period),
  );
}

Color _steelBase(Brightness brightness) => brightness == Brightness.dark
    ? const Color(0xFF7B7A78)
    : const Color(0xFFC3C4C2);

/// The colors a readout window is written in, resolved for the mode.
///
/// Callers style their own content — the selector only guarantees the
/// surface underneath it — so they ask here rather than reaching past the
/// window into the theme.
@immutable
class HardwareSelectorInk {
  const HardwareSelectorInk({
    required this.on,
    required this.onMuted,
    required this.accent,
    required this.glow,
  });

  /// Primary text in the window: backlit cream at night, ink on paper.
  final Color on;

  /// Secondary text in the window.
  final Color onMuted;

  /// Brass, for the small etched mark beside the text.
  final Color accent;

  /// The faint halo backlit text throws. Empty in light mode, where the
  /// window is a paper well rather than a lamp.
  final List<Shadow> glow;
}

class HardwareSelector extends StatefulWidget {
  const HardwareSelector({
    required this.child,
    super.key,
    this.height = kConsoleControlHeight,
    this.minWidth = 220,
    this.pressed = false,
    this.semanticHint,
  });

  /// The readout content, drawn inside the window and vertically centred.
  /// Let it ellipsize: the window narrows when the composer does.
  final Widget child;

  /// The faceplate height. Shoulder to shoulder with the Generate key.
  final double height;

  /// The narrowest the faceplate may be when it hugs its content. A tight
  /// parent still wins, so a stretched footer can make it any width.
  final double minWidth;

  /// Lets an owner that already tracks the press state drive the key's sink;
  /// otherwise the selector reads pointers itself.
  final bool pressed;

  /// Spoken after the wrapping button's label, e.g. 'Opens the provider and
  /// model menu'.
  final String? semanticHint;

  /// The window's vertical gradient for [brightness]: the pale counter-window
  /// cream on paper, warm smoked glass with a breath of navy at night.
  @visibleForTesting
  static List<Color> windowGradient(Brightness brightness) =>
      brightness == Brightness.dark
      ? const <Color>[Color(0xFF17110F), Color(0xFF281F21)]
      : const <Color>[Color(0xFFE6DBC3), Color(0xFFF6F0E0)];

  /// The ink a readout window is written in under this room's light.
  static HardwareSelectorInk inkOf(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return HardwareSelectorInk(
      on: dark ? ClawnsoleColors.cream : context.colors.onSurface,
      onMuted: dark
          ? ClawnsoleColors.creamMuted
          : context.colors.onSurfaceVariant,
      accent: dark ? ClawnsoleColors.brassBright : context.tokens.brass,
      glow: dark
          ? <Shadow>[
              Shadow(
                color: ClawnsoleColors.cream.withValues(alpha: .26),
                blurRadius: 5,
              ),
            ]
          : const <Shadow>[],
    );
  }

  @override
  State<HardwareSelector> createState() => _HardwareSelectorState();
}

class _HardwareSelectorState extends State<HardwareSelector> {
  bool _hovered = false;
  bool _pressed = false;

  bool get _isPressed => widget.pressed || _pressed;

  void _setPressed(bool value) {
    if (_pressed == value) return;
    setState(() => _pressed = value);
  }

  void _setHovered(bool value) {
    if (_hovered == value) return;
    setState(() => _hovered = value);
  }

  @override
  Widget build(BuildContext context) {
    final brightness = Theme.of(context).brightness;
    final dark = brightness == Brightness.dark;

    // Cached: the readout content does not change with hover or press.
    final content = Padding(
      padding: const EdgeInsets.fromLTRB(
        _bezel + _contentLeft,
        _bezel,
        _bezel + _keyWidth + _keyGap + _contentRight,
        _bezel,
      ),
      // Hugs its content when the parent is loose, and keeps the readout
      // flush left — ellipsizing — when a stretched footer widens it.
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[Flexible(child: widget.child)],
      ),
    );

    final Widget plate = TweenAnimationBuilder<double>(
      tween: Tween<double>(end: _hovered ? 1 : 0),
      duration: _settle,
      curve: Curves.easeOut,
      builder: (context, hover, _) => TweenAnimationBuilder<double>(
        tween: Tween<double>(end: _isPressed ? 1 : 0),
        duration: _settle,
        curve: Curves.easeOut,
        builder: (context, press, child) => DecoratedBox(
          // The faceplate stands proud of the composer card, warmly.
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(_outerRadius),
            boxShadow: <BoxShadow>[
              BoxShadow(
                color: dark
                    ? Colors.black.withValues(alpha: .5)
                    : const Color(0xFF3A2E22).withValues(alpha: .28),
                blurRadius: 10,
                offset: const Offset(0, 3),
              ),
            ],
          ),
          child: CustomPaint(
            key: const ValueKey<String>('hardware-selector-frame'),
            painter: HardwareSelectorFramePainter(brightness: brightness),
            child: Stack(
              children: <Widget>[
                child!,
                Positioned(
                  right: _bezel,
                  top: (widget.height - _keyHeight) / 2,
                  width: _keyWidth,
                  height: _keyHeight,
                  child: CustomPaint(
                    key: const ValueKey<String>('hardware-selector-chevron'),
                    painter: HardwareSelectorKeyPainter(
                      brightness: brightness,
                      hover: hover,
                      press: press,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        child: content,
      ),
    );

    final Widget sized = SizedBox(
      height: widget.height,
      child: ConstrainedBox(
        constraints: BoxConstraints(minWidth: widget.minWidth),
        child: plate,
      ),
    );

    // Listener and MouseRegion watch pointers without entering the gesture
    // arena, so the enclosing button still owns the tap.
    final Widget watched = MouseRegion(
      onEnter: (_) => _setHovered(true),
      onExit: (_) => _setHovered(false),
      child: Listener(
        onPointerDown: (_) {
          hardwareSelectionFeedback();
          _setPressed(true);
        },
        onPointerUp: (_) => _setPressed(false),
        onPointerCancel: (_) => _setPressed(false),
        child: sized,
      ),
    );

    final hint = widget.semanticHint;
    return hint == null ? watched : Semantics(hint: hint, child: watched);
  }
}

/// Paints the faceplate: brushed-steel bezel, machined lip, and the recessed
/// readout window cut into it. The chevron key paints itself, on top.
class HardwareSelectorFramePainter extends CustomPainter {
  const HardwareSelectorFramePainter({required this.brightness});

  final Brightness brightness;

  /// The window gradient actually painted, so a test can read the surface
  /// rather than trust the theme.
  List<Color> get windowColors => HardwareSelector.windowGradient(brightness);

  @override
  void paint(Canvas canvas, Size size) {
    final dark = brightness == Brightness.dark;
    final rect = Offset.zero & size;
    final outer = RRect.fromRectAndRadius(
      rect.deflate(.5),
      const Radius.circular(_outerRadius),
    );

    _paintBezel(canvas, rect, outer, dark: dark);
    _paintWindow(canvas, size, dark: dark);

    // Dark outer keyline: where the plate meets the card.
    canvas.drawRRect(
      outer,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1
        ..color = Colors.black.withValues(alpha: dark ? .5 : .38),
    );
  }

  void _paintBezel(
    Canvas canvas,
    Rect rect,
    RRect outer, {
    required bool dark,
  }) {
    // Slow variation along the plate's length, from the same steel stock as
    // the knobs but muted: the machining reads in the hairlines, not here.
    final base = _steelBase(brightness);
    final plate = <Color>[
      for (final Color color in brushedSteelStops(brightness))
        Color.lerp(color, base, .62)!,
    ];
    canvas.drawRRect(
      outer,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.centerLeft,
          end: Alignment.centerRight,
          colors: plate,
        ).createShader(rect),
    );

    // The lip: light falls on the top edge, the bottom turns away.
    canvas.drawRRect(
      outer,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: <Color>[
            Colors.white.withValues(alpha: dark ? .14 : .2),
            Colors.white.withValues(alpha: 0),
            Colors.black.withValues(alpha: .04),
            Colors.black.withValues(alpha: dark ? .32 : .18),
          ],
          stops: const <double>[0, .16, .74, 1],
        ).createShader(rect),
    );

    // Straight horizontal brushing, the long way down the plate.
    canvas.drawRRect(
      outer,
      Paint()..shader = _brushing(rect, alongX: false, alpha: dark ? .06 : .07),
    );

    // The machined rim, following the corners.
    canvas.drawRRect(
      outer.deflate(1),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.2
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: <Color>[
            Colors.white.withValues(alpha: dark ? .24 : .4),
            Colors.white.withValues(alpha: 0),
            Colors.black.withValues(alpha: .2),
          ],
          stops: const <double>[0, .45, 1],
        ).createShader(rect),
    );
  }

  void _paintWindow(Canvas canvas, Size size, {required bool dark}) {
    final windowRect = Rect.fromLTRB(
      _bezel + _chamfer,
      _bezel + _chamfer,
      size.width - _bezel - _keyWidth - _keyGap - _chamfer,
      size.height - _bezel - _chamfer,
    );
    if (windowRect.width <= _windowRadius * 2 || windowRect.height <= 4) return;
    final window = RRect.fromRectAndRadius(
      windowRect,
      const Radius.circular(_windowRadius),
    );
    final base = _steelBase(brightness);
    final chamferRect = windowRect.inflate(_chamfer);
    final chamfer = RRect.fromRectAndRadius(
      chamferRect,
      const Radius.circular(_windowRadius + _chamfer),
    );

    // A whisper of occlusion where the cut meets the plate.
    canvas.drawRRect(
      chamfer.inflate(1),
      Paint()
        ..color = Colors.black.withValues(alpha: dark ? .3 : .16)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 1.8),
    );

    // The chamfered wall of the cut: its top wall is in shadow, its lower
    // wall catches one thin line of the room. This is what makes the window
    // read as milled out of the plate rather than drawn on it.
    canvas.drawRRect(
      chamfer,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: <Color>[
            Color.lerp(base, Colors.black, dark ? .76 : .6)!,
            Color.lerp(base, Colors.black, dark ? .46 : .3)!,
            Color.lerp(base, Colors.black, dark ? .24 : .12)!,
            Color.lerp(base, Colors.white, dark ? .2 : .2)!,
          ],
          stops: const <double>[0, .45, .8, 1],
        ).createShader(chamferRect),
    );

    canvas.drawRRect(
      window,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: windowColors,
        ).createShader(windowRect),
    );

    canvas.save();
    canvas.clipRRect(window);
    final wellShadow = hardwareWellShadowAlpha(brightness);
    // Recessed: the top edge shades itself, the left a little.
    canvas.drawRect(
      windowRect,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: <Color>[
            Colors.black.withValues(alpha: wellShadow),
            Colors.black.withValues(alpha: 0),
          ],
          stops: const <double>[0, .34],
        ).createShader(windowRect),
    );
    canvas.drawRect(
      windowRect,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.centerLeft,
          end: Alignment.centerRight,
          colors: <Color>[
            Colors.black.withValues(alpha: wellShadow * .6),
            Colors.black.withValues(alpha: 0),
          ],
          stops: const <double>[0, .05],
        ).createShader(windowRect),
    );

    if (dark) {
      // Glass: one shallow reflection across the top, nothing that moves.
      final glass = Rect.fromLTWH(
        windowRect.left,
        windowRect.top,
        windowRect.width,
        windowRect.height * .34,
      );
      canvas.drawRect(
        glass,
        Paint()
          ..shader = LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: <Color>[
              Colors.white.withValues(alpha: .085),
              Colors.white.withValues(alpha: 0),
            ],
          ).createShader(glass),
      );
    }

    // The bottom lip catches the room light.
    canvas.drawRect(
      Rect.fromLTRB(
        windowRect.left,
        windowRect.bottom - 1.2,
        windowRect.right,
        windowRect.bottom,
      ),
      Paint()..color = Colors.white.withValues(alpha: dark ? .05 : .34),
    );
    canvas.restore();

    canvas.drawRRect(
      window.deflate(.4),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = .8
        ..color = dark
            ? Colors.black.withValues(alpha: .5)
            : const Color(0xFFC5B79E),
    );
  }

  @override
  bool shouldRepaint(HardwareSelectorFramePainter oldDelegate) =>
      oldDelegate.brightness != brightness;
}

/// The raised key at the right of the faceplate: brushed steel with a chevron
/// cut into it. Brightens under the cursor, sinks a pixel under the finger.
class HardwareSelectorKeyPainter extends CustomPainter {
  const HardwareSelectorKeyPainter({
    required this.brightness,
    required this.hover,
    required this.press,
  });

  final Brightness brightness;

  /// How far the cursor's brightening has settled, 0 to 1.
  final double hover;

  /// How far the key has sunk under a finger, 0 to 1.
  final double press;

  @override
  void paint(Canvas canvas, Size size) {
    final dark = brightness == Brightness.dark;
    final base = _steelBase(brightness);
    final keyRect = (Offset.zero & size).translate(0, press * 1.5);
    final key = RRect.fromRectAndRadius(
      keyRect,
      const Radius.circular(_keyRadius),
    );

    // Its own shadow, which shortens as the key sinks.
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        keyRect.translate(0, 2.4 - press * 1.6),
        const Radius.circular(_keyRadius),
      ),
      Paint()
        ..color = Colors.black.withValues(alpha: dark ? .55 : .38)
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, 3.2 - press * 1.4),
    );

    canvas.drawRRect(
      key,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: <Color>[
            Color.lerp(base, Colors.white, dark ? .3 : .42)!,
            base,
            Color.lerp(base, Colors.black, dark ? .28 : .22)!,
          ],
          stops: const <double>[0, .55, 1],
        ).createShader(keyRect),
    );

    // Vertical brushing, the way a small key is finished across its face.
    canvas.save();
    canvas.clipRRect(key);
    canvas.drawRect(
      keyRect,
      Paint()..shader = _brushing(keyRect, alongX: true, alpha: .05),
    );
    if (hover > 0) {
      canvas.drawRect(
        keyRect,
        Paint()..color = Colors.white.withValues(alpha: .07 * hover),
      );
    }
    if (press > 0) {
      canvas.drawRect(
        keyRect,
        Paint()..color = Colors.black.withValues(alpha: .09 * press),
      );
    }
    canvas.restore();

    // Machined rim, then the keyline that separates it from the plate.
    canvas.drawRRect(
      key.deflate(.6),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: <Color>[
            Colors.white.withValues(alpha: dark ? .3 : .44),
            Colors.white.withValues(alpha: 0),
            Colors.black.withValues(alpha: .2),
          ],
          stops: const <double>[0, .5, 1],
        ).createShader(keyRect),
    );
    canvas.drawRRect(
      key,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1
        ..color = Colors.black.withValues(alpha: dark ? .5 : .42),
    );

    // The chevron is cut into the metal: a dark groove with the light
    // catching its lower wall.
    final center = keyRect.center;
    Path chevron(double dy) => Path()
      ..moveTo(center.dx - 5.5, center.dy - 2.4 + dy)
      ..lineTo(center.dx, center.dy + 3.1 + dy)
      ..lineTo(center.dx + 5.5, center.dy - 2.4 + dy);
    Paint cut(Color color) => Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.7
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..color = color;
    canvas.drawPath(
      chevron(1),
      cut(Colors.white.withValues(alpha: dark ? .42 : .62)),
    );
    canvas.drawPath(chevron(0), cut(Colors.black.withValues(alpha: .62)));
  }

  @override
  bool shouldRepaint(HardwareSelectorKeyPainter oldDelegate) =>
      oldDelegate.brightness != brightness ||
      oldDelegate.hover != hover ||
      oldDelegate.press != press;
}
