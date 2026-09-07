# Clawnsole design guide

Clawnsole is a midcentury studio console: walnut burl casework, stitched
leather panels, brass hardware, parchment paper, and a patient sloth's claw
for a maker's mark. Every screen should feel like furniture: warm, solid,
unhurried, and built from a small number of honest materials.

This guide is the contract for all installed surfaces (iOS, Android, native
Windows, and Electron macOS). Flutter web is the internal Electron renderer.
The tokens and components live in `flutter/lib/app/app_theme.dart` and
`flutter/lib/ui/panels.dart`; presentation code must draw from them rather
than inventing new colors or sizes.

## 1. Principles

- **Furniture, not chrome.** Structure comes from material panels (wood,
  leather, felt) and hairline outlines on warm paper, not from floating
  shadows and gray boxes.
- **Brass is jewelry.** The brass/gold tones mark small, precious things:
  the claw, eyebrows, stitching, icons, counts. Never large fills.
- **Plum acts, navy informs, green is money and "on."** Primary actions and
  selected states are plum. Informational chips and in-progress states lean
  navy. Green belongs to the estimated-charge panel and to the lit side of
  hardware switches; nothing else uses it. Green is the one family that
  **changes value between modes**: pale baize with hunter ink on paper, deep
  hunter felt with cream at night. It is never a large dark block in light
  mode.
- **Hardware is honest.** Values are set with real-feeling hardware: a
  machined knob in a recessed groove, metal toggles, counter-window
  readouts that echo the app icon. The footer's Generate key and model
  selector are **1960s command-center hardware** — a matte backlit
  push-button indicator and a segment-display readout — never glossy
  web plastic: no specular bands, no bloom, no gradients that only a
  screen could show. No status lamps or ornament beyond the control
  itself.
- **One calm pace.** Nothing pulses or slides far. Selection states animate
  ~140 ms; everything else just settles. The single exception is physical:
  the Generate key's incandescent lamps breathe, flicker and sag while a
  submission is in flight, because a real lamp on a real supply does. It is
  the only thing in the app that moves on its own, it is a property of the
  hardware rather than an attention-getter, and it stops the moment the
  console stops working.
- **Capability is sacred.** Redesigns may reshape controls but never remove
  an input the provider supports. Prefer inference and disclosure over
  hiding features.

## 2. Materials

Bundled photography lives in `flutter/assets/textures/` and is applied only
through `TexturePanel` (`flutter/lib/ui/panels.dart`).

| Material | Asset | Used for |
| --- | --- | --- |
| Walnut burl | `wood_burl.jpg` | Side rail and mobile bottom nav; casework, dark in both modes |
| Plum leather | `leather_plum.jpg` | Settings feature panel (dark mode), dark canvas grain |
| Navy leather | `leather_navy.jpg` | Reserved — the model plaque wore it until the footer became console hardware; no panel uses it today |
| Baize / hunter felt (solid) | None | Estimated-charge panel; follows the mode |
| Cream linen | `linen_cream.jpg` | Light-mode canvas, and the tooth on pale content panels |

Rules:

- **In light mode the only dark backgrounds are buttons and the rail / tab
  bar.** Nothing else (no card, panel, well, or readout) is a dark block on
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
both its fill and its `on` color explicitly; never rely on defaults.

## 4. Typography

| Face | File | Role |
| --- | --- | --- |
| **Fraunces** (500/600 + italic) | `assets/fonts/Fraunces-*` | Display and headlines, stat numerals, wordmark |
| **Courier Prime** (400/700 + italic) | `assets/fonts/CourierPrime-*` | The Direction/prompt entry — the director's typewriter voice (`promptFontFamily`) |
| **DM Sans** (400/500/700) | `assets/fonts/DMSans-*` | Everything else |
| **DSEG14 Classic** (400/700) | `assets/fonts/DSEG14Classic-*` | The model selector's fourteen-segment readout only (`segmentDisplayFontFamily`) — never for prose |

All families are vendored so every platform renders identically offline. They
are SIL Open Font License 1.1; the license texts ship beside them as
`assets/fonts/OFL-Fraunces.txt`, `assets/fonts/OFL-CourierPrime.txt`, and
`assets/fonts/OFL-DMSans.txt`.

Scale (from `_textTheme`): display 46/38, headline 32/25/20 (Fraunces 600,
tight leading, slight negative tracking); titles 16.5/14.5/13 at 700; body
15/13.5/12; labels 13.5/12/11 at 700 with positive tracking.

- **Eyebrows** are 10.5 px, 700, +2.0 tracking, uppercase, brass.
- **Field labels** are 11 px, 700, +1.3 tracking, uppercase, near-ink, with
  a 16 px brass icon.
