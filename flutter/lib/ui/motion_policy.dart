import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

/// Whether continuous, decorative motion may run right now.
///
/// Two independent reasons hold it still. [reduceMotion] is the person's
/// preference — the platform's reduce-motion setting, on web read from
/// `prefers-reduced-motion`, on native from `MediaQuery.disableAnimations`.
/// [constrained] is the renderer's own brake: the desktop diagnostics latch it
/// when the CanvasKit heap nears its hard cap, because every continuous
/// animation there is another step toward the abort.
@immutable
class MotionPolicy {
  const MotionPolicy({this.reduceMotion = false, this.constrained = false});

  /// The person asked for reduced motion.
  final bool reduceMotion;

  /// The renderer asked for calm to protect itself.
  final bool constrained;

  /// True when a placeholder, chip, or lamp may animate at all.
  bool get animates => !reduceMotion && !constrained;

  /// The policy above [context]: the nearest [MotionPolicyScope] combined
  /// with the ambient `MediaQuery.disableAnimations`, so native targets need
  /// no scope of their own. Registers a dependency on both.
  static MotionPolicy of(BuildContext context) {
    final scope = context
        .dependOnInheritedWidgetOfExactType<MotionPolicyScope>();
    final ambient = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    return MotionPolicy(
      reduceMotion: ambient || (scope?.reduceMotion?.value ?? false),
      constrained: scope?.constrained?.value ?? false,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is MotionPolicy &&
      other.reduceMotion == reduceMotion &&
      other.constrained == constrained;

  @override
  int get hashCode => Object.hash(reduceMotion, constrained);

  @override
  String toString() =>
      'MotionPolicy(reduceMotion: $reduceMotion, constrained: $constrained)';
}

/// Publishes a [MotionPolicy] to the tree from two live sources.
///
/// Dependents rebuild when either source changes. Either may be omitted, in
/// which case that reason is simply never true.
class MotionPolicyScope extends InheritedNotifier<Listenable> {
  MotionPolicyScope({
    required super.child,
    super.key,
    this.reduceMotion,
    this.constrained,
  }) : super(
         notifier: Listenable.merge(<Listenable?>[reduceMotion, constrained]),
       );

  /// The platform's reduce-motion preference.
  final ValueListenable<bool>? reduceMotion;

  /// The renderer's memory brake.
  final ValueListenable<bool>? constrained;

  /// The nearest scope's policy without the ambient media query, or null
  /// outside any scope.
  static MotionPolicy? maybeOf(BuildContext context) {
    final scope = context
        .dependOnInheritedWidgetOfExactType<MotionPolicyScope>();
    if (scope == null) return null;
    return MotionPolicy(
      reduceMotion: scope.reduceMotion?.value ?? false,
      constrained: scope.constrained?.value ?? false,
    );
  }

  /// The merged notifier is rebuilt on every construction and has no value
  /// equality, so the inherited default (notifier identity) would wake every
  /// dependent each time the app rebuilds. Only a change of source counts;
  /// value changes reach dependents through the subscription, which the
  /// element renews on every update.
  @override
  bool updateShouldNotify(MotionPolicyScope oldWidget) =>
      !identical(oldWidget.reduceMotion, reduceMotion) ||
      !identical(oldWidget.constrained, constrained);
}
