# MyShottr Recovery, Hardening, and Acceptance Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add crash recovery, actionable errors, privacy boundary checks, and a single repeatable acceptance gate that proves the complete public-release candidate.

**Architecture:** `RecoveryStore` writes one debounced package per modified open document and `RecoveryCoordinator` offers restore only after abnormal termination. Typed error presenters map every capture, bridge, project, and export failure to one explicit UI action, while scripts and integration tests verify privacy and product-wide acceptance.

**Tech Stack:** Swift 6, Swift Concurrency, AppKit, XCTest, Vitest, Playwright, shell verification scripts

## Global Constraints

- Execute this plan after the foundation/editor, public-editor-polish,
  native-capture, and Chrome-capture plans.
- Recovery retains only the latest recoverable state per open document and is not a capture history.
- A clean save or explicit discard deletes the associated recovery package.
- No error may silently switch capture mechanisms, discard elements, or overwrite a valid destination.
- All editor assets, captures, projects, inbox files, and recovery packages remain local.
- The editor must reject non-file navigation and have no remote runtime dependency.
- Chrome must keep exactly `activeTab` and `nativeMessaging` permissions.
- v1 does not add accounts, analytics, telemetry, auto-update, signing automation, notarization, or App Store packaging.
- Use TDD for behavior and commit after every task.

---

## Repository Map for This Plan

```text
Scripts/
├── verify-privacy.sh
└── verify-v1.sh
Sources/MyShottrApp/
├── App/
│   └── UserFacingErrorPresenter.swift
├── Documents/
│   ├── RecoveryCoordinator.swift
│   ├── RecoveryStore.swift
│   └── SessionTerminationState.swift
└── Editor/
    └── EditorNavigationPolicy.swift
Tests/MyShottrTests/
├── App/UserFacingErrorPresenterTests.swift
├── Documents/RecoveryCoordinatorTests.swift
├── Documents/RecoveryStoreTests.swift
└── Editor/EditorNavigationPolicyTests.swift
docs/testing/
└── v1-acceptance.md
```

## Shared Interfaces

```swift
protocol RecoveryStoring: Sendable {
    func write(_ project: MyShottrProject, documentId: UUID) throws
    func remove(documentId: UUID) throws
    func recoverableProjects() throws -> [RecoveredProject]
}

struct RecoveredProject: Equatable, Sendable {
    let documentId: UUID
    let modifiedAt: Date
    let project: MyShottrProject
}

@MainActor
protocol UserFacingErrorPresenting {
    func present(_ error: MyShottrUserFacingError, from window: NSWindow?)
}
```

### Task 1: Debounced Current-Document Recovery

**Files:**
- Create: `Sources/MyShottrApp/Documents/RecoveryStore.swift`
- Create: `Sources/MyShottrApp/Documents/SessionTerminationState.swift`
- Create: `Sources/MyShottrApp/Documents/RecoveryCoordinator.swift`
- Modify: `Sources/MyShottrApp/Documents/DocumentSession.swift`
- Modify: `Sources/MyShottrApp/Documents/DocumentWindowController.swift`
- Modify: `Sources/MyShottrApp/App/AppDelegate.swift`
- Test: `Tests/MyShottrTests/Documents/RecoveryStoreTests.swift`
- Test: `Tests/MyShottrTests/Documents/RecoveryCoordinatorTests.swift`
- Test support: `Tests/MyShottrTests/Support/RecoveryFakes.swift`

**Interfaces:**
- Consumes: `MyShottrProject`, `ProjectPackageStore`, and document change snapshots.
- Produces: `RecoveryStore`, two-second debounce, abnormal-exit detection, restore/discard prompt.

- [ ] **Step 1: Write failing recovery-store tests**

Use an injected temporary root and assert:

```swift
func testWriteReplacesOnlySameDocumentRecovery() throws {
    let store = try RecoveryStore(root: temporaryDirectory)
    try store.write(ProjectFixtures.project(text: "first"), documentId: Fixtures.id)
    try store.write(ProjectFixtures.project(text: "second"), documentId: Fixtures.id)

    let recovered = try store.recoverableProjects()
    XCTAssertEqual(recovered.count, 1)
    XCTAssertEqual(recovered[0].project, ProjectFixtures.project(text: "second"))
}

func testRemoveDeletesRecoveryAfterCleanSave() throws {
    let store = try RecoveryStore(root: temporaryDirectory)
    try store.write(ProjectFixtures.sampleProject(), documentId: Fixtures.id)
    try store.remove(documentId: Fixtures.id)
    XCTAssertTrue(try store.recoverableProjects().isEmpty)
}
```

Also reject symlinks, packages with invalid members, unsupported project
versions, and assert the store creates or normalizes its root to mode `0700`.

- [ ] **Step 2: Write failing debounce and launch-state tests**

Inject a controllable `ContinuousClock` wrapper:

```swift
@MainActor
func testChangesWithinTwoSecondsProduceOneRecoveryWrite() async {
    session.applySnapshot(Fixtures.snapshot1)
    clock.advance(by: .seconds(1))
    session.applySnapshot(Fixtures.snapshot2)
    clock.advance(by: .seconds(2))

    XCTAssertEqual(recoverySpy.writes.map(\.project.annotationJSON),
                   [Fixtures.snapshot2])
}

func testCleanTerminationDoesNotOfferRecovery() throws {
    terminationState.markCleanExit()
    XCTAssertFalse(try coordinator.shouldOfferRecovery())
}
```

`RecoveryFakes.swift` provides an injected manual clock, a
`SpyRecoveryStore`, and a fixed `now` date. The manual clock resumes scheduled
tasks only when `advance(by:)` crosses their deadline, so the debounce test
does not sleep in wall-clock time.

- [ ] **Step 3: Run focused tests and verify failure**

Run:

```bash
xcodebuild test -project MyShottr.xcodeproj -scheme MyShottr \
  -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO \
  -only-testing:MyShottrTests/RecoveryStoreTests \
  -only-testing:MyShottrTests/RecoveryCoordinatorTests
```

Expected: missing-type compilation failures.

- [ ] **Step 4: Implement recovery and termination state**

`RecoveryStore` root is
`~/Library/Application Support/MyShottr/Recovery` with mode `0700`. Store each
document as `<document-id>.myshottr` through `ProjectPackageStore` atomic save.
`recoverableProjects()` validates every package and sorts newest first.

`DocumentSession` cancels the previous scheduled task and writes the latest
validated annotation snapshot after two seconds without a new change. It
removes recovery after successful Save or explicit Discard, not after failed
Save, Cancel, or abnormal termination.

`SessionTerminationState` maintains
`~/Library/Application Support/MyShottr/session.json`:

```json
{ "schemaVersion": 1, "cleanExit": false }
```

App launch atomically writes `cleanExit: false`; normal
`applicationWillTerminate` writes `true`.

After an unclean prior exit, `RecoveryCoordinator` presents one list of valid
recovery packages with Restore and Discard All. Restore opens each selected
project as a modified unsaved document. Discard All deletes them. It never
automatically opens or deletes recovery data.

- [ ] **Step 5: Run recovery tests and complete native suite**

Run:

```bash
xcodebuild test -project MyShottr.xcodeproj -scheme MyShottr \
  -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO
```

Expected: all recovery and existing native tests pass.

- [ ] **Step 6: Commit recovery**

```bash
git add Sources/MyShottrApp/Documents Sources/MyShottrApp/App/AppDelegate.swift \
  Tests/MyShottrTests/Documents
git commit -m "feat: recover modified documents after crashes"
```

### Task 2: Typed Actionable Error Presentation

**Files:**
- Create: `Sources/MyShottrApp/App/MyShottrUserFacingError.swift`
- Create: `Sources/MyShottrApp/App/UserFacingErrorPresenter.swift`
- Modify: `Sources/MyShottrApp/Capture/RegionCaptureCoordinator.swift`
- Modify: `Sources/MyShottrApp/Chrome/CaptureInboxCoordinator.swift`
- Modify: `Sources/MyShottrApp/Documents/DocumentWindowController.swift`
- Modify: `Sources/MyShottrApp/Editor/EditorBridge.swift`
- Test: `Tests/MyShottrTests/App/UserFacingErrorPresenterTests.swift`

