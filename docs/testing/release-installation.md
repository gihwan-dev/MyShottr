# Inkbeam v0.2.0 release-installation record

This template records evidence from files downloaded from the live Inkbeam
GitHub Release. Allowed result values are exactly `PASS`, `FAIL`, or `BLOCKED`.
A report containing a failure, blocker, placeholder, or missing evidence is
not passing release-install evidence.

## Candidate and live release

- Tag: `v0.2.0`
- Exact release commit SHA: `<40-hex SHA>`
- CI workflow URL:
  `https://github.com/gihwan-dev/inkbeam/actions/runs/<run-id>`
- Release workflow URL:
  `https://github.com/gihwan-dev/inkbeam/actions/runs/<run-id>`
- Live release URL:
  `https://github.com/gihwan-dev/inkbeam/releases/tag/v0.2.0`
- Download source URL:
  `https://github.com/gihwan-dev/inkbeam/releases/download/v0.2.0/`
- Test date and timezone:
- macOS version:
- Google Chrome version:
- Tester:

## Downloaded artifacts

### Downloaded artifact sizes

| Artifact | Expected SHA-256 | Downloaded size in bytes | Result |
| --- | --- | --- | --- |
| `Inkbeam-0.2.0-macos.zip` | `<from downloaded SHA256SUMS.txt>` | `<bytes>` | `<PASS\|FAIL\|BLOCKED>` |
| `Inkbeam-Chrome-0.2.0.zip` | `<from downloaded SHA256SUMS.txt>` | `<bytes>` | `<PASS\|FAIL\|BLOCKED>` |
| `SHA256SUMS.txt` | `<published asset SHA-256>` | `<bytes>` | `<PASS\|FAIL\|BLOCKED>` |

- Evidence:

### SHA-256 verification

Both ZIP files match the exact entries in the downloaded `SHA256SUMS.txt`.

- Result: `<PASS|FAIL|BLOCKED>`
- Evidence:

## Installation and product checks

### App launch

The downloaded app reports version `0.2.0`, opens as Inkbeam, and registers the
Inkbeam Native Messaging host from its installed absolute path.

- Result: `<PASS|FAIL|BLOCKED>`
- Evidence:

### Native region capture

`Command-Shift-2` opens region selection and a successful Retina capture opens
one correctly sized Inkbeam document without the selection overlay.

- Result: `<PASS|FAIL|BLOCKED>`
- Evidence:

### Chrome visible-viewport capture

Toolbar action and `Option-Shift-2` each open exactly one document containing
visible page pixels without browser UI.

- Result: `<PASS|FAIL|BLOCKED>`
- Evidence:

### Project reopen

Save Project, close, and reopen preserve source pixels, schema-3 annotations,
and `presentation: { "type": "none" }`. Copy Image and Export PNG preserve
source dimensions.

- Result: `<PASS|FAIL|BLOCKED>`
- Evidence:

### Extension manifest permissions

The extracted Manifest V3 extension contains exactly `activeTab` and
`nativeMessaging`, its stable public key, and no host permissions or content
scripts.

- Result: `<PASS|FAIL|BLOCKED>`
- Evidence:

### Gatekeeper behavior

The downloaded candidate matches its documented signing and notarization
state, and Gatekeeper reports the expected result for that exact artifact.

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

Only a report with every check marked `PASS`, complete evidence, one exact
commit, and hashes matching the downloaded `SHA256SUMS.txt` may be attached as
passing post-publication release-install evidence.