- Micro-type floor is **10 px**; the old 8–9 px annotations are banned.
- Weights stop at 700; the w800/w900 "shouting" weights are not used.
- The version chip next to the wordmark is DM Sans **400**, the one
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

- **`HardwareSlider`**: a machined brushed-steel knob (knurled rim, sweep-
  gradient face, lit plum indicator line) traveling a recessed groove. The
  traveled side fills lit plum with a soft glow; divisions show as small
  in-groove tick dots. Replaces every Material slider.
- **`HardwareSwitch` / `HardwareSwitchTile`**: a metal handle sliding in a
  recessed pill well. The traveled side lights **hunter green** (the cost
  panel's `#2A4633`) when on; off is simply the empty well. No status lamps.
  The tile's whole row is tappable.
- **`HardwareChoiceSwitch`**: a labeled two-position control whose selected
  option rides on a brushed-metal carriage inside a recessed well. It is used
  for mutually exclusive hardware choices such as Auto / Manual duration.
- **`CounterReadout`**: a recessed counter window (Fraunces numerals) that
  states a control's current value: duration (`10 s` / `AUTO`), frame rate
  (`3 fps`), safety (`2 / 4`).
- **`consoleKeyDecoration`**: selection tiles (ratio strip, resolution pair,
  library filters) read as console keys: a faint raised gradient when idle,
  a lit plum gradient with a soft glow when selected.
- **`HardwareLitButton`** (`hardware_button.dart`): the Generate key — a
  1960s command-center **push-button indicator**: a frosted, matte,
  translucent plum lens seated in a thin charcoal bezel with a dark gap
  around it, its legend engraved in capitals (DM Sans 700, 12 px, tracked
  1.9) and white-filled, the claw inked the same. Two incandescent lamps
  behind the diffuser light it — the lens glows plum-magenta with two soft
  hot spots — on pointer-down and while the **submission** is in flight,
  i.e. until the provider accepts the job; once the render is running the
  key returns to its unlit, pressable state (there is no spinner).
  The lamps behave like lamps, and two lights live in the cap that are not
  the same light. A finger on the key raises only the cap's own dim
  **contact glow** (30 % of full, 120 ms); the **lamps** answer `lit`
  alone, so the whole warm-up is still ahead of them when the job goes out
  and a press that never becomes a submission never moves them. The
  filament warms over ~340 ms, flaring ~7 % past its working brightness at
  ~185 ms — a cold wire is a poor resistor — before settling exactly on it;
  switched off it loses half its light in 50 ms and three quarters by
  100 ms, then hangs on as an ember out to ~600 ms. While lit it
  **breathes**: about 1.2 a second, eased so it dwells at the top and the
  bottom, down to roughly three quarters of steady and back
  (`HardwareLitButtonState.filament`, ~0.71–1.03), with the fine wander of
  an imperfect supply over it and a deeper sag now and again. The two hot
  spots lead and the whole block follows ~55 ms behind them
  (`filamentBody`), because that is the order light reaches a diffuser in.
  The filament ticks only while there is light in the lens, so a dark
  console schedules no frames. Keyboard focus wears the brass halo. No
  specular band,
  no gloss, no bloom: real lenses are matte and spill almost no light.
  Plum in both modes — a button is allowed to stay dark on paper.
- **`HardwareSelector`** (`hardware_selector.dart`): the model selector —
  the console's **alphanumeric readout**: a charcoal bezel held by four
  slotted screws around a recessed display window, and a separate square
  satin-metal key with an engraved chevron that steps the selection. The
  window shows the provider and model on two rows of a fixed eighteen-cell
  fourteen-segment display (`SegmentReadout`, DSEG14 Classic), with the
  unlit segments faintly visible behind the lit ones (`ghostRow` mirrors
  the narrow period and space cells so the rows stay registered). It
  follows the mode: lit ice-blue segments on smoked glass at night, an
  unlit liquid-crystal pane with dark segments on pale glass on paper.
  Text is upper-cased and reduced to what fourteen segments can form
  (`segmentDisplayText`). It carries no gesture of its own; the wrapping
  `PopupMenuButton` owns the tap. Both footer controls share
  `kConsoleControlHeight` (56 px, growing past ~1.25× text scale).

The grooves, wells, and readout windows are recessed into the surface they
sit on: shadowed warm cream with ink numerals in light mode, warm
near-black with cream numerals in dark mode, so light mode stays paper and
cream rather than sprouting reverse-type islands. The same rule covers media
ghosts (empty frame, reference, and library placeholders): they follow the
mode instead of always sitting on plum ink. Only the machined metal and
charcoal bezels, the plum Generate key (a button), and a switch's lit green
side stay dark in light mode — the selector's display becomes an unlit LCD
on paper.

## 6. Shell anatomy

- **Top bar (64 px):** brass claw + "Clawnsole" (Fraunces 21/19) as the
  home affordance, then the version chip (`v0.4.0`, light weight; opens
  the update dialog), then credits pill, API-key pill (wide only), and the
  appearance menu (System default / Light / Dark).
- **Side rail (≥ 900 px, 92 px wide):** walnut burl. App icon with a brass
  keyline on top; Create and Library; Settings alone at the bottom. The
  decorative claw that used to float above Settings is gone; the claw now
  lives in the wordmark and as accents.
- **Bottom nav (< 900 px):** the same burl, three labeled buttons with a
  cream-on-wood selected pill and brass count badge for working renders.
- Breakpoints: 900 (rail vs bottom nav), 1050 (settings split),
  720/1180 (library 2/3 columns), 620 (gutters), 880 (composer pairs
  the guidance accordions with the settings column, and the cost +
  destination row), 330 (Frame/Finish dropdowns stack instead of
  sharing a row), 640 (composer footer stacks). A viewport under 950 px
  tall switches the create screen into a dense mode (no first-run
  guidance line, tighter gaps).

## 7. The composer (Create)

There are **no generation-mode tabs.** The form opens with the prompt and
reads what you attach; `GenerationFormState.mode` is derived:

1. draft cache attached → **Draft enhance**
2. starting video attached → **Video continuation**
3. any keyframes → **Image to video**
4. otherwise → **Text to video**

The inference shows in the cost panel's summary line (`Text`, `Image`,
`Video`…); the footer carries no mode chip and no readiness line — a ready
console says nothing, and the lit Generate key is the signal.

