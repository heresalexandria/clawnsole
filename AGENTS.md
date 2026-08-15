# Clawnsole engineering guide

These instructions apply to the whole repository.

## Supported surfaces

Clawnsole is one product delivered through three runtime families:

- `app/` and `lib/`: the canonical Next.js web/local implementation and server APIs.
- `electron/`: a thin macOS lifecycle and security shell that packages the canonical Next.js app.
- `flutter/`: the Flutter client plus local companion for web, iOS, and Android.

Web, macOS desktop, Flutter web, iOS, and Android are supported platforms. Treat a
functional change as cross-platform by default. A platform-specific exception must
be required by the platform, documented in the change, and must not silently alter
the product contract.

## Architecture and reuse

- Define provider-neutral capabilities, request/response contracts, pricing,
  generation state, and persistence semantics before changing a platform UI.
- Keep reusable TypeScript product logic in `lib/`; UI composition belongs in
  `app/`, and server-only provider/filesystem adapters belong in `lib/server/`.
- Keep reusable Dart product logic and interfaces in `flutter/lib/core/`; Flutter
  composition belongs in `flutter/lib/app/`, reusable widgets/screens belong in
  `flutter/lib/ui/`, and HTTP/filesystem behavior stays behind the gateway and
  data-store interfaces (or narrowly scoped platform host directories).
- Do not duplicate Next.js behavior in Electron. Electron may own app lifecycle,
  packaging, native integrations, and narrowly scoped secure IPC only. It must load
  or package the canonical Next.js renderer and server.
- TypeScript and Dart cannot share runtime code. Keep their wire formats and
  provider semantics structurally identical, use the same field names where
  practical, and add matching contract/fixture tests whenever either side changes.
- Extend provider registries/adapters instead of branching product screens by
  provider. Provider-specific behavior belongs behind the provider interface.
- Keep API keys and privileged provider calls out of browser/Electron renderers.
  Keep history JSON compact: never embed uploaded frames, video blobs, base64
  payloads, or short-lived secrets. Durable media belongs in the platform's
  adjacent asset store behind small references and reference-aware cleanup.
- Prefer small modules with one ownership boundary over catch-all utility files.
  Do not extract an abstraction until it has a stable contract or real reuse.

## Functional-change checklist

For every user-visible or provider-facing change:

1. Identify the affected product contract: capabilities, request mapping, pricing,
   polling, persistence, media delivery, or UI state.
2. Update the canonical reusable modules before platform presentation code.
3. Apply and test the behavior in Next.js and Flutter. Electron should inherit the
   Next.js change; add Electron code only for a genuine desktop/native boundary.
4. Preserve existing local data where schemas change. Use explicit schema versions
   and migrations rather than silently discarding records.
5. Update relevant documentation and start/build scripts when runtime assumptions
   or required tooling changes.

## Verification

Run checks proportionate to the change, including all affected platform families:

```bash
npm test
npm run lint
npm run typecheck
npm run build
npm --prefix electron test

cd flutter
flutter analyze
flutter test
flutter build web
```

For lifecycle or packaging changes, also exercise `electron/scripts/start_macos`
and `electron/scripts/build_macos`. For native Flutter changes, run the matching
simulator/start script and at least a debug or release build for that platform.

Do not edit or commit generated output such as `.next/`, `electron/dist/`,
`flutter/build/`, native dependency caches, or local Clawnsole data files.
