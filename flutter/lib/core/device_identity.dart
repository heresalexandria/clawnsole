/// How a device names itself in the "drafts on other devices" list.
///
/// Native stores (the desktop companion, the iOS app) answer with the
/// machine's host name; a plain browser has nothing better than "Browser".
library;

export 'device_identity_stub.dart'
    if (dart.library.io) 'device_identity_io.dart';
