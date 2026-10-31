# fal provider audit — 2026-10-30

The initial fal provider exposes 16 exact endpoints across eight current video
families. The native Flutter clients and Electron companion share the same
capability declarations, request mapping, and 46 resolution-specific price
rows. Every provider/model manifest is gated to **0.62.0**, when the fal adapter
ships; the release workflow owns the version bump.

## Models and list prices

Prices below are USD per second of generated video, for both text and image
routes. The catalog calls these **published list rates**: promotions or account
pricing can reduce the charge, and the estimated requested duration is not a
receipt for the delivered output.

| Family | Exact route prefix / suffix | Published list rates |
| --- | --- | --- |
| [FLUX 3 Max](https://fal.ai/models/blackforestlabs/flux-3-max/text-to-video) | `blackforestlabs/flux-3-max/{text-to-video,image-to-video}` | 720p $0.17; 1080p $0.29 |
| [FLUX 3](https://fal.ai/models/blackforestlabs/flux-3/text-to-video) | `blackforestlabs/flux-3/{text-to-video,image-to-video}` | 720p $0.17; 1080p $0.29; 1440p $0.32; 2160p $0.47 |
| [MiniMax H3 Max](https://fal.ai/models/minimax/h3-max/text-to-video) | `minimax/h3-max/{text-to-video,image-to-video}` | 480p $0.05; 768p $0.08; 1080p $0.16 |
| [MiniMax H3 Max Turbo](https://fal.ai/models/minimax/h3-max-turbo/text-to-video) | `minimax/h3-max-turbo/{text-to-video,image-to-video}` | 480p $0.025; 768p $0.04; 1080p $0.08 |
| [Kling 4.0](https://fal.ai/models/kling/v4/text-to-video) | `kling/v4/{text-to-video,image-to-video}` | 720p $0.157; 1080p $0.235 |
| [Wan 3.0](https://fal.ai/wan-3) | `alibaba/wan-3.0/{text-to-video,image-to-video}` | 480p $0.05; 720p $0.10; 1080p $0.20 |
| [LTX 2.5 Fast](https://fal.ai/models/lightricks/ltx-2.5/text-to-video/fast) | `lightricks/ltx-2.5/{text-to-video,image-to-video}/fast` | 720p $0.09; 1080p $0.13; 1440p $0.19; 2160p $0.30 |
| [LTX 2.5 Pro](https://fal.ai/models/lightricks/ltx-2.5/text-to-video/pro) | `lightricks/ltx-2.5/{text-to-video,image-to-video}/pro` | 720p $0.12; 1080p $0.17 |

Each image endpoint's model page was checked separately; its listed rates agree
with the corresponding text endpoint. Rates do not change when the supported
audio toggle is off.

On the audit date FLUX 3 Max advertises 75% off, October 15–November 7:
$0.0425/second at 720p and $0.0725 at 1080p. H3 Max and Max Turbo advertise 35%
off through October 31, then 30% off November 1–15, returning to the listed
standard prices on November 16. The pages do not specify an exact UTC cutoff.
Clawnsole therefore does not invent one or retain a potentially expired
promotional quote. The current promotions are documented here; the UI labels
its conservative list estimates explicitly.

The [authenticated pricing API](https://fal.ai/docs/platform-apis/v1/models/pricing)
returns a base `unit_price`, `unit`, and currency for an endpoint. It does not
provide the configuration multipliers needed to map a price onto every
resolution. This initial adapter uses the audited tier table rather than
pretending that the base-unit response quotes a complete request. A future
live-price implementation must verify those multipliers or receive a
configuration-specific quote.

## Schema and request checks

The authoritative schemas are available through
`https://fal.ai/api/openapi/queue/openapi.json?endpoint_id=<exact endpoint>`.
The focused fixture in
`flutter/test/fixtures/fal_october_2026_schemas.json` records each source URL.
`fal_model_contracts.dart` maps the neutral request into that endpoint's input
and rejects incompatible modes, references, frame counts, prompt lengths,
resolutions, ratios, durations, and bounded seeds before submission.

- FLUX 3 Max accepts 5–20 seconds, 720p/1080p, seed, and optional end frame.
  FLUX 3 additionally accepts automatic duration and upsampled 1440p/2160p;
  its image endpoint accepts only a starting frame and has no seed field.
- H3 Max and Turbo support 1–15 whole seconds in Clawnsole (the API minimum
  is 0.92). Their resolution values use uppercase `480P`, `768P`, `1080P`.
  The required prompt expansion field is set to `balanced`. Image routes
  follow their pinned frame geometry. Audio is always generated; no unsupported
  toggle is sent. The schema warns that output can be about 0.7 seconds longer
  than requested, so the estimate remains approximate.
- Kling 4 supports 3–30 seconds. Image requests map ordered frames to the
  first frame, up to eight middle frames, and final frame. Their aspect ratio
  follows the images; audio has no request toggle. Its documented image
  constraints include 300-pixel minimum dimensions and a 0.4–2.5 aspect range;
  fal validates those on submission. Clawnsole's image ceiling leaves room
  below fal's 30 MiB limit.
- Wan 3 supports 2–30 seconds. Automatic duration is JSON `null`, automatic
  ratio becomes `adaptive`, and the audio switch is named `audio`. Seeds are
  limited to 0–2147483647. Its image route allows an omitted prompt.
- LTX Fast supports 6–20 seconds in two-second steps at 720p/1080p; 1440p/2160p
  are limited to ten seconds. Pro supports 6/8/10 seconds at 720p/1080p.
  Both support automatic duration, audio, and start/end images. The adapter
  fixes 25 fps, preserving Fast's twenty-second range without exposing an
  unsupported cross-product of frame rates and durations. A prompt is required
  for both LTX routes by fal's schema.

## Transport, scope, and verification

[Queue requests](https://fal.ai/docs/documentation/model-apis/inference/queue)
retain the complete model ID for submission and the durable queue identity for
polling/restart. Default provider payload/CDN retention is preserved so a
restarted app can recover results. Media is copied into Clawnsole's asset store
when available; no invented fal retention window is shown.

Verification is read-only and uses the
[request listing endpoint](https://fal.ai/docs/platform-apis/v1/models/requests/by-endpoint)
with the API key's request-read permission. Local/data-URI media follows fal's
[official JavaScript client upload protocol](https://github.com/fal-ai/fal-js/blob/main/libs/client/src/storage.ts):
initialize a signed upload, then PUT without the API key. Already-hosted HTTPS
media passes through. The initial single-upload path supports up to 90 MB;
SDK multipart uploads are outside this adapter's scope. Verification and signed
upload responses are omitted from transcripts. No paid requests were made.

This is a curated video catalog, not a claim to cover fal's hundreds of image,
audio, editing, streaming, and specialty endpoints. Seedance 2.5 is deferred:
its generic routes are unlisted, its public alternatives include explicit US
variants, and its rates are based on output dimensions and tokens. Reference,
video-editing, target-audio, multi-shot, reasoning, camera-motion, and other
advanced fal controls need an explicit neutral contract before exposure.

`fal_catalog_test.dart` validates every advertised combination against the
captured schema, checks frame ordering and automatic-duration mappings,
exercises invalid submissions, and checks all 46 list tiers through the shared
cost estimator, including sparse-price fallback. Transport/lifecycle tests
cover authentication, queued completion, error handling, and persistence
across native and companion-backed paths. Tests use mocks; live rendering and
account-specific discounts were not exercised.
