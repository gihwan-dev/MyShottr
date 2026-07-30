# MyShottr Chrome Visible-Viewport Capture Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Capture the active Chrome tab's visible page area without browser chrome and open it in MyShottr through a validated Native Messaging helper.

**Architecture:** A minimal Manifest V3 service worker calls `captureVisibleTab()` after an extension action or command. It sends a bounded PNG message to a bundled Swift command-line helper, which stages the file in an owner-only inbox, activates MyShottr, and lets the app import the capture through the existing project pipeline.

**Tech Stack:** Chrome Manifest V3, TypeScript, Vite, Vitest, Playwright Chromium, Swift 6, AppKit, POSIX file APIs, XCTest

## Global Constraints

- Execute this plan after the foundation/editor, public-editor-polish, and
  native-capture plans.
- Chrome is the only officially supported browser in v1.
- Capture only the currently visible active-tab content area.
- The extension requests only `activeTab` and `nativeMessaging`.
- Do not use content scripts or persistent host permissions.
- Protocol version is exactly `1`; MIME type is exactly `image/png`.
- Reject decoded captures larger than 45 MiB.
- Never accept an arbitrary path from Chrome.
- Inbox files and Native Messaging manifests are per-user and owner-controlled.
- Browser capture errors are explicit; do not invoke a native screen-capture fallback.
- Automated extension tests use Playwright's bundled Chromium; final acceptance uses installed Google Chrome 150 or newer.
- Use TDD for behavior and commit after every task.

---

## Repository Map for This Plan

```text
Config/
└── chrome-extension-key.b64
Packages/
└── chrome-extension/
    ├── package.json
    ├── public/manifest.json
    ├── src/
    │   ├── captureVisibleViewport.ts
    │   ├── nativeMessaging.ts
    │   ├── service-worker.ts
    │   └── status.ts
    └── tests/
Scripts/
└── generate-extension-identity.sh
Sources/
├── MyShottrApp/Chrome/
│   ├── CaptureInboxCoordinator.swift
│   ├── ChromeExtensionIdentity.swift
│   ├── NativeMessagingRegistrar.swift
│   └── PendingCaptureInbox.swift
└── MyShottrNativeHost/
    ├── AppActivator.swift
    ├── HostInboxStore.swift
    ├── HostRunner.swift
    ├── NativeCaptureMessage.swift
    ├── NativeMessageFraming.swift
    └── main.swift
Tests/
├── MyShottrNativeHostTests/
└── MyShottrTests/Chrome/
```

## Shared Interfaces

TypeScript:

```ts
export type BrowserCaptureMode = "visibleViewport" | "fullPage";

export type NativeCaptureMessage = {
  protocolVersion: 1;
  type: "capture";
  captureMode: BrowserCaptureMode;
  mimeType: "image/png";
  dataBase64: string;
};

export type NativeCaptureReply =
  | { ok: true; captureId: string }
  | { ok: false; code: "HOST_UNAVAILABLE" | "INVALID_MESSAGE" | "UNSUPPORTED_CAPTURE_MODE" | "INVALID_IMAGE" | "IMAGE_TOO_LARGE" | "STAGING_FAILED" };
```

Swift:

```swift
struct StagedCapture: Equatable, Sendable {
    let id: UUID
    let pngURL: URL
}

protocol PendingCaptureStoring: Sendable {
    func stage(pngData: Data) throws -> StagedCapture
    func pendingCaptures() throws -> [StagedCapture]
    func consume(id: UUID) throws -> Data
}
```

### Task 1: Minimal Manifest V3 Capture Extension

