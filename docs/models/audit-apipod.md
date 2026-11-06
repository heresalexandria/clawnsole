# APIPod video catalog

Audited on 2026-11-05 against APIPod’s active pricing catalog and the live
`initialSchema` OpenAPI document on each individual model page. All **103 active
video routes** are supported in Clawnsole 0.64.0 on iOS, Android, native Windows,
and companion-backed Electron macOS. The release workflow owns the version bump.
The [machine-readable coverage inventory](apipod-coverage.json) records every
route and its exact schema source.

## Model choices and automatic routes

Clawnsole 0.64.1 presents 49 logical APIPod choices while retaining all 103
wire IDs. A choice such as Seedance 2.5 automatically selects its text, pinned
frame, or creative-reference route from the attached media. Draft, Edit, Extend,
quality/speed variants, and Veo 4K remain distinct choices. Routes never jump to
another variant merely because its attachment budget is larger. The selected
wire route controls limits and pricing, and its ID remains in generation history.
Wan 2.7 text audio guidance requires 0.64.1; a version-bounded legacy manifest
retains the text-only mode for 0.64.0. Both releases expose exactly 103 routes.
Existing saved wire IDs and preferences remain valid; refreshed manifests add
`selection_group_id` and `selection_group_label` without changing route IDs.

## Coverage

| Family | Active routes |
| --- | ---: |
| gemini-omni | 4 |
| gemini-omni-flash-1.1 | 4 |
| gemini-omni-flash-1.1-lite | 3 |
| grok-imagine | 2 |
| grok-imagine-1.5 | 3 |
| kling-3.0 | 2 |
| kling-4.0 | 3 |
| kling-motion-control | 1 |
| minimax-h3 | 3 |
| minimax-h3-lite | 3 |
| minimax-h3-max | 2 |
| motion-control | 1 |
| muse-video | 3 |
| seedance-1.0 | 7 |
| seedance-2.0 | 3 |
| seedance-2.0-fast | 3 |
| seedance-2.0-fast-lite | 3 |
| seedance-2.0-lite | 3 |
| seedance-2.0-mini | 3 |
| seedance-2.0-mini-lite | 3 |
| seedance-2.0-spicy | 3 |
| seedance-2.0-x | 2 |
| seedance-2.5 | 6 |
| seedance-2.5-lite | 3 |
| seedance-2.5-spicy | 5 |
| veo3-1 | 7 |
| wan2.7-video | 3 |
| wan3.0-video | 3 |
| wan3.0-video-prime | 3 |
| wan3.0-video-prime-spicy | 3 |
| wan3.0-video-pro-spicy | 3 |
| wan3.0-video-spicy | 3 |

The catalog includes Seedance 1.0 Lite/Pro/Fast, 2.0 Standard/Fast/Mini/Lite/X
and Spicy variants, and 2.5 Standard/Lite/Spicy/Draft/Edit/Extend. APIPod currently
marks Seedance 1.5, Seedance 2.5 X, and Sora routes offline; they are recorded in
the inventory rather than offered as working choices. Other historical routes
present only in the documentation index are not advertised as active models.

Each route exposes its documented basic controls: output size, aspect ratio,
duration, configurable audio, pinned frames, creative references, or source
video as appropriate. Optional provider-only controls such as web search,
multishot scripts, voice IDs, documents, and output container are left at
provider defaults. Unknown fields are never passed through to a paid request.
No current active route schema exposes a random seed.

Live model-page schemas supersede the older documentation export, which misses
new routes and limits standard Seedance 2.5 to 720p. Current schemas support
1080p for standard 2.5 and up to 4K on selected 2.0 routes. The JSON source also
avoids the documentation YAML export’s corrupted numeric aspect-ratio enums.
Live validation rejected MiniMax H3 Lite text generation at 768p despite the
enum. Its text/image schemas describe 2K-only support, so those controls are
restricted to 2K. The reference route retains its published 768p/2K options.
Grok 1.5 Preview is limited to 720p as its schema description requires.

Integer form enums/defaults and string boolean defaults are normalized to wire
types. Wan 3’s `enum: [-1]` supplements its explicit duration range with Auto.

## Media and workflows

### iCloud Drive live verification

Fresh live tests on November 6, 2026 completed `seedance-2.5-r2v` generations
using references published from a real iPhone and the macOS production gateway.
Both outputs downloaded and decoded without errors. Both owned source copies
were removed through the native cleanup API, with publication URLs erased from
the native journals. Apple's reported snapshot expirations remain December 6;
source cleanup does not prove immediate link revocation.

