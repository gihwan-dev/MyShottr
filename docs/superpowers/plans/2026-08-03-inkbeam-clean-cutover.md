# Inkbeam Clean Cutover Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace every live MyShottr product contract with the approved Inkbeam identity, accept only editable `.inkbeam` packages, and leave exactly one Inkbeam Chrome Native Messaging path without a compatibility, migration, recovery, or full-page fallback.

**Architecture:** Perform one clean namespace cut at the build graph first, then move the Swift, WebKit, editor, Chrome, document, and local-inbox contracts behind the exact identity matrix. Preserve the current annotation schema and capture request boundary, but reject pre-Inkbeam files and preferences instead of migrating them. Finish with a file-level allowlisted source scan and the existing behavioral suites.

**Tech Stack:** Swift 6, AppKit, WebKit, XcodeGen, XCTest, TypeScript, React, Vite, Chrome Manifest V3, Node 22, pnpm 10.14, Playwright

## Global Constraints

- This is program step 1. Complete it before `2026-08-03-inkbeam-sparkle-updater.md`, `2026-08-03-inkbeam-direct-release-pipeline.md`, and `2026-08-03-inkbeam-v0.2.0-rollout.md`.
- The authoritative contract is `docs/superpowers/specs/2026-08-03-inkbeam-v0.2.0-official-release-design.md`.
- Use the exact identities below; do not introduce aliases, compatibility reads, fallback hosts, dual inboxes, old UserDefaults keys, or old project extensions.
- Preserve the committed Chrome manifest public key and deterministic extension ID. It is public identity material and must not be regenerated.
- Preserve Chrome permissions as exactly `activeTab` and `nativeMessaging`. Keep `fullPage` rejected before capture or Native Messaging.
- Preserve the strict three-member project package, immutable original pixels, and annotation schema version 3. Reject older annotation schemas instead of migrating them.
- Historical `v0.1.0` release artifacts, notes, Git history, the superseded specs, and the authoritative spec keep historical wording. Every scanner exception is an exact file path; no directory-wide documentation exception is allowed.
- Use `git mv` only for path-only renames and `apply_patch` for content changes. Do not rewrite Git history.
- Regenerate `Inkbeam.xcodeproj` after changing `project.yml`; do not hand-edit generated project files.
- Run Xcode test schemes serially and stop running Inkbeam processes before Xcode builds to avoid `build.db` contention.
- Commit after every task. A failing build, test, clean-cut scan, or visible-viewport assertion stops the task.

---

## Exact Identity Contract

| Surface | Value |
| --- | --- |
| App / project / scheme / executable | `Inkbeam` |
| App bundle ID | `dev.gihwan.inkbeam` |
| Helper executable | `InkbeamNativeHost` |
| Helper bundle ID | `dev.gihwan.inkbeam.nativehost` |
| Native Messaging host | `dev.gihwan.inkbeam.capture` |
| Capture notification | `dev.gihwan.inkbeam.captureReady` |
| Application Support / inbox | `Inkbeam` / `Inkbeam/Inbox` |
| Project extension / UTI | `.inkbeam` / `dev.gihwan.inkbeam.project` |
| Editor URL scheme / WK handler | `inkbeam-editor` / `inkbeam` |
| JS packages | `@inkbeam/editor`, `@inkbeam/chrome-extension` |
| Swift source / test roots | `InkbeamApp`, `InkbeamNativeHost`, `InkbeamShared`, `InkbeamTests`, `InkbeamNativeHostTests` |

## Target Repository Map

```text
Config/
├── Inkbeam-Info.plist
├── Inkbeam.entitlements
└── chrome-extension-key.b64
Sources/
├── InkbeamApp/
├── InkbeamNativeHost/
└── InkbeamShared/
Tests/
├── InkbeamTests/
├── InkbeamNativeHostTests/
└── Release/
Packages/
├── editor/
└── chrome-extension/
Scripts/
├── verify-clean-cutover.mjs
└── verify-inkbeam.sh
```

