import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../app/app_theme.dart';

/// Skeuomorphic console hardware: machined knobs, recessed grooves, metal
/// toggles, and counter readouts.
///
/// These widgets echo the app icon — a brushed-steel knob set into walnut —
/// while staying inside the palette: plum lights a slider's traveled side and
/// the money green lights a switch that is on. The
/// grooves, wells, and readout windows are recessed into the surface they sit
/// on — shadowed warm cream in light mode, near-black in dark mode — so light
/// mode stays a paper-and-cream room rather than sprouting dark islands.

// Brushed-metal sweep stops, light-mode finish.
const _brushedLight = <Color>[
  Color(0xFFEDEEEC),
  Color(0xFFB9BCC0),
  Color(0xFFF2F3F1),
  Color(0xFFAFB3B8),
  Color(0xFFE6E7E5),
  Color(0xFFB4B7BB),
  Color(0xFFF0F1EF),
  Color(0xFFABAFB4),
  Color(0xFFEDEEEC),
];

// The same machining under evening light.
const _brushedDark = <Color>[
  Color(0xFFC9CBC9),
  Color(0xFF8F9296),
  Color(0xFFD2D3D1),
  Color(0xFF85888D),
  Color(0xFFC2C4C2),
  Color(0xFF8A8D91),
  Color(0xFFCDCECC),
  Color(0xFF82858A),
  Color(0xFFC9CBC9),
];

/// The comfortable minimum tap target on touch hardware, in logical pixels.
///
/// The console is drawn for a mouse: a switch paints 50×28 and a console key
/// about 32 tall. Fingers need more, so touch builds grow the *hit* area to
/// this size around the same artwork.
const double kHardwareTouchTarget = 44;

/// Whether this build runs on a finger-first platform.
///
/// Only phones and tablets grow their hit areas and click their detents;
/// desktop keeps the drawn console to the pixel. Tests flip this through
/// `debugDefaultTargetPlatformOverride`.
bool get isHardwareTouchPlatform =>
    defaultTargetPlatform == TargetPlatform.iOS ||
    defaultTargetPlatform == TargetPlatform.android;

/// The small click a detent, toggle, or console key makes under a finger.
/// Silent everywhere the platform has no taptic hardware.
void hardwareSelectionFeedback() {
  if (isHardwareTouchPlatform) {
    unawaited(HapticFeedback.selectionClick());
  }
}

/// Grows a control's hit area to [kHardwareTouchTarget] on touch platforms
/// without touching what it paints or inks.
///
/// The child keeps its drawn size and stays on top, so it still handles the
/// taps that land on it; a transparent pad behind it catches the near misses.
/// Desktop gets [child] straight back, so console layouts stay
/// pixel-identical there.
class HardwareTouchTarget extends StatelessWidget {
  const HardwareTouchTarget({
    required this.onTap,
    required this.child,
    super.key,
    this.minWidth = kHardwareTouchTarget,
    this.minHeight = kHardwareTouchTarget,
    this.alignment = Alignment.center,
  });

  /// Repeats what the child's own gesture handler does. A null callback
  /// (a disabled control) leaves the pad inert.
  final VoidCallback? onTap;
  final Widget child;
  final double minWidth;
  final double minHeight;

  /// Where the drawn child sits inside the grown hit area. Controls that
  /// stand on a rule ask for the bottom so the pad grows upward only.
  final AlignmentGeometry alignment;

  @override
  Widget build(BuildContext context) {
    if (!isHardwareTouchPlatform) return child;
    return ConstrainedBox(
      constraints: BoxConstraints(minWidth: minWidth, minHeight: minHeight),
      child: Stack(
        alignment: alignment,
        children: <Widget>[
          if (onTap != null)
            Positioned.fill(
              child: ExcludeSemantics(
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: onTap,
                ),
              ),
            ),
          child,
        ],
      ),
    );
  }
}

const _wellLight = Color(0xFFE2D6BE);
const _wellDark = Color(0xFF140F0C);

Color _well(Brightness brightness) =>
    brightness == Brightness.dark ? _wellDark : _wellLight;

// Inner shadow along the top edge of a recessed slot.
double _wellShadowAlpha(Brightness brightness) =>
    brightness == Brightness.dark ? .42 : .16;

Color _litPlum(Brightness brightness) => brightness == Brightness.dark
    ? const Color(0xFF96628D)
    : ClawnsoleColors.plum;