**Interfaces:**
- Consumes: capture, permission, project, bridge, inbox, save, and composite errors.
- Produces: one exhaustive `MyShottrUserFacingError` mapping with title, message, and zero or one recovery action.

- [ ] **Step 1: Write exhaustive mapping tests**

Test every case:

```swift
func testPermissionDeniedOffersSystemSettings() {
    let viewModel = MyShottrUserFacingError.capture(.screenRecordingPermissionDenied).viewModel
    XCTAssertEqual(viewModel.title, "Screen Recording Permission Required")
    XCTAssertEqual(viewModel.primaryAction, .openScreenRecordingSettings)
}

func testUnsupportedProjectDoesNotOfferPartialImport() {
    let viewModel = MyShottrUserFacingError
        .project(.unsupportedFormatVersion(2))
        .viewModel
    XCTAssertEqual(viewModel.primaryAction, .dismiss)
    XCTAssertFalse(viewModel.message.contains("partially"))
}
```

The test table must cover:

- Screen Recording permission denied
- capture display unavailable
- ScreenCaptureKit failure
- native host unavailable
- invalid or oversized Chrome message
- invalid inbox PNG
- invalid editor bridge message
- corrupt or unsupported project
- project save failure
- PNG export failure
- composite transfer failure
- global shortcut conflict

- [ ] **Step 2: Run the focused test and verify failure**

Run:

```bash
xcodebuild test -project MyShottr.xcodeproj -scheme MyShottr \
  -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO \
  -only-testing:MyShottrTests/UserFacingErrorPresenterTests
```

Expected: missing `MyShottrUserFacingError`.

- [ ] **Step 3: Implement one presenter and route all failure paths**

Define:

```swift
enum UserFacingErrorAction: Equatable {
    case dismiss
    case openScreenRecordingSettings
    case openChromeSetupInstructions
    case retrySameOperation
}

struct UserFacingErrorViewModel: Equatable {
    let title: String
    let message: String
    let primaryAction: UserFacingErrorAction
}
```

`UserFacingErrorPresenter` uses `NSAlert` as a sheet when a document window is
available and modal otherwise. `retrySameOperation` is offered only where the
same operation is safe and idempotent; it never changes capture mechanism.

Every coordinator catches its typed domain error and forwards exactly one
`MyShottrUserFacingError`. Domain types do not present alerts themselves.
Failed save/export keeps `DocumentSession.isModified == true`; invalid project
and inbox imports never open a partial editor document.

- [ ] **Step 4: Verify error tests and native suite**

Run:

```bash
xcodebuild test -project MyShottr.xcodeproj -scheme MyShottr \
  -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO
```

Expected: all mapping and existing tests pass.

- [ ] **Step 5: Commit error surfaces**

```bash
git add Sources/MyShottrApp Tests/MyShottrTests/App
git commit -m "feat: present actionable capture and document errors"
```

### Task 3: Editor Navigation and Privacy Gate

**Files:**
- Create: `Sources/MyShottrApp/Editor/EditorNavigationPolicy.swift`
- Modify: `Sources/MyShottrApp/Editor/EditorWebView.swift`
- Create: `Tests/MyShottrTests/Editor/EditorNavigationPolicyTests.swift`
- Create: `Scripts/verify-privacy.sh`
- Modify: `Packages/chrome-extension/tests/service-worker.test.ts`

**Interfaces:**
- Consumes: WKWebView navigation actions, built editor assets, and built extension manifest.
- Produces: a deny-by-default navigation policy and a repeatable privacy verification command.

- [ ] **Step 1: Write failing navigation-policy tests**

Assert:

```swift
func testAllowsOnlyBundledFileNavigation() {
    XCTAssertEqual(policy.decision(for: URL(string: "file:///App/Editor/index.html")!), .allow)
    XCTAssertEqual(policy.decision(for: URL(string: "https://example.com")!), .cancel)
    XCTAssertEqual(policy.decision(for: URL(string: "http://localhost:3000")!), .cancel)
    XCTAssertEqual(policy.decision(for: URL(string: "data:text/html,test")!), .cancel)
}
```

