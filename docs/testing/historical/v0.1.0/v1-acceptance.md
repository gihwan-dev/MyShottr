# MyShottr v1 manual acceptance record

This template records interactive evidence for one exact release-candidate
commit. Replace every placeholder before attaching the completed report to
`refs/notes/myshottr-acceptance`.

Allowed result values are exactly `PASS`, `FAIL`, or `BLOCKED`. `BLOCKED` means
the check was not directly verified; explain the blocking condition in
Evidence. A report containing `FAIL`, `BLOCKED`, a placeholder, or missing
evidence is not passing release evidence and must not be added as a passing Git
note.

## Candidate

- Date:
- macOS version:
- Google Chrome version:
- Tested commit SHA:
- `Scripts/verify-v1.sh` result:
- `Scripts/verify-v1.sh` evidence:

## Checks

### 1. Native region shortcut

`Command-Shift-2` opens region selection.

- Result: `<PASS|FAIL|BLOCKED>`
- Evidence:

### 2. Capture cancellation

`Escape` cancels region selection without creating a document.

- Result: `<PASS|FAIL|BLOCKED>`
- Evidence:

### 3. Retina source dimensions

A Retina region opens at the exact source pixel dimensions.

- Result: `<PASS|FAIL|BLOCKED>`
- Evidence:

### 4. Overlay exclusion

The selection overlay is absent from the captured PNG.

- Result: `<PASS|FAIL|BLOCKED>`
- Evidence:

### 5. Chrome visible viewport

The Chrome extension action captures visible page content without the tab
strip, address bar, bookmarks, toolbar, popup, or other browser chrome.

- Result: `<PASS|FAIL|BLOCKED>`
- Evidence:

### 6. Chrome keyboard command

Chrome `Option-Shift-2` runs the same visible-viewport capture flow.

- Result: `<PASS|FAIL|BLOCKED>`
- Evidence:

### 7. Drawing tools and live preview

Selection, rectangle, arrow, line, text, freehand, highlighter, blur, opaque
redaction, and number-marker tools work. Every drag-created mark previews
continuously before pointer-up; `T` enters inline editing immediately. Holding
`Shift` constrains rectangles, arrows, and lines without taking over pan.

- Result: `<PASS|FAIL|BLOCKED>`
- Evidence:

### 8. Annotation editing and shortcut ownership

Move, resize, rotate, duplicate, delete, reorder, multi-select, undo, and redo
work. Empty-canvas drag with Selection (`V`) previews a marquee and selects
intersecting annotations; `Shift`-click toggles one annotation, and
`Option`-drag or `Command-D` duplicates the selection.

Scroll and `Space`-drag pan. Pinch or `Command`-scroll zooms around the pointer;
`Command-0` sets 100%, `Shift-1` fits the image, and `Shift-2` fits the current
selection. The Context Rail is hidden for Selection with no selection, shows
creation defaults for a drawing tool, shows one selection's properties, and
shows shared multi-selection fields with differing values labeled `Mixed`.

The native toolbar order is Copy Image, Undo, Redo, flexible space, Save
Project, Export PNG. `Command-Shift-C`, `Command-S`, and `Command-E` still route
through the key document while inline text or shortcut help owns focus, while
ordinary text Copy/Paste remains text-owned. `?` restores invoking focus after
`Escape`. Light and Dark follow the document window, and Reduce Motion removes
Context Rail reflow animation.

- Result: `<PASS|FAIL|BLOCKED>`
- Evidence:

### 9. Clipboard PNG

Copy Image writes the complete composited PNG and it pastes into macOS Notes.
Only after the pasteboard write succeeds, the editor window hides without
closing the document; refocusing preserves the same editor session.

- Result: `<PASS|FAIL|BLOCKED>`
- Evidence:

### 10. Export dimensions

Exported PNG dimensions equal the source image dimensions. The editor remains
visible, and completion feedback exposes only the destination basename.

- Result: `<PASS|FAIL|BLOCKED>`
- Evidence:

### 11. Project round trip and migration

`.myshottr` Save, close, and reopen preserve source pixels, element JSON, and
`presentation: { "type": "none" }`; a schema-1 fixture migrates to schema 3.

- Result: `<PASS|FAIL|BLOCKED>`
- Evidence:

### 12. Modified-document close

Closing a modified document offers Save, Discard, and Cancel.

- Result: `<PASS|FAIL|BLOCKED>`
- Evidence:

### 13. Direct capture launch

Starting a capture from a cold app launch opens the captured image directly in
the editor without an intervening recovery prompt.

- Result: `<PASS|FAIL|BLOCKED>`
- Evidence:

### 14. Screen Recording denial

Screen Recording denial gives an action that opens the relevant System
Settings page.

- Result: `<PASS|FAIL|BLOCKED>`
- Evidence:

### 15. Missing Chrome host

A missing Chrome Native Messaging host manifest reports the host as unavailable
without starting native capture or another capture mechanism.

- Result: `<PASS|FAIL|BLOCKED>`
- Evidence:

### 16. Unsupported project version

An unsupported project version refuses to open without partial import.

- Result: `<PASS|FAIL|BLOCKED>`
- Evidence:

### 17. Failed export

A failed export leaves the document modified and the destination untouched.

- Result: `<PASS|FAIL|BLOCKED>`
- Evidence:

### 18. Save terminal truthfulness and exact-artifact privacy gate

Completed Save shows `Saved` only after the native operation finishes. Later
edits surface the superseded-save message; cancellation and failure remain
truthful without closing the document. `Scripts/verify-privacy.sh` passes on
the exact artifacts built from the tested commit SHA.

- Result: `<PASS|FAIL|BLOCKED>`
- Evidence:

## Final decision

- Overall result: `<PASS|FAIL|BLOCKED>`
- Reviewer:
- Notes:

Only a report with all 18 checks marked `PASS`, complete evidence, and a tested
SHA matching the clean commit may be attached as passing release evidence.
