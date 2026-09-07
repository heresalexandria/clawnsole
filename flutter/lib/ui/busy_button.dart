import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

/// Clawnsole's one busy mark: a 14 px ring drawn with a 2 px stroke in the
/// host's current foreground colour, so a working control reads as the same
/// control rather than as a stray brand-coloured ornament.
const double kBusySpinnerSize = 14;

/// The stroke that goes with [kBusySpinnerSize].
const double kBusySpinnerStroke = 2;

/// The gap between a leading spinner and the label it precedes.
const double _busyLabelGap = 8;

/// The busy mark on its own, for hosts that are not buttons: a list row, a
/// tile, a menu entry. Inside a button the colour resolves to that button's
/// current foreground; elsewhere it follows the ambient icon colour.
class BusySpinner extends StatelessWidget {
  const BusySpinner({super.key, this.size = kBusySpinnerSize, this.color});

  final double size;
  final Color? color;

  @override
  Widget build(BuildContext context) => SizedBox.square(
    dimension: size,
    child: CircularProgressIndicator(
      strokeWidth: kBusySpinnerStroke,
      color: color ?? IconTheme.of(context).color,
    ),
  );
}

/// Which Material button a [BusyButton] wears.
enum BusyButtonVariant { filled, tonal, outlined, text, icon }

/// A Material button that owns the loader for its own action.
///
/// [onPressed] is asynchronous: while the future it returns is pending the
/// button is disabled and shows a [BusySpinner] — in the icon slot for the
/// icon variants, leading the label for the plain ones — so no action can
/// hang silently. Pass [busy] when the state lives somewhere else (a
/// controller flag, the app's busy registry); the two combine, so a
/// controller-owned flag and a locally awaited future both light the same
/// spinner.
///
/// Exceptions from [onPressed] propagate once the busy state has cleared,
/// re-entrant taps are ignored, and a button that leaves the tree mid-flight
/// never calls `setState` afterwards.
///
/// Prefer the named variants — [BusyFilledButton], [BusyOutlinedButton],
/// [BusyTextButton], [BusyIconButton] — which mirror the Material shapes.
class BusyButton extends StatefulWidget {
  const BusyButton({
    required this.onPressed,
    this.variant = BusyButtonVariant.filled,
    this.child,
    this.icon,
    this.label,
    this.busy,
    this.busyLabel,
    this.style,
    this.tooltip,
    super.key,
  }) : assert(
         variant != BusyButtonVariant.icon ||
             (icon != null && label == null && child == null),
         'An icon button carries an icon and no label.',
       ),
       assert(
         variant == BusyButtonVariant.icon ||
             (child == null) != (label == null),
         'Give a button either a child or a label, not both.',
       ),
       assert(
         variant == BusyButtonVariant.icon || label == null || icon != null,
         'A label needs an icon beside it.',
       );

  /// The work the button starts. The button stays busy until the returned
  /// future settles.
  final Future<void> Function()? onPressed;
  final BusyButtonVariant variant;

  /// The plain button's content. Mutually exclusive with [label].
  final Widget? child;

  /// The icon variants' icon, or the icon button's icon.
  final Widget? icon;

  /// The icon variants' label. Replaced by [busyLabel] while busy.
  final Widget? label;

  /// Busy state owned elsewhere, combined with this button's own future.
  final bool? busy;

  /// What the label says while the work runs, e.g. 'Saving…'.
  final String? busyLabel;
  final ButtonStyle? style;

  /// Icon buttons only.
  final String? tooltip;

  @override
  State<BusyButton> createState() => _BusyButtonState();
}

class _BusyButtonState extends State<BusyButton> {
  bool _running = false;

  bool get _busy => _running || (widget.busy ?? false);

  void _handleTap() => unawaited(_press());

