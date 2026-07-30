# MyShottr Public Editor and Branding Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Upgrade the completed foundation editor to the approved public-v1 document contract, annotation set, Quick Ink interface, remembered preferences, keyboard workflow, and production macOS icon.

**Architecture:** Keep the immutable source PNG, editable annotation scene, and native document package as separate boundaries. Migrate pre-release annotation JSON to schema version 2 with an explicit `presentation: { type: "none" }`, add line and source-only blur annotations, and persist editor preferences through the validated Swift-WebKit bridge. Brand assets and interface polish remain local app resources.

**Tech Stack:** TypeScript 5.9, React 19, Konva 10, rough.js, Zod 4, Vitest, Swift 6, AppKit, WebKit, XCTest, XcodeGen

## Global Constraints

- Execute this plan from the existing `worktree/myshottr-v1` baseline after the foundation/editor plan and before native capture.
- Minimum supported macOS version is exactly macOS 15.
- The editor bundle remains local-only under `myshottr-editor://editor`; do not add a CDN, remote font, analytics, or network dependency.
- `v0.1.0` presentation support is exactly `{ "type": "none" }`; do not implement a mockup UI.
- Full-page browser capture remains out of scope; the editor must accept arbitrary valid source dimensions.
- Keep opaque redaction because blur is not secure redaction.
- Existing format-1 pre-release projects migrate deterministically; unsupported newer versions fail explicitly.
- Blur reads source pixels only, renders below vector annotations, and never mutates `original.png`.
- Blur regions are axis-aligned, movable, and resizable in v1; the
  blur-specific public design overrides the older common rotation rule.
- Quick Ink uses coral, cream, and black; screenshot pixels remain unfiltered outside explicit blur regions.
- Use TDD and commit after every task.

---

## Repository Map for This Plan

```text
Assets/
├── AppIcon/
│   └── QuickInk-1024.png
└── StatusBar/
    └── QuickInkStatus.svg
Packages/editor/src/
├── bridge/
├── canvas/
│   ├── blurSource.ts
│   └── tools/
├── components/
│   ├── ToolIcon.tsx
│   └── VisuallyHidden.tsx
└── model/
Sources/MyShottrApp/
├── App/
├── Capture/
│   └── CaptureArtifact.swift
├── Documents/
│   ├── EditorDocumentMigrator.swift
│   └── NewProjectFactory.swift
├── Editor/
└── Preferences/
    └── EditorPreferencesStore.swift
Resources/Assets.xcassets/
├── AppIcon.appiconset/
└── StatusBarIcon.imageset/
Scripts/
└── generate-app-iconset.sh
```

## Shared Interfaces

TypeScript:

```ts
export type Presentation = { type: "none" };

export type LineElement = ElementBase & {
  type: "line";
  points: [Point, Point];
  strokeColor: PaletteColor;
  strokeWidth: 2 | 4 | 8;
  roughness: 0 | 1 | 2;
};

export type BlurElement = ElementBase & {
  type: "blur";
  radius: 12;
};

export type EditorDocument = {
  schemaVersion: 2;
  sourcePixelWidth: number;
  sourcePixelHeight: number;
  elements: EditorElement[];
  presentation: Presentation;
  defaults: EditorDefaults;
};
```

Swift:

```swift
struct CaptureArtifact: Equatable, Sendable {
    let id: UUID
    let sourceKind: CaptureSourceKind
    let pngData: Data
    let pixelWidth: Int
    let pixelHeight: Int
    let scale: Double?

    init(
        id: UUID,
        sourceKind: CaptureSourceKind,
        pngData: Data,
        scale: Double?
    ) throws
}

struct EditorPreferences: Codable, Equatable, Sendable {
    var tool: String
    var color: String
    var strokeWidth: Int
    var textSize: Int
    var roughness: Int
    var opacity: Double
}

protocol EditorPreferencesStoring: Sendable {
    func load() -> EditorPreferences
    func save(_ preferences: EditorPreferences) throws
}

struct NewProjectFactory {
    func make(
        artifact: CaptureArtifact,
        now: Date = .now
    ) throws -> MyShottrProject
}

protocol NewProjectCreating: Sendable {
    func make(
        artifact: CaptureArtifact,
        now: Date
    ) throws -> MyShottrProject
}
```

### Task 1: Schema Version 2 and Presentation Boundary

**Files:**
- Modify: `Packages/editor/src/model/elements.ts`
- Modify: `Packages/editor/src/model/schema.ts`
- Modify: `Packages/editor/src/model/defaults.ts`
- Modify: `Packages/editor/src/model/schema.test.ts`
- Modify: `Packages/editor/src/test/fixtures.ts`
- Create: `Sources/MyShottrApp/Documents/EditorDocumentMigrator.swift`
- Modify: `Sources/MyShottrApp/Documents/ProjectPackageStore.swift`
- Modify: `Sources/MyShottrApp/Documents/DocumentSession.swift`
- Modify: `Sources/MyShottrApp/Editor/EditorBridgeEnvelope.swift`
- Test: `Tests/MyShottrTests/Documents/EditorDocumentMigratorTests.swift`
- Modify test support: `Tests/MyShottrTests/Support/ProjectFixtures.swift`

**Interfaces:**
- Consumes: pre-release schema-version-1 annotation JSON and the existing format-1 `.myshottr` package.
- Produces: `EditorDocument` schema version `2`, `Presentation`, `parseEditorDocument(_:)`, and `EditorDocumentMigrator.migrate(_:)`.

- [ ] **Step 1: Write failing TypeScript migration tests**

Add tests with complete legacy and current documents:

```ts
it("migrates a schema-1 document to presentation none", () => {
  const legacy = {
    ...fixtureDocument(),
    schemaVersion: 1,
  };
  delete (legacy as Record<string, unknown>).presentation;

  expect(parseEditorDocument(legacy)).toMatchObject({
    schemaVersion: 2,
    presentation: { type: "none" },
  });
});

it("rejects an unsupported newer document", () => {
  expect(() => parseEditorDocument({
    ...fixtureDocument(),
    schemaVersion: 3,
  })).toThrow();
});

it("requires presentation none in schema 2", () => {
  expect(() => EditorDocumentSchema.parse({
    ...fixtureDocument(),
    presentation: { type: "desktopMockup" },
  })).toThrow();
});
```

- [ ] **Step 2: Write failing Swift migration tests**

Create `EditorDocumentMigratorTests.swift`:

```swift
func testMigratesSchemaOneToSchemaTwoWithPresentationNone() throws {
    let legacy = try JSONSerialization.data(withJSONObject: [
        "schemaVersion": 1,
        "sourcePixelWidth": 2,
        "sourcePixelHeight": 2,
        "elements": [],
        "defaults": ProjectFixtures.editorDefaults,
    ])

    let migrated = try EditorDocumentMigrator.migrate(legacy)
    let object = try XCTUnwrap(
        JSONSerialization.jsonObject(with: migrated) as? [String: Any]
    )

    XCTAssertEqual(object["schemaVersion"] as? Int, 2)
    XCTAssertEqual(
        (object["presentation"] as? [String: Any])?["type"] as? String,
        "none"
    )
}

func testRejectsSchemaThreeWithoutChangingInput() throws {
    let newer = try ProjectFixtures.annotationJSON(schemaVersion: 3)
    XCTAssertThrowsError(try EditorDocumentMigrator.migrate(newer)) {
        XCTAssertEqual($0 as? EditorDocumentMigrationError, .unsupportedVersion(3))
    }
}
```

Add this fixture helper:

```swift
static func annotationJSON(schemaVersion: Int) throws -> Data {
    try JSONSerialization.data(withJSONObject: [
        "schemaVersion": schemaVersion,
        "sourcePixelWidth": 2,
        "sourcePixelHeight": 2,
        "elements": [],
        "defaults": editorDefaults,
    ])
}
```

Also update `ProjectPackageStoreTests` to prove `load(from:)` returns migrated
schema-2 JSON and `save(_:to:)` writes only schema 2.

