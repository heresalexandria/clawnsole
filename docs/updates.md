# Electron desktop updates

Packaged macOS builds check GitHub Releases at most once every 24 hours. A manual
check is always available from **Clawnsole → Check for Updates…** or from the
version chip beside the wordmark in the app's top bar. Development builds explain
that they update through git instead of replacing themselves.

## In-app version chip and update dialog

The Flutter top bar shows the running version. It checks once per launch
(`lib/core/update_status.dart`) and marks the chip with a brass dot when a newer
release exists; opening the dialog re-checks immediately. Store-managed
platforms (iOS, Android) skip the check entirely because the App Store owns
their updates, and `ClawnsoleApp(checkForUpdates: false)` disables it in tests.

Where the shell can install in place, the dialog's primary action is
**Download and install <version>** — the same verified pipeline as the system
menu, not a link to GitHub. It falls back to a release link only when there is
no self-updating shell (a browser preview), and says so plainly when an
unpackaged development build declines to replace itself.

## Renderer bridge

`electron/preload.cjs` exposes `window.clawnsole` to the Flutter renderer with
`checkForUpdate()`, `startUpdate()`, and an `onUpdateEvent(callback)`
subscription. The Flutter app (`lib/core/shell_bridge*.dart`) feature-detects
this surface. Any in-flight download — including one begun from the system menu
— streams `downloading / installing / error` events that open a blocking
progress modal in the UI, alongside the dock-icon progress bar. Failures the
renderer detects itself are pushed onto the same stream, so the modal always
resolves instead of hanging. Renderer-initiated installs skip the native
confirmation dialog because the in-app dialog already carries the user's
consent; the download, checksum, and swap pipeline below is identical for both
entry points.

## Update flow

1. Read `heresalexandria/clawnsole`'s latest stable GitHub release.
2. Compare its semantic tag with the running Electron package version.
3. Select only `Clawnsole-<version>-mac-<current architecture>.zip`.
4. Download the ZIP from an allow-listed GitHub TLS host.
5. Require and verify the matching SHA-256 value in `SHA256SUMS.txt`.
6. Expand with `ditto`, replace the installed `.app`, and reopen Clawnsole.

The replacement happens in a detached helper after Electron exits. The current
bundle is moved aside first and restored if copying the new one fails. The app
checks that its parent directory is writable before it quits. Application
Support data and retained media live outside the bundle and are untouched.

## Why this is custom

This follows Aesthetician's updater instead of relying on `electron-updater`.
Squirrel.Mac refuses unsigned replacements; Clawnsole needs initial ad-hoc builds
to remain updateable before Developer ID signing is configured. Once every build
is signed and notarized, moving to `electron-updater` is reasonable, but it is
not required for the current release contract.

Only GitHub API, release, object, and release-asset hosts are accepted. Release
payload URLs are never trusted without validation. A missing checksum is a hard
failure rather than an unverified install.

## Manual validation

After changing the disk-swap path:

1. Publish an older and newer release with ZIPs and checksums.
2. Install the older `Clawnsole.app` in a writable location.
3. Choose **Check for Updates…**, then **Download and Install**.
4. Confirm the app reopens at the new version and history/media remain intact.
5. Repeat from an unwritable directory and confirm the app reports the problem
   without quitting.

Pure version, URL, checksum, and asset-selection decisions run under:

```bash
cd electron && npm test
```