/// Paints the machined knob: knurled rim, brushed face, and an optional lit
/// indicator line. Shared by the slider thumb and the switch handle.
void paintMachinedKnob(
  Canvas canvas,
  Offset center,
  double radius, {
  required Brightness brightness,
  Color? indicator,
  double indicatorAngle = -math.pi / 2,
  Color? focusGlow,
}) {
  final dark = brightness == Brightness.dark;

  // Keyboard focus: a brass halo around the rim, the way a lamp catches the
  // edge of a knob. Painted first so the knob itself stays untouched.
  if (focusGlow != null) {
    canvas.drawCircle(
      center,
      radius * 1.16,
      Paint()
        ..color = focusGlow.withValues(alpha: .5)
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, radius * .34),
    );
    canvas.drawCircle(
      center,
      radius + 1.7,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.6
        ..color = focusGlow.withValues(alpha: .85),
    );
  }

  // Soft drop shadow so the knob sits above the panel.
  canvas.drawCircle(
    center + Offset(0, radius * .14),
    radius * .98,
    Paint()
      ..color = Colors.black.withValues(alpha: dark ? .5 : .3)
      ..maskFilter = MaskFilter.blur(BlurStyle.normal, radius * .22),
  );

  // Knurled rim: a darker steel band…
  final rimRect = Rect.fromCircle(center: center, radius: radius);
  canvas.drawCircle(
    center,
    radius,
    Paint()
      ..shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: dark
            ? const <Color>[Color(0xFF6E7175), Color(0xFF2E3033)]
            : const <Color>[Color(0xFF9EA1A5), Color(0xFF4A4C50)],
      ).createShader(rimRect),
  );
  // …textured with alternating cut marks.
  final knurls = math.max(22, (radius * 2.4).round());
  final lightCut = Paint()
    ..color = Colors.white.withValues(alpha: dark ? .3 : .5)
    ..strokeWidth = math.max(.8, radius * .07)
    ..strokeCap = StrokeCap.round;
  final darkCut = Paint()
    ..color = Colors.black.withValues(alpha: .38)
    ..strokeWidth = math.max(.8, radius * .07)
    ..strokeCap = StrokeCap.round;
  for (var i = 0; i < knurls; i++) {
    final angle = i * 2 * math.pi / knurls;
    final direction = Offset(math.cos(angle), math.sin(angle));
    canvas.drawLine(
      center + direction * radius * .84,
      center + direction * radius * .97,
      i.isEven ? lightCut : darkCut,
    );
  }

  // Brushed face: a sweep gradient reads as radial machining.
  final faceRadius = radius * .78;
  final faceRect = Rect.fromCircle(center: center, radius: faceRadius);
  canvas.drawCircle(
    center,
    faceRadius,
    Paint()
      ..shader = SweepGradient(
        transform: const GradientRotation(-.6),
        colors: dark ? _brushedDark : _brushedLight,
      ).createShader(faceRect),
  );
  // Dome shading: light falls from the upper left.
  canvas.drawCircle(
    center,
    faceRadius,
    Paint()
      ..shader = RadialGradient(
        center: const Alignment(-.4, -.5),
        radius: 1.15,
        colors: <Color>[
          Colors.white.withValues(alpha: dark ? .18 : .32),
          Colors.transparent,
          Colors.black.withValues(alpha: .18),
        ],
        stops: const <double>[0, .55, 1],
      ).createShader(faceRect),
  );
  // Seat line between rim and face.
  canvas.drawCircle(
    center,
    faceRadius,
    Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = math.max(.7, radius * .05)
      ..color = Colors.black.withValues(alpha: .4),
  );

  if (indicator != null) {
    final direction = Offset(
      math.cos(indicatorAngle),
      math.sin(indicatorAngle),
    );
    final from = center + direction * faceRadius * .3;
    final to = center + direction * faceRadius * .82;
    canvas.drawLine(
      from,
      to,
      Paint()
        ..color = indicator.withValues(alpha: .55)
        ..strokeWidth = radius * .3
        ..strokeCap = StrokeCap.round
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, radius * .12),
    );
    canvas.drawLine(
      from,
      to,
      Paint()
        ..color = indicator
        ..strokeWidth = math.max(1.4, radius * .14)
        ..strokeCap = StrokeCap.round,
    );
  }
}

/// Jumps a slider to one end of its travel.
class _SliderEdgeIntent extends Intent {
  const _SliderEdgeIntent.minimum() : toMaximum = false;
  const _SliderEdgeIntent.maximum() : toMaximum = true;

  final bool toMaximum;
}

/// A [Slider] dressed as console hardware: a machined knob traveling a
/// recessed groove whose filled side lights up plum.
///
/// The knob is a real slider for assistive tech and the keyboard: it reports
/// a labelled slider node whose value is spoken in the caller's own units
/// (see [semanticFormatterCallback]), arrow keys walk one division, Home and
/// End jump to the ends, and keyboard focus lights a brass halo on the knob.
class HardwareSlider extends StatefulWidget {
  const HardwareSlider({
    required this.value,
    required this.onChanged,
    super.key,
    this.min = 0,
    this.max = 1,
    this.divisions,
    this.label,
    this.semanticLabel,
    this.semanticFormatterCallback,
  });

  final double value;
  final ValueChanged<double>? onChanged;
  final double min;
  final double max;
  final int? divisions;

  /// The value bubble shown while dragging.
  final String? label;

  /// What this knob sets, e.g. 'Duration'. Without it a screen reader
  /// announces a bare number.
  final String? semanticLabel;

  /// Speaks a raw value in the caller's units — pass a callback returning
  /// '10 seconds' rather than letting Material announce its stock "40%".
  /// Defaults to the plain number at the precision the divisions imply.
  final SemanticFormatterCallback? semanticFormatterCallback;

  @override
  State<HardwareSlider> createState() => _HardwareSliderState();
}

class _HardwareSliderState extends State<HardwareSlider> {
  late final FocusNode _focus = FocusNode(debugLabel: 'HardwareSlider')
    ..addListener(_handleFocusChange);
  bool _focused = false;

