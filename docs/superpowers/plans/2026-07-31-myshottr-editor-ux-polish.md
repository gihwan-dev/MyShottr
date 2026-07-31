# MyShottr Editor UX Polish Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Deliver the approved Canvas First + Context Rail editor experience with immediate pointer feedback, Excalidraw-style direct manipulation, strict keyboard ownership, native Undo/Redo, truthful output feedback, and schema-safe persistence without reintroducing recovery.

**Architecture:** Keep one canonical schema-3 `EditorDocument` in the web editor, keep scene Undo/Redo snapshots separate from last-used creation defaults, and move pointer and viewport geometry out of `EditorApp` into focused controllers. The React/Konva editor owns tools, scene edits, selection, and view commands; AppKit owns Copy, Save, Export, and window state. The existing strict protocol-v1 envelope is extended additively for history availability, native history actions, and output-operation status.

**Tech Stack:** TypeScript 5.9, React 19, Konva 10, rough.js, Zod 4, Vitest 3, Playwright 1.54, Swift 6, AppKit, WebKit, XCTest, XcodeGen, macOS 15+

## Global Constraints

- Execute from `/Users/choegihwan/Documents/MyShottr/.worktrees/myshottr-v1` on branch `worktree/myshottr-v1`.
- The approved source of truth is `docs/superpowers/specs/2026-07-31-myshottr-editor-ux-polish-design.md`.
- Preserve every pre-existing dirty and untracked file. Stage only the paths named by the current task.
- Do not terminate a running `MyShottr` process or discard an open editor document. The repository-wide gate runs only after the user has saved and quit every running instance.
- Recovery coordinators, recovery storage, recovery dialogs, and recovery tests remain removed. Do not add an autosave or recovery substitute.
- Full-page/scrolling capture, element capture, mockup presentation, OCR, custom colors, and a layers panel remain out of scope.
- The Chrome path continues to capture only the visible browser viewport. Keep capture-source and `presentation` boundaries open for later full-page capture and desktop mockups without implementing either feature.
- Do not add fallback document formats, permissive bridge decoders, silent protocol degradation, or a second source of truth.
- The editor bundle remains local-only under `myshottr-editor://editor`; do not add network-loaded assets, analytics, remote fonts, or a CDN.
- Bridge protocol version remains `1`; the new messages are additive and both bundled sides ship together.
- `EditorDocument` schema version becomes exactly `3`. Versions `1` and `2` migrate deterministically; version `4` and later fail explicitly.
- `EditorPreferences` storage becomes `editorPreferences.v2`. A valid v1 value migrates once; invalid v2 data must not fall back to stale v1 data.
- Creation defaults are persisted in the canonical document and sent to native preferences, but changing defaults alone creates no scene Undo entry and sends no `documentChanged`.
- Pointer movement, marquee movement, and viewport movement are ephemeral. They must not call `HistoryStore.dispatch` or send `documentChanged`.
- Canvas rendering and PNG export use the same single global `zIndex` order. Do not retain blur/highlighter type bands.
- Copy, Save, and Export are mutually exclusive per document window. Editing remains enabled during Save and Export.
- Native-owned shortcuts are `Command-Shift-C`, `Command-S`, and `Command-E`; the web editor must not intercept them.
- Use TDD for every behavior change: write the failing assertion, run it and observe the intended failure, add the smallest implementation, rerun the focused test, then commit.
- Each task ends with a focused commit. Never combine another task's files into that commit.

---

## Pre-execution State

At plan creation, the worktree already contains two approved but uncommitted streams:

1. live creation preview changes in:
   - `Packages/editor/src/canvas/EditorCanvas.tsx`
   - `Packages/editor/src/canvas/EditorCanvas.test.tsx`
2. recovery-removal changes in AppKit, document/session tests, README, release notes, design references, and acceptance documentation.

The editor baseline currently passes:

```text
14 test files passed
130 tests passed
```

The following processes were running and were intentionally left untouched:

```text
66839
67125
```

`Scripts/verify-v1.sh` currently stops before running tests while those processes exist. This is a safety gate, not a product failure.

## Repository Map for This Plan

```text
Packages/editor/
├── package.json
├── playwright.config.ts
├── tests/
│   └── visual/
│       ├── editor.accessibility.spec.ts
│       ├── editor.visual.spec.ts
│       ├── entry.tsx
│       └── visual.html
└── src/
    ├── App.tsx
    ├── bridge/
    │   ├── nativeBridge.ts
    │   └── protocol.ts
    ├── canvas/
    │   ├── EditorCanvas.tsx
    │   ├── SelectionController.ts
    │   ├── renderElement.tsx
    │   └── tools/
    │       └── createElement.ts
    ├── components/
    │   ├── ContextRail.tsx
    │   ├── EditorFeedback.tsx
    │   ├── FloatingToolPalette.tsx
    │   ├── ShortcutHelpDialog.tsx
    │   ├── TextEditorOverlay.tsx
    │   └── ZoomControls.tsx
    ├── export/
    │   └── renderDocumentToBlob.ts
    ├── input/
    │   ├── ShortcutRouter.ts
    │   └── shortcutRegistry.ts
    ├── interaction/
    │   ├── InteractionController.ts
    │   ├── geometry.ts
    │   └── duplication.ts
    ├── model/
    │   ├── defaults.ts
    │   ├── elements.ts
    │   ├── history.ts
    │   ├── reducer.ts
    │   └── schema.ts
    └── viewport/
        └── ViewportController.ts
Sources/MyShottrApp/
├── App/
│   └── MyShottrApp.swift
├── Documents/
│   ├── DocumentSession.swift
│   ├── DocumentWindowController.swift
│   ├── EditorDocumentMigrator.swift
│   ├── EditorDocumentValidator.swift
│   ├── NewProjectFactory.swift
│   └── ProjectPackageStore.swift
├── Editor/
│   ├── EditorBridge.swift
│   ├── EditorBridgeEnvelope.swift
│   └── EditorWebView.swift
└── Preferences/
    └── EditorPreferencesStore.swift
Tests/MyShottrTests/
├── Documents/
├── Editor/
├── Preferences/
└── Support/
Scripts/
└── verify-v1.sh
docs/testing/
└── v1-acceptance.md
```

## Shared Interfaces

### Schema-3 document defaults

```ts
export type EditorDefaults = {
  color: PaletteColor;
  strokeWidth: 2 | 4 | 8;
  textSize: 16 | 24 | 36;
  roughness: 0 | 1 | 2;
  opacity: 0.25 | 0.5 | 0.75 | 1;
  rectangleFillColor: PaletteColor | null;
  highlighterOpacity: 0.25 | 0.5;
};

export type EditorDocument = {
  schemaVersion: 3;
  sourcePixelWidth: number;
  sourcePixelHeight: number;
  elements: EditorElement[];
  presentation: { type: "none" };
  defaults: EditorDefaults;
};
```

### History and interaction availability

```ts
export type HistoryAvailability = {
  canUndo: boolean;
  canRedo: boolean;
};

export type InteractionLocks = {
  pointer: boolean;
  nudge: boolean;
  text: boolean;
  slider: boolean;
  shortcutHelp: boolean;
};

export const isHistoryLocked = (locks: InteractionLocks): boolean =>
  Object.values(locks).some(Boolean);
```

### Context Rail value model

```ts
export type ContextValue<T> =
  | { kind: "single"; value: T }
  | { kind: "mixed" };

export type ContextField<T> = {
  value: ContextValue<T>;
  allowedValues: readonly T[];
};

export type ContextRailModel =
  | { kind: "hidden" }
  | {
      kind: "defaults";
      title: `New ${string}`;
      tool: Exclude<EditorTool, "selection">;
      fields: ContextRailFields;
    }
  | {
      kind: "selection";
      title: string;
      selectedIds: readonly string[];
      fields: ContextRailFields;
      actions: {
        canMoveForward: boolean;
        canMoveBackward: boolean;
        canDuplicate: true;
        canDelete: true;
      };
    };
```

### Bridge additions

```ts
export type OperationStatus =
  | { operation: "save" | "export"; phase: "started" }
  | { operation: "save"; phase: "completed" }
  | { operation: "save"; phase: "superseded" }
  | { operation: "export"; phase: "completed"; displayName: string }
  | { operation: "save" | "export"; phase: "cancelled" | "failed" };

export type EditorToNativePayloads = {
  historyStateChanged: HistoryAvailability;
};

export type NativeHistoryAction = {
  action: "undo" | "redo";
};
```

```swift
struct EditorPreferences: Codable, Equatable, Sendable {
    static let storageKey = "editorPreferences.v2"
    static let legacyStorageKey = "editorPreferences.v1"

    var tool: String
    var color: String
    var strokeWidth: Int
    var textSize: Int
    var roughness: Int
    var opacity: Double
    var rectangleFillColor: String?
    var highlighterOpacity: Double
}

enum OutputOperation: Equatable {
    case copy
    case save(requestID: UUID)
    case export(requestID: UUID)
}
```

## Task 0: Stabilize the Approved Dirty Baseline

**Files:**

- Preserve all currently dirty and untracked files.
- Commit stream A only:
  - `Packages/editor/src/canvas/EditorCanvas.tsx`
  - `Packages/editor/src/canvas/EditorCanvas.test.tsx`
- Commit stream B only:
  - `README.md`
  - `Sources/MyShottrApp/App/AppDelegate.swift`
  - `Sources/MyShottrApp/App/MyShottrUserFacingError.swift`
  - `Sources/MyShottrApp/App/UserFacingErrorPresenter.swift`
  - `Sources/MyShottrApp/Documents/DocumentSession.swift`
  - `Sources/MyShottrApp/Documents/DocumentWindowController.swift`
  - delete `Sources/MyShottrApp/Documents/RecoveryCoordinator.swift`
  - delete `Sources/MyShottrApp/Documents/RecoveryStore.swift`
  - delete `Sources/MyShottrApp/Documents/SessionTerminationState.swift`
  - `Tests/MyShottrTests/App/AppDelegateLifecycleTests.swift`
  - `Tests/MyShottrTests/App/UserFacingErrorPresenterTests.swift`
  - `Tests/MyShottrTests/Documents/DocumentSessionTests.swift`
  - `Tests/MyShottrTests/Documents/DocumentWindowControllerCommandTests.swift`
  - delete `Tests/MyShottrTests/Documents/RecoveryCoordinatorTests.swift`
  - delete `Tests/MyShottrTests/Documents/RecoveryStoreTests.swift`
  - delete `Tests/MyShottrTests/Support/RecoveryFakes.swift`
  - `Tests/MyShottrTests/Support/AdditionalProjectFixtures.swift`
  - `docs/releases/v0.1.0.md`
  - `docs/superpowers/specs/2026-07-29-myshottr-v1-design.md`
  - `docs/superpowers/specs/2026-07-30-myshottr-v1-public-release-design.md`
  - `docs/testing/v1-acceptance.md`

**Outcome:** The already-approved live-preview and recovery-removal work becomes two reviewable commits before overlapping editor/native files receive additional changes.

- [ ] **Step 1: Reconfirm the exact dirty inventory without changing it**

Run:

```bash
git status --short
git diff --stat
git diff -- Packages/editor/src/canvas/EditorCanvas.tsx Packages/editor/src/canvas/EditorCanvas.test.tsx
```

Expected: the preview delta updates ephemeral `creationPreview` during drag and creates the document element only on release.

- [ ] **Step 2: Verify the preview stream**

Run:

```bash
pnpm --filter @myshottr/editor exec vitest run src/canvas/EditorCanvas.test.tsx
pnpm --filter @myshottr/editor typecheck
```

Expected: both commands exit `0`; the preview assertion proves that the draft is visible before the committed document changes.

- [ ] **Step 3: Commit only the preview stream**

Run:

```bash
git add Packages/editor/src/canvas/EditorCanvas.tsx Packages/editor/src/canvas/EditorCanvas.test.tsx
git diff --cached --check
git diff --cached --name-only
git commit -m "feat(editor): 생성 중 도형 미리보기 추가"
```

Expected staged paths: exactly two editor canvas files.

- [ ] **Step 4: Verify recovery symbols are absent from production and test code**

Run:

```bash
rg -n "RecoveryCoordinator|RecoveryStore|SessionTerminationState|Recover unsaved" Sources Tests README.md docs || true
git diff -- Sources/MyShottrApp Tests/MyShottrTests README.md docs
```

Expected: no live production recovery path or recovery prompt remains. Historical wording in a migration note is acceptable only if it explicitly says the feature was removed.

- [ ] **Step 5: Run focused recovery-removal tests without stopping user processes**

Run:

```bash
xcodegen generate
xcodebuild test \
  -project MyShottr.xcodeproj \
  -scheme MyShottr \
  -destination "platform=macOS" \
  CODE_SIGNING_ALLOWED=NO \
  -only-testing:MyShottrTests/AppDelegateLifecycleTests \
  -only-testing:MyShottrTests/UserFacingErrorPresenterTests \
  -only-testing:MyShottrTests/DocumentSessionTests \
  -only-testing:MyShottrTests/DocumentWindowControllerCommandTests
```

Expected: the focused XCTest set passes. This step must not call `kill`, `pkill`, or `killall`.

- [ ] **Step 6: Commit only the recovery-removal stream**

Stage the exact stream-B path list above, including deletions and the two untracked test/support files. Then run:

```bash
git diff --cached --check
git diff --cached --name-only
git commit -m "refactor(app): 복구 흐름 제거"
```

Expected: no file from a later UX-polish task is staged.

- [ ] **Step 7: Confirm the new implementation baseline**

Run:

```bash
git status --short
pnpm --filter @myshottr/editor test
```

Expected: the editor suite passes and the worktree contains no unexplained delta.

## Task 1: Upgrade the Web Document Contract to Schema 3

**Files:**

- Modify: `Packages/editor/src/model/elements.ts`
- Modify: `Packages/editor/src/model/schema.ts`
- Modify: `Packages/editor/src/model/defaults.ts`
- Modify: `Packages/editor/src/model/schema.test.ts`
- Modify: `Packages/editor/src/test/fixtures.ts`
- Modify: `Packages/editor/src/bridge/protocol.test.ts`
- Modify: `Packages/editor/src/canvas/SelectionController.test.ts`

**Outcome:** The web editor accepts exact schema-3 documents, migrates schemas 1 and 2 with deterministic new defaults, and rejects malformed or future documents.

- [ ] **Step 1: Add failing schema-3 and migration tests**

Add these cases to `schema.test.ts`:

```ts
it("migrates schema 1 to schema 3 with approved new defaults", () => {
  const legacy = schemaOneFixture();

  expect(parseEditorDocument(legacy)).toMatchObject({
    schemaVersion: 3,
    presentation: { type: "none" },
    defaults: {
      rectangleFillColor: null,
      highlighterOpacity: 0.5,
    },
  });
});

it("migrates schema 2 to schema 3 without changing legacy defaults", () => {
  const legacy = schemaTwoFixture();

  expect(parseEditorDocument(legacy)).toEqual({
    ...legacy,
    schemaVersion: 3,
    defaults: {
      ...legacy.defaults,
      rectangleFillColor: null,
      highlighterOpacity: 0.5,
    },
  });
});

it("requires every schema 3 defaults key", () => {
  const current = fixtureDocument();
  const { highlighterOpacity: _removed, ...defaults } = current.defaults;

  expect(() => parseEditorDocument({ ...current, defaults })).toThrow();
});

it("rejects schema 4", () => {
  expect(() =>
    parseEditorDocument({ ...fixtureDocument(), schemaVersion: 4 }),
  ).toThrow();
});
```

Add strict bridge assertions to `protocol.test.ts` for a missing `rectangleFillColor`, an invalid fill color, a missing/invalid `highlighterOpacity`, and an extra defaults key.

- [ ] **Step 2: Run the focused tests and observe the schema-2 failures**

Run:

```bash
pnpm --filter @myshottr/editor exec vitest run \
  src/model/schema.test.ts \
  src/bridge/protocol.test.ts
```

Expected failure: schema `3` and the two new defaults fields are not accepted yet.

- [ ] **Step 3: Add the exact TypeScript types and approved defaults**

Use:

```ts
export type EditorDefaults = {
  color: PaletteColor;
  strokeWidth: 2 | 4 | 8;
  textSize: 16 | 24 | 36;
  roughness: 0 | 1 | 2;
  opacity: 0.25 | 0.5 | 0.75 | 1;
  rectangleFillColor: PaletteColor | null;
  highlighterOpacity: 0.25 | 0.5;
};

export const DEFAULT_EDITOR_DEFAULTS: EditorDefaults = {
  color: "#1677FF",
  strokeWidth: 4,
  textSize: 24,
  roughness: 1,
  opacity: 1,
  rectangleFillColor: null,
  highlighterOpacity: 0.5,
};
```

Change `EditorDocument.schemaVersion` and `createEmptyDocument()` to `3`.

- [ ] **Step 4: Split legacy and current Zod schemas**

Implement exact legacy/current defaults:

```ts
const LegacyEditorDefaultsSchema = z.object({
  color: PaletteColorSchema,
  strokeWidth: StrokeWidthSchema,
  textSize: TextSizeSchema,
  roughness: RoughnessSchema,
  opacity: OpacitySchema,
}).strict();

export const EditorDefaultsSchema = LegacyEditorDefaultsSchema.extend({
  rectangleFillColor: PaletteColorSchema.nullable(),
  highlighterOpacity: z.union([z.literal(0.25), z.literal(0.5)]),
}).strict();
```

Define:

```ts
const SchemaOneDocumentSchema = z.object({
  schemaVersion: z.literal(1),
  sourcePixelWidth: FiniteNumberSchema.positive(),
  sourcePixelHeight: FiniteNumberSchema.positive(),
  elements: z.array(EditorElementSchema),
  defaults: LegacyEditorDefaultsSchema,
}).strict();

const SchemaTwoDocumentSchema = z.object({
  schemaVersion: z.literal(2),
  sourcePixelWidth: FiniteNumberSchema.positive(),
  sourcePixelHeight: FiniteNumberSchema.positive(),
  elements: z.array(EditorElementSchema),
  presentation: PresentationSchema,
  defaults: LegacyEditorDefaultsSchema,
}).strict();
```

Keep the unique ID/z-index refinement on all accepted versions.

- [ ] **Step 5: Implement deterministic v1/v2 migration**

Use one helper:

```ts
const upgradeLegacyDefaults = (
  defaults: z.infer<typeof LegacyEditorDefaultsSchema>,
): EditorDefaults => ({
  ...defaults,
  rectangleFillColor: null,
  highlighterOpacity: 0.5,
});

export function parseEditorDocument(input: unknown): EditorDocument {
  const current = EditorDocumentSchema.safeParse(input);
  if (current.success) return current.data;

  const versionTwo = SchemaTwoDocumentSchema.safeParse(input);
  if (versionTwo.success) {
    return EditorDocumentSchema.parse({
      ...versionTwo.data,
      schemaVersion: 3,
      defaults: upgradeLegacyDefaults(versionTwo.data.defaults),
    });
  }

  const versionOne = SchemaOneDocumentSchema.safeParse(input);
  if (versionOne.success) {
    return EditorDocumentSchema.parse({
      ...versionOne.data,
      schemaVersion: 3,
      presentation: { type: "none" },
      defaults: upgradeLegacyDefaults(versionOne.data.defaults),
    });
  }

  throw current.error;
}
```

- [ ] **Step 6: Update fixtures and manually constructed documents**

Make `fixtureDocument()` schema `3` with all seven defaults keys. Add explicit `schemaOneFixture()` and `schemaTwoFixture()` helpers rather than creating structurally invalid hybrids by changing only `schemaVersion`.

Update the manually constructed document in `SelectionController.test.ts`.

- [ ] **Step 7: Re-run tests, typecheck, and commit**

Run:

```bash
pnpm --filter @myshottr/editor exec vitest run \
  src/model/schema.test.ts \
  src/bridge/protocol.test.ts \
  src/canvas/SelectionController.test.ts
pnpm --filter @myshottr/editor typecheck
git diff --check
git add Packages/editor/src/model Packages/editor/src/test/fixtures.ts Packages/editor/src/bridge/protocol.test.ts Packages/editor/src/canvas/SelectionController.test.ts
git commit -m "feat(editor): 문서 스키마 3 추가"
```

## Task 2: Make Document Defaults and Scene History Canonical

**Files:**

- Modify: `Packages/editor/src/model/history.ts`
- Modify: `Packages/editor/src/model/history.test.ts`
- Modify: `Packages/editor/src/App.tsx`
- Modify: `Packages/editor/src/App.test.tsx`
- Modify: `Packages/editor/src/canvas/tools/createElement.ts`
- Modify: `Packages/editor/src/canvas/tools/createElement.test.ts`
- Modify: `Packages/editor/src/canvas/EditorCanvas.tsx`
- Modify: `Packages/editor/src/canvas/EditorCanvas.test.tsx`

**Outcome:** `EditorDocument` is the only current document value; scene Undo/Redo changes elements only; defaults remain current, seed new elements, and never mark a clean project modified by themselves.

- [ ] **Step 1: Add failing element-only history tests**

Add:

```ts
it("keeps the latest defaults when undoing a scene command", () => {
  const store = createHistoryStore(fixtureDocument());
  store.dispatch({ type: "create", element: fixtureRectangle({ id: "new" }) });
  store.setDefaults({
    ...store.document.defaults,
    rectangleFillColor: "#FADB14",
    highlighterOpacity: 0.25,
  });

  expect(store.undo()).toBe(true);
  expect(store.document.elements).toEqual([]);
  expect(store.document.defaults.rectangleFillColor).toBe("#FADB14");
  expect(store.document.defaults.highlighterOpacity).toBe(0.25);
});

it("does not add a history entry when defaults change", () => {
  const store = createHistoryStore(fixtureDocument());

  store.setDefaults({ ...store.document.defaults, strokeWidth: 8 });

  expect(store.canUndo).toBe(false);
  expect(store.canRedo).toBe(false);
});
```

- [ ] **Step 2: Run the focused history test and observe the missing API**

Run:

```bash
pnpm --filter @myshottr/editor exec vitest run src/model/history.test.ts
```

Expected failure: `setDefaults`, `canUndo`, and `canRedo` do not exist.

- [ ] **Step 3: Store scene snapshots rather than full documents**

Change the interface:

```ts
export type HistoryStore = {
  readonly document: EditorDocument;
  readonly canUndo: boolean;
  readonly canRedo: boolean;
  readonly isTransactionActive: boolean;
  setDefaults(defaults: EditorDefaults): void;
  beginTransaction(label: string): void;
  dispatch(command: EditorCommand): void;
  commitTransaction(): void;
  cancelTransaction(): boolean;
  undo(): boolean;
  redo(): boolean;
};
```

Use:

```ts
type SceneSnapshot = EditorDocument["elements"];

const snapshotScene = (document: EditorDocument): SceneSnapshot =>
  structuredClone(document.elements);

const installScene = (
  document: EditorDocument,
  elements: SceneSnapshot,
): EditorDocument =>
  EditorDocumentSchema.parse({ ...document, elements });
```

`past`, `future`, and `transaction.startingScene` store only scenes. `setDefaults` parses `{ ...document, defaults }` without touching either history stack.

`canUndo` and `canRedo` return `false` while a transaction is active:

```ts
get canUndo() {
  return transaction === undefined && past.length > 0;
},
get canRedo() {
  return transaction === undefined && future.length > 0;
},
get isTransactionActive() {
  return transaction !== undefined;
},
```

- [ ] **Step 4: Add failing creation-default tests**

In `createElement.test.ts`, assert:

```ts
expect(
  createElement({
    tool: "rectangle",
    gesture: boxGesture,
    defaults: {
      ...DEFAULT_EDITOR_DEFAULTS,
      rectangleFillColor: "#FADB14",
    },
    nextZIndex: 0,
  }),
).toMatchObject({ type: "rectangle", fillColor: "#FADB14" });

expect(
  createElement({
    tool: "highlighter",
    gesture: pathGesture,
    defaults: {
      ...DEFAULT_EDITOR_DEFAULTS,
      opacity: 1,
      highlighterOpacity: 0.25,
    },
    nextZIndex: 0,
  }),
).toMatchObject({ type: "highlighter", opacity: 0.25 });
```

- [ ] **Step 5: Consume defaults directly in element creation**

Set:

```ts
fillColor: context.defaults.rectangleFillColor
```

for rectangles, and:

```ts
opacity: context.defaults.highlighterOpacity
```

for highlighters. Delete the old shared-opacity clamp helper.

- [ ] **Step 6: Add failing React canonical-state tests**

In `App.test.tsx`, prove:

```ts
it("publishes defaults to preferences without marking the document modified", () => {
  const onChange = vi.fn();
  const onPreferencesChange = vi.fn();
  renderEditor({ onChange, onPreferencesChange });

  chooseRectangleFill("#FADB14");

  expect(onPreferencesChange).toHaveBeenLastCalledWith(
    expect.any(String),
    expect.objectContaining({ rectangleFillColor: "#FADB14" }),
  );
  expect(onChange).not.toHaveBeenCalled();
});

it("returns the latest defaults in a later annotation snapshot", async () => {
  const bridge = renderNativeEditor();
  chooseHighlighterOpacity(0.25);

  await bridge.requestAnnotationSnapshot();

  expect(bridge.lastSnapshot()).toMatchObject({
    document: {
      schemaVersion: 3,
      defaults: { highlighterOpacity: 0.25 },
    },
  });
});
```

- [ ] **Step 7: Remove duplicated defaults and selection stores from `EditorApp`**

Remove:

```ts
const defaults = useRef(...);
const selection = useRef(createSelectionController());
const [rectangleFillColor, setRectangleFillColor] = useState(...);
```

Keep one React `document` initialized from `history.current.document` and one `selectedIds` state. `SelectionController` becomes pure functions in Task 7.

Use:

```ts
const publishSceneChange = () => {
  const nextDocument = history.current.document;
  setDocument(nextDocument);
  onChange(nextDocument);
};

const updateDefaults = (nextDefaults: EditorDefaults) => {
  history.current.setDefaults(nextDefaults);
  const nextDocument = history.current.document;
  setDocument(nextDocument);
  onPreferencesChange(tool, nextDocument.defaults);
};
```

At the native `App` boundary, keep the loaded snapshot current without sending `documentChanged`:

```ts
onPreferencesChange={(tool, defaults) => {
  const loaded = loadedDocumentRef.current;
  if (loaded) {
    loadedDocumentRef.current = {
      ...loaded,
      document: { ...loaded.document, defaults },
    };
  }
  void bridge.send("editorPreferencesChanged", { tool, defaults });
}}
```

- [ ] **Step 8: Remove the separate canvas fill prop**

Delete `rectangleFillColor` from `EditorCanvasProps`, its call sites, and tests. Pass `document.defaults` to the creation path without a fill-specific side channel.

- [ ] **Step 9: Verify the canonical state and commit**

Run:

```bash
pnpm --filter @myshottr/editor exec vitest run \
  src/model/history.test.ts \
  src/canvas/tools/createElement.test.ts \
  src/canvas/EditorCanvas.test.tsx \
  src/App.test.tsx
pnpm --filter @myshottr/editor test
pnpm --filter @myshottr/editor typecheck
git diff --check
git add Packages/editor/src
git commit -m "refactor(editor): 문서 상태와 기본값 경로 통합"
```

## Task 3: Migrate Native Last-used Preferences to v2

**Files:**

- Modify: `Sources/MyShottrApp/Preferences/EditorPreferencesStore.swift`
- Modify: `Sources/MyShottrApp/Editor/EditorBridgeEnvelope.swift`
- Modify: `Sources/MyShottrApp/Editor/EditorBridge.swift`
- Modify: `Tests/MyShottrTests/Preferences/EditorPreferencesStoreTests.swift`
- Modify: `Tests/MyShottrTests/EditorBridgePreferencesTests.swift`
- Modify: `Tests/MyShottrTests/EditorBridgeEnvelopeTests.swift`
- Modify: native fixtures that construct `EditorPreferences`

**Outcome:** Valid v1 preferences migrate once to strict v2 preferences; all seven default fields cross the Swift/WebKit bridge exactly.

- [ ] **Step 1: Add failing preference migration tests**

Add:

```swift
func testMigratesValidVersionOnePreferencesAndPersistsVersionTwo() throws {
    let defaults = makeIsolatedUserDefaults()
    defaults.set(
        try JSONSerialization.data(withJSONObject: [
            "tool": "rectangle",
            "color": "#FF4D4F",
            "strokeWidth": 8,
            "textSize": 36,
            "roughness": 2,
            "opacity": 0.75,
        ]),
        forKey: EditorPreferences.legacyStorageKey
    )

    let result = UserDefaultsEditorPreferencesStore(defaults: defaults).load()

    XCTAssertEqual(result.rectangleFillColor, nil)
    XCTAssertEqual(result.highlighterOpacity, 0.5)
    XCTAssertNotNil(defaults.data(forKey: EditorPreferences.storageKey))
}

func testInvalidVersionTwoDoesNotFallBackToVersionOne() throws {
    let defaults = makeIsolatedUserDefaults()
    defaults.set(Data("{}".utf8), forKey: EditorPreferences.storageKey)
    defaults.set(validVersionOneData(), forKey: EditorPreferences.legacyStorageKey)

    XCTAssertEqual(
        UserDefaultsEditorPreferencesStore(defaults: defaults).load(),
        .approvedDefaults
    )
}
```

Also assert that encoded v2 JSON contains `"rectangleFillColor": null` rather than omitting the key.

- [ ] **Step 2: Run the focused preference tests and observe the missing v2 contract**

Run:

```bash
xcodegen generate
xcodebuild test \
  -project MyShottr.xcodeproj \
  -scheme MyShottr \
  -destination "platform=macOS" \
  CODE_SIGNING_ALLOWED=NO \
  -only-testing:MyShottrTests/EditorPreferencesStoreTests
```

- [ ] **Step 3: Implement the exact v2 value and validator**

Use:

```swift
struct EditorPreferences: Codable, Equatable, Sendable {
    static let storageKey = "editorPreferences.v2"
    static let legacyStorageKey = "editorPreferences.v1"
    static let approvedDefaults = EditorPreferences(
        tool: "selection",
        color: "#1677FF",
        strokeWidth: 4,
        textSize: 24,
        roughness: 1,
        opacity: 1,
        rectangleFillColor: nil,
        highlighterOpacity: 0.5
    )

    var tool: String
    var color: String
    var strokeWidth: Int
    var textSize: Int
    var roughness: Int
    var opacity: Double
    var rectangleFillColor: String?
    var highlighterOpacity: Double
}
```

Its `isValid` must accept `nil` or one approved palette color for fill and exactly `0.25` or `0.5` for highlighter opacity.

Give `EditorPreferences` a custom encoder that calls:

```swift
if let rectangleFillColor {
    try container.encode(rectangleFillColor, forKey: .rectangleFillColor)
} else {
    try container.encodeNil(forKey: .rectangleFillColor)
}
```

- [ ] **Step 4: Implement strict v2-first, v1-second loading**

Use a private legacy value:

```swift
private struct LegacyEditorPreferences: Codable {
    var tool: String
    var color: String
    var strokeWidth: Int
    var textSize: Int
    var roughness: Int
    var opacity: Double
}
```

Before decoding either version, use `JSONSerialization` to compare exact key sets. The load order is:

1. v2 exists: strict decode/validate it; invalid means `.approvedDefaults`.
2. v2 absent and exact valid v1 exists: add `nil`/`0.5`, save v2, return it.
3. v1 missing or invalid: `.approvedDefaults`.

Do not delete the v1 key.

- [ ] **Step 5: Add failing strict preference-envelope tests**

Test the exact payload:

```swift
[
    "tool": "rectangle",
    "defaults": [
        "color": "#FF4D4F",
        "strokeWidth": 8,
        "textSize": 36,
        "roughness": 2,
        "opacity": 0.75,
        "rectangleFillColor": NSNull(),
        "highlighterOpacity": 0.25,
    ],
]
```

Add rejection tests for a missing key, extra key, invalid fill string, non-null/non-string fill, and highlighter opacity `0.75`.

- [ ] **Step 6: Extend strict Swift bridge parsing**

In `EditorBridgeEnvelope.swift`, require:

```swift
Set(defaults.keys) == [
    "color",
    "strokeWidth",
    "textSize",
    "roughness",
    "opacity",
    "rectangleFillColor",
    "highlighterOpacity",
]
```

Accept fill only when:

```swift
defaults["rectangleFillColor"] == .null
    || validPaletteString(defaults["rectangleFillColor"])
```

In `EditorBridge.installPreferences`, decode `.null` to `nil`, decode a valid string to that string, and require highlighter opacity `0.25` or `0.5`.

- [ ] **Step 7: Update native preference fixtures and run focused tests**

Run:

```bash
xcodebuild test \
  -project MyShottr.xcodeproj \
  -scheme MyShottr \
  -destination "platform=macOS" \
  CODE_SIGNING_ALLOWED=NO \
  -only-testing:MyShottrTests/EditorPreferencesStoreTests \
  -only-testing:MyShottrTests/EditorBridgePreferencesTests \
  -only-testing:MyShottrTests/EditorBridgeEnvelopeTests
```

- [ ] **Step 8: Commit native preference v2**

Run:

```bash
git diff --check
git add Sources/MyShottrApp/Preferences/EditorPreferencesStore.swift Sources/MyShottrApp/Editor/EditorBridgeEnvelope.swift Sources/MyShottrApp/Editor/EditorBridge.swift Tests/MyShottrTests
git commit -m "feat(preferences): 편집 기본값 v2 마이그레이션 추가"
```

## Task 4: Centralize Native Schema-3 Migration and Validation

**Files:**

- Create: `Sources/MyShottrApp/Documents/EditorDocumentValidator.swift`
- Create: `Tests/MyShottrTests/Documents/EditorDocumentValidatorTests.swift`
- Modify: `Sources/MyShottrApp/Documents/EditorDocumentMigrator.swift`
- Modify: `Sources/MyShottrApp/Documents/DocumentSession.swift`
- Modify: `Sources/MyShottrApp/Documents/ProjectPackageStore.swift`
- Modify: `Sources/MyShottrApp/Documents/NewProjectFactory.swift`
- Modify: `Sources/MyShottrApp/Editor/EditorBridgeEnvelope.swift`
- Modify: `Tests/MyShottrTests/Documents/EditorDocumentMigratorTests.swift`
- Modify: `Tests/MyShottrTests/Documents/DocumentSessionTests.swift`
- Modify: `Tests/MyShottrTests/Documents/NewProjectFactoryTests.swift`
- Modify: `Tests/MyShottrTests/ProjectPackageStoreTests.swift`
- Modify: `Tests/MyShottrTests/EditorBridgeEnvelopeTests.swift`
- Modify: `Tests/MyShottrTests/EditorBridgeCompositeTransferTests.swift`
- Modify: `Tests/MyShottrTests/EditorWebViewRuntimeTests.swift`
- Modify: `Tests/MyShottrTests/Chrome/CaptureInboxCoordinatorTests.swift`
- Modify: `Tests/MyShottrTests/Support/ProjectFixtures.swift`

**Outcome:** Every native entry point shares one exact schema-3 validator; v1/v2 packages migrate in memory; new projects and saves emit only validated v3.

- [ ] **Step 1: Replace ambiguous fixtures with explicit version fixtures**

In `ProjectFixtures.swift`, provide:

```swift
static func schemaOneAnnotationJSON() throws -> Data
static func schemaTwoAnnotationJSON() throws -> Data
static func currentAnnotationJSON() throws -> Data
static func futureAnnotationJSON(version: Int = 4) throws -> Data
```

Their shapes are exact:

- v1: no `presentation`, five legacy defaults.
- v2: `presentation: none`, five legacy defaults.
- v3: `presentation: none`, seven current defaults.
- future: a structurally current body with only its version changed.

- [ ] **Step 2: Add failing migration tests**

Add:

```swift
func testMigratesVersionTwoDefaultsToVersionThree() throws {
    let migrated = try EditorDocumentMigrator.migrate(
        ProjectFixtures.schemaTwoAnnotationJSON()
    )
    let object = try XCTUnwrap(
        JSONSerialization.jsonObject(with: migrated) as? [String: Any]
    )
    let defaults = try XCTUnwrap(object["defaults"] as? [String: Any])

    XCTAssertEqual(object["schemaVersion"] as? Int, 3)
    XCTAssertTrue(defaults["rectangleFillColor"] is NSNull)
    XCTAssertEqual(defaults["highlighterOpacity"] as? Double, 0.5)
}

func testRejectsVersionFour() throws {
    XCTAssertThrowsError(
        try EditorDocumentMigrator.migrate(
            ProjectFixtures.futureAnnotationJSON()
        )
    )
}
```

Add equivalent v1→v3 and exact v3 pass-through assertions.

- [ ] **Step 3: Implement the native migrator**

Use:

```swift
switch version {
case 1:
    object["presentation"] = ["type": "none"]
    fallthrough
case 2:
    guard var defaults = object["defaults"] as? [String: Any] else {
        throw EditorDocumentMigrationError.malformedDocument
    }
    defaults["rectangleFillColor"] = NSNull()
    defaults["highlighterOpacity"] = 0.5
    object["defaults"] = defaults
    object["schemaVersion"] = 3
case 3:
    break
default:
    throw EditorDocumentMigrationError.unsupportedVersion(version)
}
```

The schema-3 validator in the next step determines whether a v3 body is actually valid.

- [ ] **Step 4: Add failing strict validator tests**

Create tests for:

- exact current document acceptance;
- missing and extra top-level/default keys;
- invalid/null/extra fill values;
- invalid highlighter opacity;
- non-positive or mismatched source dimensions;
- duplicate IDs and duplicate z-indices;
- invalid exact element keys;
- unsupported element type;
- non-finite numeric values.

- [ ] **Step 5: Extract the shared current-document validator**

Create:

```swift
enum EditorDocumentValidator {
    static func validate(
        _ data: Data,
        expectedPixelWidth: Int? = nil,
        expectedPixelHeight: Int? = nil
    ) throws
}
```

It accepts only schema `3`, exact top-level keys, `presentation.type == "none"`, exact seven-key defaults, the approved discrete values, exact per-element keys, unique non-empty IDs, and unique finite z-indices.

Move validation helpers out of `DocumentSession` rather than duplicating them.

- [ ] **Step 6: Route every native document boundary through the validator**

Implement these rules:

- `DocumentSession` delegates validation and maps errors to `.invalidDocument`.
- `ProjectPackageStore.load` migrates first, then validates against manifest dimensions.
- `ProjectPackageStore.save` validates current v3 and rejects v1/v2 input.
- `EditorBridgeEnvelope` serializes the `annotationSnapshot.document` object to `Data` and invokes the validator.
- `NewProjectFactory` emits schema `3` and all seven defaults from `EditorPreferences`.

Use this exact factory body fragment:

```swift
"schemaVersion": 3,
"defaults": [
    "color": preferences.color,
    "strokeWidth": preferences.strokeWidth,
    "textSize": preferences.textSize,
    "roughness": preferences.roughness,
    "opacity": preferences.opacity,
    "rectangleFillColor": preferences.rectangleFillColor ?? NSNull(),
    "highlighterOpacity": preferences.highlighterOpacity,
],
```

- [ ] **Step 7: Update hard-coded native schema fixtures**

Update inline valid documents in bridge composite/runtime tests and the capture-inbox expected version. Keep every invalid fixture otherwise valid so each test fails for its named reason.

- [ ] **Step 8: Run focused native tests**

Run:

```bash
xcodegen generate
xcodebuild test \
  -project MyShottr.xcodeproj \
  -scheme MyShottr \
  -destination "platform=macOS" \
  CODE_SIGNING_ALLOWED=NO \
  -only-testing:MyShottrTests/EditorDocumentMigratorTests \
  -only-testing:MyShottrTests/EditorDocumentValidatorTests \
  -only-testing:MyShottrTests/ProjectPackageStoreTests \
  -only-testing:MyShottrTests/NewProjectFactoryTests \
  -only-testing:MyShottrTests/DocumentSessionTests \
  -only-testing:MyShottrTests/CaptureInboxCoordinatorTests \
  -only-testing:MyShottrTests/EditorBridgeEnvelopeTests
```

- [ ] **Step 9: Commit native schema 3**

Run:

```bash
git diff --check
git add Sources/MyShottrApp/Documents Sources/MyShottrApp/Editor/EditorBridgeEnvelope.swift Tests/MyShottrTests
git commit -m "feat(documents): 스키마 3 검증과 마이그레이션 통합"
```

## Task 5: Extend the Strict Bridge-v1 Message Contract

**Files:**

- Modify: `Packages/editor/src/bridge/protocol.ts`
- Modify: `Packages/editor/src/bridge/protocol.test.ts`
- Modify: `Sources/MyShottrApp/Editor/EditorBridgeEnvelope.swift`
- Modify: `Tests/MyShottrTests/EditorBridgeEnvelopeTests.swift`

**Outcome:** Both sides strictly encode/decode the three approved additive messages without changing protocol version or weakening existing correlated request behavior.

- [ ] **Step 1: Add failing TypeScript protocol matrix tests**

Add valid cases:

```ts
expect(
  EditorToNativeEnvelopeSchema.parse({
    protocolVersion: 1,
    requestId: UUID,
    type: "historyStateChanged",
    payload: { canUndo: true, canRedo: false },
  }),
).toBeTruthy();

expect(
  NativeToEditorEnvelopeSchema.parse({
    protocolVersion: 1,
    requestId: UUID,
    type: "performHistoryAction",
    payload: { action: "undo" },
  }),
).toBeTruthy();
```

Table-test all `operationStatus` variants and reject:

- Export `superseded`;
- Save `completed` with `displayName`;
- Export `completed` without `displayName`;
- `started`, `cancelled`, or `failed` with `displayName`;
- unknown phase/action;
- every extra key.

- [ ] **Step 2: Run the focused protocol test and observe unknown-message failures**

Run:

```bash
pnpm --filter @myshottr/editor exec vitest run src/bridge/protocol.test.ts
```

- [ ] **Step 3: Add strict TypeScript schemas**

Use:

```ts
const HistoryStateChangedPayloadSchema = z.object({
  canUndo: z.boolean(),
  canRedo: z.boolean(),
}).strict();

const PerformHistoryActionPayloadSchema = z.object({
  action: z.enum(["undo", "redo"]),
}).strict();

const OperationStatusPayloadSchema = z.discriminatedUnion("phase", [
  z.object({
    operation: z.enum(["save", "export"]),
    phase: z.literal("started"),
  }).strict(),
  z.object({
    operation: z.literal("save"),
    phase: z.literal("completed"),
  }).strict(),
  z.object({
    operation: z.literal("save"),
    phase: z.literal("superseded"),
  }).strict(),
  z.object({
    operation: z.literal("export"),
    phase: z.literal("completed"),
    displayName: z.string(),
  }).strict(),
  z.object({
    operation: z.enum(["save", "export"]),
    phase: z.enum(["cancelled", "failed"]),
  }).strict(),
]);
```

