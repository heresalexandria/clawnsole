# Cutting a release

Clawnsole makes the release decision on the PR, bumps the shared app version
once, and builds every required target from that exact release commit. The tag
is created only after both desktop builds exist and App Store Connect accepts
the iOS upload.

```text
PR labelled minor -> merge -> bump Flutter and Electron together
                              |-> advance /models catalog_version
                              `-> dispatch exact commit from main
                                  |-> build signed iOS IPA -> upload to App Store Connect
                                  |-> build macOS DMG + updater ZIP ─┐
                                  |-> build Windows x64 ZIP ─────────┤
                                  `-> checksum -> publish desktop GitHub release
```

## Parallel merges

Merges do not need to wait for each other or for running releases. The
workflow guarantees, in every interleaving, that the newest release wins and
the iOS bundle version only moves forward:

- The prepare run decides against the merge commit's first parent — main
  immediately before that merge — never a stale snapshot of the pull request's
  base, so releases cut while a PR was open are counted correctly.
- The push of the `Release vX.Y.Z` commit to `main` is the lock. A prepare run
  that loses the race re-reads `main` and recomputes; if a release prepared
  after its merge has already landed (which necessarily contains that merge),
  it stands down green and lets the newer release ship alone.
- The trusted build run re-checks that its prepared commit still carries
  `main`'s newest version before building. A superseded or re-run stale
  dispatch skips instead of rebuilding an old bundle version.
- A newer release cancels a superseded release's still-running macOS, Windows,
  and iOS builds. Publishing is serialized, never cancelled, so a release is
  not torn down half-published.
- Uploading a build number App Store Connect has already accepted (the exact
  same number) is treated as already-complete with a warning — re-runs after a
  desktop failure and locally uploaded prepared builds do not fail the
  release. A *lower* build number still fails: that run is stale.

A `no-release` merge never cancels or displaces a running release.

## Release labels

Every PR needs exactly one:

| label | result |
|---|---|
| `major` | bump the first semantic version component and release |
| `minor` | bump the second component and release |
| `patch` | bump the third component and release |
| `no-release` | merge without changing versions or publishing |

`mobile-test` is an optional, non-impact label used in addition to exactly one
row above. It marks the new release version in `/models` `test_versions` and
builds the mobile review profile: ArtCraft Seedance 1.5 Pro, 480p, 5 seconds,
plus keyless Apple Intelligence image and image-sequence generation on
supported iOS devices. Android exposes only the ArtCraft route. It does not
affect the synchronized macOS or Windows build of that release.

The labels are created in repository setup and can be repaired at any time by
running **Create release labels** from the Actions page. The Pull request
workflow enforces the decision. A manual **Release** dispatch accepts the bump
kind directly and is useful for the first release. Select `current` to rebuild
and publish the already-synchronized version after a recoverable CI or signing
failure, without creating another version bump. Manual dispatches include iOS
by default, and a rebuild whose exact build number was already accepted by
Apple uploads nothing and continues, so leaving iOS enabled on a retry is
safe; clear **Build and upload iOS to App Store Connect** only to skip the
iOS build entirely.

## Required repository setup

Enable **Read and write permissions** under Settings → Actions → General. The
workflow commits the synchronized version bump to `main`, so branch protection
must allow `github-actions[bot]` to make that commit.

GitHub Pages must publish the repository's `docs/` directory for the custom
`clawnsole.app` domain. The public `CLAWNSOLE_SITE_URL` workflow environment
value is compiled into every target, and `/models/` must serve
`docs/models/index.html` plus its referenced provider and model manifests. It
is configuration rather than a secret. The synchronized version written by
`scripts/release/bump_version.py` is also the version used for catalog
availability checks; no separate version environment variable is needed.

iOS releases run on GitHub's `macos-26` image so the archive uses Xcode 26 and
the iOS 26 SDK required by App Store Connect. Create a GitHub environment named
`app-store-connect`, allow deployments from `main`, and configure these as
environment secrets. Do not add a required reviewer if uploads should remain
fully automatic; GitHub does not allocate the macOS runner until any environment
protection rules are satisfied.

GitHub reports a workflow started by a merged pull request as
`refs/pull/<number>/merge`, even when a job checks out a commit from `main`.
The merge-triggered run therefore prepares the version and dispatches a second
run whose workflow ref is `main`. That trusted run verifies the supplied commit
is in `main` before using it, then starts macOS, Windows, and iOS together. This
keeps the App Store Connect environment restricted to `main` without exposing
its secrets to pull-request refs.