**Files:**
- Modify: `package.json`
- Modify: `pnpm-workspace.yaml`
- Create: `Config/chrome-extension-key.b64`
- Create: `Scripts/generate-extension-identity.sh`
- Create: `Packages/chrome-extension/package.json`
- Create: `Packages/chrome-extension/tsconfig.json`
- Create: `Packages/chrome-extension/vite.config.ts`
- Create: `Packages/chrome-extension/public/manifest.json`
- Create: `Packages/chrome-extension/src/captureVisibleViewport.ts`
- Create: `Packages/chrome-extension/src/nativeMessaging.ts`
- Create: `Packages/chrome-extension/src/status.ts`
- Create: `Packages/chrome-extension/src/service-worker.ts`
- Test: `Packages/chrome-extension/tests/captureVisibleViewport.test.ts`
- Test: `Packages/chrome-extension/tests/service-worker.test.ts`

**Interfaces:**
- Consumes: Chrome `tabs.captureVisibleTab` and `runtime.sendNativeMessage`.
- Produces: `captureVisibleViewport()`, `sendCaptureToNativeHost()`, and a built unpacked extension under `Packages/chrome-extension/dist`.

- [ ] **Step 1: Generate a stable extension public identity**

Create `Scripts/generate-extension-identity.sh`:

```bash
#!/bin/zsh
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TEMP_DIR="$(mktemp -d)"
trap 'rm -rf "${TEMP_DIR}"' EXIT

openssl genrsa -out "${TEMP_DIR}/extension-private.pem" 2048
openssl rsa -in "${TEMP_DIR}/extension-private.pem" \
  -pubout -outform DER 2>/dev/null \
  | openssl base64 -A \
  > "${REPO_ROOT}/Config/chrome-extension-key.b64"

chmod 0644 "${REPO_ROOT}/Config/chrome-extension-key.b64"
```

Run `chmod +x Scripts/generate-extension-identity.sh` and then run the script
exactly once. Commit only `Config/chrome-extension-key.b64`. Never
commit the temporary private key. The public key stabilizes the unpacked
extension ID and is not a secret.

- [ ] **Step 2: Write failing capture and error-mapping tests**

Mock `globalThis.chrome` and assert:

```ts
it("captures the active tab as PNG", async () => {
  chrome.tabs.captureVisibleTab.mockResolvedValue("data:image/png;base64,iVBORw0KGgo=");
  await expect(captureVisibleViewport()).resolves.toEqual({
    protocolVersion: 1,
    type: "capture",
    captureMode: "visibleViewport",
    mimeType: "image/png",
    dataBase64: "iVBORw0KGgo=",
  });
  expect(chrome.tabs.captureVisibleTab).toHaveBeenCalledWith({ format: "png" });
});

it("rejects full-page mode before taking a viewport capture", async () => {
  await expect(runCaptureAction("fullPage")).rejects.toMatchObject({
    code: "UNSUPPORTED_CAPTURE_MODE",
  });
  expect(chrome.tabs.captureVisibleTab).not.toHaveBeenCalled();
});

it("does not send a fallback capture when native messaging fails", async () => {
  chrome.runtime.sendNativeMessage.mockRejectedValue(new Error("host not found"));
  await expect(runCaptureAction()).rejects.toMatchObject({ code: "HOST_UNAVAILABLE" });
  expect(chrome.tabs.captureVisibleTab).toHaveBeenCalledTimes(1);
});
```

Also reject a returned `data:` URL whose media type is not `image/png`, whose
base64 body is empty, or whose estimated decoded size exceeds 45 MiB.

- [ ] **Step 3: Run the extension tests and verify failure**

Run:

```bash
pnpm --filter @myshottr/chrome-extension test
```

Expected: the package or capture modules are missing.

- [ ] **Step 4: Implement the extension package**

Create `Packages/chrome-extension/package.json`:

```json
{
  "name": "@myshottr/chrome-extension",
  "private": true,
  "type": "module",
  "scripts": {
    "build": "tsc --noEmit && vite build",
    "test": "vitest run",
    "test:e2e": "playwright test",
    "typecheck": "tsc --noEmit"
  },
  "devDependencies": {
    "@playwright/test": "^1.54.0",
    "@types/chrome": "^0.0.287",
    "@types/node": "^24.0.0",
    "typescript": "^5.9.0",
    "vite": "^7.0.0",
    "vitest": "^3.0.0"
  }
}
```

