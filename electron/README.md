# Clawnsole for macOS

Electron is a thin native shell around the canonical Flutter implementation. A
desktop build packages `flutter/build/web` and the compiled Dart companion. The
companion serves the Flutter bundle and owns local provider requests, persistence,
and media on one private loopback origin. No root Next.js app or external runtime
is required.

## Canonical commands

From the repository root:

```bash
./flutter/scripts/start_macos
./flutter/scripts/build_macos
```

The direct `electron/scripts/start_macos` and `electron/scripts/build_macos`
commands remain implementation-level aliases. Development builds Flutter web,
runs the companion from source, and opens Electron. Release builds compile the
companion, package the Flutter output, and produce a `.app`, DMG, and ZIP in
`electron/dist/release`.

Set `CLAWNSOLE_ELECTRON_ARCH` to `arm64` or `x64`. A matching Dart companion is
compiled on that machine, so each architecture should be built on its matching
runner. The current release workflow ships Apple silicon and can add Intel later.

Desktop data lives at
`~/Library/Application Support/Clawnsole/clawnsole.json`, with retained media in
the adjacent `assets/` directory.

For local development, `start_macos` loads the ignored repository `.env` so
`BFL_API_KEY`, `LTX_API_KEY`, `ARTCRAFT_KEY`, `ATLAS_CLOUD_KEY`,
`RUNWAY_KEY` (or Runway’s standard `RUNWAYML_API_SECRET`), and `KREA_API_KEY`
can act as test credentials without exposing them to the Flutter renderer. Saved keys
still take precedence.

Renderer navigation may open only the exact provider and Clawnsole hosts in
`lib/runtime.cjs`. Explicit media links use a purpose-scoped shell bridge that
accepts credential-free HTTPS destinations, while release links are restricted
to this repository's GitHub releases. The bridge also verifies that requests
come from the active local renderer before handing a URL to macOS.

## Menus and window lifecycle

`lib/application-menu.cjs` builds the whole menu bar:

- **Clawnsole** carries About, **Check for Updates…**, and **Settings…**
  (`⌘,`). Settings sends `{ section: 'settings' }` to the renderer over the
  `clawnsole:navigate` channel, which the preload exposes as
  `window.clawnsole.onNavigate(callback)`. Flutter owns the destination; the
  shell only names the section.
- **View** includes **Reload Studio**, actual size, zoom in, zoom out, and full
  screen. Reload Studio replaces the renderer while leaving the companion
  running. Force Reload and Toggle DevTools remain development-only.
- **Help** opens the privacy policy, terms of use, and issue tracker through
  the same external-URL allowlist as every other link, **Show Logs** reveals
  the local diagnostic log even when the studio cannot draw, and **Save
  Diagnostics Report…** writes one text bundle (both logs, Clawnsole's macOS
  crash reports, versions and process metrics) wherever the user chooses. The
  bundle may contain the computer's name and file paths; the dialog says so.

Clawnsole follows the macOS lifecycle: closing the window does not quit, the
companion keeps serving while the app is windowless, Dock activation rebuilds
the window, and `⌘Q` quits and stops the companion.

The preload also exposes `window.clawnsole.notify({ title, body })`, which
resolves to `true` only when a system notification was actually posted. The
shell posts one only while the Clawnsole window is unfocused — a focused
window already shows the same event in the app, and a banner over it would
only be noise — so a `false` result means the renderer should say it itself.

## Companion supervision and logs

`lib/companion-supervisor.cjs` owns the packaged companion. It pings
`/health` every 30 seconds, and an unexpected exit or three consecutive failed
pings trigger one automatic restart after a short backoff. The restart replays
the same bootstrap line, so the companion reopens the same secure store with
the same session token, and prefers the previous port so the renderer origin
usually survives; when the port has been taken, the session header rebinds and
the window reloads from the new origin. A second failure inside ten minutes is
a crash loop, and Clawnsole offers **Reopen**, **Show Logs**, and **Quit**.

Companion stdout and stderr are captured to `companion.log` in
`~/Library/Logs/Clawnsole`, rotating to `companion.log.1` at 5 MB so only the
two newest files are kept. **Show Logs** reveals the current file in Finder.
Development builds also echo the same lines to the terminal.

A renderer that crashes is reloaded once; a second crash offers **Reload** or
**Quit**, and a hung renderer offers **Wait** or **Relaunch**.

