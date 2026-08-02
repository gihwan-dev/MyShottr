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
- `Scripts/verify-v1.sh` log or evidence:

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
redaction, and number-marker tools work, and drag-created marks preview live
before pointer-up.

- Result: `<PASS|FAIL|BLOCKED>`
- Evidence:

### 8. Annotation editing and shortcut ownership

Move, resize, rotate, duplicate, delete, reorder, multi-select, undo, and redo
work. `R`, `T`, `?`, `Space`, `Command-D`, `Shift-1`, and `Shift-2` must
behave in the editor exactly as documented, including inline text editing,
shortcut-help focus restore, and temporary pan.

- Result: `<PASS|FAIL|BLOCKED>`
- Evidence:

### 9. Clipboard PNG

Copy Image pastes a PNG into macOS Notes.

- Result: `<PASS|FAIL|BLOCKED>`
- Evidence:

### 10. Export dimensions

Exported PNG dimensions equal the source image dimensions.

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

Completed Save shows `Saved` only after the native operation finishes, later
edits surface the superseded-save message, and `Scripts/verify-privacy.sh`
passes on the exact artifacts built from the tested commit SHA.

- Result: `<PASS|FAIL|BLOCKED>`
- Evidence:

## Final decision

- Overall result: `<PASS|FAIL|BLOCKED>`
- Reviewer:
- Notes:

Only a report with all 18 checks marked `PASS`, complete evidence, and a tested
SHA matching the clean commit may be attached as passing release evidence.