**Model selector:** a shared searchable picker — `showProviderModelPicker`
in `provider_model_picker.dart` — opened as a modal dialog rather than a
contextual popup, so more than one control can raise the same component:
the console readout in the footer (`HardwareSelector`: charcoal bezel with
corner screws, a fourteen-segment display of provider and model, a square
chevron key) and the text trigger in the Direction header both open it,
and they share one memory of which provider sections are folded. The
search field is the header — it takes focus on desktop, where the director
can type at once, and not on iOS or Android, where the keyboard would
cover the list — with a small close key beside it for the platforms that
have no Escape. Each **provider heading is a burlwood facing** —
`BurlwoodSlice` / `BurlwoodCut` in `panels.dart` — 50 px tall, its name in
12.5 px w800 capitals tracked 1.2, cut from its own patch of the sheet: the
patches are handed out from a stable hash of the provider id and no two
touching headings may come off patches within two rows of each other, so
the figure breaks at every joint instead of running through it (a hairline
kerf and its lit edge mark the cut). The FAVORITES heading is faced from
the same run — it is the same kind of thing, and one pale bar among wooden
ones would read as a slip — while the model rows beneath keep the dialog
surface. This is casework, so **the headings stay dark in light mode**: the
owner asked for the rail's wood here specifically, which makes them a
sanctioned exception to "in light mode the only dark backgrounds are
buttons and the rail / tab bar". Their content takes
`PanelSurface.burlwood.ink(tokens)`, and the tappable heading brings its own
transparent `Material` so the ripple lands on the wood rather than behind
it. Every model row and provider heading carries a small star
(brass when lit); starred models pin into a **FAVORITES** section at the top of
the picker (model + provider name, one tap to select), starred providers'
sections sort first and open expanded, and the Providers desk groups the
same starred providers under a *Favorites* eyebrow. Stars live in
preferences (`favoriteModels` as `provider|model` keys, `favoriteProviders`),
so they follow the settings vault across devices.

Layout order:

1. **Direction**: the prompt field (4–10 lines), set in bundled Courier
   Prime — the typewriter voice for anything the director types. A quiet
   clear control sits directly after the label (disabled while empty) and
   asks before wiping the text; the live counter, copy, and fullscreen
   controls keep the header's far end. Right of the clear key a quiet
   text trigger names the current *model* with a small chevron and opens
   the same picker modal as the footer's selector — header type, not the
   machined plaque, so the model can be changed without leaving the
   prompt. It does not repeat the provider (the footer readout names it),
   though the screen reader hears both. The header is one row at every
   width, a phone included: the format picker is sized to its own widest
   word rather than a fixed slab, the trigger takes what the model name
   needs and clips it only when a row truly cannot hold it, and on a
   phone row the character counter takes a compact reading (`0 / 50k`,
   exact figures in its tooltip) so the name is spelled whole at 390 pt.
   It rides along into the fullscreen editor. Once a character is cast
   or written into a script, typing the first letters of its name
   suggests the cast in the same menu the `@` mentions use — Up/Down to
   choose, Return, Tab or a tap to take it — and writes the name as
   plain text, with no tag and no highlight. Escape dismisses it for
   that word, and a screenplay cue line keeps its own completions.
