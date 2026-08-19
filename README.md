<p align="center">
  <img src="icon.png" alt="Clawnsole icon" width="96" height="96">
</p>

<h1 align="center">Clawnsole</h1>

<p align="center"><em>Local BYO key studio for AI video generation</em></p>

<p align="center">
  <a href="https://github.com/heresalexandria/clawnsole/releases/latest/download/Clawnsole-mac-arm64.dmg"><strong>Download the latest macOS build (Apple silicon)</strong></a>
  ·
  <a href="https://github.com/heresalexandria/clawnsole/releases/latest/download/Clawnsole-windows-x64.zip"><strong>Download the latest Windows build (x64)</strong></a>
</p>

<p align="center">
  <picture>
    <source media="(prefers-color-scheme: dark)" srcset="docs/assets/clawnsole-preview-dark.png">
    <img src="docs/assets/clawnsole-preview.png" alt="Clawnsole Create screen with its machined duration knob, metal audio switch, console-key frame and finish tiles, and the hunter-green estimated-charge panel">
  </picture>
</p>

Clawnsole is a local-first Flutter video generation workspace with a premium,
midcentury-inspired interface — skeuomorphic console hardware included: a
machined-steel duration knob, metal toggles that light hunter green, and
recessed counter readouts, all drawn in code so every platform matches. Cloud
video providers share one provider-neutral Create, Library, and References
workflow. Generated work and saved reference media each have independent local
folder hierarchies and reusable tags.

## iPhone

<p align="center">
  <img src="docs/app-store/iphone/01-create.png" alt="Create an AI video in Clawnsole on iPhone" width="31%">
  <img src="docs/app-store/iphone/02-providers.png" alt="Choose providers and compare model costs in Clawnsole on iPhone" width="31%">
  <img src="docs/app-store/iphone/03-library.png" alt="Browse the local film library in Clawnsole on iPhone" width="31%">
</p>

## What it does

- Provider-aware text-to-video and image-to-video, plus FLUX 3 continuation and draft enhancement
- Model-aware image, video, and audio references, with timing and placement controls where supported
- Model-specific durations, aspect ratios, resolutions, audio, draft, and safety controls
- Live polling, manual status refresh, surfaced provider errors, and progress
- Provider balance when exposed by the API, plus setting-aware USD or credit estimates
- Per-generation quoted and realized USD cost history with provenance
- Reload-safe input previews, fullscreen playback, save-as download, and full input reuse
- Nested project folders, multi-tag organization, and combined prompt/tag/folder search
- A saved References tab with naming, nested folders, tags, media-type filters,
  sorting, and Saved/Generated pickers directly in Create
- One-tap folder and tag filters with a desktop folder rail and compact mobile picker
- System-aware light and dark themes with an explicit appearance switcher
- Uncapped compact history with retained media files and granular clear controls
- Local API-key setup with no database, `localStorage`, or IndexedDB history in
  the native and companion-backed targets
- An isolated GitHub Pages-ready browser target with optional Google Drive
  history/media sync and device-local API keys; Atlas Cloud is the initial
  static-host provider because its API allows the Pages origin
- A Providers desk for per-provider keys, console/docs links, live Atlas model
  discovery, canonical cross-provider model matching, observed quote variance,
  and route-aware 10/15/20/30-second USD comparisons

## One product, five targets

Flutter owns all product behavior, including the native Windows app. Electron
is only the macOS lifecycle and self-update shell around Flutter's web build and
local Dart companion. The old root Next.js implementation has been removed.

```bash
# from the repository root
./flutter/scripts/start_web
./flutter/scripts/start_ios
./flutter/scripts/start_android
./flutter/scripts/start_macos
./flutter/scripts/start_windows

# isolated backend-free browser target
CLAWNSOLE_GOOGLE_CLIENT_ID='…apps.googleusercontent.com' \
  ./flutter/scripts/start_github_pages
```

The matching deployable builds are:

```bash
./flutter/scripts/build_web
./flutter/scripts/build_ios
./flutter/scripts/build_android
./flutter/scripts/build_macos
./flutter/scripts/build_windows
./flutter/scripts/build_github_pages
```