  static const Map<ShortcutActivator, Intent> _edgeShortcuts =
      <ShortcutActivator, Intent>{
        SingleActivator(LogicalKeyboardKey.home): _SliderEdgeIntent.minimum(),
        SingleActivator(LogicalKeyboardKey.end): _SliderEdgeIntent.maximum(),
      };

  @override
  void dispose() {
    _focus
      ..removeListener(_handleFocusChange)
      ..dispose();
    super.dispose();
  }

  void _handleFocusChange() {
    if (_focus.hasFocus != _focused) {
      setState(() => _focused = _focus.hasFocus);
    }
  }

  bool get _enabled => widget.onChanged != null;

  /// One detent, or a tenth of the travel on a continuous groove.
  double get _step {
    final divisions = widget.divisions;
    final span = widget.max - widget.min;
    if (divisions != null && divisions > 0) return span / divisions;
    return span / 10;
  }

  double _clamp(double value) =>
      math.min(math.max(value, widget.min), widget.max);

  /// Lands [value] on the nearest detent so keyboard and screen-reader steps
  /// agree with what dragging produces.
  double _snap(double value) {
    final divisions = widget.divisions;
    if (divisions == null || divisions <= 0) return _clamp(value);
    final step = (widget.max - widget.min) / divisions;
    final index = (((value - widget.min) / step).round()).clamp(0, divisions);
    return widget.min + index * step;
  }

  int? _detent(double value) {
    final divisions = widget.divisions;
    if (divisions == null || divisions <= 0) return null;
    final step = (widget.max - widget.min) / divisions;
    return ((value - widget.min) / step).round();
  }

  String _speak(double value) =>
      widget.semanticFormatterCallback?.call(value) ?? _plainNumber(value);

  /// Whole seconds read as "6"; a 0.1 upscale factor reads as "2.4".
  String _plainNumber(double value) {
    final divisions = widget.divisions;
    final step = divisions == null || divisions <= 0
        ? null
        : (widget.max - widget.min) / divisions;
    final wholeSteps =
        step != null &&
        step == step.roundToDouble() &&
        widget.min == widget.min.roundToDouble();
    return wholeSteps ? '${value.round()}' : value.toStringAsFixed(1);
  }

  void _emit(double value) {
    final onChanged = widget.onChanged;
    if (onChanged == null || value == widget.value) return;
    if (_detent(value) != _detent(widget.value)) hardwareSelectionFeedback();
    onChanged(value);
  }

  /// Pointer path: [Slider] has already snapped the value for us.
  void _handleChanged(double value) {
    if (_detent(value) != _detent(widget.value)) hardwareSelectionFeedback();
    widget.onChanged!(value);
  }

  void _nudge(double delta) => _emit(_snap(_clamp(widget.value + delta)));

  @override
  Widget build(BuildContext context) {
    final brightness = Theme.of(context).brightness;
    final lit = _litPlum(brightness);
    final increased = _snap(_clamp(widget.value + _step));
    final decreased = _snap(_clamp(widget.value - _step));
    return Semantics(
      container: true,
      slider: true,
      enabled: _enabled,
      focusable: _enabled,
      focused: _focused,
      label: widget.semanticLabel,
      value: _speak(widget.value),
      increasedValue: _speak(increased),
      decreasedValue: _speak(decreased),
      onIncrease: _enabled ? () => _nudge(_step) : null,
      onDecrease: _enabled ? () => _nudge(-_step) : null,
      // The groove owns the announcement; Material's own slider node would
      // otherwise repeat it as a bare percentage.
      excludeSemantics: true,
      child: Shortcuts(
        shortcuts: _edgeShortcuts,
        child: Actions(
          actions: <Type, Action<Intent>>{
            _SliderEdgeIntent: CallbackAction<_SliderEdgeIntent>(
              onInvoke: (intent) {
                _emit(intent.toMaximum ? widget.max : widget.min);
                return null;
              },
            ),
          },
          child: SliderTheme(
            data: SliderTheme.of(context).copyWith(
              trackHeight: 9,
              trackShape: const _RecessedGrooveTrack(),
              thumbShape: _MachinedKnobThumb(
                radius: 14,
                indicator: lit,
                focusGlow: _focused && _enabled ? context.tokens.brass : null,
              ),
              tickMarkShape: const _GrooveTickMark(),
              activeTickMarkColor: ClawnsoleColors.cream.withValues(alpha: .55),
              inactiveTickMarkColor: brightness == Brightness.dark
                  ? ClawnsoleColors.creamMuted.withValues(alpha: .3)
                  : const Color(0xFF6B5E4C).withValues(alpha: .4),
              overlayShape: const RoundSliderOverlayShape(overlayRadius: 23),
              activeTrackColor: lit,
              inactiveTrackColor: _well(brightness),
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 12),
            ),
            child: Slider(
              value: widget.value,
              min: widget.min,
              max: widget.max,
              divisions: widget.divisions,
              label: widget.label,
              focusNode: _focus,
              onChanged: _enabled ? _handleChanged : null,
            ),
          ),
        ),
      ),
    );
  }
}

class _MachinedKnobThumb extends SliderComponentShape {
  const _MachinedKnobThumb({
    required this.radius,
    required this.indicator,
    this.focusGlow,
  });

  final double radius;
  final Color indicator;
  final Color? focusGlow;