2. **Cast row**: a compact strip between the direction and the guidance /
   settings pair, present only when a character actually holds a
   reference on a model that accepts creative references. A brass label,
   then one chip per cast member — up to three overlapping 26-pixel
   thumbnails of its media, a "+n" spillover, and the name — each opening
   the mapping editor; a small pencil and × inside each chip recast or
   uncast that character in place (the media stays in the References
   tray). A quiet *Add character* ends the row. The casting
   itself never appears in the prompt box; it is appended silently at
   submission, so an uncast composer keeps the heading through Generate
   above the fold.
3. **Aesthetic Definition accordion**: present only when a draft has an
   aesthetic — one chosen, or a custom definition of its own. A collapsible
   row in the guidance construction (`aesthetic-accordion-toggle`) sitting
   between the cast and the keyframes/references pair, with the aesthetic's
   icon, one flat line of its words, and its name as the status word. The
   body is the definition itself in an editable field. **Editing it never
   touches the saved aesthetic**: the draft becomes **Custom** — the
   Aesthetic key in the Direction toolbar says so on its single row, and the
   picker adds a *Custom* entry naming what it was edited from. Three ways
   out sit under the field: *Save as new…* (the aesthetic editor, prefilled,
   and the draft switches to the new aesthetic), *Update “name”* (writes the
   words back over the original after asking, so every draft using it moves
   together), and *Revert*. Choosing another aesthetic while a custom
   definition is open asks once before replacing it; *No aesthetic* clears
   both. The custom text is part of the draft — it persists per tab, crosses
   a relaunch, and makes an otherwise empty tab count as occupied. Typing
   here follows the Direction field's contract: no keystroke rebuilds the
   studio.

   **Reuse restores the aesthetic as a choice, never as prompt text.** A
   generation records what it appended (`aestheticReferenceId`,
   `aestheticTitle`, `aestheticText`), so reopening it lifts that block back
   out of the prompt and puts the choice where it was made: the same words
   select the aesthetic again; words the library has changed since come back
   as a **Custom** definition with the original aesthetic still selected; a
   deleted aesthetic leaves the definition alone in the accordion. A film
   rendered before this was recorded is only read that way when its last
   paragraph is still, word for word, a saved aesthetic — anything else stays
   in the prompt exactly as it was sent. Reuse into a new tab and the film
   modal's Reuse take the same door. An AI Rewrite answers with the whole
   prompt, aesthetic and all: the choice survives only when those words come
   back word for word, so nothing is ever appended to a rewrite twice.
4. **Keyframes / References accordions**: the two guidance sections are
   collapsible rows stacked in one column (paired beside the settings
   column at ≥880 px). A collapsed header carries the section name, tiny
   thumbnails of what is attached, and a status word (*None* / *n
   attached* / *Set aside*); the body holds the tiles (role tag, remove,
   URL/timing fields), capacity gauges, provider rules, add buttons, and
   the Custom-timing pill. Media arriving through any path (picker, URL,
   drop, reuse) opens its section; the whole References accordion stays a
   drop target. From the moment a picker opens or a drop lands, a
   **loading tile** with a spinner holds the exact spot the new card will
   occupy (`pendingFrameAdds` / `pendingReferenceAdds` — keyframes keep
   theirs through the whole pick-and-retain pipeline), and a draft picked
   from References wears a spinner veil while its media bytes hydrate. Models that take pinned frames **or** creative references
   but never both (`framesExclusiveWithReferences`, the ArtCraft Seedance
   family) say so inside the body; attaching one side quietly sets the
   other aside, and a conflicted form (via reuse or a model switch) pins
   both accordions open, warns in madder, and cannot submit. The
   *Normalize visual references* switch applies to both sections, so it
   sits below the pair.
5. **"Or start from…"**: two quiet text buttons under the accordions
   disclose the video-continuation and draft-enhance panels. An attached
   source collapses the irrelevant sections and explains what is set
   aside; removing it restores them. Draft enhance hides prompt/frames
   entirely (the original generation owns them) and shows only Finish +
   Safety.
6. **Frame**: a console-key ratio dropdown whose trigger and menu rows
   keep the *drawn glyph of the actual shape* plus label and hint; Auto
   uses the free-crop glyph. Frame and Finish share one dropdown row at
   every width above 330 px, so phones stop spending a full row on each.