An alive renderer can still fail to draw. Bounded diagnostics in the same log
record Flutter/browser errors, graphics context loss, executable stack locations,
and once-per-minute process CPU/memory and Flutter frame/cache/CanvasKit heap
metrics, plus the engine's own object counters (the web build sets
`FLUTTER_WEB_ENABLE_INSTRUMENTATION`). Error storms are capped before IPC and
again before disk writes, with suppressed counts retained. These records omit
exception messages, prompts, media, credentials, and full URLs. No debugging
port is opened automatically.

`lib/renderer-diagnostics.cjs` also derives alerts from consecutive health
records. A Flutter engine that aborted inside WebAssembly, froze its frame
count while errors keep arriving in the foreground, or whose wasm heap reached
1.5 GiB is reported to `lib/renderer-recovery.cjs` as engine-dead, and the
window is reloaded through the same one-silent-reload-then-dialog budget as a
process crash ("Clawnsole Stopped Drawing"). Heap growth alone, isolated
errors and idle screens never reload anything. The window-level
`webglcontextlost` listener cannot see CanvasKit's OffscreenCanvas context;
the `graphics-context-lost` console category and GPU process loss are the
signals to read. `scripts/soak-renderer.cjs` is a development tool that
samples heap, frame rate and engine counters for a URL in an isolated profile.
See [desktop diagnostics](../docs/desktop-diagnostics.md) for record shapes,
the reload rules, and soak instructions.

The packaged companion reuses the port it bound last time
(`companion-port.json` in Application Support) so Chromium's cached media for
that origin stays valid between launches; a taken port falls back to a random
one. Because the origin is stable, the renderer is built without a service
worker and the shell clears any worker or CacheStorage left on the origin
before every load, so an update can never be shadowed by a cached bundle.

Canonical web builds include source maps alongside the internal renderer so
recorded JavaScript locations can be mapped to the exact packaged Dart sources.
Use the map from the affected app version, not a fresh build with another SDK.

## Signing and notarization

Local builds default to ad-hoc/unsigned packaging. Set
`CLAWNSOLE_ELECTRON_SIGN=true` and provide Electron Builder's certificate
environment for Developer ID signing. Published CI builds require:

- `MACOS_CERTIFICATE_P12`
- `MACOS_CERTIFICATE_PASSWORD`

CI rejects a release unless the completed app has a strict, valid Developer ID
bundle signature for Team ID `KMZ785G889`. It also requires these notarization
secrets:

- `APPLE_ID`
- `APPLE_APP_SPECIFIC_PASSWORD`
- `APPLE_TEAM_ID`

Local signed builds use the `clawnsole-notarization` notarytool profile from the
login Keychain by default, keeping the app-specific password out of the shell:

```bash
CLAWNSOLE_ELECTRON_SIGN=true ./flutter/scripts/build_macos
```

Set `CLAWNSOLE_NOTARY_KEYCHAIN_PROFILE` to select a different local profile.

The hardened runtime is always on, and `assets/entitlements.mac.plist` is used
for both `entitlements` and `entitlementsInherit`, so the app and every helper
it contains are signed with the same pair of entitlements:

- `com.apple.security.cs.allow-jit`
- `com.apple.security.cs.allow-unsigned-executable-memory`

V8 needs both. Nothing else is granted: library validation stays enabled and
dyld environment variables stay blocked, so no unsigned code can be loaded into
Clawnsole. Add an entitlement only when a feature cannot ship without it.

## Self-update

The app checks the latest release afresh on startup, then at most once every 24
hours while it remains open, and provides **Clawnsole → Check for Updates…** for
an explicit check. It downloads the matching
`Clawnsole-<version>-mac-<arch>.zip`, requires a matching digest in
`SHA256SUMS.txt`, and unpacks it with `ditto`.

Before anything is swapped, the unpacked bundle must also prove it came from
Clawnsole. The updater runs `codesign --verify --deep --strict`, then reads
`TeamIdentifier=` from `codesign -d --verbose=2` and requires `KMZ785G889` —
the same Team ID the release workflow enforces. A failed signature or a
different team refuses the install with an explicit error. Only a bundle that
passed both checks is copied into place, and only then is it released from
quarantine: verify first, unquarantine last.

The swap runs after the process exits and is rollback safe. It writes
`update-result.json` beside the staged update and reopens the previous bundle
whenever the replacement fails, and the next launch reports that result once.
User data lives outside the app bundle and is never touched.

An app outside `/Applications` cannot replace itself: Gatekeeper runs a
freshly downloaded copy from a read-only randomized path, and elsewhere the
swap trips over permissions. The first packaged launch from another location
offers to move Clawnsole to Applications and remembers a decline, and
permission, read-only, and translocation failures all report
"Move Clawnsole to your Applications folder, then check for updates again."

See [desktop update design](../docs/updates.md).