  Future<void> _press() async {
    final action = widget.onPressed;
    // A second tap while the first is still in flight is not a second run.
    if (action == null || _busy) return;
    final gate = BusyGate._stateOf(context);
    setState(() => _running = true);
    gate?._acquire();
    try {
      await action();
    } finally {
      // The work can outlive the button — a dialog that pops on success, a
      // card the library rebuilt away — so clear the flag without touching a
      // disposed element.
      if (mounted) {
        setState(() => _running = false);
      } else {
        _running = false;
      }
      gate?._release();
    }
  }

  Widget _plainChild(bool busy) {
    final child = widget.child!;
    if (!busy) return child;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        const BusySpinner(),
        const SizedBox(width: _busyLabelGap),
        Flexible(
          child: widget.busyLabel == null ? child : Text(widget.busyLabel!),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final busy = _busy;
    final onPressed = widget.onPressed == null || busy ? null : _handleTap;
    final icon = widget.icon;
    final label = busy && widget.busyLabel != null
        ? Text(widget.busyLabel!)
        : widget.label;
    return switch (widget.variant) {
      BusyButtonVariant.icon => IconButton(
        onPressed: onPressed,
        style: widget.style,
        tooltip: widget.tooltip,
        icon: _BusyIconSlot(busy: busy, icon: icon!),
      ),
      BusyButtonVariant.filled when icon == null => FilledButton(
        onPressed: onPressed,
        style: widget.style,
        child: _plainChild(busy),
      ),
      BusyButtonVariant.filled => FilledButton.icon(
        onPressed: onPressed,
        style: widget.style,
        icon: _BusyIconSlot(busy: busy, icon: icon!),
        label: label!,
      ),
      BusyButtonVariant.tonal when icon == null => FilledButton.tonal(
        onPressed: onPressed,
        style: widget.style,
        child: _plainChild(busy),
      ),
      BusyButtonVariant.tonal => FilledButton.tonalIcon(
        onPressed: onPressed,
        style: widget.style,
        icon: _BusyIconSlot(busy: busy, icon: icon!),
        label: label!,
      ),
      BusyButtonVariant.outlined when icon == null => OutlinedButton(
        onPressed: onPressed,
        style: widget.style,
        child: _plainChild(busy),
      ),
      BusyButtonVariant.outlined => OutlinedButton.icon(
        onPressed: onPressed,
        style: widget.style,
        icon: _BusyIconSlot(busy: busy, icon: icon!),
        label: label!,
      ),
      BusyButtonVariant.text when icon == null => TextButton(
        onPressed: onPressed,
        style: widget.style,
        child: _plainChild(busy),
      ),
      BusyButtonVariant.text => TextButton.icon(
        onPressed: onPressed,
        style: widget.style,
        icon: _BusyIconSlot(busy: busy, icon: icon!),
        label: label!,
      ),
    };
  }
}

/// The icon slot, sized once and kept: the spinner swaps in where the icon
/// stood, so a button never resizes or shifts its label when work starts.
class _BusyIconSlot extends StatelessWidget {
  const _BusyIconSlot({required this.busy, required this.icon});

  final bool busy;
  final Widget icon;

  @override
  Widget build(BuildContext context) {
    final drawn = icon;
    final size = drawn is Icon && drawn.size != null
        ? drawn.size!
        : IconTheme.of(context).size ?? 18;
    return SizedBox.square(
      dimension: math.max(size, kBusySpinnerSize),
      child: Center(child: busy ? const BusySpinner() : icon),
    );
  }
}

/// A filled button that owns its own loader. See [BusyButton].
class BusyFilledButton extends BusyButton {
  const BusyFilledButton({
    required super.onPressed,
    required super.child,
    super.busy,
    super.busyLabel,
    super.style,
    super.key,
  }) : super(variant: BusyButtonVariant.filled);

  const BusyFilledButton.icon({
    required super.onPressed,
    required super.icon,
    required super.label,
    super.busy,
    super.busyLabel,
    super.style,
    super.key,
  }) : super(variant: BusyButtonVariant.filled);

