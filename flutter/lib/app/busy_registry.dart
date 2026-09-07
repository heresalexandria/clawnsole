import 'package:flutter/foundation.dart';

/// Which library items are working right now, by kind and id.
///
/// An action can start far from the thing it changes — a menu that has
/// already closed, a snackbar's recovery button, a card dropped on a folder —
/// and the card or row still has to show that it is working. Controller-side
/// actions wrap their work in [run] and the surfaces read [isBusy] through a
/// `ListenableBuilder`, so the loader appears wherever the item is drawn
/// rather than only where the tap landed.
///
/// Kinds in use: `generation`, `reference`, `folder`, `provider`.
class BusyRegistry extends ChangeNotifier {
  /// How many runs hold each key. Counted, not a plain set, so two actions on
  /// one item (a hide and a move) cannot clear each other's loader.
  final Map<String, int> _depths = <String, int>{};
  bool _disposed = false;

  static String keyFor(String kind, String id) => '$kind:$id';

  /// Whether anything is working on [id] of [kind].
  bool isBusy(String kind, String id) => _depths.containsKey(keyFor(kind, id));

  /// Whether anything at all is working.
  bool get isAnyBusy => _depths.isNotEmpty;

  /// The keys working right now, for diagnostics and tests.
  @visibleForTesting
  Set<String> get busyKeys => _depths.keys.toSet();

  /// Runs [action] with [id] of [kind] marked busy, clearing the mark when it
  /// finishes — including when it throws, whose error is passed on unchanged.
  Future<T> run<T>(String kind, String id, Future<T> Function() action) async {
    final key = keyFor(kind, id);
    final depth = _depths[key] ?? 0;
    _depths[key] = depth + 1;
    if (depth == 0) _notify();
    try {
      return await action();
    } finally {
      final held = _depths[key] ?? 1;
      if (held <= 1) {
        _depths.remove(key);
        _notify();
      } else {
        _depths[key] = held - 1;
      }
    }
  }

  void _notify() {
    // Work can outlive the controller that started it; a finished job must
    // not wake a disposed notifier.
    if (_disposed) return;
    notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _depths.clear();
    super.dispose();
  }
}
