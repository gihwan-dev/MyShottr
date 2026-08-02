# Inkbeam Product and Repository Rename Design

- Date: 2026-08-02
- Status: Approved product name; implementation pending written-spec review
- Current product: `MyShottr` `v0.1.0`
- New product: `Inkbeam`
- Current repository: `gihwan-dev/MyShottr`
- New repository: `gihwan-dev/inkbeam`
- First Inkbeam release: `v0.2.0`
- Tagline: `Capture fast. Mark freely.`

## 1. Purpose and Authority

This document defines the one-time migration from the public `MyShottr`
identity to `Inkbeam`. The rename covers the macOS app, Chrome extension,
editable project type, Native Messaging boundary, packages, source targets,
documentation, GitHub repository, and release artifacts.

It extends:

- [`2026-07-29-myshottr-v1-design.md`](./2026-07-29-myshottr-v1-design.md)
- [`2026-07-30-myshottr-v1-public-release-design.md`](./2026-07-30-myshottr-v1-public-release-design.md)
- [`2026-07-31-myshottr-editor-ux-polish-design.md`](./2026-07-31-myshottr-editor-ux-polish-design.md)

Those documents remain authoritative for product behavior. This document takes
precedence only for brand identity, migration, compatibility, repository, and
release naming.

`MyShottr v0.1.0` is already public. The migration must therefore preserve its
projects, tag, release assets, acceptance evidence, and incoming GitHub links.
This is not a history rewrite and must not retroactively rename v0.1.0.

## 2. Confirmed Decisions

- The public brand, macOS app, and repository are named `Inkbeam`.
- `Ink` represents hand-drawn annotation; `beam` represents the screen, light,
  and immediate capture.
- Public copy uses `Capture fast. Mark freely.`
- `Quick Ink` is no longer a public sub-brand. Historical design documents may
  retain the phrase as provenance.
- The first release under the new identity is `v0.2.0`.
- Existing `.myshottr` projects remain editable.
- New projects use `.inkbeam`.
- The Chrome extension retains its stable public key and extension identity.
- The new app uses a new bundle identifier. macOS may therefore require Screen
  Recording permission again; the app must not attempt to bypass that prompt.
- The current coral capture-frame app and menu-bar icon remain for v0.2.0.
  A separate visual-brand redesign is not part of this migration.
- The repository keeps its commits, issues, Actions history, tags, releases,
  and public visibility when GitHub renames it.
- No v0.1.0 tag, asset, checksum, Git note, or release text is rewritten.

## 3. Goals and Non-Goals

### 3.1 Goals

1. Present one coherent `Inkbeam` identity on every live user-facing surface.
2. Remove `MyShottr` from current executable, package, module, extension,
   workflow, and release identities.
3. Preserve deterministic access to editable `.myshottr` documents.
4. Let both the v0.1.0 extension package and the v0.2.0 extension reach the
   new app during the transition.
5. Preserve local-only privacy and the extension's exact permission surface.
6. Publish a verified `Inkbeam v0.2.0` without disturbing `MyShottr v0.1.0`.
7. Make old GitHub URLs redirect to the renamed repository.

### 3.2 Non-Goals

- changing capture, editor, annotation, or output behavior;
- full-page capture or desktop mockups;
- Developer ID signing, notarization, or store distribution;
- automatic updates;
- a new app icon or visual-system redesign;
- rewriting Git history or historical v0.1.0 documents;
- deleting the legacy project type, inbox, or Native Messaging identifier;
- claiming exclusive trademark rights to `Inkbeam`;
- renaming the local checkout directory while an active worktree depends on it.

## 4. Identity Map

The implementation uses the following exact identities.