7. **Duration**: Manual is the default. Models that support provider-selected
   duration show a brushed-metal Auto / Manual switch; models without that
   capability show no Auto option. Manual shows the model- and
   resolution-specific slider range. Auto replaces the slider with the same
   possible-duration range in prose. The counter readout beside the label
   is an editable recessed field (`CounterReadoutField`): type a number
   and it commits clamped to the range on blur/submit; focusing it while
   AUTO is lit drops to Manual, like touching the slider. Layouts that
   require fixed timing lock the switch to Manual and say why.
8. **Finish**: a console-key resolution dropdown (label + pixel detail
   per row; draft mode dims tiers above HD) on the Frame row, then audio
   and fast-draft hardware switches (lit hunter green when on),
   safety-tolerance knob with an `n / 4` readout, and — for models whose
   API takes one — a **Seed** field with a dice button (empty = random),
   all stacked in the single settings column.
9. **Estimated charge + Save generation to**: side by side in one row at
   desktop widths. The stitched hunter-green panel keeps the brass coin,
   credits range in Fraunces, USD in brass, balances, and rate-card link
   in a single console row; the destination panel is one row of storage
   chips, the folder dropdown, and a new-folder icon button.
10. Footer: the console **model selector** (provider + model on a
   fourteen-segment readout in a screwed charcoal bezel, chevron key;
   opens the shared picker dialog) directly before the backlit
   **GENERATE VIDEO** push-button indicator, shoulder to shoulder at 56 px.
   A status line appears only when something blocks a render (API key
   missing, this device cannot run the local model). Under 640 px the
   selector and the key stack, each spanning the composer.

**Fold contract:** the heading and the whole composer, Generate button
included, fit above the fold at 1440×900, with the Recent work header
visible beneath — enforced by a widget test. Recent work always sits
below the composer (the old ≥1160 side column is gone).

**Tabs are workspaces, not modes, and they are the heading.** Create has
no display headline: a quiet eyebrow names the studio (*Video studio* /
*Video finishing studio* / *On-device image studio*), and beneath it runs
the **tab rail** (`ComposerTabRail`) — folder tabs (rounded shoulders,
flat foot) standing on a hairline rule that runs from the last tab to the
edge. Idle tabs are raised console keys resting on the rule with muted
labels; the tab in front is **not a lit button**: it is cut from the
composer card's own paper, stands a touch taller, wears a 2 px brass lip
along its top, and covers the rule beneath it, so the open draft reads as
continuous with the composer (owner rejected a plum-filled active tab as
"looks like a button"). On touch platforms tabs are a little taller
(~38–40 pt) so the tab itself is the target; the pencil and × inside keep
modest hit areas and never stretch the tab past its neighbours.
Each tab is a complete, independent draft — Direction, provider and model,
every setting, attachments, and the save-to folder — so several films can be
worked on side by side. A "+" tab opens a blank draft using the active tab's
provider, model, and folder plus the last-used controls for that provider/model;
the × on a tab closes it (the last
tab is replaced by a blank one); long-press or double-tap renames. Labels
derive from the first words of the prompt until renamed. Reuse and Enhance
fill the active tab when it is still pristine and otherwise open a new tab.
Attachments, pending picks, a name, aesthetic selection, and settings edits
make a draft occupied even before any direction is typed. A tab born from AI Rewrite wears a small brass
`auto_awesome` mark whose tooltip is the model's one-line summary of what
changed. The model plaque is not in the heading at all: it sits in the
composer footer directly before Generate (see item 10), inside the draft it
belongs to. Phones drop the eyebrow and keep just the rail; the first-run
bring-your-own-key line sits under the rail when no provider is set up.
Tabs persist locally and sync with the Drive workspace when connected;
the active tab selection stays local. Each saved draft keeps its own compact
media recipe so removing an input stays removed on relaunch. Legacy drafts
can still restore from their source generation. Unretained uploads are
session-only: the rail identifies them before the app closes. Save failures
stay visible beneath the rail with a Retry action; an unreadable workspace
is not overwritten by a new session.

Last-used controls are separate from draft content: ratio, duration and Auto,
resolution, audio, frame rate, draft quality, safety, timing, and upscale controls
are remembered per provider/model. Blank tabs leave Direction, format, seed,
references, aesthetic selection, and source media empty. Editing only an older
tab's prompt does not replace newer remembered controls. Explicit control edits
and Generate update defaults; choosing another model restores its own defaults
and checks them against current capabilities. Settings writes are coalesced while
dragging controls and flushed on tab actions, backgrounding, and disposal. The
versioned scalar records travel through the existing preferences and encrypted
settings sync. Migration reads meaningful older drafts and generation history
without displacing settings still arriving from another device.

Closing a tab keeps the ten most recent recovery snapshots. The restore
control beside the new-tab key opens a named list of closed drafts. Recovery
opens a new tab id, preserving the original close tombstone across devices.
Open and recoverable draft assets stay protected during cleanup. The
generation-mode rule above still stands — tabs never select a mode.

