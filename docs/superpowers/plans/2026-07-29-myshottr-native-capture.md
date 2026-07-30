# MyShottr Native Region Capture Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a permission-aware, multi-display-safe macOS region selector that captures one display region with ScreenCaptureKit and opens it in the existing editor pipeline.

**Architecture:** AppKit owns one transparent selection panel per display and isolates every coordinate conversion in `DisplayGeometry`. A ScreenCaptureKit adapter accepts a selected display and local point rectangle, returns a source-resolution PNG, and hands it to the existing `DocumentSession` factory.

**Tech Stack:** Swift 6, AppKit, SwiftUI, ScreenCaptureKit, CoreGraphics, XCTest

## Global Constraints

- Execute this plan only after `2026-07-29-myshottr-foundation-editor.md` and
  `2026-07-30-myshottr-editor-public-polish.md`.
- Minimum supported macOS version is macOS 15.
- ScreenCaptureKit and `SCScreenshotManager` are the only capture path.
- No deprecated capture API or fallback capture implementation is permitted.
- Region selection may start on any connected display but may not span displays.
- The selection overlay must never appear in the captured image.
- AppKit-point and source-pixel conversions must work for 1x, 2x, negative display origins, and mixed-scale displays.
- The default global shortcut is `Command-Shift-2`; v1 does not customize it.
- Use TDD for behavior and commit after every task.

---

## Repository Map for This Plan

```text
Sources/MyShottrApp/
├── App/
│   ├── AppDelegate.swift
│   ├── AppDependencies.swift
│   ├── GlobalHotKeyRegistrar.swift
│   └── MenuBarController.swift
└── Capture/
    ├── CaptureError.swift
    ├── DisplayDescriptor.swift
    ├── DisplayGeometry.swift
    ├── RegionCaptureCoordinator.swift
    ├── RegionSelectionController.swift
    ├── RegionSelectionPanel.swift
    ├── RegionSelectionView.swift
    ├── ScreenCaptureClient.swift
    └── ScreenCapturePermission.swift
Tests/MyShottrTests/Capture/
```

## Shared Interfaces

```swift
struct DisplayDescriptor: Equatable, Sendable {
    let displayID: CGDirectDisplayID
    let frameInAppKitPoints: CGRect
    let scale: CGFloat
    let pixelSize: CGSize
}

struct RegionSelection: Equatable, Sendable {
    let display: DisplayDescriptor
    let rectInDisplayPoints: CGRect
}

enum RegionSelectionOutcome: Equatable, Sendable {
    case confirmed(RegionSelection)
    case cancelled
}

protocol ScreenCapturing: Sendable {
    func capture(selection: RegionSelection) async throws -> CaptureArtifact
}

@MainActor
protocol RegionSelecting: AnyObject {
    func selectRegion() async throws -> RegionSelectionOutcome
    func cancel()
}
```

### Task 1: Display Geometry Contract

**Files:**
- Create: `Sources/MyShottrApp/Capture/DisplayDescriptor.swift`
- Create: `Sources/MyShottrApp/Capture/DisplayGeometry.swift`
- Test: `Tests/MyShottrTests/Capture/DisplayGeometryTests.swift`
- Test support: `Tests/MyShottrTests/Support/CaptureFixtures.swift`

**Interfaces:**
- Consumes: `DisplayDescriptor` and `RegionSelection`.
- Produces: `DisplayGeometry.localRect(fromGlobalAppKitRect:on:)`, `sourceRect(for:)`, `pixelRect(for:)`, and `clamp(_:to:)`.

- [ ] **Step 1: Write failing coordinate tests**

Create exact fixtures for:

```swift
private let retina = DisplayDescriptor(
    displayID: 1,
    frameInAppKitPoints: CGRect(x: 0, y: 0, width: 1512, height: 982),
    scale: 2,
    pixelSize: CGSize(width: 3024, height: 1964)
)

private let leftDisplay = DisplayDescriptor(
    displayID: 2,
    frameInAppKitPoints: CGRect(x: -1920, y: 0, width: 1920, height: 1080),
    scale: 1,
    pixelSize: CGSize(width: 1920, height: 1080)
)
```

Assert:

```swift
func testRetinaPointRectConvertsToPixelRect() {
    let selection = RegionSelection(
        display: retina,
        rectInDisplayPoints: CGRect(x: 100, y: 80, width: 300, height: 200)
    )
    XCTAssertEqual(DisplayGeometry.pixelRect(for: selection),
                   CGRect(x: 200, y: 1404, width: 600, height: 400))
}

func testRetinaPointRectConvertsToScreenCaptureLogicalRect() {
    let selection = RegionSelection(
        display: retina,
        rectInDisplayPoints: CGRect(x: 100, y: 80, width: 300, height: 200)
    )
    XCTAssertEqual(DisplayGeometry.sourceRect(for: selection),
                   CGRect(x: 100, y: 702, width: 300, height: 200))
}

func testGlobalRectOnNegativeOriginDisplayBecomesLocal() {
    let global = CGRect(x: -1820, y: 100, width: 500, height: 400)
    XCTAssertEqual(DisplayGeometry.localRect(fromGlobalAppKitRect: global, on: leftDisplay),
                   CGRect(x: 100, y: 100, width: 500, height: 400))
}

func testClampNeverAllowsSelectionOutsideDisplay() {
    let rect = CGRect(x: -10, y: 900, width: 200, height: 200)
    XCTAssertEqual(DisplayGeometry.clamp(rect, to: retina),
                   CGRect(x: 0, y: 782, width: 200, height: 200))
}
```

The Retina expected `y` converts AppKit's bottom-left point origin to the
captured image's top-left pixel origin:
`(982 - 80 - 200) * 2 = 1404`.

`CaptureFixtures` exports:

```swift
enum CaptureFixtures {
    static let retinaDisplay: DisplayDescriptor
    static let leftDisplay: DisplayDescriptor
    static let selection: RegionSelection
    static let retinaSelection: RegionSelection
}
```

- [ ] **Step 2: Run the focused test and verify failure**

Run:

```bash
xcodebuild test -project MyShottr.xcodeproj -scheme MyShottr \
  -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO \
  -only-testing:MyShottrTests/DisplayGeometryTests
```

Expected: compilation fails because `DisplayGeometry` is undefined.

- [ ] **Step 3: Implement pure coordinate conversions**

Implement:

```swift
enum DisplayGeometry {
    static func localRect(
        fromGlobalAppKitRect rect: CGRect,
        on display: DisplayDescriptor
    ) -> CGRect {
        CGRect(
            x: rect.minX - display.frameInAppKitPoints.minX,
            y: rect.minY - display.frameInAppKitPoints.minY,
            width: rect.width,
            height: rect.height
        )
    }

    static func pixelRect(for selection: RegionSelection) -> CGRect {
        let source = sourceRect(for: selection)
        return CGRect(
            x: source.minX * selection.display.scale,
            y: source.minY * selection.display.scale,
            width: source.width * selection.display.scale,
            height: source.height * selection.display.scale
        ).integral
    }

    static func sourceRect(for selection: RegionSelection) -> CGRect {
        let points = clamp(selection.rectInDisplayPoints, to: selection.display)
        let displayHeight = selection.display.frameInAppKitPoints.height
        return CGRect(
            x: points.minX,
            y: displayHeight - points.maxY,
            width: points.width,
            height: points.height
        )
    }

    static func clamp(_ rect: CGRect, to display: DisplayDescriptor) -> CGRect {
        let bounds = CGRect(origin: .zero, size: display.frameInAppKitPoints.size)
        let width = min(max(1, rect.width), bounds.width)
        let height = min(max(1, rect.height), bounds.height)
        return CGRect(
            x: min(max(bounds.minX, rect.minX), bounds.maxX - width),
            y: min(max(bounds.minY, rect.minY), bounds.maxY - height),
            width: width,
            height: height
        )
    }
}
```

- [ ] **Step 4: Run capture geometry tests**

Run:

```bash
xcodebuild test -project MyShottr.xcodeproj -scheme MyShottr \
  -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO \
  -only-testing:MyShottrTests/DisplayGeometryTests
```

Expected: `DisplayGeometryTests` passes.

- [ ] **Step 5: Commit the geometry boundary**

```bash
git add Sources/MyShottrApp/Capture/DisplayDescriptor.swift \
  Sources/MyShottrApp/Capture/DisplayGeometry.swift \
  Tests/MyShottrTests/Capture/DisplayGeometryTests.swift
git commit -m "feat: define display capture geometry"
```

### Task 2: Permission and ScreenCaptureKit Adapter

**Files:**
- Create: `Sources/MyShottrApp/Capture/CaptureError.swift`
- Create: `Sources/MyShottrApp/Capture/ScreenCapturePermission.swift`
- Create: `Sources/MyShottrApp/Capture/ScreenCaptureClient.swift`
- Test: `Tests/MyShottrTests/Capture/ScreenCapturePermissionTests.swift`
- Test: `Tests/MyShottrTests/Capture/ScreenCaptureClientTests.swift`

**Interfaces:**
- Consumes: `RegionSelection` and `DisplayGeometry.pixelRect(for:)`.
- Produces: `ScreenCapturePermissionProviding`, `ScreenCaptureClient.capture(selection:)`, a `.screenRegion` `CaptureArtifact`, and actionable `CaptureError`.

- [ ] **Step 1: Write failing permission and configuration tests**

Use injected closures so permission behavior is testable:

```swift
func testDeniedPermissionReturnsActionableError() {
    let permission = ScreenCapturePermission(
        preflight: { false },
        request: { false },
        openSettings: {}
    )
    XCTAssertThrowsError(try permission.requireAccess()) {
        XCTAssertEqual($0 as? CaptureError, .screenRecordingPermissionDenied)
    }
}

func testConfigurationUsesExactPixelDimensions() throws {
    let selection = CaptureFixtures.retinaSelection
    let configuration = try ScreenCaptureClient.configuration(for: selection)
    XCTAssertEqual(configuration.width, 600)
    XCTAssertEqual(configuration.height, 400)
    XCTAssertEqual(configuration.sourceRect,
                   CGRect(x: 100, y: 702, width: 300, height: 200))
}
```

The `sourceRect` passed to ScreenCaptureKit is display-local logical points
with a top-left origin while width and height are source pixels.

- [ ] **Step 2: Run tests and verify failure**

Run:

```bash
xcodebuild test -project MyShottr.xcodeproj -scheme MyShottr \
  -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO \
  -only-testing:MyShottrTests/ScreenCapturePermissionTests \
  -only-testing:MyShottrTests/ScreenCaptureClientTests
```

Expected: missing-type compilation failures.

- [ ] **Step 3: Implement permission and capture**

Define:

```swift
enum CaptureError: Error, Equatable {
    case screenRecordingPermissionDenied
    case displayUnavailable(CGDirectDisplayID)
    case emptySelection
    case captureAlreadyInProgress
    case captureFailed(String)
    case pngEncodingFailed
}
```

`ScreenCapturePermission` wraps `CGPreflightScreenCaptureAccess`,
`CGRequestScreenCaptureAccess`, and an
`NSWorkspace.open(URL(string:
"x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture")!)`
action. `requireAccess()` requests once and throws on denial.

`ScreenCaptureClient.capture` must:

1. require permission before enumerating content;
2. fetch `SCShareableContent.excludingDesktopWindows(false,
   onScreenWindowsOnly: true)`;
3. find the `SCDisplay` matching `displayID`;
4. construct `SCContentFilter(display:excludingWindows:)`;
5. set `SCStreamConfiguration.sourceRect` from
   `DisplayGeometry.sourceRect(for:)`;
6. set output width and height from `DisplayGeometry.pixelRect`;
7. set `showsCursor = false`;
8. await `SCScreenshotManager.captureImage`;
9. encode the `CGImage` as PNG through ImageIO;
10. return `CaptureArtifact(id: UUID(), sourceKind: .screenRegion, pngData:
    pngData, scale: Double(selection.display.scale))`.

Do not introduce `CGWindowListCreateImage`, `CGDisplayCreateImage`, command-line
`screencapture`, or another capture path.

- [ ] **Step 4: Run focused and complete native tests**

Run:

```bash
xcodebuild test -project MyShottr.xcodeproj -scheme MyShottr \
  -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO
```

Expected: all native tests pass without requiring Screen Recording permission;
the real ScreenCaptureKit call remains behind the injected adapter in tests.

- [ ] **Step 5: Commit ScreenCaptureKit integration**

```bash
git add Sources/MyShottrApp/Capture Tests/MyShottrTests/Capture
git commit -m "feat: capture selected regions with ScreenCaptureKit"
```

### Task 3: Region Selection Overlay

**Files:**
- Create: `Sources/MyShottrApp/Capture/RegionSelectionPanel.swift`
- Create: `Sources/MyShottrApp/Capture/RegionSelectionView.swift`
- Create: `Sources/MyShottrApp/Capture/RegionSelectionController.swift`
- Test: `Tests/MyShottrTests/Capture/RegionSelectionStateTests.swift`

**Interfaces:**
- Consumes: `[DisplayDescriptor]`.
- Produces: `RegionSelecting.selectRegion()`, a `RegionSelectionState` reducer, and one `RegionSelectionPanel` per display.

- [ ] **Step 1: Write failing interaction-state tests**

Keep pointer behavior in a pure reducer:

```swift
func testDragCreatesNormalizedSelection() {
    var state = RegionSelectionState(display: CaptureFixtures.retinaDisplay)
    state.reduce(.pointerDown(CGPoint(x: 400, y: 300)))
    state.reduce(.pointerDragged(CGPoint(x: 100, y: 80)))
    XCTAssertEqual(state.selectionRect,
                   CGRect(x: 100, y: 80, width: 300, height: 220))
}

func testMoveClampsSelectionToDisplay() {
    var state = RegionSelectionState(
        display: CaptureFixtures.retinaDisplay,
        selectionRect: CGRect(x: 100, y: 100, width: 300, height: 200)
    )
    state.reduce(.beginMove(CGPoint(x: 150, y: 150)))
    state.reduce(.pointerDragged(CGPoint(x: -500, y: -500)))
    XCTAssertEqual(state.selectionRect?.origin, .zero)
}

func testReturnConfirmsOnlyNonEmptySelection() {
    var state = RegionSelectionState(display: CaptureFixtures.retinaDisplay)
    state.reduce(.confirm)
    XCTAssertNil(state.result)
}
```

Also cover all eight resize handles, `Escape`, a second pointer-down replacing
the selection, and events received by a non-active display.

- [ ] **Step 2: Run the focused tests and verify failure**

Run:

```bash
xcodebuild test -project MyShottr.xcodeproj -scheme MyShottr \
  -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO \
  -only-testing:MyShottrTests/RegionSelectionStateTests
```

Expected: compilation fails because selection state is undefined.

- [ ] **Step 3: Implement reducer, view, panels, and continuation lifecycle**

`RegionSelectionPanel` must be borderless, non-activating until capture begins,
opaque `false`, background clear, and at `.screenSaver` level. During capture
it accepts key events and uses a crosshair cursor.

`RegionSelectionView` must draw:

- a 55% black dimming layer outside the selected rectangle;
- a one-source-pixel white border around the selection;
- eight 8×8 point resize handles;
- width × height in source pixels above the selection.

`RegionSelectionController.selectRegion()` creates panels for all current
screens, activates the panel where pointer-down begins, ignores drag events
from other displays, and resumes its continuation exactly once with:

Closing panels, pressing `Escape`, or calling `cancel()` must resolve and clear
the continuation. Pressing `Return` confirms a non-empty selection. Hide and
order out every panel before returning `.confirmed`.

- [ ] **Step 4: Run overlay state and lifecycle tests**

Run:

```bash
xcodebuild test -project MyShottr.xcodeproj -scheme MyShottr \
  -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO \
  -only-testing:MyShottrTests/RegionSelectionStateTests
```

Expected: every reducer and single-resume test passes.

- [ ] **Step 5: Commit the overlay**

```bash
git add Sources/MyShottrApp/Capture/RegionSelection* \
  Tests/MyShottrTests/Capture/RegionSelectionStateTests.swift
git commit -m "feat: add interactive region selection overlay"
```

### Task 4: Menu Bar, Global Shortcut, and Capture Pipeline

**Files:**
- Create: `Sources/MyShottrApp/App/AppDependencies.swift`
- Create: `Sources/MyShottrApp/App/GlobalHotKeyRegistrar.swift`
- Create: `Sources/MyShottrApp/App/MenuBarController.swift`
- Create: `Sources/MyShottrApp/Capture/RegionCaptureCoordinator.swift`
- Modify: `Sources/MyShottrApp/App/AppDelegate.swift`
- Modify: `Sources/MyShottrApp/App/MyShottrApp.swift`
- Modify: `Sources/MyShottrApp/Documents/DocumentWindowController.swift`
- Test: `Tests/MyShottrTests/Capture/RegionCaptureCoordinatorTests.swift`
- Test: `Tests/MyShottrTests/App/GlobalHotKeyRegistrarTests.swift`
- Test support: `Tests/MyShottrTests/Support/CaptureFakes.swift`

**Interfaces:**
- Consumes: `RegionSelecting`, `ScreenCapturing`, `NewProjectCreating`, `DocumentWindowController`, and `ProjectPackageStoring`.
- Produces: menu-bar Capture Area/Open Project/Quit commands and the `Command-Shift-2` capture pipeline.

- [ ] **Step 1: Write failing coordinator tests**

Use fakes to assert:

```swift
@MainActor
func testConfirmedSelectionOpensScreenRegionDocument() async throws {
    let selector = FakeRegionSelector(result: .confirmed(CaptureFixtures.selection))
    let capturer = FakeScreenCapturer(result: try CaptureArtifact(
        id: UUID(uuidString: "299BEFAA-FF18-49FD-B39B-58F622AF1605")!,
        sourceKind: .screenRegion,
        pngData: ProjectFixtures.pngData,
        scale: 2
    ))
    let projects = StubNewProjectFactory()
    let windows = SpyDocumentWindowPresenter()
    let coordinator = RegionCaptureCoordinator(
        selector: selector,
        capturer: capturer,
        projectFactory: projects,
        windows: windows
    )

    await coordinator.captureArea()

    XCTAssertEqual(windows.presentedProjects.count, 1)
    XCTAssertEqual(windows.presentedProjects[0].manifest.sourceKind, .screenRegion)
}

@MainActor
func testCancelledSelectionDoesNotCaptureOrOpenWindow() async {
    // Arrange `.cancelled`; assert capturer and presenter are untouched.
}
```

Test a second trigger while capture is active returns
`CaptureError.captureAlreadyInProgress` and does not create another overlay.

Create test doubles with these exact boundaries:

```swift
@MainActor
protocol DocumentWindowPresenting: AnyObject {
    func present(project: MyShottrProject)
}

@MainActor
final class FakeRegionSelector: RegionSelecting {
    var result: RegionSelectionOutcome
    func selectRegion() async throws -> RegionSelectionOutcome { result }
    func cancel() {}
}

struct FakeScreenCapturer: ScreenCapturing {
    let result: CaptureArtifact
    func capture(selection: RegionSelection) async throws -> CaptureArtifact {
        result
    }
}

struct StubNewProjectFactory: NewProjectCreating {
    func make(
        artifact: CaptureArtifact,
        now: Date
    ) throws -> MyShottrProject {
        try NewProjectFactory(
            preferences: StubPreferences(.approvedDefaults)
        ).make(
            artifact: artifact,
            now: now
        )
    }
}

@MainActor
final class SpyDocumentWindowPresenter: DocumentWindowPresenting {
    private(set) var presentedProjects: [MyShottrProject] = []
    func present(project: MyShottrProject) { presentedProjects.append(project) }
}
```

`DocumentWindowController` conforms to `DocumentWindowPresenting`.

- [ ] **Step 2: Run focused tests and verify failure**

Run:

```bash
xcodebuild test -project MyShottr.xcodeproj -scheme MyShottr \
  -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO \
  -only-testing:MyShottrTests/RegionCaptureCoordinatorTests
```

Expected: missing coordinator compilation failure.

- [ ] **Step 3: Implement app composition and commands**

`GlobalHotKeyRegistrar` uses `RegisterEventHotKey` with key code for `2` and
`cmdKey | shiftKey`. It owns and unregisters the event handler and throws
`GlobalHotKeyError.registrationFailed(OSStatus)` on conflicts.

`MenuBarController` creates one `NSStatusItem` with:

```text
Capture Area        ⌘⇧2
Open Project…
-----------------------
Quit MyShottr
```

Load `NSImage(named: "StatusBarIcon")`, require the bundled image, set
`isTemplate = true`, and assign it to the status button. A missing asset is an
explicit initialization error rather than a text-only status item.

`RegionCaptureCoordinator.captureArea()` must guard against reentrancy, await
selection, obtain the validated artifact from `capturer.capture(selection:)`,
and create a `MyShottrProject` with:

```swift
let project = try projectFactory.make(
    artifact: artifact,
    now: now()
)
```

and open it with the existing document window. The shared factory owns schema
version `2`, `presentation: none`, dimensions, and remembered defaults; the
capture coordinator must not construct annotation JSON itself.

Change `MyShottrApp` to expose no empty `WindowGroup`; `AppDelegate` creates the
menu-bar controller and document windows on demand. Use activation policy
`.accessory` until an editor window opens, activate MyShottr when a document
opens, and return to `.accessory` after the last editor closes.

- [ ] **Step 4: Run the native capture gate**

Run:

```bash
pnpm test
pnpm build
xcodegen generate
xcodebuild test -project MyShottr.xcodeproj -scheme MyShottr \
  -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO
xcodebuild build -project MyShottr.xcodeproj -scheme MyShottr \
  -configuration Debug -destination 'platform=macOS'
```

Expected: automated tests pass and the signed local Debug app builds.

- [ ] **Step 5: Manually verify real ScreenCaptureKit behavior**

Run the Debug app and verify:

1. first capture shows the Screen Recording permission explanation;
2. denial stops capture and opens the correct System Settings pane on request;
3. after granting permission and relaunching, `Command-Shift-2` opens overlays
   on every display;
4. selecting a Retina region opens a document with matching pixel dimensions;
5. the dimming overlay and selection border are absent from the captured image;
6. `Escape` cancels without opening an editor;
7. a second shortcut during selection does not create a second capture flow.

- [ ] **Step 6: Commit the native capture increment**

```bash
git add Sources/MyShottrApp Tests/MyShottrTests
git commit -m "feat: capture macOS regions from the menu bar"
```

## Plan 2 Completion Gate

The increment is complete only after the full automated gate passes and the
seven manual permission and capture checks succeed on the local Mac. Chrome
capture remains absent and enters through the same `MyShottrProject` creation
path in Plan 3.