Create `Packages/chrome-extension/tsconfig.json`:

```json
{
  "compilerOptions": {
    "target": "ES2022",
    "lib": ["ES2022", "WebWorker"],
    "module": "ESNext",
    "moduleResolution": "Bundler",
    "strict": true,
    "noEmit": true,
    "types": ["chrome", "vitest/globals", "node"]
  },
  "include": ["src", "tests", "vite.config.ts", "playwright.config.ts"]
}
```

Create `Packages/chrome-extension/vite.config.ts`:

```ts
import { promises as fs } from "node:fs";
import { dirname, resolve } from "node:path";
import { fileURLToPath } from "node:url";
import { defineConfig, type Plugin } from "vite";

const packageDir = dirname(fileURLToPath(import.meta.url));
const repoRoot = resolve(packageDir, "../..");

function injectStableKey(): Plugin {
  return {
    name: "inject-stable-extension-key",
    async writeBundle() {
      const manifestPath = resolve(packageDir, "dist/manifest.json");
      const manifest = JSON.parse(await fs.readFile(manifestPath, "utf8"));
      manifest.key = (
        await fs.readFile(resolve(repoRoot, "Config/chrome-extension-key.b64"), "utf8")
      ).trim();
      await fs.writeFile(manifestPath, `${JSON.stringify(manifest, null, 2)}\n`);
    },
  };
}

export default defineConfig({
  publicDir: "public",
  plugins: [injectStableKey()],
  build: {
    outDir: "dist",
    emptyOutDir: true,
    rollupOptions: {
      input: resolve(packageDir, "src/service-worker.ts"),
      output: {
        entryFileNames: "service-worker.js",
      },
    },
  },
});
```

Create a Manifest V3 manifest:

```json
{
  "manifest_version": 3,
  "name": "MyShottr Web Capture",
  "version": "0.1.0",
  "description": "Capture the visible page viewport in MyShottr.",
  "permissions": ["activeTab", "nativeMessaging"],
  "background": {
    "service_worker": "service-worker.js",
    "type": "module"
  },
  "action": {
    "default_title": "Capture visible page in MyShottr"
  },
  "commands": {
    "capture-visible-viewport": {
      "suggested_key": {
        "default": "Alt+Shift+2",
        "mac": "Alt+Shift+2"
      },
      "description": "Capture visible page in MyShottr"
    }
  }
}
```

The Vite config reads `Config/chrome-extension-key.b64`, inserts it as the
manifest's `"key"`, and emits the service worker as
`dist/service-worker.js`. It must not add `host_permissions` or
`content_scripts`.

`service-worker.ts` registers only:

```ts
chrome.action.onClicked.addListener(() => void runCaptureAction());
chrome.commands.onCommand.addListener((command) => {
  if (command === "capture-visible-viewport") void runCaptureAction();
});
```

`runCaptureAction(mode: BrowserCaptureMode = "visibleViewport")` rejects
`fullPage` with `UNSUPPORTED_CAPTURE_MODE` before calling Chrome. The
`visibleViewport` path captures once, sends once to
`com.myshottr.capture`, and uses `chrome.action.setBadgeText` plus
`setTitle` to display bounded success or failure state. It clears the badge
after three seconds. It must not retry by switching capture mechanisms.

- [ ] **Step 5: Verify extension unit tests, permissions, and build**

Run:

```bash
pnpm --filter @myshottr/chrome-extension test
pnpm --filter @myshottr/chrome-extension typecheck
pnpm --filter @myshottr/chrome-extension build
node -e 'const m=require("./Packages/chrome-extension/dist/manifest.json"); if (JSON.stringify(m.permissions)!==JSON.stringify(["activeTab","nativeMessaging"]) || m.host_permissions || m.content_scripts) process.exit(1)'
```