| Successful test | Measured preparation | Verified result |
| --- | --- | --- |
| Real iPhone, production Swift service and product iCloud Drive container | Publication 6.794 s; anonymous download and SHA-256 verification 0.619 s; provider acceptance 1.484 s | Completed 4.041667 s H.264 video, 854×480, 97 frames, 1,692,359 bytes; local source cleanup 11.5 ms. |
| macOS complete `DirectGateway` flow | Normalization, storage, hosting and submission 7.710 s total; native publication 4.480 s; link resolution and anonymous verification 0.466 s | Completed video retained in the asset store, 1,612,987 bytes; full decode passed; source cleanup 15 ms, zero active leases or pending cleanup. |

The iPhone used an isolated diagnostic app running the exact production Swift
source with `iCloud.app.clawnsole.clawnsole`. Its published reference was resolved
and submitted through the production Dart resolver and APIPod adapter on the Mac.
This verifies real-device publication, provider reachability and cleanup, but is
not an installed Flutter Files/Photos-to-generation UI test. Method-channel
wiring and native/backend integration have separate automated coverage. The
diagnostic app was uninstalled without replacing the existing TestFlight app.

These successful tests satisfy the live generation gate, but do not establish
consistent delivery latency. Earlier attempts on November 6 (UTC), before these
successful runs, all used `seedance-2.5-r2v` and received:
“failed to resolve reference video duration for seedance billing; check that
video_urls are reachable media files”. The quoted $0.5292 was an estimate, not a
settled charge.

| Attempt | Verified local/hosting evidence | Provider result |
| --- | --- | --- |
| Original video through the production hosting backend | 1,252,662 bytes; readiness and consent verified; preparation took 14.880 s; anonymous GET took 1.254 s and matched SHA-256 | Rejected after 8.21 s. This harness did not record HTTP status or an accepted task ID. |
| Fast-start MP4 control | 1,231,205 bytes; `moov` precedes `mdat`; all 97 decoded frames matched the original; anonymous GET took 16.097 s and matched SHA-256 | HTTP 400 after 8.14 s; no task accepted. |
| Actual `DirectGateway` flow | Normalization, retained-asset storage, iCloud publication and provider submission all ran; normalized source was 719,668 bytes | HTTP 400 with the same error, saved as `Error` with no request ID. Native source cleanup completed; Apple's reported snapshot expiry was 2026-12-06. |

During those earlier failures, the direct-URL resolver matched the successful
POC. Anonymous full GETs
returned the expected bytes, and range GETs returned matching byte ranges.
Several range requests took roughly 7–28 s to receive their first byte; the
formerly successful URL and fast-start control also showed delays. HEAD probes
returned HTTP 501. These observations make a provider fetch timeout plausible,
but neither APIPod's internal fetch deadline nor provider-region reachability
has been verified. They do not establish the cause, a reliable workaround, or
that moving MP4 metadata alone fixes the problem.

Automated verification is separate: 52 focused Flutter 3.47 tests passed for
hosting lifecycle, journal migration, source cleanup versus snapshot expiry,
account-bound consent, direct/native/companion wiring, saved-reference attachment,
and process timeout/crash/restart behavior. The corresponding owned-file analyzer
check passed. These tests use local fakes and do not replace live provider
verification. Source removal also does not prove that Apple's published snapshot
is no longer readable.

### Reference hosting design

Media inputs require publicly reachable HTTPS URLs. The documented API has no
API-key upload endpoint. iOS and Electron macOS publish copies of imported or
private library media through the user's iCloud Drive. The source copy uses user
Drive storage; this route creates no app CloudKit database and operates no
Clawnsole media server. It does not move the user's existing local or Google
Drive library. Android and Windows continue to support text generation and
public-URL inputs; no unsupported local-hosting fallback is attempted.

The device must be signed in to an Apple Account with iCloud Drive enabled.
Clawnsole checks readiness and requires sharing consent scoped to this device,
Apple account and disclosure version before publication. The native gateway or
companion creates only separately owned reference copies, waits for upload,
resolves Apple's attachment page and verifies anonymous media bytes before paid
submission. Existing public HTTPS inputs bypass staging and normalization;
local inputs retain normal compatibility fixes. Keys and publication operations
remain outside the Flutter web renderer.

