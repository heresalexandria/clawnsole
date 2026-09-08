# Desktop resilience and recovery

This change hardens concrete failure paths found while investigating intermittent
macOS failures. It preserves the canonical Flutter product on iOS, Android,
Windows and the Electron macOS renderer. It does not identify a conclusive cause
for every historical incident or guarantee that native software can never crash.

## What the investigation established

The retained local diagnostics contained substantial companion disk writes and
repeated handled Drive authentication failures near one hour after startup.
Neither was a process-termination record. A generic Electron startup abort could
not be attributed to the installed Clawnsole application. Raw diagnostic reports,
credentials, prompts, media and library records are not included in this change.

Independent fault injection did establish defects in the previous code:

| Trigger | Previous behavior | Resulting behavior |
| --- | --- | --- |
| Companion executable missing or inaccessible | Unhandled child-process error could terminate Electron | Startup rejects safely, records a lifecycle event and explains the failed launch |
| Quit during port allocation/bootstrap/readiness | A late launch could create an orphan companion | Launch is cancelled; late work cannot publish a ready process |
| Rejected native recovery dialog | Unhandled promise rejection | Failure is contained and logged |
| Renderer dies or recovers while a dialog is pending | Synchronous native reload or stale dialog action | Deferred reload; closed/recovered windows invalidate pending actions |
| Foreground session reaches token expiry | Library reads fail; no periodic silent renewal | Renewal before expiry and bounded recovery retries; cached library remains readable |
| Old Drive response arrives after renewal/sign-out | Could overwrite or invalidate the newer session | Session revision guards prevent stale publication and disconnection |
| Browse many large images | 240 full encoded files could remain cached, regardless of byte size | Completed asset cache capped at 32 MiB, frame cache at 8 MiB |
| Recycle a tile while preview work is pending | Old result could be saved or displayed for its new source | Captured source identity and mounted/load-token checks reject stale completions |
| Cache receives truncated/stalled/oversize media | Incomplete publication or queued disk buffers | Verified staging with backpressure, limits, cancellation and atomic publication |
| Save identical library metadata repeatedly | Rewrites current file and replaces useful backup with the same revision | Disk-content comparison skips identical replacement and preserves prior different revision |
| Atomic rename fails | Delete-then-retry could remove the only primary copy | Failure preserves the primary; temporary files are cleaned when possible |