## 8. Library & recent work

- The toolbar is **one quiet row**: console-key **media-type segments**
  (All / Video / Image on the Library, All / Image / Video / Audio on
  References; icon + label + count), a search field, a **Filters** console
  key, and the view toggle (References: a sort key instead). The segment
  counts are *facet counts* — they honour every other active filter, so
  they describe what is in the folder in view. Selected segments = plum
  fill with cream icon and text; both modes were verified against the old
  unreadable-active-tab bug. Narrow layouts stack the search above the
  segment row and shrink Select to an icon key.
- **The References desk is three folder tabs** — *Media*, *Aesthetics*,
  and *Characters*, with facet counts — standing on a hairline rule that closes the pinned
  heading under *Your creative ingredients.* They are the Create draft
  rail's construction (`SectionTabRail`, `lib/ui/section_tabs.dart`) cut
  larger: idle tabs are raised console keys on the rule, the open desk is
  cut from the surface beneath it with a brass lip and covers the rule,
  never a lit button. Both tabs keep the same 1440-px column and padding,
  so switching never shifts the heading. The aesthetic half
  replaces the folder rail with one scrolling column, which is what keeps a
  long aesthetic list scrollable instead of growing the pinned heading;
  dropped files still only ever mean media.
- **The aesthetic library follows the one-row toolbar pattern**
  (`lib/ui/aesthetic_library.dart`): All / Starred facet segments, one
  search field over titles, text, and tags, a **Tags** console key popover
  (`#tag · count` chips plus *Reset filters*), and the *Add aesthetic* key.
  Rows are one card of hairline-separated lines — line icon, title, brass
  star toggle, tag pills (four, then *+n*), two lines of the reference
  text, and a pencil. Starred entries lead, then titles A→Z. On Create the
  aesthetic key opens a searchable anchored panel with the same ordering:
  *No aesthetic*, a **Favorites** group, then **All**, each row starring in
  place without closing the panel, and a *Manage aesthetics…* footer that
  opens this tab. A draft whose definition was edited in the composer leads
  the panel with a **Custom** row naming the aesthetic it grew out of (see
  §7, item 3); the library itself is never edited from Create without
  being asked.
- **The Characters tab manages the name→media mappings Create casts**
  (`lib/ui/character_library.dart`, `lib/app/app_controller_characters.dart`).
  A character *is* saved media: the reference carrying a `characterName`
  assignment, plus any saved file already called that name, which Create casts
  beside it — so a row shows overlapping cast thumbnails, the cue-style name, a
  reference count, and a ⋯ menu (*Edit character*, *Release @card*, *Delete
  character*). The toolbar keeps the one-row pattern: All / Unassigned facet
  segments, one search over character and reference names, and a **New
  character** key. The editing sheet names the character and picks the
  reference that carries the name; because an assignment is unique across
  references, choosing another moves it rather than failing at the storage
  boundary, and the sheet names the files that will be cast alongside it. An
  **Unassigned** section lists media no character has claimed, each row
  offering the name its own file implies. *Delete character* only clears the
  assignment — the media never leaves References. Every write goes through
  `updateSavedReference`, so Drive, the local store, prompt tags, and the
  composer stay in step, and a batch speaks once (“VINCE renamed to VINNIE
  across 1 reference.”). Per-draft casting is untouched: the Cast row and the
  Characters modal on **Create** still own that draft's `characterMappings`,
  and a library rename leaves an open draft's cast exactly as it was.
- **Filters popover** (`LibraryFilterButton`): status, favorites, and tags
  live in an anchored panel instead of stacked chip rows. The key lights
  plum with a count while any of them narrows the view, and the panel
  offers *Reset filters*. The References toolbar shares the same pattern.
- **Storage lives with the folders** (`StorageSidebarSection`): the left
  rail leads with All storage / On this device / Google Drive rows and
  per-storage counts, above the folder tree; narrow layouts get the same
  rows in the folder sheet. The Drive row carries the connection state
  and a brass *Reconnect* action when a configured session is signed out.
  Narrow layouts open that sheet from a **console-key folder dropdown**
  that hugs its label (bordered key, count, chevron) — a control, not a
  full-width heading — on both Library and References.
