# ArtCraft model and pricing audit — 2026-10-30

The public [live video catalog](https://api.storyteller.ai/v1/omni_gen/models/video?provider=artcraft)
contains 30 distinct enabled routes. Clawnsole already supported 28; this update
adds `wan_3p0` and `wan_3p0_prime`. Disabled catalog entries remain excluded.
FLUX 3 Max is not exposed by this ArtCraft catalog.

Every enabled route was checked with a POST to
`https://api.storyteller.ai/v1/omni_gen/cost/video`, using the live catalog's
default duration, resolution and aspect ratio, with audio enabled when offered.
These read-only quotes do not generate or charge for media. All 28 existing
compiled default rates agree with these fresh quotes. Each row below records
the whole quote and its effective per-second fallback; these are **default
configuration** rates, not claims that every resolution and input has that price.
The app continues to request configuration-specific quotes.

| Route | Default seconds | Resolution | Quoted credits/USD cents | Effective USD/s |
| --- | ---: | --- | ---: | ---: |
| `flux_3` | 5 | seven_twenty_p | 98 | 0.19600 |
| `flux_3_draft` | 5 | seven_twenty_p | 35 | 0.07000 |
| `grok_imagine_video` | 8 | seven_twenty_p | 73 | 0.09125 |
| `grok_imagine_video_1p5` | 8 | seven_twenty_p | 118 | 0.14750 |
| `happy_horse_1p0` | 5 | seven_twenty_p | 85 | 0.17000 |
| `kling_1p6_pro` | 5 | provider default | 57 | 0.11400 |
| `kling_2p5_turbo_pro` | 5 | provider default | 41 | 0.08200 |
| `kling_2p6_pro` | 5 | provider default | 81 | 0.16200 |
| `minimax_h3` | 5 | two_k | 150 | 0.30000 |
| `seedance_1p5_pro` | 8 | ten_eighty_p | 135 | 0.16875 |
| `seedance_2p0` | 5 | seven_twenty_p | 93 | 0.18600 |
| `seedance_2p0_fast` | 5 | seven_twenty_p | 64 | 0.12800 |
| `seedance_2p0_bp` | 5 | seven_twenty_p | 125 | 0.25000 |
| `seedance_2p0_bp_fast` | 5 | seven_twenty_p | 100 | 0.20000 |
| `seedance_2p0_bpu` | 5 | seven_twenty_p | 125 | 0.25000 |
| `seedance_2p0_bpu_fast` | 5 | seven_twenty_p | 100 | 0.20000 |
| `seedance_2p0_mini` | 5 | seven_twenty_p | 45 | 0.09000 |
| `seedance_2p0_bp_mini` | 5 | seven_twenty_p | 46 | 0.09200 |
| `seedance_2p0_bpu_mini` | 5 | seven_twenty_p | 46 | 0.09200 |
| `seedance_2p5` | 5 | seven_twenty_p | 134 | 0.26800 |
| `seedance_2p5_u` | 5 | seven_twenty_p | 158 | 0.31600 |
| `seedance_2p5_preview` | 5 | seven_twenty_p | 214 | 0.42800 |
| `veo_3_fast` | 8 | ten_eighty_p | 138 | 0.17250 |
| `veo_3p1` | 8 | ten_eighty_p | 384 | 0.48000 |
| `veo_3p1_fast` | 8 | ten_eighty_p | 132 | 0.16500 |
| `veo_3p1_lite` | 8 | seven_twenty_p | 46 | 0.05750 |
| `vidu_q3` | 5 | seven_twenty_p | 82 | 0.16400 |
| `vidu_q3_turbo` | 5 | seven_twenty_p | 42 | 0.08400 |
| `wan_3p0` | 5 | seven_twenty_p | 49 | 0.09800 |
| `wan_3p0_prime` | 5 | seven_twenty_p | 94 | 0.18800 |

## Wan capability and pricing contract

Both new routes offer 2–30 seconds, 480p/720p/1080p, first/last frames or up to
10 image, 5 video and 5 audio references, audio control, and a 20,000-character
prompt ceiling. Video and audio input budgets are each 15 seconds. The combined
reference-video and output duration must be at most 30 seconds. The new
provider-neutral `max_combined_video_seconds` contract makes the available input
budget shrink as output duration grows. Its manifests require app 0.61.0, which
understands this budget. The API gateway also rejects known combined overruns
before contacting ArtCraft.

Fresh five-second quotes across resolutions:

| Route | 480p | 720p | 1080p |
| --- | ---: | ---: | ---: |
| Wan 3.0 | $0.25 | $0.49 | $0.97 |
| Wan 3.0 Prime | $0.46 | $0.94 | $1.88 |

The values were additionally checked for 2, 10 and 30 seconds. Whole-credit
rounding means multiplying the five-second effective rate is only a fallback;
the live quote retains the provider's exact configuration total.

Sources: [Wan request normalization](https://github.com/storytold/artcraft-services/blob/main/crates/api_clients/artcraft/artcraft_router/src/generate/generate_video/providers/wan_3p0_common.rs),
[measured duration enforcement](https://github.com/storytold/artcraft-services/blob/main/crates/service/web/storyteller_web/src/http_server/endpoints/omni_gen/generate/video/wan_3p0_reference_duration.rs),
[Wan pricing](https://github.com/storytold/artcraft-services/blob/main/crates/api_clients/artcraft/artcraft_router/src/generate/generate_video/providers/artcraft/wan_3p0/cost.rs).

## Reference-video pricing correction

ArtCraft's public cost endpoint selects its reference-video rate only when
`reference_video_media_tokens` is populated. It ignores URL reference fields;
a live request containing only `estimate_only` input duration still returns
the no-reference price. Clawnsole's composer has local files and public URLs
before upload, so treating that response as an exact reference price was wrong.

The shared published estimator now applies the audited reference rate for every
Seedance 2.0 variant, including Mini, Plus and Ultra, and for Seedance 2.5/Ultra.
Seedance 2.0 charges a resolution-specific output rate with video references.
Seedance 2.5 charges its reference rate for output plus aggregate video-input
seconds, rounds the aggregate input upward to whole seconds, clamps its billing
range to 4–30 seconds, and rounds the final total upward to whole credits.
Unknown durations produce a bounded estimate. The displayed basis explicitly
says these are published rates; estimates are never recorded as provider
receipt charges. Seedance 2.5 Preview pricing does not depend on references.

The app now forwards measured aggregate input duration to the adapter and
invalidates the estimate when a measurement arrives. For genuinely uploaded
ArtCraft media tokens the adapter can still request a live quote with
`estimate_only.total_input_video_duration_millis`. Generation never receives
these estimate-only fields; ArtCraft independently measures its actual inputs.

Sources: [cost request schema](https://github.com/storytold/artcraft-services/blob/main/crates/api_clients/artcraft/artcraft_api_defs/src/omni_gen/cost_and_generate_requests/omni_gen_video_cost_and_generate_request.rs),
[cost endpoint](https://github.com/storytold/artcraft-services/blob/main/crates/service/web/storyteller_web/src/http_server/endpoints/omni_gen/cost/video/omni_gen_video_cost_handler.rs),
[Seedance shared pricing](https://github.com/storytold/artcraft-services/blob/main/crates/api_clients/artcraft/artcraft_router/src/generate/generate_video/providers/artcraft/seedance_common.rs),
[Seedance 2.0 pricing](https://github.com/storytold/artcraft-services/tree/main/crates/api_clients/artcraft/artcraft_router/src/generate/generate_video/providers/artcraft/seedance_2p0),
[Omni API](https://github.com/storytold/artcraft/blob/main/_docs/omni_api/artcraft_omni_api.md).

No paid generations were submitted during this audit. Adapter tests verify
payload mapping with mocked HTTP, while controller tests exercise the combined
budget and quote invalidation on the shared native/companion product path.