Add `historyStateChanged` to editor→native and `performHistoryAction` plus `operationStatus` to native→editor. Keep existing `saveCompleted`/`saveFailed` decode compatibility, but do not use them in the new state machine.

- [ ] **Step 4: Add failing Swift exact-key tests**

Cover all valid variants and the same invalid matrix as TypeScript. Assert that all states of one operation keep the envelope `requestId`; do not introduce a payload operation ID.

- [ ] **Step 5: Add Swift domain types and exact validation**

Use:

```swift
struct EditorHistoryState: Equatable, Sendable {
    let canUndo: Bool
    let canRedo: Bool
}

enum EditorHistoryAction: String, Equatable, Sendable {
    case undo
    case redo
}

enum EditorOutputOperation: String, Equatable, Sendable {
    case save
    case export
}

enum EditorOperationStatus: Equatable, Sendable {
    case started(EditorOutputOperation)
    case saveCompleted
    case saveSuperseded
    case exportCompleted(displayName: String)
    case cancelled(EditorOutputOperation)
    case failed(EditorOutputOperation)
}
```

Extend `NativeToEditorMessageType` with `.performHistoryAction` and `.operationStatus`; extend `EditorToNativeMessageType` with `.historyStateChanged`. Validate exact keys in the existing strict envelope switch.

- [ ] **Step 6: Run both protocol suites and commit**

Run:

```bash
pnpm --filter @myshottr/editor exec vitest run src/bridge/protocol.test.ts
xcodebuild test \
  -project MyShottr.xcodeproj \
  -scheme MyShottr \
  -destination "platform=macOS" \
  CODE_SIGNING_ALLOWED=NO \
  -only-testing:MyShottrTests/EditorBridgeEnvelopeTests
git diff --check
git add Packages/editor/src/bridge Sources/MyShottrApp/Editor/EditorBridgeEnvelope.swift Tests/MyShottrTests/EditorBridgeEnvelopeTests.swift
git commit -m "feat(bridge): 히스토리와 출력 상태 계약 추가"
```

## Task 6: Build One Shortcut Registry, Router, Palette, and Help Dialog

**Files:**

- Create: `Packages/editor/src/input/shortcutRegistry.ts`
- Create: `Packages/editor/src/input/ShortcutRouter.ts`
- Create: `Packages/editor/src/input/ShortcutRouter.test.ts`
- Modify: `Packages/editor/src/canvas/tools/ToolController.ts`
- Create: `Packages/editor/src/components/ShortcutHelpDialog.tsx`
- Create: `Packages/editor/src/components/ShortcutHelpDialog.test.tsx`
- Modify: `Packages/editor/src/components/FloatingToolPalette.tsx`
- Modify: `Packages/editor/src/App.tsx`
- Modify: `Packages/editor/src/App.test.tsx`
- Modify: `Packages/editor/src/canvas/tools/createElement.test.ts`
- Modify: `Packages/editor/src/styles.css`

**Outcome:** One data registry drives key matching, visible tool hints, tooltips, and the help dialog; keyboard behavior is input-source independent and respects native ownership.

- [ ] **Step 1: Add failing router tests for the complete contract**

Table-test:

```ts
const toolCases = [
  ["KeyV", "selection"],
  ["KeyR", "rectangle"],
  ["KeyA", "arrow"],
  ["KeyL", "line"],
  ["KeyT", "text"],
  ["KeyP", "freehand"],
  ["KeyH", "highlighter"],
  ["KeyB", "blur"],
  ["KeyX", "redaction"],
  ["KeyN", "numberMarker"],
] as const;

it.each(toolCases)("maps %s by code", (code, tool) => {
  expect(commandFor({ code })).toEqual({ type: "selectTool", tool });
});
```

Also assert:

- `Shift+Digit1` → Fit Image;
- `Shift+Digit2` → Fit Selection;
- `Shift+Slash` → Shortcut Help;
- `Command+Digit0` → 100%;
- `Command+Y` → no command;
- native Copy/Save/Export → no web command and no `preventDefault`;
- composing, input, textarea, select, and any contenteditable descendant → suppressed;
- active gesture → only Escape;
- open help dialog → only Escape;
- inline text → element Copy/Paste and tool keys suppressed.

- [ ] **Step 2: Run the router tests and observe failures in the current `event.key` path**

Run:

```bash
pnpm --filter @myshottr/editor exec vitest run src/input/ShortcutRouter.test.ts
```

- [ ] **Step 3: Define one registry with explicit ownership**

Use:

```ts
export type ShortcutOwner = "web" | "native";
export type ShortcutGroup =
  | "Tools"
  | "Edit and Selection"
  | "View and Navigation"
  | "Output";

export type ShortcutDefinition = {
  id: string;
  owner: ShortcutOwner;
  group: ShortcutGroup;
  label: string;
  displayKeys: readonly string[];
  tool?: EditorTool;
  matches(event: KeyboardEvent): boolean;
};

export const SHORTCUT_REGISTRY: readonly ShortcutDefinition[] = [
  {
    id: "tool-selection",
    owner: "web",
    group: "Tools",
    label: "Selection",
    displayKeys: ["V"],
    tool: "selection",
    matches: (event) => event.code === "KeyV" && !event.metaKey,
  },
  {
    id: "output-copy-image",
    owner: "native",
    group: "Output",
    label: "Copy Image",
    displayKeys: ["⌘", "⇧", "C"],
    matches: (event) =>
      event.code === "KeyC" && event.metaKey && event.shiftKey,
  },
];
```

Complete the registry with every approved tool, edit, view, and output shortcut. There must be one entry per displayed behavior and no `Command-Y` entry.

- [ ] **Step 4: Implement suppression and code-based command routing**

Use:

```ts
export const isTextEntryTarget = (target: EventTarget | null): boolean => {
  if (!(target instanceof Element)) return false;
  return target.matches("input, textarea, select, [contenteditable]")
    || target.closest("[contenteditable]") !== null;
};

export function keyboardCommandFor(
  event: KeyboardEvent,
  context: ShortcutContext,
): EditorShortcutCommand | undefined {
  if (event.isComposing || isTextEntryTarget(event.target)) return undefined;
  if (context.interactionActive && event.code !== "Escape") return undefined;
  if ((context.textEditing || context.shortcutHelpOpen)
      && event.code !== "Escape") {
    return undefined;
  }

  const definition = SHORTCUT_REGISTRY.find((entry) => entry.matches(event));
  if (!definition || definition.owner === "native") return undefined;
  return commandFromDefinition(definition, event);
}
```

Keep Escape priority execution in `EditorApp`, where live state is available; the router returns only `{ type: "escape" }`.

- [ ] **Step 5: Add failing palette and help-dialog accessibility tests**

Assert:

```ts
expect(
  screen.getByRole("button", { name: "Rectangle, shortcut R" }),
).toHaveAttribute("aria-pressed", "true");

expect(screen.getByText("R").tagName).toBe("KBD");
expect(screen.getByText("R")).toHaveAttribute("aria-hidden", "true");
```

For the dialog, test role/modal state, close-button initial focus, Tab/Shift-Tab trapping, Escape close, and restoration to the element focused before opening.

- [ ] **Step 6: Render visible hints and focus/hover tooltips from the registry**

Use:

```tsx
<button
  aria-label={`${entry.label}, shortcut ${entry.displayKeys[0]}`}
  aria-pressed={tool === entry.tool}
  aria-describedby={`tool-tip-${entry.tool}`}
>
  <ToolIcon tool={entry.tool} />
  <kbd aria-hidden="true">{entry.displayKeys[0]}</kbd>
  <span role="tooltip" id={`tool-tip-${entry.tool}`}>
    {entry.label} · {entry.displayKeys[0]}
  </span>
</button>
```

The tooltip must become visible on both `:hover` and `:focus-visible`.

- [ ] **Step 7: Build `ShortcutHelpDialog` from the same registry**

Group `SHORTCUT_REGISTRY` by `group`; do not duplicate shortcut label arrays in the component. Output shortcuts appear in the dialog even though the web router never executes them.

- [ ] **Step 8: Integrate Escape priority and tool-specific cursors**

Execute exactly one first-applicable rule:

```ts
if (shortcutHelpOpen) closeShortcutHelp();
else if (textEditSession) cancelTextEdit();
else if (interactionController.active) cancelInteraction();
else if (tool !== "selection") setTool("selection");
else setSelectedIds([]);
```

Map selection to `default`, text to `text`, all drawing tools to `crosshair`, Space-ready to `grab`, and active Space-pan to `grabbing`.

- [ ] **Step 9: Run focused tests, full editor tests, and commit**

Run:

```bash
pnpm --filter @myshottr/editor exec vitest run \
  src/input/ShortcutRouter.test.ts \
  src/components/ShortcutHelpDialog.test.tsx \
  src/App.test.tsx
pnpm --filter @myshottr/editor test
pnpm --filter @myshottr/editor typecheck
git diff --check
git add Packages/editor/src
git commit -m "feat(editor): 단축키 레지스트리와 도움말 추가"
```

## Task 7: Replace the Form Palette with the Derived Context Rail

**Files:**

- Create: `Packages/editor/src/components/contextRailModel.ts`
- Create: `Packages/editor/src/components/contextRailModel.test.ts`
- Create: `Packages/editor/src/components/ContextRail.tsx`
- Create: `Packages/editor/src/components/ContextRail.test.tsx`
- Delete: `Packages/editor/src/components/ContextStylePalette.tsx`
- Delete: `Packages/editor/src/components/ContextStylePalette.test.tsx`
- Modify: `Packages/editor/src/App.tsx`
- Modify: `Packages/editor/src/App.test.tsx`
- Modify: `Packages/editor/src/model/reducer.ts`
- Modify: `Packages/editor/src/model/history.test.ts`
- Modify: `Packages/editor/src/canvas/EditorCanvas.tsx`
- Modify: `Packages/editor/src/export/renderDocumentToBlob.ts`
- Modify: `Packages/editor/src/export/renderDocumentToBlob.test.ts`
- Modify: `Packages/editor/src/styles.css`

**Outcome:** The 248-point left rail derives hidden/default/single/multi/mixed state from canonical data, emits semantic intents, and never infers a multi-selection value from the first element.

- [ ] **Step 1: Add failing pure-model tests**

Cover:

```ts
it("is hidden for Selection with no selection", () => {
  expect(deriveContextRailModel({
    tool: "selection",
    document: fixtureDocument(),
    selectedIds: [],
  })).toEqual({ kind: "hidden" });
});

it("shows new Rectangle defaults with fill", () => {
  expect(deriveContextRailModel({
    tool: "rectangle",
    document: fixtureDocument({
      defaults: {
        ...DEFAULT_EDITOR_DEFAULTS,
        rectangleFillColor: "#FADB14",
      },
    }),
    selectedIds: [],
  })).toMatchObject({
    kind: "defaults",
    title: "New Rectangle",
    fields: {
      fillColor: { value: { kind: "single", value: "#FADB14" } },
    },
  });
});
```

Add table cases for:

- single Rectangle;
- fixed Blur and Redaction values;
- same-type multi-selection with a mixed field;
- Rectangle + Text property intersection;
- Rectangle + Blur hiding unsupported shared fields;
- allowed-value domain intersection;
- every field: color, fill, width, roughness, text size, opacity;
- reorder action enablement at z-order edges.

- [ ] **Step 2: Run the model test and observe the missing rail**

Run:

```bash
pnpm --filter @myshottr/editor exec vitest run src/components/contextRailModel.test.ts
```

- [ ] **Step 3: Implement property support and intersection as pure data**

Use:

```ts
export type RailPropertyKey =
  | "color"
  | "fillColor"
  | "strokeWidth"
  | "roughness"
  | "textSize"
  | "opacity";

export type RailValue<T> =
  | { kind: "single"; value: T }
  | { kind: "mixed" };

const commonKeys = (
  selected: readonly EditorElement[],
): RailPropertyKey[] =>
  ALL_PROPERTY_KEYS.filter((key) =>
    selected.every((element) => supportsProperty(element, key)),
  );

const deriveValue = <T>(values: readonly T[]): RailValue<T> =>
  values.every((value) => Object.is(value, values[0]))
    ? { kind: "single", value: values[0] }
    : { kind: "mixed" };
```

For each shared field, intersect the selected types' allowed values. Do not expose a field when the resulting domain is empty.

- [ ] **Step 4: Add failing direct-control tests**

Test DOM semantics:

- swatches use `radiogroup`/`radio` or `aria-pressed` buttons;
- segmented controls expose a label and selected state;
- mixed fields show visible `Mixed` text and an accessible mixed description;
- discrete opacity slider exposes min/max/step/value text;
- icon-only actions have exact accessible names;
- defaults mode has no selection actions;
- selection mode has Forward, Backward, Duplicate, Delete.

Assert one semantic intent per activation:

```ts
expect(onIntent).toHaveBeenCalledWith({
  type: "setSelectionProperty",
  property: "strokeWidth",
  value: 8,
});
expect(onIntent).toHaveBeenCalledTimes(1);
```

- [ ] **Step 5: Render direct controls with no `<select>`**

Implement `ContextRail` as a pure view of `ContextRailModel`. It owns only short-lived DOM focus/slider gesture state; it does not copy selected values into component state.

Use exact geometry:

```css
.context-rail {
  position: absolute;
  inset-block-start: 76px;
  inset-inline-start: 16px;
  inline-size: 248px;
  max-block-size: calc(100% - 92px);
  overflow-y: auto;
  padding: 12px;
  gap: 12px;
}
```

- [ ] **Step 6: Route rail intents to one semantic document command**

For a selection property:

```ts
const updated = applyRailProperty(selectedElements, property, value);
history.current.dispatch({ type: "updateMany", elements: updated });
publishSceneChange();
```

For defaults, call only `updateDefaults`.

For a selected-element opacity slider:

- `input`: update an ephemeral preview and set `locks.slider = true`;
- release/change: dispatch one `updateMany`, clear preview and lock;
- cancel/Escape: discard preview, clear lock, no history.

- [ ] **Step 7: Add Duplicate/Delete/Forward/Backward actions**

Use existing reducer commands for delete and reorder. Duplicate delegates to the shared primitive introduced in Task 10; until Task 10 lands, expose the semantic callback without adding a second duplication algorithm.

- [ ] **Step 8: Make canvas and export use the same global z-order**

Replace type bands with:

```ts
const orderedElements = [...document.elements].sort(
  (left, right) => left.zIndex - right.zIndex,
);
```

Use this order in both `EditorCanvas` and `renderDocumentToBlob`. Refactor export so the one ordered loop dispatches blur drawing when it reaches a blur element; do not run a separate blur pass.