Node documents that an unhandled EventEmitter error can terminate its process.
Electron also documents renderer process-loss events and has fixed native
reentrancy problems with synchronous recovery navigation. Clawnsole now explicitly
defers its reload regardless of runtime version.
[Node error behavior](https://nodejs.org/api/errors.html),
[Electron process events](https://www.electronjs.org/docs/latest/api/web-contents),
[Electron recovery-navigation fix](https://releases.electronjs.org/pr/51917).

## Recovery contracts

The companion has one automatic restart during an unstable period, reset after
ten minutes of healthy operation. Health checks do not overlap for one child.
Failed startup, broken bootstrap pipes, early process exit and callback failure
have explicit owners. Stopping is terminal for that supervisor instance.

That budget only covers a companion that fails for its own reasons, so a stray
asynchronous error no longer ends the isolate: an abandoned download whose
client was closed, or any error delivered to a reader that has already given
up, is logged with its stack trace and costs its own request. Two such exits
inside the restart budget would otherwise reach the user as a companion that
"stopped and could not be restarted". A companion that cannot finish starting
still exits, because the shell can relaunch a failed launch but not a server
that is listening on nothing.

The renderer reloads once automatically, then asks on a repeated crash. Five
minutes between crashes restores its automatic budget. Successful document load
invalidates obsolete dialogs without resetting that budget. Saved drafts and
generation receipts are restored through existing persistence; unsaved transient
renderer state cannot survive a process crash. Recovery does not submit another
paid generation. Intentional repeated Generate activations with identical inputs
continue to create separate takes.

A live renderer process whose Flutter engine has stopped drawing shares that
budget. The September 2026 field log showed the CanvasKit wasm heap growing to
its 2 GiB cap, an Emscripten abort inside `SkPictureRecorder`, and then a
blank window for three and a half hours with the frame count frozen and about
7,000 errors per minute, while Electron never received `render-process-gone`
because the process was still alive. The shell now treats three signals as an
engine death and reloads the window through the same one-silent-reload-then-
dialog budget, recording `renderer-engine-dead` with a fixed reason:

- `engine-abort`: a console message matching an Emscripten abort.
- `frames-frozen`: at least two consecutive `flutter-health` records with no
  new frames while the app is active and errors keep arriving (Flutter's own
  suppressed-error counter moved, or 1,000 or more errors in the minute).
  Flutter's matching in-app verdict, `flutter-engine-stalled`, is recorded as
  corroboration and never reloads by itself.
- `heap-critical`: the wasm heap at or above 1.5 GiB.

Nothing else reloads a live renderer: heap growth alone is only recorded, an
isolated error is only recorded, and a frozen frame count with no errors is an
idle screen. Repeated triggers are ignored while a reload or the "Clawnsole
Stopped Drawing" dialog is pending, and each trigger re-arms only for a new
document or once frames resume. The recovery smoke drives this path on a real
window alongside the six process crashes.

Unexpected shell exceptions are observed for diagnostics, without suppressing
Node's fatal behavior or continuing after unknown main-process corruption.
Known detached operations catch their own failures. A failed smoke launch exits
with status 1, rather than appearing successful to CI.

## Drive sessions

The shared controller attempts silent renewal every 45 minutes while active.
Transient or rejected renewals retry after 30, 60, 120, 240 and then 300 seconds.
Only one maintenance pass runs at a time, and explicit sign-out suspends automatic
reconnection. Native/desktop existing authorization contracts supply credentials;
maintenance never opens an interactive sign-in flow.

Authorization failures leave the persisted library mirror usable and connection
state disconnected. Mutations requiring Drive remain subject to the existing
connected-store checks. Renewed sessions reject stale in-flight errors and
metadata, including stale ETags. Schema decoding succeeds before a new validator
and its data are accepted together. A fake-clock eight-hour foreground test
exercises repeated expiry and renewal without real credentials or API calls.

## Resource and persistence bounds

Preview cache budgets count the full backing byte buffer, not just a view into
it. Oversized images still display for their active caller but are not memoized.
Memory pressure clears completed caches; pending or evicted jobs cannot refill
them after the clear. Gateway and loader identity prevent cross-source reuse
without retaining source videos through cache keys.

Shared disk caches use the verified stream writer already used by retained
originals: 2 GiB transfer ceiling, 30-second idle and eight-minute total deadline,
declared-length checks, private staging, and per-chunk disk backpressure. Failed
replacement leaves the old complete cached file usable. Unused duplicate streams
are cancelled, and optional progress listeners cannot break a download.

New staging directories hold advisory leases. Opportunistic cleanup can reclaim
owned leftovers older than 24 hours after a process crash, while preserving
active leases, fresh files, links and unexpected contents. Each root is swept
once per process with a bounded candidate/time budget. Filesystems without lock
support can still transfer media; their stages are marked ineligible for this
automatic cleanup. Normal success/failure cleanup remains in place everywhere.

Unchanged library writes compare actual on-disk contents so restores or external
edits remain visible. The no-op path still sanitizes existing recovery copies and
rejects unsupported schemas. Changed generation receipts are still persisted
immediately with atomic replacement and backup; there is no new debounce or
durability delay. This eliminates redundant writes, not all whole-library
serialization or legitimate media traffic.

### Library write volume

A rendering film changes the library on every status poll (every 4–8 s), so
each changed save is the desktop companion's steady-state disk cost. Before
this pass one save of a ~1.5 MB library wrote the file twice — the staged
temporary for the new revision and a second full copy for `.bak`, both
flushed — and read it about six times (the unchanged-save comparison, a
second read inside the backup preparation, and the recovery sweep re-reading
and re-decoding `.bak` on every call), about 3 MB dirtied per poll, ≈670 KB/s;
macOS attributed 2.1 GB of writes to the companion over seven hours.

Now one changed save writes the library once. The `.bak` is a hard link to the
previous inode (`link(2)`, `CreateHardLinkW` on NTFS; never `dart:io`'s
`Link`, which is a symlink and would follow the canonical name to the new
revision). The rename that follows only swaps the canonical *name* to the new
inode, so the canonical file exists at every instant and the old inode lives
on as `.bak` unchanged — a directory entry instead of 1.5 MB. Filesystems that
refuse links (FAT/exFAT, some shares) fall back to the copy. The previous
contents are read once and handed to the backup preparation; the legacy
credential/diagnostic scrub still writes a fresh `.bak` when it changes
anything. The recovery sweep still runs after every save, including the no-op
path, but a `.bak`/`.corrupt-*` copy it has already found clean is trusted by
size and modification stamp and is only stat-ed; a copy that changed on disk
is read and sanitized again. Per changed poll: ~1.5 MB written, ~1.5 MB read,
one JSON decode of the previous revision (shared by the schema check and the
scrub). Measured on a 1.4 MB library (30 changed saves, macOS APFS): 81.7 MiB
written before, 40.9 MiB after, and the per-save `.bak` re-read (1.4 MB every
save, changed or not) gone; 33 ms per changed save became 17 ms and a no-op
save 14 ms became 9 ms. Regression tests count whole-file writes, copies and
reads per save through `IOOverrides` (`atomic_file_test.dart`) and prove the
link shares the inode (`hard_link_test.dart`).

## Local diagnostics

The existing `companion.log` and one rotated predecessor retain shell version,
startup/readiness/quit, companion exit, renderer loss, GPU/utility loss,
unresponsive/responsive and recovery-failure events. New lifecycle fields are
allowlisted process reasons, numeric exit codes and runtime versions. They do
not include request bodies, prompts, media, URLs or exception payloads. Individual
lines and files are capped; unavailable disk or terminal output cannot throw
back through diagnostics. No diagnostic upload service is enabled.

On macOS, inspect `~/Library/Logs/Clawnsole/companion.log` and `.log.1` alongside
the corresponding macOS DiagnosticReports entry. Match timestamps, product
version and process identity before attributing a failure. An absent report is
not proof that no failure occurred; a disk-write report with no action taken is
not proof that the OS killed the application.

**Help → Save Diagnostics Report…** gathers both log files, the newest twelve
Clawnsole crash reports from the user and system DiagnosticReports folders,
runtime versions, the renderer version and current process metrics into one
text file (5 MiB per file, 40 MiB total). Crash reports and file paths are
copied verbatim, so the bundle may contain the computer's name and file paths;
the save dialog states this. It is written only where the user chooses and is
never uploaded.

The minute sample additionally records frames per minute, the wasm heap size,
and, because the renderer is built with `FLUTTER_WEB_ENABLE_INSTRUMENTATION`,
the engine's own object counters (created, deleted, leaked and live per label,
with per-minute deltas). Derived `renderer-engine-stalled`,
`renderer-heap-growth` and `renderer-error-storm` records name the condition
that was met with numbers only. The preload's window-level
`webglcontextlost` listener cannot see the CanvasKit context, which lives on
an OffscreenCanvas inside the `flt-glass-pane` shadow root; the
`graphics-context-lost` console category and a GPU `electron-child-gone`
record are the signals that matter. See
[desktop diagnostics](desktop-diagnostics.md) for the exact record shapes.

The packaged companion reuses its last port (`companion-port.json`) so the
renderer origin, and with it Chromium's per-origin HTTP cache, CacheStorage and
wasm code cache, survive between launches instead of being rewritten each time;
the field profile had accumulated 74 loopback origins and roughly 2 GB of cache
writes per day. The shell pins the disk cache to 512 MiB. A taken port still
falls back to a random one exactly as before.

## Verification and repeatable experiments

The regressions include real missing-executable/early-exit child processes,
dialog rejection, concurrent health checks, cancelled startup, stale recovery
actions, token expiry, delayed Drive responses, source recycling, memory pressure,
truncated media, stalled streams, unused response cancellation and failed rename.
The existing submission, sync, draft and playback suites remain part of CI.

macOS CI builds and smoke-tests the package, verifies a deliberately failed
startup returns failure, and runs `electron/scripts/smoke-recovery.cjs`. That
fixture creates its own sandboxed window/profile and deliberately crashes its
renderer six times, verifying the document after each automatic or dialog-based
reload. It never opens the user's studio library.

For a repeatable cache memory experiment, run from `flutter/`:

```sh
dart compile exe tool/cache_memory_benchmark.dart -o /tmp/clawnsole-cache-bench
/tmp/clawnsole-cache-bench 50
/tmp/clawnsole-cache-bench 250
```

Local macOS ARM64 AOT results with Dart 3.9.0, 64 KiB source chunks and 5 ms RSS
sampling:

| Fixture | Elapsed | Baseline RSS | Peak RSS | Increase |
| --- | ---: | ---: | ---: | ---: |
| 50 MiB | 501 ms | 14,254,080 B | 18,153,472 B | 3,899,392 B |
| 250 MiB | 2,500 ms | 14,254,080 B | 18,677,760 B | 4,423,680 B |

These measurements cover local disk caching in separate compiled processes.
They do not measure total Flutter/Electron memory, live provider/Drive transfers,
or real video decoding. The useful result is bounded buffering as media grows.

## Remaining verification limits

Physical-device GPU/codec failures, real multi-hour sleep/wake sessions, network
revocation with live accounts and OS termination during a paid request remain
integration scenarios beyond synthetic tests. The app retains the existing
uncertain-submission recovery contract; it cannot reconstruct an unreturned
provider receipt by safely repeating the charge.

The original cache experiment bounds completed memoized data, not every live
widget, pending image read or platform decoder. The follow-up below also bounds
preview extraction concurrency; running work holds its slot until it actually
finishes. Large byte-oriented reference imports, editing and export paths remain
separate from streamed result delivery and are not covered by this experiment.

## Long-session preview and playback bounds

A further resource audit found three caches outside the earlier memoization
budgets: controller-restored preview bytes, the controller's successful read
futures, and generated-film thumbnail/filmstrip jobs. The controller now keeps
at most 32 MiB of completed restored bytes and 8 MiB of generated reference
previews; shared generated-film previews have a 16 MiB budget. Each also has an
entry limit. Budgets count backing buffers, including byte-array views. Pending
consumers still receive their results, while cleared or evicted completions
cannot restore retained cache data. OS memory pressure clears these caches;
durable media, drafts, Drive sessions and upload queues remain intact. A local
to Drive publish transfers its cached preview to the published id without
counting the same buffer twice or downloading the thumbnail again.

Reference frame/metadata probes and generated-film filmstrips share two
concurrent extraction slots. A 20-video regression fixture completes all 40
frame/metadata probes with peak concurrency of two. Queued reference probes for
disposed or recycled cards skip extraction. Duration probes also avoid waiting
forever to dispose a native player whose creation failed. Source/controller
identity is captured before asynchronous work so recycling a card cannot write
one film's previews onto another.

Cold Drive seeks previously buffered the entire requested range, potentially
almost a whole film for `bytes=1-`, while also warming the disk cache. Turning
the disk cache off likewise buffered whole videos. Both paths now deliver
streams with response backpressure. Range-ignoring servers are skipped and
limited while streaming; legacy records without a size use temporary disk
staging for exact suffix ranges. Regression fixtures announce a 1 GiB body and
verify playback starts after the first 64 KiB, without a buffered asset read.
Abandoning playback cancels upstream even when media validation is awaiting a
stalled next chunk. Normal cache warming and replay remain available.

Draft edits arriving during a slow Drive publish now obey the existing
20-second automatic publication interval, avoiding continuous back-to-back
writes. Local saves remain immediate, explicit flushes publish the latest
revision, and a pending revision is sent automatically after the interval even
without another edit. Reconnect recovery, conditional metadata reads and the
normal cross-device reconciliation schedule are preserved.

These are bounds on disposable caches and concurrent preview work, not a cap
on total process memory. Mounted gallery cards, active playback, compositor
resources, and reference editing still require memory. Synthetic regression
coverage and a fresh native simulator launch do not establish the sole cause
of an observed whole-machine freeze or substitute for a long live session.

## Continuous motion on the desktop renderer

The macOS shell renders Flutter web with CanvasKit, where every `ui.Gradient`,
`ImageShader`, `ColorFilter` and `MaskFilter.blur` a painter creates is a Wasm
allocation that only a JavaScript finalizer frees — and the finalizer only runs
when the JavaScript heap grows, which a steadily repainting page does not make
it do. A single spinner that re-recorded the whole Create screen at 120 Hz
leaked ~96 MiB/min of gradients until the 2 GiB Wasm cap aborted the engine and
left the window blank. Four rules keep that from coming back.

### 1. Repaint isolation

No continuously animating widget may share a picture with the rest of the
page.

- Every vsync-driven site — Material's indeterminate `CircularProgressIndicator`
  and `LinearProgressIndicator`, `RotationTransition`, `AnimatedRotation` while
  it turns, `BusySpinner`, the loading placeholders in `MediaThumbnail` and the
  video loader — sits in a `MotionIsolate` (`lib/ui/motion_isolate.dart`).
  Since Flutter 3.27 a rebuild anywhere below a `LayoutBuilder` schedules that
  builder's layout callback, which dirties every ancestor up to the nearest
  relayout boundary; each of those re-runs layout and marks paint, so one 10 px
  spinner inside a card re-recorded the page. `MotionIsolate` is a
  `RepaintBoundary` around a tight-sized `LayoutBuilder`: the child's rebuilds
  stay in that builder's scope and its repaint stays in that layer. Give it a
  tight size (both dimensions, or one when the parent fixes the other); debug
  builds assert it.
- Long-lived indicators on cards (the status chip's ring, the progress bar
  under a rendering film, the "Loading preview" ring) use
  `PacedCircularProgressIndicator` / `PacedLinearProgressIndicator`
  (`lib/ui/paced_progress_indicator.dart`): Material's own geometry, painted
  from a `MotionClock` instead of a vsync ticker. Keep Material's widgets for
  short-lived work (a button's busy mark) and the paced ones for anything that
  can stay on screen for minutes.
- The Create screen's major sections each record their own picture: the
  heading, the composer (keyed per tab), the footer's model plaque and Generate
  key, the Recent work section, and every generation card. `TexturePanel` and
  `AppBackdrop` keep their photographs in their own layers, with a second
  boundary between the texture and its content. The top bar and the screen body
  are separate pictures too.
- Painters that change every frame take their motion through a
  `CustomPainter.repaint` listenable, never through a per-frame rebuild.

### 2. Painter allocation hygiene

Hot painters create shaders and geometry once per (size, theme inputs) and
reuse them across paints:

- `ShaderCache` / `PathCache` (`lib/ui/paint_cache.dart`) are small LRU stores
  that dispose what they evict. A `State` owns one and clears it in `dispose`;
  stateless painters share a module-level cache.
- The machined knob (`paintMachinedKnob`) draws about the origin on a
  translated canvas, so one rim/face/dome set serves every slider position.
  The groove track, switch well, Generate key bezel/lens/edges, and the model
  selector plate and key all cache by rectangle and room light. The lamps
  behind a lit Generate key change with the filament, so those shaders are
  created per frame and disposed with it.
- The stitched panel border and the tab-rail silhouettes are cut once per size.
  `TexturePanel` hands the engine one `ColorFilter` instance per tint.
- Nothing that repaints continuously blurs: `MaskFilter.blur` leaks a native
  object per draw in this engine. The update chip's shadow is painted once at a
  fixed hue for that reason; the Generate key's blurred seating shadow is
  acceptable because the key only repaints while lit.
- `test/support/shader_recording_canvas.dart` records shaders and mask filters
  without rendering. `paintTwice(painter.paint, size)` reports what a second
  paint created that the first did not; `test/painter_shader_reuse_test.dart`
  asserts that set is empty (or disposed) for every hot painter.

### 3. Placeholder cadence and pause policy

`MotionClock` (`lib/ui/motion_clock.dart`) drives the rendering placeholders
(both styles), the paced indicators, the estimated progress bar, and the update
chip's glow. It is a timer, not a ticker: at most 24 frames a second, and one
shared timer for every running clock so several surfaces cost one frame per
tick. It pauses entirely — no timer, no frames — when:

- the document is hidden, paused, or detached — an unfocused-but-visible
  desktop window is merely `inactive` and keeps animating, since its work is
  still in view;
- the route it sits on is not current (a detail modal above the studio stops
  the card underneath, so the film is animated once, not twice);
- the widget is outside any enclosing scroll viewport (judged in each
  viewport's own coordinates; re-checked on scroll, on every tick, and at 4 Hz
  while scrolled away);
- the `MotionPolicy` forbids motion: the person asked for reduced motion, or
  the renderer's memory brake latched.

`MotionPolicyScope` (`lib/ui/motion_policy.dart`) is provided from
`ClawnsoleApp`'s `MaterialApp.builder`, fed by `ReducedMotionWatcher`
(`lib/core/reduced_motion.dart`: `prefers-reduced-motion` on the web via
`matchMedia`, followed live; a stub elsewhere, where
`MediaQuery.disableAnimations` already carries the preference) and by
`RendererDiagnostics.motionConstrained`. Under either, a placeholder draws one
static frame. `MotionPolicy.of(context)` folds in the ambient media query, so
native targets need no scope.

### 4. Verifying with the renderer soak

`tool/renderer_soak.dart` renders a grid of placeholders with no controller or
library (`?style=broadcastStatic|cyclone&cards=12`, plus `&reduceMotion=1` or
`&constrained=1` to exercise the policy) and publishes `window.__soakFrames`,
the count of Flutter frames completed, for a runner to read.

The reproduction harness used for this fix rsyncs `flutter/` into a copy built
with the CI SDK (3.47) plus engine object counters, serves a copy of a library
with one generation forced pending from a companion on a spare port, and runs
an offscreen Electron window at 120 Hz printing JSON lines: CanvasKit heap,
rAF rate, Flutter frames per minute from `flutter-health`, and native object
counters (`Gradient.linear Created/Leaked`, `ColorFilter …`, …). Profile
builds also print `repaint-origin:`, `layout-origin:` and `build-origin:`
chains from an instrumented `rendering/object.dart` and
`widgets/framework.dart`; the first ancestor tagged `[RB]` is the boundary that
gets re-recorded. Run it with a window tall enough to show the pending card
(the default 980 px window keeps Recent work below the fold, where the
placeholder now correctly pauses). Healthy numbers: heap flat after warm-up
over three minutes, gradient and colour-filter creation flat at steady state,
Flutter frames ≈ 24/s with a placeholder on screen (rAF still reads 120), and
repaint origins limited to the placeholder's and indicators' own boundaries.
Never point the companion at `~/Library` data.