- [ ] **Step 3: Run focused tests and verify failure**

Run:

```bash
pnpm --filter @myshottr/editor test -- schema.test.ts
xcodegen generate
xcodebuild test -project MyShottr.xcodeproj -scheme MyShottr \
  -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO \
  -only-testing:MyShottrTests/EditorDocumentMigratorTests \
  -only-testing:MyShottrTests/ProjectPackageStoreTests
```

Expected: TypeScript reports missing `parseEditorDocument` and Swift reports a
missing `EditorDocumentMigrator`.

- [ ] **Step 4: Implement the TypeScript v2 model**

Add:

```ts
export type Presentation = { type: "none" };

export type EditorDocument = {
  schemaVersion: 2;
  sourcePixelWidth: number;
  sourcePixelHeight: number;
  elements: EditorElement[];
  presentation: Presentation;
  defaults: EditorDefaults;
};
```

In `schema.ts`, retain the existing element union and define:

```ts
const PresentationSchema = z.object({
  type: z.literal("none"),
}).strict();

const documentBody = {
  sourcePixelWidth: FiniteNumberSchema.positive(),
  sourcePixelHeight: FiniteNumberSchema.positive(),
  elements: z.array(EditorElementSchema),
  defaults: EditorDefaultsSchema,
};

const LegacyEditorDocumentSchema = z.object({
  schemaVersion: z.literal(1),
  ...documentBody,
}).strict();

export const EditorDocumentSchema = z.object({
  schemaVersion: z.literal(2),
  ...documentBody,
  presentation: PresentationSchema,
}).strict().superRefine(validateUniqueElementIdentity);

export function parseEditorDocument(input: unknown): EditorDocument {
  const current = EditorDocumentSchema.safeParse(input);
  if (current.success) return current.data;

  const legacy = LegacyEditorDocumentSchema.safeParse(input);
  if (!legacy.success) throw current.error;
  return EditorDocumentSchema.parse({
    ...legacy.data,
    schemaVersion: 2,
    presentation: { type: "none" },
  });
}
```

Move the existing duplicate-ID and duplicate-z-index callback into
`validateUniqueElementIdentity` and apply it to the current schema. Update
`createEmptyDocument()` and all fixtures to write:

```ts
{
  schemaVersion: 2,
  presentation: { type: "none" },
}
```

- [ ] **Step 5: Implement native migration and strict v2 validation**

Create:

```swift
enum EditorDocumentMigrationError: Error, Equatable {
    case malformedDocument
    case unsupportedVersion(Int)
}

enum EditorDocumentMigrator {
    static func migrate(_ data: Data) throws -> Data {
        guard var object = try JSONSerialization.jsonObject(with: data)
                as? [String: Any],
              let version = object["schemaVersion"] as? Int
        else {
            throw EditorDocumentMigrationError.malformedDocument
        }

        switch version {
        case 1:
            object["schemaVersion"] = 2
            object["presentation"] = ["type": "none"]
        case 2:
            break
        default:
            throw EditorDocumentMigrationError.unsupportedVersion(version)
        }
        return try JSONSerialization.data(
            withJSONObject: object,
            options: [.sortedKeys]
        )
    }
}
```

Call `EditorDocumentMigrator.migrate` before
`ProjectPackageStore.validateAnnotationJSON` returns a loaded project.
`DocumentSession.validate` must require the exact top-level keys:

```swift
[
    "schemaVersion", "sourcePixelWidth", "sourcePixelHeight",
    "elements", "presentation", "defaults",
]
```

Require schema version `2` and `presentation == ["type": "none"]`. Update
`EditorBridgeEnvelope` annotation-snapshot validation to the same exact keys.
Do not accept schema 1 at those downstream boundaries; migration happens once
at package load.

- [ ] **Step 6: Run the schema and native package gates**

Run:

```bash
pnpm --filter @myshottr/editor test -- schema.test.ts
pnpm --filter @myshottr/editor typecheck
xcodebuild test -project MyShottr.xcodeproj -scheme MyShottr \
  -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO
```

Expected: all editor schema and native tests pass.

- [ ] **Step 7: Commit the presentation boundary**

```bash
git add Packages/editor/src/model Packages/editor/src/test \
  Sources/MyShottrApp/Documents Sources/MyShottrApp/Editor/EditorBridgeEnvelope.swift \
  Tests/MyShottrTests
git commit -m "feat: add versioned presentation boundary"
```

### Task 2: Remembered Editor Preferences and New Project Factory

**Files:**
- Create: `Sources/MyShottrApp/Preferences/EditorPreferencesStore.swift`
- Create: `Sources/MyShottrApp/Capture/CaptureArtifact.swift`
- Create: `Sources/MyShottrApp/Documents/NewProjectFactory.swift`
- Modify: `Sources/MyShottrApp/Documents/PNGMetadata.swift`
- Modify: `Sources/MyShottrApp/Documents/ProjectManifest.swift`
- Modify: `Sources/MyShottrApp/Editor/EditorBridge.swift`
- Modify: `Sources/MyShottrApp/Editor/EditorBridgeEnvelope.swift`
- Modify: `Sources/MyShottrApp/Editor/EditorWebView.swift`
- Modify: `Sources/MyShottrApp/Documents/DocumentWindowController.swift`
- Modify: `Packages/editor/src/bridge/protocol.ts`
- Modify: `Packages/editor/src/App.tsx`
- Test: `Tests/MyShottrTests/Preferences/EditorPreferencesStoreTests.swift`
- Test: `Tests/MyShottrTests/Capture/CaptureArtifactTests.swift`
- Test: `Tests/MyShottrTests/Documents/NewProjectFactoryTests.swift`
- Test support: `Tests/MyShottrTests/Support/EditorPreferencesFakes.swift`
- Modify: `Tests/MyShottrTests/EditorBridgeEnvelopeTests.swift`
- Modify: `Packages/editor/src/bridge/protocol.test.ts`
- Modify: `Packages/editor/src/App.test.tsx`

**Interfaces:**
- Consumes: validated editor defaults, selected tool, PNG data, and `CaptureSourceKind`.
- Produces: `CaptureArtifact`, `EditorPreferencesStoring`, `UserDefaultsEditorPreferencesStore`, `NewProjectCreating`, `NewProjectFactory.make`, and `editorPreferencesChanged` bridge messages.

- [ ] **Step 1: Write failing preference and factory tests**

Add:

```swift
func testInvalidStoredPreferencesReturnApprovedDefaults() {
    defaults.set(Data("not-json".utf8), forKey: EditorPreferences.storageKey)
    XCTAssertEqual(store.load(), .approvedDefaults)
}

func testFactoryUsesStoredPreferencesAndPresentationNone() throws {
    let preferences = EditorPreferences(
        tool: "arrow",
        color: "#FF4D4F",
        strokeWidth: 8,
        textSize: 36,
        roughness: 2,
        opacity: 0.75
    )
    let factory = NewProjectFactory(preferences: StubPreferences(preferences))
    let artifact = try CaptureArtifact(
        id: ProjectFixtures.documentID,
        sourceKind: .screenRegion,
        pngData: ProjectFixtures.pngData,
        scale: 2
    )
    let project = try factory.make(
        artifact: artifact,
        now: Date(timeIntervalSince1970: 100)
    )
    let document = try XCTUnwrap(
        JSONSerialization.jsonObject(with: project.annotationJSON)
            as? [String: Any]
    )

    XCTAssertEqual(document["schemaVersion"] as? Int, 2)
    XCTAssertEqual((document["elements"] as? [Any])?.count, 0)
    XCTAssertEqual(
        (document["presentation"] as? [String: Any])?["type"] as? String,
        "none"
    )
    XCTAssertEqual(
        (document["defaults"] as? [String: Any])?["color"] as? String,
        "#FF4D4F"
    )
}
```

Add:

```swift
func testArtifactDerivesPixelDimensionsWithoutSourceSpecificLogic() throws {
    let artifact = try CaptureArtifact(
        id: ProjectFixtures.documentID,
        sourceKind: .chromeVisibleViewport,
        pngData: ProjectFixtures.pngData,
        scale: nil
    )
    XCTAssertEqual(artifact.pixelWidth, 2)
    XCTAssertEqual(artifact.pixelHeight, 2)
    XCTAssertNil(artifact.scale)
}
```

Add protocol tests that accept only:

```ts
{
  type: "editorPreferencesChanged",
  payload: {
    tool: "arrow",
    defaults: fixtureDocument().defaults,
  },
}
```

and reject unknown tools, colors, widths, sizes, roughness, opacity, or extra
keys.

Create shared test support:

```swift
struct StubPreferences: EditorPreferencesStoring {
    let value: EditorPreferences

    init(_ value: EditorPreferences) {
        self.value = value
    }

    func load() -> EditorPreferences { value }
    func save(_ preferences: EditorPreferences) throws {}
}
```

- [ ] **Step 2: Run focused tests and verify failure**

Run:

```bash
pnpm --filter @myshottr/editor test -- protocol.test.ts App.test.tsx
xcodebuild test -project MyShottr.xcodeproj -scheme MyShottr \
  -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO \
  -only-testing:MyShottrTests/EditorPreferencesStoreTests \
  -only-testing:MyShottrTests/NewProjectFactoryTests \
  -only-testing:MyShottrTests/EditorBridgeEnvelopeTests
```

Expected: missing preferences, factory, and bridge-message failures.

- [ ] **Step 3: Implement validated native preferences**

Use:

```swift
struct EditorPreferences: Codable, Equatable, Sendable {
    static let storageKey = "editorPreferences.v1"
    static let approvedDefaults = EditorPreferences(
        tool: "selection",
        color: "#1677FF",
        strokeWidth: 4,
        textSize: 24,
        roughness: 1,
        opacity: 1
    )

    var tool: String
    var color: String
    var strokeWidth: Int
    var textSize: Int
    var roughness: Int
    var opacity: Double

    var isValid: Bool {
        ["selection", "rectangle", "arrow", "text", "freehand",
         "highlighter", "redaction", "numberMarker"].contains(tool)
        && ["#000000", "#FF4D4F", "#1677FF", "#FADB14"].contains(color)
        && [2, 4, 8].contains(strokeWidth)
        && [16, 24, 36].contains(textSize)
        && [0, 1, 2].contains(roughness)
        && [0.25, 0.5, 0.75, 1].contains(opacity)
    }
}
```

`UserDefaultsEditorPreferencesStore` decodes only a valid value, returns
`.approvedDefaults` for absent or invalid storage, and refuses to save an
invalid value.

Add `PNGMetadata.read(from data: Data)` using
`CGImageSourceCreateWithData`. Make the URL overload delegate to the data
overload.

`NewProjectFactory.make` reads PNG dimensions and constructs the existing
format-1 manifest from `artifact.id`, `artifact.sourceKind`,
`artifact.pixelWidth`, and `artifact.pixelHeight`, plus this exact annotation
object:

```swift
[
    "schemaVersion": 2,
    "sourcePixelWidth": metadata.pixelWidth,
    "sourcePixelHeight": metadata.pixelHeight,
    "elements": [],
    "presentation": ["type": "none"],
    "defaults": [
        "color": preferences.color,
        "strokeWidth": preferences.strokeWidth,
        "textSize": preferences.textSize,
        "roughness": preferences.roughness,
        "opacity": preferences.opacity,
    ],
]
```

`CaptureArtifact.init` validates PNG data through `PNGMetadata.read(from:)` and
stores the derived dimensions. Make `NewProjectFactory` conform to
`NewProjectCreating`; the artifact owns identity, source kind, dimensions, PNG
bytes, and optional display scale, while the factory owns document defaults
and serialization.

Add `var sourceScale: Double? = nil` to `ProjectManifest` and write
`artifact.scale`. The optional field decodes older pre-release manifests that
do not contain it. Native screen captures persist their display scale; Chrome
viewport captures persist `nil`. Do not persist browser URL, title, or history.

- [ ] **Step 4: Add the preference bridge**

Add `editorPreferencesChanged` to both protocol enums. The TypeScript payload
schema is:

```ts
const EditorPreferencesChangedPayloadSchema = z.object({
  tool: z.enum([
    "selection", "rectangle", "arrow", "text", "freehand",
    "highlighter", "redaction", "numberMarker",
  ]),
  defaults: EditorDefaultsSchema,
}).strict();
```

Expose `EditorDefaultsSchema` from `model/schema.ts`.
Extend `EditorAppProps`:

```ts
export type EditorAppProps = {
  initialDocument: EditorDocument;
  initialTool: EditorTool;
  sourceImageURL: string;
  onChange: (document: EditorDocument) => void;
  onPreferencesChange: (
    tool: EditorTool,
    defaults: EditorDefaults,
  ) => void;
};
```

Pass the initial tool into `EditorApp` through `loadDocument`:

```ts
initialTool: z.enum([
  "selection", "rectangle", "arrow", "text", "freehand",
  "highlighter", "redaction", "numberMarker",
])
```

After `selectTool` and `setDefaults`, `EditorApp` invokes
`onPreferencesChange(tool, defaults)`. The outer `App`, which owns the native
bridge, supplies:

```ts
onPreferencesChange={(tool, defaults) => {
  void bridge.send("editorPreferencesChanged", { tool, defaults });
}}
```

`EditorBridge` receives a validated payload, saves it through
`EditorPreferencesStoring`, and never marks the document modified solely
because a global preference changed. `sendLoadDocument` reads the current
preference and includes `initialTool`. Inject the store through
`EditorWebView` and `DocumentWindowController`.

- [ ] **Step 5: Run preference and factory tests**

Run:

```bash
pnpm --filter @myshottr/editor test -- protocol.test.ts App.test.tsx
pnpm --filter @myshottr/editor typecheck
xcodebuild test -project MyShottr.xcodeproj -scheme MyShottr \
  -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO
```

Expected: all tests pass and a new project is valid schema 2.

- [ ] **Step 6: Commit preferences and project creation**

```bash
git add Packages/editor/src Sources/MyShottrApp/Preferences \
  Sources/MyShottrApp/Documents Sources/MyShottrApp/Editor \
  Tests/MyShottrTests
git commit -m "feat: remember editor preferences for new captures"
```

### Task 3: Line Annotation

**Files:**
- Modify: `Packages/editor/src/model/elements.ts`
- Modify: `Packages/editor/src/model/schema.ts`
- Modify: `Packages/editor/src/test/fixtures.ts`
- Modify: `Packages/editor/src/canvas/tools/createElement.ts`
- Modify: `Packages/editor/src/canvas/tools/createElement.test.ts`
- Modify: `Packages/editor/src/canvas/tools/ToolController.ts`
- Modify: `Packages/editor/src/canvas/roughRenderer.ts`
- Modify: `Packages/editor/src/canvas/renderElement.tsx`
- Modify: `Packages/editor/src/canvas/SelectionController.ts`
- Modify: `Packages/editor/src/canvas/EditorCanvas.tsx`
- Modify: `Packages/editor/src/export/renderDocumentToBlob.ts`
- Modify: `Packages/editor/src/export/renderDocumentToBlob.test.ts`
- Modify: `Packages/editor/src/components/FloatingToolPalette.tsx`
- Modify: `Packages/editor/src/components/ContextStylePalette.tsx`
- Modify: `Sources/MyShottrApp/Documents/DocumentSession.swift`

**Interfaces:**
- Consumes: `CreationGesture.kind = "box"`, stable rough seeds, and existing arrow transform behavior.
- Produces: `LineElement`, the `line` tool, `L` shortcut, preview rendering, export rendering, and native schema acceptance.

- [ ] **Step 1: Write failing line model and rendering tests**

Add:

```ts
it("creates a two-point rough line from a box gesture", () => {
  const line = createElement("line", {
    kind: "box",
    start: { x: 10, y: 20 },
    end: { x: 90, y: 60 },
  }, creationContext());

  expect(line).toMatchObject({
    type: "line",
    x: 10,
    y: 20,
    width: 80,
    height: 40,
    points: [{ x: 10, y: 20 }, { x: 90, y: 60 }],
  });
});

it("maps L to line without modifiers", () => {
  expect(keyboardCommandFor(new KeyboardEvent("keydown", { key: "l" })))
    .toBe("line");
});

it("exports line with its stored rough seed", async () => {
  await renderDocumentToBlob(fixtureDocument({ elements: [fixtureLine()] }), "source.png");
  expect(path2D).toHaveBeenCalledWith(
    expect.stringMatching(/\S+/),
  );
});
```

Update the all-tools tests to include `line`.

- [ ] **Step 2: Run focused tests and verify failure**

Run:

```bash
pnpm --filter @myshottr/editor test -- \
  createElement.test.ts renderDocumentToBlob.test.ts
```

Expected: the `line` discriminant is rejected or unhandled.

- [ ] **Step 3: Implement line creation, transforms, and rendering**

Add `LineElement` from Shared Interfaces to the union and `EditorTool`.
Its Zod schema is:

```ts
const LineElementSchema = ElementBaseSchema.extend({
  type: z.literal("line"),
  points: z.tuple([PointSchema, PointSchema]),
  strokeColor: PaletteColorSchema,
  strokeWidth: StrokeWidthSchema,
  roughness: RoughnessSchema,
}).strict();
```

Handle `line` everywhere `arrow` uses a box gesture, endpoint transform, and
rough linear path. Extend the TypeScript and Swift editor-preference validators
from Task 2 to accept `line`. Change the renderer signature to:

```ts
export function roughPathsFor(
  element: RectangleElement | ArrowElement | LineElement,
): RoughPath[]
```

Use `generator.line` for the line and the arrow shaft. Compute the arrowhead
from the final segment angle and render two additional seeded rough lines:

```ts
const angle = Math.atan2(endY - startY, endX - startX);
const headLength = Math.max(12, element.strokeWidth * 4);
const left = {
  x: endX - headLength * Math.cos(angle - Math.PI / 6),
  y: endY - headLength * Math.sin(angle - Math.PI / 6),
};
const right = {
  x: endX - headLength * Math.cos(angle + Math.PI / 6),
  y: endY - headLength * Math.sin(angle + Math.PI / 6),
};
```

Use `seed`, `seed + 1`, and `seed + 2` for shaft, left head, and right head so
reopen and export remain stable. The line renders only its shaft. Add a test
that arrow output has three rough drawables and line output has one.

Add `line` to `DocumentSession.supportedElementTypes` and validate it with the
exact same keys and style rules as arrow.

- [ ] **Step 4: Run the line gate**

Run:

```bash
pnpm --filter @myshottr/editor test
pnpm --filter @myshottr/editor typecheck
pnpm --filter @myshottr/editor build
xcodebuild test -project MyShottr.xcodeproj -scheme MyShottr \
  -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO
```

Expected: all editor and native validation tests pass.

- [ ] **Step 5: Commit line annotations**

```bash
git add Packages/editor/src Sources/MyShottrApp/Documents/DocumentSession.swift
git commit -m "feat: add editable line annotations"
```

### Task 4: Source-Only Blur Annotation

**Files:**
- Modify: `Packages/editor/src/model/elements.ts`
- Modify: `Packages/editor/src/model/schema.ts`
- Modify: `Packages/editor/src/test/fixtures.ts`
- Create: `Packages/editor/src/canvas/blurSource.ts`
- Test: `Packages/editor/src/canvas/blurSource.test.ts`
- Modify: `Packages/editor/src/canvas/tools/createElement.ts`
- Modify: `Packages/editor/src/canvas/tools/createElement.test.ts`
- Modify: `Packages/editor/src/canvas/tools/ToolController.ts`
- Modify: `Packages/editor/src/canvas/renderElement.tsx`
- Modify: `Packages/editor/src/canvas/EditorCanvas.tsx`
- Modify: `Packages/editor/src/export/renderDocumentToBlob.ts`
- Modify: `Packages/editor/src/export/renderDocumentToBlob.test.ts`
- Modify: `Packages/editor/src/components/FloatingToolPalette.tsx`
- Modify: `Packages/editor/src/components/ContextStylePalette.tsx`
- Modify: `Sources/MyShottrApp/Documents/DocumentSession.swift`

**Interfaces:**
- Consumes: the immutable source image, box creation gestures, element transforms, and source-resolution export canvas.
- Produces: `BlurElement`, `BLUR_RADIUS_PX`, `createBlurredSourceCanvas`, preview/export parity, and the `B` shortcut.

- [ ] **Step 1: Write failing blur model and source-layer tests**

Add:

```ts
it("creates a fixed-radius blur region", () => {
  expect(createElement("blur", {
    kind: "box",
    start: { x: 20, y: 30 },
    end: { x: 120, y: 80 },
  }, creationContext())).toMatchObject({
    type: "blur",
    x: 20,
    y: 30,
    width: 100,
    height: 50,
    radius: 12,
  });
});

it("builds one source-resolution Gaussian-blurred canvas", () => {
  const result = createBlurredSourceCanvas(sourceImage, 1440, 900, 12);
  expect(result).toMatchObject({ width: 1440, height: 900 });
  expect(offscreenContext.filter).toBe("blur(12px)");
  expect(offscreenContext.drawImage).toHaveBeenCalledWith(
    sourceImage, 0, 0, 1440, 900,
  );
});

it("draws blur before vector annotations during export", async () => {
  await renderDocumentToBlob(fixtureDocument({
    elements: [fixtureText(), fixtureBlur()],
  }), "source.png");
  expect(drawOperations).toEqual([
    "source",
    "blurred-source-crop",
    "text",
  ]);
});
```

Test that serialization rejects a different radius, a negative size, and
unknown blur keys.

- [ ] **Step 2: Run focused tests and verify failure**

Run:

```bash
pnpm --filter @myshottr/editor test -- \
  blurSource.test.ts createElement.test.ts renderDocumentToBlob.test.ts
```

Expected: missing blur type and helper failures.

- [ ] **Step 3: Implement deterministic blurred-source generation**

Create:

```ts
export const BLUR_RADIUS_PX = 12 as const;

export function createBlurredSourceCanvas(
  source: CanvasImageSource,
  width: number,
  height: number,
  radius: typeof BLUR_RADIUS_PX,
): HTMLCanvasElement {
  const canvas = document.createElement("canvas");
  canvas.width = width;
  canvas.height = height;
  const context = canvas.getContext("2d");
  if (!context) throw new Error("Unable to create blur rendering context");
  context.filter = `blur(${radius}px)`;
  context.drawImage(source, 0, 0, width, height);
  context.filter = "none";
  return canvas;
}
```

Add:

```ts
export type BlurElement = ElementBase & {
  type: "blur";
  radius: 12;
};
```

The Zod schema requires `radius: z.literal(12)`. Blur uses a box gesture,
renders at opacity `1`, and exposes no color, stroke, roughness, or opacity
controls. Extend the TypeScript and Swift editor-preference validators from
Task 2 to accept `blur`.

- [ ] **Step 4: Implement preview and export ordering**

In `EditorCanvas`, build the blurred source once per source image:

```ts
const blurredSource = useMemo(
  () => image
    ? createBlurredSourceCanvas(
        image,
        document.sourcePixelWidth,
        document.sourcePixelHeight,
        BLUR_RADIUS_PX,
      )
    : undefined,
  [image, document.sourcePixelWidth, document.sourcePixelHeight],
);
```

Sort elements in this fixed visual order:

```ts
const orderedElements = [
  ...elementsOfType(document, "blur"),
  ...elementsOfType(document, "highlighter"),
  ...normalVectorElements(document),
];
```

