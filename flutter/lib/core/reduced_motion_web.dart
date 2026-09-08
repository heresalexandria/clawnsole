import 'dart:js_interop';

import 'package:flutter/foundation.dart';
import 'package:web/web.dart' as web;

/// A live view of the platform's reduce-motion preference, read from the
/// `prefers-reduced-motion: reduce` media feature and followed as it changes.
///
/// Flutter web never maps the operating system's preference onto
/// `MediaQuery.disableAnimations`, so without this the desktop renderer would
/// keep every continuous animation running for a person who asked it not to.
class ReducedMotionWatcher {
  ReducedMotionWatcher() {
    try {
      final query = web.window.matchMedia('(prefers-reduced-motion: reduce)');
      _query = query;
      _value.value = query.matches;
      _listener = ((web.Event _) {
        _value.value = query.matches;
      }).toJS;
      query.addEventListener('change', _listener);
    } on Object {
      // A test harness or an unusual embedder without matchMedia: the
      // preference simply reads as off, as it always has.
      _query = null;
      _listener = null;
    }
  }

  final ValueNotifier<bool> _value = ValueNotifier<bool>(false);
  web.MediaQueryList? _query;
  JSFunction? _listener;

  /// True while the platform asks for reduced motion.
  ValueListenable<bool> get reduceMotion => _value;

  void dispose() {
    final query = _query;
    final listener = _listener;
    if (query != null && listener != null) {
      try {
        query.removeEventListener('change', listener);
      } on Object {
        // Nothing left to unhook.
      }
    }
    _query = null;
    _listener = null;
    _value.dispose();
  }
}
