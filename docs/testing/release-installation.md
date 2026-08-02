# MyShottr v0.1.0 release-installation record

This is an evidence template for testing the files downloaded from the live
GitHub Release. Allowed result values are exactly `PASS`, `FAIL`, or `BLOCKED`.
`BLOCKED` means the check was not directly verified and the reason must be
recorded. A report containing `FAIL`, `BLOCKED`, a placeholder, or missing
evidence is not passing release-install evidence and must not be attached as a
passing Git note.

## Candidate and live release

- Tag: `v0.1.0`
- Exact release commit SHA: `<40-hex SHA>`
- CI workflow URL:
  `https://github.com/gihwan-dev/MyShottr/actions/runs/<run-id>`
- Release workflow URL:
  `https://github.com/gihwan-dev/MyShottr/actions/runs/<run-id>`
- Live release URL:
  `https://github.com/gihwan-dev/MyShottr/releases/tag/v0.1.0`
- Download source URL:
  `https://github.com/gihwan-dev/MyShottr/releases/download/v0.1.0/`
- Test date and timezone:
- macOS version:
- Google Chrome version:
- Tester:

## Downloaded artifacts

### Downloaded artifact sizes

| Artifact | Expected SHA-256 | Downloaded size in bytes | Result |
| --- | --- | --- | --- |
| `MyShottr-0.1.0-macos.zip` | `<from downloaded SHA256SUMS.txt>` | `<bytes>` | `<PASS\|FAIL\|BLOCKED>` |
| `MyShottr-Chrome-0.1.0.zip` | `<from downloaded SHA256SUMS.txt>` | `<bytes>` | `<PASS\|FAIL\|BLOCKED>` |
| `SHA256SUMS.txt` | `<published asset SHA-256>` | `<bytes>` | `<PASS\|FAIL\|BLOCKED>` |

- Evidence:

### SHA-256 verification

Both ZIP files match the exact entries in the downloaded `SHA256SUMS.txt`.

- Result: `<PASS|FAIL|BLOCKED>`
- Evidence:

## Installation and product checks

### App launch

The app extracted from the downloaded ZIP reports version `0.1.0`, opens using
the documented unsigned-app flow, and registers the Native Messaging Host from
its installed absolute path.

- Result: `<PASS|FAIL|BLOCKED>`
- Evidence:

### Native region capture

`Command-Shift-2` opens region selection, `Escape` cancels cleanly, and a
successful Retina capture opens one correctly sized Quick Ink document without
the selection overlay.

- Result: `<PASS|FAIL|BLOCKED>`
- Evidence:

### Chrome visible-viewport capture

The downloaded extension loads with Developer mode and **Load unpacked**.
Toolbar action and `Option-Shift-2` each open exactly one document containing
visible page pixels without tabs, address bar, bookmarks, toolbar, developer
tools, or extension popup.

- Result: `<PASS|FAIL|BLOCKED>`
- Evidence:

### Project reopen

Save Project, close, and reopen preserve the original pixels, annotations, and
`presentation: { "type": "none" }`. Copy Image and Export PNG also succeed at
source dimensions. `R` must preview a rectangle while dragging, `T` must open
inline text editing immediately, and an empty-canvas drag with Selection must
preview a marquee. `Shift`-click toggles selection; `Option`-drag or
`Command-D` duplicates it. Scroll and `Space`-drag pan, pinch or
`Command`-scroll zooms around the pointer, `Command-0` sets 100%, `Shift-1`
fits the image, and `Shift-2` fits the current selection.

The Context Rail must cover hidden, creation-default, single-selection,
multi-selection, and `Mixed` states. The native toolbar order must be Copy
Image, Undo, Redo, flexible space, Save Project, Export PNG. Copy success hides
without closing the document; `?` restores focus when closed. Light, Dark, and
Reduce Motion behavior must match the accepted candidate.

- Result: `<PASS|FAIL|BLOCKED>`
- Evidence:

### Extension manifest permissions

The extracted `manifest.json` uses Manifest V3, contains exactly `activeTab`
and `nativeMessaging`, contains its stable public key, and has no host
permissions or content scripts.

- Result: `<PASS|FAIL|BLOCKED>`
- Evidence:

### Gatekeeper behavior

`spctl --assess --type execute` rejects the app as expected for this
unsigned/unnotarized release, and the documented Control-click or **System
Settings → Privacy & Security → Open Anyway** flow opens it without broad
quarantine removal.

- Result: `<PASS|FAIL|BLOCKED>`
- Evidence:

## Final decision

- Overall result: `<PASS|FAIL|BLOCKED>`
- Exact release commit SHA rechecked:
- Remote tag dereference SHA:
- Downloaded release URL rechecked:
- Git note attachment SHA:
- Reviewer:
- Notes:

Only a report with every required check marked `PASS`, complete evidence, tag
and workflow references resolving to the same exact commit SHA, and downloaded
asset hashes matching the workflow-produced `SHA256SUMS.txt` may be attached as
passing post-publication release-install evidence.
