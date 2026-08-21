import 'dart:js_interop';

@JS('clawnsole')
external _ClawnsoleShellJS? get _shell;

extension type _ClawnsoleShellJS._(JSObject _) implements JSObject {
  external JSPromise<JSAny?> settingsVault(JSString action, JSString value);
}

Future<Map<String, Object?>> invokePlatformSettingsVault(
  String action,
  String value,
) async {
  final shell = _shell;
  if (shell == null) {
    throw StateError(
      'Encrypted settings sync is available in the packaged Clawnsole desktop app.',
    );
  }
  final result = (await shell.settingsVault(action.toJS, value.toJS).toDart)
      .dartify();
  if (result is! Map) {
    throw StateError('The desktop shell returned an invalid vault response.');
  }
  return result.map((key, item) => MapEntry(key.toString(), item as Object?));
}