### Task 1: Cut Over the Build Graph and Public Metadata

**Files:**
- Create: `Tests/Release/identity-contract.test.mjs`
- Modify: `package.json`, `project.yml`, `pnpm-lock.yaml`
- Rename: `Config/MyShottr-Info.plist` -> `Config/Inkbeam-Info.plist`
- Rename: `Config/MyShottr.entitlements` -> `Config/Inkbeam.entitlements`
- Rename: `Sources/MyShottrApp` -> `Sources/InkbeamApp`
- Rename: `Sources/MyShottrNativeHost` -> `Sources/InkbeamNativeHost`
- Rename: `Sources/MyShottrShared` -> `Sources/InkbeamShared`
- Rename: `Tests/MyShottrTests` -> `Tests/InkbeamTests`
- Rename: `Tests/MyShottrNativeHostTests` -> `Tests/InkbeamNativeHostTests`
- Rename: `Assets/AppIcon/QuickInk-1024.png` -> `Assets/AppIcon/Inkbeam-1024.png`
- Rename: `Assets/StatusBar/QuickInkStatus.svg` -> `Assets/StatusBar/InkbeamStatus.svg`
- Rename: `docs/images/editor-quick-ink.png` -> `docs/images/editor-inkbeam.png`

- [ ] **Step 1: Add the failing identity contract**

Create `Tests/Release/identity-contract.test.mjs` with the exact public contract:

```js
import assert from "node:assert/strict";
import fs from "node:fs";
import test from "node:test";

const read = (path) => fs.readFileSync(path, "utf8");

test("the build graph exposes only Inkbeam identities", () => {
  const project = read("project.yml");
  const appInfo = read("Config/Inkbeam-Info.plist");
  const rootPackage = JSON.parse(read("package.json"));
  const editorPackage = JSON.parse(read("Packages/editor/package.json"));
  const chromePackage = JSON.parse(read("Packages/chrome-extension/package.json"));

  assert.match(project, /^name: Inkbeam$/m);
  assert.match(project, /PRODUCT_BUNDLE_IDENTIFIER: dev\.gihwan\.inkbeam$/m);
  assert.match(project, /PRODUCT_BUNDLE_IDENTIFIER: dev\.gihwan\.inkbeam\.nativehost$/m);
  assert.match(project, /CFBundleTypeExtensions: \[inkbeam\]/);
  assert.match(project, /UTTypeIdentifier: dev\.gihwan\.inkbeam\.project/);
  assert.doesNotMatch(project, /com\.myshottr|\.myshottr|MyShottr/);
  assert.match(appInfo, /dev\.gihwan\.inkbeam\.project/);
  assert.match(appInfo, /<string>inkbeam<\/string>/);
  assert.equal(rootPackage.name, "inkbeam");
  assert.equal(editorPackage.name, "@inkbeam/editor");
  assert.equal(chromePackage.name, "@inkbeam/chrome-extension");
});
```

Append it to `test:release` in `package.json` before the other release tests.

- [ ] **Step 2: Run RED**

```bash
node --test Tests/Release/identity-contract.test.mjs
```

Expected: FAIL because `Config/Inkbeam-Info.plist` and the Inkbeam identities do not exist.

- [ ] **Step 3: Rename the path graph and set exact XcodeGen identities**

Use path-only moves, then update `project.yml` so its target skeleton is exactly:

```yaml
name: Inkbeam
options:
  bundleIdPrefix: dev.gihwan
targets:
  Inkbeam:
    type: application
    platform: macOS
    dependencies:
      - target: InkbeamNativeHost
        embed: false
        link: false
    sources:
      - Sources/InkbeamApp
      - Sources/InkbeamShared
    info:
      path: Config/Inkbeam-Info.plist
    entitlements:
      path: Config/Inkbeam.entitlements
    settings:
      base:
        PRODUCT_BUNDLE_IDENTIFIER: dev.gihwan.inkbeam
        PRODUCT_NAME: Inkbeam
  InkbeamTests:
    type: bundle.unit-test
    platform: macOS
    sources:
      - Tests/InkbeamTests
    dependencies:
      - target: Inkbeam
  InkbeamNativeHost:
    type: tool
    platform: macOS
    sources:
      - Sources/InkbeamNativeHost
      - Sources/InkbeamShared
    settings:
      base:
        PRODUCT_BUNDLE_IDENTIFIER: dev.gihwan.inkbeam.nativehost
  InkbeamNativeHostTests:
    type: bundle.unit-test
    platform: macOS
    sources:
      - Tests/InkbeamNativeHostTests
      - path: Sources/InkbeamNativeHost
        excludes: [main.swift]
      - Sources/InkbeamShared
    dependencies:
      - target: InkbeamNativeHost
schemes:
  Inkbeam:
    build:
      targets:
        Inkbeam: all
        InkbeamTests: [test]
    test:
      targets: [InkbeamTests]
  InkbeamNativeHost:
    build:
      targets:
        InkbeamNativeHost: all
        InkbeamNativeHostTests: [test]
    test:
      targets: [InkbeamNativeHostTests]
```

Keep the existing deployment target, assets, editor prebuild, helper embed phase, test fixture resources, and Swift settings around this skeleton. Change the helper copy source and destination to `InkbeamNativeHost`.

`MyShottr.xcodeproj` is generated and currently untracked. Before generating
the new project, confirm `git ls-files -- MyShottr.xcodeproj` is empty and, if
the exact directory exists, move only that resolved directory to Finder Trash.
Do not recursively delete a glob or another project path.

- [ ] **Step 4: Update the plist, packages, lockfile, and build scripts**

Set the document declaration in both `project.yml` and `Config/Inkbeam-Info.plist` to:

```xml
<key>CFBundleDocumentTypes</key>
<array><dict>
  <key>CFBundleTypeName</key><string>Inkbeam Project</string>
  <key>CFBundleTypeExtensions</key><array><string>inkbeam</string></array>
  <key>CFBundleTypeRole</key><string>Editor</string>
  <key>LSHandlerRank</key><string>Owner</string>
  <key>LSItemContentTypes</key><array><string>dev.gihwan.inkbeam.project</string></array>
</dict></array>
```

Rename package names and every `pnpm --filter` call to `@inkbeam/*`, then run `pnpm install --lockfile-only` so the checked-in lockfile is generated rather than manually edited.

Update `Scripts/generate-app-iconset.sh` and asset configuration/tests to use
the two Inkbeam source filenames. Regenerate the existing `AppIcon.appiconset`
from `Assets/AppIcon/Inkbeam-1024.png`; preserve the approved image pixels and
status-bar template behavior rather than inventing a second icon during the
namespace cut.

- [ ] **Step 5: Generate and run GREEN**

```bash
pnpm install --frozen-lockfile
xcodegen generate
node --test Tests/Release/identity-contract.test.mjs
xcodebuild -list -project Inkbeam.xcodeproj
```

Expected: PASS; the project lists only `Inkbeam` and `InkbeamNativeHost` schemes.

- [ ] **Step 6: Commit**

```bash
git add project.yml package.json pnpm-lock.yaml Config Sources Tests Scripts Packages Assets Resources
git commit -m "refactor(brand): cut build graph over to Inkbeam"
```

### Task 2: Rename Swift Product Types Without Aliases

**Files:**
- Rename: `Sources/InkbeamApp/App/MyShottrApp.swift` -> `Sources/InkbeamApp/App/InkbeamApp.swift`
- Rename: `Sources/InkbeamApp/App/MyShottrUserFacingError.swift` -> `Sources/InkbeamApp/App/InkbeamUserFacingError.swift`
- Rename: `Sources/InkbeamApp/Documents/MyShottrProject.swift` -> `Sources/InkbeamApp/Documents/InkbeamProject.swift`
- Modify: all Swift files under `Sources/InkbeamApp`, `Sources/InkbeamNativeHost`, `Sources/InkbeamShared`
- Modify: all Swift tests under `Tests/InkbeamTests`, `Tests/InkbeamNativeHostTests`

