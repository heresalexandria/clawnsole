import 'google_drive_auth_base.dart';
import 'google_drive_auth_stub.dart'
    if (dart.library.io) 'google_drive_auth_io.dart'
    if (dart.library.js_interop) 'google_drive_auth_web.dart';

export 'google_drive_auth_base.dart';

GoogleDriveAuthorizer createGoogleDriveAuthorizer() =>
    createPlatformGoogleDriveAuthorizer();
