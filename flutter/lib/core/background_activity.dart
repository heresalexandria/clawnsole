import 'package:flutter/services.dart';

/// Tells the platform shell whether provider work (submissions, status polls,
/// or result downloads) is still pending, so the shell can keep the process
/// executing briefly after the app leaves the foreground.
///
/// iOS suspends an app almost immediately after it is backgrounded, which
/// freezes the poll timer and kills in-flight provider requests. The iOS shell
/// answers this signal with a finite `beginBackgroundTask` window (~30
/// seconds) so near-complete work can land before suspension. Platforms whose
/// shells never suspend the process (desktop, Android short-term background)
/// simply have no handler registered and the signal is a no-op.
abstract class BackgroundActivityCoordinator {
  Future<void> setPendingWork(bool pending);
}

class MethodChannelBackgroundActivity implements BackgroundActivityCoordinator {
  MethodChannelBackgroundActivity();

  static const MethodChannel _channel = MethodChannel(
    'ai.clawnsole/background_activity',
  );

  bool? _lastReported;
  bool _unsupported = false;

  @override
  Future<void> setPendingWork(bool pending) async {
    if (_unsupported || _lastReported == pending) return;
    _lastReported = pending;
    try {
      await _channel.invokeMethod<void>('setPendingWork', <String, Object?>{
        'pending': pending,
      });
    } on MissingPluginException {
      _unsupported = true;
    } on Object {
      // The signal is a best-effort lifecycle hint. Losing one update must
      // never surface as a product failure; the next state change retries.
      _lastReported = null;
    }
  }
}