- [ ] **Step 1: Make renamed-type tests fail**

Rename `AppConfigurationTests` and project fixture references first, and assert these symbols compile:

```swift
func testInkbeamProjectPreservesOriginalPixels() {
    let project = InkbeamProject.fixture()
    XCTAssertEqual(project.originalPNG, PNGFixture.source2x)
}

func testProductErrorNamesInkbeam() {
    let error = InkbeamUserFacingError.wrapping(
        CaptureError.cancelled,
        context: .capture
    )
    XCTAssertFalse(error.title.contains("MyShottr"))
}
```

Run:

```bash
xcodebuild test -project Inkbeam.xcodeproj -scheme Inkbeam \
  -destination 'platform=macOS' -only-testing:InkbeamTests/AppConfigurationTests
```

Expected: FAIL because the new Swift symbols do not exist.

- [ ] **Step 2: Rename, do not alias, product symbols**

Make the project contract exact:

```swift
struct InkbeamProject: Equatable, Sendable {
    var manifest: ProjectManifest
    let originalPNG: Data
    var annotationJSON: Data
}

protocol ProjectPackageStoring: Sendable {
    func load(from url: URL) throws -> InkbeamProject
    func save(_ project: InkbeamProject, to url: URL) throws
}

@main
struct InkbeamApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    // Preserve the existing scene and command contents.
}
```

Rename `MyShottrUserFacingError` to `InkbeamUserFacingError` at every presenter and call site. Do not leave typealiases from old symbols.

- [ ] **Step 3: Rename live UI, identifiers, temporary prefixes, and test environment variables**

Use `Inkbeam`, `dev.gihwan.inkbeam.*`, `.inkbeam-*`, and `INKBEAM_NATIVE_HOST_TEST_*` in live code. Include window titles, toolbar identifiers, status item tooltip, quit menu, app activation, test-process environment, temporary directories, and diagnostics.

- [ ] **Step 4: Run GREEN and compile both architectures**

```bash
xcodegen generate
xcodebuild test -project Inkbeam.xcodeproj -scheme Inkbeam \
  -destination 'platform=macOS'
xcodebuild test -project Inkbeam.xcodeproj -scheme InkbeamNativeHost \
  -destination 'platform=macOS'
xcodebuild build -project Inkbeam.xcodeproj -scheme Inkbeam \
  -configuration Debug -destination 'generic/platform=macOS' \
  ARCHS='arm64 x86_64' ONLY_ACTIVE_ARCH=NO CODE_SIGNING_ALLOWED=NO
```

Expected: all tests pass and both app/helper binaries contain `arm64` and `x86_64`.

- [ ] **Step 5: Commit**

```bash
git add Sources Tests project.yml
git commit -m "refactor(brand): rename live Swift namespaces"
```

### Task 3: Enforce `.inkbeam`-Only Documents and Current Preferences

**Files:**
- Delete: `Sources/InkbeamApp/Documents/EditorDocumentMigrator.swift`
- Delete: `Tests/InkbeamTests/Documents/EditorDocumentMigratorTests.swift`
- Modify: `Sources/InkbeamApp/Documents/ProjectPackageStore.swift`
- Modify: `Sources/InkbeamApp/Documents/DocumentWindowController.swift`
- Modify: `Sources/InkbeamApp/App/AppDelegate.swift`
- Modify: `Sources/InkbeamApp/Preferences/EditorPreferencesStore.swift`
- Modify: related document, plist, preference, and fixture tests

- [ ] **Step 1: Add failing rejection tests**

