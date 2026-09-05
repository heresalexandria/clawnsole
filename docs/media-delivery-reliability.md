# Media delivery reliability

This follow-up to the studio reliability fixes separates provider receipts from
large media transfers across canonical Flutter and the Electron companion.
Every intentional Generate activation still creates its own operation, including
identical prompts, references and settings. Delivery retries never create a new
provider generation.

## Status and retention

Production gateways expose `pollStatus` and `retainResult`. Status checks persist
ready receipts and delivery URLs without waiting for media; the compatibility
`poll` method still performs both stages for older callers. The controller uses
one status slot and a separate pool of two media transfers. Queued transfers with
known earlier delivery expiry run first. A failed transfer requests a fresh
provider link on its next status attempt; an already saved link can still be
retained when a provider key is unavailable.

Manual checks and timer ticks share active/queued operation IDs. Retention is
also deduplicated at the gateway by generation ID. Short metadata writes are
serialized; successful downloads merge into the latest matching record without
dropping newer organization or status data. Deleted records are never recreated
by a late transfer. Stale failures cannot replace newer saved results. This is a
local concurrency contract, not a new distributed Drive transaction protocol.

Status requests have a 90-second controller ceiling. Media uses independent
idle, connection and total deadlines, with an eight-minute staging/transfer
budget and a ten-minute controller ceiling. Existing failure backoff and jitter
remain in effect. OS background delivery recovery runs independently of provider
status checks on foreground return.

## Streaming and integrity

Canonical native and companion stores can import streams and open existing
assets as streams. Files are staged privately, checked for declared size,
observed size and optional SHA-256, then atomically published. Empty, truncated,
oversize, mismatched and failed transfers do not publish partial files. Newly
retained assets include compact size and checksum metadata; existing assets
remain readable without checksums.

The default result limit is 2 GiB. Local disk import, background-file import and
Drive multipart upload avoid building a complete media payload in Dart memory.
Drive uploads remain single-request multipart uploads; resumable sessions,
restart checkpoints and general offline outboxes are still follow-on work.
Files awaiting metadata publication receive a one-hour in-process cleanup grace period;
normal referenced-file cleanup resumes after publication, and a permanent wipe
still removes them. Small custom/test stores without streaming support have a
bounded 8 MiB fallback.
Provider-required base64 references and byte-oriented user exports are separate
paths and are not made fully streaming by this change.

## Remote fetch and renderer boundaries

The process-owned media client accepts public HTTPS GET/HEAD requests. It rejects
credentials in URLs, nonstandard ports, private/special-use addresses and unsafe
headers; validates each redirect; resolves once per hop; and connects to those
validated addresses while retaining the original TLS hostname. Automatic proxy
routing is disabled because it would bypass the pinned destination. Managed
networks that require an outbound proxy need a separately designed compatible
policy. Ordinary public CDN redirects and byte-range requests remain supported.

Media responses use a passive MIME allowlist and a bounded active-document
prefix check. The companion sends `nosniff`, a sandbox CSP and no-referrer policy
on media routes. Electron navigation and privileged IPC accept only the app
document (`/` or `/index.html`, including fragment routes), so media/API paths
cannot acquire desktop bridge privileges. Media still shares the companion's
loopback origin; a physically separate media origin remains an additional
possible defense.

## iOS background limitation

The OS background download service remains enabled so transfers already handed
to iOS can finish while the app is suspended. Its initial destination receives
public-address preflight, and imported files receive media and integrity checks.
This does **not** pin the later OS connection or validate every background
redirect. Apple documents that background URL sessions follow redirects without
calling the redirect delegate. Replacing this transport requires a separate
background-delivery design; this PR does not claim to close that boundary.
[Apple URLSession redirect behavior](https://developer.apple.com/documentation/foundation/urlsessiontaskdelegate/urlsession(_:task:willperformhttpredirection:newrequest:completionhandler:)).

## Verification scope

Synthetic regression tests exercise blocked downloads while later jobs finish,
expiry ordering, repeated activation, retry links, stale/deleted records,
concurrent metadata saves, stream size/checksum/deadline failures, upload
backpressure, public/private DNS answers, redirects, cancellation, compression,
MIME spoofing, range playback and Electron sender/navigation boundaries. Native
and packaged smoke checks use isolated profiles. Live paid-provider billing,
authenticated Drive outages and iOS termination/background-network behavior
require separate device integration validation.

## Local memory experiment

On the audit host (macOS ARM64, Flutter 3.35.1), separate test processes streamed
reused 64 KiB chunks through the actual local store, verified length and SHA-256,
and removed their temporary files. RSS was sampled every 5 ms.

| File size | Time | Baseline RSS | Peak RSS | Increase |
|---|---:|---:|---:|---:|
| 50 MiB | 1.187 s | 143,179,776 B | 155,467,776 B | 12,288,000 B |
| 250 MiB | 3.521 s | 142,852,096 B | 158,760,960 B | 15,908,864 B |

These are local import measurements, not end-to-end iPhone/provider/Drive
benchmarks. Runtime heap, filesystem cache and sampling affect RSS; the useful
result is that a fivefold larger file did not require a fivefold media buffer.
The 2 GiB boundary is checked with synthetic declared/observed size tests; a
2 GiB physical-device transfer was not measured.

The Android development launcher also handles an absent optional Google OAuth
client on the macOS-provided Bash 3.2. Native verification used isolated iOS 26.5
and Android 34 ARM64 simulators/emulators with no provider keys.
