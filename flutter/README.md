# Clawnsole for Flutter

This directory is the canonical Clawnsole implementation for web, iOS, Android,
and the Electron macOS renderer. Product behavior belongs here; Electron owns
only desktop lifecycle, packaging, and self-update.

## Capabilities

- BFL FLUX 3, LTX 2.5/2.3, ArtCraft’s live video catalog, and selected
  Create-ready Atlas Cloud models
- Text-to-video and image/reference-to-video across providers, plus FLUX 3
  video continuation and draft enhance
- Provider-aware uploaded or hosted references, with FLUX-specific even or
  explicit keyframe timing
- Start/last-frame workflows, supported fixed or auto durations, model-specific
  aspect ratios and resolutions, synchronized audio, draft mode, and safety tolerance
- Provider-aware balance checks and setting-aware USD estimates
- Live Atlas video catalog and no-charge request preflight, with published
  provider pricing fallbacks
- Provider-reported charges and before/after balances in generation history
- Live polling, determinate/indeterminate progress, completed-video playback,
  draft enhancement, reuse, deletion, and device download
- Uncapped compact history plus referenced local inputs/completed videos, storage
  accounting, reload-safe reuse/playback, and granular clear actions
- Per-provider local keys and a responsive Providers comparison desk

## Install

Use Flutter 3.35.1 or newer and Dart 3.9 or newer.

```bash
cd flutter
flutter pub get
```

## One-command local starts

The scripts install missing Dart packages, select or launch a local emulator,
and keep Flutter attached for hot reload:

```bash
./scripts/start_web
./scripts/start_ios
./scripts/start_android
./scripts/start_macos
```

`start_web` starts the loopback companion, waits for its health check, opens
Chrome, and stops the companion when Flutter exits. `start_ios` reuses a booted
iPhone simulator or boots the newest available one. `start_android` reuses a
running Android emulator or launches the first configured Android AVD.
`start_macos` builds Flutter web, serves it through the Dart companion, and
opens the thin Electron shell.

Use `CLAWNSOLE_IOS_SIMULATOR_ID`, `CLAWNSOLE_ANDROID_AVD_ID`, or
`CLAWNSOLE_ANDROID_DEVICE_ID` to choose a specific emulator. Every script also
accepts extra `flutter run` arguments.

## Run on iOS or Android

Native builds call the selected provider directly. API keys and compact
history are stored in `Clawnsole/clawnsole.json`, with retained media in the
adjacent `assets/` directory. The OS app sandbox protects both from other apps.

```bash
flutter run -d ios
flutter run -d android
```

Android release builds require your own signing configuration before store
distribution. iOS device/archive builds require an Apple development team and
the usual Xcode signing setup.

## Run on web

Browsers cannot write an application JSON file directly, and providers do not
grant arbitrary browser origins API access. Clawnsole therefore includes a
loopback-only Dart companion that owns provider keys, requests, polling,
media proxy, and the local JSON file. No `localStorage` or IndexedDB history is
used.

Normally, use the single command:

```bash
./scripts/start_web
```

The script owns both the companion and Flutter process. The manual two-terminal
workflow remains available when debugging the companion itself.

The default companion address is `http://127.0.0.1:8787`. The start script uses
the repository's `.clawnsole/clawnsole.json`, preserving history from the retired
root application. Both are local-only.

Override them when needed:

```bash
CLAWNSOLE_FLUTTER_DATA_FILE=/absolute/path/clawnsole.json \
  dart run tool/clawnsole_companion.dart --port 8790

flutter run -d chrome \
  --dart-define=CLAWNSOLE_PROXY_URL=http://127.0.0.1:8790
```

The companion binds only to IPv4 loopback and accepts only localhost browser
origins. The browser receives sanitized history and whether a key exists, never
the saved key itself.

## Build targets

```bash
./scripts/build_web
./scripts/build_ios
./scripts/build_android
./scripts/build_macos
```

- `build_web` creates `build/web` and compiles the companion into the standalone
  `build/clawnsole_companion` executable. By default the companion serves that
  directory on the same origin; pass `CLAWNSOLE_PROXY_URL` only when hosting the
  two separately.
- `build_ios` creates a signed Xcode archive and IPA. It defaults to App Store
  export; set `CLAWNSOLE_IOS_EXPORT_METHOD` to `ad-hoc`, `development`, or
  `enterprise` when appropriate. Xcode signing must already be configured. iOS
  builds are deliberately local-only and are not run or published by GitHub
  Actions. For App Review, set `CLAWNSOLE_IOS_REVIEW_BFL_API_KEY`,
  `CLAWNSOLE_IOS_REVIEW_LTX_API_KEY`,
  `CLAWNSOLE_IOS_REVIEW_ATLAS_API_KEY`, and/or
  `CLAWNSOLE_IOS_REVIEW_ARTCRAFT_API_KEY`. A local, Git-ignored
  `flutter/.env.ios-review` or repository `.env` is loaded automatically; the
  ordinary `BFL_API_KEY`, `LTX_API_KEY`, `ARTCRAFT_KEY`, and
  `ATLAS_CLOUD_KEY` names act as development/App Review fallbacks. The script
  passes credentials only to the iOS compiler; web, Android, and macOS builds
  do not receive it.
- `build_android` creates the Play Store AAB. It intentionally refuses to build
  until `android/key.properties` points at a real upload keystore; copy
  `android/key.properties.example` to get started.
- `build_macos` packages the Flutter web output and companion in Electron,
  producing the standalone app, DMG, and updater ZIP.

All build scripts accept extra Flutter build arguments such as `--build-name`
and `--build-number`.

Each iOS review credential is a fallback, not local user data. A saved user key
takes precedence. Clawnsole validates active access at launch and immediately
before generation; HTTP 401/403 responses during credit checks, submission, or
polling invalidate the active source. The review credential is never populated
into a field, returned through a snapshot, or written to `clawnsole.json`.

Any credential compiled into a client IPA can be recovered by a determined
party. Use a temporary, revocable, least-privilege project key with a strict
spending limit, and revoke it as soon as App Review is complete. A server-side
broker is required if the credential must remain a true secret.

## Persistence policy

- History is compact and uncapped.
- Prompts, request IDs, polling URLs, status, settings, costs, and small asset
  references are retained in JSON; base64 payloads are never written there.
- Uploaded references and generated videos are separate local files, enabling
  preview, playback, and full-input reuse after restart.
- BFL delivery links are treated as ten-minute links and pruned after the result
  is copied locally.
- Removing history prunes unreferenced assets. Saving exports a user-directed copy.

## Verification

```bash
dart format --output=none --set-exit-if-changed lib tool test
flutter analyze
flutter test
flutter build web
```

The implementation follows the official BFL, LTX, ArtCraft, and Atlas Cloud API,
polling, model capability, and pricing documentation. Atlas models are read
from its public catalog; 720p Create-ready costs use its calculate endpoint,
with checked-in starting-rate fallbacks.