| Surface | v0.1.0 identity | Inkbeam identity |
| --- | --- | --- |
| Product display name | `MyShottr` | `Inkbeam` |
| GitHub repository | `gihwan-dev/MyShottr` | `gihwan-dev/inkbeam` |
| macOS app | `MyShottr.app` | `Inkbeam.app` |
| App executable and Xcode scheme | `MyShottr` | `Inkbeam` |
| Xcode project | `MyShottr.xcodeproj` | `Inkbeam.xcodeproj` |
| Native helper | `MyShottrNativeHost` | `InkbeamNativeHost` |
| App bundle identifier | `com.myshottr.app` | `dev.gihwan.inkbeam` |
| Helper bundle identifier | `com.myshottr.native-host` | `dev.gihwan.inkbeam.nativehost` |
| Primary Native Messaging host | `com.myshottr.capture` | `dev.gihwan.inkbeam.capture` |
| Capture-ready notification | `com.myshottr.captureReady` | `dev.gihwan.inkbeam.captureReady` |
| App support directory | `Application Support/MyShottr` | `Application Support/Inkbeam` |
| Editor URL scheme | `myshottr-editor` | `inkbeam-editor` |
| WebKit bridge name | `myshottr` | `inkbeam` |
| Editor package | `@myshottr/editor` | `@inkbeam/editor` |
| Chrome package | `@myshottr/chrome-extension` | `@inkbeam/chrome-extension` |
| Primary project extension | `.myshottr` | `.inkbeam` |
| Primary project UTI | `com.myshottr.project` | `dev.gihwan.inkbeam.project` |
| Chrome display name | `MyShottr` | `Inkbeam` |
| Extension package | `MyShottr-Chrome-0.1.0.zip` | `Inkbeam-Chrome-0.2.0.zip` |
| macOS archive | `MyShottr-0.1.0-macos.zip` | `Inkbeam-0.2.0-macos.zip` |
| Acceptance Git note | `refs/notes/myshottr-acceptance` | `refs/notes/inkbeam-acceptance` |

Swift product types, test targets, source directories, environment variables,
temporary-path prefixes, and current scripts follow the new identity. A live
source identifier may retain `myshottr` only when it implements an explicit
legacy-compatibility contract listed in this document.

Historical specifications, the v0.1.0 release record, v0.1.0 artifact names,
and the v0.1.0 acceptance Git note remain unchanged.

## 5. Editable Project Compatibility

### 5.1 Primary format

New captures save with the `.inkbeam` extension. For example, a project named
`Example` contains exactly:

```text
Example.inkbeam/
├── manifest.json
├── original.png
└── document.json
```

The package `formatVersion`, annotation `schemaVersion`, manifest fields,
immutable original pixels, and JSON validation rules do not change. A brand
rename is not a document-schema migration.

### 5.2 Legacy `.myshottr` projects

Inkbeam registers both document types:

- exported primary type `dev.gihwan.inkbeam.project` for `.inkbeam`;
- imported legacy type `com.myshottr.project` for `.myshottr`.

Opening `.myshottr` uses the same strict package loader as `.inkbeam`. Save
preserves the opened URL and extension, so an existing `.myshottr` project is
updated in place. A new unsaved document always proposes `.inkbeam`.

Inkbeam declares a legacy `CFBundleDocumentTypes` entry with editor role and
`LSItemContentTypes` containing `com.myshottr.project`. Finder open, Open-panel
visibility, and in-place save must work without coercing the extension to
`.inkbeam`.

Because v0.2.0 does not change either document schema, a `.myshottr` project
saved by Inkbeam v0.2.0 must still open in MyShottr v0.1.0 with identical source
pixels and annotations. A later schema change must make its own backward-write
policy explicit before it can alter this contract.

Inkbeam must not silently copy, rename, or delete a legacy project. Unsupported
package or annotation versions continue to fail explicitly without partial
import.

### 5.3 Compatibility duration

Reading and saving `.myshottr` is a permanent compatibility contract unless a
later, separately approved design replaces it. It is not scheduled for removal
in v0.2.x.

## 6. Chrome and Native Messaging Migration

### 6.1 Stable extension identity

The Manifest V3 extension keeps the existing stable `key`. Renaming its display
name, package directory, command descriptions, and source package must not
change the derived Chrome extension ID.

