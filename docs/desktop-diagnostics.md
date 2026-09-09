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
- `renderer-process-metrics` also carries `framesPerMinute` and `heapBytes`
  (the CanvasKit wasm heap) once two health records have been seen, and an
  `engineCounters` object when the renderer was built with engine
  instrumentation (below).

### Derived records

The shell compares each `flutter-health` record with the previous one from the
same Flutter instance (a frame count that goes backwards means a new instance
and resets every derived value) and counts errors per minute across
`flutter-error`, `web-error`, `web-unhandled-rejection` and
`renderer-console-error`, including the preload's suppressed-count summaries.
All derived records are numeric only:

- `renderer-error-storm` `{sourceEvent, perMinute}` is written once per minute
  per source when that source alone reaches 1,000 errors in the minute.
- `renderer-engine-stalled` `{framesDelta, intervalMs, lastFrameAgeMs,
  appActive, flutterErrorsDelta, errorsPerMinute, consecutiveMinutes}` is
  written when the frame count has not moved for at least two consecutive
  health records while the app is active **and** errors are still arriving
  (`flutterErrorsDelta > 0` or `errorsPerMinute >= 1000`). A static idle
  screen produces no frames and no errors and never writes this record.
- `renderer-heap-growth` `{heapBytes, heapDeltaBytes, framesDelta, intervalMs,
  framesPerMinute, critical}` is written when the wasm heap grew by 64 MiB in
  one interval, by 256 MiB over the last five intervals, or when it is at or
  above 1.5 GiB (`critical: 1`). The heap cannot grow past 2 GiB; the field
  incident reached it at roughly 96 MiB per minute before the engine aborted.
- `renderer-console-error` with `category: "engine-abort"` marks an Emscripten
  abort (`Aborted(...)`, `Cannot enlarge memory`, `RuntimeError: Aborted`).
  The message text is never logged, only the category.

### Flutter self-reports

`flutter-health` additionally records `lifecycleState` (0 detached, 1 resumed,
2 inactive, 3 hidden, 4 paused), `documentHidden` (1 when the browser document
is hidden, 0 when visible; absent on native targets), `framesSinceLastHealth`
(frames completed since the previous health record, so a frozen engine shows 0
while `frameCount` stays flat), `motionConstrained` (0/1), and `heapPressure`
(0 none, 1 growing, 2 critical). The Flutter app keeps the current
`canvasKitHeapBytes` sample plus the ten before it: pressure is `growing` when
the heap grew by 64 MiB or more within one interval or by 256 MiB or more over
those ten intervals (ten minutes at the default cadence), and `critical` once the allocated heap reaches 1 GiB, half of the
2 GiB WebAssembly cap. The first critical reading emits
`flutter-motion-constrained` (with `heapBytes`) once and latches the in-app
motion brake for the rest of that Flutter instance: continuous animations stop
so the heap, which never shrinks, is not driven to the abort that leaves the
window blank. The brake never releases without a renderer reload.

`flutter-engine-stalled` (with `lastFrameAgeMs` and `errorsInWindow`) is the
app's own verdict that a foreground window completed no frame for two
consecutive health intervals while errors kept arriving in each of them — the
same gate as the shell's rule: its suppressed-error counter moved (more than
the ten reports a minute it forwards) or a thousand or more errors landed in
the interval; it re-arms after the next completed frame. The shell records it
as corroboration; only the shell's own `renderer-engine-stalled` rule,
computed from the health records it received, decides on a reload. A static
foreground screen with no errors, or with a few isolated ones, is not a stall,
and hidden or paused windows never report one. `flutter-lifecycle` (with
`lifecycleState`) marks each lifecycle transition, limited to twenty per
minute, so the log shows when the window went inactive or hidden relative to
memory growth. All of these records remain numeric codes and byte counts;
Flutter never reloads itself, the desktop shell decides on recovery.

### Automatic engine recovery

A renderer whose process is alive but whose engine no longer draws is treated
exactly like a crashed process. The shell reloads the window when either:

- a console message is classified `engine-abort`, or
- `renderer-engine-stalled` fires (two consecutive frozen health records, app
  active, errors still arriving), or
- the wasm heap reaches 1.5 GiB (`heap-critical`).

The reload shares the crash budget: one silent reload, then the "Clawnsole
Stopped Drawing" dialog offering **Reload** or **Quit**; five minutes of
stability restores the silent reload. The lifecycle line is
`renderer-engine-dead {"reason": "engine-abort" | "frames-frozen" |
"heap-critical", "type": "Renderer"}`. Each condition raises one trigger per
document: repeated triggers while a reload or dialog is pending are ignored,
and a new document or a positive frame delta re-arms them. Memory growth
alone (`heap-growth`), an isolated error, or a frozen frame count without
errors never reloads anything; use the native Reload Studio action for those.

### Graphics context loss

The preload's `webglcontextlost` listener on `window` cannot observe the
CanvasKit context: Flutter renders into an OffscreenCanvas, or a canvas inside
the `flt-glass-pane` shadow root, and the event does not bubble to the window.
Treat the `graphics-context-lost` console category and an
`electron-child-gone` record for the `GPU` process as the real signals; the
`webgl-context-lost` event only fires for the synthetic smoke fixture.

