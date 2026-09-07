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
  each device's published Create drafts, aesthetic references, and compact
  asset references. It never contains provider credentials or preferences.
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

Connect every device to the same Clawnsole Drive folder to share the aesthetic
library and to reach the drafts open on your other devices. Draft text,
titles, settings, screenplay casting, aesthetic selection, and retained
attachment layouts survive relaunch. Every write saves locally first; the
device's published record reaches Drive in the background, at most once every
twenty seconds while you keep typing and at once when the app leaves the
foreground or a film is submitted.

Open tabs belong to the device that has them open. Each device publishes its
own strip (its tabs, which one is in front, a device name and a save time) as
a record of its own, and a sync only ever *reads* the other devices' records:
nothing arriving from Drive rewrites the tab you are typing in, and a stale
copy echoed back by another device can no longer replace newer local text.
The aesthetic library still merges by id and modification time, with deletion
tombstones so an offline device cannot resurrect a removed aesthetic.

To pick up work from elsewhere, use the **Recover a draft** key beside "+"
on the Create tab rail. It lists the drafts closed on this device and, under
each other device's name and last save time, the drafts open there. Choosing
one opens a *copy* as a new tab here; the other device keeps its own. Opening
the menu quietly refreshes the other devices' records; the periodic Drive
refresh keeps them current the rest of the time. Devices that have not saved
for thirty days drop off the list until they save again.

A Drive file last written by an older build carries one merged strip at the
top level; newer builds read it as the drafts of "Another device (older
version)" so nothing is lost while the other devices update. Closing a tab is
local to the device that closes it.

Composer schema 4 adds these fields without discarding older drafts. Attachment
records contain asset references, never media bytes or base64. Drive-backed
media is accessible on other devices; device-local media still belongs to its
original device. Move or copy that media to Drive when it needs to travel.

Aesthetic references are text-only library entries managed on the **Aesthetics**
tab of the References desk, beside **Media**. Each entry carries a title, one
SVG line icon, a color, comma-separated tags, a star, and the reference text.
The editor keeps the icon out of the way: the current icon sits beside a
**Change icon** action that unfolds a short, scrolling grid grouped by
subject, and twenty-two colour swatches sit underneath. The tab's toolbar filters by All /
Starred, a search across titles, text, and tags, and a Tags popover; rows show
the star and tag pills. The Aesthetic menu immediately to the right of
Characters selects one per Create tab, or **No aesthetic**; it is a searchable
panel that lists starred aesthetics first, stars entries in place, and links
back to the library. Generation requests append only the reference text after
the editable prompt, including in Screenplay mode; the title, icon, and tags
are never sent as prompt content. Prompt limits and estimates use the composed
prompt. Editing an aesthetic updates selected tabs; deleting it removes its
effect. Aesthetics do not consume media-reference slots or appear in media
pickers.

## Generation reconciliation

Every device polls a shared generation independently, so `statusCheckCount` is
a per-device write version, never a cross-device clock — and device clocks
skew. Reconciliation therefore ranks delivery first: a film published to Drive
beats one still staged on the device that made it, which beats a live provider
delivery link, which beats a record with no media. Only an even delivery
contest falls back to `updatedAt`. This ordering governs the Drive merge, the
in-memory acceptance of a poll or retention result, and the per-record fold
that happens when a library read is superseded by a local write while it was
in flight. Delivered media is never traded away: a receipt cannot retract a
result asset, and a record that arrives failed but delivered is treated as
successful everywhere in the UI.

A superseded periodic refresh is folded record by record instead of being
discarded, so a device with work in flight still adopts films finished
elsewhere; records only that device knows about (a card just submitted, a
folder just created) survive the fold untouched.

Media staged for Drive lives on one device until its background upload pass
publishes it. That device never waits on the upload and never downloads its
own film back: the staged original plays and previews from disk, and when the
pass publishes it the original is moved into the Drive media cache under its
new Drive id (a rename, not a copy), so the swapped record keeps playing from
the same bytes. A client that still holds the staged id from a record it read
before the swap is served the published film too; the companion remembers
which staged ids it published for the life of the process. Preview bytes a
card already restored carry over the id swap, so the card never falls back to
a loading placeholder. The pass reads what is pending from the local mirror
(no Drive round trip), remembers uploads across a failed record swap so a
retry never duplicates a file on Drive, keeps retrying cheaply while Drive is
disconnected instead of reporting the queue empty, and re-fetches a ready
result from its provider link when the staged copy has gone missing. Every
pass is logged to the companion log. Background prefetch of the listing never
evicts a full cache; only playback and publishing do.

Until then, other devices see the reference but not the bytes: the companion
serves the record's provider delivery link instead when one is still live,
and otherwise answers 404 with "This film is still uploading from the device
that made it." The player says the same rather than blaming local playback.

### What the storage chip says

A staged asset on a Drive record names a file that exists on exactly one
device, so the chip describes the record from the point of view of the device
drawing it. Each pass reports its own queue — the staged ids this device holds
bytes for, and the ones it found no bytes for, which only their origin device
can publish — and that report is what the chip reads. **Syncing…** means this
device has the upload queued or in flight. **Sync stalled** means this device
holds the bytes but cannot publish them: Drive is disconnected, or the upload
keeps failing; the pump is still retrying with backoff. **Awaiting upload**
means the bytes are elsewhere (or no pass has classified them yet) — this
device is waiting, not working, and the chip clears the moment the origin
device publishes. Nothing on Drive is published by the wrong device, so
"Syncing…" is never shown on a device that cannot finish it, and only
uploads this device owes hold the iOS background-work window open.

A manual refresh re-kicks this device's pass and reports what it found:
"Google Drive data refreshed. 2 upload(s) still in progress; 1 file(s)
waiting on the device that made them." A pass that outruns the refresh's short
wait still reports its queue; the pump keeps going either way.

On macOS the pump is not in the renderer — the companion process holds the
staged bytes and publishes them — so the companion's report is what this
device is doing, and it travels over two routes. Every `GET /state` response
carries a top-level `driveUploads` object beside `driveConnection`:
`{queued, foreign, stalledDetail, reported}`, which is the pass's report
verbatim and is never persisted into the library. `POST /drive/uploads/flush`
runs a pass now — joining the one already in flight rather than racing it —
waits up to three seconds, the same cap the studio applies to a native pump,
and answers `{settled, driveUploads}` with the queue as it stands; the pass
itself outlives the cap. `WebGateway` implements the same
`DriveUploadStatusSource` the native gateway does, so the studio installs the
companion's report through the one path it already had. `reported` rides the
wire rather than being inferred: a companion too old to send the object at all
has said nothing about who owes these uploads, and the renderer must read that
silence as "Awaiting upload", not as an empty queue meaning published. A
`/state` read that finds staged media also makes sure a pass is coming, so
media a cross-device merge introduces gets classified rather than sitting
undescribed.

A record whose staged reference reappears from a cross-device merge after this
process already published it is re-swapped from the upload ledger rather than
uploaded again — by then the staged original has been renamed into the Drive
media cache, so a second upload would find no bytes and the record would be
stuck saying it is not on Drive.

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