Permissions remain exactly:

```json
["activeTab", "nativeMessaging"]
```

The extension adds no host permissions, optional host permissions, content
scripts, URL persistence, analytics, or alternate capture path.

### 6.2 Primary host

The Inkbeam extension sends to `dev.gihwan.inkbeam.capture`. On each unblocked
app launch, and after leaving the migration-blocked state, Inkbeam atomically
writes:

```text
~/Library/Application Support/Google/Chrome/NativeMessagingHosts/
  dev.gihwan.inkbeam.capture.json
```

The manifest has mode `0600`, points to the helper inside the running
`Inkbeam.app`, and allows only the existing stable extension origin.

Registration replaces a complete manifest atomically. An interrupted or failed
write leaves no truncated destination or temporary file. Every launch validates
the installed helper path and replaces a stale manifest left by an older build.

### 6.3 Legacy host adapter

For v0.2.x, Inkbeam also writes `com.myshottr.capture.json` with the same exact
helper path and allowed origin. This is a deliberate migration adapter for the
unpacked v0.1.0 extension, not an alternate capture mechanism.

The legacy alias changes only the host name Chrome looks up. Both aliases launch
the new helper, so both hand off through `dev.gihwan.inkbeam.captureReady` and
the new Inkbeam inbox. Live Inkbeam code does not listen for the old
`com.myshottr.captureReady` notification.

The new host registration is required. If it fails, app launch reports the
existing actionable host-installation error. If only legacy registration
fails, Inkbeam reports a compatibility-specific warning explaining that the
v0.1.0 extension must be replaced; the primary Inkbeam host remains usable.

A primary failure before atomic replacement leaves any previously complete
manifest intact. A directory-sync failure after replacement may leave the new
complete manifest installed but reports the failure and forces validation on the
next launch; no failure may leave truncated JSON. Primary failure stops Chrome
capture with the existing actionable installation error. A legacy registration
failure does not roll back or corrupt the validated primary manifest. Tests
inject failures before replacement, during replacement, after replacement, and
after helper-path changes and assert these on-disk postconditions.

Removal of the legacy host adapter is outside this design and requires a later
explicit decision.

## 7. Local Data and macOS Permission Migration

### 7.1 Durable capture inbox

New captures stage in:

```text
~/Library/Application Support/Inkbeam/Inbox/
```

Inkbeam also scans the v0.1.0 `Application Support/MyShottr/Inbox/` directory
for pending captures. It processes the new inbox first and the legacy inbox
second, with deterministic filename ordering inside each directory.

The logical capture identifier is the canonical UUID at the start of a filename
accepted by the existing inbox state grammar, including its pending,
processing, and presented-cleanup states. Other filenames never establish a
capture identity. Before import, the dual-inbox coordinator resolves all valid
entries with the same UUID and validates their PNG payloads.

A valid capture is removed from its source inbox only after successful import.
If the same logical identifier exists in both directories:

- identical bytes are imported once and both copies are removed after success;
- different bytes produce an explicit collision error and neither copy is
  removed.

Invalid, oversized, insecure, or malformed entries follow the existing bounded
quarantine-and-remove behavior and produce the existing batch error; they are
never opened or treated as duplicates. A transient scan, read, presentation,
commit, or cleanup failure preserves every not-yet-committed valid entry for a
later retry. Tests cover pending and recovered processing states in both roots,
invalid legacy entries, cleanup failure, and duplicate cleanup durability.

The app does not move the whole legacy application-support directory and does
not delete an empty legacy directory.

### 7.2 Screen Recording permission

The new bundle identifier creates a separate macOS privacy identity. Inkbeam
uses the existing Screen Recording permission flow and documents that users may
need to grant access again.

The app must not modify TCC databases, remove quarantine broadly, or claim that
MyShottr's permission transfers automatically.

If the user denies or defers permission, Inkbeam stops the capture attempt,
keeps the menu-bar app available, explains that Screen Recording access is
required, and offers to open the relevant System Settings page. Retrying after
the user grants access uses the same capture command; no alternate capture path
is introduced.