Expected: all commands exit `0`; the built manifest has exactly the two allowed
permissions and no content script or host permissions.

- [ ] **Step 6: Commit the extension**

```bash
git add Config/chrome-extension-key.b64 Scripts/generate-extension-identity.sh \
  Packages/chrome-extension package.json pnpm-workspace.yaml pnpm-lock.yaml
git commit -m "feat: capture Chrome visible viewport"
```

### Task 2: Native Messaging Framing and Helper

**Files:**
- Modify: `project.yml`
- Create: `Sources/MyShottrNativeHost/NativeCaptureMessage.swift`
- Create: `Sources/MyShottrNativeHost/NativeMessageFraming.swift`
- Create: `Sources/MyShottrNativeHost/HostInboxStore.swift`
- Create: `Sources/MyShottrNativeHost/HostRunner.swift`
- Create: `Sources/MyShottrNativeHost/AppActivator.swift`
- Create: `Sources/MyShottrNativeHost/main.swift`
- Test: `Tests/MyShottrNativeHostTests/NativeMessageFramingTests.swift`
- Test: `Tests/MyShottrNativeHostTests/HostInboxStoreTests.swift`
- Test: `Tests/MyShottrNativeHostTests/HostRunnerTests.swift`
- Test support: `Tests/MyShottrNativeHostTests/Support/HostFixtures.swift`
- Test support: `Tests/MyShottrNativeHostTests/Support/TemporaryDirectoryTestCase.swift`

**Interfaces:**
- Consumes: `NativeCaptureMessage` JSON from the extension.
- Produces: `HostCaptureStaging`, `HostInboxStore`, and a
  `MyShottrNativeHost` executable that reads one Chrome-framed message, stages
  one capture, replies once, and exits.

- [ ] **Step 1: Add failing framing and validation tests**

Test Chrome's four-byte little-endian length prefix:

```swift
func testReadsOneFramedMessage() throws {
    let body = Data(#"{"protocolVersion":1}"#.utf8)
    var length = UInt32(body.count).littleEndian
    let input = Data(bytes: &length, count: 4) + body
    XCTAssertEqual(try NativeMessageFraming.read(from: input), body)
}

func testRejectsMessageAboveChromeLimitBeforeAllocation() {
    var length = UInt32(64 * 1024 * 1024 + 1).littleEndian
    let input = Data(bytes: &length, count: 4)
    XCTAssertThrowsError(try NativeMessageFraming.read(from: input)) {
        XCTAssertEqual($0 as? NativeMessageError, .messageTooLarge)
    }
}
```

`HostRunnerTests` must reject protocol version `2`, `captureMode =
fullPage`, non-PNG MIME, malformed base64, decoded data above 45 MiB, and PNG
data whose ImageIO type is not PNG.
It must return an error reply below 1 MiB and never call the staging spy for
invalid input. `HostInboxStoreTests` must assert root mode `0700`, staged file
mode `0600`, `O_EXCL` behavior, partial-file deletion, and UUID-only filenames.

`HostFixtures` owns a 1×1 valid PNG, its base64 value, a valid protocol message,
and length-prefix helpers. The helper test target uses its own
`TemporaryDirectoryTestCase` because it must not import the app test target.

- [ ] **Step 2: Run helper tests and verify failure**

Run:

```bash
xcodegen generate
xcodebuild test -project MyShottr.xcodeproj -scheme MyShottrNativeHost \
  -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO
```

Expected: the target or helper types are missing.

- [ ] **Step 3: Add helper targets and implement one-message lifecycle**

Add `MyShottrNativeHost` as a macOS command-line target and
`MyShottrNativeHostTests` as its unit-test target in `project.yml`. Make the app
target depend on the helper and copy the built executable to
`MyShottr.app/Contents/Helpers/MyShottrNativeHost` in a post-build script.
Merge this target and scheme fragment:

```yaml
targets:
  MyShottrNativeHost:
    type: tool
    platform: macOS
    sources:
      - Sources/MyShottrNativeHost
    settings:
      base:
        PRODUCT_BUNDLE_IDENTIFIER: com.myshottr.native-host
  MyShottrNativeHostTests:
    type: bundle.unit-test
    platform: macOS
    sources:
      - Tests/MyShottrNativeHostTests
    dependencies:
      - target: MyShottrNativeHost

schemes:
  MyShottrNativeHost:
    build:
      targets:
        MyShottrNativeHost: all
        MyShottrNativeHostTests: [test]
    test:
      targets:
        - MyShottrNativeHostTests
```

Add this dependency and post-build script to the existing `MyShottr` target:

```yaml
dependencies:
  - target: MyShottrNativeHost
postBuildScripts:
  - name: Embed Native Messaging Host
    script: |
      set -euo pipefail
      DESTINATION="${TARGET_BUILD_DIR}/${CONTENTS_FOLDER_PATH}/Helpers"
      mkdir -p "${DESTINATION}"
      cp "${BUILT_PRODUCTS_DIR}/MyShottrNativeHost" \
        "${DESTINATION}/MyShottrNativeHost"
      chmod 0755 "${DESTINATION}/MyShottrNativeHost"
    basedOnDependencyAnalysis: false
```

Define exact reply codes:

```swift
enum BrowserCaptureMode: String, Codable {
    case visibleViewport
    case fullPage
}

struct NativeCaptureMessage: Codable {
    let protocolVersion: Int
    let type: String
    let captureMode: BrowserCaptureMode
    let mimeType: String
    let dataBase64: String
}

enum NativeHostErrorCode: String, Codable {
    case invalidMessage = "INVALID_MESSAGE"
    case unsupportedCaptureMode = "UNSUPPORTED_CAPTURE_MODE"
    case invalidImage = "INVALID_IMAGE"
    case imageTooLarge = "IMAGE_TOO_LARGE"
    case stagingFailed = "STAGING_FAILED"
}

struct NativeHostReply: Codable {
    let ok: Bool
    let captureId: UUID?
    let code: NativeHostErrorCode?
}
```

`HostRunner` requires `type == "capture"` and
`captureMode == .visibleViewport`. It returns
`UNSUPPORTED_CAPTURE_MODE` before decoding or staging image data for
`.fullPage`.

Define the helper-local staging boundary:

```swift
protocol HostCaptureStaging {
    func stage(pngData: Data) throws -> UUID
}
```

`HostInboxStore` implements it directly inside the helper target. It creates
`~/Library/Application Support/MyShottr/Inbox` with mode `0700`, writes
`<capture-id>.png` with `O_CREAT | O_EXCL | O_WRONLY | O_NOFOLLOW` and mode
`0600`, calls `fsync`, and removes a partial file on every error. The app-side
`PendingCaptureInbox` in Task 3 independently validates and consumes the same
directory contract; the helper never imports the app executable target.

`main.swift` calls `HostRunner.run(input: .standardInput, output:
.standardOutput)` exactly once. All diagnostics go to standard error; standard
output contains only one length-prefixed JSON reply.

The helper locates the containing `.app` by walking upward from its executable
URL until it finds `Contents/Info.plist`. It stages before activating the app.
If staging fails, it does not launch the app.

- [ ] **Step 4: Verify helper tests and framing executable**

Run:

```bash
xcodebuild test -project MyShottr.xcodeproj -scheme MyShottrNativeHost \
  -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO
xcodebuild build -project MyShottr.xcodeproj -scheme MyShottr \
  -configuration Debug -destination 'platform=macOS'
test -x "$HOME/Library/Developer/Xcode/DerivedData/"*/Build/Products/Debug/MyShottr.app/Contents/Helpers/MyShottrNativeHost
```

Expected: tests pass, the app builds, and the helper exists and is executable
inside the app bundle.

- [ ] **Step 5: Commit the helper**