## Engine object counters

The renderer is built with `--dart-define=FLUTTER_WEB_ENABLE_INSTRUMENTATION=true`
(`flutter/scripts/build_web`, `electron/scripts/start_macos` and the pull
request workflow), so the engine prints `Engine counters:` followed by
`<Label> Created/Deleted/Leaked: N` lines to the console at most every two
seconds. The shell parses only that message shape, keeps the latest values for
at most 64 labels, and writes them into `renderer-process-metrics` as
`engineCounters: {label: {created, deleted, leaked, live, createdDelta,
deletedDelta, leakedDelta, liveDelta}}`, where `live = created - deleted -
leaked` and the deltas are per minute-sample. `live` that climbs every minute
under a steady workload identifies the native object type that is leaking. No
other console text is retained.

## Save Diagnostics Report

**Help → Save Diagnostics Report…** writes one plain-text bundle named
`Clawnsole-Diagnostics-<UTC stamp>.txt` (default location: Downloads) and
reveals it in Finder. It contains, under section headers: the runtime
versions (Electron, Chrome, Node, V8), platform, architecture and macOS
version; the renderer `version.json`; the same process metrics the minute
sample records; `companion.log` and `companion.log.1`; and the newest twelve
regular files named `Clawnsole…` from `~/Library/Logs/DiagnosticReports` and
`/Library/Logs/DiagnosticReports`, each capped at 5 MiB with a 40 MiB total.
Log lines are sanitized, but macOS crash reports and the file listing are
copied as-is, so **the bundle may contain your computer's name and file
paths**; the save dialog says so. Review it before sharing.

## Stable companion origin

The packaged companion listens on the port it bound last time
(`companion-port.json` under Application Support, a single validated integer),
falling back to a random port when that one is taken. Chromium keys its HTTP
cache and every kind of origin storage by origin, so a fixed loopback port
keeps the cached thumbnails and films (`/assets` responses are cacheable for a
day) valid across launches instead of writing a fresh copy under a new origin
every start; the field profile had accumulated 74 origins and a 900 MB cache.
The shell also pins the disk cache budget to 512 MiB. The renderer bundle
itself is served `no-store` and gains nothing from the cache.

A stable origin would also let a Flutter service worker outlive an update and
keep serving the previous bundle, so the desktop renderer is built with
`--pwa-strategy=none` and the shell clears any service worker and CacheStorage
left on the renderer origin before every load.

## Reproducing and symbolication

`flutter/tool/renderer_soak.dart` renders synthetic pending-generation placeholders
without an application controller, credentials, provider requests, or user data.
Build it into a separate output directory and exercise it in an isolated browser
profile when investigating animation resource lifetimes. Keep the placeholder
style, card count, viewport, engine build, and runtime the same for comparisons.

### Renderer soak tool

`electron/scripts/soak-renderer.cjs` loads one URL in a hidden, unthrottled
window inside a throwaway profile and prints one JSON line per sample with the
CanvasKit wasm heap size (`flutterCanvasKit.HEAPU8.byteLength`), the
`requestAnimationFrame` rate, Tab/GPU working sets and the latest engine
counters. It never opens the installed app's profile.

To soak the synthetic placeholder page, build it with instrumentation and
serve the output directory with any static server:

```sh
cd flutter
flutter build web --release --target tool/renderer_soak.dart \
  --dart-define=FLUTTER_WEB_ENABLE_INSTRUMENTATION=true -o build/soak
python3 -m http.server 7399 --bind 127.0.0.1 --directory build/soak &
cd ../electron
./node_modules/.bin/electron scripts/soak-renderer.cjs \
  --url='http://127.0.0.1:7399/?style=cyclone&cards=12' --seconds=600 --interval=10
```

To soak the full app, start the development companion with
`./flutter/scripts/start_macos`, close the Electron window it opens, and run
the tool against the companion's origin with the session token that
`electron/scripts/start.mjs` generated. The tool reads the token from the
`CLAWNSOLE_COMPANION_TOKEN` environment variable (or from the first line of
standard input) and adds it as the `X-Clawnsole-Session` header for that
origin only. It refuses a token on the command line: argv is visible to every
local process and is kept in shell history, and this token unlocks the whole
companion.

```sh
CLAWNSOLE_COMPANION_TOKEN=<session token> ./node_modules/.bin/electron \
  scripts/soak-renderer.cjs --url=http://127.0.0.1:<port>/ --seconds=1800 --offscreen
```

`--offscreen` renders without a compositor surface at 120 frames per second,
which reproduces a per-frame leak faster. Compare `heapBytes` and each
counter's `live` value between the first and last lines: a heap that climbs
while `fps` stays flat and a `live` count that never plateaus is a leak.

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
installed application's library or issue paid generation requests. The
recovery smoke also drives one dead-engine reload through `recoverFrom`, and
the diagnostics smoke replays an instrumented engine's counter message and an
Emscripten abort line to verify the parser and the `engine-dead` alert.