See [Flutter setup](flutter/README.md) and [macOS desktop packaging](electron/README.md).
Windows scripts run on Windows with Visual Studio and its Desktop development
with C++ workload installed.

## Persistence

Clawnsole has no database. Native apps store `clawnsole.json` inside their
application support sandbox. Companion-backed web and Electron store the same
compact schema in a local file, with retained inputs and videos in an adjacent
`assets/` directory. The separate standalone browser build stores portable
metadata and media in a user-authorized Google Drive folder; only device API
keys and a connection hint use localStorage.

- History is not capped.
- Folder names, tag labels, generation assignments, and saved-reference metadata
  live in the same compact local JSON schema and migrate without changing older records.
- Removing a folder never removes its films; directly filed work returns to
  **Unfiled**, tags stay intact, and subfolders move up one level.
- Reference folders follow the same safe removal behavior within their separate
  hierarchy.
- Base64 request payloads and video blobs are never stored in JSON.
- Removing history prunes media only when it is no longer used by another
  generation or a saved reference.
- Provider delivery links may be temporary; completed videos are retained locally first.
- User-supplied provider keys are plaintext inside the locally protected JSON file
  and are never returned to the web renderer. An optional temporary iOS App
  Review fallback is compiled only by the local iOS build script, never written
  to local JSON, and never displayed in the app.
- Standalone-browser keys are never written to Drive. localStorage is not a
  secret vault, so this mode should be used only on trusted devices and served
  from the reviewed GitHub Pages origin.

See [standalone web and Google Drive setup](docs/google-drive-web.md).

## Architecture

- `flutter/lib/core/`: provider contracts, pricing, models, gateways, and storage
- `flutter/lib/app/`: application state and composition
- `flutter/lib/ui/`: shared responsive screens and widgets
- `flutter/tool/clawnsole_companion.dart`: loopback web/API/media companion
- `electron/`: macOS shell, packaging, checksum-verified GitHub updater
- `flutter/windows/`: native Windows runner and product metadata
- `.github/workflows/`: PR checks plus parallel macOS and Windows releases

## Releases and desktop updates

Merging a PR with exactly one of `major`, `minor`, `patch`, or `no-release`
drives parallel macOS and Windows release builds. macOS is signed and notarized;
Windows is currently distributed as an unsigned x64 ZIP. A manual dispatch can
cut a release without a PR or retry the current synchronized version after a
recoverable failure. iOS builds are intentionally local-only through
`./flutter/scripts/build_ios`; GitHub never receives the iOS signing material or
an IPA.

Packaged Electron builds check GitHub at most once per day and expose
**Clawnsole → Check for Updates…**. An accepted update downloads the architecture
matched ZIP, verifies `SHA256SUMS.txt`, replaces the installed app with rollback,
and reopens it. Windows update checks open the GitHub release for a manual ZIP
download. iOS remains under normal App Store distribution semantics.

See [release setup](docs/releases.md) and [desktop updates](docs/updates.md).

## Privacy and support

Read the [privacy policy](PRIVACY.md), its
[public web version](https://heresalexandria.github.io/clawnsole/privacy/), or use the
[issue tracker](https://github.com/heresalexandria/clawnsole/issues) for support.
Do not post API keys, private prompts, or personal media in a public issue.

## Verification

```bash
cd flutter
dart format --output=none --set-exit-if-changed lib tool test
flutter analyze
flutter test
flutter build web
./scripts/build_github_pages

cd ../electron
npm test
```

Provider contracts and fallback rates follow the official
[BFL documentation](https://docs.bfl.ai/flux_3/flux3_video),
[LTX documentation](https://docs.ltx.io), and
[Atlas Cloud video documentation](https://www.atlascloud.ai/docs/models/video).
Atlas models are refreshed from its public catalog and Create-ready costs use
schema-aware, no-charge request preflight when available. Equivalent model
routes retain provider-specific IDs while sharing a canonical comparison ID.
