# Screenplay authoring

A compact single-row header contains the Plaintext / Screenplay selector, an
icon-only Clear control, the used/max character count, and an icon-only Expand
control. A 3-pixel bar below the count fills green, then orange at 80% and red
at 95%, with a gray unused track. The count includes added aesthetic direction.
Its tooltip and accessibility label give the remaining or exceeded allowance;
when a provider publishes no maximum, the editor's 50,000-character cap is shown
and explicitly identified as an editor limit.
Below the header, a single-line toolbar contains Copy, AI rewrite, Characters
on compatible models, and the aesthetic picker. Compact layouts use labelled
tooltips with icon-only actions, reserving room for the selected aesthetic's
name. The picker reads "Aesthetic" when none is selected; long names truncate
with an ellipsis and remain available in full through its tooltip and menu.
The same layout adapts to larger accessibility text without horizontal scrolling.
In screenplay mode
the element selector, Prev, and Next sit directly below the editor, followed by
the suggestion tags.
The Enter / Tab hint sits directly above the text entry area. The expanded editor
includes the same controls, and the shared Flutter implementation serves native
Windows, iOS/Android, and the macOS Electron renderer.

The format is saved per draft. It formats scene headings, character cues,
action, dialogue, parentheticals, and transitions using the bundled Courier
Prime font. Tab and Shift Tab cycle elements; the element menu and Prev /
Next arrow controls do the same on touch devices, with 48-pixel minimum touch
targets. The mobile hint describes these touch controls. Enter advances a character cue or
parenthetical to dialogue, dialogue to action, and a transition to a scene.
Enter on an empty indented line returns to action. Scene and character elements
capitalize while typing. Completions include scene prefixes, previous scene
headings, speakers, and assigned characters. Tap a
suggestion or use Alt + Up/Down and Enter. Ordinary arrows, including Shift
selection, always move through the script when screenplay completions are visible. Escape dismisses suggestions. Pasting a
script recognizes its elements. Active input-method compositions are preserved.

The prompt box fills the available width in both formats, including the expanded
editor. Screenplay indentation scales to that width, while retaining compact
indentation in plain text. This is
an authoring editor, without print pagination or production scheduling tools.
Turning Screenplay off preserves the text. Copy includes the direction and the
casting block appended to it, exactly as a generation receives them. AI rewrite
is sent the same combined text and is asked to preserve screenplay structure and
casting, with the usual review and undo flow; casting lines echoed back in a
rewrite are absorbed into the cast rather than left in the editor.

In either format, type **@** to list attached references beside the cursor.
Type part of a reference name to filter, use Up/Down to highlight a reference,
and press Enter to insert its highlighted tag. This also works in the expanded
editor and stays available independently of automatic character detection.
Moving the cursor through existing tags does not open autocomplete. Plaintext
uses ordinary text-field cursor movement and wrapping, including Shift selection
and modified navigation shortcuts. Only unmodified Up/Down select suggestions
while a typed @ query is active; Left/Right or Escape dismiss that menu.

Use **Name character** on an attached image/video card, or **Character name** in
a saved reference's edit dialog. Assignments are optional, uppercased, and
unique across references. Known names match whole names in the screenplay,
including mixed-case names in action without a speaking role. If no character
assignment is set, an exact reference name (ignoring its media extension) can
also supply the default. On a compatible model with room, matching saved media
attaches automatically and the character joins the draft's cast:

```text
ALEXANDRIA: @alx.mp4
```

That line is never part of the editable prompt. The cast is separate draft
state, shown in the composer's Cast row and the Characters modal, and appended
silently at submission after the direction and before any aesthetic text — the
same way an aesthetic is appended. It counts toward the prompt character budget
and appears in the stored prompt of the film it produced. A casting line pasted
or typed into the prompt box, restored from a workspace written before composer
schema 6, or reused from an older film, is absorbed into the cast and removed
from the editable text along with the blank line it sat behind.