- **The folder rail is a file manager, not a list**
  (`lib/ui/library_folders.dart`, shared by both collections through
  `FolderScope`): on wide layouts the heading and rail are **pinned** while
  the results scroll on their own, so folders never drift off-screen.
  Branches **collapse** behind chevrons (session state; choosing or moving a
  folder reopens its ancestors). *New folder*, *New subfolder*, and *Rename*
  are **editor rows in place** (Enter saves, Esc cancels, blur saves like
  Finder; a top-level row offers a device/Drive toggle when both storages
  exist) — no modal. Each row's ⋯ menu appears on hover or selection
  (always on touch) and also opens on right-click / long-press; *Move to…*
  is the only dialog, and it is the same tree limited to the folder's
  storage without its own branch. **Drag and drop**: cards (the whole
  selection when the card is part of one) and folder rows drop onto folder
  rows or *Unfiled*; a mouse drags at once, a finger long-presses first so
  lists still scroll; the target lights plum, a closed branch opens after a
  moment of hovering, and cross-storage or into-own-branch drops are simply
  not accepted. The item **move dialog** reuses the tree and can grow a new
  folder in place.
- **Drive reconnects itself at startup** (`resumeGoogleDrive`): the
  companion and shell hold Drive sessions per process, so the controller
  quietly reattaches a previously configured connection on launch using a
  silent grant (stored refresh token on desktop, lightweight sign-in on
  mobile) — never an interactive prompt. When no silent grant exists, a
  `DriveReconnectNotice` card under the Library/References toolbar says
  Drive work is hidden (not lost) and offers *Reconnect*.
- **No Ready chips on cards**: a delivered thumbnail already says ready,
  so `StatusBadge` renders nothing for ready work and only appears for
  in-progress, failed, or status-unavailable items.
- Card actions stay light: the primary verbs (**Save**, **Reuse/Retry**,
  **Check status**, and — once an AI Rewrite key is saved — **AI Rewrite**
  on delivered films) are buttons; everything else (Organize, Enhance,
  **Extend**, Copy to Drive, View details, Delete) folds into the shared
  `GenerationActionsMenu` (⋯), which also lists AI Rewrite for the dense
  card sizes. The cost readout is a compact amount chip
  (`GenerationCostChip`) on the same row — just the credit or dollar
  figure at a glance, with the realized/estimated wording, USD
  conversion, balance trail, and quote-vs-realized lines in a small
  anchored popover on tap.
- **Extend writes the next scene.** On a delivered film whose model takes a
  reference video, the ⋯ menu offers *Extend*: it opens the film the way
  Reuse does — same model, settings, folder, and aesthetic — but attaches the
  film itself as the first creative reference and clears the direction back
  to `Extend @name.`, plus the script's first scene heading when the film was
  written as a screenplay. Nothing else of the old direction is kept; the
  point is to write what happens next. The reference is named after the film
  (the tab name it was rendered from, else its first words), and the
  references the film was rendered with come back — the cast first, then the
  rest, each group in its original order — for as long as the model has room
  beside the film: counted per kind, against the total, and against the
  reference-video seconds, with the extended film counting first. Anything
  that will not fit is left out, cast or not, and said so in one flash
  notice; an extension of an extension already carries the earlier
  references baked into its footage. Keyframes are not carried over: the
  film itself is the guidance now.
- Every card shows **all settings** as `GenerationSpecChips`: mode, ratio
  (with mini shape glyph), duration, resolution, audio, draft tier, timed
  keyframes.
- **Playback opens a film-sized modal** (`showVideoPlayerModal`): wide
  viewports get a dialog matched to the video's aspect ratio (dark media
  chrome, timeline strip, transport bar); viewports under 700 px get a
  fullscreen player with a close overlay. The fullscreen button inside the
  modal opens the true fullscreen route. Space toggles playback, ←/→ seek
  (5% of the film, clamped 1–5 s), Escape closes the surface it is pressed
  on. Saved video references play through the same modal. The inline
  timeline band is 34 px and the transport bar 40 px
  (`GenerationVideo.chromeHeight` = 74), so the idle filmstrip a card
  reserves under its thumbnail stays a low-profile strip rather than a
  second media zone.
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

### Provenance and the film modal

Above its prompt, a card says where a film came from when there is
something to say (`GenerationProvenance`): the **name of the tab** it was
rendered from (only when the director named that tab — an unnamed tab
adds no row), and for an AI Rewrite iteration a brass ✦ **"Rewrite of …"
link** naming the film it was rewritten from; the link opens that film.
Generations carry `title`, `rewriteOfLocalId`, and `rewriteSummary` for
this, stamped at submit time from the composer tab.

