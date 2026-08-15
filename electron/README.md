# Clawnsole for macOS

Electron is a thin native shell around the canonical Flutter implementation. A
desktop build packages `flutter/build/web` and the compiled Dart companion. The
companion serves the Flutter bundle and owns local BFL requests, persistence,
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

## Signing and notarization

Local builds default to ad-hoc/unsigned packaging. Set
`CLAWNSOLE_ELECTRON_SIGN=true` and provide Electron Builder's certificate
environment for Developer ID signing. Published CI builds require:

- `MACOS_CERTIFICATE_P12`
- `MACOS_CERTIFICATE_PASSWORD`

CI rejects a release unless the completed app has a strict, valid Developer ID
bundle signature for Team ID `KMZ785G889`. Notarization is enabled when all of
these optional secrets are present:

- `APPLE_ID`
- `APPLE_APP_SPECIFIC_PASSWORD`
- `APPLE_TEAM_ID`

Partial notarization configuration is treated as an error.

## Self-update

The app checks the latest release at most once every 24 hours and provides
**Clawnsole → Check for Updates…** for an explicit check. It downloads the
matching `Clawnsole-<version>-mac-<arch>.zip`, requires a matching digest in
`SHA256SUMS.txt`, unpacks with `ditto`, and performs a rollback-safe app swap
after the running process exits. User data is outside the app bundle and is not
touched.

See [desktop update design](../docs/updates.md).