For a blur group at `element.x`, `element.y`, clip to its width and height and
place the full blurred source at `-element.x`, `-element.y`. Keep the group
draggable and resizable through the existing handlers. Set
`rotateEnabled={selectedElement?.type !== "blur"}` on the transformer because
v1 blur regions are axis-aligned source crops.

For export, create one blurred source canvas. Before drawing vector elements,
for each blur region:

```ts
context.save();
context.translate(element.x, element.y);
context.rotate((element.rotation * Math.PI) / 180);
context.beginPath();
context.rect(0, 0, element.width, element.height);
context.clip();
context.drawImage(
  blurredSource,
  -element.x,
  -element.y,
  document.sourcePixelWidth,
  document.sourcePixelHeight,
);
context.restore();
```

Then render highlighters and normal annotations. Never write the blurred
pixels into `original.png`.

- [ ] **Step 5: Add native validation and run the blur gate**

Add `blur` to `DocumentSession.supportedElementTypes`. Validate exact base
keys plus `radius`, require `radius == 12`, opacity `1`, and rotation `0`.

Run:

```bash
pnpm --filter @myshottr/editor test
pnpm --filter @myshottr/editor typecheck
pnpm --filter @myshottr/editor build
xcodebuild test -project MyShottr.xcodeproj -scheme MyShottr \
  -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO
```

Expected: all tests and builds pass.

- [ ] **Step 6: Commit blur annotations**

```bash
git add Packages/editor/src Sources/MyShottrApp/Documents/DocumentSession.swift
git commit -m "feat: add non-destructive blur annotations"
```

### Task 5: Editable Text and Contextual Element Styles

**Files:**
- Create: `Packages/editor/src/components/TextEditorOverlay.tsx`
- Test: `Packages/editor/src/components/TextEditorOverlay.test.tsx`
- Modify: `Packages/editor/src/App.tsx`
- Modify: `Packages/editor/src/App.test.tsx`
- Modify: `Packages/editor/src/canvas/EditorCanvas.tsx`
- Modify: `Packages/editor/src/canvas/renderElement.tsx`
- Modify: `Packages/editor/src/components/ContextStylePalette.tsx`
- Modify: `Packages/editor/src/model/elements.ts`
- Modify: `Packages/editor/src/model/reducer.ts`
- Modify: `Packages/editor/src/model/history.test.ts`

**Interfaces:**
- Consumes: selected elements, source-to-screen canvas transform, existing
  update commands, and editor defaults.
- Produces: double-click text editing, `updateMany`, and style changes that
  modify selected elements rather than only future defaults.

- [ ] **Step 1: Write failing text-edit and selected-style tests**

Add:

```ts
it("edits existing text and commits one history command", () => {
  renderEditor(fixtureDocument({ elements: [fixtureText()] }));
  fireEvent.doubleClick(screen.getByTestId("element-text-1"));
  const editor = screen.getByRole("textbox", { name: "Edit annotation text" });
  fireEvent.change(editor, { target: { value: "Ship this" } });
  fireEvent.keyDown(editor, { key: "Enter", metaKey: true });

  expect(latestDocument().elements[0]).toMatchObject({
    type: "text",
    text: "Ship this",
  });
  fireEvent.keyDown(window, { key: "z", metaKey: true });
  expect(latestDocument().elements[0]).toMatchObject({
    type: "text",
    text: "Annotate this",
  });
});

it("escapes text editing without changing the document", () => {
  renderEditor(fixtureDocument({ elements: [fixtureText()] }));
  fireEvent.doubleClick(screen.getByTestId("element-text-1"));
  fireEvent.change(
    screen.getByRole("textbox", { name: "Edit annotation text" }),
    { target: { value: "Discard me" } },
  );
  fireEvent.keyDown(
    screen.getByRole("textbox", { name: "Edit annotation text" }),
    { key: "Escape" },
  );
  expect(latestDocument().elements[0]).toMatchObject({
    text: "Annotate this",
  });
});

it("applies a color change to the selected rectangle", () => {
  renderEditor();
  selectFixtureRectangle();
  fireEvent.change(screen.getByLabelText("Color"), {
    target: { value: "#FF4D4F" },
  });
  expect(latestDocument().elements[0]).toMatchObject({
    strokeColor: "#FF4D4F",
  });
});
```

Add reducer/history coverage:

```ts
it("applies updateMany as one undoable command", () => {
  const history = createHistoryStore(fixtureDocument({
    elements: [fixtureRect(), fixtureText()],
  }));
  history.dispatch({
    type: "updateMany",
    elements: [
      { ...fixtureRect(), opacity: 0.5 },
      { ...fixtureText(), opacity: 0.5 },
    ],
  });
  expect(history.undo()).toBe(true);
  expect(history.document.elements.map((element) => element.opacity))
    .toEqual([1, 1]);
});
```

- [ ] **Step 2: Run focused tests and verify failure**

Run:

```bash
pnpm --filter @myshottr/editor test -- \
  TextEditorOverlay.test.tsx App.test.tsx history.test.ts
```

Expected: missing text overlay and `updateMany` failures.

- [ ] **Step 3: Add an atomic multi-element update command**

Extend:

```ts
export type EditorCommand =
  | { type: "create"; element: EditorElement }
  | { type: "update"; element: EditorElement }
  | { type: "updateMany"; elements: EditorElement[] }
  | { type: "delete"; ids: string[] }
  | { type: "reorder"; ids: string[]; direction: "forward" | "backward" };
```

`updateMany` rejects duplicate IDs, requires every ID to exist, replaces each
element in place, and normalizes no z-index. The history store records the
whole command as one undo entry.

- [ ] **Step 4: Implement the text editor overlay**

Create:

```tsx
import { useEffect, useRef, useState } from "react";
import type { TextElement } from "../model/elements";

export function TextEditorOverlay({
  element,
  zoom,
  pan,
  onCommit,
  onCancel,
}: {
  element: TextElement;
  zoom: number;
  pan: { x: number; y: number };
  onCommit: (text: string) => void;
  onCancel: () => void;
}) {
  const [value, setValue] = useState(element.text);
  const ref = useRef<HTMLTextAreaElement>(null);

  useEffect(() => {
    ref.current?.focus();
    ref.current?.select();
  }, []);

  return (
    <textarea
      ref={ref}
      aria-label="Edit annotation text"
      value={value}
      style={{
        position: "absolute",
        left: pan.x + element.x * zoom,
        top: pan.y + element.y * zoom,
        width: Math.max(48, element.width * zoom),
        minHeight: Math.max(32, element.height * zoom),
        fontSize: element.fontSize * zoom,
        color: element.color,
        transform: `rotate(${element.rotation}deg)`,
        transformOrigin: "top left",
      }}
      onChange={(event) => setValue(event.target.value)}
      onBlur={() => onCommit(value)}
      onKeyDown={(event) => {
        if (event.key === "Escape") {
          event.preventDefault();
          onCancel();
        } else if (event.key === "Enter" && event.metaKey) {
          event.preventDefault();
          onCommit(value);
        }
      }}
    />
  );
}
```

`renderElement` adds `data-testid="element-\(id)"` and an `onDoubleClick`
handler. `EditorCanvas` reports the text element ID to `EditorApp`, which
renders one overlay. Commit dispatches one `update` with trimmed text and an
auto-sized width/height measured with the same system font. Empty trimmed text
deletes the element. Escape closes the overlay without dispatching.

- [ ] **Step 5: Make contextual controls edit the selection**

Change `ContextStylePalette` to accept:

```ts
{
  tool: EditorTool;
  defaults: EditorDefaults;
  selectedElements: EditorElement[];
  onDefaultsChange: (defaults: EditorDefaults) => void;
  onElementsChange: (elements: EditorElement[]) => void;
}
```

When `selectedElements` is empty, controls continue to change creation
defaults. When selection exists, derive visible controls from the selected
types and dispatch `updateMany`:

```ts
function recolor(element: EditorElement, color: PaletteColor): EditorElement {
  switch (element.type) {
    case "rectangle":
    case "arrow":
    case "line":
      return { ...element, strokeColor: color };
    case "text":
    case "freehand":
    case "highlighter":
    case "numberMarker":
      return { ...element, color };
    case "blur":
    case "redaction":
      return element;
  }
}
```

Stroke width applies only to rectangle, arrow, line, and freehand. Roughness
applies only to rectangle, arrow, and line. Text size applies only to text.
Opacity applies to every selected type except blur and redaction. Do not alter
unsupported properties on heterogeneous selections.

- [ ] **Step 6: Run text and contextual-style tests**

Run:

```bash
pnpm --filter @myshottr/editor test
pnpm --filter @myshottr/editor typecheck
pnpm --filter @myshottr/editor build
```

Expected: all tests pass, existing text persists, and selected styles are
undoable.

- [ ] **Step 7: Commit editable text and selected styles**

```bash
git add Packages/editor/src
git commit -m "feat: edit text and selected annotation styles"
```

### Task 6: Multi-Selection, Group Transforms, and Z-Order

**Files:**
- Modify: `Packages/editor/src/App.tsx`
- Modify: `Packages/editor/src/App.test.tsx`
- Modify: `Packages/editor/src/canvas/EditorCanvas.tsx`
- Modify: `Packages/editor/src/canvas/EditorCanvas.test.tsx`
- Modify: `Packages/editor/src/canvas/SelectionController.ts`
- Modify: `Packages/editor/src/canvas/SelectionController.test.ts`
- Modify: `Packages/editor/src/canvas/tools/ToolController.ts`
- Modify: `Packages/editor/src/model/reducer.ts`
- Modify: `Packages/editor/src/model/history.test.ts`
- Modify: `Packages/editor/src/components/ContextStylePalette.tsx`

**Interfaces:**
- Consumes: `updateMany`, registered Konva groups, shift-click input, and
  existing reorder commands.
- Produces: ordered `selectedIds`, group movement/transform, multi-delete,
  multi-duplicate, and forward/backward ordering controls and shortcuts.

- [ ] **Step 1: Write failing multi-selection and ordering tests**

Add:

```ts
it("shift-click toggles membership without losing the first selection", () => {
  const selection = new SelectionController();
  selection.replace("rect-1");
  selection.toggle("text-1");
  expect(selection.selectedIds).toEqual(["rect-1", "text-1"]);
  selection.toggle("rect-1");
  expect(selection.selectedIds).toEqual(["text-1"]);
});

it("moves a selected pair by one bounded delta and undoes once", () => {
  renderEditor(fixtureDocument({
    elements: [fixtureRect(), fixtureText()],
  }));
  selectWithShift("rect-1", "text-1");
  dragElement("rect-1", { x: 20, y: 12 });
  expect(positions()).toEqual([
    { x: 20, y: 12 },
    { x: 60, y: 62 },
  ]);
  fireEvent.keyDown(window, { key: "z", metaKey: true });
  expect(positions()).toEqual([
    { x: 0, y: 0 },
    { x: 40, y: 50 },
  ]);
});

it("moves selected elements forward without duplicate z-indices", () => {
  const next = editorReducer(documentWithThreeElements(), {
    type: "reorder",
    ids: ["rect-1", "text-1"],
    direction: "forward",
  });
  expect(new Set(next.elements.map((element) => element.zIndex)).size)
    .toBe(next.elements.length);
});
```

Test `Meta+]` maps to `bringForward`, `Meta+[` maps to `sendBackward`, delete
removes all selected IDs, and duplicate creates the same number of new IDs.

- [ ] **Step 2: Run focused tests and verify failure**

Run:

```bash
pnpm --filter @myshottr/editor test -- \
  SelectionController.test.ts EditorCanvas.test.tsx App.test.tsx history.test.ts
```

Expected: the single-selection controller and missing order shortcuts fail.

- [ ] **Step 3: Implement ordered multi-selection**

Replace the single selected ID with:

```ts
export class SelectionController {
  #selectedIds: string[] = [];

  get selectedIds(): readonly string[] {
    return this.#selectedIds;
  }

  replace(id: string): void {
    this.#selectedIds = [id];
  }

  toggle(id: string): void {
    this.#selectedIds = this.#selectedIds.includes(id)
      ? this.#selectedIds.filter((candidate) => candidate !== id)
      : [...this.#selectedIds, id];
  }

  clear(): void {
    this.#selectedIds = [];
  }
}
```

`EditorApp` stores `selectedIds: string[]`. A normal click replaces selection;
Shift-click toggles membership; clicking the empty stage clears it.

- [ ] **Step 4: Implement group move and transform**

Attach the Transformer to all registered selected groups:

```ts
const selectedNodes = selectedIds.flatMap((id) => {
  const node = nodes.current.get(id);
  return node ? [node] : [];
});
transformer.current?.nodes(selectedNodes);
```

At interaction start, snapshot every selected element. Dragging any selected
node computes one source-coordinate delta and applies
`moveElementsWithinBounds(snapshot, delta, bounds)`. Clamp the shared delta so
no selected element leaves the source image. Dispatch `updateMany` inside one
history transaction.

At group transform end, read each selected Konva group's final position,
scale, and rotation, call the existing bounded resize helper for each element,
reset node scale to `1`, and dispatch one `updateMany`. If a blur is selected
with other elements, disable rotation for the whole Transformer.

- [ ] **Step 5: Implement multi-delete, duplicate, and z-order**

Delete dispatches all selected IDs. Duplicate maps every selected element
through the same bounded 12-pixel offset, assigns unique IDs, consecutive
seeds, and consecutive z-indices, dispatches one `updateMany`-compatible batch
creation command:

```ts
| { type: "createMany"; elements: EditorElement[] }
```

Add `createMany` to reducer and history as one undo entry.

Extend `KeyboardCommand`:

```ts
| "bringForward"
| "sendBackward"
```

Map `Meta+]` and `Meta+[` and dispatch the existing reorder command with every
selected ID. Add visible Bring Forward and Send Backward buttons to the
contextual palette when selection exists.

- [ ] **Step 6: Run multi-selection and full editor tests**

Run:

```bash
pnpm --filter @myshottr/editor test
pnpm --filter @myshottr/editor typecheck
pnpm --filter @myshottr/editor build
```

Expected: all selection, group transform, ordering, history, and prior editor
tests pass.

- [ ] **Step 7: Commit multi-selection and ordering**

```bash
git add Packages/editor/src
git commit -m "feat: add multi-selection and annotation ordering"
```

### Task 7: Keyboard Editing and Explicit Native Output Actions

**Files:**
- Modify: `Packages/editor/src/canvas/tools/ToolController.ts`
- Modify: `Packages/editor/src/canvas/tools/createElement.ts`
- Modify: `Packages/editor/src/App.tsx`
- Modify: `Packages/editor/src/App.test.tsx`
- Modify: `Sources/MyShottrApp/App/MyShottrApp.swift`
- Modify: `Sources/MyShottrApp/Documents/DocumentWindowController.swift`
- Test: `Tests/MyShottrTests/Documents/DocumentWindowControllerCommandTests.swift`

**Interfaces:**
- Consumes: selected editor elements, the existing duplicate operation, and native Copy/Save/Export methods.
- Produces: annotation copy/paste, `Command-Shift-C` Copy Image, `Command-S` Save Project, and `Command-E` Export PNG.

- [ ] **Step 1: Write failing command tests**

Add editor tests:

```ts
it("copies and pastes a selected annotation without replacing its identity", () => {
  renderEditor();
  selectFixtureRectangle();
  fireEvent.keyDown(window, { key: "c", metaKey: true });
  fireEvent.keyDown(window, { key: "v", metaKey: true });

  const elements = latestDocument().elements;
  expect(elements).toHaveLength(2);
  expect(elements[1]).toMatchObject({ x: 12, y: 12 });
  expect(elements[1].id).not.toBe(elements[0].id);
});

it("does not turn command-v into the selection tool", () => {
  expect(keyboardCommandFor(
    new KeyboardEvent("keydown", { key: "v", metaKey: true }),
  )).toBe("paste");
});
```

