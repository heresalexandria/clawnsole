<p align="center">
  <img src="icon.png" alt="Clawnsole icon" width="96" height="96">
</p>

<h1 align="center">Clawnsole</h1>

<p align="center"><em>One AI video studio, across providers and devices</em></p>

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

Clawnsole is a unified Flutter workspace for generating AI video across
providers and devices. Its premium, midcentury-inspired interface includes
skeuomorphic console hardware: a machined-steel duration knob, metal toggles
that light hunter green, and recessed counter readouts, all drawn in code so
every platform matches. Cloud video providers share one provider-neutral
Create, Library, and References workflow, while project folders, reusable tags,
and optional Google Drive sync keep work organized wherever you create.

## iPhone

<p align="center">
  <img src="docs/app-store/iphone/01-create.png" alt="Create an AI video in Clawnsole on iPhone" width="31%">
  <img src="docs/app-store/iphone/02-providers.png" alt="Choose providers and compare model costs in Clawnsole on iPhone" width="31%">
  <img src="docs/app-store/iphone/03-library.png" alt="Browse the local film library in Clawnsole on iPhone" width="31%">
</p>

## What it does

- Provider-aware text-to-video and image-to-video, plus FLUX 3 continuation,
  draft enhancement, and FLUX Video Upscale finishing at 1.5×–3×
- Keyless Apple Intelligence still-image creation on supported iPhones and
  iPads, plus silent MP4 sequences built from one generated image per second
- Model-aware image, video, and audio references, with timing and placement controls where supported
- Model-specific durations, aspect ratios, resolutions, audio, draft, and safety controls
- App-wide polling, foreground/relaunch recovery, manual status refresh,
  surfaced provider and result-retrieval errors, and progress
- Provider balance when exposed by the API, plus setting-aware USD or credit estimates
- Per-generation quoted and realized USD cost history with provenance
- Reload-safe input previews, fullscreen playback, save-as download, and full input reuse
- Composer tabs on Create: several independent drafts (direction, model,
  settings, attachments) open side by side, persisted on the device
- AI Rewrite: a finished film's frames, prompt, and your change notes go to
  the OpenAI or Anthropic model you pick (vendor, model, effort) and the
  revised prompt opens in a new tab with the film's full recipe; a wand on
  the Direction box rewrites a draft in place with Undo. Keys are asked for
  on first use, kept in the encrypted vault, and synced with your other keys
- Named tabs and rewrite lineage on every card, and a film modal (tap any
  card) that shows the whole recipe untruncated with an iterations strip to
  walk back through AI Rewrite versions
- Nested project folders with a pinned rail, collapsible branches, in-place
  rename, and drag-and-drop filing, plus multi-tag organization and combined
  prompt/tag/folder search
- A saved References tab with naming, nested folders, tags, media-type filters,
  duration-aware sorting, non-destructive video trimming, and Saved/Generated
  pickers directly in Create
- Live reference-count and media-duration gauges that track each selected
  model's per-kind and total input ceilings
- One-tap folder, media-type, and tag filters with a desktop folder rail and compact mobile picker
- Starred models and providers pinned in a Favorites section of the model
  picker and the provider desk, carried with your synced preferences
- System-aware light and dark themes with an explicit appearance switcher
- Uncapped compact history with retained media files and granular clear controls
- OS-secure API-key storage with no database, `localStorage`, or IndexedDB
  history in installed builds
- Optional Google Drive history/media sync across macOS, Windows, iOS, and
  Android, plus passphrase-encrypted provider-key and preference sync with a
  one-time recovery code
- A Providers desk for per-provider keys, console/docs links, live Atlas Cloud,
  Krea, and Runway model discovery, canonical cross-provider model matching,
  observed quote variance, and route-aware 10/15/20/30-second USD comparisons
- A remotely managed, version-aware provider/model catalog from
  `https://clawnsole.app/models/`, with a durable device cache and complete
  build-time fallback when the site is unavailable
- A version-gated `mobile-test` profile that limits store review builds to
  ArtCraft Seedance 1.5 Pro at 480p for 5 seconds plus Apple Intelligence on
  supported iOS devices, then unlocks the other catalog routes remotely

## One studio, every screen

The same Clawnsole workflow runs on iOS, Android, macOS, and Windows.
Flutter owns all product behavior, including the native Windows app. Electron
is only the macOS lifecycle and self-update shell around Flutter's web build and
local Dart companion. Flutter web remains the internal Electron renderer and a
local development harness; the standalone hosted app has been retired. The old
root Next.js implementation has also been removed.

```bash
# from the repository root
./flutter/scripts/start_ios
./flutter/scripts/start_android
./flutter/scripts/start_macos
./flutter/scripts/start_windows

# internal companion-backed renderer development
./flutter/scripts/start_web
```

The matching deployable builds are:

```bash
./scripts/build_ios.sh
./flutter/scripts/build_android
./flutter/scripts/build_macos
./flutter/scripts/build_windows

# internal Electron renderer/companion build
./flutter/scripts/build_web
```

See [Flutter setup](flutter/README.md) and [macOS desktop packaging](electron/README.md).
Windows scripts run on Windows with Visual Studio and its Desktop development
with C++ workload installed.

## Persistence