  @override
  Size getPreferredSize(bool isEnabled, bool isDiscrete) =>
      Size.fromRadius(radius);

  @override
  void paint(
    PaintingContext context,
    Offset center, {
    required Animation<double> activationAnimation,
    required Animation<double> enableAnimation,
    required bool isDiscrete,
    required TextPainter labelPainter,
    required RenderBox parentBox,
    required SliderThemeData sliderTheme,
    required TextDirection textDirection,
    required double value,
    required double textScaleFactor,
    required Size sizeWithOverflow,
  }) {
    paintMachinedKnob(
      context.canvas,
      center,
      radius,
      brightness: sliderTheme.inactiveTrackColor == _wellDark
          ? Brightness.dark
          : Brightness.light,
      indicator: indicator.withValues(alpha: enableAnimation.value),
      focusGlow: focusGlow,
    );
  }

  // Value equality keeps an unchanged groove out of a needless repaint, and
  // lets a test see the focus halo arrive.
  @override
  bool operator ==(Object other) =>
      other is _MachinedKnobThumb &&
      other.radius == radius &&
      other.indicator == indicator &&
      other.focusGlow == focusGlow;

  @override
  int get hashCode => Object.hash(radius, indicator, focusGlow);
}

class _RecessedGrooveTrack extends SliderTrackShape with BaseSliderTrackShape {
  const _RecessedGrooveTrack();

  @override
  void paint(
    PaintingContext context,
    Offset offset, {
    required RenderBox parentBox,
    required SliderThemeData sliderTheme,
    required Animation<double> enableAnimation,
    required TextDirection textDirection,
    required Offset thumbCenter,
    Offset? secondaryOffset,
    bool isDiscrete = false,
    bool isEnabled = false,
  }) {
    final canvas = context.canvas;
    final rect = getPreferredRect(
      parentBox: parentBox,
      offset: offset,
      sliderTheme: sliderTheme,
      isEnabled: isEnabled,
      isDiscrete: isDiscrete,
    );
    final radius = Radius.circular(rect.height / 2);
    final groove = RRect.fromRectAndRadius(rect, radius);
    final well = sliderTheme.inactiveTrackColor ?? _wellLight;
    final dark = well == _wellDark;
    final enable = enableAnimation.value;

    // Bottom lip catches the light, so the groove reads as recessed.
    canvas.drawRRect(
      groove.shift(const Offset(0, 1.1)),
      Paint()..color = Colors.white.withValues(alpha: dark ? .07 : .8),
    );
    canvas.drawRRect(groove, Paint()..color = well);

    // Lit side of the groove.
    final lit = (sliderTheme.activeTrackColor ?? ClawnsoleColors.plum)
        .withValues(alpha: .45 + .55 * enable);
    final isLtr = textDirection == TextDirection.ltr;
    final active = RRect.fromRectAndRadius(
      Rect.fromLTRB(
        isLtr ? rect.left + 1.4 : thumbCenter.dx,
        rect.top + 1.4,
        isLtr ? thumbCenter.dx : rect.right - 1.4,
        rect.bottom - 1.4,
      ),
      Radius.circular((rect.height - 2.8) / 2),
    );
    if (active.width > 1) {
      canvas.drawRRect(
        active,
        Paint()
          ..color = lit.withValues(alpha: .4 * enable)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3),
      );
      canvas.drawRRect(active, Paint()..color = lit);
    }

    // Inner shadow along the top edge of the slot.
    canvas.save();
    canvas.clipRRect(groove);
    canvas.drawRect(
      Rect.fromLTWH(rect.left, rect.top, rect.width, rect.height * .55),
      Paint()
        ..shader =
            LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: <Color>[
                Colors.black.withValues(
                  alpha: _wellShadowAlpha(
                    dark ? Brightness.dark : Brightness.light,
                  ),
                ),
                Colors.transparent,
              ],
            ).createShader(
              Rect.fromLTWH(rect.left, rect.top, rect.width, rect.height * .55),
            ),
    );
    canvas.restore();
  }
}

class _GrooveTickMark extends SliderTickMarkShape {
  const _GrooveTickMark();

  @override
  Size getPreferredSize({
    required SliderThemeData sliderTheme,
    required bool isEnabled,
  }) => const Size(2.4, 2.4);

  @override
  void paint(
    PaintingContext context,
    Offset center, {
    required RenderBox parentBox,
    required SliderThemeData sliderTheme,
    required Animation<double> enableAnimation,
    required Offset thumbCenter,
    required bool isEnabled,
    required TextDirection textDirection,
  }) {
    final isLtr = textDirection == TextDirection.ltr;
    final active = isLtr
        ? center.dx <= thumbCenter.dx
        : center.dx >= thumbCenter.dx;
    final color = active
        ? sliderTheme.activeTickMarkColor
        : sliderTheme.inactiveTickMarkColor;
    context.canvas.drawCircle(center, 1.2, Paint()..color = color!);
  }
}

/// A metallic toggle: a machined handle sliding in a recessed well whose
/// active side lights up hunter green.
///
/// Reads to assistive tech as one labelled switch, takes Space or Enter from
/// the keyboard, and on touch platforms answers to a finger-sized area
/// around the drawn 50×28 well.
class HardwareSwitch extends StatefulWidget {
  const HardwareSwitch({
    required this.value,
    required this.onChanged,
    super.key,
    this.semanticLabel,
    this.canRequestFocus = true,
  });

