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
//
// Two lights live in the cap and they are not the same light. The finger's
// own contact glow comes up dim while the key is held — the console has not
// accepted anything yet. The lamps proper belong to the console: they answer
// only [HardwareLitButton.lit], so the whole warm-up is still ahead of them
// when the job goes out, and a press that never turns into a submission
// never moves them.

import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import '../app/app_theme.dart';
import 'hardware.dart';
import 'paint_cache.dart';

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

// A cold filament draws more than a hot one, so the first moment of a lamp
// is brighter than its steady state. This is where the overshoot lands.
const _lensTopFlash = Color(0xFFB35CA3);
const _lensBottomFlash = Color(0xFF914688);

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

// ---------------------------------------------------------------------------
// Lamp timing. Every number here is a lamp fact, not a UI preference.
// ---------------------------------------------------------------------------

/// How long the filament takes to come up to heat.
const Duration _warmUp = Duration(milliseconds: 340);

/// How long the glass keeps a trace of it after the console lets go.
const Duration _afterglow = Duration(milliseconds: 600);

/// The key's own contact glow under a finger: quick on, unhurried off.
const Duration _contactOn = Duration(milliseconds: 120);
const Duration _contactOff = Duration(milliseconds: 220);

/// How much light the contact glow puts in the lens compared with the lamps.
const double _contactGlow = .3;

/// The lamp's breath while it is lit: how far down it swings and how often.
const double _breathFloor = .74;
const double _breathHz = 1.18;

/// The breath comes in over this long, so the warm-up is seen for itself
/// before the lamp starts moving.
const double _breathRampSeconds = .45;

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

/// The filament coming up to heat. A cold wire is a poor resistor, so it
/// draws hard for the first instant and flares a few percent past its
/// working brightness before settling back to it.
class _FilamentWarm extends Curve {
  const _FilamentWarm();

  static double _raw(double t) => 1 - math.exp(-4 * t) * math.cos(4.2 * t);

  // Trimmed so the curve lands exactly on 1 at the end of the warm-up.
  @override
  double transformInternal(double t) => _raw(t) - (_raw(1) - 1) * t;
}

/// Switched off, a filament loses most of its light in a breath and then
/// sits there glowing dim while the last heat leaves the wire.
class _FilamentCool extends Curve {
  const _FilamentCool();

  /// [u] is how far into the cool-down we are, 0 to 1.
  static double _ember(double u) =>
      .74 * math.exp(-11 * u) + .26 * math.exp(-3.2 * u);

  @override
  double transformInternal(double t) {
    // The reverse curve is handed the parent's remaining value, so the time
    // that has passed is its complement.
    final u = 1 - t;
    return (_ember(u) - _ember(1) * u).clamp(0.0, 1.0);
  }
}

