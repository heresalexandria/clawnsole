import 'dart:js_interop';

import 'google_drive_auth_base.dart';

const _googleClientId = String.fromEnvironment('CLAWNSOLE_GOOGLE_CLIENT_ID');

@JS('clawnsoleGoogleDrive.authorize')
external JSPromise<JSString> _authorizeGoogleDrive(JSString clientId);

@JS('clawnsoleGoogleDrive.disconnect')
external void _disconnectGoogleDrive();

@JS('clawnsole')
external _ClawnsoleShellJS? get _shell;

extension type _ClawnsoleShellJS._(JSObject _) implements JSObject {
  external JSPromise<JSString> authorizeGoogleDrive();
  external JSPromise<JSAny?> disconnectGoogleDrive();
}

GoogleDriveAuthorizer createPlatformGoogleDriveAuthorizer() =>
    _WebGoogleDriveAuthorizer();

class _WebGoogleDriveAuthorizer implements GoogleDriveAuthorizer {
  bool get _usesShell => _shell != null;

  @override
  bool get isAvailable => _usesShell || _googleClientId.isNotEmpty;

  @override
  String get unavailableMessage =>
      'Build this target with CLAWNSOLE_GOOGLE_CLIENT_ID to enable Drive.';

  @override
  Future<String> authorize() async {
    if (!isAvailable) throw StateError(unavailableMessage);
    final token = _usesShell
        ? (await _shell!.authorizeGoogleDrive().toDart).toDart
        : (await _authorizeGoogleDrive(_googleClientId.toJS).toDart).toDart;
    final clean = token.trim();
    if (clean.isEmpty) throw StateError('Google Drive authorization failed.');
    return clean;
  }

  @override
  Future<void> disconnect() async {
    if (_usesShell) {
      await _shell!.disconnectGoogleDrive().toDart;
    } else {
      _disconnectGoogleDrive();
    }
  }
}