```swift
func testLoadRejectsOlderAnnotationSchemaInsteadOfMigrating() throws {
    let packageURL = try makeProjectPackage(
        extension: "inkbeam",
        schemaVersion: 2
    )
    XCTAssertThrowsError(try ProjectPackageStore().load(from: packageURL)) {
        XCTAssertEqual($0 as? ProjectPackageError, .invalidAnnotationJSON)
    }
}

func testOpenPanelAllowsOnlyInkbeamProjects() {
    XCTAssertEqual(AppDelegate.editableProjectExtension, "inkbeam")
}

func testPreferencesIgnorePreInkbeamStorage() throws {
    defaults.set(legacyPreferencesData, forKey: "editorPreferences.v2")
    XCTAssertEqual(UserDefaultsEditorPreferencesStore(defaults: defaults).load(), .approvedDefaults)
}
```

Expected RED: schema 2 is migrated and the old preferences key is still read.

- [ ] **Step 2: Remove migration and validate stored annotation JSON directly**

Replace the migration block in `ProjectPackageStore.load` with:

```swift
let annotationJSON: Data
do {
    annotationJSON = try Data(contentsOf: documentURL)
} catch {
    throw ProjectPackageError.invalidAnnotationJSON
}
try validateAnnotationJSON(
    annotationJSON,
    expectedPixelWidth: manifest.sourcePixelWidth,
    expectedPixelHeight: manifest.sourcePixelHeight
)
```

Delete the migrator and its tests. Keep `EditorDocumentValidator` strict at schema version 3.

- [ ] **Step 3: Make file selection and save names exact**

Expose one shared type declaration:

```swift
extension UTType {
    static let inkbeamProject = UTType(
        exportedAs: "dev.gihwan.inkbeam.project",
        conformingTo: .package
    )
}
```

Use only `.inkbeamProject` in open/save panels, default to `Untitled.inkbeam`, and reject any non-`inkbeam` URL before calling `ProjectPackageStore`.

- [ ] **Step 4: Remove preference compatibility**

Keep one key and one strict decoder:

```swift
struct EditorPreferences: Codable, Equatable, Sendable {
    static let storageKey = "inkbeam.editorPreferences.v1"
    // Preserve approved defaults and current fields only.
}

func load() -> EditorPreferences {
    guard
        let data = defaults.data(forKey: EditorPreferences.storageKey),
        hasExactCurrentKeys(data),
        let value = try? JSONDecoder().decode(EditorPreferences.self, from: data),
        value.isValid
    else { return .approvedDefaults }
    return value
}
```

Delete `legacyStorageKey`, `LegacyEditorPreferences`, and migration tests. Do not read `Application Support/MyShottr`, old defaults suites, or old projects.

- [ ] **Step 5: Verify RED-to-GREEN document behavior**

```bash
xcodegen generate
xcodebuild test -project Inkbeam.xcodeproj -scheme Inkbeam \
  -destination 'platform=macOS' \
  -only-testing:InkbeamTests/ProjectPackageStoreTests \
  -only-testing:InkbeamTests/DocumentSessionTests \
  -only-testing:InkbeamTests/EditorPreferencesStoreTests \
  -only-testing:InkbeamTests/AppInfoPlistTests
```

Expected: `.inkbeam` create/save/reopen/edit/resave passes; schema 1/2 and `.myshottr` inputs fail without conversion.

- [ ] **Step 6: Commit**

```bash
git add Sources/InkbeamApp Tests/InkbeamTests Config/Inkbeam-Info.plist project.yml
git commit -m "feat(documents): enforce Inkbeam-only project contract"
```

### Task 4: Cut Over the WebKit and Editor Runtime Contract

**Files:**
- Modify: `Sources/InkbeamApp/Editor/*`
- Modify: `Packages/editor/package.json`, `Packages/editor/index.html`, `Packages/editor/src/bridge/*`
- Modify: editor and Swift bridge tests