Add an export test with interleaved Rectangle/Blur/Highlighter z-indices and assert draw calls follow z-index exactly.

- [ ] **Step 9: Delete the old palette and integrate the rail**

Remove imports, styles, and tests for `ContextStylePalette`. Do not keep a compatibility adapter or a hidden duplicate.

- [ ] **Step 10: Verify rail state, export order, and commit**

Run:

```bash
pnpm --filter @myshottr/editor exec vitest run \
  src/components/contextRailModel.test.ts \
  src/components/ContextRail.test.tsx \
  src/model/history.test.ts \
  src/export/renderDocumentToBlob.test.ts \
  src/App.test.tsx
pnpm --filter @myshottr/editor typecheck
git diff --check
git add Packages/editor/src
git commit -m "feat(editor): Context Rail과 전역 레이어 순서 추가"
```

## Task 8: Replace the Image-sized Stage with `ViewportController`

**Files:**

- Create: `Packages/editor/src/viewport/ViewportController.ts`
- Create: `Packages/editor/src/viewport/ViewportController.test.ts`
- Delete: `Packages/editor/src/canvas/CanvasViewport.ts`
- Delete: `Packages/editor/src/canvas/CanvasViewport.test.ts`
- Create: `Packages/editor/src/components/EditorWorkspace.tsx`
- Create: `Packages/editor/src/components/EditorWorkspace.test.tsx`
- Modify: `Packages/editor/src/canvas/EditorCanvas.tsx`
- Modify: `Packages/editor/src/canvas/EditorCanvas.test.tsx`
- Modify: `Packages/editor/src/components/ZoomControls.tsx`
- Create: `Packages/editor/src/components/ZoomControls.test.tsx`
- Modify: `Packages/editor/src/App.tsx`
- Modify: `Packages/editor/src/App.test.tsx`
- Modify: `Packages/editor/src/styles.css`

**Outcome:** One measured full-workspace Stage owns source/workspace transforms, 10–800% zoom, pointer-anchored zoom, wheel/trackpad pan, fit commands, bounded pan, and Context Rail reflow.

- [ ] **Step 1: Add failing pure viewport tests**

Use:

```ts
it("keeps the source point under the pointer while zooming", () => {
  const controller = fixtureViewport();
  const pointer = { x: 640, y: 430 };
  const sourceBefore = controller.toSourcePoint(pointer);

  controller.zoomAt(pointer, 2.4);

  expect(controller.toSourcePoint(pointer)).toEqualPoint(sourceBefore);
});

it("keeps zoom and centers the previous source point after rail reflow", () => {
  const controller = fixtureViewport();
  const before = controller.snapshot;
  const centeredSource = controller.toSourcePoint(center(before.availableRect));

  controller.setWorkspace(workspaceWithRail(), {
    preserveCenteredSourcePoint: true,
  });

  expect(controller.snapshot.zoom).toBe(before.zoom);
  expect(
    controller.toSourcePoint(center(controller.snapshot.availableRect)),
  ).toEqualPoint(centeredSource);
});
```

Add min/max, 10-percentage-point steps, small-axis centering, large-axis clamps, 100%, Fit Image, Fit Selection, 24-point padding, and empty-selection no-op cases.

- [ ] **Step 2: Run the viewport tests and observe the missing controller**

Run:

```bash
pnpm --filter @myshottr/editor exec vitest run src/viewport/ViewportController.test.ts
```

- [ ] **Step 3: Implement the pure viewport API**

Use:

```ts
export const MIN_ZOOM = 0.1;
export const MAX_ZOOM = 8;
export const FIT_PADDING = 24;
export const RAIL_REFLOW_DURATION_MS = 160;

export class ViewportController {
  constructor(
    private readonly source: Size,
    initial: { workspace: Size; availableRect: Rect },
  ) {}

  get snapshot(): ViewportSnapshot;
  toSourcePoint(workspacePoint: Point): Point;
  toWorkspacePoint(sourcePoint: Point): Point;
  setWorkspace(
    metrics: { workspace: Size; availableRect: Rect },
    options: { preserveCenteredSourcePoint: boolean },
  ): ViewportSnapshot;
  zoomAt(workspacePoint: Point, zoom: number): ViewportSnapshot;
  panBy(delta: Point): ViewportSnapshot;
  set100Percent(): ViewportSnapshot;
  fitImage(padding = FIT_PADDING): ViewportSnapshot;
  fitSelection(bounds: Rect, padding = FIT_PADDING): ViewportSnapshot;
}
```

Clamp after every mutation:

```ts
const clampAxis = (
  availableStart: number,
  availableSize: number,
  transformedSize: number,
  proposedPan: number,
): number =>
  transformedSize <= availableSize
    ? availableStart + (availableSize - transformedSize) / 2
    : clamp(
        proposedPan,
        availableStart + availableSize - transformedSize,
        availableStart,
      );
```

- [ ] **Step 4: Add failing workspace measurement tests**

Mock `ResizeObserver` and assert:

- Stage width/height equal the full web-content rectangle;
- no rail uses the full safe canvas rectangle;
- visible rail reserves its 248 width plus insets/gap;
- reflow calls `setWorkspace(...preserveCenteredSourcePoint: true)`;
- reduced motion applies immediately;
- ordinary motion applies only pan interpolation for 160 ms and leaves zoom fixed.

- [ ] **Step 5: Build `EditorWorkspace` and full-size Stage**

Render:

```tsx
<Stage
  width={viewport.workspace.width}
  height={viewport.workspace.height}
>
  <Layer>
    <Group
      x={viewport.pan.x}
      y={viewport.pan.y}
      scaleX={viewport.zoom}
      scaleY={viewport.zoom}
    >
      {sourceAndAnnotations}
    </Group>
  </Layer>
</Stage>
```

The Stage never uses `sourcePixelWidth * zoom` as its DOM size.

- [ ] **Step 6: Route wheel, pinch, Space-pan, buttons, and fit shortcuts**

For wheel:

```ts
if (event.evt.metaKey || event.evt.ctrlKey) {
  event.evt.preventDefault();
  viewport.zoomAt(pointer, zoomFromWheel(event.evt.deltaY));
} else {
  event.evt.preventDefault();
  viewport.panBy({
    x: -event.evt.deltaX,
    y: -event.evt.deltaY,
  });
}
```

Space must be held before pointer-down to start pan. Delete every Shift-pan path and replace its tests.

`ZoomControls` emits semantic `zoomIn`, `zoomOut`, `zoom100`, `fitImage`, and `fitSelection` intents; only `ViewportController` calculates values.

- [ ] **Step 7: Verify viewport integration and commit**

Run:

```bash
pnpm --filter @myshottr/editor exec vitest run \
  src/viewport/ViewportController.test.ts \
  src/components/EditorWorkspace.test.tsx \
  src/components/ZoomControls.test.tsx \
  src/canvas/EditorCanvas.test.tsx \
  src/App.test.tsx
pnpm --filter @myshottr/editor test
pnpm --filter @myshottr/editor typecheck
git diff --check
git add Packages/editor/src
git commit -m "feat(editor): 측정형 viewport와 pan zoom 추가"
```

## Task 9: Introduce One Pointer Lifecycle and Continuous Creation Preview

**Files:**

- Create: `Packages/editor/src/interaction/InteractionController.ts`
- Create: `Packages/editor/src/interaction/InteractionController.test.ts`
- Create: `Packages/editor/src/interaction/geometry.ts`
- Create: `Packages/editor/src/interaction/geometry.test.ts`
- Modify: `Packages/editor/src/canvas/EditorCanvas.tsx`
- Modify: `Packages/editor/src/canvas/EditorCanvas.test.tsx`
- Modify: `Packages/editor/src/canvas/tools/createElement.ts`
- Modify: `Packages/editor/src/canvas/tools/createElement.test.ts`
- Modify: `Packages/editor/src/canvas/renderElement.tsx`
- Modify: `Packages/editor/src/canvas/renderElement.test.tsx`
- Modify: `Packages/editor/src/App.tsx`
- Modify: `Packages/editor/src/App.test.tsx`

**Outcome:** Pointer-down snapshots all gesture inputs, pointer-move updates only an animation-frame-bounded preview, pointer-up emits at most one semantic command, and cancel emits none.

- [ ] **Step 1: Convert the existing live-preview assertion into a tool matrix**

Preserve the approved dirty-baseline behavior and extend it:

```ts
it.each([
  "rectangle",
  "arrow",
  "line",
  "freehand",
  "highlighter",
  "blur",
  "redaction",
] as const)(
  "previews %s without changing the document",
  (tool) => {
    const onCommand = vi.fn();
    const screen = renderCanvas({ tool, onCommand });

    screen.pointerDown({ x: 20, y: 30, pointerId: 1 });
    screen.pointerMove({ x: 120, y: 90, pointerId: 1 });

    expect(screen.previewElements()).toHaveLength(1);
    expect(screen.committedElements()).toHaveLength(0);
    expect(onCommand).not.toHaveBeenCalled();

    screen.pointerUp({ x: 120, y: 90, pointerId: 1 });
    expect(onCommand).toHaveBeenCalledTimes(1);
  },
);
```

Add Number Marker live-preview/click commit and new Text draft-without-element cases.

- [ ] **Step 2: Add failing controller terminal and snapshot tests**

Test:

```ts
it("commits with the tool and defaults captured at pointer-down", () => {
  const controller = new InteractionController();
  controller.begin({
    pointerId: 7,
    tool: "rectangle",
    point: { x: 10, y: 10 },
    modifiers: { shift: false, option: false },
    defaults: {
      ...DEFAULT_EDITOR_DEFAULTS,
      rectangleFillColor: "#FADB14",
    },
    document: fixtureDocument(),
    selectedIds: [],
    spaceHeld: false,
  });

  controller.update({ x: 80, y: 60 }, {
    shift: false,
    option: false,
  });
  const result = controller.commit({ x: 80, y: 60 }, {
    shift: false,
    option: false,
  });

  expect(result).toMatchObject({
    type: "command",
    command: {
      type: "create",
      element: {
        type: "rectangle",
        fillColor: "#FADB14",
      },
    },
  });
});
```

Mutate the current app tool/defaults between update and commit in the integration test and prove the result is still from pointer-down.

Assert `cancel()` and pointer cancellation return the document/history to the exact starting state.

- [ ] **Step 3: Implement shared constraint geometry**

Use:

```ts
export function constrainSquare(start: Point, end: Point): Point {
  const dx = end.x - start.x;
  const dy = end.y - start.y;
  const magnitude = Math.max(Math.abs(dx), Math.abs(dy));
  return {
    x: start.x + Math.sign(dx || 1) * magnitude,
    y: start.y + Math.sign(dy || 1) * magnitude,
  };
}

export function constrainToNearest45Degrees(
  start: Point,
  end: Point,
): Point {
  const dx = end.x - start.x;
  const dy = end.y - start.y;
  const distance = Math.hypot(dx, dy);
  const snapped =
    Math.round(Math.atan2(dy, dx) / (Math.PI / 4)) * (Math.PI / 4);
  return {
    x: start.x + Math.cos(snapped) * distance,
    y: start.y + Math.sin(snapped) * distance,
  };
}
```

Compute in source space and call the same helper for preview and commit.

- [ ] **Step 4: Define the controller state and results**

Use:

```ts
export type InteractionSnapshot = {
  pointerId: number;
  tool: EditorTool;
  defaults: EditorDefaults;
  selectedElements: readonly EditorElement[];
  start: Point;
  modifiers: InteractionModifiers;
};

export type InteractionCommit =
  | { type: "none" }
  | {
      type: "command";
      command: EditorCommand;
      selectedIds?: readonly string[];
    }
  | { type: "selection"; selectedIds: readonly string[] }
  | {
      type: "beginNewText";
      point: Point;
      defaults: EditorDefaults;
    }
  | { type: "viewport"; pan: Point };
```

The class exposes only:

```ts
get active(): boolean;
get preview(): InteractionPreview | null;
begin(input: InteractionBeginInput): InteractionPreview | null;
update(point: Point, modifiers: InteractionModifiers): InteractionPreview;
commit(point: Point, modifiers: InteractionModifiers): InteractionCommit;
cancel(): void;
```

- [ ] **Step 5: Use Pointer Events and capture as the only terminal path**

Wire:

```tsx
onPointerDown={handlePointerDown}
onPointerMove={handlePointerMove}
onPointerUp={handlePointerUp}
onPointerCancel={handlePointerCancel}
```

On start:

```ts
stage.container().setPointerCapture(event.evt.pointerId);
```

On up/cancel, release the same pointer ID if held. Delete window-level `mouseup` and competing mouse terminal code.

- [ ] **Step 6: Bound preview rendering to one animation frame**

Store the latest point synchronously, schedule only one frame, and flush the latest point before pointer-up:

```ts
latestMoveRef.current = { point, modifiers };
if (frameRef.current === null) {
  frameRef.current = requestAnimationFrame(() => {
    frameRef.current = null;
    const latest = latestMoveRef.current;
    if (latest) setPreview(controller.update(latest.point, latest.modifiers));
  });
}
```

Cancellation cancels the pending frame and clears its latest point.

- [ ] **Step 7: Integrate creation results without pointer-move publication**

`pointermove` may update only `creationPreview`; it must not call `history.dispatch`, `setDocument` with a committed document, `onChange`, or the native bridge.

`pointerup` routes one returned command through `history.dispatch` and `publishSceneChange`.

Text returns `beginNewText`; it does not create a placeholder annotation.

- [ ] **Step 8: Verify constraints, cancellation, and one-command commit**

Run:

```bash
pnpm --filter @myshottr/editor exec vitest run \
  src/interaction/geometry.test.ts \
  src/interaction/InteractionController.test.ts \
  src/canvas/EditorCanvas.test.tsx \
  src/canvas/tools/createElement.test.ts \
  src/canvas/renderElement.test.tsx \
  src/App.test.tsx
pnpm --filter @myshottr/editor typecheck
```

- [ ] **Step 9: Commit the pointer lifecycle**

Run:

```bash
git diff --check
git add Packages/editor/src
git commit -m "feat(editor): pointer 제스처와 생성 미리보기 통합"
```

## Task 10: Add Canonical Selection and Ephemeral Direct Manipulation

**Files:**

