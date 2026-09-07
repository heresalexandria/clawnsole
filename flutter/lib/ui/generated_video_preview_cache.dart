import 'dart:typed_data';

import 'package:flutter/widgets.dart';

import '../core/async_value_cache.dart';

class GeneratedVideoPreview {
  const GeneratedVideoPreview({required this.thumbnail, this.timeline});

  final Uint8List thumbnail;
  final Uint8List? timeline;
}

class GeneratedVideoPreviewJob {
  const GeneratedVideoPreviewJob({
    required this.future,
    required this.startedAt,
    required this.expectedDuration,
  });

  final Future<GeneratedVideoPreview?> future;
  final DateTime startedAt;
  final Duration expectedDuration;
}

/// Keeps shared progress metadata only while extraction is pending. Completed
/// Futures retain their encoded thumbnail/filmstrip bytes, so those belong in
/// the byte-budgeted cache instead of an unbounded job registry.
class GeneratedVideoPreviewCache with WidgetsBindingObserver {
  GeneratedVideoPreviewCache({int maximumBytes = 16 * 1024 * 1024})
    : _values = AsyncValueCache<GeneratedVideoPreview?>(
        maximumWeight: maximumBytes,
        weightOf: (preview) => preview == null
            ? 0
            : preview.thumbnail.buffer.lengthInBytes +
                  (preview.timeline?.buffer.lengthInBytes ?? 0),
      );

  final AsyncValueCache<GeneratedVideoPreview?> _values;
  final Map<Object, GeneratedVideoPreviewJob> _pending = {};
  WidgetsBinding? _binding;

  int get retainedBytes => _values.retainedWeight;
  int get pendingCount => _pending.length;

  Future<GeneratedVideoPreview?>? lookup(Object key) =>
      _pending[key]?.future ?? _values.lookupFuture(key);

  GeneratedVideoPreviewJob load(
    Object key, {
    required Duration expectedDuration,
    required Future<GeneratedVideoPreview?> Function() loader,
  }) {
    if (!identical(_binding, WidgetsBinding.instance)) {
      _binding?.removeObserver(this);
      _binding = WidgetsBinding.instance..addObserver(this);
    }
    final existing = _pending[key];
    if (existing != null) return existing;
    late final GeneratedVideoPreviewJob job;
    final future = _values.load(key, loader).whenComplete(() {
      if (identical(_pending[key], job)) _pending.remove(key);
    });
    job = GeneratedVideoPreviewJob(
      future: future,
      startedAt: DateTime.now(),
      expectedDuration: expectedDuration,
    );
    _pending[key] = job;
    return job;
  }

  @override
  void didHaveMemoryPressure() => _values.clear();

  void dispose() {
    _binding?.removeObserver(this);
    _binding = null;
    _values.clear();
    _pending.clear();
  }
}
