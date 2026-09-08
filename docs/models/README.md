# Clawnsole provider catalog

`https://clawnsole.app/models/` is Clawnsole's remotely managed provider and
model catalog. `index.html` is YAML-compatible JSON so GitHub Pages serves the
directory endpoint directly. It points to one manifest per provider, and each
provider points to one manifest per model. Paths must stay relative to this
directory.

The root also carries `catalog_version`, the newest app release whose test
status it can authoritatively answer, and `test_versions`, the mobile releases
currently using the review-only capability profile. Advancing both fields in
the same release commit prevents an older Pages deployment or device cache
from accidentally unlocking a new review build.

The app fetches the complete graph atomically. It validates every referenced
manifest before replacing the active catalog, stores the last valid graph in
the device-local Clawnsole data file, and falls back to that cache or the
catalog compiled into the build when Pages cannot be reached. The Electron
renderer passes the same validated graph to its local companion so UI and
request routing use the same definitions.

## Version availability

Providers and models accept the same optional `availability` mapping. Bounds
are inclusive and use the synchronized semantic app version from
`flutter/lib/core/app_version.dart`, which the release workflow updates with
the Flutter and Electron package versions.

```yaml
availability:
  min_version: 0.42.0
  max_version: 0.49.9
```

To target exactly one release:

```yaml
availability:
  version: 0.43.1
```

`version`, `min_version`, and `max_version` may be combined, although an exact
version is normally used by itself. Omit `availability` to expose the entry to
every app version. All manifests in the baseline catalog omit it.

## Mobile test releases

Add the optional `mobile-test` label alongside the PR's one required release
impact label. The release workflow advances `catalog_version`, adds the new
release version to `test_versions`, and compiles the `ARTCRAFT_TEST_KEY` Actions
secret only into that release's iOS build. The same mobile build defines are
supported by `flutter/scripts/build_android` for signed Android AAB builds.

A mobile-test build exposes ArtCraft → Seedance 1.5 Pro → 480p → 5
seconds plus any manifest-defined `apple-local` provider. The Apple provider
is still filtered by the native platform boundary, so Android exposes only the
ArtCraft route while supported iOS devices also expose Apple Image and Apple
Image Sequence. Its bundled fallback is already restricted, and any catalog
older than the app remains restricted. Desktop binaries ignore
`test_versions`.

After store review, remove the version from `test_versions` and deploy Pages.
For example:

```bash
python3 scripts/release/set_mobile_test_version.py 0.42.0 --remove-test
```

On the next successful startup refresh, that installed mobile version restores
every otherwise-compatible provider/model and stops using the compiled test
credential. The refreshed state is cached, so later offline launches remain
unlocked. If Pages is unavailable before that successful refresh, the app
keeps its last known restricted state.

## Adding entries

A model manifest carries the complete provider-neutral UI and request
capability contract: modes, geometry, duration, references, pricing, and other
feature switches. Add its relative path to the owning provider's `models`
list. Remove that path to stop exposing the model after the Pages deployment.

`max_input_image_pixels` and `max_input_image_bytes` record safe per-image
provider/model ceilings for pinned frames and creative image references. Leave
headroom below a provider's raw limit when its downstream image pipeline pads
or aligns dimensions, and below decoded-byte limits when it expands a base64
data URI. When reference normalization is enabled, Clawnsole decodes the
complete oriented image and proportionally downscales only images that exceed
a ceiling; it never crops them. Omit the fields for recommendations,
output-resolution limits, or provider-side automatic resizing that does not
establish a dependable input ceiling.

`max_reference_video_seconds` and `max_reference_audio_seconds` are aggregate
input budgets across the attached clips of that type. They are independent of
the output `max_duration`. If a remote or cached manifest omits one of these
budgets, the app uses the compiled budget for the exact same provider ID and
model route, provided that input type is still enabled. Explicit manifest
values and resolution overrides take precedence. Unknown routes and matching
display names or model families do not inherit another route's budget.
Omitted resolution-budget mappings also retain the compiled mapping; an
explicit mapping, including an empty one, replaces it completely.

Krea's `bytedance/seedance-2-5` has a 30-second aggregate reference-video
compatibility fallback. [Krea's API guide](https://www.krea.ai/blog/seedance-2-5-api-access-guide-features-code-examples-for-long-form-video)
publishes the 10-video count and a separate 4–30-second **output** duration;
it does not state an aggregate input duration. The fallback was selected for
Clawnsole's Seedance 2.5 compatibility behavior, corroborated by
[Pika's Seedance 2.5 input contract](https://dev.pika.art/models/bytedance/seedance-2.5/reference-to-video),
which explicitly caps combined reference video at 30 seconds. This is a
fallback, not a claim that Krea's API declares the limit. Krea's unpublished
audio budget and other models' unpublished totals remain unspecified; do not
derive them from output durations or reference counts.

A provider manifest also declares an `adapter`. A catalog update can add a new
provider ID without an app release when it uses a wire adapter already present
in that app build: `apple-local`, `artcraft`, `atlas`, `bfl`, `krea`, `ltx`, or
`runway`. `apple-local` is implemented only by the native iOS app. A genuinely
new API protocol still requires an app release that implements its adapter;
older builds safely ignore providers whose adapter they do not understand.

Keep `schema_version: 1` on the index and every manifest. Invalid schemas,
unsafe or cross-origin paths, malformed values, duplicate IDs, and catalogs
with no compatible providers are rejected without replacing the prior catalog.