Foundation's publication API is documented, but the attachment-page resolver
needed to obtain the direct media URL follows Apple's observed website behavior
and is not a supported direct-download API. Invalid or changed responses stop
submission with an actionable error. File-format, size and model limits still
apply; one successful reference generation does not verify every model or asset.

**Source deletion does not immediately revoke the published snapshot.** Anyone
with its link can retain access after processing and cleanup. Apple reported
expiration dates around 30 days in the diagnostic tests; these were not tests of
a full 30-day lifetime. The recovery journal distinguishes pending source cleanup
from published snapshots, retains expiration metadata without public URLs, and
reconciles interrupted work without blindly repeating paid submissions. An
account change prevents mutation of another account's copies and requires new
consent. Snapshot quota accounting is not established by the storage tests.

### Google Drive diagnostic and legacy cleanup

On 2026-11-05, two Google Drive copies of the same nonprivate video passed
anonymous full-download/SHA256 checks and APIPod's duration-based pricing probe
($0.5292 each). Seedance 2.5 nevertheless failed both tasks during upstream asset
review with a TOS downloader HTTP 502. One used Drive's `webContentLink`; the
other used its verified final `drive.usercontent.google.com` URL. No usage/cost
was reported. This established a downstream fetch failure, not its cause or
permanence. Both permissions were revoked and copies trashed successfully.

Google Drive is therefore not used for new reference hosting. Existing hosting
journals migrate with explicit backend ownership, allowing old Drive copies to
be cleaned up through the original connected account. Disconnecting Google Drive
cleans only its legacy leases and does not suspend independent iCloud references.
Library sync and the encrypted settings vault continue to use Google Drive.

