/// Schedules silent session renewal independently of library reads. Drive
/// access tokens are short-lived; an open studio must renew them even when
/// the user never leaves the foreground or opens Settings.
class GoogleDriveSessionSchedule {
  GoogleDriveSessionSchedule({DateTime Function()? clock})
    : _clock = clock ?? DateTime.now;

  final DateTime Function() _clock;
  DateTime? _nextAttempt;
  bool _wasConnected = false;
  bool _suspended = false;
  int _failures = 0;

  bool get isSuspended => _suspended;

  bool isDue({required bool connected, required bool configured}) {
    if (_suspended || !configured) return false;
    // A rejected session should recover on the next maintenance pass, even
    // if its scheduled renewal was still some time away.
    if (_wasConnected && !connected) _nextAttempt = null;
    _wasConnected = connected;
    return _nextAttempt == null || !_clock().isBefore(_nextAttempt!);
  }

  void renewed() {
    _suspended = false;
    _wasConnected = true;
    _failures = 0;
    _nextAttempt = _clock().add(const Duration(minutes: 45));
  }

  void failed({required bool connected}) {
    _wasConnected = connected;
    // Offline/revoked grants must not turn the four-second polling loop into
    // an OAuth request storm. Retry after 30, 60, 120, 240, then 300 seconds.
    final seconds = (30 * (1 << _failures.clamp(0, 4))).clamp(30, 300);
    _failures = (_failures + 1).clamp(0, 4);
    _nextAttempt = _clock().add(Duration(seconds: seconds));
  }

  /// Explicit sign-out wins over background maintenance, including a grant
  /// that the platform temporarily continues to return after revocation.
  void suspend() => _suspended = true;
}