### 7.3 Side-by-side app behavior

`MyShottr.app` and `Inkbeam.app` can exist together, and their processes may
briefly overlap while Inkbeam detects the old app. Their capture services must
never be active together because both register `Command-Shift-2` and can rewrite
the legacy Native Messaging manifest.

Inkbeam checks for `com.myshottr.app` before any host registration or inbox
import at startup and through workspace app launch/termination notifications.
This covers both launch orders. While the old app runs, Inkbeam enters a
migration-blocked state: existing editor windows stay open, but Inkbeam does not
register the global shortcut, install or repair host manifests, consume inbox
notifications, or start a new capture. It presents one actionable message
asking the user to quit MyShottr and does not terminate the old app or take over
without user action.

After MyShottr terminates, Inkbeam atomically reinstalls and validates both host
manifests, starts its capture services, and scans both inboxes before declaring
the transition recovered. Installation docs tell users to quit and remove the
old app after confirming their projects open in Inkbeam.

## 8. Source and Package Rename Boundary

To satisfy this design, the rename must be completed in current live code rather
than limited to display strings. The implementation renames:

- `project.yml`, the generated Xcode project, Info.plist and entitlements paths,
  schemes, products, modules, targets, helper embed paths, and test targets;
- `Sources/MyShottrApp`, `Sources/MyShottrShared`, and
  `Sources/MyShottrNativeHost`;
- corresponding test directories and `@testable import` declarations;
- `MyShottr`-prefixed Swift domain and error types;
- package names, environment variables, bridge identifiers, URL schemes, and
  deterministic temporary-path prefixes;
- app metadata, document types, menus, alerts, and accessibility labels;
- `Packages/editor/package.json`, `Packages/chrome-extension/package.json`, and
  `Packages/chrome-extension/public/manifest.json`;
- `Packages/editor/index.html` and the editor's visual-test harness title;
- `Scripts/verify-v1.sh`, artifact verification and packaging scripts,
  `Scripts/render-release-notes.mjs`, README commands, release-note fixtures,
  and both GitHub workflow contracts.

The v0.2.0 icon pixels remain unchanged, but the live source assets and icon
generation inputs are renamed from `QuickInk-1024.png` and
`QuickInkStatus.svg` to Inkbeam-owned filenames. `Quick Ink` does not remain as
a current internal asset identity merely because the artwork is reused. The
icon-generation script and asset-catalog `Contents.json` references are updated
in the same change.

Legacy strings are isolated in named compatibility constants and tests. A brand
verification script rejects non-allowlisted `MyShottr`, `myshottr`, and
`com.myshottr` occurrences in current live surfaces.

The scan covers source and generated Xcode configuration plus the built app's
bundle metadata and executable strings, the built helper, the unpacked Chrome
output, both release archives, generated checksums, and release-note fixtures.
Finding an unallowlisted legacy identity in any shipped artifact fails the
release gate.

Historical files are not mass-rewritten. The allowlist contains exact paths and
reasons for:

- v0.1.0 release notes and evidence;
- historical design and implementation documents;
- `.myshottr`, `com.myshottr.project`, `com.myshottr.capture`, the old app
  bundle identifier, and the old application-support directory;
- the old capture-ready notification only in the identity map, historical
  sources, and tests proving live code no longer subscribes to it;
- tests that prove those compatibility contracts.

## 9. Repository and Release Transition

### 9.1 GitHub repository rename

The code migration is implemented and verified locally on a branch before the
external repository rename. Public `main` remains the accepted MyShottr v0.1.0
source until the repository has its new identity. Repo-coupled Inkbeam docs and
workflow contracts are never merged into `gihwan-dev/MyShottr`. The transition
order is:

1. implement the identity and compatibility changes on a local branch;
2. pass focused and full local verification at one exact commit;
3. record the commit, confirm a clean worktree, and freeze public `main` without
   creating a tag or release;
