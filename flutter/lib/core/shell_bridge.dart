import 'shell_bridge_stub.dart'
    if (dart.library.js_interop) 'shell_bridge_web.dart';

/// Progress reported by the desktop shell while it updates the app.
class ShellUpdateEvent {
  const ShellUpdateEvent({
    required this.phase,
    this.version,
    this.received,
    this.total,
    this.fraction,
    this.message,
  });

  /// One of `downloading`, `installing`, or `error`.
  final String phase;
  final String? version;
  final int? received;
  final int? total;
  final double? fraction;
  final String? message;

  factory ShellUpdateEvent.fromMap(Map<String, Object?> map) =>
      ShellUpdateEvent(
        phase: map['phase']?.toString() ?? 'unknown',
        version: map['version']?.toString(),
        received: (map['received'] as num?)?.toInt(),
        total: (map['total'] as num?)?.toInt(),
        fraction: (map['fraction'] as num?)?.toDouble(),
        message: map['message']?.toString(),
      );
}

/// The desktop shell's self-update surface, reachable from the renderer.
///
/// Present only when the Flutter web build runs inside the Electron shell;
/// null on plain web, iOS, and Android.
abstract class ShellUpdater {
  /// Asks the shell for the latest-release summary.
  ///
  /// Background checks leave [force] false so the shell can honor its
  /// persisted 24-hour throttle. User-requested checks set it to true.
  Future<Map<String, Object?>> check({bool force = false});

  /// Starts the verified download-and-install flow. Progress arrives on
  /// [events]; on success the shell quits and reopens the app itself.
  Future<Map<String, Object?>> start();

  Stream<ShellUpdateEvent> get events;
}

ShellUpdater? _cached;
bool _resolved = false;

ShellUpdater? get shellUpdater {
  if (!_resolved) {
    _cached = createShellUpdater();
    _resolved = true;
  }
  return _cached;
}
