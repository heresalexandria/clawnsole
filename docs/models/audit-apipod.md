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

Media inputs require publicly reachable HTTPS URLs. The documented API has no
API-key upload endpoint; local files and base64 data are rejected before paid
submission, and hosted inputs bypass local normalization. Keys remain in native
settings storage or the desktop companion, never in the Flutter web renderer.

The official [Seedance web/API guide](https://www.apipod.ai/blog/alors-on-danse-ai-seedance-2-5)
distinguishes local uploads in its web playground from publicly reachable media
URLs in API requests. The current website uses multipart `/console/uploads`
with a browser session and `/auth/refresh`. On 2026-11-05 an empty multipart
request using the working API key returned HTTP 401, “Invalid or expired token”;
no media bytes were uploaded. No supported API-key upload endpoint was found in
the official API index. A local Files/Photos import therefore cannot be made
provider-readable merely by preserving its local path; Clawnsole offers a
public-URL attachment instead of silently uploading to an unrelated host.

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