4. rename `gihwan-dev/MyShottr` to `gihwan-dev/inkbeam` through GitHub while
   `main` still contains the unchanged v0.1.0 source;
5. update the local `origin` URL and verify repository, clone, release, issue,
   and Actions redirects from the old URL;
6. push the unchanged migration branch to the renamed repository without
   updating `main`;
7. use the existing checked-in `workflow_dispatch` trigger to run fresh full CI
   on that branch and require the run's head SHA to equal the recorded commit;
8. integrate the verified branch into `main`, then prove remote `main` still
   equals that accepted commit;
9. perform interactive migration acceptance on that exact commit;
10. push `refs/notes/inkbeam-acceptance` attached to the exact release commit;
11. create and publish `v0.2.0` only after every release gate passes.

If GitHub refuses the rename, redirect verification fails, or CI does not run
under the new repository identity, the process stops before changing `main`,
tagging, or publishing v0.2.0. A failed post-rename gate leaves the renamed
repository on the accepted v0.1.0 `main` until the problem is resolved; it does
not trigger an automatic rename-back or history rewrite.

The local workspace directory is not renamed while the current Codex worktree
is active. Filesystem checkout naming is operational state, not public product
identity.

### 9.2 v0.1.0 preservation

The existing `v0.1.0` tag and release remain `MyShottr v0.1.0`. Its assets keep
their published names and hashes. The old acceptance note remains at
`refs/notes/myshottr-acceptance`.

Acceptance tooling selects the note namespace by release identity: historical
v0.1.0 validation continues to read `refs/notes/myshottr-acceptance`, while
Inkbeam v0.2.0 and later read `refs/notes/inkbeam-acceptance`. The new release
path must not make the historical note unreadable.

Repository redirect checks must prove that the old repository and v0.1.0
release URLs still reach their original content after the GitHub rename.
They assert exact final destinations for the repository root, the v0.1.0
release, one existing issue, and one existing Actions run rather than accepting
a redirect to a generic GitHub page.

### 9.3 v0.2.0 artifacts

The first Inkbeam release publishes exactly:

```text
Inkbeam-0.2.0-macos.zip
Inkbeam-Chrome-0.2.0.zip
SHA256SUMS.txt
```

The release title is `Inkbeam v0.2.0`. Release notes explain:

- the product and repository rename;
- `.myshottr` compatibility and the new `.inkbeam` default;
- the requirement to quit MyShottr before launching Inkbeam;
- possible Screen Recording reauthorization;
- replacement of the unpacked Chrome directory;
- continued unsigned and unnotarized distribution.

## 10. Security and Privacy Invariants

The rename changes identity, not trust boundaries.

- Captures, projects, inbox data, clipboard output, and exports stay local.
- The editor continues to block remote navigation and network access.
- The Chrome permission set remains exact.
- Native Messaging manifests retain owner-only permissions and exact origins.
- Both native host names point to the same helper inside the current app bundle.
- Legacy project loading uses the same strict schema and archive checks.
- Legacy inbox import uses explicit paths and never scans a broader directory.
- No credentials, accounts, analytics, telemetry, or cloud services are added.
- Unsigned and unnotarized limitations remain explicit in README and release
  notes.

## 11. Verification and Acceptance

### 11.1 Automated contracts

The implementation adds or updates tests for:

1. app, executable, helper, bundle, scheme, package, archive, and release names;
2. primary `.inkbeam` save and reopen with exact package members;
3. legacy `.myshottr` Finder/Open-panel open, in-place save, v0.1.0 reopen, and
   unsupported-version rejection;
4. primary and legacy UTI plus `CFBundleDocumentTypes` registration;
5. stable Chrome extension ID after the manifest rename;
6. exact extension permissions and `dev.gihwan.inkbeam.capture` usage;
7. atomic primary and legacy Native Messaging manifest registration, injected
   write failures, and stale helper-path repair;
8. new and legacy inbox import, UUID identity resolution, invalid-entry removal,
   identical duplicate handling, conflicting duplicate rejection, and retry
   after injected scan, commit, and cleanup failures;
