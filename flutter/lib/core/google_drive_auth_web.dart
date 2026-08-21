import 'dart:js_interop';

import 'google_drive_auth_base.dart';

@JS('clawnsole')
external _ClawnsoleShellJS? get _shell;

extension type _ClawnsoleShellJS._(JSObject _) implements JSObject {
  external JSPromise<JSString> authorizeGoogleDrive();
  external JSPromise<JSString?> restoreGoogleDrive();
  external JSPromise<JSAny?> disconnectGoogleDrive();
}

GoogleDriveAuthorizer createPlatformGoogleDriveAuthorizer() =>
    _WebGoogleDriveAuthorizer();

class _WebGoogleDriveAuthorizer implements GoogleDriveAuthorizer {
  bool get _usesShell => _shell != null;

  @override
  bool get isAvailable => _usesShell;

  @override
  String get unavailableMessage =>
      'Google Drive is available in the packaged Clawnsole desktop app.';

  @override
  Future<String> authorize() async {
    if (!isAvailable) throw StateError(unavailableMessage);
    final token = (await _shell!.authorizeGoogleDrive().toDart).toDart;
    final clean = token.trim();
    if (clean.isEmpty) throw StateError('Google Drive authorization failed.');
    return clean;
  }

  @override
  Future<String?> restore() async {
    if (!isAvailable) return null;
    final value = await _shell!.restoreGoogleDrive().toDart;
    final token = value?.toDart.trim() ?? '';
    return token.isEmpty ? null : token;
  }

  @override
  Future<void> disconnect() async {
    if (_usesShell) await _shell!.disconnectGoogleDrive().toDart;
  }
}
