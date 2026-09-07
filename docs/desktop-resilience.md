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
