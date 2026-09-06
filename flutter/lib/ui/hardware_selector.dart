// The model selector: an alphanumeric readout of the kind a 1960s command
// center mounted beside its push-button indicators — a smoked-glass display
// window in a charcoal bezel held by four slotted screws, showing segment
// characters with the unlit segments faintly visible behind them, and a
// small square metal key to its right that steps the selection.
//
// The control paints itself — no bitmaps — so it matches the Generate key
// beside it on every platform. The window follows the mode: lit ice-blue
// segments on smoked glass at night; an unlit liquid-crystal pane, dark
// segments on pale glass, on paper — so light mode never sprouts a dark
// island. The bezel and key are metal in both.
//
// It carries no gesture of its own. The tap belongs to whatever wraps it —
// typically a [PopupMenuButton] whose `child` this is — so hover and press
// are read through [MouseRegion] and [Listener], which do not enter the
// gesture arena.

import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'hardware.dart';

/// Bezel thickness: the charcoal frame around the window, wide enough to
/// hold a screw head in each corner.
const double _bezel = 8;

/// Outer corner radius of the plate and the window's own corners.
const double _outerRadius = 6;
const double _windowRadius = 3;

/// The step key's drawn size, its gap from the window, and its inset from
/// the plate's right edge (clear of the corner screws).
const double _keyWidth = 30;
const double _keyHeight = 38;
const double _keyGap = 6;
const double _keyRight = 10;
const double _keyRadius = 3.5;

/// Padding from the window's edges to the readout content.
const double _contentLeft = 11;
const double _contentRight = 9;

/// Screw heads: radius and where they sit in the bezel corners.
const double _screwRadius = 2.4;
const double _screwInset = 4.8;

/// How long a hover or press takes to settle. One calm pace.
const Duration _settle = Duration(milliseconds: 140);

/// The segment display face bundled in `assets/fonts` (DSEG14 Classic).
const String segmentDisplayFontFamily = 'DSEG14 Classic';

// The bezel: matte charcoal, the same stock as the Generate key's frame.
const _bezelTop = Color(0xFF34302E);
const _bezelBottom = Color(0xFF211E1C);

// Satin metal for the step key and the screw heads.
const _metalLight = Color(0xFFC4C1BA);
const _metalMid = Color(0xFF9B9892);
const _metalDark = Color(0xFF6A6863);

// Lit segments at night.
const _segmentLit = Color(0xFFD8F5FF);
const _segmentLitMuted = Color(0xFFA7DBEE);

// Liquid-crystal segments on paper.
const _segmentInk = Color(0xFF1F2724);
const _segmentInkMuted = Color(0xFF465350);

/// Characters DSEG14 can form. Everything else becomes a space.
final Set<int> _segmentGlyphs = <int>{for (var c = 0x20; c < 0x7F; c++) c}
  ..removeAll('#;[]{}'.codeUnits);

/// A string as a fourteen-segment display would show it: capitals, and only
/// the characters the display has segments for. Middle dots and dashes
/// become spaces and hyphens; anything else the display cannot form is
/// dropped to a space. Runs of spaces collapse.
String segmentDisplayText(String text) {
  final buffer = StringBuffer();
  var pendingSpace = false;
  for (final rune in text.toUpperCase().runes) {
    final char = switch (rune) {
      0x00B7 || 0x2022 || 0x2027 => ' ', // · • ‧
      0x2013 || 0x2014 || 0x2212 => '-', // – — −
      0x00D7 => 'X',
      _ => _segmentGlyphs.contains(rune) ? String.fromCharCode(rune) : ' ',
    };
    if (char == ' ') {
      pendingSpace = buffer.isNotEmpty;
      continue;
    }
    if (pendingSpace) buffer.write(' ');
    pendingSpace = false;
    buffer.write(char);
  }
  return buffer.toString();
}

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
    required this.ghost,
    required this.glow,
  });

  /// Lit segments: ice-blue at night, liquid-crystal ink on paper.
  final Color on;

  /// The second line, a little dimmer.
  final Color onMuted;

  /// Small marks beside the text, such as the provider's glyph.
  final Color accent;

  /// The segments that are off, faintly visible behind the lit ones.
  final Color ghost;

  /// The halo lit segments throw. Empty in light mode, where nothing is lit.
  final List<Shadow> glow;
}