```bash
git add project.yml Sources/MyShottrNativeHost Tests/MyShottrNativeHostTests
git commit -m "feat: add Chrome native messaging helper"
```

### Task 3: Owner-Only Inbox, Host Registration, and App Import

**Files:**
- Create: `Sources/MyShottrApp/Chrome/ChromeExtensionIdentity.swift`
- Create: `Sources/MyShottrApp/Chrome/PendingCaptureInbox.swift`
- Create: `Sources/MyShottrApp/Chrome/NativeMessagingRegistrar.swift`
- Create: `Sources/MyShottrApp/Chrome/CaptureInboxCoordinator.swift`
- Modify: `Sources/MyShottrNativeHost/AppActivator.swift`
- Modify: `Sources/MyShottrApp/App/AppDelegate.swift`
- Test: `Tests/MyShottrTests/Chrome/ChromeExtensionIdentityTests.swift`
- Test: `Tests/MyShottrTests/Chrome/PendingCaptureInboxTests.swift`
- Test: `Tests/MyShottrTests/Chrome/NativeMessagingRegistrarTests.swift`
- Test: `Tests/MyShottrTests/Chrome/CaptureInboxCoordinatorTests.swift`
- Test support: `Tests/MyShottrTests/Support/ChromeFixtures.swift`

**Interfaces:**
- Consumes: fixed extension public key, bundled helper URL, `StagedCapture`, `NewProjectCreating`, and `DocumentWindowController`.
- Produces: user-level host registration, safe pending capture import, and `.chromeVisibleViewport` projects.

- [ ] **Step 1: Write failing identity, inbox, and registration tests**

Cover:

```swift
func testExtensionIdHasThirtyTwoLowercaseAPCharacters() throws {
    let id = try ChromeExtensionIdentity.id(fromBase64DER: Fixtures.extensionPublicKey)
    XCTAssertTrue(id.range(of: #"^[a-p]{32}$"#, options: .regularExpression) != nil)
}

func testInboxRejectsSymbolicLink() throws {
    let inbox = try PendingCaptureInbox(root: temporaryDirectory)
    let link = temporaryDirectory.appendingPathComponent("\(UUID()).png")
    try FileManager.default.createSymbolicLink(at: link, withDestinationURL: Fixtures.pngURL)
    XCTAssertThrowsError(try inbox.consume(id: UUID(uuidString: link.deletingPathExtension().lastPathComponent)!))
}

func testRegistrarWritesExactAllowedOriginAndAbsoluteHelperPath() throws {
    let manifest = try registrar.makeManifest()
    XCTAssertEqual(manifest.name, "com.myshottr.capture")
    XCTAssertEqual(manifest.type, "stdio")
    XCTAssertEqual(manifest.allowedOrigins, ["chrome-extension://\(Fixtures.extensionId)/"])
    XCTAssertTrue(manifest.path.hasPrefix("/"))
}

@MainActor
func testCoordinatorBuildsChromeViewportProjectThroughSharedFactory() throws {
    let factory = SpyNewProjectFactory()
    let coordinator = CaptureInboxCoordinator(
        inbox: StubPendingCaptureInbox(pngData: ProjectFixtures.pngData),
        projectFactory: factory,
        windows: SpyDocumentWindowPresenter()
    )

    try coordinator.consume(id: ChromeFixtures.captureID)

    XCTAssertEqual(factory.requests.count, 1)
    XCTAssertEqual(factory.requests[0].sourceKind, .chromeVisibleViewport)
    XCTAssertEqual(factory.requests[0].id, ChromeFixtures.captureID)
    XCTAssertNil(factory.requests[0].scale)
}

final class SpyNewProjectFactory: NewProjectCreating, @unchecked Sendable {
    struct Request {
        let id: UUID
        let sourceKind: CaptureSourceKind
        let scale: Double?
    }
    private(set) var requests: [Request] = []

    func make(
        artifact: CaptureArtifact,
        now: Date
    ) throws -> MyShottrProject {
        requests.append(Request(
            id: artifact.id,
            sourceKind: artifact.sourceKind,
            scale: artifact.scale
        ))
        return try NewProjectFactory(
            preferences: StubPreferences(.approvedDefaults)
        ).make(
            artifact: artifact,
            now: now
        )
    }
}
```

