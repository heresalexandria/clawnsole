import 'dart:async';

import 'hybrid_data_store.dart';
import 'models.dart';

/// Runs one background Drive upload pass: publishes staged media, then swaps
/// the records over through the owner's canonical read/write path (the vault
/// facade on native builds, the serialized companion store on desktop web).
///
/// Returns true when nothing this device can publish remains pending.
Future<bool> runDriveUploadPass({
  required HybridDataStore hybrid,
  required Future<StoredData> Function() read,
  required Future<void> Function(StoredData data) write,
}) async {
  if (!hybrid.isDriveConnected) return true;
  final result = await hybrid.uploadQueuedDriveAssets(await read());
  if (result.replacements.isNotEmpty) {
    // Swap on a fresh read so records written while the uploads ran are kept.
    await write(
      HybridDataStore.applyDriveAssetReplacements(
        await read(),
        result.replacements,
      ),
    );
  }
  return result.failures == 0;
}

/// Schedules background Drive upload passes with single-flight execution and
/// exponential retry backoff. Owners call [schedule] whenever staged media
/// may be waiting: after a deferred write, a Drive connect, or a refresh.
class DriveUploadPump {
  DriveUploadPump({
    required Future<bool> Function() flush,
    this.initialRetryDelay = const Duration(seconds: 5),
    this.maximumRetryDelay = const Duration(minutes: 5),
  }) : _flush = flush;

  final Future<bool> Function() _flush;
  final Duration initialRetryDelay;
  final Duration maximumRetryDelay;

  Timer? _timer;
  bool _running = false;
  bool _rerunRequested = false;
  bool _disposed = false;
  Duration? _retryDelay;

  void schedule([Duration delay = Duration.zero]) {
    if (_disposed) return;
    if (_running) {
      _rerunRequested = true;
      return;
    }
    _timer?.cancel();
    _timer = Timer(delay, () {
      _timer = null;
      unawaited(_run());
    });
  }

  Future<void> _run() async {
    if (_disposed || _running) return;
    _running = true;
    var done = false;
    try {
      done = await _flush();
    } on Object {
      // A failed pass retries below; the staged bytes stay pending in the
      // records themselves, so nothing is lost by backing off.
      done = false;
    } finally {
      _running = false;
    }
    if (_disposed) return;
    if (done) {
      _retryDelay = null;
      if (_rerunRequested) {
        _rerunRequested = false;
        schedule();
      }
      return;
    }
    _rerunRequested = false;
    final delay = _retryDelay ?? initialRetryDelay;
    final doubled = delay * 2;
    _retryDelay = doubled > maximumRetryDelay ? maximumRetryDelay : doubled;
    schedule(delay);
  }

  void dispose() {
    _disposed = true;
    _timer?.cancel();
    _timer = null;
  }
}
