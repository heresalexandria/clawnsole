import 'dart:js_interop';
import 'dart:js_interop_unsafe';

@JS('clawnsole')
external JSObject? get _shell;

/// True only when the Electron preload published the data-folder methods;
/// plain-browser sessions keep the controls hidden.
bool get shellManagesDataLocation {
  final shell = _shell;
  return shell != null &&
      shell.has('revealDataFolder') &&
      shell.has('chooseDataDirectory');
}

Future<Map<String, Object?>> _invoke(String method) async {
  final shell = _shell;
  if (shell == null || !shell.has(method)) {
    throw StateError(
      'The data folder is managed by the packaged Clawnsole desktop app.',
    );
  }
  final result = (await shell.callMethod<JSPromise<JSAny?>>(method.toJS).toDart)
      .dartify();
  if (result is! Map) {
    throw StateError(
      'The desktop shell returned an invalid data-folder response.',
    );
  }
  return result.map((key, item) => MapEntry(key.toString(), item as Object?));
}

Future<Map<String, Object?>> revealShellDataFolder() =>
    _invoke('revealDataFolder');

Future<Map<String, Object?>> chooseShellDataDirectory() =>
    _invoke('chooseDataDirectory');
