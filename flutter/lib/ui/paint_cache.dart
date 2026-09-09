import 'dart:collection';
import 'dart:ui' as ui;

/// A small least-recently-used store of shaders keyed by what they were built
/// from, so a painter that runs many times at the same size hands the engine
/// the same native object each time instead of a fresh one.
///
/// On CanvasKit every `ui.Gradient` and `ImageShader` is a Wasm allocation
/// that only a JavaScript finalizer ever frees, and the finalizer cannot keep
/// up with a painter creating several per frame. Creating them once per
/// (size, theme) and reusing them across paints removes that pressure while
/// leaving the pixels untouched.
///
/// Evicted and cleared shaders are disposed. The owner — a `State`, or the
/// module for stateless painters — calls [clear] when it goes away.
class ShaderCache<K extends Object> {
  ShaderCache({this.capacity = 16}) : assert(capacity > 0);

  final int capacity;
  final LinkedHashMap<K, ui.Shader> _entries = LinkedHashMap<K, ui.Shader>();

  int get length => _entries.length;

  /// The shader for [key], created with [create] on the first request.
  ui.Shader obtain(K key, ui.Shader Function() create) {
    final existing = _entries.remove(key);
    if (existing != null) {
      _entries[key] = existing;
      return existing;
    }
    final shader = create();
    _entries[key] = shader;
    while (_entries.length > capacity) {
      final oldest = _entries.keys.first;
      _entries.remove(oldest)?.dispose();
    }
    return shader;
  }

  /// Disposes every shader held.
  void clear() {
    for (final shader in _entries.values) {
      shader.dispose();
    }
    _entries.clear();
  }
}

/// The same least-recently-used store for geometry that is expensive to
/// build — a dashed outline, a tab silhouette — but cheap to keep.
class PathCache<K extends Object> {
  PathCache({this.capacity = 32}) : assert(capacity > 0);

  final int capacity;
  final LinkedHashMap<K, ui.Path> _entries = LinkedHashMap<K, ui.Path>();

  int get length => _entries.length;

  ui.Path obtain(K key, ui.Path Function() create) {
    final existing = _entries.remove(key);
    if (existing != null) {
      _entries[key] = existing;
      return existing;
    }
    final path = create();
    _entries[key] = path;
    while (_entries.length > capacity) {
      _entries.remove(_entries.keys.first);
    }
    return path;
  }

  void clear() => _entries.clear();
}