- [ ] **Step 1: Change tests to the target scheme and handler**

Pin the exact source URL and handler:

```ts
expect(message.sourceImageURL).toBe(
  "inkbeam-editor://editor/document/00000000-0000-0000-0000-000000000001/original.png",
);
expect(window.webkit.messageHandlers.inkbeam).toBeDefined();
```

```swift
XCTAssertEqual(EditorWebView.editorScheme, "inkbeam-editor")
XCTAssertEqual(EditorWebView.bridgeName, "inkbeam")
```

Run the focused JS and Swift suites and expect failure on the old scheme/handler.

- [ ] **Step 2: Replace the contract atomically on both sides**

Set:

```swift
static let editorScheme = "inkbeam-editor"
static let bridgeName = "inkbeam"
```

and:

```ts
const nativeMessageEvent = "inkbeam:native-message";
const snapshotRequestEvent = "inkbeam:request-annotation-snapshot";
window.webkit.messageHandlers.inkbeam.postMessage(envelope);
```

Update navigation allowlists and resource URLs to `inkbeam-editor://editor/...`. Do not accept the old scheme or handler as an alternative.

- [ ] **Step 3: Run focused and package tests**

```bash
pnpm --filter @inkbeam/editor test
pnpm --filter @inkbeam/editor typecheck
pnpm --filter @inkbeam/editor build
xcodebuild test -project Inkbeam.xcodeproj -scheme Inkbeam \
  -destination 'platform=macOS' \
  -only-testing:InkbeamTests/EditorNavigationPolicyTests \
  -only-testing:InkbeamTests/EditorWebViewRuntimeTests \
  -only-testing:InkbeamTests/EditorBridgeEnvelopeTests
```

- [ ] **Step 4: Commit**

```bash
git add Packages/editor Sources/InkbeamApp/Editor Tests/InkbeamTests/Editor
git commit -m "refactor(editor): cut bridge over to Inkbeam"
```

### Task 5: Cut Over Chrome, the Helper, and the Single Inbox

**Files:**
- Modify: `Packages/chrome-extension/public/manifest.json`, `src/*`, `tests/*`, `vite.config.ts`
- Modify: `Sources/InkbeamApp/Chrome/*`
- Modify: `Sources/InkbeamNativeHost/*`
- Modify: related Swift tests and `docs/testing/chrome-capture.md`

- [ ] **Step 1: Add failing one-host/one-inbox tests**

Pin these values in TypeScript and Swift tests:

```ts
expect(NATIVE_HOST_NAME).toBe("dev.gihwan.inkbeam.capture");
expect(manifest.permissions).toEqual(["activeTab", "nativeMessaging"]);
await expect(handleCaptureRequest({ mode: "fullPage" })).rejects.toMatchObject({
  code: "UNSUPPORTED_CAPTURE_MODE",
});
```

```swift
XCTAssertEqual(registrar.hostName, "dev.gihwan.inkbeam.capture")
XCTAssertEqual(CaptureInboxCoordinator.captureReadyNotification.rawValue,
               "dev.gihwan.inkbeam.captureReady")
XCTAssertEqual(inbox.rootURL.lastPathComponent, "Inbox")
XCTAssertEqual(inbox.rootURL.deletingLastPathComponent().lastPathComponent, "Inkbeam")
```

- [ ] **Step 2: Implement the exact host manifest**

Make registrar output equivalent to:

```json
{
  "name": "dev.gihwan.inkbeam.capture",
  "description": "Open Chrome viewport captures in Inkbeam",
  "path": "/Applications/Inkbeam.app/Contents/Helpers/InkbeamNativeHost",
  "type": "stdio",
  "allowed_origins": ["chrome-extension://mcpmeggdbafgeemngbfniplmcjmigfbh/"]
}
```

The literal extension ID above is the existing value derived from
`Config/chrome-extension-key.b64`. The implementation must continue deriving
and testing it from that public key; it must not regenerate or replace the key.

