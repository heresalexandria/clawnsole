# Clawnsole for Flutter

This directory is a standalone Flutter implementation of Clawnsole for web,
iOS, and Android. It does not import, rewrite, or change the sibling Next.js
application.

## Capabilities

- FLUX 3 text-to-video, image-to-video, video continuation, and draft enhance
- One to ten uploaded or hosted keyframes, with even or explicit timing
- Start/last-frame workflows, auto or 5–20 second duration, all documented
  aspect ratios, HD/FHD, synchronized audio, draft mode, and safety tolerance
- Live BFL credit balance and setting-aware credit/USD estimates
- Exact API charge plus before/after credit snapshots in generation history
- Live polling, determinate/indeterminate progress, completed-video playback,
  draft enhancement, reuse, deletion, and device download
- Uncapped compact local history with file-size accounting and granular clear
  actions; uploaded sources and video blobs are never persisted
- Provider-neutral gateway, catalog, and pricing boundaries for future services

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
```

`start_web` starts the loopback companion, waits for its health check, opens
Chrome, and stops the companion when Flutter exits. `start_ios` reuses a booted
iPhone simulator or boots the newest available one. `start_android` reuses a
running Android emulator or launches the first configured Android AVD.

Use `CLAWNSOLE_IOS_SIMULATOR_ID`, `CLAWNSOLE_ANDROID_AVD_ID`, or
`CLAWNSOLE_ANDROID_DEVICE_ID` to choose a specific emulator. Every script also
accepts extra `flutter run` arguments.

## Run on iOS or Android

Native builds call `https://api.bfl.ai` directly. The API key and compact
history are stored in `Clawnsole/clawnsole.json` inside the app documents
directory. The OS app sandbox protects this file from other apps.

```bash
flutter run -d ios
flutter run -d android
```

Android release builds require your own signing configuration before store
distribution. iOS device/archive builds require an Apple development team and
the usual Xcode signing setup.

## Run on web

Browsers cannot write an application JSON file directly, and BFL does not
grant arbitrary browser origins API access. Clawnsole therefore includes a
loopback-only Dart companion that owns the API key, BFL requests, polling,
media proxy, and the local JSON file. No `localStorage` or IndexedDB history is
used.

Normally, use the single command:

```bash
./scripts/start_web
```

The script owns both the companion and Flutter process. The manual two-terminal
workflow remains available when debugging the companion itself.

The default companion address is `http://127.0.0.1:8787`, and its default data
file is `flutter/.clawnsole/clawnsole-flutter.json`. Both are local-only.

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
```

- `build_web` creates `build/web` and compiles the companion into the standalone
  `build/clawnsole_companion` executable. The static web bundle still needs that
  local companion while it is used.
- `build_ios` creates a signed Xcode archive and IPA. It defaults to App Store
  export; set `CLAWNSOLE_IOS_EXPORT_METHOD` to `ad-hoc`, `development`, or
  `enterprise` when appropriate. Xcode signing must already be configured.
- `build_android` creates the Play Store AAB. It intentionally refuses to build
  until `android/key.properties` points at a real upload keystore; copy
  `android/key.properties.example` to get started.

All build scripts accept extra Flutter build arguments such as `--build-name`
and `--build-number`.

## Persistence policy

- History is compact and uncapped.
- Prompts, request IDs, polling URLs, status, settings, costs, and temporary
  delivery URLs are retained.
- Uploaded images, source clips, draft bundles, and generated video bytes are
  held only long enough to submit or save; they are not written to history.
- BFL delivery links are treated as ten-minute links and pruned after expiry.
- Saving a video is an explicit user-directed download/filesystem action.

## Verification

```bash
dart format --output=none --set-exit-if-changed lib tool test
flutter analyze
flutter test
flutter build web
```

The implementation follows BFL’s FLUX 3 documentation, credits endpoint,
polling guidance, and published pricing calculator.
