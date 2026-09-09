import 'package:flutter/foundation.dart';

/// A live view of the platform's reduce-motion preference.
///
/// Native targets receive the preference through Flutter's own accessibility
/// features (`MediaQuery.disableAnimations`), so this source stays off and
/// never changes.
class ReducedMotionWatcher {
  ReducedMotionWatcher();

  final ValueNotifier<bool> _value = ValueNotifier<bool>(false);

  /// True while the platform asks for reduced motion.
  ValueListenable<bool> get reduceMotion => _value;

  void dispose() => _value.dispose();
}
