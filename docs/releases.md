# Cutting a release

Clawnsole follows the same release shape as Aesthetician: a release decision is
made on the PR, the version is bumped once, target builds run independently, and
the tag is created only after every required artifact exists.

```text
PR labelled minor -> merge -> bump Flutter and Electron together
                              |-> build signed iOS IPA
                              |-> build macOS DMG + updater ZIP
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

Run **Create release labels** once from the Actions page. The Pull request
workflow enforces the decision. A manual **Release** dispatch accepts the bump
kind directly and is useful for the first release. Manual dispatches can target
macOS only while iOS signing is being provisioned; labelled PR releases continue
to require and build both platforms in parallel.

## Required repository setup

Enable **Read and write permissions** under Settings → Actions → General. The
workflow commits the synchronized version bump to `main`, so branch protection
must allow `github-actions[bot]` to make that commit.

The signed iOS job requires base64-encoded certificate/profile data:

| secret | value |
|---|---|
| `IOS_CERTIFICATE_P12` | App Store distribution certificate `.p12`, base64 encoded |
| `IOS_CERTIFICATE_PASSWORD` | password for that `.p12` |
| `IOS_PROVISIONING_PROFILE` | App Store `.mobileprovision`, base64 encoded |
| `IOS_TEAM_ID` | Apple Developer team ID |

The profile must cover `app.clawnsole.clawnsole`. The workflow imports it into a
temporary keychain, exports a signed IPA, then deletes the keychain.

Uploading that IPA to App Store Connect requires a scoped API key:

| secret | value |
|---|---|
| `APP_STORE_CONNECT_KEY_ID` | App Store Connect API key ID |
| `APP_STORE_CONNECT_ISSUER_ID` | API issuer UUID |
| `APP_STORE_CONNECT_API_KEY_P8` | `AuthKey_*.p8`, base64 encoded |

The release job uploads the build to App Store Connect. Processing, TestFlight
selection, review submission, and public App Store release remain Apple-side
approval steps.

macOS signing is optional so the pipeline can cut an initial release like
Aesthetician does. Add these secrets when Developer ID distribution is ready:

| secret | value |
|---|---|
| `MACOS_CERTIFICATE_P12` | Electron Builder-compatible base64 `.p12` |
| `MACOS_CERTIFICATE_PASSWORD` | certificate password |
| `APPLE_ID` | notarization Apple ID |
| `APPLE_APP_SPECIFIC_PASSWORD` | notarization app password |
| `APPLE_TEAM_ID` | Apple team ID |

Without the macOS certificate, the release is unsigned and GitHub Actions emits
a warning. The checksum-verified in-app updater still works, but the first manual
download can trigger Gatekeeper.

## What is published

For a full release, the iOS and macOS jobs depend only on `prepare`, so they
build in parallel on separate `macos-15` runners and `publish` waits for both.
A macOS-only manual release skips iOS and publishes after the desktop build.
Release assets can include:

- `Clawnsole-<version>-ios.ipa`
- `Clawnsole-<version>-mac-arm64.dmg`
- `Clawnsole-mac-arm64.dmg` (stable alias used by the README's latest-download link)
- `Clawnsole-<version>-mac-arm64.zip`
- `SHA256SUMS.txt`

The ZIP is the Electron updater asset. Artifact naming, architecture selection,
and digest parsing are covered by Electron tests. Android and hosted web jobs can
be added to this fan-out later.

The same IPA is attached to the GitHub release for build provenance after App
Store Connect accepts the upload.
