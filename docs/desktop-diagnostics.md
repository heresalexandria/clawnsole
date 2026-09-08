# Desktop rendering diagnostics

If the macOS studio freezes or becomes blank, preserve `companion.log` and
`companion.log.1` using **Help → Show Logs** before using **View → Reload Studio**.
The reload replaces the Flutter renderer while leaving the companion running;
saved drafts and generation records are restored by the ordinary startup path.
Unsaved renderer-only edits cannot survive a reload. Do not delete the library
or disconnect Drive as a rendering recovery step.

The log is bounded to two 5 MB files. Renderer reports contain fixed event names,
error types, sanitized executable locations, and numeric measurements. Raw error
messages, prompts, media contents, credentials, and full source URLs are omitted.
Repeated errors are rate limited and counted rather than written once per frame.
The diagnostic bridge accepts only the current app's main frame.

## Reading the evidence

- `renderer-gone` and `renderer-unresponsive` identify Chromium process failures.
  Companion `/health` success alone does not establish that Flutter is drawing.
- `flutter-error`, `flutter-platform-error`, `web-error`, and
  `web-unhandled-rejection` identify framework or runtime failures. Stack entries
  retain Dart/JavaScript line positions and WebAssembly function indexes/offsets.
- Graphics context events distinguish a lost WebGL context from a normal load.
- `flutter-health` records completed frame count and last-frame age, image cache
  sizes, and optional CanvasKit memory values without forcing additional frames.
  `appActive` distinguishes foreground from background observations. A static
  screen legitimately produces no new frames; frame age is not itself a hang.
- `renderer-process-metrics` records CPU percentage and working-set sizes in KiB.
  Flutter/CanvasKit memory measurements are in bytes. CanvasKit heap size is
  allocated capacity, not live-object size, and need not shrink after cleanup.
  Compare growth over repeated equivalent workloads and capture errors nearby.
- Diagnostic suppression counts distinguish a repeated failure storm from a
  single exception while keeping logging work bounded.
  `flutterErrorsSuppressed` is cumulative for the current Flutter instance.
  Optional native counters stop being queried after a failure until the engine
  changes; scalar heap readings continue without entering native code.

The app does not automatically reload a live renderer based on a memory threshold
or an isolated error. Use the native Reload Studio action when needed.

## Reproducing and symbolication

`flutter/tool/renderer_soak.dart` renders synthetic pending-generation placeholders
without an application controller, credentials, provider requests, or user data.
Build it into a separate output directory and exercise it in an isolated browser
profile when investigating animation resource lifetimes. Keep the placeholder
style, card count, viewport, engine build, and runtime the same for comparisons.

Canonical `flutter/scripts/build_web` builds include `main.dart.js.map`. Preserve
the map and renderer version from the affected package; rebuilding with another
Flutter SDK does not produce matching source locations. WebAssembly frames also
need symbols from the exact CanvasKit engine build. Generated bundles, source
maps, captured logs, and private diagnostic screenshots must not be committed.

For shell integration tests, run from `electron/`:

```sh
npm test
./node_modules/.bin/electron scripts/smoke-recovery.cjs
./node_modules/.bin/electron scripts/smoke-diagnostics.cjs
```

Both smoke scripts use isolated synthetic profiles. They must never open the
installed application's library or issue paid generation requests.
