# Krea model and pricing audit — 2026-10-30

Checked the public [Krea OpenAPI document](https://api.krea.ai/openapi.json),
[model reference](https://www.krea.ai/docs/api-reference/introduction), and
[API pricing page](https://www.krea.ai/app/api/pricing). API prices are separate
from consumer subscriptions. The fixed rate card uses each endpoint's
`x-krea-pricing.price_points`, including exact duration prices where the charge
is not linear. These are a verified snapshot, not an automatic pricing feed.

## Added routes

| Model | API route | USD per output second |
| --- | --- | --- |
| FLUX 3 Max | `black-forest-labs/flux-3-max` | 720p $0.17; 1080p $0.29 |
| Kling 4.0 | `kling/kling-4` | 720p $0.157; 1080p $0.235 |
| MiniMax H3 Max Turbo | `minimax/h3-max-turbo` | 480p $0.025; 768p $0.04; 1080p $0.08 |
| Wan 3.0 Prime | `alibaba/wan-3.0-prime` | 480p $0.068; 720p $0.14; 1080p $0.28; reference video seconds also billed |
| Gemini Omni Flash | `google/gemini-omni-flash` | Variable; settled by provider |
| Gemini Omni Flash 1.1 | `google/gemini-omni-flash-1.1` | Variable; settled by provider |
| FLUX Video Edit | `black-forest-labs/flux-video-edit` | Variable; settled by provider |

The new manifests require Clawnsole 0.61.0, because the adapter must know their
request fields. Existing FLUX 3 Video now includes 1440p and 2160p, and H3 Max
includes 1080p; legacy manifests retain the previous capabilities for older
apps. FLUX 3 Max uses start/end images; the specialized timed frame-index input
is not exposed because Krea does not specify the frame-rate mapping needed by
Clawnsole's seconds-based keyframes. H3 Max camera trajectories likewise stay
in the discovery-only catalog until the app has a trajectory input contract.

## Existing routes

All 23 previously enabled Krea models were checked. Updated fixed pricing for
Wan 2.5, Veo 3.1/fast/lite, Kling 2.6/3.0/o1, Hailuo 2.3/fast/3, H3 Max,
Seedance 2.0/fast/mini, LTX 2.5 pro/fast, Ray 2, Runway Gen-4.5, Vidu Q3,
and Grok Imagine 1.5. Wan 3.0 and the existing FLUX 3 tiers retain their current
rates. FLUX 3 Video adds 1440p $0.40/s and 2160p $0.80/s generation, and
1440p $0.65/s and 2160p $0.95/s video-to-video.

The full configuration-specific fixed rates live in the shared Flutter rate
card. In particular, Hailuo 2.3 Full HD costs $0.49 for either six or ten
seconds, and Fast Full HD costs $0.33 for either duration. A per-second average
cannot replace those exact clip prices. Seedance 2.0's lower reference tier
requires a video reference, not merely a start image. Hailuo 3 charges for
output plus reference-video duration and $0.04 per reference image after the
first five. Wan Prime similarly bills output plus reference-video duration.
Unknown input duration is shown as an unavailable estimate until measured.
The schema accepts fractional reference seconds but publishes only integer
billable-second price points; fractional inputs therefore use the surrounding
whole-second prices as a range instead of claiming an undocumented rounding
rule.

Krea now explicitly lists Seedance 2.5 as **variable** pricing and no longer
publishes fixed price points. The previous fixed tiers were removed. Variable
models remain usable, display “Variable price,” and do not persist a fabricated
zero-dollar quote. Provider-reported task cost still takes precedence when
available. No price from fal's temporary FLUX 3 Max promotion is applied to
Krea's separately priced route.

All four Seedance 2.x endpoints mark `generate_audio` as rejected from
2026-10-30T00:00:00Z. The adapter omits it and the catalog hides the unsupported
mute control. This does not imply that the generated video is silent.

No paid generation was submitted during this audit. Regression tests exercise
route mappings, deprecated-field removal, resolution/audio/duration tiers,
reference billing, unavailable prices, and the shared native/companion path.