**Every card body opens the film modal** (`showGenerationDetailModal`):
the thumbnail keeps click-to-play, the ⋯ menu's *Open film* is the same
door, and the body (prompt, chips, provenance) is one tap. The modal is
nearly the full viewport (a full-screen page on phones) so nothing has to
be truncated. The header is the film's name — the tab name when the
director gave one, else the direction's first words — with favorite and
close. Two columns from about 900 px of content width (so a 1024-wide
window still gets both): media at true aspect ratio with the inline
player on the left; on the right the status and storage badges, the
complete selectable prompt with its copy control, folder and tag chips
(tapping one leaves the modal and filters the library), spec chips,
inputs with their labels written out, the cost readout with its breakdown
inline, the action row (Save, Reuse/Retry, AI Rewrite, Check status, and
a ⋯ carrying the card's organize verbs — Move, Tag, Hide, Copy to Drive,
Delete — but never *Open film*, which is where the ⋯ already led), and a
collapsed *Provider details* accordion holding the request bookkeeping
the old details dialog showed. Deleting the record from inside the modal
closes it. When the film has lineage, an **Iterations** strip walks the
chain both ways — *Rewritten from* → *This film* → *Rewrite* cards, oldest
first — and tapping another card swaps the modal to that film with a
*Back* affordance. Escape closes; the modal follows the controller so a
film that finishes rendering while open updates in place.

### AI Rewrite

An **AI Rewrite** button on a delivered film opens a dialog that asks a
multimodal LLM to revise the film's prompt; a **magic-wand key** before the
character counter in the Direction header opens the same dialog for the
draft in front (no frames — nothing has rendered yet), rewriting the
direction in place with *Undo* on the notice. Both entry points are always
present: without a saved key the dialog opens on a first-run step (pick
OpenAI or Anthropic, paste the key, *Verify & save*, *Get a key* link) and
carries straight on once the key verifies. The director picks the vendor
(when both have keys; the row is hidden when there is one), the model (a live listing with the vendor's newest
chat models first, a curated fallback when the listing is unavailable, and a
"Custom model id…" escape hatch), the vendor's own effort level, and types
what should be different next time in the Courier Prime direction voice. The
original prompt sits collapsed underneath for reference, and a small strip
shows the frames being sent (eight evenly spaced samples, downscaled). The
request carries the frames, the original prompt, the target provider and
model, the duration and ratio, the published prompt limit, and the exact
reference mentions (`@Image 1`) the prompt may use, so the answer respects
them. The vendor is constrained to structured JSON (`prompt` + a one-line
`summary`); the revised prompt lands in a **new composer tab** seeded from the
film's full recipe — settings, references, frames, folder — with the summary
in the tab's brass mark and in a notice. Errors stay inline in the dialog
(rejected key, rate limit, a vendor refusal, or an unusable answer) and never
open a tab.

Keys live in **Settings › AI Rewrite** (one masked field per vendor with
Verify & save, Replace, Remove, and a Get-a-key link), stored beside the
provider keys in the OS-secure vault and carried with them by secure
settings sync, so a key saved on one device follows to the others. On desktop the Electron renderer never
sees them: the companion holds the key and makes the vendor call; native
builds call the vendor directly. The last-used vendor, model, and effort are
remembered per vendor in preferences.

## 9. Version & updates

- The top-bar **version chip** opens a dialog that reports the running
  version. Automatic checks use Apple's public App Store listing on native iOS,
  the Electron shell bridge when present, and the GitHub releases API on other
  surfaces.
- A newer release adds an **Update Available** chip beside the running version
  on wide layouts. Compact layouts and native mobile apps use a flash
  notification so the header remains responsive.
- Where the shell can install in place (packaged macOS), the dialog offers
  **Download and install**; elsewhere it links the release page (or notes
  App Store delivery on mobile).
- Any in-place update, from this dialog **or** the macOS *Check for
  Updates…* menu, surfaces a blocking **progress modal** with the
  download byte count and bar, then a verifying/installing state before
  the app reopens itself. The shell streams `downloading / installing /
  error` events over `window.clawnsole` (see `electron/preload.cjs`,
  `flutter/lib/core/shell_bridge*.dart`).
- `scripts/release/bump_version.py` keeps `pubspec.yaml`, the Electron
  package, and `lib/core/app_version.dart` on one version.

## 10. Voice

Calm, concrete, lightly warm. Headlines are short imperatives or plain
nouns ("Your films.", "Room to stretch."); Create's heading is its tab
rail, not a headline. Body copy is
complete sentences that state what happens and why it is safe. No
exclamation points, no jargon-as-drama.

## 11. Accessibility checklist

- Selected/unselected states differ by more than hue (fill + outline +
  weight).
- Every icon-only control has a tooltip; frame thumbs describe role and
  timing.
- Keyboard: screenplay mode uses Tab / Shift Tab for element cycling;
  Escape followed by Tab / Shift Tab returns to ordinary focus traversal.
  Dialogs close on Escape; the video player focuses itself and
  keeps Space (play/pause), ←/→ (seek), and Escape bindings; interactive
  rows are real `InkWell`s with focus states.
- Test both modes at 375 px and ≥ 1440 px before shipping UI changes;
  `flutter test` guards the narrow-width overflows that test fonts expose.