The editor web view test must assert `javaScriptCanOpenWindowsAutomatically ==
false` and no custom user scripts include an `http:` or `https:` string.

- [ ] **Step 2: Run focused tests and verify failure**

Run:

```bash
xcodebuild test -project MyShottr.xcodeproj -scheme MyShottr \
  -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO \
  -only-testing:MyShottrTests/EditorNavigationPolicyTests
```

Expected: missing navigation policy.

- [ ] **Step 3: Implement deny-by-default navigation**

`EditorNavigationPolicy` allows only `file:` URLs whose standardized path is
inside the bundled `Resources/Editor` directory. It cancels every other scheme,
new-window request, download, and external navigation.

Create `Scripts/verify-privacy.sh`:

```bash
#!/bin/zsh
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
EDITOR_DIST="${REPO_ROOT}/Packages/editor/dist"
EDITOR_SOURCE="${REPO_ROOT}/Packages/editor/src"
EXTENSION_MANIFEST="${REPO_ROOT}/Packages/chrome-extension/dist/manifest.json"

if rg -n "https?://|src=['\"]//|href=['\"]//" "${EDITOR_DIST}/index.html"; then
  echo "Remote asset found in bundled editor entrypoint" >&2
  exit 1
fi

if rg -n 'fetch\(|XMLHttpRequest\(|new WebSocket\(|EventSource\(' "${EDITOR_SOURCE}"; then
  echo "Network API found in editor source" >&2
  exit 1
fi

node -e '
const fs = require("fs");
const manifest = JSON.parse(fs.readFileSync(process.argv[1], "utf8"));
const expected = ["activeTab", "nativeMessaging"];
if (JSON.stringify(manifest.permissions) !== JSON.stringify(expected)) process.exit(1);
if (manifest.host_permissions || manifest.content_scripts) process.exit(1);
' "${EXTENSION_MANIFEST}"
```

The extension unit test also asserts no source file registers
`chrome.scripting`, `chrome.webRequest`, or a content script.

- [ ] **Step 4: Run privacy and complete tests**

Run:

```bash
pnpm build
pnpm test
Scripts/verify-privacy.sh
xcodebuild test -project MyShottr.xcodeproj -scheme MyShottr \
  -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO
```

Expected: all commands exit `0`.

- [ ] **Step 5: Commit privacy hardening**

```bash
git add Sources/MyShottrApp/Editor Tests/MyShottrTests/Editor \
  Packages/chrome-extension/tests Scripts/verify-privacy.sh
git commit -m "test: enforce local-only editor and extension permissions"
```

### Task 4: Complete v1 Release-Candidate Verification

**Files:**
- Create: `Scripts/verify-v1.sh`
- Create: `docs/testing/v1-acceptance.md`
- Modify: `README.md`

**Interfaces:**
- Consumes: every product subsystem and test suite.
- Produces: one automated gate, one manual acceptance record, and local release-candidate setup instructions.

- [ ] **Step 1: Add the automated verification script**

Create `Scripts/verify-v1.sh`:

```bash
#!/bin/zsh
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "${REPO_ROOT}"

pnpm install --frozen-lockfile
pnpm test
pnpm typecheck
pnpm build
pnpm --filter @myshottr/chrome-extension exec playwright install chromium
pnpm --filter @myshottr/chrome-extension exec playwright test
Scripts/verify-privacy.sh

xcodegen generate
xcodebuild test \
  -project MyShottr.xcodeproj \
  -scheme MyShottr \
  -destination 'platform=macOS' \
  CODE_SIGNING_ALLOWED=NO
xcodebuild test \
  -project MyShottr.xcodeproj \
  -scheme MyShottrNativeHost \
  -destination 'platform=macOS' \
CODE_SIGNING_ALLOWED=NO
xcodebuild build \
  -project MyShottr.xcodeproj \
  -scheme MyShottr \
  -configuration Debug \
  -destination 'platform=macOS'
```

