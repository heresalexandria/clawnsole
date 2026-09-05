# Google Drive and encrypted settings sync

Clawnsole can connect the same app-owned Drive folder from Electron macOS,
native Windows, iOS, and Android. The installed apps keep a local library and
show Local and Drive items together with explicit provenance and filters.

The public, standalone browser app has been retired because provider APIs do
not consistently allow browser CORS. Flutter web remains an internal renderer:
Electron packages it with the loopback Dart companion, and `start_web` remains
available as a local development harness. This does not change or remove the
existing `docs/` website, splash page, privacy policy, or terms.

## Drive files

Clawnsole creates an app-marked folder using the narrow
`https://www.googleapis.com/auth/drive.file` scope. It can manage files it
created, not unrelated files elsewhere in the account.

- `clawnsole.json` contains portable generations, references, folders, tags,
  Create tabs, aesthetic references, and compact asset references. It never contains provider credentials or
  preferences.
- `assets/` contains retained Drive media.
- `clawnsole-vault.json` contains provider credentials and preferences only as
  an authenticated encrypted envelope.

The settings vault uses a random data-encryption key and XChaCha20-Poly1305.
A one-time sync passphrase on each new device derives the key that unlocks that
random key; neither the passphrase nor a verifier is stored. A recovery code is
shown once during setup. The unlocked vault key is cached only in platform
secure storage: iOS Keychain, Windows secure storage, or Electron `safeStorage`
on macOS. Changing the passphrase does not invalidate already unlocked devices.

Disconnecting Drive leaves local credentials and the encrypted Drive files in
place. **Forget cached unlock** removes only that device's remembered vault key.

## Create workspace sync

Connect every device to the same Clawnsole Drive folder to share open Create
tabs and the aesthetic library. Draft text, titles, settings, screenplay casting,
aesthetic selection, and retained attachment layouts survive relaunch. Writes
save locally first; Drive publication runs in the background. Reconciliation
runs at startup, on return to the foreground, during the periodic Drive refresh,
and through the explicit Refresh control. Offline edits publish on reconnect.

Tabs merge independently by stable id and modification time. Concurrent edits
to different tabs survive together; for edits to the same tab, the latest
modification wins (equal timestamps use a deterministic tie-break). Explicit
close/delete tombstones prevent stale devices from resurrecting removed tabs
or aesthetics. Closing a tab closes it across devices; selecting a tab does not
change the tab currently selected on another device.

Composer schema 4 adds these fields without discarding older drafts. Attachment
records contain asset references, never media bytes or base64. Drive-backed
media is accessible on other devices; device-local media still belongs to its
original device. Move or copy that media to Drive when it needs to travel.

Aesthetic references are text-only library entries managed under References.
Choose a title, one of 16 SVG icons, a color, and the reference text. The Aesthetic
menu immediately to the right of Characters selects one per Create tab, or
**No aesthetic**. Generation requests append only the reference text after the
editable prompt, including in Screenplay mode; the title and icon are never
sent as prompt content. Prompt limits and estimates use the composed prompt.
Editing an aesthetic updates selected tabs; deleting it removes its effect.
Aesthetics do not consume media-reference slots or appear in media pickers.

## Google Cloud setup

1. Create or select a Google Cloud project and enable the Google Drive API.
2. Configure the OAuth consent screen for `Clawnsole`, using
   `https://clawnsole.app/`, `https://clawnsole.app/privacy/`, and
   `https://clawnsole.app/tos/`.
3. Configure the installed-app clients:
   - **macOS Electron and Windows:** a Desktop app client exposed as
     `CLAWNSOLE_GOOGLE_DESKTOP_CLIENT_ID`. The optional installed-app client
     secret may be supplied as `CLAWNSOLE_GOOGLE_DESKTOP_CLIENT_SECRET`.
   - **iOS:** register bundle ID `app.clawnsole.clawnsole`, create an iOS client,
     and set `CLAWNSOLE_GOOGLE_IOS_CLIENT_ID`.
   - **Android:** register `app.clawnsole.clawnsole` and signing SHA
     fingerprints, then set the matching web client ID as
     `CLAWNSOLE_GOOGLE_ANDROID_SERVER_CLIENT_ID`.

macOS and Windows use system-browser OAuth with a loopback redirect and PKCE.
The mobile Google SDK manages its native session. The macOS refresh token is
encrypted with Electron `safeStorage`; Windows uses OS-backed secure storage.

For release workflows, configure `GOOGLE_DESKTOP_OAUTH_CLIENT_ID` and, only
when required, `GOOGLE_DESKTOP_OAUTH_CLIENT_SECRET`. iOS signing and its OAuth
configuration remain local to the release Mac.

## Internal renderer development

Use the companion-backed target only for local development:

```bash
./flutter/scripts/start_web
./flutter/scripts/build_web
```

The browser renderer never receives saved provider keys or the cached vault
key. In Electron, the shell authenticates each renderer request to the local
companion with a per-launch token. Privileged provider and vault operations
remain in the companion/native boundary.
