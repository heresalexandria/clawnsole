# Standalone web and Google Drive

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

Access tokens are kept in memory and expire. Reconnect from Settings when
Google asks for authorization again. No refresh token or backend is used.

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
