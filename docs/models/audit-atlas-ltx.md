# Atlas Cloud and LTX catalog audit — 2026-10-30

All changes live in the shared Flutter catalog, pricing code, and adapters.
Native mobile/Windows and the Electron companion use the same contracts.
New manifests require app version `0.61.0`; older apps retain their existing
routes until the updated adapters ship. The release workflow owns the version
bump.

## LTX Studio

Added direct LTX 2.5 Fast and Pro with text, first/last-frame, and audio-driven
generation; 720p through 4K; and the newly supported square, 3:2, and 2:3
shapes. Automatic duration is allowed without a last frame. The adapter rejects
that unsupported combination before sending a generation request.

Verified USD/second rates:

| Model | 720p | 1080p | 1440p | 4K |
| --- | ---: | ---: | ---: | ---: |
| LTX 2.5 Fast | .09 | .13 | .19 | .30 |
| LTX 2.5 Pro | .12 | .17 | .25 | .39 |
| LTX 2.3 Fast | .03 | .06 | .12 | .24 |
| LTX 2.3 Pro | .04 | .08 | .16 | .32 |
| LTX 2.3 Pro, audio input | .06 | .10 | .18 | .34 |

2.5 audio uses the corresponding generation rates. Audio estimates now use the
measured input duration, with a supported-duration range when it is unknown;
the previous flat $0.10/second estimate was wrong outside 1080p. Auto estimates
respect the selected resolution's duration limit.

Sources: [pricing](https://docs.ltx.io/pricing),
[LTX 2.5 capabilities](https://docs.ltx.io/models/ltx-2-5/),
[LTX 2.3 capabilities](https://docs.ltx.io/models/ltx-2-3/),
[audio request contract](https://docs.ltx.io/api-documentation/api-reference/async-video-generation/submit-audio-to-video),
[changelog](https://docs.ltx.io/api-changelog).

## Atlas Cloud

Reviewed every existing selectable route against the live
[public catalog](https://api.atlascloud.ai/api/v1/models). Seedance 2.0's
published starting rate changed from .112 to .09 USD/second; Mini changed from
.039 to .045. Other existing catalog base prices were unchanged. Hailuo 2.3's
.28 catalog value is a **six-second clip price**, not a per-second rate:
unauthenticated `/api/v1/model/calculate` quotes confirmed .28 for six seconds
and .56 for ten. Offline estimates and price comparison rows now preserve those
clip totals.

Added 25 creation routes covering these newly available model families:

- Kling 4.0; Wan 3.0 and Wan 3.0 Prime.
- MiniMax H3, H3 Fast, H3 Max, and H3 Max Turbo.
- PixVerse V6 Max; Grok Imagine 1.5 Lite; Vidu Q4 Preview.
- Luma Ray 3.2; LTX 2.5 Fast and Pro.

Every family has text and image routes except Vidu Q4, whose added route is
image-to-video. First/last frames and intermediate Kling 4 keyframes are
supported where the exact route permits them. Wan 3's public-URL requirement
is fulfilled by uploading local frames through Atlas before submission.
Kling 4 and H3 expose no audio switch in their Atlas schemas; their descriptions
explain that native audio is always enabled and the unsupported mute toggle is
hidden.
Kling 4 prompts are capped at the published 26,000-character ceiling. Atlas
also documents a smaller 11,000-character limit for non-English prompts; the
shared character-count control does not currently distinguish prompt languages.

Capabilities and payload fields came from the `schema` URLs in the live
catalog, under
[`https://static.atlascloud.ai/model/schema/`](https://static.atlascloud.ai/model/schema/kwaivgi-kling-v4.0-text-to-video.json).
The test fixture `flutter/test/fixtures/atlas_october_2026_schemas.json` records
the required fields, enums, and bounds from those 25 official schemas. Tests
validate payloads across every exposed resolution and aspect ratio, including
minimum/maximum durations.

Inventory preflight rows now carry the quoted resolution and audio setting so
an HD/audio quote cannot be reused for Full HD, 4K, or silent requests.
Atlas still fetches current prices and performs a configuration-specific quote
before submission. Offline catalog rates remain explicitly described as
starting rates; they do not promise that audio, resolution, input-video, or
provider enhancement tiers cost the same. Native resolution options are
exposed; separately billed ESR/SR enhancement variants remain unselected.

Other Atlas catalog entries remain visible in its existing live pricing
inventory as not ready for creation. Reference/edit/reframe/avatar pipelines
with different required inputs have not been advertised as newly supported
creation modes. No FLUX 3 Max entry was present in Atlas's public catalog.

## Verification

`atlas_ltx_refresh_test.dart` covers the official-schema matrix, Wan image
uploads, LTX request geometry and automatic-duration guard, every LTX rate
with and without published price rows, measured audio billing, and both
Hailuo clip lengths. These checks use mocked HTTP and do not purchase video
renders. Updated the existing Atlas/LTX catalog and price assertions in
`provider_api_test.dart`.