- Create: `Packages/editor/src/interaction/selectionGeometry.ts`
- Create: `Packages/editor/src/interaction/selectionGeometry.test.ts`
- Create: `Packages/editor/src/interaction/duplication.ts`
- Create: `Packages/editor/src/interaction/duplication.test.ts`
- Modify: `Packages/editor/src/canvas/SelectionController.ts`
- Modify: `Packages/editor/src/canvas/SelectionController.test.ts`
- Modify: `Packages/editor/src/interaction/InteractionController.ts`
- Modify: `Packages/editor/src/interaction/InteractionController.test.ts`
- Modify: `Packages/editor/src/canvas/EditorCanvas.tsx`
- Modify: `Packages/editor/src/canvas/EditorCanvas.test.tsx`
- Modify: `Packages/editor/src/canvas/renderElement.tsx`
- Modify: `Packages/editor/src/App.tsx`
- Modify: `Packages/editor/src/App.test.tsx`
- Modify: `Packages/editor/src/components/ContextRail.tsx`
- Modify: `Packages/editor/src/components/ContextRail.test.tsx`

**Outcome:** One `selectedIds` state drives Shift-click, marquee, move, resize, rotate, Option-drag, Command-D, delete/reorder, and held-key nudge without pointer-move persistence churn.

- [ ] **Step 1: Add failing pure selection geometry tests**

Cover:

```ts
it("selects by rotated AABB intersection, not containment", () => {
  const rotated = fixtureRectangle({
    x: 100,
    y: 100,
    width: 80,
    height: 20,
    rotation: 45,
  });

  expect(
    intersectingElementIds(
      [rotated],
      { x: 140, y: 90, width: 8, height: 8 },
    ),
  ).toEqual([rotated.id]);
});

it("treats movement below three CSS points on both axes as a click", () => {
  expect(
    isMarqueeGesture(
      { x: 10, y: 10 },
      { x: 12.9, y: 12.9 },
      2,
    ),
  ).toBe(false);
});
```

The threshold converts to source space as `3 / zoom`.

- [ ] **Step 2: Make `SelectionController` pure**

Replace the mutable selected-ID class with:

```ts
export const replaceSelection = (id: string): readonly string[] => [id];

export const toggleSelection = (
  selectedIds: readonly string[],
  id: string,
): readonly string[] =>
  selectedIds.includes(id)
    ? selectedIds.filter((selectedId) => selectedId !== id)
    : [...selectedIds, id];

export const clearSelection = (): readonly string[] => [];
```

`EditorApp`'s React `selectedIds` is the only selection store.

- [ ] **Step 3: Implement rotated bounds, intersection, and union**

Export:

```ts
export function rotatedElementBounds(element: EditorElement): Rect;
export function intersectingElementIds(
  elements: readonly EditorElement[],
  marquee: Rect,
): readonly string[];
export function unionBounds(
  elements: readonly EditorElement[],
): Rect | undefined;
```

Lines and arrows use their rendered endpoint bounds plus stroke expansion; the resulting rotated/source-space AABB participates in the same intersection test.

- [ ] **Step 4: Add failing duplication tests**

Assert:

```ts
const copies = createDuplicateElements(
  fixtureDocument(),
  [source],
  { x: 12, y: 12 },
);

expect(copies).toHaveLength(1);
expect(copies[0].id).not.toBe(source.id);
expect(copies[0].zIndex).toBeGreaterThan(source.zIndex);
expect(copies[0]).toMatchObject({
  x: source.x + 12,
  y: source.y + 12,
});
```

Test source bounds, unique IDs/z-indices, multi-selection relative spacing, and a drag delta other than 12.

- [ ] **Step 5: Implement one duplication primitive**

Use:

```ts
export function createDuplicateElements(
  document: Pick<
    EditorDocument,
    "elements" | "sourcePixelWidth" | "sourcePixelHeight"
  >,
  sources: readonly EditorElement[],
  delta: Point = { x: 12, y: 12 },
): EditorElement[];
```

Command-D and Context Rail Duplicate use the default delta. Option-drag uses the actual source-space drag delta. All callers dispatch one `createMany` and select the returned IDs.

- [ ] **Step 6: Add failing move and Option-drag tests**

Assert during drag:

```ts
expect(history.document.elements).toEqual(startingElements);
expect(onChange).not.toHaveBeenCalled();
expect(screen.previewElements()).toMatchObject(expectedMovedGeometry);
```

At release:

```ts
expect(onCommand).toHaveBeenCalledTimes(1);
expect(onCommand).toHaveBeenCalledWith({
  type: "updateMany",
  elements: expectedMovedGeometry,
});
```

For Option-drag, originals remain while clone previews move, release emits one `createMany`, and cancel emits none.

- [ ] **Step 7: Stop dispatching during move/resize/rotate**

On pointer start, snapshot selected elements and node geometry. On move, update draft elements or Konva nodes only. On release, return one `updateMany`. On cancel, restore node attributes from the snapshot.

Transform already commits near this boundary; normalize it to the same commit/cancel result path.

- [ ] **Step 8: Add held-key nudge tests**

Use fake repeated key events:

```ts
fireEvent.keyDown(window, { code: "ArrowRight" });
fireEvent.keyDown(window, { code: "ArrowRight", repeat: true });
fireEvent.keyDown(window, {
  code: "ArrowDown",
  repeat: true,
  shiftKey: true,
});

expect(onChange).not.toHaveBeenCalled();

fireEvent.keyUp(window, { code: "ArrowRight" });
expect(onChange).toHaveBeenCalledTimes(1);
expect(history.canUndo).toBe(true);
```

Test 1/10 source-pixel steps, bounds clamping, one Undo entry, interaction lock, and Escape cancellation.

- [ ] **Step 9: Implement a nudge session**

Use:

```ts
type NudgeSession = {
  startingElements: readonly EditorElement[];
  previewElements: readonly EditorElement[];
  heldCodes: Set<string>;
};
```

First arrow key-down begins the session and sets `locks.nudge`. Repeats update preview. The session commits one `updateMany` only when the final held arrow key is released. Escape restores the start snapshot.

- [ ] **Step 10: Wire marquee and selection modifiers**

With Selection active:

- pointer-down on empty source begins marquee;
- movement below threshold clears on release as a click;
- normal marquee replaces selection;
- Shift-click toggles one hit element;
- marquee itself remains ephemeral and non-draggable.

- [ ] **Step 11: Verify direct manipulation and commit**

Run:

```bash
pnpm --filter @myshottr/editor exec vitest run \
  src/interaction/selectionGeometry.test.ts \
  src/interaction/duplication.test.ts \
  src/canvas/SelectionController.test.ts \
  src/interaction/InteractionController.test.ts \
  src/canvas/EditorCanvas.test.tsx \
  src/components/ContextRail.test.tsx \
  src/App.test.tsx
pnpm --filter @myshottr/editor test
pnpm --filter @myshottr/editor typecheck
git diff --check
git add Packages/editor/src
git commit -m "feat(editor): 선택과 직접 조작 상호작용 추가"
```

## Task 11: Unify New and Existing Text Editing

**Files:**

- Create: `Packages/editor/src/components/textEditSession.ts`
- Create: `Packages/editor/src/components/textEditSession.test.ts`
- Modify: `Packages/editor/src/components/TextEditorOverlay.tsx`
- Modify: `Packages/editor/src/components/TextEditorOverlay.test.tsx`
- Modify: `Packages/editor/src/interaction/InteractionController.ts`
- Modify: `Packages/editor/src/canvas/EditorCanvas.tsx`
- Modify: `Packages/editor/src/App.tsx`
- Modify: `Packages/editor/src/App.test.tsx`

**Outcome:** A Text click opens an inline draft before any element exists; new/existing text share commit, cancel, deletion, keyboard, positioning, and history semantics.

- [ ] **Step 1: Add failing session transition tests**

Use:

```ts
export type TextEditSession =
  | {
      kind: "new";
      point: Point;
      defaults: EditorDefaults;
      initialText: "";
    }
  | {
      kind: "existing";
      element: TextElement;
      initialText: string;
    };

export type TextEditResult =
  | { type: "cancel" }
  | { type: "commit"; text: string };
```

Test new non-empty create, new blank no-op, existing non-empty update, existing blank delete, and cancel preserving the original.

- [ ] **Step 2: Run the session/overlay tests and observe current placeholder behavior**

Run:

```bash
pnpm --filter @myshottr/editor exec vitest run \
  src/components/textEditSession.test.ts \
  src/components/TextEditorOverlay.test.tsx \
  src/App.test.tsx
```

- [ ] **Step 3: Open a new draft directly from the interaction result**

When `InteractionController` returns:

```ts
{
  type: "beginNewText",
  point,
  defaults: structuredClone(document.defaults),
}
```

set a `TextEditSession` and `locks.text = true`; do not dispatch a create command.

- [ ] **Step 4: Use one overlay for new and existing text**

Existing text opens from double-click or Enter only when exactly one selected element is Text. Other selection shapes ignore Enter.

The overlay behavior is:

- Return inserts a line break;
- Command-Enter commits;
- blur commits;
- Escape cancels;
- focus starts in the textarea;
- pan/zoom changes recompute the workspace position from the session's source position.

- [ ] **Step 5: Preserve non-empty input exactly**

Use `text.trim().length === 0` only to decide blankness. Save the original `text` string for non-empty values; do not trim user-entered leading/trailing spaces or line breaks.

Route terminal results:

```ts
if (result.type === "cancel") return;
if (session.kind === "new" && result.text.trim().length > 0) {
  dispatchCreateText(session, result.text);
} else if (
  session.kind === "existing"
  && result.text.trim().length === 0
) {
  dispatch({ type: "delete", ids: [session.element.id] });
} else if (session.kind === "existing") {
  dispatch({
    type: "update",
    element: { ...session.element, text: result.text },
  });
}
```

Each non-no-op terminal path publishes one document command and one Undo entry.

- [ ] **Step 6: Verify text editing and commit**

Run:

```bash
pnpm --filter @myshottr/editor exec vitest run \
  src/components/textEditSession.test.ts \
  src/components/TextEditorOverlay.test.tsx \
  src/interaction/InteractionController.test.ts \
  src/App.test.tsx
pnpm --filter @myshottr/editor test
pnpm --filter @myshottr/editor typecheck
git diff --check
git add Packages/editor/src
git commit -m "feat(editor): 텍스트 편집 세션 통합"
```

## Task 12: Publish Web History Availability and Share One History Action

**Files:**

- Modify: `Packages/editor/src/model/history.ts`
- Modify: `Packages/editor/src/model/history.test.ts`
- Modify: `Packages/editor/src/App.tsx`
- Modify: `Packages/editor/src/App.test.tsx`
- Modify: `Packages/editor/src/bridge/nativeBridge.ts`

**Outcome:** Keyboard and native Undo/Redo call one web action; native receives exact availability after load and every history/interaction transition; locked/no-op actions never mutate the document.

- [ ] **Step 1: Complete the history availability transition tests**

Assert the full table:

| Operation | `canUndo` | `canRedo` |
| --- | ---: | ---: |
| initial | false | false |
| first command | true | false |
| Undo | depends on remaining past | true |
| Redo | true | depends on remaining future |
| new command after Undo | true | false |
| active transaction | false | false |
| changed transaction commit | true | false |
| transaction cancel | restored pre-transaction values |

Use getters already introduced in Task 2; add any missing transition assertion before integration.

- [ ] **Step 2: Add failing App integration tests**

Test:

```ts
it("sends initial history state immediately after load", async () => {
  const bridge = renderLoadedNativeEditor();

  await bridge.waitForEditor();

  expect(bridge.sent("historyStateChanged").at(-1)?.payload).toEqual({
    canUndo: false,
    canRedo: false,
  });
});

it.each(["keyboard", "native"] as const)(
  "performs Undo through the shared action for %s",
  async (source) => {
    const editor = renderEditorWithOneUndoEntry();
    source === "keyboard"
      ? editor.press({ code: "KeyZ", metaKey: true })
      : editor.receiveNative("performHistoryAction", { action: "undo" });

    expect(editor.document().elements).toEqual([]);
    expect(editor.selectedIds()).toEqual([]);
    expect(editor.documentChangedCount()).toBe(1);
  },
);
```

Add lock cases for pointer, nudge, text, slider, and shortcut help. During each lock, outgoing history is `false/false`, received action is a no-op, selection stays unchanged, and no `documentChanged` is sent.

- [ ] **Step 3: Expose the smallest editor handle**

Use:

```ts
export type EditorAppHandle = {
  getDocument(): EditorDocument;
  performHistoryAction(action: "undo" | "redo"): boolean;
};
```

Implement through `forwardRef`/`useImperativeHandle` so the outer native-bridge `App` can request the latest canonical document and invoke the same history function as the shortcut router.

- [ ] **Step 4: Implement one `performHistoryAction` function**

Use:

```ts
const performHistoryAction = (action: "undo" | "redo"): boolean => {
  if (isHistoryLocked(locks)) {
    publishHistoryState();
    return false;
  }

  const changed =
    action === "undo"
      ? history.current.undo()
      : history.current.redo();

  if (!changed) {
    publishHistoryState();
    return false;
  }

  setSelectedIds([]);
  publishSceneChange();
  publishHistoryState();
  return true;
};
```

Keyboard and native command handlers both call this exact function.

- [ ] **Step 5: Publish deduplicated availability at every required boundary**

Compute:

```ts
const visibleHistoryState: HistoryAvailability =
  isHistoryLocked(locks)
    ? { canUndo: false, canRedo: false }
    : {
        canUndo: history.current.canUndo,
        canRedo: history.current.canRedo,
      };
```

Publish after:

- load/mount;
- semantic command;
- transaction begin/commit/cancel;
- Undo/Redo;
- each interaction-lock enter/leave.

Suppress only byte-for-byte duplicate state:

```ts
if (
  lastHistoryState.current?.canUndo === next.canUndo
  && lastHistoryState.current?.canRedo === next.canRedo
) return;
```

- [ ] **Step 6: Subscribe to native history action and return the latest document**

The outer `App` subscribes to `performHistoryAction`, forwards it through the handle, and uses `getDocument()` for annotation snapshots and composite rendering. This removes stale `loadedDocumentRef` reads from output operations.

- [ ] **Step 7: Verify web history integration and commit**

Run:

```bash
pnpm --filter @myshottr/editor exec vitest run \
  src/model/history.test.ts \
  src/bridge/protocol.test.ts \
  src/App.test.tsx
pnpm --filter @myshottr/editor test
pnpm --filter @myshottr/editor typecheck
git diff --check
git add Packages/editor/src
git commit -m "feat(editor): 네이티브 히스토리 상태 동기화 추가"
```

## Task 13: Route Native History State and Build the AppKit Toolbar