Clawnsole has no database. Native mobile apps store `clawnsole.json` inside
their application sandbox; native Windows stores it in
`%LOCALAPPDATA%\Clawnsole` (a library that already lives in
`Documents\Clawnsole` keeps being used). Electron's companion stores the same
compact schema in a local file, with retained inputs and videos in an adjacent
`assets/` directory. Every write replaces the file atomically and keeps the
previous copy beside it as `clawnsole.json.bak`, which is read back
automatically if the main file is ever missing or damaged. Desktop installs can
move the data directory from Settings for portable use: a small
`data-location.json` pointer stays in the default location and names the
chosen folder, and the previous copy is kept as a safety net. All installed targets can additionally connect to the same
app-owned Google Drive folder. Local and Drive generations, references, and
folders remain separate records with visible provenance; copying local work to
Drive is non-destructive, and the separate move action deletes local originals
only after every copy is verified in Drive.

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
- Provider task receipts are persisted as soon as submission succeeds, before
  optional balance and cost refreshes. Polling resumes on launch and foreground
  resume regardless of the visible screen.
- Provider delivery links may be temporary; completed videos are retained
  locally first, and interrupted result downloads remain durably retryable.
- User-supplied provider keys live in OS-secure storage, never in
  `clawnsole.json`, and are uploaded only inside the passphrase-encrypted
  settings vault. They are never returned to the Electron renderer. An optional temporary iOS App
  Review fallback is compiled only by the local iOS build script, never written
  to local JSON, and never displayed in the app.

See [Google Drive and encrypted settings sync](docs/google-drive-web.md).

## Architecture

- `flutter/lib/core/`: provider contracts, pricing, models, gateways, and storage
- `docs/models/`: discrete GitHub Pages provider/model YAML manifests
- `flutter/lib/app/`: application state and composition
- `flutter/lib/ui/`: shared responsive screens and widgets
- `flutter/tool/clawnsole_companion.dart`: loopback web/API/media companion
- `electron/`: macOS shell, packaging, checksum-verified GitHub updater
- `flutter/windows/`: native Windows runner and product metadata
- `.github/workflows/`: PR checks plus parallel iOS, macOS, and Windows releases

## Releases and desktop updates

Merging a PR with exactly one of `major`, `minor`, `patch`, or `no-release`
drives parallel iOS, macOS, and Windows release builds from one synchronized
release commit. macOS is signed and notarized; Windows is currently distributed
as an unsigned x64 ZIP. iOS is signed on an ephemeral GitHub-hosted Mac and
uploaded directly to App Store Connect. The IPA is never stored as an Actions
artifact or attached to the GitHub release, and the workflow does not wait for
Apple's asynchronous processing or review. A manual dispatch can cut a release,
retry the current synchronized version, or omit iOS when that exact build is
already present in App Store Connect.

Every surface checks for a newer stable release on startup and every 24 hours
while running. Native iOS reads the version Apple has actually published in the
App Store; the other surfaces read GitHub Releases. Packaged Electron builds
also expose **Clawnsole → Check for Updates…**; an accepted update downloads the
architecture-matched ZIP, verifies `SHA256SUMS.txt`, replaces the installed app
with rollback, and reopens it. Windows updates open the GitHub release for a
manual download, while iOS remains under normal App Store distribution
semantics.

See [release setup](docs/releases.md) and [desktop updates](docs/updates.md).

## Privacy and support

Read the [privacy policy](PRIVACY.md), the [terms of use](TERMS.md), or their
public web versions at [Privacy](https://clawnsole.app/privacy/) and
[Terms](https://clawnsole.app/tos/). Use the
[issue tracker](https://github.com/heresalexandria/clawnsole/issues) for support.
Do not post API keys, private prompts, or personal media in a public issue.

## Verification

```bash
cd flutter
dart format --output=none --set-exit-if-changed lib tool test
flutter analyze
flutter test
flutter build web

cd ../electron
npm test
```

Provider contracts and fallback rates follow the official
[BFL video documentation](https://docs.bfl.ai/flux_3/flux3_video),
[BFL Video Upscale documentation](https://docs.bfl.ai/flux_tools/flux_video_upscale),
[LTX documentation](https://docs.ltx.io), and
[Atlas Cloud video documentation](https://www.atlascloud.ai/docs/models/video),
plus Runway’s [model guide](https://docs.dev.runwayml.com/guides/models/) and
[pricing](https://docs.dev.runwayml.com/guides/pricing/), and
[Krea’s API documentation](https://www.krea.ai/docs/).
Atlas Cloud models are refreshed from its public catalog and Create-ready costs use
schema-aware, no-charge request preflight when available. Runway’s guide is
refreshed for new video model IDs; unfamiliar routes remain comparison-only
until their request shape, limits, and rate are audited. Krea’s create-ready
routes are read from its live OpenAPI spec, with other and legacy routes kept
comparison-only, and its published per-request USD prices are used directly
since Krea bills fixed USD amounts rather than credits. Equivalent routes
retain provider-specific IDs while sharing a canonical comparison ID.

Catalog authoring, version bounds, and adapter compatibility are documented in
[the model manifest guide](docs/models/README.md). Builds read the public
`CLAWNSOLE_SITE_URL` setting from the environment or repository `.env`; the
checked-in `.env.example` and GitHub Actions use `https://clawnsole.app/`.
