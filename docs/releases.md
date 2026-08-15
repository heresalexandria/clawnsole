# Cutting a release

Clawnsole follows the same release shape as Aesthetician: a release decision is
made on the PR, the shared app version is bumped once, and the tag is created
only after the signed macOS artifacts exist.

```text
PR labelled minor -> merge -> bump Flutter and Electron together
                              -> build macOS DMG + updater ZIP
                              -> checksum -> publish GitHub release
```

## Release labels

Every PR needs exactly one:

| label | result |
|---|---|
| `major` | bump the first semantic version component and release |
| `minor` | bump the second component and release |
| `patch` | bump the third component and release |
| `no-release` | merge without changing versions or publishing |

The labels are created in repository setup and can be repaired at any time by
running **Create release labels** from the Actions page. The Pull request
workflow enforces the decision. A manual **Release** dispatch accepts the bump
kind directly and is useful for the first release. Select `current` to rebuild
and publish the already-synchronized version after a recoverable CI or signing
failure, without creating another version bump.

## Required repository setup

Enable **Read and write permissions** under Settings → Actions → General. The
workflow commits the synchronized version bump to `main`, so branch protection
must allow `github-actions[bot]` to make that commit.

iOS is intentionally local-only. GitHub Actions never receives an iOS signing
certificate or provisioning profile and never builds, stores, or publishes an
IPA. Use `./flutter/scripts/build_ios` on a configured Mac when an iOS archive is
needed.

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

GitHub releases contain only the notarized macOS application and its updater
metadata. Release assets can include:

- `Clawnsole-<version>-mac-arm64.dmg`
- `Clawnsole-mac-arm64.dmg` (stable alias used by the README's latest-download link)
- `Clawnsole-<version>-mac-arm64.zip`
- `SHA256SUMS.txt`

The ZIP is the Electron updater asset. Artifact naming, architecture selection,
and digest parsing are covered by Electron tests. iOS, Android, and hosted web
distribution remain outside this workflow.