/// Public so tests can read the lamp without screen-scraping pixels.
class HardwareLitButtonState extends State<HardwareLitButton>
    with TickerProviderStateMixin {
  // The console's lamps. They answer `lit` and nothing else: a finger on the
  // key does not light them, so the warm-up is still whole when the job goes
  // out, and a press that comes to nothing never disturbs them.
  late final AnimationController _lamp = AnimationController(
    vsync: this,
    duration: _warmUp,
    reverseDuration: _afterglow,
    value: widget.lit ? 1 : 0,
  )..addStatusListener(_handleLampStatus);
  late final Animation<double> _glow = CurvedAnimation(
    parent: _lamp,
    curve: const _FilamentWarm(),
    reverseCurve: const _FilamentCool(),
  );

  // The key's own contact glow while a finger holds it down.
  late final AnimationController _contact = AnimationController(
    vsync: this,
    duration: _contactOn,
    reverseDuration: _contactOff,
  );

  // The filament's life, ticking only while there is light in the lens.
  late final Ticker _filamentTicker = createTicker(_tickFilament);
  final ValueNotifier<double> _filament = ValueNotifier<double>(1);
  double _filamentBody = 1;
  final int _seed = math.Random().nextInt(1 << 20);
  late final List<double> _phases = <double>[
    for (var i = 0; i < 3; i++) _hash01(i - 31) * 2 * math.pi,
  ];
  late final AnimationController _hoverLift = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 140),
    reverseDuration: const Duration(milliseconds: 200),
  );

  bool _pressed = false;
  bool _focused = false;

  /// The key's shaders, built once per size and light and reused across
  /// paints; a lit lamp's lens still changes with the filament, and those
  /// entries cycle out through the cache's own disposal.
  final ShaderCache<Object> _shaders = ShaderCache<Object>(capacity: 24);

  /// The frost speckle mapped onto the lens, once per lens rectangle.
  final Map<Rect, (List<Offset>, List<Offset>)> _frostPoints =
      <Rect, (List<Offset>, List<Offset>)>{};

  bool get _enabled => widget.onPressed != null;

  /// How lit the lens is right now: 0 with everything off, 1 at the lamps'
  /// working brightness, and a little over 1 at the top of the warm-up
  /// flare. A held key on its own reaches only the contact glow.
  @visibleForTesting
  double get litAmount => math.max(_glow.value, _contactGlow * _contact.value);

  /// The filament's momentary output relative to steady, as the hot spots
  /// see it: roughly 0.72–1.06 while the lamps are on — the slow breath and
  /// the fine flicker together — and exactly 1 when they are off.
  @visibleForTesting
  double get filament => _filament.value;

  /// The same output as the whole block sees it: the diffuser lags the hot
  /// spots by a few frames and rounds their edges off.
  @visibleForTesting
  double get filamentBody => _filamentBody;

  /// Whether the filament is alive — true only while there is light in the
  /// lens, from the first frame of warm-up to the last of the afterglow.
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
    // Going inert mid-press drops the finger's own state. It must not reach
    // the lamps: the console lights those, and it has just said to.
    if (!_enabled && (_pressed || _focused)) {
      _pressed = false;
      _focused = false;
      _hoverLift.reverse();
      _driveContact();
    }
  }

  @override
  void dispose() {
    _filamentTicker.dispose();
    _filament.dispose();
    _lamp.dispose();
    _contact.dispose();
    _hoverLift.dispose();
    _shaders.clear();
    super.dispose();
  }

  // The filament lives exactly as long as any light is in the lens: from the
  // first frame of warm-up to the last of the afterglow, and never once the
  // lamp is cold, so a dark console schedules no frames.
  void _handleLampStatus(AnimationStatus status) {
    if (status == AnimationStatus.dismissed) {
      _filamentTicker.stop();
      _filament.value = 1;
      _filamentBody = 1;
    } else if (!_filamentTicker.isActive) {
      _filamentTicker.start();
    }
  }

  void _tickFilament(Duration elapsed) {
    final t = elapsed.inMicroseconds / Duration.microsecondsPerSecond;
    final hot = _filamentAt(t);
    _filamentBody = _bodyAt(t);
    if ((hot - _filament.value).abs() > .0004) _filament.value = hot;
  }

  /// A cheap, allocation-free noise in [0, 1) for integer [n]. The old code
  /// built a [math.Random] per call, several times a frame, for this.
  double _hash01(int n) {
    var h = (n * 374761393 + _seed * 668265263) & 0x3fffffff;
    h = (h ^ (h >> 13)) & 0x3fffffff;
    h = (h * 1274126177) & 0x3fffffff;
    h = (h ^ (h >> 16)) & 0x3fffffff;
    return (h & 0xfffff) / 0x100000;
  }

  /// What the lamp is giving at [t] seconds, relative to its steady output.
  ///
  /// Two things are layered. A slow breath — a little over one a second,
  /// eased so it dwells at the top and the bottom instead of sweeping evenly
  /// — takes the lamp down to about three quarters and back; it fades in
  /// over the first half second so the warm-up is read for itself first.
  /// Over that runs the fine wander of a filament on an imperfect supply,
  /// with a deeper sag now and then.
  double _filamentAt(double t) {
    final swing = (1 + math.cos(2 * math.pi * _breathHz * t)) / 2;
    final eased = Curves.easeInOutCubic.transform(swing.clamp(0.0, 1.0));
    final depth = (t / _breathRampSeconds).clamp(0.0, 1.0);
    final breath =
        1 - (1 - (_breathFloor + (1 - _breathFloor) * eased)) * depth;
    final fine =
        .022 * math.sin(2 * math.pi * 3.11 * t + _phases[0]) +
        .014 * math.sin(2 * math.pi * 5.87 * t + _phases[1]) +
        .009 * math.sin(2 * math.pi * 9.43 * t + _phases[2]);
    var w = breath * (1 + fine);
    // Roughly three windows in ten, the supply drops for a moment.
    const window = .7;
    final k = (t / window).floor();
    if (_hash01(k) < .3) {
      final at = (k + .18 + .64 * _hash01(k + 977)) * window;
      final d = (t - at) / .038;
      w -= .11 * math.exp(-d * d);
    }
    return w.clamp(.62, 1.08);
  }

  /// The same output after the diffuser: a few frames behind the hot spots
  /// and averaged over two taps, so the block breathes a beat after them.
  double _bodyAt(double t) {
    const lag = .055;
    return (_filamentAt(t - lag) + _filamentAt(t - lag - .035)) / 2;
  }

  // The lamps follow the console. Warm 340 ms, cool 600 ms, never a loop.
  void _driveLamp() {
    if (widget.lit) {
      _lamp.forward();
    } else {
      _lamp.reverse();
    }
  }

  // The contact glow follows the finger, and only the finger.
  void _driveContact() {
    if (_pressed && _enabled) {
      _contact.forward();
    } else {
      _contact.reverse();
    }
  }

  // A key clicks as it goes down, the way real hardware does.
  void _setPressed(bool value) {
    if (_pressed == value) return;
    if (value) hardwareSelectionFeedback();
    setState(() => _pressed = value);
    _driveContact();
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
      animation: Listenable.merge(<Listenable>[
        _lamp,
        _contact,
        _hoverLift,
        _filament,
      ]),
      builder: (context, _) {
        // Three levels, because a diffused lamp is not one number: what is
        // steadily in the lens, what the hot spots are giving this instant,
        // and what has reached the whole block a few frames later.
        final contact = _contactGlow * _contact.value;
        final lamp = _glow.value;
        final lit = math.max(lamp.clamp(0.0, 1.0), contact);
        final glow = math.max(lamp * _filament.value, contact);
        final body = math.max(lamp * _filamentBody, contact);
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
            glow: glow,
            body: body,
            hover: _hoverLift.value,
            pressed: _pressed,
            focusGlow: _focused ? context.tokens.brass : null,
            shaders: _shaders,
            frostPoints: _frostPoints,
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
      // The lamps repaint on their own picture while lit, so the warm-up
      // and the breath never re-record the console around the key.
      child: RepaintBoundary(child: face),
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
    required this.glow,
    required this.body,
    required this.hover,
    required this.pressed,
    required this.focusGlow,
    required this.shaders,
    required this.frostPoints,
  });

  final bool dark;

  /// Owned by the key's state; see [HardwareLitButtonState].
  final ShaderCache<Object> shaders;
  final Map<Rect, (List<Offset>, List<Offset>)> frostPoints;

  /// The steady light in the lens, 0 to 1: what the structure of the cap —
  /// its edge catch, its tooth, its ink — is lit by.
  final double lit;

  /// What the hot spots are giving this instant, breath and flicker
  /// included. Runs a little over 1 at the top of the warm-up flare.
  final double glow;

  /// What has reached the whole block: the same light a few frames later,
  /// with the diffuser's edges taken off it.
  final double body;

  final double hover;
  final bool pressed;
  final Color? focusGlow;

  /// The halo around each lamp sits between the two: further through the
  /// diffuser than the hot spot, nearer than the block.
  double get _halo => (glow + body) / 2;

  /// Hover is a small lift in the lens, not a colour change.
  Color _lift(Color color) => Color.lerp(color, Colors.white, .05 * hover)!;

  /// An alpha that survives the warm-up flare pushing a level past 1.
  static double _alpha(double base, double level) =>
      (base * level).clamp(0.0, 1.0);

  /// The lens plastic at [level]: from unlit through working brightness and,
  /// past 1, on into the brief flare of a filament that is still cold.
  static Color _plastic(Color idle, Color working, Color flash, double level) =>
      level <= 1
      ? Color.lerp(idle, working, level.clamp(0.0, 1.0))!
      : Color.lerp(working, flash, (level - 1).clamp(0.0, 1.0))!;

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
        ..color = _spill.withValues(alpha: _alpha(dark ? .26 : .17, _halo))
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 9),
    );
  }

  // Matte charcoal, with the light catching its top and left edges and its
  // bottom and right edges turning away.
  void _paintBezel(Canvas canvas, Rect rect, RRect outer) {
    canvas.drawRRect(
      outer,
      Paint()
        ..shader = shaders.obtain(
          ('bezel', rect),
          () => const LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: <Color>[_bezelTop, _bezelBottom],
          ).createShader(rect),
        ),
    );
    // The bevel: one hairline inside the outer edge, lit at top-left.
    canvas.drawRRect(
      outer.deflate(.6),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1
        ..shader = shaders.obtain(
          ('bevel', rect, dark),
          () => LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: <Color>[
              Colors.white.withValues(alpha: dark ? .16 : .24),
              Colors.white.withValues(alpha: .03),
              Colors.black.withValues(alpha: .35),
            ],
            stops: const <double>[0, .5, 1],
          ).createShader(rect),
        ),
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
        ..shader = shaders.obtain(
          ('lens', lensRect, body, hover),
          () => LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: <Color>[
              _lift(_plastic(_lensTopIdle, _lensTopLit, _lensTopFlash, body)),
              _lift(
                _plastic(
                  _lensBottomIdle,
                  _lensBottomLit,
                  _lensBottomFlash,
                  body,
                ),
              ),
            ],
          ).createShader(lensRect),
        ),
    );
    // The diffuser lightens toward the middle even with the lamps off.
    canvas.drawRect(
      lensRect,
      Paint()
        ..shader = shaders.obtain(
          ('diffuser', lensRect),
          () => RadialGradient(
            center: const Alignment(0, .1),
            radius: .9,
            colors: <Color>[
              Colors.white.withValues(alpha: .07),
              Colors.white.withValues(alpha: 0),
            ],
          ).createShader(lensRect),
        ),
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
    // The lamps' glow, wide and soft — one remove further through the
    // diffuser than the filaments themselves, so it answers a beat later.
    // The lamps change with every breath of the filament, so their shaders
    // are made for the frame and released with it rather than cached.
    final halo = _halo;
    for (final center in centers) {
      final radius = math.max(height * 1.15, width * .34);
      _drawWithShader(
        RadialGradient(
          colors: <Color>[
            _lamp.withValues(alpha: _alpha(.58, halo)),
            _lamp.withValues(alpha: _alpha(.21, halo)),
            _lamp.withValues(alpha: 0),
          ],
          stops: const <double>[0, .45, 1],
        ).createShader(Rect.fromCircle(center: center, radius: radius)),
        (paint) => canvas.drawCircle(center, radius, paint),
      );
    }
    // The hot spots where the filaments sit closest to the diffuser. These
    // lead: nothing stands between them and the wire.
    for (final center in centers) {
      final radius = height * .42;
      _drawWithShader(
        RadialGradient(
          colors: <Color>[
            const Color(0xFFFCE3F4).withValues(alpha: _alpha(.46, glow)),
            _lamp.withValues(alpha: _alpha(.28, glow)),
            _lamp.withValues(alpha: 0),
          ],
          stops: const <double>[0, .35, 1],
        ).createShader(Rect.fromCircle(center: center, radius: radius)),
        (paint) => canvas.drawCircle(center, radius, paint),
      );
    }
    // The thick edges of the block stay a little darker than its middle.
    canvas.drawRect(
      lensRect,
      Paint()
        ..shader = shaders.obtain(
          ('edges', lensRect, lit),
          () => LinearGradient(
            colors: <Color>[
              _shade.withValues(alpha: .28 * lit),
              _shade.withValues(alpha: 0),
              _shade.withValues(alpha: 0),
              _shade.withValues(alpha: .28 * lit),
            ],
            stops: const <double>[0, .18, .82, 1],
          ).createShader(lensRect),
        ),
    );
  }

  static void _drawWithShader(ui.Shader shader, void Function(Paint) draw) {
    try {
      draw(Paint()..shader = shader);
    } finally {
      shader.dispose();
    }
  }

  // Frosted plastic has tooth: a fine, even speckle over the whole lens.
  void _paintFrost(Canvas canvas, Rect lensRect) {
    final (light, deep) = frostPoints.putIfAbsent(lensRect, () {
      final light = <Offset>[];
      final deep = <Offset>[];
      for (var i = 0; i < _frost.length; i++) {
        final point = lensRect.topLeft.translate(
          _frost[i].dx * lensRect.width,
          _frost[i].dy * lensRect.height,
        );
        (i.isEven ? light : deep).add(point);
      }
      // The lens moves a pixel when pressed; keep a couple of mappings, not
      // a history of every size the key has been.
      if (frostPoints.length >= 4) frostPoints.remove(frostPoints.keys.first);
      return (light, deep);
    });
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
        ..shader = shaders.obtain(
          ('edge', lensRect, lit),
          () => LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: <Color>[
              Colors.white.withValues(alpha: .26 + .1 * lit),
              Colors.white.withValues(alpha: .04),
              _shade.withValues(alpha: .34),
            ],
            stops: const <double>[0, .55, 1],
          ).createShader(lensRect),
        ),
    );
  }

  @override
  bool shouldRepaint(_IndicatorPainter old) =>
      old.dark != dark ||
      old.lit != lit ||
      old.glow != glow ||
      old.body != body ||
      old.hover != hover ||
      old.pressed != pressed ||
      old.focusGlow != focusGlow;
}
