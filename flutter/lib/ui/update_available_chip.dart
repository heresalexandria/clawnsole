import 'dart:math' as math;

import 'package:flutter/material.dart';

/// The desktop affordance for a newer release.
class UpdateAvailableChip extends StatefulWidget {
  const UpdateAvailableChip({
    required this.onPressed,
    required this.installable,
    super.key,
    this.version,
  });

  final VoidCallback onPressed;
  final bool installable;
  final String? version;

  @override
  State<UpdateAvailableChip> createState() => _UpdateAvailableChipState();
}

class _UpdateAvailableChipState extends State<UpdateAvailableChip>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 6),
    value: .12,
  );
  bool _animating = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final shouldAnimate = !MediaQuery.disableAnimationsOf(context);
    if (shouldAnimate == _animating) return;
    _animating = shouldAnimate;
    if (shouldAnimate) {
      _controller.repeat();
    } else {
      _controller.stop();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final version = widget.version;
    return Semantics(
      button: true,
      label: version == null
          ? widget.installable
                ? 'Update available. Download and install.'
                : 'Update available. View release.'
          : widget.installable
          ? 'Clawnsole $version is available. Download and install.'
          : 'Clawnsole $version is available. View release.',
      child: Tooltip(
        message: widget.installable
            ? version == null
                  ? 'Download and install the Clawnsole update'
                  : 'Download and install Clawnsole $version'
            : version == null
            ? 'View the Clawnsole update'
            : 'View Clawnsole $version',
        child: AnimatedBuilder(
          animation: _controller,
          builder: (context, child) {
            final phase = _controller.value * math.pi * 2;
            final blend = (math.sin(phase) + 1) / 2;
            final center = Alignment(
              math.cos(phase) * .72,
              math.sin(phase * 1.35) * .58,
            );
            final glow = Color.lerp(
              const Color(0xFF2563EB),
              const Color(0xFF8B5CF6),
              blend,
            )!;
            final middle = Color.lerp(
              const Color(0xFF6D28D9),
              const Color(0xFF1D4ED8),
              blend,
            )!;
            return Material(
              color: Colors.transparent,
              child: Ink(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(999),
                  border: Border.all(
                    color: Colors.white.withValues(alpha: .28),
                  ),
                  gradient: RadialGradient(
                    center: center,
                    radius: 1.2,
                    colors: <Color>[glow, middle, const Color(0xFF312E81)],
                    stops: const <double>[0, .58, 1],
                  ),
                  boxShadow: <BoxShadow>[
                    BoxShadow(
                      color: middle.withValues(alpha: .3),
                      blurRadius: 12,
                      spreadRadius: -2,
                    ),
                  ],
                ),
                child: InkWell(
                  key: const Key('update-available-chip'),
                  onTap: widget.onPressed,
                  borderRadius: BorderRadius.circular(999),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 11,
                      vertical: 7,
                    ),
                    child: const Text(
                      'Update Available',
                      maxLines: 1,
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        letterSpacing: .15,
                      ),
                    ),
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}
