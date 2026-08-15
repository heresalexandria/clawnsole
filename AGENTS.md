# Clawnsole engineering guide

These instructions apply to the whole repository.

## Supported surfaces

Clawnsole is one Flutter product delivered through four targets:

- `flutter/`: the canonical UI, provider contracts, pricing, persistence, and
  platform gateways for web, iOS, and Android.
- `electron/`: a thin macOS shell around the compiled Flutter web app and Dart
  companion. It owns desktop lifecycle, packaging, and self-update only.

Flutter web, iOS, Android, and Electron macOS are supported. Treat functional
changes as cross-platform by default. A platform exception must be required by
the platform and documented in the change.

The retired root Next.js application must not be reintroduced. The canonical
desktop entry points live beside the other Flutter scripts:

```bash
./flutter/scripts/start_macos
./flutter/scripts/build_macos
```

## Architecture and reuse

- Define provider-neutral capabilities, request/response contracts, pricing,
  generation state, and persistence semantics before changing presentation.
- Keep reusable product logic and interfaces in `flutter/lib/core/`. Flutter
  composition belongs in `flutter/lib/app/`, reusable widgets/screens belong in
  `flutter/lib/ui/`, and HTTP/filesystem behavior stays behind gateways and
  data-store interfaces.
- Do not duplicate Flutter behavior in Electron. Electron may own app lifecycle,
  secure native integrations, update checks, and packaging. Its renderer is the
  Flutter web build and its local server is `flutter/tool/clawnsole_companion.dart`.
- Extend provider registries and adapters instead of branching product screens
  by provider. Provider-specific behavior belongs behind the provider boundary.
- Keep API keys and privileged provider calls out of web renderers. Keep history
  JSON compact: never embed uploaded frames, video blobs, base64 payloads, or
  short-lived secrets. Durable media belongs in the adjacent asset store behind
  small references and reference-aware cleanup.
- Prefer small modules with one ownership boundary over catch-all utility files.

## Functional-change checklist

1. Identify the affected contract: capabilities, request mapping, pricing,
   polling, persistence, media delivery, or UI state.
2. Update canonical Flutter core and gateway modules before presentation code.
3. Verify native Flutter and companion-backed web behavior. Electron should
   inherit product behavior from the Flutter web build.
4. Preserve existing local data where schemas change. Use explicit schema
   versions and migrations rather than discarding records.
5. Update documentation and start/build scripts when runtime assumptions change.

## Release contract

- Electron and Flutter versions must remain aligned. Use
  `scripts/release/bump_version.py`; do not bump one package independently.
- macOS updater asset names, GitHub Actions output names, and Electron Builder's
  `artifactName` form one tested contract.
- Published macOS bundles must be Developer ID signed, notarized, stapled, and
  pass Gatekeeper plus strict signature verification before upload.
- Every published release must contain `SHA256SUMS.txt`. The desktop updater
  refuses unverified downloads.
- `.github/workflows/release.yml` publishes only signed, notarized macOS builds.
  iOS distribution builds and signing material stay local to a configured Mac.
  Android and hosted web release jobs can be added later without changing
  product code.

## Verification

Run checks proportionate to the change, including all affected platform families:

```bash
cd flutter
dart format --output=none --set-exit-if-changed lib tool test
flutter analyze
flutter test
flutter build web

cd ../electron
npm test
```

For lifecycle or packaging changes, also exercise
`flutter/scripts/start_macos` and `flutter/scripts/build_macos`. For native
Flutter changes, run the matching simulator script and a debug or release build.

Do not edit or commit generated output such as `electron/dist/`,
`flutter/build/`, native dependency caches, or local Clawnsole data files.
