# BFL and Runway catalog audit — 2026-10-30

This audit covers video generation, editing, and upscaling routes that fit
Clawnsole's shared Flutter generation contract. Image-only APIs, speech,
realtime sessions, HDR conversion, and frame-rate conversion require distinct
product contracts and are not newly enabled here.

## Black Forest Labs

Sources: [video parameters](https://docs.bfl.ai/flux_3/flux3_video),
[API schema](https://api.bfl.ai/openapi.json),
[pricing](https://docs.bfl.ai/quick_start/pricing), and
[Video Edit](https://docs.bfl.ai/flux_tools/flux_video_edit).
The pricing page now renders rates dynamically. Its public, published
[Sanity data feed](https://2gpum2i6.api.sanity.io/v2025-02-19/data/query/production?perspective=published&query=*%5B_type%20%3D%3D%20%22pricing%22%5D%5B0%5D%7BpricingCards%5B%5D%7Btitle%2CapiEndpoint%2CvideoRates%2CmpSecondPrice%2CsecondPrice%7D%7D)
was queried directly; older help/search snapshots contain superseded rates.
Values in that feed are credits, with one credit equal to $0.01.

| Route | HD | Full HD | QHD | UHD |
| --- | ---: | ---: | ---: | ---: |
| FLUX 3 text/image, USD/output-second | 0.15 | 0.24 | 0.28 | 0.41 |
| FLUX 3 continuation, USD/output-second | 0.21 | 0.27 | 0.31 | 0.45 |

Text/image drafts remain $0.06/s. The live feed omits continuation-draft
pricing; its $0.12/s fallback is retained from BFL's
[last explicit published table](https://help.bfl.ai/articles/7986977817-what-are-the-costs-associated-with-using-your-models)
and marked as such in the cost desk. This rate was not newly confirmed by the
current feed.

Video Upscale now costs $0.035 per delivered megapixel-second for precise and
$0.05 for creative. The new Video Edit [fast] route costs $0.03/output-second,
retains source duration, and accepts only video, prompt, and moderation setting.

FLUX 3's expanded resolutions and 9:21 framing use a manifest requiring
0.61.0. A legacy manifest retains the existing HD/FHD surface on older builds.
The new adapter maps the app's `4k` resolution to BFL's `uhd` wire value.

FLUX 3 Max is a separate fal post-trained model, not a BFL direct endpoint.
See [fal's model page](https://fal.ai/flux-3-max). Its Krea route is covered by
the Krea audit; BFL's API does not advertise a direct Max route.

## Runway

Sources: [model catalog](https://docs.dev.runwayml.com/guides/models/),
[credit pricing](https://docs.dev.runwayml.com/guides/pricing/), and
[OpenAPI schema](https://docs.dev.runwayml.com/openapi.json).

Added Kling 4; Kling 3.0 and O3 Standard, Pro, and 4K; Kling 2.5 Turbo Pro;
WAN 3.0 and Prime; H3 Max; Grok Imagine 1.5 Lite; and Gemini Omni Flash 1.1.
All new manifests require 0.61.0 because their wire mappings require the new
adapter. Existing Seedance 2.0, Fast, and Mini rates were corrected separately
for 480p and 720p. Other existing video rates were checked and retained.

Pricing now includes Hailuo reference-video charges and Gemini input charges.
Kling 4 uses the published input/output duration formula and rounds the list
charge before applying its promotion, then rounds again. Its 20% discount
expires automatically at 2026-12-01 00:00 UTC. Unknown reference-video lengths
produce a range bounded by the 30-second aggregate input cap. Editing waits
for measured source duration because it determines both input and output cost.
The cost desk stores exact 3–30-second clip totals from the same rounding
helper, so its columns agree with the generation estimate through expiry.

The fixture `flutter/test/fixtures/runway-video-contracts-2026-10-30.json`
records the official schema's allowed fields, required fields, and geometry
for the added routes. Tests exercise every exposed resolution/aspect ratio
against this independently captured contract, plus separate edit endpoints,
reference shapes, pricing, promotion expiry, and version compatibility.

Kling O3 creative image references are exposed for source-video editing only;
its generation route currently exposes pinned first/last frames. Gemini 1.1's
source-video mode is editing. Optional multi-shot, HDR, and provider-specific
reasoning controls are not exposed by the current neutral UI contract.