Add a native command-routing test that installs the controller as the key
window's next responder and verifies each selector resolves to it:

```swift
window.makeKey()
XCTAssertTrue(
    NSApp.target(
        forAction: #selector(DocumentWindowController.copyComposite(_:)),
        to: nil,
        from: nil
    ) === controller
)
```

- [ ] **Step 2: Run focused tests and verify failure**

Run:

```bash
pnpm --filter @myshottr/editor test -- App.test.tsx
xcodebuild test -project MyShottr.xcodeproj -scheme MyShottr \
  -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO \
  -only-testing:MyShottrTests/DocumentWindowControllerCommandTests
```

Expected: missing `copy`/`paste` commands and unavailable native selectors.

- [ ] **Step 3: Implement annotation copy and paste**

Extend:

```ts
export type KeyboardCommand =
  | EditorTool
  | "delete"
  | "duplicate"
  | "copy"
  | "paste"
  | "undo"
  | "redo";
```

Map `Meta+C` to `copy` and `Meta+V` to `paste` before unmodified tool keys.
`EditorApp` stores cloned elements for every `selectedIds` entry in one ref on
copy. Paste calls the same bounded group-offset logic as duplicate, assigns new
UUIDs, consecutive seeds and z-indices, dispatches `createMany`, selects the
new elements, and leaves the operating-system clipboard unchanged.

- [ ] **Step 4: Add native menu commands and explicit labels**

Make the three controller actions internal `@objc` methods. Set:

```swift
item.label = "Copy Image"
item.toolTip = "Copy the annotated PNG (Command-Shift-C)"

item.label = "Save Project"
item.toolTip = "Save an editable MyShottr project (Command-S)"

item.label = "Export PNG"
item.toolTip = "Export the annotated PNG (Command-E)"
```

After creating the window, insert the controller into the responder chain:

```swift
self.nextResponder = window.nextResponder
window.nextResponder = self
```

Add SwiftUI commands:

```swift
CommandMenu("Image") {
    Button("Copy Image") {
        NSApp.sendAction(
            #selector(DocumentWindowController.copyComposite(_:)),
            to: nil,
            from: nil
        )
    }
    .keyboardShortcut("c", modifiers: [.command, .shift])

    Button("Export PNG") {
        NSApp.sendAction(
            #selector(DocumentWindowController.exportComposite(_:)),
            to: nil,
            from: nil
        )
    }
    .keyboardShortcut("e", modifiers: [.command])
}
```

Add Save Project with `Command-S` under the File command group. The responder
action returns `false` when no document window is key; it never creates a blank
document.

- [ ] **Step 5: Run command tests and the complete editor gate**

Run:

```bash
pnpm test
pnpm typecheck
pnpm build
xcodebuild test -project MyShottr.xcodeproj -scheme MyShottr \
  -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO
```

Expected: all commands pass and existing editor behavior remains green.

- [ ] **Step 6: Commit keyboard and output actions**

```bash
git add Packages/editor/src Sources/MyShottrApp/App/MyShottrApp.swift \
  Sources/MyShottrApp/Documents/DocumentWindowController.swift \
  Tests/MyShottrTests/Documents
git commit -m "feat: complete editor keyboard workflow"
```

### Task 8: Quick Ink Interface and Production Icon Assets

**Files:**
- Create: `Packages/editor/src/components/ToolIcon.tsx`
- Create: `Packages/editor/src/components/VisuallyHidden.tsx`
- Modify: `Packages/editor/src/components/FloatingToolPalette.tsx`
- Modify: `Packages/editor/src/components/ContextStylePalette.tsx`
- Modify: `Packages/editor/src/components/ZoomControls.tsx`
- Modify: `Packages/editor/src/styles.css`
- Modify: `Packages/editor/src/App.test.tsx`
- Create: `Assets/AppIcon/QuickInk-1024.png`
- Create: `Assets/StatusBar/QuickInkStatus.svg`
- Create: `Resources/Assets.xcassets/Contents.json`
- Create: `Resources/Assets.xcassets/AppIcon.appiconset/Contents.json`
- Create: `Resources/Assets.xcassets/StatusBarIcon.imageset/Contents.json`
- Create: `Scripts/generate-app-iconset.sh`
- Modify: `project.yml`
- Test: `Tests/MyShottrTests/App/AppIconConfigurationTests.swift`

**Interfaces:**
- Consumes: the approved Quick Ink direction and the completed tool set.
- Produces: accessible icon-first editor controls, all macOS AppIcon renditions, and a monochrome template status item image.

- [ ] **Step 1: Write failing accessibility and asset tests**

Add:

```ts
it("renders every tool as an icon button with label and shortcut", () => {
  renderToolbar();
  expect(screen.getByRole("button", { name: "Rectangle (R)" }))
    .toHaveAttribute("title", "Rectangle (R)");
  expect(screen.getByRole("button", { name: "Blur (B)" }))
    .toHaveAttribute("title", "Blur (B)");
});
```

Create a native test:

```swift
import AppKit
import XCTest
@testable import MyShottr

func testProjectConfigUsesQuickInkAppIcon() throws {
    let repositoryRoot = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
    let project = try String(
        contentsOf: repositoryRoot.appendingPathComponent("project.yml"),
        encoding: .utf8
    )
    XCTAssertTrue(project.contains("ASSETCATALOG_COMPILER_APPICON_NAME: AppIcon"))
    XCTAssertNotNil(NSImage(named: "StatusBarIcon"))
}
```

- [ ] **Step 2: Run focused tests and verify failure**

Run:

```bash
pnpm --filter @myshottr/editor test -- App.test.tsx
xcodegen generate
xcodebuild test -project MyShottr.xcodeproj -scheme MyShottr \
  -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO \
  -only-testing:MyShottrTests/AppIconConfigurationTests
```

Expected: icon buttons and asset catalog are missing.

- [ ] **Step 3: Implement accessible icon-first controls**

Create `ToolIcon.tsx`:

```tsx
import type { EditorTool } from "../model/elements";

const paths: Record<EditorTool, string[]> = {
  selection: ["M5 3l13 9-6 2-2 6z"],
  rectangle: ["M4 5h16v14H4z"],
  arrow: ["M5 18 19 6", "m13 0h6v6"],
  line: ["M5 18 19 6"],
  text: ["M5 5h14", "M12 5v14", "M8 19h8"],
  freehand: ["M4 17c4-10 6 4 9-5s4-5 7-5"],
  highlighter: ["m5 15 8-8 4 4-8 8H5z", "M4 21h16"],
  blur: ["M7 7h2M12 7h1M16 7h1M7 12h1M11 12h2M16 12h1M7 17h2M12 17h1M16 17h2"],
  redaction: ["M4 6h16v12H4z", "M7 9h10M7 12h10M7 15h10"],
  numberMarker: ["M12 21a9 9 0 1 0 0-18 9 9 0 0 0 0 18", "M10 9l2-1v8", "M10 16h4"],
};

export function ToolIcon({ tool }: { tool: EditorTool }) {
  return (
    <svg
      viewBox="0 0 24 24"
      width="20"
      height="20"
      fill="none"
      stroke="currentColor"
      strokeWidth="1.8"
      strokeLinecap="round"
      strokeLinejoin="round"
      aria-hidden="true"
    >
      {paths[tool].map((path) => <path key={path} d={path} />)}
    </svg>
  );
}
```

Create `VisuallyHidden.tsx`:

```tsx
import type { ReactNode } from "react";

export function VisuallyHidden({ children }: { children: ReactNode }) {
  return <span className="visually-hidden">{children}</span>;
}
```

`FloatingToolPalette` renders:

```tsx
<button
  key={entry.tool}
  type="button"
  aria-label={`${entry.label} (${entry.shortcut.toUpperCase()})`}
  title={`${entry.label} (${entry.shortcut.toUpperCase()})`}
  aria-pressed={tool === entry.tool}
  onClick={() => onSelect(entry.tool)}
>
  <ToolIcon tool={entry.tool} />
  <VisuallyHidden>{entry.label}</VisuallyHidden>
</button>
```

