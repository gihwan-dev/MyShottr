# Inkbeam manual acceptance record

This template records interactive evidence for one exact Inkbeam candidate.
Replace every placeholder before attaching the completed report to
`refs/notes/inkbeam-acceptance`.

Allowed result values are exactly `PASS`, `FAIL`, or `BLOCKED`. A report with a
failure, blocker, placeholder, or missing evidence is not passing evidence.

## Candidate

- Date:
- macOS version:
- Google Chrome version:
- Tested commit SHA:
- `Scripts/verify-inkbeam.sh` result:
- `Scripts/verify-inkbeam.sh` evidence:

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

The extension captures only the visible page content and excludes browser UI.

- Result: `<PASS|FAIL|BLOCKED>`
- Evidence:

### 6. Chrome keyboard command

Chrome `Option-Shift-2` runs the same visible-viewport capture flow.

- Result: `<PASS|FAIL|BLOCKED>`
- Evidence:

### 7. Drawing tools and live preview

Every supported mark previews continuously and commits once at pointer-up.

- Result: `<PASS|FAIL|BLOCKED>`
- Evidence:

### 8. Annotation editing and shortcut ownership

Selection, transformation, history, viewport, Context Rail, toolbar, focus,
appearance, and Reduce Motion behavior match the candidate contracts.

- Result: `<PASS|FAIL|BLOCKED>`
- Evidence:

### 9. Clipboard PNG

Copy Image writes the complete composited PNG and hides only after success.

- Result: `<PASS|FAIL|BLOCKED>`
- Evidence:

### 10. Export dimensions

Exported PNG dimensions equal the source image dimensions.

- Result: `<PASS|FAIL|BLOCKED>`
- Evidence:

### 11. Project round trip and legacy rejection

`.inkbeam` save and reopen preserve source pixels and schema-3 annotations.
Older extensions and annotation schemas are rejected without conversion.

- Result: `<PASS|FAIL|BLOCKED>`
- Evidence:

### 12. Modified-document close

Closing a modified document offers Save, Discard, and Cancel.

- Result: `<PASS|FAIL|BLOCKED>`
- Evidence:

### 13. Direct capture launch

A cold capture opens directly without a recovery prompt.

- Result: `<PASS|FAIL|BLOCKED>`
- Evidence:

### 14. Screen Recording denial

Permission denial offers the relevant System Settings action.

- Result: `<PASS|FAIL|BLOCKED>`
- Evidence:

### 15. Missing Chrome host

A missing Inkbeam Native Messaging host reports an actionable failure without
using another capture mechanism.

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

Save feedback reflects native completion, and `Scripts/verify-privacy.sh`
passes on artifacts built from the tested commit.

- Result: `<PASS|FAIL|BLOCKED>`
- Evidence:

## Final decision

- Overall result: `<PASS|FAIL|BLOCKED>`
- Reviewer:
- Notes:
