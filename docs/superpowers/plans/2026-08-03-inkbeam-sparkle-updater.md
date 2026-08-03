# Inkbeam Sparkle Updater Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Integrate Sparkle 2.9.4 as a consent-first, signed-feed updater that is silent on first launch, prompts once on second launch, never silently downloads or installs, and cannot bypass Inkbeam's modified-document termination decisions.

**Architecture:** Pin Sparkle in XcodeGen, inject one committed public EdDSA key and one build-time feed URL into the app, and hide `SPUStandardUpdaterController` behind a small `UpdateService`. Gate all normal startup work on a writable Applications install, let Sparkle own feed verification/download/replacement/relaunch, and retain AppDelegate's existing termination loop as the only save/discard/cancel authority. Test Inkbeam policy with injected adapters; test Sparkle cryptography and final artifacts in the direct-release and rollout plans.

**Tech Stack:** Swift 6, AppKit, SwiftUI, Sparkle 2.9.4, XcodeGen, Swift Package Manager, XCTest, OSLog, Node 22

## Global Constraints

- Execute only after `2026-08-03-inkbeam-clean-cutover.md` is complete and clean. All paths below are post-cutover Inkbeam paths.
- Complete this plan before the direct-release pipeline and staged-rollout plans.
- Pin `https://github.com/sparkle-project/Sparkle` to exact version `2.9.4`; do not use `SUUpdater`, a floating package range, a custom installer, or a second update framework.
- The release private EdDSA key remains only in the login Keychain under Sparkle account `inkbeam`. Never export it, commit it, place it in an environment file, print it in logs, or upload it to GitHub.
- `Config/SparklePublicEDKey.txt` contains exactly one base64 public-key line. A missing or mismatched key blocks building release products; there is no default key.
- RC builds receive only `https://gihwan-dev.github.io/inkbeam/appcast-beta.xml`; final builds receive only `https://gihwan-dev.github.io/inkbeam/appcast.xml`. There is no runtime feed override or user beta toggle.
- Omit `SUEnableAutomaticChecks`; this preserves Sparkle's second-launch consent behavior. Set `SUAllowsAutomaticUpdates = NO`, `SUAutomaticallyUpdate = NO`, and `SUEnableSystemProfiling = NO`.
- A release-location failure prevents updater startup, Native Messaging registration, inbox startup, and global shortcut registration. Development builds may bypass this with a compile-time `DEBUG` branch only; release builds may not.
- Preserve the existing AppDelegate termination state machine. Do not add recovery snapshots, a recovery chooser, update-specific document storage, or a force-quit path.
- Commit after every task. A failing consent, network-count, termination, security-plist, or install-location test stops the task.

---

## Target Interfaces

```swift
@MainActor
protocol UpdateServing: AnyObject {
    var canCheckForUpdates: Bool { get }
    func start() throws
    func checkForUpdates()
}

enum UpdateChannel: String, Equatable {
    case beta = "Release Candidate"
    case stable = "Stable"
}

struct UpdateConfiguration: Equatable {
    let feedURL: URL
    let publicEDKey: String
    let channel: UpdateChannel
}

enum InstallLocationDecision: Equatable {
    case eligible
    case moveToApplications
}
```

### Task 1: Pin Sparkle and Make Security Metadata Build-Time Only

**Files:**
- Modify: `project.yml`
- Modify: `Config/Inkbeam-Info.plist`
- Create: `Config/SparklePublicEDKey.txt` through the public-key operator step
- Create: `Scripts/generate-project.sh`
- Modify: `Tests/InkbeamTests/App/AppInfoPlistTests.swift`
- Modify: `Tests/InkbeamTests/AppConfigurationTests.swift`

- [ ] **Step 1: Add failing package and plist assertions**

Add these assertions to the configuration tests:

```swift
func testSparkleSecurityKeysAreStrict() throws {
    let info = try XCTUnwrap(Bundle.main.infoDictionary)
    XCTAssertNil(info["SUEnableAutomaticChecks"])
    XCTAssertEqual(info["SUScheduledCheckInterval"] as? Int, 86_400)
    XCTAssertEqual(info["SUAutomaticallyUpdate"] as? Bool, false)
    XCTAssertEqual(info["SUAllowsAutomaticUpdates"] as? Bool, false)
    XCTAssertEqual(info["SUEnableSystemProfiling"] as? Bool, false)
    XCTAssertEqual(info["SUEnableJavaScript"] as? Bool, false)
    XCTAssertEqual(info["SUVerifyUpdateBeforeExtraction"] as? Bool, true)
    XCTAssertEqual(info["SURequireSignedFeed"] as? Bool, true)
    XCTAssertEqual(info["SUSignedFeedFailureExpirationInterval"] as? Int, 0)
    XCTAssertNotNil(info["SUPublicEDKey"] as? String)
    XCTAssertNotNil(URL(string: try XCTUnwrap(info["SUFeedURL"] as? String)))
}
```

Add a Node contract assertion to `Tests/Release/identity-contract.test.mjs`:

```js
assert.match(project, /Sparkle:\n\s+url: https:\/\/github\.com\/sparkle-project\/Sparkle\n\s+exactVersion: 2\.9\.4/);
assert.doesNotMatch(project, /from:|upToNext|branch:|revision:/);
```

- [ ] **Step 2: Run RED**

```bash
node --test Tests/Release/identity-contract.test.mjs
xcodegen generate
xcodebuild test -project Inkbeam.xcodeproj -scheme Inkbeam \
  -destination 'platform=macOS' -only-testing:InkbeamTests/AppInfoPlistTests
```

Expected: FAIL because Sparkle and the security keys are absent.

- [ ] **Step 3: Generate or confirm the public key without exporting the private key**

Resolve the pinned package into a deterministic tool directory:

```bash
mkdir -p build/sparkle-tools
xcodebuild -resolvePackageDependencies \
  -project Inkbeam.xcodeproj -scheme Inkbeam \
  -derivedDataPath build/sparkle-tools/DerivedData
SPARKLE_TOOLS="build/sparkle-tools/DerivedData/SourcePackages/artifacts/sparkle/Sparkle/bin"
test -x "${SPARKLE_TOOLS}/generate_keys"
"${SPARKLE_TOOLS}/generate_keys" --account inkbeam
```

The final command prints the public key and stores or reads the private key from Keychain. Validate the printed value against `^[A-Za-z0-9+/]{43}=$`, then use `apply_patch` to add that exact one-line value to `Config/SparklePublicEDKey.txt`. Do not use `-x`, `-f`, `--ed-key-file`, shell redirection of Keychain data, or a test key.

- [ ] **Step 4: Add exact package and plist substitutions**

Add to `project.yml`:

```yaml
packages:
  Sparkle:
    url: https://github.com/sparkle-project/Sparkle
    exactVersion: 2.9.4
```

Add the product to `Inkbeam.dependencies`:

```yaml
      - package: Sparkle
        product: Sparkle
```

Add these Info properties, using Xcode build-setting substitution:

```yaml
        SUFeedURL: $(INKBEAM_APPCAST_URL)
        SUPublicEDKey: $(INKBEAM_SPARKLE_PUBLIC_KEY)
        SUScheduledCheckInterval: 86400
        SUAutomaticallyUpdate: false
        SUAllowsAutomaticUpdates: false
        SUEnableSystemProfiling: false
        SUEnableJavaScript: false
        SUShowReleaseNotes: true
        SUVerifyUpdateBeforeExtraction: true
        SURequireSignedFeed: true
        SUSignedFeedFailureExpirationInterval: 0
```

Add the corresponding target build settings so XcodeGen resolves the values
from the generator's environment into the generated project:

```yaml
    settings:
      base:
        INKBEAM_APPCAST_URL: ${INKBEAM_GENERATED_APPCAST_URL}
        INKBEAM_SPARKLE_PUBLIC_KEY: ${INKBEAM_SPARKLE_PUBLIC_KEY}
```

Do not add `SUEnableAutomaticChecks` or `SUAllowedURLSchemes`.

- [ ] **Step 5: Add one project generator with no key fallback**

Create executable `Scripts/generate-project.sh`:

```bash
#!/bin/zsh
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
KEY_FILE="${ROOT}/Config/SparklePublicEDKey.txt"
CHANNEL="${INKBEAM_RELEASE_CHANNEL:-stable}"

test -f "${KEY_FILE}"
KEY="$(tr -d '\r\n' < "${KEY_FILE}")"
[[ "${KEY}" =~ '^[A-Za-z0-9+/]{43}=$' ]]

case "${CHANNEL}" in
  beta) FEED='https://gihwan-dev.github.io/inkbeam/appcast-beta.xml' ;;
  stable) FEED='https://gihwan-dev.github.io/inkbeam/appcast.xml' ;;
  *) echo 'INKBEAM_RELEASE_CHANNEL must be beta or stable' >&2; exit 64 ;;
esac

cd "${ROOT}"
INKBEAM_GENERATED_APPCAST_URL="${FEED}" \
INKBEAM_SPARKLE_PUBLIC_KEY="${KEY}" \
xcodegen generate
```

The `stable` default is for local development only. Official builds always pass the stage's exact channel from the release contract; no built app can change it at runtime.

- [ ] **Step 6: Run GREEN and commit**

```bash
chmod +x Scripts/generate-project.sh
Scripts/generate-project.sh
node --test Tests/Release/identity-contract.test.mjs
xcodebuild test -project Inkbeam.xcodeproj -scheme Inkbeam \
  -destination 'platform=macOS' -only-testing:InkbeamTests/AppInfoPlistTests
git add project.yml Config Scripts/generate-project.sh Tests
git commit -m "build(update): pin Sparkle and signed-feed metadata"
```

### Task 2: Block Runtime Services Outside Writable Applications

**Files:**
- Create: `Sources/InkbeamApp/App/InstallLocationPolicy.swift`
- Create: `Tests/InkbeamTests/App/InstallLocationPolicyTests.swift`
- Modify: `Sources/InkbeamApp/App/AppDelegate.swift`
- Modify: `Sources/InkbeamApp/App/InkbeamUserFacingError.swift`
- Modify: `Tests/InkbeamTests/App/AppDelegateLifecycleTests.swift`

- [ ] **Step 1: Add failing policy tests**

```swift
func testReleaseAppInSystemApplicationsIsEligible() {
    XCTAssertEqual(policy.decision(
        bundleURL: URL(fileURLWithPath: "/Applications/Inkbeam.app"),
        isWritable: true,
        isDebugBuild: false
    ), .eligible)
}

func testReleaseAppOnDMGIsRejected() {
    XCTAssertEqual(policy.decision(
        bundleURL: URL(fileURLWithPath: "/Volumes/Inkbeam/Inkbeam.app"),
        isWritable: false,
        isDebugBuild: false
    ), .moveToApplications)
}

func testTranslocatedReleaseAppIsRejected() {
    XCTAssertEqual(policy.decision(
        bundleURL: URL(fileURLWithPath: "/private/var/folders/AppTranslocation/Inkbeam.app"),
        isWritable: true,
        isDebugBuild: false
    ), .moveToApplications)
}
```

Add an AppDelegate lifecycle test proving installer, inbox, hotkey, and updater factories each remain at call count zero when the decision is rejected.

- [ ] **Step 2: Run RED**

```bash
Scripts/generate-project.sh
xcodebuild test -project Inkbeam.xcodeproj -scheme Inkbeam \
  -destination 'platform=macOS' \
  -only-testing:InkbeamTests/InstallLocationPolicyTests \
  -only-testing:InkbeamTests/AppDelegateLifecycleTests
```

- [ ] **Step 3: Implement one explicit policy**

```swift
struct InstallLocationPolicy {
    func decision(
        bundleURL: URL,
        isWritable: Bool,
        isDebugBuild: Bool
    ) -> InstallLocationDecision {
        if isDebugBuild { return .eligible }
        guard isWritable else { return .moveToApplications }
        let path = bundleURL.standardizedFileURL.path
        guard !path.contains("/AppTranslocation/") else {
            return .moveToApplications
        }
        let system = "/Applications/"
        let user = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Applications", isDirectory: true).path + "/"
        return path.hasPrefix(system) || path.hasPrefix(user)
            ? .eligible
            : .moveToApplications
    }
}
```

At the beginning of `applicationDidFinishLaunching`, evaluate the policy. On rejection, activate the app, present an `installLocation` error saying to drag Inkbeam to Applications and relaunch, then return before all normal service setup.

- [ ] **Step 4: Run GREEN and commit**

```bash
xcodebuild test -project Inkbeam.xcodeproj -scheme Inkbeam \
  -destination 'platform=macOS' \
  -only-testing:InkbeamTests/InstallLocationPolicyTests \
  -only-testing:InkbeamTests/AppDelegateLifecycleTests
git add Sources/InkbeamApp/App Tests/InkbeamTests/App
git commit -m "feat(app): gate services on install location"
```

### Task 3: Wrap `SPUStandardUpdaterController` Behind `UpdateService`

**Files:**
- Create: `Sources/InkbeamApp/Update/UpdateConfiguration.swift`
- Create: `Sources/InkbeamApp/Update/UpdateService.swift`
- Create: `Sources/InkbeamApp/Update/UpdateDiagnostics.swift`
- Create: `Tests/InkbeamTests/Update/UpdateConfigurationTests.swift`
- Create: `Tests/InkbeamTests/Update/UpdateServiceTests.swift`

- [ ] **Step 1: Write failing configuration and adapter tests**

Test that only the exact stable and beta HTTPS URLs parse, the public key is one base64 line, manual checking forwards once, and `start()` forwards once even if called repeatedly.

```swift
func testConfigurationRejectsHTTPFeed() {
    XCTAssertThrowsError(try UpdateConfiguration(
        info: validInfo(feed: "http://gihwan-dev.github.io/inkbeam/appcast.xml")
    ))
}

func testManualCheckForwardsExactlyOnce() throws {
    let controller = FakeUpdaterController()
    let service = UpdateService(controller: controller, configuration: .stableFixture)
    try service.start()
    service.checkForUpdates()
    XCTAssertEqual(controller.startCount, 1)
    XCTAssertEqual(controller.manualCheckCount, 1)
}
```

- [ ] **Step 2: Define the adapter seam**

```swift
@MainActor
protocol StandardUpdaterControlling: AnyObject {
    var canCheckForUpdates: Bool { get }
    func startUpdater()
    func checkForUpdates(_ sender: Any?)
}

extension SPUStandardUpdaterController: StandardUpdaterControlling {}
```

Implement `UpdateService`:

```swift
@MainActor
final class UpdateService: UpdateServing {
    private let controller: any StandardUpdaterControlling
    private let configuration: UpdateConfiguration
    private let diagnostics: UpdateDiagnostics
    private var started = false

    init(
        controller: any StandardUpdaterControlling,
        configuration: UpdateConfiguration,
        diagnostics: UpdateDiagnostics = .live
    ) {
        self.controller = controller
        self.configuration = configuration
        self.diagnostics = diagnostics
    }

    var canCheckForUpdates: Bool { controller.canCheckForUpdates }

    func start() throws {
        guard !started else { return }
        try configuration.validate()
        controller.startUpdater()
        started = true
        diagnostics.record(.started(channel: configuration.channel))
    }

    func checkForUpdates() {
        diagnostics.record(.manualCheckStarted(host: configuration.feedURL.host ?? ""))
        controller.checkForUpdates(nil)
    }
}
```

The live factory constructs `SPUStandardUpdaterController(startingUpdater: false, updaterDelegate: nil, userDriverDelegate: nil)`. Do not expose feed setters or Sparkle preferences from this wrapper.

- [ ] **Step 3: Restrict diagnostics**

Use `Logger(subsystem: "dev.gihwan.inkbeam", category: "updates")` and accept only timestamps, current/discovered version/build, result category, Sparkle error code, appcast host, and signature outcome. Do not accept arbitrary strings or URLs in the diagnostics API.

- [ ] **Step 4: Run GREEN and commit**

```bash
Scripts/generate-project.sh
xcodebuild test -project Inkbeam.xcodeproj -scheme Inkbeam \
  -destination 'platform=macOS' -only-testing:InkbeamTests/Update
git add Sources/InkbeamApp/Update Tests/InkbeamTests/Update
git commit -m "feat(update): wrap Sparkle updater service"
```

### Task 4: Add Manual Check UI and Consent-Preserving Startup

**Files:**
- Modify: `Sources/InkbeamApp/App/AppDelegate.swift`
- Modify: `Sources/InkbeamApp/App/MenuBarController.swift`
- Modify: `Sources/InkbeamApp/App/AppDependencies.swift`
- Modify: menu and lifecycle tests

- [ ] **Step 1: Add failing menu/lifecycle tests**

Assert the status menu order is Capture, Open, separator, `Check for Updates…`, separator, Quit; the update item invokes once; launch calls `UpdateService.start()` only after the install-location gate; and no call to `checkForUpdates()` occurs during launch.

- [ ] **Step 2: Inject one updater factory**

Add:

```swift
typealias UpdateServiceFactory = () throws -> any UpdateServing
```

Store the resulting service strongly in AppDelegate. After the install-location gate passes and before constructing the menu, call only `try updateService.start()`. Sparkle owns first/second-launch consent through the absent `SUEnableAutomaticChecks` key.

- [ ] **Step 3: Add the menu command**

Extend `MenuBarController.init` with:

```swift
checkForUpdates: @escaping () -> Void,
canCheckForUpdates: @escaping () -> Bool,
```

Create `Check for Updates…` with no key equivalent. Its action calls the closure, and validation reads `canCheckForUpdates()`.

- [ ] **Step 4: Run GREEN and commit**

```bash
xcodebuild test -project Inkbeam.xcodeproj -scheme Inkbeam \
  -destination 'platform=macOS' \
  -only-testing:InkbeamTests/MenuBarControllerTests \
  -only-testing:InkbeamTests/AppDelegateLifecycleTests
git add Sources/InkbeamApp/App Tests/InkbeamTests/App
git commit -m "feat(update): add consent-preserving update menu"
```

### Task 5: Prove Update Relaunch Cannot Bypass Document Safety

**Files:**
- Modify: `Tests/InkbeamTests/App/AppDelegateLifecycleTests.swift`
- Modify only if tests expose a gap: `Sources/InkbeamApp/App/AppDelegate.swift`, `Sources/InkbeamApp/Documents/DocumentWindowController.swift`

- [ ] **Step 1: Add the three update-relaunch decision tests**

Use existing `EditorWindowControlling` fakes to prove:

1. cancel returns `terminateLater`, replies `false`, and a later retry prompts again;
2. save completes before reply `true`, and a save failure replies `false`;
3. explicit discard replies `true` while the last saved project remains unchanged.

Also retain active-output cancellation, prompt coalescing, revision-change restart, and newly opened window coverage.

- [ ] **Step 2: Run RED or confirm the existing state machine is already GREEN**

```bash
xcodebuild test -project Inkbeam.xcodeproj -scheme Inkbeam \
  -destination 'platform=macOS' \
  -only-testing:InkbeamTests/AppDelegateLifecycleTests \
  -only-testing:InkbeamTests/DocumentWindowControllerOutputTests
```

If all new tests pass, do not modify production termination code. If one fails, make the smallest change inside the existing `resolveTermination()` loop; do not add an updater-specific quit route.

- [ ] **Step 3: Commit tests and any minimal correction**

```bash
git add Tests/InkbeamTests/App Sources/InkbeamApp/App Sources/InkbeamApp/Documents
git commit -m "test(update): prove modified document relaunch safety"
```

### Task 6: Add Consent/Network Harness and Full Updater Gate

**Files:**
- Create: `Tests/UpdaterHarness/RequestCountingServer.swift`
- Create: `Tests/InkbeamTests/Update/UpdaterConsentIntegrationTests.swift`
- Modify: `Scripts/verify-privacy.sh`
- Modify: `README.md`, `Tests/Release/documentation.test.mjs`

- [ ] **Step 1: Build a request-counting HTTPS test seam**

The harness records only request count, method, timestamp, and path. Inject isolated `UserDefaults` suites and a clock into the Inkbeam orchestration test; do not alter Sparkle defaults in production.

- [ ] **Step 2: Encode the observable matrix**

Automated orchestration tests must assert:

```text
launch 1                         prompt 0, automatic requests 0
launch 2 before consent         prompt 1, automatic requests 0
approve                         requests 1 only after approval
decline                         requests 0
launch 3 both branches          prompt 0
approved launch before 86400s   extra requests 0
approved launch at 86400s       eligible scheduled requests 1
```

Use two isolated profiles for approve and decline. Keep real Sparkle UI/network observation as a mandatory RC acceptance item in the rollout plan.

- [ ] **Step 3: Replace the old no-updater documentation assertion**

Document manual checks, second-launch consent, 24-hour scheduling after approval, no automatic download/install, no system profiling, exact GitHub Pages/Release network boundary, and install-to-Applications requirement. The release docs test must reject claims of silent installation, analytics, a beta toggle, or a first-launch automatic check.

- [ ] **Step 4: Run the plan completion gate**

```bash
Scripts/generate-project.sh
pnpm test:release
Scripts/verify-privacy.sh
xcodebuild test -project Inkbeam.xcodeproj -scheme Inkbeam -destination 'platform=macOS'
node Scripts/verify-clean-cutover.mjs
git diff --check
```

Expected: all pass; Info.plist has the exact security settings; first-launch orchestration performs no automatic request; termination tests cover cancel, save/retry, discard, and failure.

- [ ] **Step 5: Commit**

```bash
git add Tests/UpdaterHarness Tests/InkbeamTests Scripts/verify-privacy.sh README.md Tests/Release
git commit -m "test(update): enforce consent privacy and lifecycle policy"
```

## Completion Gate

- Sparkle resolves at exact `2.9.4` and `SPUStandardUpdaterController` is the only updater API.
- The public key is committed once; release private key material remains only in Keychain account `inkbeam`.
- RC/stable feed choice is build-time only and all signed-feed/security keys are exact.
- First launch has no prompt/request; second launch prompts once; approval schedules 24-hour checks; decline keeps manual checks only.
- Automatic download, automatic installation, system profiling, JavaScript release notes, telemetry, and runtime feed changes are disabled.
- A release app outside writable Applications initializes none of updater, Chrome host/inbox, or global shortcut services.
- Sparkle relaunch travels through the existing modified-document termination gate, including cancel, save, discard, and failure outcomes.
- The worktree is clean after the final task commit.
