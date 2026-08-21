import 'dart:js_interop';
import 'dart:js_interop_unsafe';

import 'google_drive_auth_base.dart';

@JS('clawnsole')
external _ClawnsoleShellJS? get _shell;

extension type _ClawnsoleShellJS._(JSObject _) implements JSObject {
  external JSPromise<JSString> authorizeGoogleDrive();
  external JSPromise<JSString> authorizeGoogleDriveSilently();
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
  Future<String?> authorizeSilently() async {
    // Older desktop shells predate the silent bridge; the session simply
    // stays disconnected until the user reconnects from Settings.
    if (!isAvailable ||
        !_shell!.hasProperty('authorizeGoogleDriveSilently'.toJS).toDart) {
      return null;
    }
    try {
      final token = (await _shell!.authorizeGoogleDriveSilently().toDart).toDart
          .trim();
      return token.isEmpty ? null : token;
    } on Object {
      return null;
    }
  }

  @override
  Future<void> disconnect() async {
    if (_usesShell) await _shell!.disconnectGoogleDrive().toDart;
  }
}
