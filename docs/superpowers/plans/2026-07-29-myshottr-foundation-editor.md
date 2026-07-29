# MyShottr Foundation and Editor Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a runnable macOS document app that opens `.myshottr` projects, provides eight tools (selection plus seven drawable annotations) in a local WKWebView canvas, and copies or exports a source-resolution PNG.

**Architecture:** XcodeGen creates a SwiftUI/AppKit document application and embeds a Vite-built React editor. Swift owns project packages, native windows, files, and the clipboard; TypeScript owns annotation state, interaction, rendering, and undo/redo through a versioned bridge.

**Tech Stack:** Swift 6, SwiftUI, AppKit, WKWebView, XcodeGen, TypeScript, React, Konva, rough.js, Zod, Vite, Vitest, XCTest

## Global Constraints

- Minimum supported macOS version is macOS 15.
- The editor bundle is local-only; it must not load runtime CDN or remote assets.
- The canvas coordinate system is source-image pixels and export dimensions equal source dimensions.
- The source PNG is immutable; annotations remain separate vector data.
- The project format contains exactly `manifest.json`, `original.png`, and `document.json`.
- Unsupported project versions and element types fail explicitly; data is never silently discarded.
- v1 has no layers panel, grouping, infinite canvas, cloud sync, telemetry, or capture history.
- Use TDD for behavior and commit after every task.

---

## Repository Map for This Plan

```text
Config/
├── MyShottr.entitlements
└── MyShottr-Info.plist
Packages/
└── editor/
    ├── index.html
    ├── package.json
    ├── tsconfig.json
    ├── vite.config.ts
    └── src/
        ├── App.tsx
        ├── main.tsx
        ├── bridge/
        ├── canvas/
        ├── model/
        └── test/
Scripts/
└── build-editor.sh
Sources/
└── MyShottrApp/
    ├── App/
    ├── Documents/
    ├── Editor/
    └── Export/
Tests/
└── MyShottrTests/
project.yml
package.json
pnpm-workspace.yaml
```

## Shared Interfaces

Swift owns these interfaces from Task 2 onward:

```swift
enum CaptureSourceKind: String, Codable, Sendable {
    case screenRegion
    case chromeVisibleViewport
}

struct ProjectManifest: Codable, Equatable, Sendable {
    static let currentFormatVersion = 1
    let formatVersion: Int
    let documentId: UUID
    let createdAt: Date
    var updatedAt: Date
    let sourcePixelWidth: Int
    let sourcePixelHeight: Int
    let sourceKind: CaptureSourceKind
}

struct MyShottrProject: Equatable, Sendable {
    var manifest: ProjectManifest
    let originalPNG: Data
    var annotationJSON: Data
}

protocol ProjectPackageStoring: Sendable {
    func load(from url: URL) throws -> MyShottrProject
    func save(_ project: MyShottrProject, to url: URL) throws
}
```

TypeScript owns this editor surface from Task 3 onward:

```ts
export type EditorDocument = {
  schemaVersion: 1;
  sourcePixelWidth: number;
  sourcePixelHeight: number;
  elements: EditorElement[];
  defaults: EditorDefaults;
};

export type EditorCommand =
  | { type: "create"; element: EditorElement }
  | { type: "update"; element: EditorElement }
  | { type: "delete"; ids: string[] }
  | { type: "reorder"; ids: string[]; direction: "forward" | "backward" };
```

### Task 1: Reproducible Workspace and App Shell

**Files:**
- Modify: `.gitignore`
- Create: `project.yml`
- Create: `Config/MyShottr-Info.plist`
- Create: `Config/MyShottr.entitlements`
- Create: `package.json`
- Create: `pnpm-workspace.yaml`
- Create: `Packages/editor/package.json`
- Create: `Packages/editor/index.html`
- Create: `Packages/editor/tsconfig.json`
- Create: `Packages/editor/vite.config.ts`
- Create: `Packages/editor/src/main.tsx`
- Create: `Packages/editor/src/App.tsx`
- Create: `Scripts/build-editor.sh`
- Create: `Sources/MyShottrApp/App/MyShottrApp.swift`
- Create: `Sources/MyShottrApp/App/AppDelegate.swift`
- Test: `Tests/MyShottrTests/AppConfigurationTests.swift`

**Interfaces:**
- Consumes: None.
- Produces: `MyShottr.app`, the `MyShottrTests` XCTest target, and the `@myshottr/editor` workspace package.

- [ ] **Step 1: Install and verify the project generator**

Run:

```bash
brew install xcodegen
xcodegen --version
```

Expected: both commands exit `0`, and the second command prints an XcodeGen version.

- [ ] **Step 2: Write the failing app-configuration test**

Create `Tests/MyShottrTests/AppConfigurationTests.swift`:

```swift
import XCTest
@testable import MyShottr

final class AppConfigurationTests: XCTestCase {
    func testBundleDeclaresScreenCaptureReasonAndProjectType() throws {
        let info = try XCTUnwrap(Bundle.main.infoDictionary)
        XCTAssertFalse(try XCTUnwrap(info["NSScreenCaptureUsageDescription"] as? String).isEmpty)

        let documentTypes = try XCTUnwrap(info["CFBundleDocumentTypes"] as? [[String: Any]])
        let extensions = documentTypes
            .compactMap { $0["CFBundleTypeExtensions"] as? [String] }
            .flatMap { $0 }
        XCTAssertTrue(extensions.contains("myshottr"))
    }
}
```

- [ ] **Step 3: Add the workspace manifests and minimal app**

Create `project.yml` with these complete target definitions:

```yaml
name: MyShottr
options:
  bundleIdPrefix: com.myshottr
  deploymentTarget:
    macOS: "15.0"
settings:
  base:
    SWIFT_VERSION: "6.0"
    MACOSX_DEPLOYMENT_TARGET: "15.0"
    ENABLE_USER_SCRIPT_SANDBOXING: NO
targets:
  MyShottr:
    type: application
    platform: macOS
    sources:
      - Sources/MyShottrApp
    info:
      path: Config/MyShottr-Info.plist
    entitlements:
      path: Config/MyShottr.entitlements
    preBuildScripts:
      - name: Build Local Editor
        script: Scripts/build-editor.sh
        basedOnDependencyAnalysis: false
    settings:
      base:
        PRODUCT_BUNDLE_IDENTIFIER: com.myshottr.app
        PRODUCT_NAME: MyShottr
        CODE_SIGN_STYLE: Automatic
  MyShottrTests:
    type: bundle.unit-test
    platform: macOS
    sources:
      - Tests/MyShottrTests
    dependencies:
      - target: MyShottr
schemes:
  MyShottr:
    build:
      targets:
        MyShottr: all
        MyShottrTests: [test]
    test:
      targets:
        - MyShottrTests
```

Create the root JS workspace:

```json
{
  "name": "myshottr",
  "private": true,
  "packageManager": "pnpm@10.14.0",
  "scripts": {
    "build": "pnpm --filter @myshottr/editor build",
    "test": "pnpm -r test",
    "typecheck": "pnpm -r typecheck"
  }
}
```

```yaml
packages:
  - Packages/*
```

Create `Packages/editor/package.json`:

```json
{
  "name": "@myshottr/editor",
  "private": true,
  "type": "module",
  "scripts": {
    "build": "tsc --noEmit && vite build",
    "test": "vitest run",
    "typecheck": "tsc --noEmit"
  },
  "dependencies": {
    "konva": "^10.0.0",
    "react": "^19.0.0",
    "react-dom": "^19.0.0",
    "react-konva": "^19.0.0",
    "roughjs": "^4.6.6",
    "zod": "^4.0.0"
  },
  "devDependencies": {
    "@testing-library/react": "^16.0.0",
    "@types/react": "^19.0.0",
    "@types/react-dom": "^19.0.0",
    "@vitejs/plugin-react": "^5.0.0",
    "jsdom": "^26.0.0",
    "typescript": "^5.9.0",
    "vite": "^7.0.0",
    "vitest": "^3.0.0"
  }
}
```

Create `Packages/editor/tsconfig.json`:

```json
{
  "compilerOptions": {
    "target": "ES2022",
    "useDefineForClassFields": true,
    "lib": ["ES2022", "DOM", "DOM.Iterable"],
    "allowJs": false,
    "skipLibCheck": true,
    "esModuleInterop": true,
    "allowSyntheticDefaultImports": true,
    "strict": true,
    "forceConsistentCasingInFileNames": true,
    "module": "ESNext",
    "moduleResolution": "Bundler",
    "resolveJsonModule": true,
    "isolatedModules": true,
    "noEmit": true,
    "jsx": "react-jsx",
    "types": ["vitest/globals"]
  },
  "include": ["src", "vite.config.ts"]
}
```

Create `Packages/editor/vite.config.ts`:

```ts
import { defineConfig } from "vitest/config";
import react from "@vitejs/plugin-react";

export default defineConfig({
  base: "./",
  plugins: [react()],
  build: {
    outDir: "dist",
    emptyOutDir: true,
  },
  test: {
    environment: "jsdom",
    setupFiles: [],
  },
});
```

Create `Packages/editor/index.html`:

```html
<!doctype html>
<html lang="en">
  <head>
    <meta charset="UTF-8" />
    <meta name="viewport" content="width=device-width, initial-scale=1.0" />
    <title>MyShottr Editor</title>
  </head>
  <body>
    <div id="root"></div>
    <script type="module" src="/src/main.tsx"></script>
  </body>
</html>
```

Create `Packages/editor/src/main.tsx` and `App.tsx`:

```tsx
import { StrictMode } from "react";
import { createRoot } from "react-dom/client";
import { App } from "./App";

const root = document.getElementById("root");
if (!root) throw new Error("Missing #root");

createRoot(root).render(
  <StrictMode>
    <App />
  </StrictMode>,
);
```

```tsx
export function App() {
  return <main aria-label="MyShottr editor">Editor ready</main>;
}
```

`Scripts/build-editor.sh` must build into the app resources without a network step:

```bash
#!/bin/zsh
set -euo pipefail

REPO_ROOT="${SRCROOT}"
EDITOR_DIR="${REPO_ROOT}/Packages/editor"
OUTPUT_DIR="${TARGET_BUILD_DIR}/${UNLOCALIZED_RESOURCES_FOLDER_PATH}/Editor"

cd "${EDITOR_DIR}"
pnpm build
rm -rf "${OUTPUT_DIR}"
mkdir -p "${OUTPUT_DIR}"
cp -R dist/. "${OUTPUT_DIR}/"
```

Create a minimal SwiftUI app:

```swift
import SwiftUI

@main
struct MyShottrApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        WindowGroup {
            Text("MyShottr")
                .frame(minWidth: 960, minHeight: 640)
        }
        .commands {
            CommandGroup(replacing: .newItem) {}
        }
    }
}
```

```swift
import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
    }
}
```

Create `Config/MyShottr.entitlements`:

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict/>
</plist>
```

Create `Config/MyShottr-Info.plist`:

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleDevelopmentRegion</key>
    <string>en</string>
    <key>CFBundleExecutable</key>
    <string>$(EXECUTABLE_NAME)</string>
    <key>CFBundleIdentifier</key>
    <string>$(PRODUCT_BUNDLE_IDENTIFIER)</string>
    <key>CFBundleInfoDictionaryVersion</key>
    <string>6.0</string>
    <key>CFBundleName</key>
    <string>$(PRODUCT_NAME)</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>0.1.0</string>
    <key>CFBundleVersion</key>
    <string>1</string>
    <key>LSMinimumSystemVersion</key>
    <string>$(MACOSX_DEPLOYMENT_TARGET)</string>
    <key>NSHighResolutionCapable</key>
    <true/>
    <key>NSScreenCaptureUsageDescription</key>
    <string>MyShottr captures a screen region that you explicitly select.</string>
    <key>CFBundleDocumentTypes</key>
    <array>
        <dict>
            <key>CFBundleTypeName</key>
            <string>MyShottr Project</string>
            <key>CFBundleTypeExtensions</key>
            <array><string>myshottr</string></array>
            <key>CFBundleTypeRole</key>
            <string>Editor</string>
            <key>LSHandlerRank</key>
            <string>Owner</string>
            <key>LSItemContentTypes</key>
            <array><string>com.myshottr.project</string></array>
        </dict>
    </array>
    <key>UTExportedTypeDeclarations</key>
    <array>
        <dict>
            <key>UTTypeIdentifier</key>
            <string>com.myshottr.project</string>
            <key>UTTypeConformsTo</key>
            <array><string>com.apple.package</string></array>
            <key>UTTypeDescription</key>
            <string>MyShottr Project</string>
            <key>UTTypeTagSpecification</key>
            <dict>
                <key>public.filename-extension</key>
                <array><string>myshottr</string></array>
            </dict>
        </dict>
    </array>
</dict>
</plist>
```

Replace `.gitignore` with:

```gitignore
.superpowers/
.DS_Store
DerivedData/
MyShottr.xcodeproj/
node_modules/
Packages/*/node_modules/
Packages/editor/dist/
Packages/chrome-extension/dist/
```

The built editor and generated Xcode project are reproducible outputs.

- [ ] **Step 4: Generate dependencies and verify the test passes**

Run:

```bash
pnpm install
chmod +x Scripts/build-editor.sh
xcodegen generate
xcodebuild test \
  -project MyShottr.xcodeproj \
  -scheme MyShottr \
  -destination 'platform=macOS' \
  CODE_SIGNING_ALLOWED=NO
```

Expected: pnpm creates `pnpm-lock.yaml`, XcodeGen creates
`MyShottr.xcodeproj`, and XCTest reports `TEST SUCCEEDED`.

- [ ] **Step 5: Commit the reproducible shell**

```bash
git add .gitignore Config Packages Scripts Sources Tests package.json pnpm-workspace.yaml pnpm-lock.yaml project.yml
git commit -m "build: scaffold MyShottr app and editor workspace"
```

### Task 2: Versioned Project Package

**Files:**
- Create: `Sources/MyShottrApp/Documents/ProjectManifest.swift`
- Create: `Sources/MyShottrApp/Documents/MyShottrProject.swift`
- Create: `Sources/MyShottrApp/Documents/ProjectPackageError.swift`
- Create: `Sources/MyShottrApp/Documents/ProjectPackageStore.swift`
- Create: `Sources/MyShottrApp/Documents/PNGMetadata.swift`
- Test: `Tests/MyShottrTests/ProjectPackageStoreTests.swift`
- Test support: `Tests/MyShottrTests/Support/ProjectFixtures.swift`
- Test support: `Tests/MyShottrTests/Support/TemporaryDirectoryTestCase.swift`
- Test fixture: `Tests/Fixtures/source-2x.png`

**Interfaces:**
- Consumes: the Swift interfaces under “Shared Interfaces.”
- Produces: `ProjectPackageStore.load(from:)`, `save(_:to:)`, and `PNGMetadata.read(from:)`.

- [ ] **Step 1: Write package round-trip and rejection tests**

Create tests that construct a 2×2 fixture PNG and assert:

```swift
func testSaveAndLoadRoundTrip() throws {
    let url = temporaryDirectory.appendingPathComponent("Sample.myshottr")
    let project = try ProjectFixtures.sampleProject()

    try ProjectPackageStore().save(project, to: url)
    XCTAssertEqual(try ProjectPackageStore().load(from: url), project)
    XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: url.path).sorted(),
                   ["document.json", "manifest.json", "original.png"])
}

func testRejectsUnsupportedFormatVersion() throws {
    let url = try ProjectFixtures.package(formatVersion: 2)
    XCTAssertThrowsError(try ProjectPackageStore().load(from: url)) {
        XCTAssertEqual($0 as? ProjectPackageError, .unsupportedFormatVersion(2))
    }
}

func testRejectsPNGWhoseDimensionsDoNotMatchManifest() throws {
    let url = try ProjectFixtures.package(sourcePixelWidth: 99)
    XCTAssertThrowsError(try ProjectPackageStore().load(from: url)) {
        XCTAssertEqual($0 as? ProjectPackageError, .sourceDimensionsMismatch)
    }
}
```

- [ ] **Step 2: Run the focused test and confirm failure**

Run:

```bash
xcodebuild test -project MyShottr.xcodeproj -scheme MyShottr \
  -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO \
  -only-testing:MyShottrTests/ProjectPackageStoreTests
```

Expected: compilation fails because `ProjectPackageStore` is undefined.

- [ ] **Step 3: Implement strict package loading and atomic saving**

Implement `ProjectPackageError` with exact cases:

```swift
enum ProjectPackageError: Error, Equatable {
    case notDirectoryPackage
    case invalidMemberSet([String])
    case invalidManifest
    case unsupportedFormatVersion(Int)
    case invalidAnnotationJSON
    case invalidPNG
    case sourceDimensionsMismatch
}
```

`ProjectPackageStore.load(from:)` must:

1. reject symbolic-link package roots;
2. require exactly the three named regular files;
3. decode `manifest.json` using ISO-8601 dates;
4. require `formatVersion == 1`;
5. require `document.json` to be a JSON object with `schemaVersion == 1`;
6. read PNG pixel dimensions with ImageIO;
7. compare PNG dimensions with the manifest.

`save(_:to:)` must write all three members into a sibling temporary directory,
validate that directory through `load(from:)`, then use
`FileManager.replaceItemAt` for an existing destination or `moveItem` for a new
destination. It must remove the temporary directory in `defer`.

`ProjectFixtures` must expose these exact helpers used by this and later plans:

```swift
enum ProjectFixtures {
    static let pngData: Data
    static func sampleProject() throws -> MyShottrProject
    static func project(text: String) -> MyShottrProject
    static func package(
        formatVersion: Int = 1,
        sourcePixelWidth: Int = 2
    ) throws -> URL
}
```

`TemporaryDirectoryTestCase` creates one unique temporary directory in
`setUpWithError()` and deletes only that exact directory in
`tearDownWithError()`.

- [ ] **Step 4: Run focused and complete native tests**

Run:

```bash
xcodebuild test -project MyShottr.xcodeproj -scheme MyShottr \
  -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO
```

Expected: `ProjectPackageStoreTests` and `AppConfigurationTests` pass.

- [ ] **Step 5: Commit the project format**

```bash
git add Sources/MyShottrApp/Documents Tests/MyShottrTests Tests/Fixtures
git commit -m "feat: add versioned MyShottr project packages"
```

### Task 3: Typed Editor Model and Command History

**Files:**
- Create: `Packages/editor/src/model/elements.ts`
- Create: `Packages/editor/src/model/schema.ts`
- Create: `Packages/editor/src/model/defaults.ts`
- Create: `Packages/editor/src/model/reducer.ts`
- Create: `Packages/editor/src/model/history.ts`
- Test: `Packages/editor/src/model/schema.test.ts`
- Test: `Packages/editor/src/model/history.test.ts`
- Test support: `Packages/editor/src/test/fixtures.ts`

**Interfaces:**
- Consumes: the `EditorDocument` and `EditorCommand` shapes under “Shared Interfaces.”
- Produces: `EditorElementSchema`, `EditorDocumentSchema`,
  `createEmptyDocument()`, `findElement()`, `applyCommand()`, and
  `createHistoryStore()`.

- [ ] **Step 1: Write failing schema and history tests**

Add Vitest cases that assert:

```ts
it("rejects an unknown element type", () => {
  const value = fixtureDocument({ elements: [{ ...fixtureRect(), type: "video" }] });
  expect(() => EditorDocumentSchema.parse(value)).toThrow();
});

it("round-trips every supported element", () => {
  const document = fixtureDocument({ elements: allElementFixtures() });
  expect(EditorDocumentSchema.parse(JSON.parse(JSON.stringify(document)))).toEqual(document);
});

it("coalesces a transform drag into one undo entry", () => {
  const history = createHistoryStore(fixtureDocument());
  history.beginTransaction("transform");
  history.dispatch({
    type: "update",
    element: { ...findElement(history.document, "rect-1"), x: 10 },
  });
  history.dispatch({
    type: "update",
    element: { ...findElement(history.document, "rect-1"), x: 20 },
  });
  history.commitTransaction();
  history.undo();
  expect(findElement(history.document, "rect-1").x).toBe(0);
});
```

`src/test/fixtures.ts` exports:

```ts
export function fixtureRect(): RectangleElement;
export function allElementFixtures(): EditorElement[];
export function fixtureDocument(
  overrides?: Partial<EditorDocument>,
): EditorDocument;
export function creationGesture(
  tool: Exclude<EditorTool, "selection">,
): CreationGesture;
```

Every fixture uses stable IDs, unique z-index values, finite bounds, and fixed
rough.js seeds.

- [ ] **Step 2: Run tests and verify they fail**

Run:

```bash
pnpm --filter @myshottr/editor test -- src/model
```

Expected: Vitest fails because the model modules do not exist.

- [ ] **Step 3: Implement the discriminated element union**

Define `ElementBase` with:

```ts
export type Point = { x: number; y: number };
export type PaletteColor = "#000000" | "#FF4D4F" | "#1677FF" | "#FADB14";
export type EditorDefaults = {
  color: PaletteColor;
  strokeWidth: 2 | 4 | 8;
  textSize: 16 | 24 | 36;
  roughness: 0 | 1 | 2;
  opacity: 0.25 | 0.5 | 0.75 | 1;
};

type ElementBase = {
  id: string;
  x: number;
  y: number;
  width: number;
  height: number;
  rotation: number;
  opacity: 0.25 | 0.5 | 0.75 | 1;
  zIndex: number;
  seed: number;
};
```

Export these tool and gesture types from `elements.ts`:

```ts
export type EditorTool =
  | "selection" | "rectangle" | "arrow" | "text"
  | "freehand" | "highlighter" | "redaction" | "numberMarker";

export type CreationGesture =
  | { kind: "box"; start: Point; end: Point }
  | { kind: "path"; points: Point[] }
  | { kind: "point"; point: Point };
```

Define these exact discriminators and properties:

```ts
type RectangleElement = ElementBase & {
  type: "rectangle"; strokeColor: PaletteColor; strokeWidth: 2 | 4 | 8;
  fillColor: PaletteColor | null; roughness: 0 | 1 | 2;
};
type ArrowElement = ElementBase & {
  type: "arrow"; points: [Point, Point]; strokeColor: PaletteColor;
  strokeWidth: 2 | 4 | 8; roughness: 0 | 1 | 2;
};
type TextElement = ElementBase & {
  type: "text"; text: string; color: PaletteColor;
  fontSize: 16 | 24 | 36;
};
type FreehandElement = ElementBase & {
  type: "freehand"; points: Point[]; color: PaletteColor;
  strokeWidth: 2 | 4 | 8;
};
type HighlighterElement = ElementBase & {
  type: "highlighter"; points: Point[]; color: PaletteColor;
  strokeWidth: 8; opacity: 0.25 | 0.5;
};
type RedactionElement = ElementBase & {
  type: "redaction"; color: "#000000"; opacity: 1;
};
type NumberMarkerElement = ElementBase & {
  type: "numberMarker"; number: number; color: PaletteColor;
};

export type EditorElement =
  | RectangleElement
  | ArrowElement
  | TextElement
  | FreehandElement
  | HighlighterElement
  | RedactionElement
  | NumberMarkerElement;
```

Use `z.discriminatedUnion("type", ...)` to validate all seven drawable types;
selection is a tool, not a persisted element. Reject non-finite numbers,
negative sizes, empty freehand point arrays, duplicate IDs, and duplicate
z-index values. An `update` command replaces one complete element and must
reject a missing ID or a replacement whose `type` differs from the existing
element.

Implement immutable `applyCommand` and a history store with
`beginTransaction`, `dispatch`, `commitTransaction`, `undo`, and `redo`.

- [ ] **Step 4: Run model tests and typecheck**

Run:

```bash
pnpm --filter @myshottr/editor test -- src/model
pnpm --filter @myshottr/editor typecheck
```

Expected: both commands exit `0`.

- [ ] **Step 5: Commit the editor model**

```bash
git add Packages/editor/src/model
git commit -m "feat: add typed annotation model and history"
```

### Task 4: Canvas First Editor and Eight Tools

