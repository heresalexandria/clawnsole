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
- **Plum acts, navy informs, green is money — and "on."** Primary actions and
  selected states are plum. Informational chips and in-progress states lean
  navy. Green belongs to the estimated-charge panel and to the lit side of
  hardware switches; nothing else uses it. Green is the one family that
  **changes value between modes**: pale baize with hunter ink on paper, deep
  hunter felt with cream at night. It is never a large dark block in light
  mode.
- **Hardware is honest.** Values are set with real-feeling hardware — a
  machined knob in a recessed groove, metal toggles, counter-window
  readouts — echoing the app icon. No status lamps or ornament beyond the
  control itself.
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
| Walnut burl | `wood_burl.jpg` | Side rail, mobile bottom nav — casework, dark in both modes |
| Plum leather | `leather_plum.jpg` | Settings feature panel (dark mode), dark canvas grain |
| Navy leather | `leather_navy.jpg` | Provider plaque (dark mode) |
| Baize / hunter felt (solid) | — | Estimated-charge panel; follows the mode |
| Cream linen | `linen_cream.jpg` | Light-mode canvas, and the tooth on pale content panels |

Rules:

- **In light mode the only dark backgrounds are buttons and the rail / tab
  bar.** Nothing else — no card, panel, well, or readout — is a dark block on
  paper. `PanelSurface.isCasework` draws the line: the walnut burl is the
  cabinet the app is built into and stays dark in both modes; every other
  panel is *content* and follows the mode. A test walks all four surfaces and
  fails if a content panel is dark on paper.
- Content panels are pale on paper and dark at night: plum and navy become
  tinted panel colors under a whisper of linen weave (35 %), and the hunter
  felt becomes baize. At night they return to the leather photographs and
  deep felt.
- Ask a panel for its colors rather than reaching for tokens directly:
  `surface.ink(tokens)` returns `on` / `onMuted` / `accent` already resolved
  for that surface and mode. Casework keeps cream ink; content panels use ink
  on paper and cream at night. Every pair clears 4.5:1.
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
| Money surface | baize `#D6E3CB` | hunter felt `#2A4633` | estimated-charge panel |
| onMoney / muted | `#1D3325` / `#4A6152` | cream / cream-muted | text on the money panel |
| moneyAccent | brass `#7C5B22` | brass `#D9B36C` | coin ring, stitch, rate-card link |
| switchOn | signal `#4A7C55` | hunter `#2A4633` | lit side of a hardware switch |
| plumInk | `#271E25` | same | video chrome, snackbar, tooltips (media ghosts follow the mode) |

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

### Hardware controls (`flutter/lib/ui/hardware.dart`)

The value-setting controls are skeuomorphic console hardware, drawn in code
(no bitmaps) so they render identically on every platform and in both modes:

- **`HardwareSlider`** — a machined brushed-steel knob (knurled rim, sweep-
  gradient face, lit plum indicator line) traveling a recessed groove. The
  traveled side fills lit plum with a soft glow; divisions show as small
  in-groove tick dots. Replaces every Material slider.
- **`HardwareSwitch` / `HardwareSwitchTile`** — a metal handle sliding in a
  recessed pill well. The traveled side lights **hunter green** (the cost
  panel's `#2A4633`) when on; off is simply the empty well. No status lamps.
  The tile's whole row is tappable.
- **`CounterReadout`** — a recessed counter window (Fraunces numerals) that
  states a control's current value: duration (`10 s` / `AUTO`), frame rate
  (`3 fps`), safety (`2 / 4`).
- **`consoleKeyDecoration`** — selection tiles (ratio strip, resolution pair,
  library filters) read as console keys: a faint raised gradient when idle,
  a lit plum gradient with a soft glow when selected.

The grooves, wells, and readout windows are recessed into the surface they
sit on — shadowed warm cream with ink numerals in light mode, warm
near-black with cream numerals in dark mode — so light mode stays paper and
cream rather than sprouting reverse-type islands. The same rule covers media
ghosts (empty frame, reference, and library placeholders): they follow the
mode instead of always sitting on plum ink. Only the machined metal, the
navy plaque, the hunter cost panel, and a switch's lit green side stay dark
in light mode.

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
   header. Models that take pinned frames **or** creative references but
   never both (`framesExclusiveWithReferences`, the ArtCraft Seedance
   family) say so up front; attaching one side quietly sets the other aside
   with an explanation, and a conflicted form (via reuse or a model switch)
   warns in madder and cannot submit.
3. **"Or start from…"** — two quiet text buttons disclose the
   video-continuation and draft-enhance panels. An attached source
   collapses the irrelevant sections and explains what is set aside;
   removing it restores them. Draft enhance hides prompt/frames entirely
   (the original generation owns them) and shows only Finish + Safety.
4. **Frame** — the ratio strip: one tile per aspect ratio with a *drawn
   glyph of the actual shape* (bounded 28×18) plus label; Auto uses the
   free-crop glyph. Selected tile fills plum.
5. **Duration** — the knob slider is **always live**; dragging it
   immediately sets a fixed duration (clearing Auto), and the Auto pill
   re-enables provider choice. The counter readout beside the label states
   the current value (`10 s`, or `AUTO`). Layouts that require fixed timing
   disable Auto and say why.
6. **Finish** — HD / Full HD console keys, audio and fast-draft hardware
   switches (lit hunter green when on), safety-tolerance knob with an
   `n / 4` readout.
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