Also assert staged files are regular files with `0600` permissions, duplicate
capture IDs cannot overwrite a file, `consume` deletes after reading, invalid
PNG is deleted and rejected, and pending captures sort by modification date.

`ChromeFixtures` exports the committed public-key base64, its known computed
extension ID, one valid staged-capture ID, and the app-bundle/helper URLs used
by registrar tests.

- [ ] **Step 2: Run focused tests and verify failure**

Run:

```bash
xcodebuild test -project MyShottr.xcodeproj -scheme MyShottr \
  -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO \
  -only-testing:MyShottrTests/ChromeExtensionIdentityTests \
  -only-testing:MyShottrTests/PendingCaptureInboxTests \
  -only-testing:MyShottrTests/NativeMessagingRegistrarTests \
  -only-testing:MyShottrTests/CaptureInboxCoordinatorTests
```

Expected: missing-type compilation failures.

- [ ] **Step 3: Implement safe staging and registration**

`PendingCaptureInbox` root is
`~/Library/Application Support/MyShottr/Inbox`. Create it as `0700`. Stage with
POSIX `open` flags `O_CREAT | O_EXCL | O_WRONLY | O_NOFOLLOW` and mode `0600`.
Call `fsync`, close, then validate PNG type and dimensions with ImageIO.

`ChromeExtensionIdentity`:

1. base64-decodes the DER public key;
2. computes SHA-256;
3. takes the first 16 bytes;
4. maps each high and low nibble from `0...15` to ASCII `a...p`;
5. returns the resulting 32-character extension ID.

`NativeMessagingRegistrar.install()` atomically writes:

```json
{
  "name": "com.myshottr.capture",
  "description": "Open Chrome viewport captures in MyShottr",
  "path": "/absolute/path/MyShottr.app/Contents/Helpers/MyShottrNativeHost",
  "type": "stdio",
  "allowed_origins": ["chrome-extension://<computed-id>/"]
}
```

to:

```text
~/Library/Application Support/Google/Chrome/NativeMessagingHosts/com.myshottr.capture.json
```

Add the fixed public key as an app resource in `project.yml`:

```yaml
resources:
  - path: Config/chrome-extension-key.b64
```

`AppActivator` opens or activates the containing MyShottr app and then posts a
distributed notification named `com.myshottr.captureReady` containing only the
capture UUID string.

`CaptureInboxCoordinator` observes that notification and also scans pending
captures at app launch. For every valid capture it creates:

```swift
let artifact = try CaptureArtifact(
    id: captureID,
    sourceKind: .chromeVisibleViewport,
    pngData: pngData,
    scale: nil
)
```

and calls:

```swift
let project = try projectFactory.make(
    artifact: artifact,
    now: now()
)
```

then opens the existing editor window. The shared factory owns schema version
`2`, `presentation: none`, dimensions, and remembered defaults; the inbox
coordinator must not construct annotation JSON itself.

- [ ] **Step 4: Run Chrome bridge native tests**

Run:

```bash
xcodebuild test -project MyShottr.xcodeproj -scheme MyShottr \
  -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO
xcodebuild test -project MyShottr.xcodeproj -scheme MyShottrNativeHost \
  -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO
```

Expected: all app and helper tests pass.

- [ ] **Step 5: Commit registration and import**

```bash
git add Sources/MyShottrApp/Chrome Sources/MyShottrApp/App/AppDelegate.swift \
  Sources/MyShottrNativeHost Tests/MyShottrTests/Chrome
git commit -m "feat: import validated Chrome captures"
```

### Task 4: Extension Integration and Real Chrome Acceptance

