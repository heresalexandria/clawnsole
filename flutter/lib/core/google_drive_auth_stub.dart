import 'google_drive_auth_base.dart';

GoogleDriveAuthorizer createPlatformGoogleDriveAuthorizer() =>
    const _UnavailableGoogleDriveAuthorizer();

class _UnavailableGoogleDriveAuthorizer implements GoogleDriveAuthorizer {
  const _UnavailableGoogleDriveAuthorizer();

  @override
  bool get isAvailable => false;

  @override
  String get unavailableMessage =>
      'Google Drive authorization is unavailable on this platform.';

  @override
  Future<String> authorize() => throw UnsupportedError(unavailableMessage);

  @override
  Future<String?> authorizeSilently() async => null;

  @override
  Future<void> disconnect() async {}
}
