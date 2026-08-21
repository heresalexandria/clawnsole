# Clawnsole for Flutter

This directory is the canonical Clawnsole implementation for iOS, Android,
native Windows, and the Electron macOS renderer. Flutter web is retained as the
internal Electron renderer and local companion-backed development harness, not
as a standalone hosted product. Product behavior belongs here; Electron owns
only macOS desktop lifecycle, packaging, and self-update.

## Capabilities

- BFL FLUX 3 and FLUX Video Upscale, LTX 2.3, ArtCraft’s live video catalog, and selected
  Create-ready Atlas Cloud models
- Text-to-video and image/reference-to-video across providers, plus FLUX 3
  video continuation and draft enhance
- BFL video super-resolution from 1.5×–3× with Precise/Creative detail modes,
  optional guidance, preserved source audio, and delivered-output rate display
- Model-aware multi-upload image, video, and audio references, kept distinct
  from first/last or explicitly timed keyframes
- A searchable saved-reference library with independent nested folders, tags,
  naming, sorting, and direct Saved/Generated selection from Create
- Start/last-frame workflows, supported fixed or auto durations, model-specific
  aspect ratios and resolutions, synchronized audio, draft mode, and safety tolerance
- Provider-aware balance checks and setting-aware USD estimates
- Live Atlas Cloud video catalog and schema-aware routes for Seedance, Grok, Veo,
  Wan, Kling, Vidu, PixVerse, Hailuo, and FLUX 3
- Canonical model identities for cross-provider route and cost comparison
- Exact Atlas route preflight where available, plus quoted-versus-realized
  costs and before/after balances in generation history
- Live polling, determinate/indeterminate progress, completed-video playback,
  draft enhancement, reuse, deletion, and device download
- Uncapped compact history plus referenced local inputs/completed videos, storage
  accounting, reload-safe reuse/playback, and granular clear actions
- Per-provider local keys and a responsive Providers comparison desk

### Input capability contract

The Create screen derives its controls from the selected model rather than
treating every image as a keyframe:

- BFL FLUX 3 exposes up to ten ordered/timed keyframes and one continuation
  video.
- BFL FLUX Video Upscale accepts a source clip up to 20 seconds and 50 MB,
  preserves its aspect ratio and audio, and delivers up to roughly 14.4 MP.
- LTX 2.3 exposes first/last-frame interpolation; Pro also exposes one
  audio-driven input up to 20 seconds at 720p/1080p or 10 seconds at 1440p/4K.
- ArtCraft’s checked-in create-ready catalog mirrors the public Omni catalog’s
  model-specific start/end, image, video, audio, and combined-reference limits.
  Where upstream modes are separate, Create keeps keyframes and creative
  references mutually exclusive; the live catalog still determines current
  availability and rate rows.
- Atlas Seedance 2.5 References exposes 30 images, 10 videos, and 10 audio
  clips (30 seconds total per media kind), plus explicit new-video, edit, and
  extend tasks. Seedance 2.0 References variants expose 9 images, 3 videos, and
  3 audio clips (15 seconds total). Their Frames endpoints remain deliberately
  limited to first and optional last images.
- Atlas routes outside Seedance map the shared form into each model family’s
  published field names, resolution values, audio flags, and image inputs.