**Files:**
- Modify: `Packages/editor/src/App.tsx`
- Create: `Packages/editor/src/canvas/EditorCanvas.tsx`
- Create: `Packages/editor/src/canvas/CanvasViewport.ts`
- Create: `Packages/editor/src/canvas/SelectionController.ts`
- Create: `Packages/editor/src/canvas/renderElement.tsx`
- Create: `Packages/editor/src/canvas/roughRenderer.ts`
- Create: `Packages/editor/src/canvas/tools/ToolController.ts`
- Create: `Packages/editor/src/canvas/tools/createElement.ts`
- Create: `Packages/editor/src/components/FloatingToolPalette.tsx`
- Create: `Packages/editor/src/components/ContextStylePalette.tsx`
- Create: `Packages/editor/src/components/ZoomControls.tsx`
- Create: `Packages/editor/src/styles.css`
- Test: `Packages/editor/src/canvas/CanvasViewport.test.ts`
- Test: `Packages/editor/src/canvas/tools/createElement.test.ts`
- Test: `Packages/editor/src/App.test.tsx`

**Interfaces:**
- Consumes: `EditorDocument`, `EditorElement`, `EditorCommand`, and the history store.
- Produces: `<EditorApp initialDocument sourceImageURL onChange />`,
  `CanvasViewport`, `createElement()`, and the Canvas First interaction UI.

- [ ] **Step 1: Write failing viewport and tool tests**

Cover exact behavior:

```ts
it("maps pointer coordinates to source pixels at any zoom", () => {
  const viewport = new CanvasViewport({ sourceWidth: 3000, sourceHeight: 2000 });
  viewport.setTransform({ zoom: 0.5, panX: 100, panY: 50 });
  expect(viewport.toSourcePoint({ x: 600, y: 450 })).toEqual({ x: 1000, y: 800 });
});

it.each([
  "rectangle", "arrow", "text", "freehand",
  "highlighter", "redaction", "numberMarker",
] as const)("creates a valid %s element", (tool) => {
  expect(() => EditorElementSchema.parse(createElement(tool, creationGesture(tool)))).not.toThrow();
});
```

Render `<EditorApp>` and assert the floating palette contains eight controls:
selection plus the seven drawable types. Selecting a rectangle must show color,
stroke, fill, roughness, and opacity controls; selecting redaction must not show
an opacity control.

- [ ] **Step 2: Run focused editor tests and verify failure**

Run:

```bash
pnpm --filter @myshottr/editor test -- src/canvas src/App.test.tsx
```

Expected: Vitest fails on missing canvas and component modules.

- [ ] **Step 3: Implement the canvas-first editor**

Use two Konva layers:

1. `sourceLayer` for the immutable source image;
2. `annotationLayer` for highlighters, normal elements, selection outlines, and
   the `Konva.Transformer`.

Render highlighters before every other annotation while preserving their
relative order. Render rough rectangles and arrows by calling
`rough.generator().rectangle(...)` or `rough.generator().linearPath(...)`,
converting the drawable with `generator.toPaths()`, and rendering every result
as a Konva `Path`. Do not access Konva's private canvas context.

Implement creation through one typed function:

```ts
export function createElement(
  tool: Exclude<EditorTool, "selection">,
  gesture: CreationGesture,
  context: {
    defaults: EditorDefaults;
    nextNumberMarker: number;
    nextZIndex: number;
    seed: number;
  },
): EditorElement;
```

`numberMarker` uses `nextNumberMarker`; every other tool ignores it. The caller
derives the next marker as one greater than the largest existing marker number
and derives z-index as one greater than the current largest z-index.

Implement these keyboard commands:

```ts
const shortcuts = {
  select: "v",
  rectangle: "r",
  arrow: "a",
  text: "t",
  freehand: "p",
  highlighter: "h",
  redaction: "x",
  numberMarker: "n",
  delete: ["Backspace", "Delete"],
  duplicate: "Meta+d",
  undo: "Meta+z",
  redo: ["Meta+Shift+z", "Meta+y"],
};
```

Pointer transforms must update only through `EditorCommand`. Clamp movement so
at least one source pixel of each element remains inside the source bounds.
Begin a history transaction on pointer-down and commit it on pointer-up.

- [ ] **Step 4: Verify editor behavior and production build**

Run:

```bash
pnpm --filter @myshottr/editor test
pnpm --filter @myshottr/editor typecheck
pnpm --filter @myshottr/editor build
```

Expected: all tests pass, typecheck exits `0`, and Vite creates
`Packages/editor/dist/index.html` plus hashed assets.

- [ ] **Step 5: Commit the editor UI**

```bash
git add Packages/editor
git commit -m "feat: add canvas-first annotation editor"
```

### Task 5: Versioned Native-Web Bridge

**Files:**
- Create: `Sources/MyShottrApp/Editor/BridgeJSONValue.swift`
- Create: `Sources/MyShottrApp/Editor/EditorBridgeEnvelope.swift`
- Create: `Sources/MyShottrApp/Editor/EditorBridge.swift`
- Create: `Sources/MyShottrApp/Editor/EditorResourceSchemeHandler.swift`
- Create: `Sources/MyShottrApp/Editor/EditorWebView.swift`
- Create: `Sources/MyShottrApp/Documents/DocumentSession.swift`
- Create: `Packages/editor/src/bridge/protocol.ts`
- Create: `Packages/editor/src/bridge/nativeBridge.ts`
- Test: `Tests/MyShottrTests/EditorBridgeEnvelopeTests.swift`
- Test: `Tests/MyShottrTests/EditorResourceSchemeHandlerTests.swift`
- Test: `Packages/editor/src/bridge/protocol.test.ts`

**Interfaces:**
- Consumes: `MyShottrProject` and `<EditorApp>`.
- Produces: `EditorBridge.load(project:)`,
  `EditorBridge.requestAnnotationSnapshot() async throws -> Data`, and
  identical protocol version `1` envelopes in Swift and TypeScript.

- [ ] **Step 1: Write cross-language envelope tests**

Swift must decode this fixture:

```json
{
  "protocolVersion": 1,
  "requestId": "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE",
  "type": "editorReady",
  "payload": {}
}
```

and reject protocol version `2`, unknown types, missing request IDs, and payloads
larger than 8 MiB. TypeScript must accept the same fixture and reject the same
mutations through Zod.

`EditorResourceSchemeHandlerTests` must assert that
`myshottr-resource://document/<document-id>/original.png` returns only the
active session's PNG with `Content-Type: image/png`; unknown IDs, extra path
segments, non-GET requests, and path traversal return an error without reading
a filesystem path.

Add a bridge integration test that loads annotation JSON containing an unknown
element type and another whose source dimensions differ from the manifest. In
both cases the editor sends `bridgeError` with code `INVALID_DOCUMENT`, the
native session does not mark the document open, and no partial element array is
installed.

- [ ] **Step 2: Run both test suites and verify failure**

Run:

```bash
pnpm --filter @myshottr/editor test -- src/bridge
xcodebuild test -project MyShottr.xcodeproj -scheme MyShottr \
  -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO \
  -only-testing:MyShottrTests/EditorBridgeEnvelopeTests
```

Expected: both suites fail because the bridge types are missing.

- [ ] **Step 3: Implement the bridge and document session**

Use the exact message types from the design:

```swift
enum NativeToEditorMessageType: String, Codable {
    case loadDocument, saveCompleted, saveFailed, requestComposite, setAppearance
}

enum EditorToNativeMessageType: String, Codable {
    case editorReady, documentChanged, annotationSnapshot
    case compositeChunk, compositeCompleted, bridgeError
}
```

`EditorWebView` must:

- register `EditorResourceSchemeHandler` for `myshottr-resource` before
  constructing `WKWebView`;
- load `Resources/Editor/index.html` using
  `loadFileURL(_:allowingReadAccessTo:)`;
- disable navigation away from the bundled editor;
- register exactly one script handler named `myshottr`;
- remove the handler during teardown;
- send `loadDocument` only after `editorReady`;
- mark `DocumentSession.isModified` on `documentChanged`;
- update `annotationJSON` only after a validated `annotationSnapshot`.

`EditorResourceSchemeHandler` receives PNG bytes from the active
`DocumentSession` through an injected `@MainActor (UUID) -> Data?` closure. It
does not accept file URLs. `loadDocument` sends:

```json
{
  "documentId": "<uuid>",
  "sourceImageURL": "myshottr-resource://document/<uuid>/original.png",
  "annotationDocument": {}
}
```

so the source PNG never enters the JSON bridge size limit.

TypeScript must expose:

```ts
type Envelope<T extends string, P> = {
  protocolVersion: 1;
  requestId: string;
  type: T;
  payload: P;
};

type EditorToNativePayloads = {
  editorReady: {};
  documentChanged: {};
  annotationSnapshot: { document: EditorDocument };
  compositeChunk: {
    requestId: string;
    index: number;
    total: number;
    dataBase64: string;
  };
  compositeCompleted: { requestId: string };
  bridgeError: {
    code: "INVALID_DOCUMENT" | "INVALID_MESSAGE" | "RENDER_FAILED";
    message: string;
  };
};

type NativeToEditorEnvelope =
  | Envelope<"loadDocument", {
      documentId: string;
      sourceImageURL: string;
      annotationDocument: EditorDocument;
    }>
  | Envelope<"saveCompleted", { requestId: string }>
  | Envelope<"saveFailed", { requestId: string; message: string }>
  | Envelope<"requestComposite", { requestId: string }>
  | Envelope<"setAppearance", { colorScheme: "light" | "dark" }>;

type EditorToNativeType = keyof EditorToNativePayloads;
type PayloadFor<T extends EditorToNativeType> = EditorToNativePayloads[T];

type NativeBridge = {
  send<T extends EditorToNativeType>(type: T, payload: PayloadFor<T>): Promise<void>;
  subscribe(handler: (message: NativeToEditorEnvelope) => void): () => void;
};
```

Use `window.webkit.messageHandlers.myshottr.postMessage` only inside
`nativeBridge.ts`; components receive the `NativeBridge` through React context.

- [ ] **Step 4: Verify bridge tests and app build**

Run:

```bash
pnpm test
xcodebuild test -project MyShottr.xcodeproj -scheme MyShottr \
  -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO
```

Expected: all Swift and TypeScript tests pass.

- [ ] **Step 5: Commit the bridge**

```bash
git add Sources/MyShottrApp/Editor Sources/MyShottrApp/Documents/DocumentSession.swift Packages/editor/src/bridge
git commit -m "feat: connect native documents to the web editor"
```

### Task 6: Composite Transfer, Clipboard, Save, and Export

**Files:**
- Create: `Packages/editor/src/export/renderDocumentToBlob.ts`
- Create: `Packages/editor/src/export/sendComposite.ts`
- Create: `Sources/MyShottrApp/Export/CompositeTransfer.swift`
- Create: `Sources/MyShottrApp/Export/PNGClipboardWriter.swift`
- Create: `Sources/MyShottrApp/Documents/DocumentWindowController.swift`
- Modify: `Sources/MyShottrApp/App/MyShottrApp.swift`
- Test: `Packages/editor/src/export/renderDocumentToBlob.test.ts`
- Test: `Tests/MyShottrTests/CompositeTransferTests.swift`
- Test: `Tests/MyShottrTests/PNGClipboardWriterTests.swift`

**Interfaces:**
- Consumes: `EditorBridge`, `DocumentSession`, and `ProjectPackageStoring`.
- Produces: `CompositeTransfer.begin(requestId:)`, `append(chunk:)`, `finish()`, `PNGClipboardWriter.write(data:)`, and native Copy/Save/Export commands.

- [ ] **Step 1: Write failing composite and clipboard tests**

TypeScript must verify that a 3000×2000 document exports a 3000×2000 PNG even
when viewport zoom is `0.25`. Swift must verify:

```swift
func testRejectsOutOfOrderCompositeChunk() throws {
    let transfer = try CompositeTransfer(requestId: UUID(), expectedChunks: 2)
    XCTAssertThrowsError(try transfer.append(index: 1, base64: "AA==")) {
        XCTAssertEqual($0 as? CompositeTransferError, .unexpectedChunk(expected: 0, received: 1))
    }
}

func testClipboardContainsPNG() throws {
    let pasteboard = NSPasteboard(name: .init("MyShottrTests"))
    try PNGClipboardWriter(pasteboard: pasteboard).write(data: ProjectFixtures.pngData)
    XCTAssertEqual(pasteboard.data(forType: .png), ProjectFixtures.pngData)
}
```

- [ ] **Step 2: Run focused tests and verify failure**

Run:

```bash
pnpm --filter @myshottr/editor test -- src/export
xcodebuild test -project MyShottr.xcodeproj -scheme MyShottr \
  -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO \
  -only-testing:MyShottrTests/CompositeTransferTests \
  -only-testing:MyShottrTests/PNGClipboardWriterTests
```

Expected: missing-module or missing-type failures.

- [ ] **Step 3: Implement source-resolution output**

`renderDocumentToBlob` must create an offscreen canvas whose width and height
equal `sourcePixelWidth` and `sourcePixelHeight`, draw the original PNG, draw
elements in z-order with highlighters first, and call
`canvas.toBlob(..., "image/png")`.

`sendComposite` must split base64 into 512 KiB strings and send:

```ts
{ type: "compositeChunk", payload: { requestId, index, total, dataBase64 } }
```

followed by `compositeCompleted`. Swift writes decoded chunks to an owner-only
temporary file, verifies PNG magic bytes and ImageIO dimensions, and atomically
moves the file only for Export. Copy writes `.png` data to `NSPasteboard`.

`DocumentWindowController` must:

- show Copy, Save, and Export title-bar actions;
- ask the editor for `annotationSnapshot` before Save;
- ask the editor for a composite before Copy or Export;
- use `NSSavePanel` for first project Save and PNG Export;
- use `ProjectPackageStore` for `.myshottr`;
- keep the document modified after any failed operation;
- prompt Save, Discard, or Cancel before closing a modified document.

- [ ] **Step 4: Run the full foundation gate**

Run:

```bash
pnpm test
pnpm typecheck
pnpm build
xcodegen generate
xcodebuild test -project MyShottr.xcodeproj -scheme MyShottr \
  -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO
xcodebuild build -project MyShottr.xcodeproj -scheme MyShottr \
  -configuration Debug -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO
```

Expected: every command exits `0`; the Debug app contains
`Contents/Resources/Editor/index.html`.

- [ ] **Step 5: Manually verify the independent increment**

Open a generated `.myshottr` fixture, create one of every annotation, undo and
redo a transform, save, close, reopen, copy, and export. Expected:

- all elements and styles reopen unchanged;
- clipboard and exported images have the fixture's pixel dimensions;
- the app performs no network request.

- [ ] **Step 6: Commit the foundation increment**

```bash
git add Packages/editor Sources/MyShottrApp Tests/MyShottrTests
git commit -m "feat: save copy and export annotated projects"
```

## Plan 1 Completion Gate

The increment is complete only after all commands in Task 6 Step 4 pass and the
manual fixture workflow in Task 6 Step 5 succeeds. Native screen capture and
Chrome capture are intentionally absent; they enter through the stable
`MyShottrProject` and `DocumentSession` interfaces in the next plans.