/// One line of a segment display: the text in lit segments over the ghost
/// of every segment the display has, so the readout reads as hardware
/// rather than as a typeface.
class SegmentReadout extends StatelessWidget {
  const SegmentReadout(
    this.text, {
    required this.fontSize,
    super.key,
    this.primary = true,
    this.minCells = 0,
  });

  final String text;
  final double fontSize;

  /// The main line is brightest; a secondary line sits a little dimmer.
  final bool primary;

  /// How many character cells the display has at least: the ghost row runs
  /// this far even under a short name, the way a real display's unused
  /// cells stay faintly visible.
  final int minCells;

  /// The ghost row under [shown]: every letter and digit becomes the
  /// all-segments-on glyph, while the narrow cells — spaces, periods,
  /// colons — stay themselves so the two rows keep the same advances and
  /// the lit segments land exactly on their ghosts.
  static String ghostRow(String shown, {int minCells = 0}) {
    final buffer = StringBuffer();
    for (final rune in shown.runes) {
      buffer.write(switch (rune) {
        0x20 || 0x2E || 0x3A || 0x27 || 0x2C => String.fromCharCode(rune),
        _ => '~',
      });
    }
    var cells = shown.runes.length;
    while (cells < minCells) {
      buffer.write('~');
      cells += 1;
    }
    return buffer.toString();
  }

  @override
  Widget build(BuildContext context) {
    final ink = HardwareSelector.inkOf(context);
    final shown = segmentDisplayText(text);
    final style = TextStyle(
      fontFamily: segmentDisplayFontFamily,
      fontSize: fontSize,
      height: 1.2,
      color: primary ? ink.on : ink.onMuted,
      shadows: primary
          ? ink.glow
          : <Shadow>[
              for (final shadow in ink.glow)
                Shadow(
                  color: shadow.color.withValues(alpha: shadow.color.a * .7),
                  blurRadius: shadow.blurRadius,
                ),
            ],
    );
    // `~` is the every-segment-on character; the ghost row mirrors the
    // text's narrow cells so the two stay registered.
    return Stack(
      children: <Widget>[
        ExcludeSemantics(
          child: Text(
            ghostRow(shown, minCells: minCells),
            maxLines: 1,
            softWrap: false,
            overflow: TextOverflow.clip,
            style: style.copyWith(color: ink.ghost, shadows: const <Shadow>[]),
          ),
        ),
        Text(
          shown,
          maxLines: 1,
          softWrap: false,
          overflow: TextOverflow.clip,
          semanticsLabel: text,
          style: style,
        ),
      ],
    );
  }
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
  /// Let it clip: the window narrows when the composer does.
  final Widget child;

  /// The plate height. Shoulder to shoulder with the Generate key.
  final double height;

  /// The narrowest the plate may be when it hugs its content. A tight
  /// parent still wins, so a stretched footer can make it any width.
  final double minWidth;

  /// Lets an owner that already tracks the press state drive the key's sink;
  /// otherwise the selector reads pointers itself.
  final bool pressed;

  /// Spoken after the wrapping button's label, e.g. 'Opens the provider and
  /// model menu'.
  final String? semanticHint;

  /// The window's vertical gradient for [brightness]: smoked glass at night,
  /// an unlit liquid-crystal pane on paper.
  @visibleForTesting
  static List<Color> windowGradient(Brightness brightness) =>
      brightness == Brightness.dark
      ? const <Color>[Color(0xFF0A0E11), Color(0xFF131A1E)]
      : const <Color>[Color(0xFFD3D8CB), Color(0xFFE0E4D8)];

