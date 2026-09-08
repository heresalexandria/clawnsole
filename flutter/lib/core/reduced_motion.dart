/// The platform's "reduce motion" preference, observed live.
///
/// Flutter web never sets `MediaQuery.disableAnimations` from the operating
/// system, so the desktop renderer reads the CSS media feature
/// `prefers-reduced-motion` itself and follows it as it changes. Installed
/// native targets hand that preference to Flutter through the accessibility
/// features, so they use the stub, which never reports it on.
library;

export 'reduced_motion_stub.dart'
    if (dart.library.js_interop) 'reduced_motion_web.dart';