Use these CSS tokens:

```css
:root {
  --ink: #201b1a;
  --canvas-surround: #f7f1e8;
  --panel: rgb(255 252 247 / 94%);
  --coral: #ff6b5f;
  --coral-strong: #ed4f45;
  --border: rgb(32 27 26 / 12%);
  --shadow: 0 16px 42px rgb(73 45 38 / 16%);
}

.visually-hidden {
  position: absolute;
  width: 1px;
  height: 1px;
  padding: 0;
  margin: -1px;
  overflow: hidden;
  clip: rect(0, 0, 0, 0);
  white-space: nowrap;
  border: 0;
}
```

Style 36-pixel icon buttons, 14-pixel panel radii, visible keyboard focus,
coral active states, compact contextual controls, and the warm ivory workspace.
Keep the screenshot surface white and unfiltered.

- [ ] **Step 4: Generate and install Quick Ink artwork**

Use the `imagegen` skill with this exact prompt:

```text
Create a production macOS application icon at 1024 by 1024 pixels. Quick Ink
identity: warm coral-to-salmon gradient background, a centered cream screenshot
card, one bold black hand-drawn crop rectangle and a short black hand-drawn
arrow, friendly Excalidraw energy, strong simple silhouette readable at 16px,
subtle dimensional lighting, no text, no letters, no watermark, no third-party
logo, full square artwork with safe margins for the macOS squircle mask.
```

Save the approved output as `Assets/AppIcon/QuickInk-1024.png`. Create
`QuickInkStatus.svg` as a monochrome crop-corner plus short arrow using black
strokes, no background, and a `24 24` view box.

Create `Scripts/generate-app-iconset.sh`:

```bash
#!/bin/zsh
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SOURCE="${REPO_ROOT}/Assets/AppIcon/QuickInk-1024.png"
DESTINATION="${REPO_ROOT}/Resources/Assets.xcassets/AppIcon.appiconset"

test -f "${SOURCE}"
mkdir -p "${DESTINATION}"

sips -z 16 16 "${SOURCE}" --out "${DESTINATION}/icon_16x16.png" >/dev/null
sips -z 32 32 "${SOURCE}" --out "${DESTINATION}/icon_16x16@2x.png" >/dev/null
sips -z 32 32 "${SOURCE}" --out "${DESTINATION}/icon_32x32.png" >/dev/null
sips -z 64 64 "${SOURCE}" --out "${DESTINATION}/icon_32x32@2x.png" >/dev/null
sips -z 128 128 "${SOURCE}" --out "${DESTINATION}/icon_128x128.png" >/dev/null
sips -z 256 256 "${SOURCE}" --out "${DESTINATION}/icon_128x128@2x.png" >/dev/null
sips -z 256 256 "${SOURCE}" --out "${DESTINATION}/icon_256x256.png" >/dev/null
sips -z 512 512 "${SOURCE}" --out "${DESTINATION}/icon_256x256@2x.png" >/dev/null
sips -z 512 512 "${SOURCE}" --out "${DESTINATION}/icon_512x512.png" >/dev/null
cp "${SOURCE}" "${DESTINATION}/icon_512x512@2x.png"
cp "${REPO_ROOT}/Assets/StatusBar/QuickInkStatus.svg" \
  "${REPO_ROOT}/Resources/Assets.xcassets/StatusBarIcon.imageset/QuickInkStatus.svg"
```

Create `AppIcon.appiconset/Contents.json`:

```json
{
  "images": [
    { "filename": "icon_16x16.png", "idiom": "mac", "scale": "1x", "size": "16x16" },
    { "filename": "icon_16x16@2x.png", "idiom": "mac", "scale": "2x", "size": "16x16" },
    { "filename": "icon_32x32.png", "idiom": "mac", "scale": "1x", "size": "32x32" },
    { "filename": "icon_32x32@2x.png", "idiom": "mac", "scale": "2x", "size": "32x32" },
    { "filename": "icon_128x128.png", "idiom": "mac", "scale": "1x", "size": "128x128" },
    { "filename": "icon_128x128@2x.png", "idiom": "mac", "scale": "2x", "size": "128x128" },
    { "filename": "icon_256x256.png", "idiom": "mac", "scale": "1x", "size": "256x256" },
    { "filename": "icon_256x256@2x.png", "idiom": "mac", "scale": "2x", "size": "256x256" },
    { "filename": "icon_512x512.png", "idiom": "mac", "scale": "1x", "size": "512x512" },
    { "filename": "icon_512x512@2x.png", "idiom": "mac", "scale": "2x", "size": "512x512" }
  ],
  "info": { "author": "xcode", "version": 1 }
}
```

Create `StatusBarIcon.imageset/Contents.json`:

```json
{
  "images": [
    {
      "filename": "QuickInkStatus.svg",
      "idiom": "universal",
      "scale": "1x"
    }
  ],
  "info": { "author": "xcode", "version": 1 },
  "properties": {
    "preserves-vector-representation": true,
    "template-rendering-intent": "template"
  }
}
```

The asset-catalog root `Contents.json` is:

```json
{
  "info": { "author": "xcode", "version": 1 }
}
```

Add the asset catalog to the app target and set:

```yaml
resources:
  - path: Resources/Assets.xcassets
settings:
  base:
    ASSETCATALOG_COMPILER_APPICON_NAME: AppIcon
```

Merge those keys with the existing app target instead of creating a second
`resources` or `settings` mapping.

The resulting build setting is exactly:

```yaml
ASSETCATALOG_COMPILER_APPICON_NAME: AppIcon
```

Create `QuickInkStatus.svg` with this exact source:

```svg
<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24">
  <g fill="none" stroke="#000" stroke-width="2" stroke-linecap="round" stroke-linejoin="round">
    <path d="M4 9V5a1 1 0 0 1 1-1h4M15 4h4a1 1 0 0 1 1 1v4M20 15v4a1 1 0 0 1-1 1h-4M9 20H5a1 1 0 0 1-1-1v-4"/>
    <path d="m9 15 6-6m-2 0h2v2"/>
  </g>
</svg>
```

The native-capture plan's menu-bar task loads `NSImage(named:
"StatusBarIcon")`, sets `isTemplate = true`, and uses it for the status item.

- [ ] **Step 5: Verify visual assets and UI**

Run:

```bash
chmod +x Scripts/generate-app-iconset.sh
Scripts/generate-app-iconset.sh
pnpm --filter @myshottr/editor test
pnpm --filter @myshottr/editor build
xcodegen generate
xcodebuild test -project MyShottr.xcodeproj -scheme MyShottr \
  -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO
xcodebuild build -project MyShottr.xcodeproj -scheme MyShottr \
  -configuration Debug -destination 'platform=macOS'
```

Expected: every command exits `0`. Manually inspect the editor at 1280×860 and
the icon at 16, 32, 128, and 1024 pixels. Confirm tooltips, keyboard focus,
coral active states, toolbar wrapping, Dock readability, and menu-bar template
behavior.

- [ ] **Step 6: Commit Quick Ink branding**

```bash
git add Assets Resources Packages/editor/src project.yml \
  Scripts/generate-app-iconset.sh \
  Tests/MyShottrTests/App
git commit -m "feat: apply Quick Ink branding"
```

## Completion Gate

This plan is complete only when:

```bash
pnpm test
pnpm typecheck
pnpm build
xcodegen generate
xcodebuild test -project MyShottr.xcodeproj -scheme MyShottr \
  -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO
xcodebuild build -project MyShottr.xcodeproj -scheme MyShottr \
  -configuration Debug -destination 'platform=macOS'
git status --short
```

passes, `git status --short` is empty, a schema-1 fixture opens as schema 2,
line and blur survive save/reopen, Copy Image and annotation copy remain
distinct, and Quick Ink assets are visible in the built app.