| secret | value |
|---|---|
| `IOS_CERTIFICATE_P12` | Apple Distribution certificate and private key (`.p12`), base64 encoded |
| `IOS_CERTIFICATE_PASSWORD` | password for the iOS `.p12` |
| `IOS_PROVISIONING_PROFILE` | App Store distribution profile for `app.clawnsole.clawnsole`, base64 encoded |
| `GOOGLE_IOS_OAUTH_CLIENT_ID` | Google OAuth iOS client ID compiled into the production build |
| `ARTCRAFT_TEST_KEY` | ArtCraft credential compiled only when the source PR has `mobile-test`; runtime use is gated by `/models` `test_versions` |
| `APP_STORE_CONNECT_KEY_ID` | App Store Connect team API key ID |
| `APP_STORE_CONNECT_ISSUER_ID` | App Store Connect API issuer UUID |
| `APP_STORE_CONNECT_API_KEY_P8` | raw contents of the API key's downloaded `AuthKey_*.p8` file |

The existing `APPLE_TEAM_ID` secret is shared by macOS notarization and iOS
signing and must remain `KMZ785G889`. Generate the App Store Connect team API key
with the `Developer` role, which is sufficient to upload builds without giving
the workflow an Account Holder or Admin key. Apple permits downloading the P8
private key only once, so retain a separate secure backup.

The workflow decodes the certificate and profile into runner-temporary files,
imports the private key into a randomly protected temporary keychain, validates
the team, bundle ID, distribution profile, signed IPA, semantic version, and
build number, then uploads with Apple's `altool`. The P8 key is exposed only to
the upload step. Cleanup removes the keychain, profile, P8, and IPA even after a
failure; the hosted runner is then discarded.

The IPA is never sent to `actions/upload-artifact` and never becomes a GitHub
Release asset. `altool` waits only for the transfer and Apple's immediate upload
acceptance. App Store processing, TestFlight availability, review submission,
and public release remain asynchronous Apple-side operations and are not polled,
so no runner minutes are spent waiting for them.

For a `mobile-test` release, the workflow passes the shared ArtCraft credential
only to the IPA build step. The key is not persisted into Clawnsole's data or
shown in provider settings. Removing the release version from `/models`
`test_versions` disables the compiled credential after the next successful
catalog refresh; users must then configure their own provider keys. The signed
Android build script implements the identical define contract, although
Android distribution remains outside this workflow.

For a local fallback, sync the workflow-created release commit and run
`./scripts/build_ios.sh` from the repository root. Do not build the pre-bump
merged feature commit: its marketing version would not match the GitHub release.

Published macOS builds must be Developer ID signed. Configure:

| secret | value |
|---|---|
| `MACOS_CERTIFICATE_P12` | Electron Builder-compatible base64 `.p12` |
| `MACOS_CERTIFICATE_PASSWORD` | certificate password |
| `APPLE_ID` | notarization Apple ID |
| `APPLE_APP_SPECIFIC_PASSWORD` | notarization app password |
| `APPLE_TEAM_ID` | Apple team ID |

All five secrets are required. CI performs strict bundle verification, confirms
the `KMZ785G889` Team ID, notarizes the app, and requires Gatekeeper and stapler
verification before it uploads any desktop artifact.

## What is published

GitHub releases contain the notarized macOS application, its updater metadata,
and the unsigned native Windows x64 build. Release assets can include:

- `Clawnsole-<version>-mac-arm64.dmg`
- `Clawnsole-mac-arm64.dmg` (stable alias used by the README's latest-download link)
- `Clawnsole-<version>-mac-arm64.zip`
- `Clawnsole-<version>-windows-x64.zip`
- `Clawnsole-windows-x64.zip` (stable alias used by latest-download links)
- `SHA256SUMS.txt`

The macOS ZIP is the Electron updater asset. Windows updates remain a manual ZIP
download, and the unsigned executable may trigger a Microsoft Defender
SmartScreen warning. Artifact naming, architecture selection, and digest parsing
are covered by Electron tests. The iOS binary is delivered privately to App
Store Connect, not published on GitHub. Android distribution remains outside
this workflow.