  final bool value;
  final ValueChanged<bool>? onChanged;

  /// What this switch turns on, e.g. 'Synchronized audio'.
  final String? semanticLabel;

  /// Set false when an enclosing row already owns the focus stop — see
  /// [HardwareSwitchTile], where the whole row toggles.
  final bool canRequestFocus;

  @override
  State<HardwareSwitch> createState() => _HardwareSwitchState();
}

class _HardwareSwitchState extends State<HardwareSwitch>
    with SingleTickerProviderStateMixin {
  late final AnimationController _position = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 140),
    value: widget.value ? 1 : 0,
  );

  @override
  void didUpdateWidget(covariant HardwareSwitch oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.value != widget.value) {
      if (widget.value) {
        _position.forward();
      } else {
        _position.reverse();
      }
    }
  }

  @override
  void dispose() {
    _position.dispose();
    super.dispose();
  }

  void _toggle() {
    hardwareSelectionFeedback();
    widget.onChanged!(!widget.value);
  }

  @override
  Widget build(BuildContext context) {
    final enabled = widget.onChanged != null;
    final brightness = Theme.of(context).brightness;
    return MergeSemantics(
      child: Semantics(
        container: true,
        enabled: enabled,
        toggled: widget.value,
        label: widget.semanticLabel,
        child: Opacity(
          opacity: enabled ? 1 : .45,
          child: HardwareTouchTarget(
            onTap: enabled ? _toggle : null,
            child: InkWell(
              borderRadius: BorderRadius.circular(999),
              canRequestFocus: widget.canRequestFocus,
              onTap: enabled ? _toggle : null,
              child: Padding(
                padding: const EdgeInsets.all(3),
                child: AnimatedBuilder(
                  animation: _position,
                  builder: (context, _) => CustomPaint(
                    size: const Size(50, 28),
                    painter: _SwitchPainter(
                      t: Curves.easeOut.transform(_position.value),
                      brightness: brightness,
                      // The money green, tuned per mode: a signal lamp on
                      // paper, the cost panel's felt at night.
                      lit: context.tokens.switchOn,
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

/// A two-position labeled switch set into a recessed console well. The
/// selected option rides on a brushed-metal carriage instead of using a flat
/// segmented-control fill.
///
/// Each half is one node in a mutually exclusive group, so a screen reader
/// says "AUTO, selected" rather than reading the label twice. On touch
/// platforms the well keeps its drawn 36 px height inside a finger-sized
/// 44 px band.
class HardwareChoiceSwitch extends StatelessWidget {
  const HardwareChoiceSwitch({
    required this.firstLabel,
    required this.secondLabel,
    required this.firstSelected,
    required this.onChanged,
    super.key,
    this.firstKey,
    this.secondKey,
    this.semanticLabel,
  });

  final String firstLabel;
  final String secondLabel;
  final bool firstSelected;
  final ValueChanged<bool>? onChanged;
  final Key? firstKey;
  final Key? secondKey;

  /// What the pair chooses between, e.g. 'Duration mode'. Spoken as a hint
  /// on each half so the group has a name.
  final String? semanticLabel;

  void _select(bool first) {
    if (first != firstSelected) hardwareSelectionFeedback();
    onChanged!(first);
  }

  @override
  Widget build(BuildContext context) {
    final enabled = onChanged != null;
    final brightness = Theme.of(context).brightness;
    final dark = brightness == Brightness.dark;
    final selectedText = dark
        ? const Color(0xFF242025)
        : ClawnsoleColors.plumInk;
    final well = Container(
      width: 164,
      height: 36,
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: _well(brightness),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: Colors.black.withValues(alpha: dark ? .5 : .18),
        ),
        boxShadow: <BoxShadow>[
          BoxShadow(
            color: Colors.black.withValues(alpha: _wellShadowAlpha(brightness)),
            blurRadius: 3,
            offset: const Offset(0, 1),
          ),
          BoxShadow(
            color: Colors.white.withValues(alpha: dark ? .06 : .75),
            offset: const Offset(0, 1),
          ),
        ],
      ),
      child: Stack(
        children: <Widget>[
          AnimatedAlign(
            duration: const Duration(milliseconds: 160),
            curve: Curves.easeOutCubic,
            alignment: firstSelected
                ? Alignment.centerLeft
                : Alignment.centerRight,
            child: FractionallySizedBox(
              widthFactor: .5,
              heightFactor: 1,
              child: Container(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(7),
                  border: Border.all(
                    color: Colors.black.withValues(alpha: .38),
                  ),
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: dark
                        ? const <Color>[
                            Color(0xFFD0D1CF),
                            Color(0xFF92959A),
                            Color(0xFFBFC1BF),
                          ]
                        : const <Color>[
                            Color(0xFFF3F4F2),
                            Color(0xFFB6B9BD),
                            Color(0xFFE1E2E0),
                          ],
                  ),
                  boxShadow: <BoxShadow>[
                    BoxShadow(
                      color: Colors.black.withValues(alpha: dark ? .5 : .3),
                      blurRadius: 3,
                      offset: const Offset(0, 1.5),
                    ),
                    BoxShadow(
                      color: context.tokens.switchOn.withValues(alpha: .35),
                      blurRadius: 4,
                    ),
                  ],
                ),
              ),
            ),
          ),
          Row(
            children: <Widget>[
              Expanded(
                child: _HardwareChoice(
                  key: firstKey,
                  label: firstLabel,
                  selected: firstSelected,
                  enabled: enabled,
                  selectedText: selectedText,
                  groupLabel: semanticLabel,
                  onTap: () => _select(true),
                ),
              ),
              Expanded(
                child: _HardwareChoice(
                  key: secondKey,
                  label: secondLabel,
                  selected: !firstSelected,
                  enabled: enabled,
                  selectedText: selectedText,
                  groupLabel: semanticLabel,
                  onTap: () => _select(false),
                ),
              ),
            ],
          ),
        ],
      ),
    );
    return Opacity(
      opacity: enabled ? 1 : .55,
      child: isHardwareTouchPlatform
          // Touch keeps the drawn 36 px well and hangs a finger-sized band
          // behind it, split down the middle so a near miss still picks the
          // right half. A locked switch gets the same band, unpressable, so
          // nothing shifts when the layout locks it to Manual.
          ? SizedBox(
              width: 164,
              height: kHardwareTouchTarget,
              child: Stack(
                children: <Widget>[
                  if (enabled)
                    Positioned.fill(
                      child: ExcludeSemantics(
                        child: Row(
                          children: <Widget>[
                            Expanded(
                              child: GestureDetector(
                                behavior: HitTestBehavior.opaque,
                                onTap: () => _select(true),
                              ),
                            ),
                            Expanded(
                              child: GestureDetector(
                                behavior: HitTestBehavior.opaque,
                                onTap: () => _select(false),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  Center(child: well),
                ],
              ),
            )
          : well,
    );
  }
}

class _HardwareChoice extends StatelessWidget {
  const _HardwareChoice({
    required this.label,
    required this.selected,
    required this.enabled,
    required this.selectedText,
    required this.onTap,
    super.key,
    this.groupLabel,
  });

  final String label;
  final bool selected;
  final bool enabled;
  final Color selectedText;
  final VoidCallback onTap;
  final String? groupLabel;

  @override
  Widget build(BuildContext context) => MergeSemantics(
    child: Semantics(
      container: true,
      button: true,
      inMutuallyExclusiveGroup: true,
      selected: selected,
      enabled: enabled,
      label: label,
      hint: groupLabel,
      child: InkWell(
        borderRadius: BorderRadius.circular(7),
        onTap: enabled ? onTap : null,
        // The label is already spoken above; without this the carriage
        // announces itself twice ("AUTO AUTO").
        child: ExcludeSemantics(
          child: Center(
            child: Text(
              label,
              style: TextStyle(
                fontSize: 10.5,
                fontWeight: FontWeight.w700,
                letterSpacing: .7,
                color: selected
                    ? selectedText
                    : context.colors.onSurfaceVariant,
              ),
            ),
          ),
        ),
      ),
    ),
  );
}

class _SwitchPainter extends CustomPainter {
  const _SwitchPainter({
    required this.t,
    required this.brightness,
    required this.lit,
  });

  final double t;
  final Brightness brightness;
  final Color lit;

  @override
  void paint(Canvas canvas, Size size) {
    final dark = brightness == Brightness.dark;
    final well = RRect.fromRectAndRadius(
      Rect.fromLTWH(0, 0, size.width, size.height),
      Radius.circular(size.height / 2),
    );

    // Recessed well with a lit bottom lip.
    canvas.drawRRect(
      well.shift(const Offset(0, 1.2)),
      Paint()..color = Colors.white.withValues(alpha: dark ? .07 : .8),
    );
    canvas.drawRRect(well, Paint()..color = _well(brightness));

    final knobRadius = size.height / 2 - 2.6;
    final knobX = knobRadius + 2.6 + t * (size.width - 2 * (knobRadius + 2.6));
    final knobCenter = Offset(knobX, size.height / 2);

    // The traveled side lights up.
    if (t > .02) {
      final strip = RRect.fromRectAndRadius(
        Rect.fromLTRB(2, 2, knobX, size.height - 2),
        Radius.circular(size.height / 2 - 2),
      );
      final color = lit.withValues(alpha: .55 + .45 * t);
      canvas.drawRRect(
        strip,
        Paint()
          ..color = Color.lerp(
            lit,
            Colors.white,
            .25,
          )!.withValues(alpha: .45 * t)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3.5),
      );
      canvas.drawRRect(strip, Paint()..color = color);
    }

    // Inner shadow at the top of the well.
    canvas.save();
    canvas.clipRRect(well);
    final shadowRect = Rect.fromLTWH(0, 0, size.width, size.height * .5);
    canvas.drawRect(
      shadowRect,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: <Color>[
            Colors.black.withValues(alpha: _wellShadowAlpha(brightness)),
            Colors.transparent,
          ],
        ).createShader(shadowRect),
    );
    canvas.restore();

    paintMachinedKnob(canvas, knobCenter, knobRadius, brightness: brightness);
  }

  @override
  bool shouldRepaint(_SwitchPainter oldDelegate) =>
      oldDelegate.t != t ||
      oldDelegate.brightness != brightness ||
      oldDelegate.lit != lit;
}

/// A labeled switch row: title and subtitle on the left, the metallic switch
/// on the right. The whole row toggles.
///
/// The row is one merged switch node — title as the label, subtitle as the
/// hint — with a single focus stop that Space or Enter throws.
class HardwareSwitchTile extends StatelessWidget {
  const HardwareSwitchTile({
    required this.title,
    required this.value,
    required this.onChanged,
    super.key,
    this.subtitle,
    this.semanticLabel,
  });

  final String title;
  final String? subtitle;
  final bool value;
  final ValueChanged<bool>? onChanged;

  /// Overrides [title] as the spoken name, for titles that only read well
  /// with their surrounding section.
  final String? semanticLabel;

  /// The switch grows to [kHardwareTouchTarget] under a finger, so the row
  /// gives back the same padding and keeps its drawn height.
  static const double _switchBoxHeight = 34;

  @override
  Widget build(BuildContext context) {
    final enabled = onChanged != null;
    final inset = isHardwareTouchPlatform
        ? math.max(0.0, 8 - (kHardwareTouchTarget - _switchBoxHeight) / 2)
        : 8.0;
    return MergeSemantics(
      child: Semantics(
        container: true,
        toggled: value,
        enabled: enabled,
        label: semanticLabel ?? title,
        hint: subtitle,
        child: InkWell(
          borderRadius: BorderRadius.circular(11),
          onTap: enabled
              ? () {
                  hardwareSelectionFeedback();
                  onChanged!(!value);
                }
              : null,
          child: Padding(
            padding: EdgeInsets.symmetric(vertical: inset),
            child: Row(
              children: <Widget>[
                Expanded(
                  // The row already speaks these; repeating them would read
                  // the title twice.
                  child: ExcludeSemantics(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Text(
                          title,
                          style: const TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        if (subtitle != null) ...<Widget>[
                          const SizedBox(height: 1),
                          Text(
                            subtitle!,
                            style: TextStyle(
                              fontSize: 11,
                              color: context.colors.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                ExcludeSemantics(
                  child: HardwareSwitch(
                    value: value,
                    onChanged: onChanged,
                    canRequestFocus: false,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// A recessed counter window that displays the current value of a control,
/// like the printed readout on studio hardware. The window is shadowed cream
/// with ink numerals in light mode and a dark pane with cream numerals in
/// dark mode, so neither mode gets a foreign-looking island.
class CounterReadout extends StatelessWidget {
  const CounterReadout(
    this.text, {
    super.key,
    this.unit,
    this.semanticLabel,
    this.unitLabel,
  });

  final String text;
  final String? unit;

  /// What the window counts, e.g. 'Frame rate'. Without it the numerals are
  /// announced bare.
  final String? semanticLabel;

  /// The spoken form of [unit], e.g. 'frames per second' for `fps`.
  final String? unitLabel;

  /// The window's one-node announcement: numerals plus a pronounceable unit.
  String get _spoken {
    final spokenUnit = unitLabel ?? unit;
    return spokenUnit == null ? text : '$text $spokenUnit';
  }

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return Semantics(
      container: true,
      readOnly: true,
      label: semanticLabel,
      value: _spoken,
      // One node for the whole window; the numerals and the unit would
      // otherwise be read as two unrelated scraps.
      excludeSemantics: true,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: _readoutWindowDecoration(dark),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Text(text, style: _readoutNumeralStyle(context, dark)),
            if (unit != null) ...<Widget>[
              const SizedBox(width: 4),
              Text(unit!, style: _readoutUnitStyle(context, dark)),
            ],
          ],
        ),
      ),
    );
  }
}

BoxDecoration _readoutWindowDecoration(bool dark) => BoxDecoration(
  borderRadius: BorderRadius.circular(7),
  border: Border.all(
    color: dark ? Colors.black.withValues(alpha: .45) : const Color(0xFFC5B79E),
    width: .8,
  ),
  gradient: dark
      ? const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: <Color>[Color(0xFF191317), Color(0xFF2E242C)],
        )
      : const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: <Color>[Color(0xFFE6DBC3), Color(0xFFF6F0E0)],
        ),
  boxShadow: <BoxShadow>[
    BoxShadow(
      color: Colors.white.withValues(alpha: dark ? .08 : .8),
      offset: const Offset(0, 1),
      blurRadius: 0,
    ),
  ],
);

TextStyle _readoutNumeralStyle(BuildContext context, bool dark) => TextStyle(
  fontFamily: 'Fraunces',
  fontSize: 13,
  fontWeight: FontWeight.w600,
  letterSpacing: .4,
  color: dark ? ClawnsoleColors.cream : context.colors.onSurface,
);

TextStyle _readoutUnitStyle(BuildContext context, bool dark) => TextStyle(
  fontSize: 10.5,
  fontWeight: FontWeight.w700,
  color: dark ? ClawnsoleColors.creamMuted : context.colors.onSurfaceVariant,
);

/// A [CounterReadout] whose numerals can be typed: the same recessed counter
/// window, but the value is a digits-only text field that commits on submit
/// or focus loss. Unparseable input snaps back to the last real value.
class CounterReadoutField extends StatefulWidget {
  const CounterReadoutField({
    required this.value,
    required this.onCommit,
    super.key,
    this.unit,
    this.fieldKey,
    this.enabled = true,
    this.onEditingStarted,
    this.semanticLabel,
    this.unitLabel,
  });

  /// The committed value to display while not editing (may be non-numeric,
  /// like AUTO).
  final String value;

  /// Receives the typed number on submit or blur; the owner clamps it.
  final ValueChanged<int> onCommit;
  final String? unit;

  /// Key applied to the inner text field so tests can type into it.
  final Key? fieldKey;
  final bool enabled;

  /// Called when the field gains focus, before any digits arrive — the hook
  /// that lets an AUTO readout drop to manual the moment it is touched.
  final VoidCallback? onEditingStarted;

  /// What the window counts, e.g. 'Duration'. Without it the field is
  /// announced as an unnamed edit box.
  final String? semanticLabel;

  /// The spoken form of [unit], e.g. 'seconds' for `s`.
  final String? unitLabel;

  @override
  State<CounterReadoutField> createState() => _CounterReadoutFieldState();
}

class _CounterReadoutFieldState extends State<CounterReadoutField> {
  late final TextEditingController _text = TextEditingController(
    text: widget.value,
  );
  final FocusNode _focus = FocusNode();

  @override
  void initState() {
    super.initState();
    _focus.addListener(_handleFocusChange);
  }

  @override
  void didUpdateWidget(covariant CounterReadoutField oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!_focus.hasFocus && _text.text != widget.value) {
      _text.text = widget.value;
    }
  }

  @override
  void dispose() {
    _focus
      ..removeListener(_handleFocusChange)
      ..dispose();
    _text.dispose();
    super.dispose();
  }

  void _handleFocusChange() {
    if (_focus.hasFocus) {
      widget.onEditingStarted?.call();
      // Select everything so typing replaces the shown value (which may be a
      // non-numeric AUTO placeholder).
      _text.selection = TextSelection(
        baseOffset: 0,
        extentOffset: _text.text.length,
      );
    } else {
      _commit();
    }
  }

  void _commit() {
    final parsed = int.tryParse(_text.text.trim());
    if (parsed != null) {
      widget.onCommit(parsed);
      // Keep the parsed digits so a follow-up blur commit re-submits the
      // same number; the owner's rebuild then syncs in the clamped value.
      _text.text = '$parsed';
    } else {
      _text.text = widget.value;
    }
  }

  /// 'Duration, seconds' — the field itself supplies the number and the
  /// "editable" role.
  String? get _label {
    final spokenUnit = widget.unitLabel ?? widget.unit;
    final parts = <String>[
      if (widget.semanticLabel != null) widget.semanticLabel!,
      if (spokenUnit != null) spokenUnit,
    ];
    return parts.isEmpty ? null : parts.join(', ');
  }

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return MergeSemantics(
      child: Semantics(
        container: true,
        enabled: widget.enabled,
        label: _label,
        child: Opacity(
          opacity: widget.enabled ? 1 : .55,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: _readoutWindowDecoration(dark),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                SizedBox(
                  width: 46,
                  child: TextField(
                    key: widget.fieldKey,
                    controller: _text,
                    focusNode: _focus,
                    enabled: widget.enabled,
                    keyboardType: TextInputType.number,
                    inputFormatters: <TextInputFormatter>[
                      FilteringTextInputFormatter.digitsOnly,
                    ],
                    textAlign: TextAlign.right,
                    style: _readoutNumeralStyle(context, dark),
                    cursorColor: dark
                        ? ClawnsoleColors.cream
                        : context.colors.onSurface,
                    decoration: null,
                    onSubmitted: (_) => _commit(),
                  ),
                ),
                if (widget.unit != null) ...<Widget>[
                  const SizedBox(width: 4),
                  // Spoken by the label above, in words rather than 's'.
                  ExcludeSemantics(
                    child: Text(
                      widget.unit!,
                      style: _readoutUnitStyle(context, dark),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Decoration for selection tiles that behave like console keys: raised when
/// idle, lit plum and gently pressed when selected.
BoxDecoration consoleKeyDecoration(
  BuildContext context, {
  required bool selected,
  double radius = 11,
}) {
  final colors = context.colors;
  final dark = Theme.of(context).brightness == Brightness.dark;
  if (selected) {
    return BoxDecoration(
      borderRadius: BorderRadius.circular(radius),
      border: Border.all(color: colors.primary),
      gradient: LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: <Color>[
          Color.lerp(colors.primary, Colors.white, .14)!,
          colors.primary,
          Color.lerp(colors.primary, Colors.black, .12)!,
        ],
        stops: const <double>[0, .45, 1],
      ),
      boxShadow: <BoxShadow>[
        BoxShadow(
          color: colors.primary.withValues(alpha: dark ? .45 : .3),
          blurRadius: 9,
          offset: const Offset(0, 2),
        ),
      ],
    );
  }
  return BoxDecoration(
    borderRadius: BorderRadius.circular(radius),
    border: Border.all(color: colors.outlineVariant),
    gradient: LinearGradient(
      begin: Alignment.topCenter,
      end: Alignment.bottomCenter,
      colors: <Color>[
        Color.lerp(colors.surfaceContainerLow, Colors.white, dark ? .045 : .5)!,
        colors.surfaceContainerLow,
      ],
      stops: const <double>[0, .5],
    ),
  );
}
