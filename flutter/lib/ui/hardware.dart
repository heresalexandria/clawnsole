import 'dart:math' as math;

import 'package:flutter/material.dart';

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
}) {
  final dark = brightness == Brightness.dark;

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

/// A [Slider] dressed as console hardware: a machined knob traveling a
/// recessed groove whose filled side lights up plum.
class HardwareSlider extends StatelessWidget {
  const HardwareSlider({
    required this.value,
    required this.onChanged,
    super.key,
    this.min = 0,
    this.max = 1,
    this.divisions,
    this.label,
  });

  final double value;
  final ValueChanged<double>? onChanged;
  final double min;
  final double max;
  final int? divisions;
  final String? label;

  @override
  Widget build(BuildContext context) {
    final brightness = Theme.of(context).brightness;
    final lit = _litPlum(brightness);
    return SliderTheme(
      data: SliderTheme.of(context).copyWith(
        trackHeight: 9,
        trackShape: const _RecessedGrooveTrack(),
        thumbShape: _MachinedKnobThumb(radius: 14, indicator: lit),
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
        value: value,
        min: min,
        max: max,
        divisions: divisions,
        label: label,
        onChanged: onChanged,
      ),
    );
  }
}

class _MachinedKnobThumb extends SliderComponentShape {
  const _MachinedKnobThumb({required this.radius, required this.indicator});

  final double radius;
  final Color indicator;

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
    );
  }
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
class HardwareSwitch extends StatefulWidget {
  const HardwareSwitch({
    required this.value,
    required this.onChanged,
    super.key,
  });

  final bool value;
  final ValueChanged<bool>? onChanged;

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

  @override
  Widget build(BuildContext context) {
    final enabled = widget.onChanged != null;
    final brightness = Theme.of(context).brightness;
    return Semantics(
      container: true,
      enabled: enabled,
      toggled: widget.value,
      child: Opacity(
        opacity: enabled ? 1 : .45,
        child: InkWell(
          borderRadius: BorderRadius.circular(999),
          onTap: enabled ? () => widget.onChanged!(!widget.value) : null,
          child: Padding(
            padding: const EdgeInsets.all(3),
            child: AnimatedBuilder(
              animation: _position,
              builder: (context, _) => CustomPaint(
                size: const Size(50, 28),
                painter: _SwitchPainter(
                  t: Curves.easeOut.transform(_position.value),
                  brightness: brightness,
                  // The money green, tuned per mode: a signal lamp on paper,
                  // the cost panel's felt at night.
                  lit: context.tokens.switchOn,
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
class HardwareChoiceSwitch extends StatelessWidget {
  const HardwareChoiceSwitch({
    required this.firstLabel,
    required this.secondLabel,
    required this.firstSelected,
    required this.onChanged,
    super.key,
    this.firstKey,
    this.secondKey,
  });

  final String firstLabel;
  final String secondLabel;
  final bool firstSelected;
  final ValueChanged<bool>? onChanged;
  final Key? firstKey;
  final Key? secondKey;

  @override
  Widget build(BuildContext context) {
    final enabled = onChanged != null;
    final brightness = Theme.of(context).brightness;
    final dark = brightness == Brightness.dark;
    final selectedText = dark
        ? const Color(0xFF242025)
        : ClawnsoleColors.plumInk;
    return Opacity(
      opacity: enabled ? 1 : .55,
      child: Container(
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
              color: Colors.black.withValues(
                alpha: _wellShadowAlpha(brightness),
              ),
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
                    onTap: () => onChanged!(true),
                  ),
                ),
                Expanded(
                  child: _HardwareChoice(
                    key: secondKey,
                    label: secondLabel,
                    selected: !firstSelected,
                    enabled: enabled,
                    selectedText: selectedText,
                    onTap: () => onChanged!(false),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
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
  });

  final String label;
  final bool selected;
  final bool enabled;
  final Color selectedText;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    selected: selected,
    enabled: enabled,
    label: label,
    child: InkWell(
      borderRadius: BorderRadius.circular(7),
      onTap: enabled ? onTap : null,
      child: Center(
        child: Text(
          label,
          style: TextStyle(
            fontSize: 10.5,
            fontWeight: FontWeight.w700,
            letterSpacing: .7,
            color: selected ? selectedText : context.colors.onSurfaceVariant,
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
class HardwareSwitchTile extends StatelessWidget {
  const HardwareSwitchTile({
    required this.title,
    required this.value,
    required this.onChanged,
    super.key,
    this.subtitle,
  });

  final String title;
  final String? subtitle;
  final bool value;
  final ValueChanged<bool>? onChanged;

  @override
  Widget build(BuildContext context) {
    final enabled = onChanged != null;
    return InkWell(
      borderRadius: BorderRadius.circular(11),
      onTap: enabled ? () => onChanged!(!value) : null,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Row(
          children: <Widget>[
            Expanded(
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
            const SizedBox(width: 12),
            HardwareSwitch(value: value, onChanged: onChanged),
          ],
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
  const CounterReadout(this.text, {super.key, this.unit});

  final String text;
  final String? unit;

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(7),
        border: Border.all(
          color: dark
              ? Colors.black.withValues(alpha: .45)
              : const Color(0xFFC5B79E),
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
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Text(
            text,
            style: TextStyle(
              fontFamily: 'Fraunces',
              fontSize: 13,
              fontWeight: FontWeight.w600,
              letterSpacing: .4,
              color: dark ? ClawnsoleColors.cream : context.colors.onSurface,
            ),
          ),
          if (unit != null) ...<Widget>[
            const SizedBox(width: 4),
            Text(
              unit!,
              style: TextStyle(
                fontSize: 10.5,
                fontWeight: FontWeight.w700,
                color: dark
                    ? ClawnsoleColors.creamMuted
                    : context.colors.onSurfaceVariant,
              ),
            ),
          ],
        ],
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
