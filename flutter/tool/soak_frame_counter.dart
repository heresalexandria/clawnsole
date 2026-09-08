/// The soak harness's frame counter: `window.__soakFrames` on the web,
/// nothing elsewhere.
library;

export 'soak_frame_counter_stub.dart'
    if (dart.library.js_interop) 'soak_frame_counter_web.dart';