  /// The ink a readout window is written in under this room's light.
  static HardwareSelectorInk inkOf(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return dark
        ? const HardwareSelectorInk(
            on: _segmentLit,
            onMuted: _segmentLitMuted,
            accent: _segmentLitMuted,
            ghost: Color(0x16BDEBFF),
            glow: <Shadow>[
              Shadow(color: Color(0x8C63D6FF), blurRadius: 5),
              Shadow(color: Color(0x4D63D6FF), blurRadius: 1.5),
            ],
          )
        : const HardwareSelectorInk(
            on: _segmentInk,
            onMuted: _segmentInkMuted,
            accent: _segmentInkMuted,
            ghost: Color(0x0E000000),
            glow: <Shadow>[],
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
        _keyRight + _keyWidth + _keyGap + _contentRight,
        _bezel,
      ),
      // Hugs its content when the parent is loose, and keeps the readout
      // flush left — clipping — when a stretched footer widens it.
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
          // The plate stands a little proud of the composer card.
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(_outerRadius),
            boxShadow: <BoxShadow>[
              BoxShadow(
                color: dark
                    ? Colors.black.withValues(alpha: .55)
                    : const Color(0xFF3A2E22).withValues(alpha: .3),
                blurRadius: 4.5,
                offset: const Offset(0, 2),
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
                  right: _keyRight,
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

/// Paints the plate: charcoal bezel with its bevel and corner screws, and
/// the display window recessed into it. The step key paints itself, on top.
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
      rect,
      const Radius.circular(_outerRadius),
    );

    _paintBezel(canvas, rect, outer, dark: dark);
    _paintWindow(canvas, size, dark: dark);
    _paintScrews(canvas, size, dark: dark);
  }

  void _paintBezel(
    Canvas canvas,
    Rect rect,
    RRect outer, {
    required bool dark,
  }) {
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
    // The outer keyline where the plate meets the card.
    canvas.drawRRect(
      outer,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1
        ..color = Colors.black.withValues(alpha: dark ? .6 : .42),
    );
  }

  void _paintWindow(Canvas canvas, Size size, {required bool dark}) {
    final windowRect = Rect.fromLTRB(
      _bezel,
      _bezel,
      size.width - _keyRight - _keyWidth - _keyGap,
      size.height - _bezel,
    );
    if (windowRect.width <= _windowRadius * 2 || windowRect.height <= 4) return;
    final window = RRect.fromRectAndRadius(
      windowRect,
      const Radius.circular(_windowRadius),
    );

    // The cut into the plate: a dark line where the glass meets the frame.
    canvas.drawRRect(
      window.inflate(1),
      Paint()..color = Colors.black.withValues(alpha: dark ? .7 : .35),
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
    // Recessed behind the bezel: the top edge shades itself, the left a
    // little.
    final wellShadow = dark ? .55 : hardwareWellShadowAlpha(brightness) + .06;
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
          stops: const <double>[0, .32],
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
          stops: const <double>[0, .06],
        ).createShader(windowRect),
    );
    if (dark) {
      // Smoked glass: one shallow reflection of the room across the top.
      final glass = Rect.fromLTWH(
        windowRect.left,
        windowRect.top,
        windowRect.width,
        windowRect.height * .4,
      );
      canvas.drawRect(
        glass,
        Paint()
          ..shader = LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: <Color>[
              Colors.white.withValues(alpha: .05),
              Colors.white.withValues(alpha: 0),
            ],
          ).createShader(glass),
      );
    }
    // The bottom lip of the cut catches the room light.
    canvas.drawRect(
      Rect.fromLTRB(
        windowRect.left,
        windowRect.bottom - 1,
        windowRect.right,
        windowRect.bottom,
      ),
      Paint()..color = Colors.white.withValues(alpha: dark ? .06 : .4),
    );
    canvas.restore();
  }

  // Four slotted screws hold the plate to the panel. Each slot sits at its
  // own angle — nobody lines them up.
  void _paintScrews(Canvas canvas, Size size, {required bool dark}) {
    const angles = <double>[-.35, .6, 1.2, -1.05];
    final centers = <Offset>[
      const Offset(_screwInset, _screwInset),
      Offset(size.width - _screwInset, _screwInset),
      Offset(_screwInset, size.height - _screwInset),
      Offset(size.width - _screwInset, size.height - _screwInset),
    ];
    for (var i = 0; i < centers.length; i++) {
      final center = centers[i];
      // Countersink shadow.
      canvas.drawCircle(
        center.translate(0, .4),
        _screwRadius + .6,
        Paint()..color = Colors.black.withValues(alpha: dark ? .6 : .4),
      );
      // The head: satin metal, lit from the upper left.
      canvas.drawCircle(
        center,
        _screwRadius,
        Paint()
          ..shader = RadialGradient(
            center: const Alignment(-.4, -.45),
            radius: 1,
            colors: dark
                ? const <Color>[_metalMid, _metalDark, Color(0xFF3B3936)]
                : const <Color>[_metalLight, _metalMid, _metalDark],
            stops: const <double>[0, .6, 1],
          ).createShader(Rect.fromCircle(center: center, radius: _screwRadius)),
      );
      // The slot, cut straight across.
      final direction = Offset(math.cos(angles[i]), math.sin(angles[i]));
      final from = center - direction * (_screwRadius * .78);
      final to = center + direction * (_screwRadius * .78);
      canvas.drawLine(
        from.translate(0, .5),
        to.translate(0, .5),
        Paint()
          ..color = Colors.white.withValues(alpha: dark ? .22 : .5)
          ..strokeWidth = .9
          ..strokeCap = StrokeCap.round,
      );
      canvas.drawLine(
        from,
        to,
        Paint()
          ..color = Colors.black.withValues(alpha: .7)
          ..strokeWidth = .9
          ..strokeCap = StrokeCap.round,
      );
    }
  }

  @override
  bool shouldRepaint(HardwareSelectorFramePainter oldDelegate) =>
      oldDelegate.brightness != brightness;
}