The official [Seedance web/API guide](https://www.apipod.ai/blog/alors-on-danse-ai-seedance-2-5)
distinguishes local uploads in its web playground from publicly reachable media
URLs in API requests. The current website uses multipart `/console/uploads`
with a browser session and `/auth/refresh`. On 2026-11-05 an empty multipart
request using the working API key returned HTTP 401, “Invalid or expired token”;
no media bytes were uploaded. No supported API-key upload endpoint was found in
the official API index. A local Files/Photos import therefore cannot be made
provider-readable merely by preserving its local path. Clawnsole offers either
a public-URL attachment or explicitly disclosed publication through user iCloud
Drive on supported Apple platforms. See [temporary media sharing](../google-drive-web.md#temporary-media-sharing).

Seedance edits and extensions use the source-video editor. The source is sent
first in `video_urls`; reference prompt numbering accounts for that position.
Motion control requires both the character image and source video. Muse and
Grok expose exact duration choices instead of invalid intermediate durations.

Seedance Draft creates a 480p preview. Finalization accepts the platform task ID
of a completed draft from the same account within seven days, sends only that
ID and 1080p resolution, and reuses the original prompt/media/timing/audio.
Completed previews can be finalized from the library; task IDs remain compact
metadata and are never treated as media URLs or downloaded.

## Pricing and persistence

Published estimates use each route’s base charge, per-second dimensions, and
resolution/audio/reference multipliers. Flat per-request routes remain flat;
Muse uses its discrete duration prices. Unresolved pricing tiers yield a range.
Seedance video inputs include input plus output duration at the applicable
reference rate; unmeasured inputs leave the quote unavailable. Final draft
pricing is unavailable until the provider resolves the original draft inputs.
Only returned `usage.cost` is settled USD spend. Estimated values never become
realized charges. Polling, operation IDs, ambiguous receipts, restarts, and media
retention use the existing shared native/companion transport.

APIPod's documented public `/v1/pricing/estimate` now supplies the live quote for
the resolved route. Only billing dimensions are sent: no prompt, API key, task
ID, or media URL. Unavailable/malformed quotes fall back to the published
estimate; incomplete source metadata never yields a falsely exact live quote.
Input videos round up **individually** before their durations are added to the
output. For example, a 5-second 480p Standard output plus 4.0417- and 6.0417-second
references bills 17 seconds at $0.0588/second, totaling $0.9996. A live quote
using the source URLs and a separate metadata-only quote returned the same total.

The current [Seedance 2.5 Standard page](https://www.apipod.ai/models/seedance-2.5)
and live API agree on $0.098/second at 480p, $0.2205 at 720p, and $0.54194 at
1080p for text/frame generation. The catalog's “from $0.059/sec” is the rounded
video-reference rate, with input plus output seconds billed. Authenticated and
public quotes agreed. The reviewed official Standard/Lite/pricing pages did not
advertise a sub-cent Standard rate; static rates were not lowered speculatively.

The original three 0.63 routes remain in version-bounded legacy manifests. New
contracts require 0.64, and stale versioned catalogs cannot replace a newer
bundled catalog. A failed Pages deployment therefore cannot hide new providers.

## Verification sources

- [Active route inventory and list prices](https://www.apipod.ai/pricing.md)
- [Site integration index and public pricing endpoint](https://www.apipod.ai/llms.txt)
- [Live model catalog and per-model API schemas](https://www.apipod.ai/models)
- [Documentation export index](https://docs.apipod.ai/llms.txt)
- [Authentication](https://docs.apipod.ai/authentication.md)
- [Task polling](https://docs.apipod.ai/api-reference/openapi/query-video-task.yaml)

Local quote checks against `/v1/pricing/estimate` matched Veo Lite 720p ($0.08),
Muse 10 seconds ($0.20), Seedance 2.0 Mini 4 seconds/480p ($0.10), MiniMax H3 Lite
5 seconds/2K ($0.31), and Wan 3 2 seconds/480p ($0.09).

## Live smoke test

`flutter/test/apipod_live_test.dart` is skipped unless both `APIPOD_API_KEY` and
`RUN_APIPOD_LIVE_TESTS=true` are supplied to the test process. It creates three
paid 4-second 480p jobs, verifies output downloads, and checks reported costs.
Set `APIPOD_LIVE_REPORT` to a local JSON path to retain task IDs. After an
interruption, use that same report with `APIPOD_LIVE_RESUME=true` to poll the
existing jobs; an uncertain submission without a confirmed ID is never resent.
Downloads use the production media client with bounded retries of the same
URL. `APIPOD_LIVE_OUTPUT_DIR` optionally saves MP4s for inspection.

Set `APIPOD_LIVE_SUITE=catalog` for the eight-family text smoke suite. It requires
`APIPOD_LIVE_REPORT`, refuses to overwrite an existing report, and preflights
all payloads and a $3 estimate ceiling before the first paid submission. Use
`APIPOD_LIVE_RESUME=true` to resume saved task IDs without submitting again.
The default suite retains the three original Seedance 2.5 mode tests.

Set `APIPOD_LIVE_SUITE=workflow` and `APIPOD_LIVE_REFERENCE_REPORT` to an existing
verified Seedance smoke report for one grouped Seedance 2.5 reference job. It
resolves the alias to the reference route, requires a fresh live quote below
$1, persists the submission before polling, and checks settled cost against
that quote plus MP4 delivery. It reuses the existing report's measured public
output instead of paying for another source clip.

The 2026-11-05 workflow check selected the `seedance-2.5` family with a measured
4.041667-second public video reference and resolved to `seedance-2.5-r2v`.
Its live quote and settled charge both equaled **$0.5292** (4 output seconds +
5 rounded input seconds). The one submitted job delivered a 1,252,662-byte H.264
MP4 at 854×480, lasting 4.041667 seconds, with no audio stream.

## Expanded live results (2026-11-05)

Seven families produced downloadable, codec-verified MP4s: Seedance 2.0 Mini,
Veo 3.1 Lite, Grok 1.5 Fast, Wan 3, MiniMax H3 Lite 2K, Muse, and Kling 3. The eighth
job, Gemini Omni, completed upstream but failed output delivery. Total reported
charges were $1.328, including that $0.25 Gemini job. The rejected MiniMax 768p
request had no accepted task; the separately corrected 2K request succeeded.

- **Gemini Omni text:** APIPod returned an unsigned upstream API content URL
  requiring another service’s token. Re-polling the same task did not repair it.
  Clawnsole does not forward the APIPod key to another host. The route’s picker
  description warns that generation may be charged without downloadable output.
- **Muse text:** a 5-second silent request produced a 10-second video with audible
  AAC audio. This is recorded as successful delivery with a provider parameter
  mismatch, not exact duration/audio compliance. Its model description warns
  that those output properties can differ.

These are provider-side observations, not claimed successful end-to-end results
for every catalog route. Automated mapper coverage spans all 103 active routes;
live validation is sampled and retains accepted task IDs instead of retrying
paid submissions.