  const BusyFilledButton.tonal({
    required super.onPressed,
    required super.child,
    super.busy,
    super.busyLabel,
    super.style,
    super.key,
  }) : super(variant: BusyButtonVariant.tonal);

  const BusyFilledButton.tonalIcon({
    required super.onPressed,
    required super.icon,
    required super.label,
    super.busy,
    super.busyLabel,
    super.style,
    super.key,
  }) : super(variant: BusyButtonVariant.tonal);
}

/// An outlined button that owns its own loader. See [BusyButton].
class BusyOutlinedButton extends BusyButton {
  const BusyOutlinedButton({
    required super.onPressed,
    required super.child,
    super.busy,
    super.busyLabel,
    super.style,
    super.key,
  }) : super(variant: BusyButtonVariant.outlined);

  const BusyOutlinedButton.icon({
    required super.onPressed,
    required super.icon,
    required super.label,
    super.busy,
    super.busyLabel,
    super.style,
    super.key,
  }) : super(variant: BusyButtonVariant.outlined);
}

/// A text button that owns its own loader. See [BusyButton].
class BusyTextButton extends BusyButton {
  const BusyTextButton({
    required super.onPressed,
    required super.child,
    super.busy,
    super.busyLabel,
    super.style,
    super.key,
  }) : super(variant: BusyButtonVariant.text);

  const BusyTextButton.icon({
    required super.onPressed,
    required super.icon,
    required super.label,
    super.busy,
    super.busyLabel,
    super.style,
    super.key,
  }) : super(variant: BusyButtonVariant.text);
}

/// An icon button that owns its own loader. See [BusyButton].
class BusyIconButton extends BusyButton {
  const BusyIconButton({
    required super.onPressed,
    required super.icon,
    super.tooltip,
    super.busy,
    super.style,
    super.key,
  }) : super(variant: BusyButtonVariant.icon);
}

/// Holds a dialog together while its primary action runs.
///
/// Wrap a dialog in a [BusyGate] and every [BusyButton] beneath it reports
/// its busy state upward, so Cancel, the fields and [PopScope] can read one
/// flag through [BusyGate.of] instead of threading a bool through the tree.
class BusyGate extends StatefulWidget {
  const BusyGate({required this.child, super.key});

  final Widget child;

  /// Whether work started by a [BusyButton] under the nearest gate is still
  /// running. Registers a dependency, so callers rebuild when it flips.
  static bool of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<_BusyGateScope>()?.busy ??
      false;

  static _BusyGateState? _stateOf(BuildContext context) =>
      context.getInheritedWidgetOfExactType<_BusyGateScope>()?.state;

  @override
  State<BusyGate> createState() => _BusyGateState();
}

class _BusyGateState extends State<BusyGate> {
  int _depth = 0;
  bool _closed = false;

  void _acquire() {
    if (_closed) return;
    setState(() => _depth += 1);
  }

  void _release() {
    // A gate that left with its dialog stays quiet: the button's `finally`
    // still runs, and there is nothing left to tell.
    if (_closed) return;
    setState(() => _depth = math.max(0, _depth - 1));
  }

  @override
  void dispose() {
    _closed = true;
    super.dispose();
  }

  @override
  Widget build(BuildContext context) =>
      _BusyGateScope(busy: _depth > 0, state: this, child: widget.child);
}

class _BusyGateScope extends InheritedWidget {
  const _BusyGateScope({
    required this.busy,
    required this.state,
    required super.child,
  });

  final bool busy;
  final _BusyGateState state;

  @override
  bool updateShouldNotify(_BusyGateScope oldWidget) => oldWidget.busy != busy;
}

/// Rebuilds [builder] with the nearest [BusyGate]'s state, for the siblings
/// of a busy button: Cancel, form fields, a [PopScope] that must hold.
class BusyGateBuilder extends StatelessWidget {
  const BusyGateBuilder({required this.builder, super.key});

  final Widget Function(BuildContext context, bool busy) builder;

  @override
  Widget build(BuildContext context) => builder(context, BusyGate.of(context));
}