/// The square metal step key at the right of the plate: satin metal with a
/// chevron cut into it. Brightens under the cursor, sinks under the finger.
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
    final keyRect = (Offset.zero & size).translate(0, press * 1.5);
    final key = RRect.fromRectAndRadius(
      keyRect,
      const Radius.circular(_keyRadius),
    );

    // The cut it sits in, and its own shadow, which shortens as it sinks.
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        (Offset.zero & size).inflate(1.2),
        const Radius.circular(_keyRadius + 1.2),
      ),
      Paint()..color = Colors.black.withValues(alpha: dark ? .55 : .35),
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        keyRect.translate(0, 2 - press * 1.4),
        const Radius.circular(_keyRadius),
      ),
      Paint()
        ..color = Colors.black.withValues(alpha: dark ? .5 : .32)
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, 2.4 - press * 1.2),
    );

    // Satin metal, top-lit.
    final top = dark ? _metalMid : _metalLight;
    final mid = dark ? const Color(0xFF807D77) : _metalMid;
    final bottom = dark ? const Color(0xFF55534F) : _metalDark;
    canvas.drawRRect(
      key,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: <Color>[
            Color.lerp(top, Colors.white, .08 * hover)!,
            Color.lerp(mid, Colors.white, .08 * hover)!,
            Color.lerp(bottom, Colors.black, .12 * press)!,
          ],
          stops: const <double>[0, .55, 1],
        ).createShader(keyRect),
    );
    // The bevel and the keyline.
    canvas.drawRRect(
      key.deflate(.6),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1
        ..shader = LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: <Color>[
            Colors.white.withValues(alpha: dark ? .3 : .5),
            Colors.white.withValues(alpha: 0),
            Colors.black.withValues(alpha: .25),
          ],
          stops: const <double>[0, .5, 1],
        ).createShader(keyRect),
    );
    canvas.drawRRect(
      key,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1
        ..color = Colors.black.withValues(alpha: dark ? .55 : .42),
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
      cut(Colors.white.withValues(alpha: dark ? .38 : .6)),
    );
    canvas.drawPath(chevron(0), cut(Colors.black.withValues(alpha: .66)));
  }

  @override
  bool shouldRepaint(HardwareSelectorKeyPainter oldDelegate) =>
      oldDelegate.brightness != brightness ||
      oldDelegate.hover != hover ||
      oldDelegate.press != press;
}