**Files:**

- Modify: `Sources/MyShottrApp/Editor/EditorBridge.swift`
- Modify: `Sources/MyShottrApp/Editor/EditorWebView.swift`
- Create: `Tests/MyShottrTests/Editor/EditorBridgeStateCommandTests.swift`
- Modify: `Tests/MyShottrTests/EditorBridgeCompositeTransferTests.swift`
- Modify: `Sources/MyShottrApp/Documents/DocumentWindowController.swift`
- Modify: `Tests/MyShottrTests/Documents/DocumentWindowControllerCommandTests.swift`
- Verify unchanged: `Sources/MyShottrApp/App/MyShottrApp.swift`

**Outcome:** AppKit toolbar state mirrors web history exactly, toolbar clicks send one action, output items respect editor readiness, and uncorrelated JavaScript failures reach the existing bridge-error UI path.

- [ ] **Step 1: Add failing bridge-routing tests**

Test:

- valid `historyStateChanged` calls one typed callback;
- malformed state reports a protocol error;
- `performHistoryAction(.undo)` emits one strict envelope;
- every operation status encoder uses the caller's request ID;
- fire-and-forget synchronous/async failure calls `onUncorrelatedError` once;
- late errors for retired correlated requests stay ignored.

- [ ] **Step 2: Run bridge tests and observe missing routing**

Run:

```bash
xcodegen generate
xcodebuild test \
  -project MyShottr.xcodeproj \
  -scheme MyShottr \
  -destination "platform=macOS" \
  CODE_SIGNING_ALLOWED=NO \
  -only-testing:MyShottrTests/EditorBridgeStateCommandTests \
  -only-testing:MyShottrTests/EditorBridgeCompositeTransferTests
```

- [ ] **Step 3: Add typed bridge APIs**

Expose:

```swift
var onHistoryStateChanged: ((EditorHistoryState) -> Void)?

func performHistoryAction(_ action: EditorHistoryAction)

func sendOperationStatus(
    requestID: UUID,
    status: EditorOperationStatus
)
```

Parse the already strict-validated `historyStateChanged` payload and relay exactly one typed value.

- [ ] **Step 4: Separate correlated and fire-and-forget sends**

Implement distinct private paths:

```swift
private func sendCorrelated(
    requestID: UUID,
    type: NativeToEditorMessageType,
    payload: BridgeJSONValue
) throws

private func sendFireAndForget(
    requestID: UUID,
    type: NativeToEditorMessageType,
    payload: BridgeJSONValue
)
```

Rules:

- load/snapshot/composite keep their current continuation, deadline, retired-ID, and late-error behavior;
- `performHistoryAction`/`operationStatus` use fire-and-forget;
- any encode/readiness/evaluate-JavaScript failure in fire-and-forget calls `reportUncorrelatedError(.invalidMessage)`;
- do not retry or create a web fallback event.

- [ ] **Step 5: Add failing native toolbar tests**

Assert default order:

```swift
[
    .copyComposite,
    .undoEditor,
    .redoEditor,
    .flexibleSpace,
    .saveProject,
    .exportComposite,
]
```

Assert:

- all five actions are disabled before editor load;
- after load, Copy/Save/Export enable;
- Undo/Redo follow the last history state;
- one click sends exactly one action;
- output in flight disables only Copy/Save/Export, not Undo/Redo;
- labels, tooltips, and SF Symbols match the design.

- [ ] **Step 6: Store readiness, history, and output state in the window controller**

Use:

```swift
private var editorIsReady = false
private var historyState = EditorHistoryState(
    canUndo: false,
    canRedo: false
)
private var outputOperation: OutputOperation?
```

After:

```swift
try await editorLoadOperation?.wait()
```

set `editorIsReady = true` and validate visible toolbar items.

Implement:

```swift
func validateToolbarItem(_ item: NSToolbarItem) -> Bool {
    switch item.itemIdentifier {
    case .copyComposite, .saveProject, .exportComposite:
        return editorIsReady && outputOperation == nil
    case .undoEditor:
        return editorIsReady && historyState.canUndo
    case .redoEditor:
        return editorIsReady && historyState.canRedo
    default:
        return true
    }
}
```

- [ ] **Step 7: Add Undo/Redo toolbar selectors**

Use:

```swift
@objc func undoEditor(_ sender: Any?) -> Bool {
    guard window?.isKeyWindow == true,
          validateHistoryAction(.undo)
    else { return false }
    editorWebView.performHistoryAction(.undo)
    return true
}

@objc func redoEditor(_ sender: Any?) -> Bool {
    guard window?.isKeyWindow == true,
          validateHistoryAction(.redo)
    else { return false }
    editorWebView.performHistoryAction(.redo)
    return true
}
```

Do not add native Undo/Redo keyboard commands to `MyShottrApp.swift`; WebKit remains the single owner of `Command-Z` and `Command-Shift-Z`.

- [ ] **Step 8: Verify bridge failure reaches existing native error presentation**

Connect `EditorWebView.onBridgeFailure` to the existing `DocumentWindowController.present` path and assert a failed history/status send becomes one actionable native bridge error rather than disappearing.

- [ ] **Step 9: Run focused native tests and commit**

Run:

```bash
xcodebuild test \
  -project MyShottr.xcodeproj \
  -scheme MyShottr \
  -destination "platform=macOS" \
  CODE_SIGNING_ALLOWED=NO \
  -only-testing:MyShottrTests/EditorBridgeStateCommandTests \
  -only-testing:MyShottrTests/EditorBridgeCompositeTransferTests \
  -only-testing:MyShottrTests/DocumentWindowControllerCommandTests
git diff --check
git add Sources/MyShottrApp/Editor Sources/MyShottrApp/Documents/DocumentWindowController.swift Tests/MyShottrTests
git commit -m "feat(app): 네이티브 Undo Redo 툴바 추가"
```

## Task 14: Make Copy, Save, and Export One Truthful Native State Machine

**Files:**

- Modify: `Sources/MyShottrApp/Documents/DocumentWindowController.swift`
- Modify: `Sources/MyShottrApp/Documents/DocumentSession.swift`
- Modify: `Tests/MyShottrTests/Documents/DocumentWindowControllerCommandTests.swift`
- Create: `Tests/MyShottrTests/Documents/DocumentWindowControllerOutputTests.swift`
- Modify: `Tests/MyShottrTests/Documents/DocumentSessionTests.swift`
- Modify: `Sources/MyShottrApp/App/MyShottrUserFacingError.swift` only if an existing error context must distinguish the three commands

**Outcome:** Only one output operation runs per window; Copy hides only after clipboard success; Save/Export status matches native terminal reality; cancellation remains silent.

- [ ] **Step 1: Add narrow deterministic test seams**

Extend the controller initializer with optional closures:

```swift
typealias CompositeProvider = @MainActor (
    _ destinationDirectory: URL?
) async throws -> CompositeTransfer

typealias ClipboardWriter = @MainActor (_ data: Data) throws -> Void
typealias URLProvider = @MainActor () -> URL?
typealias OperationStatusSender = @MainActor (
    _ requestID: UUID,
    _ status: EditorOperationStatus
) -> Void
typealias WindowHider = @MainActor () -> Void
```

Production defaults call the current editor web view, PNG pasteboard writer, save panels, bridge, and `window.orderOut(nil)`. Tests inject spies/fakes. Do not add alternate production behavior.

- [ ] **Step 2: Add failing shared-guard and Copy tests**

Test exact order with an event recorder:

```swift
XCTAssertEqual(events, [
    "composite.request",
    "transfer.data",
    "clipboard.write",
    "window.hide",
])
```

Also assert:

- composite failure: no clipboard write, no hide, one native error;
- clipboard failure: no hide, one native error;
- a suspended first output causes second Copy/Save/Export to return false;
- Copy emits no success operation status.

- [ ] **Step 3: Acquire and release one output guard**

Guard before any modal panel:

```swift
private func beginOutput(_ operation: OutputOperation) -> Bool {
    guard editorIsReady, outputOperation == nil else { return false }
    outputOperation = operation
    toolbar?.validateVisibleItems()
    return true
}

private func finishOutput() {
    outputOperation = nil
    toolbar?.validateVisibleItems()
}
```

Use `defer { finishOutput() }` within one main-actor task. Acquiring before `NSSavePanel.runModal()` prevents a nested event-loop overlap; `started` still waits until a destination is chosen.

- [ ] **Step 4: Implement Copy's exact success boundary**

Use:

```swift
let transfer = try await compositeProvider(nil)
defer { transfer.discard() }
let data = try transfer.data()
try clipboardWriter(data)
hideWindow()
```

On error, keep the window visible and present the existing clipboard/composite error.

- [ ] **Step 5: Add failing Save-order and outcome tests**

Test:

- unsaved destination cancellation calls no snapshot, status, or store;
- destination exists before `modificationRevision` capture/start/snapshot;
- completed sends `started`, then `completed` with the same request ID;
- revision race sends `superseded`, keeps `session.isModified == true`;
- cancellation after start sends `cancelled`, no native error;
- failure sends `failed` before presenting the native error;
- explicit Save never hides/closes;
- close-prompt Save continues close only for fully saved.

- [ ] **Step 6: Implement a typed Save outcome**

Use:

```swift
enum ProjectSaveOutcome: Equatable {
    case saved
    case superseded
    case cancelledBeforeStart
    case cancelledAfterStart
    case failed
}
```

Sequence:

```text
guard acquired
→ unsaved destination selection
→ silent return if cancelled
→ capture revision
→ send started
→ request annotation snapshot
→ atomically save project
→ completeSave(expectedRevision)
→ send completed or superseded
→ guard released
```

Map `.savedWithNewerChanges` only to `.saveSuperseded`.

- [ ] **Step 7: Add failing Export-order and filename tests**

Test:

- destination cancellation produces no status/composite request;
- `started` precedes composite;
- transfer move precedes `completed`;
- completed contains basename only;
- line breaks/control characters are removed;
- display name is limited to 120 Swift `Character`s;
- failed status precedes native alert;
- window stays visible after success and failure.

- [ ] **Step 8: Implement display-safe export names**

Use:

```swift
func displaySafeBasename(for url: URL) -> String {
    let filtered = url.lastPathComponent.unicodeScalars.filter {
        !CharacterSet.controlCharacters.contains($0)
    }
    return String(String.UnicodeScalarView(filtered).prefix(120))
}
```

If this scalar-based expression does not preserve user-perceived `Character` limits in the failing emoji/combining test, construct the filtered string first and apply `String(filteredString.prefix(120))`. The test's contract is 120 `Character`s, not 120 bytes or scalars.

- [ ] **Step 9: Send exactly one terminal state per started operation**

Every started Save/Export reuses its outer request ID for `completed`, `superseded`, `cancelled`, or `failed`. Raw errors and paths never enter `operationStatus`.

- [ ] **Step 10: Run output/session tests and commit**

Run:

```bash
xcodebuild test \
  -project MyShottr.xcodeproj \
  -scheme MyShottr \
  -destination "platform=macOS" \
  CODE_SIGNING_ALLOWED=NO \
  -only-testing:MyShottrTests/DocumentWindowControllerCommandTests \
  -only-testing:MyShottrTests/DocumentWindowControllerOutputTests \
  -only-testing:MyShottrTests/DocumentSessionTests
git diff --check
git add Sources/MyShottrApp/Documents Sources/MyShottrApp/App/MyShottrUserFacingError.swift Tests/MyShottrTests/Documents
git commit -m "feat(app): 출력 작업 상태와 창 동작 정교화"
```

## Task 15: Render Delayed Save and Export Feedback in the Editor

**Files:**

- Create: `Packages/editor/src/components/EditorFeedback.tsx`
- Create: `Packages/editor/src/components/EditorFeedback.test.tsx`
- Modify: `Packages/editor/src/App.tsx`
- Modify: `Packages/editor/src/App.test.tsx`
- Modify: `Packages/editor/src/styles.css`

**Outcome:** Save/Export progress appears only after 150 ms, terminal messages are truthful and transient, stale operation IDs cannot overwrite newer feedback, and failures remain owned by native alerts.

- [ ] **Step 1: Add fake-timer state-machine tests**

Use `vi.useFakeTimers()` and assert:

```ts
it("does not flash progress for a fast completion", () => {
  const view = renderFeedback();
  view.receive(status("request-a", "save", "started"));
  vi.advanceTimersByTime(149);
  view.receive(status("request-a", "save", "completed"));

  expect(screen.queryByText("Saving…")).not.toBeInTheDocument();
  expect(screen.getByText("Saved")).toBeInTheDocument();
});

it("shows progress at 150ms", () => {
  const view = renderFeedback();
  view.receive(status("request-a", "export", "started"));
  vi.advanceTimersByTime(150);

  expect(screen.getByText("Exporting…")).toBeInTheDocument();
});
```

Add completed/superseded/cancelled/failed, stale terminal, new-start-clears-old-toast, 1.5-second, and 2-second cases.

- [ ] **Step 2: Run the component test and observe the missing state machine**

Run:

```bash
pnpm --filter @myshottr/editor exec vitest run src/components/EditorFeedback.test.tsx
```

- [ ] **Step 3: Implement request-ID-owned feedback state**

Use:

```ts
type FeedbackState =
  | { kind: "idle" }
  | {
      kind: "pending";
      requestId: string;
      operation: "save" | "export";
      progressVisible: boolean;
    }
  | {
      kind: "toast";
      requestId: string;
      message: string;
    };
```

On `started`, clear the prior timer/toast and start a 150 ms timer. A terminal state is accepted only when its envelope request ID equals the current pending request ID.

Map:

```ts
save completed  -> "Saved" for 1500ms
save superseded -> "New changes still need saving" for 2000ms
export completed -> `Exported ${displayName}` for 1500ms
cancelled/failed -> idle immediately
```

- [ ] **Step 4: Render one accessible bottom-center status**

Use:

```tsx
<output
  className="editor-feedback"
  role="status"
  aria-live="polite"
>
  {message}
</output>
```

Place it 24 points above the lower workspace edge and reserve the lower-right zoom-control safe area.

- [ ] **Step 5: Subscribe to `operationStatus` at the outer App boundary**

Pass strict envelopes to `EditorFeedback`; do not sanitize or reinterpret native failures in the web layer. `displayName` is already safe and must be displayed as plain React text.

- [ ] **Step 6: Verify feedback integration and commit**

Run:

```bash
pnpm --filter @myshottr/editor exec vitest run \
  src/components/EditorFeedback.test.tsx \
  src/bridge/protocol.test.ts \
  src/App.test.tsx
pnpm --filter @myshottr/editor test
pnpm --filter @myshottr/editor typecheck
git diff --check
git add Packages/editor/src
git commit -m "feat(editor): 저장과 내보내기 피드백 추가"
```

## Task 16: Add Real-browser Visual and Accessibility Regression Coverage

**Files:**

- Modify: `Packages/editor/package.json`
- Modify: `pnpm-lock.yaml`
- Create: `Packages/editor/playwright.config.ts`
- Create: `Packages/editor/tests/visual/visual.html`
- Create: `Packages/editor/tests/visual/entry.tsx`
- Create: `Packages/editor/tests/visual/editor.visual.spec.ts`
- Create: `Packages/editor/tests/visual/editor.accessibility.spec.ts`
- Create: generated Darwin screenshot baselines under `Packages/editor/tests/visual/*-snapshots/`
- Modify: `Packages/editor/src/App.tsx`
- Modify: `Packages/editor/src/styles.css`
- Modify: `Scripts/verify-v1.sh`

**Outcome:** Seven deterministic editor states are compared in light and dark appearance, while actual browser focus, semantics, contrast, and reduced motion are regression-tested without adding a production bridge fallback.

- [ ] **Step 1: Add the editor-local Playwright dependency and script**

Run:

```bash
pnpm --filter @myshottr/editor add -D @playwright/test@^1.54.0
```

Set:

```json
{
  "scripts": {
    "build": "tsc --noEmit && vite build",
    "test": "vitest run",
    "test:visual": "playwright test",
    "typecheck": "tsc --noEmit"
  }
}
```

Keep the version range aligned with the Chrome-extension package.

- [ ] **Step 2: Create a deterministic, test-only browser entry**

`tests/visual/visual.html` loads `entry.tsx`. `entry.tsx` imports exported production `EditorApp` and supplies a fixed local data-URL source image, schema-3 fixture document, fixed tool/selection/status state, and no-op callbacks.

Use this complete state union:

```ts
export type VisualFixtureState =
  | "selection-empty"
  | "new-rectangle"
  | "selected-rectangle"
  | "mixed-rectangle-text"
  | "shortcut-help"
  | "save-success"
  | "rail-reduced-motion";
```

The entry reads only those enumerated query parameters and throws for any other value. It must not modify production `App` to work when the native bridge is missing.

- [ ] **Step 3: Configure a fixed local Playwright server**

Create:

```ts
import { defineConfig } from "@playwright/test";

export default defineConfig({
  testDir: "./tests/visual",
  testMatch: "**/*.spec.ts",
  workers: 1,
  fullyParallel: false,
  webServer: {
    command: "pnpm exec vite --host 127.0.0.1 --port 4173",
    url: "http://127.0.0.1:4173/tests/visual/visual.html",
    reuseExistingServer: false,
  },
  use: {
    baseURL: "http://127.0.0.1:4173",
    viewport: { width: 1280, height: 860 },
    deviceScaleFactor: 1,
    trace: "retain-on-failure",
  },
});
```

- [ ] **Step 4: Write the 14-state visual test before baselines exist**

Use:

```ts
const states = [
  "selection-empty",
  "new-rectangle",
  "selected-rectangle",
  "mixed-rectangle-text",
  "shortcut-help",
  "save-success",
  "rail-reduced-motion",
] as const;

for (const appearance of ["light", "dark"] as const) {
  for (const state of states) {
    test(`${state} in ${appearance}`, async ({ page }) => {
      await page.emulateMedia({
        colorScheme: appearance,
        reducedMotion:
          state === "rail-reduced-motion" ? "reduce" : "no-preference",
      });
      await page.goto(
        `/tests/visual/visual.html?state=${state}&appearance=${appearance}`,
      );
      await expect(page.getByRole("main", {
        name: "MyShottr editor",
      })).toBeVisible();
      await expect(page).toHaveScreenshot(
        `${state}-${appearance}.png`,
        {
          animations: "disabled",
          caret: "hide",
          scale: "css",
        },
      );
    });
  }
}
```

Run once and observe missing-snapshot failures.

- [ ] **Step 5: Add real-browser accessibility assertions**

Test both light and dark:

- Tab order: tool palette → Context Rail → zoom controls;
- every tool has a visible focus ring and accessible shortcut name;
- tooltips show on hover and focus;
- `<kbd aria-hidden="true">` avoids duplicate announcements;
- swatches/segments/sliders expose pressed/radio/value state;
- mixed value has visible `Mixed` text;
- help dialog traps focus and restores the prior control;
- feedback is `role="status"` with `aria-live="polite"`;
- reduced motion removes the 160 ms reflow transition.

Calculate computed-color contrast in the test:

```ts
expect(textContrastRatio).toBeGreaterThanOrEqual(4.5);
expect(controlBoundaryContrastRatio).toBeGreaterThanOrEqual(3);
expect(activeStateContrastRatio).toBeGreaterThanOrEqual(3);
```

Sample every core token pairing in both appearances rather than one arbitrary button.

- [ ] **Step 6: Fix visual/accessibility failures in production CSS and semantics**

Keep:

- visible `:focus-visible` rings;
- distinct active, hover, and focus states;
- accessible color names;
- cream/coral/ink product tokens;
- fixed rail geometry;
- bottom-center feedback outside zoom controls;
- `prefers-reduced-motion` disabling rail/status transitions.

Do not add a DOM annotation tree for Konva elements; that remains out of scope.

- [ ] **Step 7: Review and commit the baseline screenshots**

Run:

```bash
pnpm --filter @myshottr/editor exec playwright install chromium
pnpm --filter @myshottr/editor test:visual -- --update-snapshots
pnpm --filter @myshottr/editor test:visual
```

Open every generated image and compare it against the approved Context Rail reference at the same size/state. Baselines are accepted only after manual inspection; never approve a failing layout by blindly updating screenshots.

- [ ] **Step 8: Add the visual gate to repository verification**

After the existing Chromium install step in `Scripts/verify-v1.sh`, add:

```bash
run_step "Run editor visual and accessibility tests" \
  pnpm --filter @myshottr/editor test:visual
```

The existing pinned Chromium installation is shared; do not add another CI job or browser download.

- [ ] **Step 9: Run editor and visual gates, then commit**

Run:

```bash
pnpm --filter @myshottr/editor test
pnpm --filter @myshottr/editor typecheck
pnpm --filter @myshottr/editor build
pnpm --filter @myshottr/editor test:visual
git diff --check
git add Packages/editor/package.json Packages/editor/playwright.config.ts Packages/editor/tests Packages/editor/src/App.tsx Packages/editor/src/styles.css pnpm-lock.yaml Scripts/verify-v1.sh
git commit -m "test(editor): 시각 회귀와 접근성 검증 추가"
```

## Task 17: Integrate Documentation, Acceptance, and the Full Release Gate

**Files:**

- Modify: `README.md`
- Modify: `docs/testing/v1-acceptance.md`
- Modify: `docs/releases/v0.1.0.md`
- Modify: `docs/superpowers/specs/2026-07-31-myshottr-editor-ux-polish-design.md`
- Modify: release workflow/tests only if the existing release contract fails after the editor visual gate is added

**Outcome:** Documentation matches shipped behavior, automated and manual acceptance are recorded, no placeholder/contract drift remains, and the existing v0.1.0 release path receives a verified build.

- [ ] **Step 1: Update user-facing workflow and shortcut documentation**

Document:

- `V/R/A/L/T/P/H/B/X/N`;
- `?` help;
- marquee, Shift-click, Option-drag, Command-D;
- 1/10-pixel nudge;
- Space-pan, wheel pan, pointer-centered zoom;
- Command-0, Shift-1, Shift-2;
- Context Rail hidden/default/single/multi/mixed behavior;
- native Copy/Undo/Redo/Save/Export toolbar order;
- Copy success hides rather than closes;
- Save completed versus superseded feedback;
- recovery remains absent;
- browser capture remains visible viewport only;
- full-page capture and mockups remain future work.

- [ ] **Step 2: Expand the manual acceptance checklist**

Add explicit checkboxes for:

```text
[ ] Korean and English input sources trigger identical tool shortcuts.
[ ] Every creation tool previews continuously before pointer-up.
[ ] Shift constrains Rectangle/Line/Arrow; Shift no longer pans.
[ ] Marquee intersection and Shift-click selection work.
[ ] Option-drag and Command-D create selected editable copies.
[ ] Space-drag and trackpad pan stay within source bounds.
[ ] Pointer-centered pinch/Command-wheel zoom keeps its anchor.
[ ] Context Rail reflows without changing zoom or source center.
[ ] Native Undo/Redo enablement matches web history and locks.
[ ] Copy hides only after the PNG is present on the pasteboard.
[ ] Save, superseded Save, cancellation, failure, and Export show correct UI.
[ ] Light, dark, and reduced-motion states match the approved reference.
[ ] A Chrome capture contains only the visible viewport and no extension toolbar.
[ ] No recovery prompt or recovery document flow appears.
```

Record the tested app build SHA and macOS version beside the completed checklist.

- [ ] **Step 3: Run a contract and placeholder scan**

Run:

```bash
rg -n "TODO|TBD|FIXME|HACK|placeholder|fallback" Packages/editor Sources/MyShottrApp Tests/MyShottrTests README.md docs
rg -n "schemaVersion.?2|editorPreferences\\.v1|saveCompleted|saveFailed|Command-Y|Shift-pan|ContextStylePalette" Packages/editor Sources/MyShottrApp Tests/MyShottrTests README.md docs
rg -n "RecoveryCoordinator|RecoveryStore|SessionTerminationState|Recover unsaved" Sources Tests README.md docs || true
```

Review every match:

- schema 1/2 references are valid only in migration tests/docs;
- `editorPreferences.v1` is valid only as the migration input key;
- `saveCompleted`/`saveFailed` may remain only as unused v1 decoder compatibility;
- no executable Command-Y, Shift-pan, old palette, or recovery path remains;
- no implementation placeholder or fallback is permitted.

- [ ] **Step 4: Run all JavaScript/editor/release checks**

Run:

```bash
pnpm --filter @myshottr/editor test
pnpm --filter @myshottr/editor typecheck
pnpm --filter @myshottr/editor build
pnpm --filter @myshottr/editor exec playwright install chromium
pnpm --filter @myshottr/editor test:visual
pnpm test:release
```

- [ ] **Step 5: Run all native tests and a Debug build**

Run:

```bash
xcodegen generate
xcodebuild test \
  -project MyShottr.xcodeproj \
  -scheme MyShottr \
  -destination "platform=macOS" \
  CODE_SIGNING_ALLOWED=NO
xcodebuild build \
  -project MyShottr.xcodeproj \
  -scheme MyShottr \
  -configuration Debug \
  -destination "platform=macOS"
```

- [ ] **Step 6: Perform the real-app interaction pass**

Launch the newly built app and complete every manual acceptance checkbox using:

- an on-device region capture;
- a Chrome visible-viewport capture;
- a reopened `.myshottr` project;
- light and dark appearance;
- reduced motion enabled;
- Korean and English input sources;
- fast and deliberately delayed Save/Export fakes only in automated tests, with ordinary real Save/Export paths in the app.

Capture the seven approved UI states at the same window size as the reference and compare them side by side.

- [ ] **Step 7: Ask the user to save and quit running MyShottr instances before the full gate**

Do not kill the app. Recheck:

```bash
pgrep -x MyShottr
```

Proceed only when it returns no PID after the user has confirmed their editor work is saved.

- [ ] **Step 8: Run the repository-wide gate**

Run:

```bash
Scripts/verify-v1.sh
```

Expected: locked dependency install, all TypeScript tests/typecheck/build, editor and extension Playwright tests, privacy verification, Xcode generation, app/native-host tests, signed Debug build, and artifact validation all pass.

- [ ] **Step 9: Run two independent final reviews**

Request:

1. a code-quality review focused on pointer/history/output races, invalid-state handling, and strict bridge validation;
2. a test review focused on missing behavioral regressions and screenshot false positives.

Resolve every P0/P1/P2 finding, rerun the affected focused suite, then rerun `Scripts/verify-v1.sh`. Repeat until both reviewers return no findings.

- [ ] **Step 10: Commit documentation and final integration changes**

Run:

```bash
git diff --check
git status --short
git add README.md docs Packages/editor Sources/MyShottrApp Tests/MyShottrTests Scripts/verify-v1.sh pnpm-lock.yaml project.yml
git diff --cached --name-only
git commit -m "docs(release): v0.1.0 편집기 동작과 검증 갱신"
```

Before committing, confirm the staged set contains only reviewed final-integration/documentation changes and no generated local build products.

- [ ] **Step 11: Re-run the exact release handoff from the existing public-release plan**

Use the tag/package/GitHub Release workflow already approved for v0.1.0. The release handoff must consume the exact commit that passed the full gate; do not rebuild from an uncommitted or different tree.

Record:

```text
release commit SHA
tag
CI run URL and conclusion
GitHub Release URL
DMG/ZIP checksum
downloaded artifact launch result
```

Do not declare release complete until the public artifact is downloadable and launches on a clean verification path.

## Final Acceptance Matrix

| Area | Required evidence |
| --- | --- |
| Schema | TS and Swift v1/v2→v3 tests; exact-key rejection; schema-4 rejection |
| Defaults | v1 preferences→v2; defaults survive scene Undo; defaults-only change sends no `documentChanged` |
| Shortcuts | `KeyboardEvent.code`, IME suppression, no Command-Y, native output ownership |
| Creation | all tool previews, rAF bound, pointer snapshot, one release command |
| Selection | rotated-AABB marquee intersection, Shift-click, one canonical `selectedIds` |
| Manipulation | ephemeral move/transform, Option-drag/Cmd-D shared primitive, held nudge one Undo |
| Viewport | full measured Stage, 10–800%, pointer anchor, clamps, fit, rail reflow |
| Context Rail | hidden/default/single/multi/mixed, direct controls, one semantic command |
| Layering | identical global `zIndex` order in canvas and PNG export |
| History bridge | initial and locked availability, one native action, successful change publication |
| Output | one-operation guard, Copy hide-after-pasteboard, Save superseded, sanitized Export name |
| Feedback | 150 ms delay, stale ID rejection, correct toast durations, polite live region |
| Accessibility | focus order/rings, labels, tooltip focus, contrast, dialog trap/restore, reduced motion |
| Recovery/scope | no recovery path; no full-page capture or mockup UI |
| Release | full gate SHA equals tag/release SHA; public artifact download and launch verified |
