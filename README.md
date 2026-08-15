# Clawnsole

Clawnsole is a local-first video generation workspace with a premium, midcentury-inspired interface. It currently supports Black Forest Labs’ FLUX 3 video API and keeps provider boundaries explicit so more video APIs can be added without rewriting the library or generation UI.

## What it does

- Text-to-video, image-to-video, video continuation, and draft enhancement
- One to ten start, end, and intermediate keyframes
- Evenly spaced frames or explicit per-frame timing
- Auto or 5–20 second duration, all documented aspect ratios, HD/FHD, synchronized audio, drafts, and safety tolerance
- Live polling with progress bars using the `polling_url` returned by BFL
- Live provider credit balance with manual and automatic refresh
- Per-generation estimates from BFL’s published rate card, reconciled to the exact API charge after submission
- Credit and USD spend history, including available balance before and after each submitted job
- Completed-video playback through a same-origin media proxy
- Browser save picker (“Save to Finder”) with a normal download fallback
- Uncapped compact generation history, reusable settings, file-size accounting, and granular clear controls
- API-key setup in the UI, stored only in Clawnsole’s local data file

## Run locally

```bash
npm install
npm run dev
```

Open [http://localhost:3000](http://localhost:3000), go to Settings, and paste a BFL project key. The Next.js process must remain running while you use the app.

## Persistence policy

Clawnsole has no database and uses no browser storage. Its single source of truth is:

- `.clawnsole/clawnsole.json`

That directory is gitignored. Set `CLAWNSOLE_DATA_FILE` before starting the app if you want the file elsewhere, which will also make it easy to move into an Electron or Flutter application-data directory later.

- Generation history is not capped.
- History stores prompts, request IDs, polling URLs, compact generation settings, status, and temporary delivery URLs. It never stores uploaded images, source clips, generated video blobs, or base64 request payloads.
- History also stores the estimate shown at submission, BFL’s returned credit charge, and the available-credit snapshots around the request. USD cost is derived using BFL’s published conversion of one credit to $0.01.
- BFL delivery URLs are treated as ten-minute links and removed from stored history after expiry.
- The BFL API key is stored as plaintext in the local JSON file with owner-only file permissions (`0600`). API routes use it server-side and return only whether a key exists to the browser.
- Settings shows the exact file path, file size, generation count, and last-write time. It can clear history, reset preferences, remove the API key, or delete the entire file.

Saving a finished video is a user-directed filesystem action; it is not app persistence.

## Provider architecture

- `lib/providers/` contains provider-neutral request contracts and UI capability metadata.
- `lib/providers/pricing.ts` dispatches provider-specific cost estimates and currency conversion.
- `lib/server/providers/` contains server-only adapters and error normalization.
- `lib/server/data-store.ts` owns the atomic local JSON-file reads and writes.
- `/api/generations` and `/api/generations/status` are provider-dispatched API routes.
- `/api/local-state` exposes sanitized local state and data-management actions.
- `/api/media` validates BFL delivery hosts and proxies range requests for playback and saving.

Add future providers by extending the provider ID and catalog, implementing a server adapter, and registering it in the server provider map.

## Verification

```bash
npm test
npm run lint
npm run typecheck
npm run build
```

The implementation follows BFL’s official [FLUX 3 video documentation](https://docs.bfl.ai/flux_3/flux3_video), [API reference](https://docs.bfl.ai/api-reference/utility/generate-a-video-with-flux-3), [pricing calculator](https://bfl.ai/pricing), and [polling integration guidance](https://docs.bfl.ai/api_integration/integration_guidelines).
