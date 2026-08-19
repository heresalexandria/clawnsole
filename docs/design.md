# Clawnsole design guide

Clawnsole is a midcentury studio console: walnut burl casework, stitched
leather panels, brass hardware, parchment paper, and a patient sloth's claw
for a maker's mark. Every screen should feel like furniture — warm, solid,
unhurried, and built from a small number of honest materials.

This guide is the contract for all surfaces (web, iOS, Android, macOS).
The tokens and components live in `flutter/lib/app/app_theme.dart` and
`flutter/lib/ui/panels.dart`; presentation code must draw from them rather
than inventing new colors or sizes.

## 1. Principles

- **Furniture, not chrome.** Structure comes from material panels (wood,
  leather, felt) and hairline outlines on warm paper — not from floating
  shadows and gray boxes.
- **Brass is jewelry.** The brass/gold tones mark small, precious things:
  the claw, eyebrows, stitching, icons, counts. Never large fills.
- **Plum acts, navy informs, green is money.** Primary actions and selected
  states are plum. Informational chips and in-progress states lean navy.
  The estimated-charge panel is hunter green, and nothing else is.
- **One calm pace.** Nothing pulses or slides far. Selection states animate
  ~140 ms; everything else just settles.
- **Capability is sacred.** Redesigns may reshape controls but never remove
  an input the provider supports. Prefer inference and disclosure over
  hiding features.

## 2. Materials

Bundled photography lives in `flutter/assets/textures/` and is applied only
through `TexturePanel` (`flutter/lib/ui/panels.dart`).

| Material | Asset | Used for |
| --- | --- | --- |
| Walnut burl | `wood_burl.jpg` | Side rail, mobile bottom nav |
| Plum leather | `leather_plum.jpg` | Settings feature panel, dark canvas grain |
| Navy leather | `leather_navy.jpg` | Provider plaque |
| Hunter felt (solid) | — | Estimated-charge panel |
| Cream linen | `linen_cream.jpg` | Light-mode canvas |

Rules:

- Panels are **always dark**, in both appearance modes, like the furniture
  they borrow from. Their content uses `tokens.onPanel` (cream),
  `tokens.onPanelMuted`, and `tokens.panelBrass` — never scheme colors.
- Leather panels may be **stitched** (`stitched: true`): a dashed brass
  thread inset 9 px, dash 5.5 / gap 4.5, 1.2 px wide at 45 % opacity.
- The photographs are hue-shifted toward the palette with a
  `BlendMode.color` tint declared per surface in `panels.dart`; do not
  re-tint at call sites.
- The page backdrop (`AppBackdrop`) lays a faint texture over the canvas
  color: linen at 55 % in light mode, leather grain at 12 % in dark mode.
- Textures were generated with OpenAI `gpt-image-1` (prompts in the session
  script `gen_textures.py` style: flat swatch, even light, no vignetting)
  and compressed to ≤ 420 KB JPEGs. Regenerate at 1024², then
  `sips -s format jpeg -s formatOptions 82`.

## 3. Color

Two `ColorScheme`s plus a `ClawnsoleTokens` theme extension. Key hex values
(complete set in `app_theme.dart`):

| Role | Light | Dark | Notes |
| --- | --- | --- | --- |
| Canvas | `#F1EBDE` linen | `#15100C` espresso | scaffold + backdrop |
| Surface (card) | `#FBF7ED` | `#211B15` | with `outlineVariant` hairline |
| Ink `onSurface` | `#29202F` | `#F1E9DB` parchment | |
| Muted `onSurfaceVariant` | `#60566A` | `#B9AB9B` greige | |
| Primary (action) | plum `#532B4E` | plum `#6E3D66` | buttons, selected tiles, sliders |
| onPrimary | cream `#FBF3E6` | cream `#FBF3E6` | |
| Secondary (info) | navy `#26405F` | mist `#AFC3E6` | working states, quiet links |
| Tertiary | brass `#7C5B22` | heather `#D9B4D0` | dark-mode text accents |
| Error | madder `#96342B` | `#F0B3A8` | |
| Tokens.brass | `#7C5B22` | `#D9B36C` | eyebrows, claw, icons, badges |
| Panel foregrounds | cream `#F3EAD9` / muted `#CFC1B0` / brass `#D9B36C` | same | on all panels |
| Hunter felt | `#2A4633` | same | cost panel only |
| plumInk | `#271E25` | same | video chrome, media ghosts, snackbar, tooltips |