Removing the reference also removes it from every cast entry and suppresses
automatic reattachment in that draft. To cast it again, attach the reference and
save its character assignment. Clearing the assignment removes its unchanged
cast entry without rewriting the script's character names. Renaming a reference
follows into the cast. Automatic casting respects the chosen model's media kinds
and reference count limits. Unsupported media can be attached after choosing a
compatible model.

## The Cast row

When at least one character holds a reference on a model that accepts creative
image or video references, a compact **Cast** strip sits above the composer's
guidance and settings columns. Each chip carries up to three overlapping
thumbnails of that character's media, a "+n" spillover, and the cast name; a tap
opens the same mapping editor the Characters modal uses, and the chip's own
pencil and × recast or uncast that character without opening the Characters
modal (uncasting keeps the media attached). A quiet **Add character** action
ends the row. With no cast, the row is absent entirely, so an
empty composer keeps its heading through Generate above the fold.

The **Characters** control is available only on models that accept creative
image or video references; keyframe-only and audio-only models do not support
casting. In Screenplay mode, the modal detects character cues using the same
parser as the editor and also lists known reference names mentioned in action.
Unmatched uppercase words do not become cast members. Opening Characters
reconciles matching references in an existing screenplay, so restored scripts
do not require another keystroke to show their casting. Explicitly added
characters and absorbed casting lines remain listed in either format. Each row
shows the character's mapped media as stacked thumbnails beside its name.
Use **Add character** at any time, including before writing a prompt, for
non-speaking roles or manual Plaintext casting. Entering a matching name
preselects its references. Choose a character to select, change, or remove one
or more attached or saved image/video references. A manual selection, including
**Remove all**, takes precedence over automatic matching and survives later
typing. Renaming an existing cast keeps its reference selection. A character
added without references to an empty draft survives unrelated settings edits.
Saving attaches new media within the chosen model's
limits and replaces that character's cast entry. Removing a cast entry
keeps media in the References tray for other uses. Removing a card from that
tray removes its token from every cast entry, preserving other mapped media.

The reference chooser inside the editor carries a **Search references** field, a
thumbnail per row, and All / Images / Videos keys whose counts follow the search.
References that match the name being typed — by their saved character name, or
by their file name once its media extension is dropped — are grouped first under
a **Matches NAME** eyebrow, so two references both named VINNY sit at the top
while casting VINNY. Currently selected references come next, then anything
attached to this direction, then the rest alphabetically. A selected reference
that no longer exists stays listed as unavailable so it can be removed or
replaced.

Renaming defaults to changing the cast name only. Select **Also
rename in direction** to replace whole character-name occurrences in the script
as well. Script-to-casting aliases persist in composer tabs and generation reuse.
Cast names must be unique within a script. Library card assignments remain
unique library defaults; a script's cast can choose several media per character
without changing those defaults. Manual casting also works in Plaintext mode.

Both formats submit the current editor text with the casting block appended.
The provider adapters translate attached reference names into their existing
reference dialects (for example `@video1` for Seedance through Krea or Runway),
while preserving the surrounding direction and line breaks. The displayed and
saved prompt keeps the readable reference names. Character assignments are
authoring metadata and introduce no provider-specific fields, privileged
renderer calls, or inline media.

Stored-data schema 25 adds optional reference character names and generation
screenplay mode; older records retain their media and default to unassigned,
prose-mode records. Composer schema 6 stores the cast as its own record field
instead of casting lines inside the prompt; a workspace written by an older
build has its lines absorbed on restore, and older builds refuse a schema-6
workspace rather than silently dropping casts.
Composer schema 4 also syncs tabs and aesthetic selections through Drive,
retaining compact attachment layouts. Composer schema 3 introduced the mode, handled character names, character aliases,
and saved reference ids with their prompt names. These saved references restore
into their own tabs, including inactive tabs. Retained assets and HTTPS references reopen with the draft. Local assets
require their original device unless copied to Drive.
Copied library media starts unassigned so it can be cast without duplicating
the original reference's character.
