import 'dart:async';

/// Shares pending work and retains completed values within both entry and
/// weight budgets. Evicted pending work still completes for its callers, but
/// cannot repopulate the cache after eviction or a memory-pressure clear.
class AsyncValueCache<T> {
  AsyncValueCache({
    required this.maximumWeight,
    required this.weightOf,
    this.maximumEntries = 240,
  }) : assert(maximumWeight >= 0),
       assert(maximumEntries > 0);

  final int maximumWeight;
  final int maximumEntries;
  final int Function(T value) weightOf;
  final Map<Object, _CacheEntry<T>> _entries = <Object, _CacheEntry<T>>{};
  int _weight = 0;

  int get retainedWeight => _weight;
  int get length => _entries.length;
  bool get isEmpty => _entries.isEmpty;

  /// Returns a completed value without starting work, refreshing its recency.
  T? lookup(Object key) {
    final entry = _entries.remove(key);
    if (entry == null) return null;
    _entries[key] = entry;
    return entry.value;
  }

  /// Retains already available data under the same budgets as loaded values.
  void put(Object key, T value) {
    final weight = value == null ? -1 : weightOf(value);
    _remove(key);
    if (weight < 0 || weight > maximumWeight) return;
    _entries[key] = _CacheEntry(Future<T>.value(value))
      ..value = value
      ..weight = weight;
    _weight += weight;
    _trim();
  }

  void remove(Object key) => _remove(key);

  /// Reuses and touches pending or retained work without starting a loader.
  Future<T>? lookupFuture(Object key) {
    final cached = _entries.remove(key);
    if (cached != null) {
      _entries[key] = cached;
      return cached.future;
    }
    return null;
  }

  Future<T> load(Object key, Future<T> Function() loader) {
    final cached = lookupFuture(key);
    if (cached != null) return cached;

    final result = Completer<T>();
    final entry = _CacheEntry(result.future);
    _entries[key] = entry;
    _trim();
    Future<T>.sync(loader).then(
      (value) {
        try {
          if (identical(_entries[key], entry)) {
            final weight = value == null ? 0 : weightOf(value);
            if (value == null || weight < 0 || weight > maximumWeight) {
              _remove(key);
            } else {
              entry.value = value;
              entry.weight = weight;
              _weight += weight;
              _trim();
            }
          }
          result.complete(value);
        } on Object catch (error, stack) {
          if (identical(_entries[key], entry)) _remove(key);
          result.completeError(error, stack);
        }
      },
      onError: (Object error, StackTrace stack) {
        if (identical(_entries[key], entry)) _remove(key);
        result.completeError(error, stack);
      },
    );
    return result.future;
  }

  void clear() {
    _entries.clear();
    _weight = 0;
  }

  void _remove(Object key) {
    final entry = _entries.remove(key);
    if (entry != null) _weight -= entry.weight;
  }

  void _trim() {
    while (_entries.length > maximumEntries || _weight > maximumWeight) {
      _remove(_entries.keys.first);
    }
  }
}

class _CacheEntry<T> {
  _CacheEntry(this.future);

  final Future<T> future;
  T? value;
  int weight = 0;
}
