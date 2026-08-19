# Google Drive and standalone web

Clawnsole can connect the same app-owned Drive folder from native Windows,
Electron macOS, iOS, Android, and the standalone browser build. Native and
companion-backed surfaces keep their local library too: the UI shows Local and
Drive items together with explicit badges and filters, and a non-destructive,
idempotent copy action can fold selected or all local work into Drive.

Clawnsole has two deliberately separate web targets:

- `./flutter/scripts/start_web` and `build_web` use the local Dart companion.
- `./flutter/scripts/start_github_pages` and `build_github_pages` call video
  providers directly and use a user-authorized Google Drive folder for all
  portable history and media.

The standalone target writes `clawnsole.json` and an `assets/` folder inside a
Drive folder created by Clawnsole. Generated videos, retained generation
inputs, saved references, folders, tags, and non-secret preferences are
portable. Provider API keys are intentionally excluded from Drive and remain
in that browser's localStorage. This avoids exposing paid provider credentials
when a Drive folder is shared, but each browser/device must enter its own keys.

## Google Cloud setup

1. Create or select a Google Cloud project.
2. Enable the Google Drive API.
3. Configure the OAuth consent screen.
4. Create an OAuth 2.0 client with application type **Web application**.
5. Add every development and hosted origin, for example
   `http://localhost:7357` and `https://heresalexandria.github.io`.
6. Export its public client ID before starting or building:

   ```bash
   export CLAWNSOLE_GOOGLE_CLIENT_ID='…apps.googleusercontent.com'
   ./flutter/scripts/start_github_pages
   ```

The app requests only `https://www.googleapis.com/auth/drive.file`. It can see
and manage files that Clawnsole created, not the rest of the user's Drive. A
folder is reopened by its user-selected name and the Clawnsole app marker, so
the same Google account can connect to it from another browser. After Clawnsole
creates the folder, it can be moved anywhere in Drive without breaking sync.

Provider API keys and iOS App Review credentials are never serialized into the
portable file. They stay on each device. Storing paid API keys in Drive is
intentionally unsupported: shared folders, Drive exports, and account access
would otherwise broaden who can recover them.

## Native OAuth clients

- **macOS Electron and Windows:** create a Desktop app OAuth client and set
  `CLAWNSOLE_GOOGLE_DESKTOP_CLIENT_ID`. The client secret is optional and can
  be supplied as `CLAWNSOLE_GOOGLE_DESKTOP_CLIENT_SECRET`; installed-app
  secrets are not treated as confidential. Both use system-browser OAuth with
  a loopback redirect and PKCE. macOS encrypts the refresh token with Electron
  `safeStorage`; Windows uses operating-system-backed secure storage.
- **Android:** register `app.clawnsole.clawnsole` and the SHA fingerprints
  for each signing configuration, create a Web application client in the same
  project, and set its ID as
  `CLAWNSOLE_GOOGLE_ANDROID_SERVER_CLIENT_ID`.
- **iOS:** register Clawnsole's bundle ID, create an iOS client, and set
  `CLAWNSOLE_GOOGLE_IOS_CLIENT_ID`. `start_ios` and `build_ios` derive the
  reversed callback scheme into an ignored, temporary Xcode configuration.

The mobile Google SDK manages its own sign-in session. Desktop refresh tokens
are revocable and remain encrypted on the device. Disconnect revokes/forgets
the local grant but leaves the Drive folder and its contents intact.

For workflow-packaged desktop artifacts, configure repository secrets
`GOOGLE_DESKTOP_OAUTH_CLIENT_ID` and (when required)
`GOOGLE_DESKTOP_OAUTH_CLIENT_SECRET`. Builds remain valid without them, but the
Drive control explains that OAuth is unavailable.

## GitHub Pages build

```bash
CLAWNSOLE_GOOGLE_CLIENT_ID='…apps.googleusercontent.com' \
  CLAWNSOLE_WEB_BASE_HREF='/clawnsole/app/' \
  ./flutter/scripts/build_github_pages
```

The output is `flutter/build/github-pages/app/`. Flutter PR checks build the
same directory and upload it as a test artifact, and the manual standalone-web
workflow can produce the artifact on demand. Neither path deploys or replaces
the existing `docs/` splash page. Add a repository secret named
`GOOGLE_OAUTH_CLIENT_ID` to make Drive available in workflow-built artifacts.

Direct provider calls depend on each provider allowing browser CORS for its API
and delivery hosts. A preflight check from the intended Pages origin on August
19, 2026 found that Atlas Cloud allows it; BFL and ArtCraft reject it, and LTX
does not return the required allow-origin header. The standalone build therefore
exposes Atlas Cloud only for now. Native and companion-backed builds continue to
offer all supported providers. Recheck these policies before enabling another
provider in `BrowserDriveGateway`.
