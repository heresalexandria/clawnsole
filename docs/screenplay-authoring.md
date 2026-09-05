# Screenplay authoring

A compact single-row header contains the Plaintext / Screenplay selector, an
icon-only Clear control, the character count, and an icon-only Expand control.
Below the header, a single-line toolbar contains Copy, AI rewrite, and, on
compatible models, Characters.
It can scroll horizontally at large accessibility text sizes. In screenplay mode
the element selector, Prev, and Next sit directly below the editor, followed by
the suggestion tags.
The Enter / Tab hint sits directly above the text entry area. The expanded editor
includes the same controls, and the shared Flutter implementation serves native
Windows, iOS/Android, and the macOS Electron renderer.

The format is saved per draft. It formats scene headings, character cues,
action, dialogue, parentheticals, and transitions using the bundled Courier
Prime font. Tab and Shift Tab cycle elements; the element menu and Prev /
Next controls do the same on touch devices. Enter advances a character cue or
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
Turning Screenplay off preserves the text. Copy includes the editable script
and its mapping lines. AI rewrite is asked to preserve screenplay structure
and casting, with the usual review and undo flow.

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
unique across references. Use the character in the script as a speaker or an
uppercase entity in action. On a compatible model with room, its saved media
attaches automatically and a line appears at the end of Direction:

```text
ALEXANDRIA: @alx.mp4
```

The line is ordinary editable prompt text. Editing or deleting it is respected
on subsequent keystrokes. Removing the reference also removes its unchanged
mapping and suppresses automatic reattachment in that draft. To cast it again,
attach the reference and save its character assignment. Clearing the assignment
removes its unchanged mapping without rewriting the script's character names.
Automatic casting respects the chosen model's media kinds and reference count
limits. Unsupported media can be attached after choosing a compatible model.

The **Characters** control is available only on models that accept creative
image or video references; keyframe-only and audio-only models do not support
casting. In Screenplay mode, the modal detects character cues using the same
parser as the editor. Uppercase words in action or Plaintext do not become cast
members. Explicitly added characters and casting lines remain listed in either
format. Use **Add character** for non-speaking roles or manual Plaintext casting.
Choose a character to select, change, or remove one or more attached or saved
image/video references. Saving attaches new media within the chosen model's
limits and replaces that character's editable footer line. Removing a mapping
keeps media in the References tray for other uses. Removing a card from that
tray removes its token from every casting line, preserving other mapped media.

Renaming defaults to changing the name in the casting footer. Select **Also
rename in direction** to replace whole character-name occurrences in the script
as well. Script-to-casting aliases persist in composer tabs and generation reuse.
Cast names must be unique within a script. Library card assignments remain
unique library defaults; a script's cast can choose several media per character
without changing those defaults. Manual casting also works in Plaintext mode.

Both formats submit the current editor text, including editable casting lines.
The provider adapters translate attached reference names into their existing
reference dialects (for example `@video1` for Seedance through Krea or Runway),
while preserving the surrounding direction and line breaks. The displayed and
saved prompt keeps the readable reference names. Character assignments are
authoring metadata and introduce no provider-specific fields, privileged
renderer calls, or inline media.

Stored-data schema 25 adds optional reference character names and generation
screenplay mode; older records retain their media and default to unassigned,
prose-mode records. Composer schema 3 stores the mode, handled character names, character aliases,
and saved reference ids with their prompt names. These saved references restore
into their own tabs, including inactive tabs. Unsaved URL references remain
session-only, as before; save them to References to retain their assignments.
Copied library media starts unassigned so it can be cast without duplicating
the original reference's character.
