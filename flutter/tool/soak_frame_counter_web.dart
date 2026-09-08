import 'dart:js_interop';

@JS('__soakFrames')
external set _soakFrames(JSNumber value);

/// Publishes the number of Flutter frames completed as `window.__soakFrames`,
/// so the Electron soak runner can read the renderer's real frame rate rather
/// than the browser's requestAnimationFrame cadence.
void publishSoakFrameCount(int frames) {
  _soakFrames = frames.toJS;
}
