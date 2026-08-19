import 'dart:math' as math;

import 'package:flutter/material.dart';

/// A compact affordance for a newer release on desktop and mobile.
class UpdateAvailableChip extends StatefulWidget {
  const UpdateAvailableChip({
    required this.onPressed,
    super.key,
    this.compact = false,
    this.version,
  });

  final VoidCallback onPressed;
  final bool compact;
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
          ? 'Update available. View update options.'
          : 'Clawnsole $version is available. View update options.',
      child: Tooltip(
        message: version == null
            ? 'View the available Clawnsole update'
            : 'View the Clawnsole $version update',
        child: SizedBox(
          width: widget.compact ? 64 : null,
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
                      padding: EdgeInsets.symmetric(
                        horizontal: widget.compact ? 7 : 11,
                        vertical: widget.compact ? 5 : 7,
                      ),
                      child: FittedBox(
                        fit: BoxFit.scaleDown,
                        child: Text(
                          widget.compact ? 'Update' : 'Update Available',
                          maxLines: 1,
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: widget.compact ? 10.5 : 11,
                            fontWeight: FontWeight.w700,
                            letterSpacing: .15,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}
