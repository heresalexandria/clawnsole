import 'dart:async';
import 'dart:collection';

/// Limits expensive asynchronous work without blocking the UI isolate.
/// Callers can check whether queued work is still needed inside [run]'s
/// callback, before allocating its resources.
class AsyncWorkPool {
  AsyncWorkPool({required this.maximumConcurrent})
    : assert(maximumConcurrent > 0);

  final int maximumConcurrent;
  final Queue<void Function()> _pending = Queue<void Function()>();
  int _active = 0;

  Future<T> run<T>(Future<T> Function() action) {
    final result = Completer<T>();
    _pending.add(() {
      _active += 1;
      Future<T>.sync(
        action,
      ).then(result.complete, onError: result.completeError).whenComplete(() {
        _active -= 1;
        _startPending();
      });
    });
    _startPending();
    return result.future;
  }

  void _startPending() {
    while (_active < maximumConcurrent && _pending.isNotEmpty) {
      _pending.removeFirst()();
    }
  }
}
