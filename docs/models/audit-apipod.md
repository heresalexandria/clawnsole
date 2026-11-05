# APIPod Seedance 2.5

Verified against APIPod's official documentation on 2026-11-05. The adapter
and catalog require Clawnsole 0.63.0; the release workflow owns the version bump.

## Supported routes

| Route | Inputs | Output |
| --- | --- | --- |
| `seedance-2.5-t2v` | Prompt | 4–30 seconds, 480p or 720p |
| `seedance-2.5-i2v` | Hosted first/last images | 4–30 seconds, adaptive aspect ratio |
| `seedance-2.5-r2v` | Up to 30 images, 10 videos, 10 audios | 4–30 seconds, 480p or 720p |

Audio generation can be enabled or disabled. Reference video and audio each
have a 30-second aggregate budget; individual clips must be 2–30 seconds.
Reference audio also requires an image or video. References must be publicly
reachable URLs, supplied with the existing Paste URL controls. APIPod's public
API documents no API-key file upload endpoint or base64 support. Local uploads
are therefore unavailable on these routes; Clawnsole does not publish private
files through another service. Public references bypass local normalization.

The landing page advertises 1080p, seed, edit, extend, and draft features that
are not covered consistently by the three standard route schemas. These
controls and alternate model families are deliberately not exposed by this
integration. The published OpenAPI schemas enumerate only 480p/720p and omit
seed. Image-to-video omits aspect ratio; its geometry follows the input.

## Transport and persistence

Provider verification uses the authenticated, non-generating
`GET /v1/account/status`. Requests use Bearer authentication. Generation posts
to `/v1/videos/generations`, then polls `/v1/videos/status/{task_id}`. The
durable generation operation supplies a stable idempotency token. Stored
receipts contain only the task ID and canonical polling URL. Provider keys
remain in the native settings vault or desktop companion, never the renderer.
Polling preserves pending/processing states, failures and cancellation, and
normalizes successful output URLs for Clawnsole's existing media retention.

## Pricing

| Resolution | No reference video | With reference video |
| --- | --- | --- |
| 480p | $0.098/output second | $0.0588/(input + output) second |
| 720p | $0.2205/output second | $0.1323/(input + output) second |

These are estimates from APIPod's published route tables. Video input activates
the lower rate for both reference and output duration. Unknown input duration
leaves the estimate unavailable instead of quoting output alone. Final token
usage determines the charge; only the task's returned `usage.cost` is recorded
as realized USD spend. Account balances and quotes are not task charges.

## Official sources

- [Seedance 2.5 overview](https://www.apipod.ai/models/seedance-2.5)
- [Text route schema](https://docs.apipod.ai/api-reference/openapi/seedance--2-5-text-to-video.yaml)
- [Image route schema](https://docs.apipod.ai/api-reference/openapi/seedance--2-5-image-to-video.yaml)
- [Reference route schema](https://docs.apipod.ai/api-reference/openapi/seedance--2-5-reference-to-video.yaml)
- [Task query schema](https://docs.apipod.ai/api-reference/openapi/query-video-task.yaml)
- [Authentication](https://docs.apipod.ai/authentication.md)
- [Idempotency and envelopes](https://docs.apipod.ai/endpoint-conventions.md)
- [Reference route pricing](https://www.apipod.ai/models/seedance-2.5/seedance-2.5-r2v)
- [Pricing estimates](https://www.apipod.ai/pricing.md)