Write exactly `~/Library/Application Support/Google/Chrome/NativeMessagingHosts/dev.gihwan.inkbeam.capture.json` atomically. Do not write or delete an old host manifest.

- [ ] **Step 3: Replace helper/inbox/notification/test namespaces**

Use only:

```swift
static let captureReadyNotification = Notification.Name(
    "dev.gihwan.inkbeam.captureReady"
)
```

and `~/Library/Application Support/Inkbeam/Inbox`. Rename test-only environment variables to `INKBEAM_NATIVE_HOST_TEST_INBOX`, `INKBEAM_NATIVE_HOST_TEST_APP_PATH`, and `INKBEAM_NATIVE_HOST_TEST_NOTIFICATION` without accepting old names.

- [ ] **Step 4: Preserve visible-viewport isolation and fixed identity**

Keep `captureVisibleTab` as the only pixel-producing Chrome API, reject `fullPage` before capture/send, and assert the built manifest has no `host_permissions`, `optional_host_permissions`, `content_scripts`, analytics, or network upload code. Keep `Config/chrome-extension-key.b64` byte-identical.

- [ ] **Step 5: Run all bridge tests**

```bash
pnpm --filter @inkbeam/chrome-extension test
pnpm --filter @inkbeam/chrome-extension typecheck
pnpm --filter @inkbeam/chrome-extension build
pnpm --filter @inkbeam/chrome-extension exec playwright test
xcodebuild test -project Inkbeam.xcodeproj -scheme InkbeamNativeHost \
  -destination 'platform=macOS'
xcodebuild test -project Inkbeam.xcodeproj -scheme Inkbeam \
  -destination 'platform=macOS' \
  -only-testing:InkbeamTests/NativeMessagingRegistrarTests \
  -only-testing:InkbeamTests/CaptureInboxCoordinatorTests \
  -only-testing:InkbeamTests/PendingCaptureInboxTests \
  -only-testing:InkbeamTests/ChromeExtensionIdentityTests
```

Expected: fixed ID unchanged; one Inkbeam host and inbox; visible viewport only.

- [ ] **Step 6: Commit**

```bash
git add Packages/chrome-extension Sources/InkbeamApp/Chrome Sources/InkbeamNativeHost Tests docs/testing/chrome-capture.md
git commit -m "refactor(chrome): use one Inkbeam native bridge"
```

### Task 6: Add the Clean-Cut Gate and Update Current Documentation

**Files:**
- Create: `Scripts/verify-clean-cutover.mjs`
- Rename: `Scripts/verify-v1.sh` -> `Scripts/verify-inkbeam.sh`
- Modify: `README.md`, `package.json`, current scripts/tests/docs
- Move old v0.1.0-only acceptance docs into `docs/testing/historical/v0.1.0/`

- [ ] **Step 1: Create a failing scanner test**

Create a scanner with these exact banned live tokens:

```js
const banned = [
  "MyShottr",
  ".myshottr",
  "com.myshottr",
  "MyShottrNativeHost",
  "myshottr-editor",
  "QuickInk",
  "Quick Ink",
];
```

Scan `project.yml`, generated `Inkbeam.xcodeproj/project.pbxproj`,
`package.json`, `pnpm-lock.yaml`, `Config`, `Sources`, `Packages`, `Scripts`,
`Tests`, `README.md`, and current `docs`. Fail if the generated project is
absent. Apply the banned set to both relative path names and UTF-8 file
contents. Exact file exceptions are limited to:

