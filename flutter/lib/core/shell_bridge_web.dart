import 'dart:async';
import 'dart:js_interop';

import 'shell_bridge.dart';

/// The API the Electron preload script exposes as `window.clawnsole`.
@JS('clawnsole')
external _ClawnsoleShellJS? get _shellJS;

extension type _ClawnsoleShellJS._(JSObject _) implements JSObject {
  external JSPromise<JSAny?> checkForUpdate(bool force);
  external JSPromise<JSAny?> startUpdate();
  external void onUpdateEvent(JSFunction callback);
  external JSPromise<JSBoolean> openExternalUrl(JSString url, JSString purpose);
}

Future<bool?> openShellExternalUrl(Uri url, ExternalUrlPurpose purpose) async {
  final shell = _shellJS;
  if (shell == null) return null;
  return (await shell
          .openExternalUrl(url.toString().toJS, purpose.name.toJS)
          .toDart)
      .toDart;
}

Map<String, Object?> _toMap(JSAny? value) {
  final dart = value.dartify();
  if (dart is Map) {
    return dart.map((key, item) => MapEntry(key.toString(), item as Object?));
  }
  return const <String, Object?>{};
}

class _WebShellUpdater implements ShellUpdater {
  _WebShellUpdater(this._shell) {
    _shell.onUpdateEvent(
      ((JSAny? payload) {
        final map = _toMap(payload);
        if (map.isNotEmpty) _events.add(ShellUpdateEvent.fromMap(map));
      }).toJS,
    );
  }

  final _ClawnsoleShellJS _shell;
  final StreamController<ShellUpdateEvent> _events =
      StreamController<ShellUpdateEvent>.broadcast();

  @override
  Stream<ShellUpdateEvent> get events => _events.stream;

  @override
  Future<Map<String, Object?>> check({bool force = false}) async =>
      _toMap(await _shell.checkForUpdate(force).toDart);

  @override
  Future<Map<String, Object?>> start() async =>
      _toMap(await _shell.startUpdate().toDart);
}

/// Records that the renderer found and bound the shell bridge. The desktop
/// smoke test reads this to prove the in-app update path is wired end to end,
/// rather than only that the preload published its API.
@JS('clawnsoleShellReady')
external set _shellReady(bool value);

ShellUpdater? createShellUpdater() {
  final shell = _shellJS;
  if (shell == null) return null;
  _shellReady = true;
  return _WebShellUpdater(shell);
}
