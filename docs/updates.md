# App updates

Every supported build checks its public release source on startup and every 24
hours while running. Native iOS checks Apple's App Store lookup catalog so only
versions that users can actually install are reported. The other surfaces check
GitHub Releases. A manual macOS check is also available from **Clawnsole → Check
for Updates…** or from the version beside the wordmark in the app's top bar.
Native Windows builds send available updates to the GitHub release for a manual
download. Development builds explain that they update through git instead of
replacing themselves.

When the platform's release source successfully reports a newer **major**
version, Clawnsole blocks continued use until the update begins. macOS uses the
verified in-place updater; iOS opens App Store product `6801916362`, and Android
opens Google Play package `app.clawnsole.clawnsole`. The gate is never shown
when the request fails, the version cannot be parsed, or the newest release
remains in the current major version. App Store review and processing are
therefore decoupled from GitHub release timing. Android still reads GitHub, so
publish the GitHub release only after its Play Store build is available.

## In-app version chip and update dialog

The Flutter top bar always shows the running version. On viewports at least 900
pixels wide, a newer release adds an animated blue-purple **Update Available**
chip beside the version. Packaged macOS can install from that chip; Windows and
development builds open the update dialog and release link. Compact
viewports and native mobile apps keep the header uncluttered and flash an update
notification instead. iOS and Android leave installation to their stores.
Opening the version dialog re-checks immediately outside store-managed builds.
`ClawnsoleApp(checkForUpdates: false)` disables network checks in tests.

The launch check is always fresh. Later automatic checks retain the macOS
shell's persisted 24-hour throttle, while other surfaces query on the shared
24-hour in-process schedule.

Where the shell can install in place, the dialog's primary action is
**Download and install <version>** uses the same verified pipeline as the system
menu, not a link to GitHub. It falls back to a release link only when there is
no self-updating shell, including native Windows, and says
so plainly when an unpackaged development build declines to replace itself.

## Renderer bridge

`electron/preload.cjs` exposes `window.clawnsole` to the Flutter renderer with
`checkForUpdate()`, `startUpdate()`, and an `onUpdateEvent(callback)`
subscription. The Flutter app (`lib/core/shell_bridge*.dart`) feature-detects
this surface. Any in-flight download, including one begun from the system menu,
streams `downloading / installing / error` events that open a blocking
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