Image, video, and audio references are ordered independently and retained as
separate local assets. Provider upload adapters convert local media into the
token or hosted-asset form required by ArtCraft and Atlas before submission.
The References tab stores reusable media alongside compact metadata. Its folder
tree is independent from Generated history, while the Create picker can search
either hierarchy without copying local assets unnecessarily.

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
./scripts/start_windows
```

`start_web` starts the loopback companion, waits for its health check, opens
Chrome, and stops the companion when Flutter exits. `start_ios` reuses a booted
iPhone simulator or boots the newest available one. `start_android` reuses a
running Android emulator or launches the first configured Android AVD.
`start_macos` builds Flutter web, serves it through the Dart companion, and
opens the thin Electron shell.
`start_windows` runs the native Flutter desktop app and must be invoked on a
Windows machine with Visual Studio's Desktop development with C++ workload.

Optional Google Drive support is shared by every surface. Configure the
platform OAuth client before launching:

- macOS Electron and native Windows:
  `CLAWNSOLE_GOOGLE_DESKTOP_CLIENT_ID` (and the optional installed-app client
  secret)
- Android: `CLAWNSOLE_GOOGLE_ANDROID_SERVER_CLIENT_ID`, using the registered
  web client ID; also register the Android package and every signing SHA
- iOS: `CLAWNSOLE_GOOGLE_IOS_CLIENT_ID`; the iOS scripts derive and inject its
  native client ID and reversed callback URL scheme. TestFlight and App Store
  builds use Apple App Attest for Google Sign-In App Check. Local development
  and simulator requests may remain unverified unless a debug provider is
  configured, so enable App Check enforcement only after a Drive sign-in from
  a TestFlight or App Store build appears as verified in Google Cloud.

Use `CLAWNSOLE_IOS_SIMULATOR_ID`, `CLAWNSOLE_ANDROID_AVD_ID`, or
`CLAWNSOLE_ANDROID_DEVICE_ID` to choose a specific emulator. Every script also
accepts extra `flutter run` arguments.

## Run on iOS or Android

Native builds call the selected provider directly. API keys are kept in
OS-secure storage; compact history is stored in `Clawnsole/clawnsole.json`,
with retained media in the adjacent `assets/` directory.

```bash
flutter run -d ios
flutter run -d android
```

Android release builds require your own signing configuration before store
distribution. iOS device/archive builds require an Apple development team and
the usual Xcode signing setup.

## Develop the internal web renderer

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

The companion binds only to IPv4 loopback and authenticates privileged
Electron requests with a per-launch token. The renderer receives sanitized
history and whether a key exists, never the saved provider key or cached vault
key. The direct `start_web` harness encrypts secure values with a development
key stored beside its ignored local data with owner-only file permissions;
packaged macOS uses Electron `safeStorage` instead. This target is not
published as a standalone website.

Native and companion-backed builds keep their existing local library and show
it alongside Drive with explicit Local/Drive badges and filters. The default
destination for new work is remembered. “Copy local library to Drive” creates
portable copies while retaining the local originals; rerunning it is
idempotent. Provider API keys and preferences sync only through the separately
encrypted settings vault.

## Build targets

```bash
./scripts/build_web
./scripts/build_ios
./scripts/build_android
./scripts/build_macos
./scripts/build_windows
```

- `build_web` creates `build/web` and compiles the companion into the standalone
  `build/clawnsole_companion` executable. By default the companion serves that
  directory on the same origin; pass `CLAWNSOLE_PROXY_URL` only when hosting the
  two separately.
- `build_ios` creates a signed Xcode archive and IPA. It defaults to App Store
  export; set `CLAWNSOLE_IOS_EXPORT_METHOD` to `ad-hoc`, `development`, or
  `enterprise` when appropriate. Xcode signing must already be configured. iOS
  builds are deliberately local-only and are not run or published by GitHub
  Actions. Provider test keys are opt-in and excluded by default. To prepare a
  review build that includes them, set `INCLUDE_IOS_TEST_KEYS=true` plus
  `CLAWNSOLE_IOS_REVIEW_BFL_API_KEY`,
  `CLAWNSOLE_IOS_REVIEW_LTX_API_KEY`,
  `CLAWNSOLE_IOS_REVIEW_ATLAS_API_KEY`, and/or
  `CLAWNSOLE_IOS_REVIEW_ARTCRAFT_API_KEY`. A local, Git-ignored
  `flutter/.env.ios-review` or repository `.env` is loaded automatically; the
  ordinary `BFL_API_KEY`, `LTX_API_KEY`, `ARTCRAFT_KEY`, and
  `ATLAS_CLOUD_KEY` names act as development/App Review fallbacks. The script
  passes credentials only to the iOS compiler when the opt-in is true;
  Android, macOS, Windows, and the internal renderer build do not receive them.
- `build_android` creates the Play Store AAB. It intentionally refuses to build
  until `android/key.properties` points at a real upload keystore; copy
  `android/key.properties.example` to get started.
- `build_macos` packages the Flutter web output and companion in Electron,
  producing the standalone app, DMG, and updater ZIP. Its Drive refresh token
  is encrypted with Electron `safeStorage`.
- `build_windows` creates the native x64 release directory under
  `build/windows/x64/runner/Release`. It rejects Dart defines and clears provider
  credential variables so API keys cannot be compiled into the executable. Its
  Drive refresh token is stored with the operating-system-backed secure storage
  plugin.

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
- Uploaded and saved references plus generated videos are separate local files,
  enabling preview, playback, search, and full-input reuse after restart.
- BFL delivery links are treated as ten-minute links and pruned after the result
  is copied locally.
- Removing history preserves the References library and prunes only assets no
  longer used by a saved reference or another generation.

## Verification

```bash
dart format --output=none --set-exit-if-changed lib tool test
flutter analyze
flutter test
flutter build web
```

The implementation follows the official BFL, LTX, ArtCraft, and Atlas Cloud API,
polling, model capability, and pricing documentation. Atlas models are read
from its public catalog; supported-duration Create-ready costs use exact route
payloads with its calculate endpoint and checked-in starting-rate fallbacks.