**Files:**
- Create: `Packages/chrome-extension/playwright.config.ts`
- Create: `Packages/chrome-extension/tests/fixtures.ts`
- Create: `Packages/chrome-extension/tests/capture.e2e.ts`
- Create: `Tests/MyShottrNativeHostTests/NativeHostProcessTests.swift`
- Create: `docs/testing/chrome-capture.md`

**Interfaces:**
- Consumes: built extension, Native Messaging helper, registrar, inbox coordinator.
- Produces: automated Chromium confidence plus a documented real-Chrome acceptance gate.

- [ ] **Step 1: Write a Playwright extension fixture**

Create `playwright.config.ts`:

```ts
import { defineConfig } from "@playwright/test";

export default defineConfig({
  testDir: "./tests",
  testMatch: "**/*.e2e.ts",
  workers: 1,
  fullyParallel: false,
  use: {
    trace: "retain-on-failure",
  },
});
```

Use a persistent bundled-Chromium context:

```ts
const context = await chromium.launchPersistentContext("", {
  channel: "chromium",
  args: [
    `--disable-extensions-except=${extensionPath}`,
    `--load-extension=${extensionPath}`,
  ],
});
```

Retrieve the Manifest V3 service worker and extension ID. Do not use installed
Google Chrome flags for automated loading because current Chrome does not
support that sideloading path.

- [ ] **Step 2: Add automated boundary tests**

Playwright must verify the built extension loads, exposes only the expected
permissions, and invokes a test seam around `captureVisibleTab` once per action.
The Swift process test must:

1. launch `MyShottrNativeHost` as a subprocess;
2. write a valid length-prefixed capture message;
3. close stdin;
4. read and decode one reply;
5. assert `ok == true`;
6. assert exactly one owner-only PNG appears in a temporary injected inbox.

- [ ] **Step 3: Run the automated Chrome gate**

Run:

```bash
pnpm --filter @myshottr/chrome-extension build
pnpm --filter @myshottr/chrome-extension test
pnpm --filter @myshottr/chrome-extension exec playwright install chromium
pnpm --filter @myshottr/chrome-extension exec playwright test
xcodebuild test -project MyShottr.xcodeproj -scheme MyShottrNativeHost \
  -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO
```

Expected: every command exits `0`.

- [ ] **Step 4: Document and perform the real Chrome workflow**

`docs/testing/chrome-capture.md` must use these exact checks:

1. build and launch MyShottr once;
2. verify the user-level host manifest exists and its path points into the
   running app bundle;
3. open `chrome://extensions`, enable Developer mode, and load
   `Packages/chrome-extension/dist`;
4. visit a page with an unmistakable top edge and scroll position;
5. click the extension action;
6. confirm MyShottr opens one editor document;
7. confirm the PNG contains page pixels but no tab strip, address bar, toolbar,
   or extension popup;
8. trigger `Option-Shift-2` and confirm the same behavior;
9. rename the host manifest, trigger capture, and confirm the extension reports
   `HOST_UNAVAILABLE` without a desktop-capture fallback;
10. restore the manifest and confirm capture succeeds again.

- [ ] **Step 5: Run the combined product gate**

Run:

```bash
pnpm test
pnpm typecheck
pnpm build
xcodebuild test -project MyShottr.xcodeproj -scheme MyShottr \
  -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO
xcodebuild test -project MyShottr.xcodeproj -scheme MyShottrNativeHost \
  -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO
```

Expected: all automated gates pass, followed by all ten manual Chrome checks.

- [ ] **Step 6: Commit the Chrome capture increment**

```bash
git add Packages/chrome-extension Tests/MyShottrNativeHostTests docs/testing/chrome-capture.md
git commit -m "test: verify Chrome viewport capture end to end"
```

## Plan 3 Completion Gate

The increment is complete only when installed Chrome captures the visible page
without browser chrome, the helper stages no invalid or arbitrary files, and
both automated and documented manual gates pass.