9. both old/new app launch orders, capture-service suspension, and recovery
   without automatic termination;
10. denied Screen Recording permission, System Settings guidance, and retry;
11. `inkbeam-editor` navigation and `inkbeam` WebKit bridge ownership;
12. privacy, packaging, workflow, release-note, documentation, and brand-scan
    contracts;
13. absence of non-allowlisted legacy names in source and shipped artifacts.

The canonical `Scripts/verify-v1.sh` entry point will be renamed to
`Scripts/verify-inkbeam.sh`; a small `Scripts/verify-v1.sh` compatibility
launcher prints the new command and delegates for one release so existing
contributor instructions do not break abruptly. Its message, exit status, and
argument forwarding are contract-tested.

### 11.2 Interactive migration acceptance

The exact v0.2.0 candidate must demonstrate:

1. a v0.1.0 `.myshottr` project opens with identical source pixels and elements;
2. saving that project preserves its `.myshottr` path and reopens correctly;
3. the saved `.myshottr` project also reopens in MyShottr v0.1.0;
4. Finder and the Open panel both expose the legacy project to Inkbeam;
5. a new capture saves as `.inkbeam` and reopens correctly;
6. the v0.1.0 unpacked extension reaches Inkbeam through the legacy host;
7. the renamed extension reaches Inkbeam through the primary host;
8. a stale legacy host path is repaired after MyShottr exits;
9. Chrome captures still contain visible page pixels only;
10. denying Screen Recording produces the actionable System Settings flow, and
   retrying the same command succeeds after permission is granted;
11. native capture presents the normal Screen Recording flow for the new app
   identity and succeeds after permission is granted;
12. each app launch order produces the migration-blocked state; Inkbeam capture
    services stay suspended until MyShottr quits and recover afterward;
13. copy, export, R, T, undo, redo, and direct manipulation remain unchanged;
14. old repository, v0.1.0 release, issue, and Actions URLs resolve to their
    exact renamed-repository resources;
15. the new public archive names and SHA-256 checks match the release workflow;
16. no recovery chooser, upload, telemetry, or alternate capture mechanism
    appears.

## 12. Commit and Delivery Structure

Implementation and delivery are split into reviewable stages with no mixed
release mutation:

1. rename compiled products, modules, live source symbols, editor identity, and
   current tests;
2. add `.inkbeam` identity and permanent `.myshottr` project compatibility;
3. add Native Messaging, inbox, and side-by-side migration contracts;
4. rename packages, documentation, scripts, workflows, and artifact contracts;
5. complete local verification and freeze the accepted commit;
6. rename the GitHub repository, update `origin`, and verify redirects;
7. push the migration branch, pass renamed-repository CI, and integrate it into
   `main`;
8. attach exact acceptance evidence and publish v0.2.0.

The GitHub rename, tag, and release are not combined with unverified code
changes. A failed gate stops the sequence without deleting or rewriting v0.1.0.
All generated Xcode project changes, built-editor resource manifests, and other
tracked generated rename artifacts are committed at the accepted source commit;
release verification must not depend on later uncommitted regeneration.

## 13. Completion Criteria

The migration is complete only when:

- every live user-facing surface says `Inkbeam`;
- every compiled product and current package uses the Inkbeam identity;
- new `.inkbeam` and legacy `.myshottr` round trips pass;
- an Inkbeam-saved `.myshottr` project remains readable by MyShottr v0.1.0;
- both transition Native Messaging host names are verified;
- either app launch order suspends Inkbeam capture until MyShottr exits and then
  recovers both host manifests and inbox scanning;
- full local and renamed-repository CI pass at the exact commit;
- the old repository and v0.1.0 release URLs redirect correctly;
- `gihwan-dev/inkbeam` is public and its `main` points to the accepted commit;
- `v0.2.0` is a non-draft public Inkbeam release with verified checksums;
- v0.1.0 remains available and unchanged;
- the worktree is clean and no unrelated user changes were modified.