Dark mode is deliberately a **warm evening study**: espresso neutrals with
no violet cast, so the wood, navy, green, and plum read as one room. In
dark mode, text-like accents (text buttons, outlined buttons, progress)
use `tertiary` heather because mid-plum fills lack contrast as text.

Contrast floor: body and label text ≥ 4.5:1 against its background;
decorative micro-caps ≥ 3:1 at 700 weight. Every selected control states
both its fill and its `on` color explicitly — never rely on defaults.

## 4. Typography

| Face | File | Role |
| --- | --- | --- |
| **Fraunces** (500/600 + italic) | `assets/fonts/Fraunces-*` | Display and headlines, stat numerals, wordmark |
| **DM Sans** (400/500/700) | `assets/fonts/DMSans-*` | Everything else |

Both families are vendored so every platform renders identically offline. They
are SIL Open Font License 1.1; the license texts ship beside them as
`assets/fonts/OFL-Fraunces.txt` and `assets/fonts/OFL-DMSans.txt`.

Scale (from `_textTheme`): display 46/38, headline 32/25/20 (Fraunces 600,
tight leading, slight negative tracking); titles 16.5/14.5/13 at 700; body
15/13.5/12; labels 13.5/12/11 at 700 with positive tracking.

- **Eyebrows** are 10.5 px, 700, +2.0 tracking, uppercase, brass.
- **Field labels** are 11 px, 700, +1.3 tracking, uppercase, near-ink, with
  a 16 px brass icon.
- Micro-type floor is **10 px**; the old 8–9 px annotations are banned.
- Weights stop at 700 — the w800/w900 "shouting" weights are not used.
- The version chip next to the wordmark is DM Sans **400** — the one
  deliberately light element in the top bar.

## 5. Shape, depth, spacing

- Radii: cards 16, panels 16, inputs/controls 11–12, chips 8–10,
  pills 999. Media wells clip at the card radius minus the border (15).
- Borders are hairline `outlineVariant`; shadows are soft and warm
  (6 % alpha, 18 blur, y-offset 6). Depth is suggestion, not drama.
- Spacing rhythm: 4-pt grid; 20 px card padding; 18–22 px between
  sections inside a card; 24–28 px page gutters (16 under 620 px).

## 6. Shell anatomy

- **Top bar (64 px):** brass claw + "Clawnsole" (Fraunces 21/19) as the
  home affordance, then the version chip (`v0.4.0`, light weight — opens
  the update dialog), then credits pill, API-key pill (wide only), and the
  appearance menu (System default / Light / Dark).
- **Side rail (≥ 900 px, 92 px wide):** walnut burl. App icon with a brass
  keyline on top; Create and Library; Settings alone at the bottom. The
  decorative claw that used to float above Settings is gone — the claw now
  lives in the wordmark and as accents.
- **Bottom nav (< 900 px):** the same burl, three labeled buttons with a
  cream-on-wood selected pill and brass count badge for working renders.
- Breakpoints: 900 (rail vs bottom nav), 1160 (create-screen split),
  1050 (settings split), 720/1180 (library 2/3 columns), 620 (gutters),
  640 (settings grid columns), 480 (composer footer stacks).

## 7. The composer (Create)

There are **no generation-mode tabs.** The form opens with the prompt and
reads what you attach; `GenerationFormState.mode` is derived:

1. draft cache attached → **Draft enhance**
2. starting video attached → **Video continuation**
3. any keyframes → **Image to video**
4. otherwise → **Text to video**

The current inference is always visible as a quiet chip beside the
Generate button. Layout order:

1. **Direction** — the prompt field (4–10 lines).
2. **Reference frames · optional** — thumbnail tiles (role tag, remove,
   URL/timing fields when relevant), three add buttons (First / Middle /
   Last, each offering *Upload an image* or *Paste an image URL*), and the
   Custom-timing pill. Provider rules are stated in one sentence under the
   header.
3. **"Or start from…"** — two quiet text buttons disclose the
   video-continuation and draft-enhance panels. An attached source
   collapses the irrelevant sections and explains what is set aside;
   removing it restores them. Draft enhance hides prompt/frames entirely
   (the original generation owns them) and shows only Finish + Safety.
4. **Frame** — the ratio strip: one tile per aspect ratio with a *drawn
   glyph of the actual shape* (bounded 28×18) plus label; Auto uses the
   free-crop glyph. Selected tile fills plum.
5. **Duration** — the slider is **always live**; dragging it immediately
   sets a fixed duration (clearing Auto), and the Auto pill re-enables
   provider choice. Layouts that require fixed timing disable Auto and say
   why.
6. **Finish** — HD / Full HD segmented pair, audio and fast-draft
   switches, safety-tolerance slider with `n / 4` readout.
7. **Estimated charge** — the stitched hunter-green panel: brass coin,
   credits range in Fraunces, USD in brass, balance before/after, basis
   note, rate-card link.
8. Footer — claw + readiness line, mode chip, plum **Generate video**.

## 8. Library & recent work

- Filter is a **segmented control** with icon + label + count per state
  (All / In progress / Ready / Needs attention). Selected = plum fill with
  cream icon and text — both modes were verified against the old
  unreadable-active-tab bug.
- Every card shows **all settings** as `GenerationSpecChips`: mode, ratio
  (with mini shape glyph), duration, resolution, audio, draft tier, timed
  keyframes.
- `ReferenceInputsStrip` shows 44 px thumbnails of each keyframe (and a
  chip for a video/draft source). Tapping opens the full-resolution viewer
  (zoomable) with **Download** and, for remote frames, **Open link**.
  Frames submitted inline and never retained say so honestly.
- `GenerationPrompt` shows the prompt with a **copy button** (one click →
  clipboard + snackbar) and a *Show full prompt / Show less* toggle that
  expands the entire direction in place.
- Status semantics: working = navy chip with spinner; ready = plum;
  needs attention / status unavailable = madder; exact provider charges
  render on plum containers, estimates on navy.

## 9. Version & updates

- The top-bar **version chip** opens a dialog that reports the running
  version and checks the latest GitHub release (through the Electron shell
  bridge when present, otherwise the public releases API).
- A newer release adds an **Update Available** chip beside the running version
  on wide layouts. Compact layouts and native mobile apps use a flash
  notification so the header remains responsive.
- Where the shell can install in place (packaged macOS), the dialog offers
  **Download and install**; elsewhere it links the release page (or notes
  App Store delivery on mobile).
- Any in-place update — from this dialog **or** the macOS *Check for
  Updates…* menu — surfaces a blocking **progress modal** with the
  download byte count and bar, then a verifying/installing state before
  the app reopens itself. The shell streams `downloading / installing /
  error` events over `window.clawnsole` (see `electron/preload.cjs`,
  `flutter/lib/core/shell_bridge*.dart`).
- `scripts/release/bump_version.py` keeps `pubspec.yaml`, the Electron
  package, and `lib/core/app_version.dart` on one version.

## 10. Voice

Calm, concrete, lightly warm. Headlines are short imperatives or plain
nouns ("Make it move.", "Your films.", "Room to stretch."). Body copy is
complete sentences that state what happens and why it is safe. No
exclamation points, no jargon-as-drama.

## 11. Accessibility checklist

- Selected/unselected states differ by more than hue (fill + outline +
  weight).
- Every icon-only control has a tooltip; frame thumbs describe role and
  timing.
- Keyboard: dialogs close on Escape; the video player keeps Space/Escape
  bindings; interactive rows are real `InkWell`s with focus states.
- Test both modes at 375 px and ≥ 1440 px before shipping UI changes;
  `flutter test` guards the narrow-width overflows that test fonts expose.