- [ ] **Step 2: Write the manual acceptance template and local candidate setup**

`docs/testing/v1-acceptance.md` must record date, macOS version, Chrome version,
tested commit SHA, and pass/fail evidence fields for:

1. `Command-Shift-2` opens region selection.
2. `Escape` cancels without a document.
3. a Retina region opens at exact source pixel dimensions.
4. the overlay is absent from the captured PNG.
5. Chrome action captures visible page content without browser chrome.
6. Chrome `Option-Shift-2` runs the same capture flow.
7. selection, rectangle, arrow, line, text, freehand, highlighter, blur, opaque
   redaction, and number-marker tools work.
8. move, resize, rotate, duplicate, delete, reorder, multi-select, undo, and
   redo work.
9. Copy pastes a PNG into macOS Notes.
10. exported PNG dimensions equal source dimensions.
11. `.myshottr` Save, close, and reopen preserve source pixels, element JSON,
    and `presentation: none`; a schema-1 fixture migrates to schema 2.
12. closing a modified document offers Save, Discard, and Cancel.
13. forced app termination offers the latest recovery package on next launch.
14. Screen Recording denial gives the System Settings action.
15. missing Chrome host manifest reports host unavailable without native
    capture.
16. unsupported project version refuses to open without partial import.
17. failed export leaves the document modified and destination untouched.
18. `Scripts/verify-privacy.sh` passes on the exact built artifacts.

`README.md` must include:

```text
Prerequisites: macOS 15+, Xcode 26+, Node 22+, pnpm 10+, XcodeGen.
Build: Scripts/verify-v1.sh
Run: open the Debug MyShottr.app from DerivedData.
Chrome: load Packages/chrome-extension/dist as an unpacked extension.
First launch: open MyShottr once so it registers the Native Messaging host.
Permission: grant Screen Recording when macOS prompts, then relaunch MyShottr.
```

Also list the v1 non-goals from the design so early users do not interpret
missing Safari, full-page capture, OCR, or history as defects.

- [ ] **Step 3: Run the candidate gate and commit the final candidate**

Run:

```bash
chmod +x Scripts/*.sh
Scripts/verify-v1.sh
git add README.md Scripts/verify-v1.sh docs/testing/v1-acceptance.md
git commit -m "docs: add MyShottr v1 acceptance gate"
```

Expected: verification passes before the commit, and the commit succeeds.

- [ ] **Step 4: Verify the exact final candidate SHA**

```bash
TESTED_SHA="$(git rev-parse HEAD)"
Scripts/verify-v1.sh
git status --short
```

Expected: the gate passes and status is empty. Keep `TESTED_SHA` for the
manual record; do not modify tracked files after this point.

- [ ] **Step 5: Execute the manual checklist and attach exact-SHA evidence**

Copy `docs/testing/v1-acceptance.md` to a temporary report, complete all 18
result fields, and attach it to the tested commit without changing that commit:

```bash
TESTED_SHA="$(git rev-parse HEAD)"
REPORT_PATH="/tmp/myshottr-v1-acceptance-${TESTED_SHA}.md"
cp docs/testing/v1-acceptance.md "${REPORT_PATH}"
open -e "${REPORT_PATH}"
git notes --ref=myshottr-acceptance add -F "${REPORT_PATH}" "${TESTED_SHA}"
```

Expected: every item in the temporary report is marked PASS before the
`git notes` command. A failed item stops completion and remains unrecorded as a
passing release.

- [ ] **Step 6: Verify the evidence points to the clean tested commit**

Run:

```bash
TESTED_SHA="$(git rev-parse HEAD)"
git notes --ref=myshottr-acceptance show "${TESTED_SHA}"
git status --short
```

Expected: the note shows the date, environment, `TESTED_SHA`, and 18 PASS
entries; worktree status is empty.

## Plan 4 Completion Gate

MyShottr v1 is complete only when `Scripts/verify-v1.sh` passes at the final
commit and `refs/notes/myshottr-acceptance` contains all 18 passing checks
attached to that exact commit SHA. A nearly complete checklist, a static-only
build, or an unverified Chrome/native bridge is not completion.