```js
const exactHistoricalFiles = new Set([
  "docs/releases/v0.1.0.md",
  "docs/testing/historical/v0.1.0/release-installation.md",
  "docs/testing/historical/v0.1.0/v1-acceptance.md",
  "docs/superpowers/plans/2026-07-29-myshottr-chrome-capture.md",
  "docs/superpowers/plans/2026-07-29-myshottr-foundation-editor.md",
  "docs/superpowers/plans/2026-07-29-myshottr-native-capture.md",
  "docs/superpowers/plans/2026-07-29-myshottr-recovery-hardening.md",
  "docs/superpowers/plans/2026-07-29-myshottr-v1-roadmap.md",
  "docs/superpowers/plans/2026-07-30-myshottr-editor-public-polish.md",
  "docs/superpowers/plans/2026-07-30-myshottr-public-distribution.md",
  "docs/superpowers/plans/2026-07-30-myshottr-v1-public-release-roadmap.md",
  "docs/superpowers/plans/2026-07-31-myshottr-editor-ux-polish.md",
  "docs/superpowers/specs/2026-07-29-myshottr-v1-design.md",
  "docs/superpowers/specs/2026-07-30-myshottr-v1-public-release-design.md",
  "docs/superpowers/specs/2026-07-31-myshottr-editor-ux-polish-design.md",
  "docs/superpowers/specs/2026-08-02-inkbeam-rename-design.md",
  "docs/superpowers/specs/2026-08-03-inkbeam-v0.2.0-official-release-design.md",
  "docs/superpowers/plans/2026-08-03-inkbeam-clean-cutover.md",
  "docs/superpowers/plans/2026-08-03-inkbeam-sparkle-updater.md",
  "docs/superpowers/plans/2026-08-03-inkbeam-direct-release-pipeline.md",
  "docs/superpowers/plans/2026-08-03-inkbeam-v0.2.0-rollout.md",
  "Scripts/verify-clean-cutover.mjs",
]);
```

Allow the README's historical deprecation wording only by parsing an exact `<!-- historical-v0.1.0:start -->` / `<!-- historical-v0.1.0:end -->` section and scanning all other README text.

- [ ] **Step 2: Run RED and resolve every reported live occurrence**

```bash
node Scripts/verify-clean-cutover.mjs
```

Expected initially: FAIL with exact file and line for every remaining live token. Rename current release tests/scripts/docs to Inkbeam semantics; move historical evidence rather than broad-allowlisting it.

- [ ] **Step 3: Update the canonical verification script**

`Scripts/verify-inkbeam.sh` must use `Inkbeam.xcodeproj`, Inkbeam schemes, `Inkbeam.app`, `InkbeamNativeHost`, and run the clean-cut scanner before packaging/release tests. Keep the existing dependency, unit, typecheck, build, Playwright, privacy, and dual Xcode test gates.

- [ ] **Step 4: Run the full completion gate**

```bash
pkill -x Inkbeam 2>/dev/null || true
pkill -x InkbeamNativeHost 2>/dev/null || true
pnpm install --frozen-lockfile
pnpm test
pnpm typecheck
pnpm build
pnpm test:release
xcodegen generate
node Scripts/verify-clean-cutover.mjs
xcodebuild test -project Inkbeam.xcodeproj -scheme Inkbeam -destination 'platform=macOS'
xcodebuild test -project Inkbeam.xcodeproj -scheme InkbeamNativeHost -destination 'platform=macOS'
```

Expected: all pass; `rg` finds old terms only in the exact historical/design/plan files above.

- [ ] **Step 5: Review the diff and commit**

```bash
git diff --check
git status --short
git diff --stat
git add README.md package.json Scripts Tests docs project.yml Config Sources Packages pnpm-lock.yaml
git commit -m "test(brand): enforce the Inkbeam clean cut"
```

## Completion Gate

- `Inkbeam.xcodeproj` generates and both Inkbeam schemes pass serially.
- `.inkbeam` is the only registered/editable project extension; older schema and `.myshottr` input are rejected without conversion.
- No legacy preferences, recovery chooser, alternate URL scheme, old helper ID, old inbox read, or typealias remains.
- Chrome retains its fixed extension ID, exact permissions, and viewport-only behavior.
- The clean-cut scanner passes with exact file-level historical exceptions only.
- The worktree is clean after the final task commit.
