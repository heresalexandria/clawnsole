import 'dart:async';
import 'dart:js_interop';
import 'dart:js_interop_unsafe';

import 'shell_bridge.dart';

/// The API the Electron preload script exposes as `window.clawnsole`.
@JS('clawnsole')
external _ClawnsoleShellJS? get _shellJS;

extension type _ClawnsoleShellJS._(JSObject _) implements JSObject {
  external JSPromise<JSAny?> checkForUpdate(bool force);
  external JSPromise<JSAny?> startUpdate();
  external void onUpdateEvent(JSFunction callback);
  external JSPromise<JSBoolean> openExternalUrl(JSString url, JSString purpose);
  external void onNavigate(JSFunction callback);
  external JSPromise<JSAny?> notify(JSAny options);
}

/// Older preloads predate a member; probing keeps the renderer compatible
/// with a shell that has not been updated yet.
bool _shellHas(_ClawnsoleShellJS shell, String member) => shell.has(member);

Stream<String> createShellNavigationStream() {
  final shell = _shellJS;
  if (shell == null || !_shellHas(shell, 'onNavigate')) {
    return const Stream<String>.empty();
  }
  final controller = StreamController<String>.broadcast();
  shell.onNavigate(
    ((JSAny? payload) {
      final section = _toMap(payload)['section']?.toString();
      if (section != null && section.isNotEmpty) controller.add(section);
    }).toJS,
  );
  return controller.stream;
}

Future<bool> shellNotify(String title, String body) async {
  final shell = _shellJS;
  if (shell == null || !_shellHas(shell, 'notify')) return false;
  final result = await shell
      .notify(<String, String>{'title': title, 'body': body}.jsify()!)
      .toDart;
  return result.dartify() == true;
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
