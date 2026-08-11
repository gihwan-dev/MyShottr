# Inkbeam Middle-Button Canvas Pan Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add an Excalidraw-style middle-mouse drag that pans the Inkbeam editor viewport from any canvas target, including Transformer handles and the live text editor, without changing annotations, selection, focus, or history.

**Architecture:** `EditorCanvas` intercepts non-left pointer input at the outer DOM capture boundary, owns middle-pointer capture, and routes accepted middle drags through the same semantic `InteractionController` viewport-pan lifecycle used by Space-drag. `App` supplies separate annotation-interaction and viewport-pan locks so text editing can block annotation gestures while still permitting middle pan; `ViewportController` remains input-device agnostic.

**Tech Stack:** TypeScript 5.9, React 19, React DOM pointer events, Konva 10, Vitest 3, Testing Library 16, Playwright 1.54, Vite 7, pnpm 10

## Global Constraints

- Execute from `/Users/choegihwan/Documents/MyShottr/.worktrees/myshottr-v1` on branch `worktree/fix-region-auto-capture`.
- The approved source of truth is `docs/superpowers/specs/2026-08-11-inkbeam-middle-button-pan-design.md`.
- Preserve the pre-existing uncommitted capture-cursor changes in `Sources/InkbeamApp/Capture/RegionSelectionController.swift` and `Tests/InkbeamTests/Capture/RegionSelectionStateTests.swift`. Never stage either file in an editor task.
- Preserve commit `2edbb10` and the design commits `8d8e633` and `0e0a269`; do not rewrite or squash them while implementing this plan.
- A middle-button drag starts when native `button === 1`, owns only its initiating `pointerId`, pans in raw workspace coordinates, and ends exactly once.
- Middle pan takes precedence over empty canvas, annotations, selection outlines, Transformer handles, and the active text-editor textarea.
- Middle pan must never create, select, move, resize, edit, commit, cancel, or add history; the selected tool and selection remain unchanged.
- A middle press arriving during another active pointer interaction is suppressed but must not convert, cancel, or hijack that interaction.
- Right-button input remains non-mutating; ordinary left-button, Space-drag, wheel/trackpad pan, and Command/Control-wheel zoom keep their current behavior.
- An active text editor locks annotation interactions but not middle-button viewport pan. An active nudge transaction locks both.
- Pointer-up commits the final pending pan delta. Pointer-cancel, blur, Escape, and unmount release capture and prevent late callbacks.
- The active middle pan cursor is `grabbing`; it has no pre-press `grab` state. Existing Space readiness remains `grab`.
- Prevent middle-button pointer, compatibility-mousedown, and auxiliary-click browser defaults so WKWebView/Chromium auto-scroll cannot appear.
- Do not add dependencies, a second viewport store, synthetic wheel events, inertial motion, mouse-button remapping, or new bridge/schema/protocol variants.
- Do not edit historical release evidence under `docs/testing/historical/`.
- Use TDD for every behavior change: add the failing assertion, run it and capture the intended RED, add the smallest implementation, rerun the focused test to GREEN, then commit only that task's files.
- Run editor unit tests serially with the existing Vitest configuration and Playwright with the package's existing single-worker configuration.
- Do not claim real-app acceptance until the signed Debug app has been launched and the user has confirmed the physical middle-button gesture.

---

## Pre-execution State

At plan creation:

```text
branch: worktree/fix-region-auto-capture
HEAD:   0e0a269 docs(editor): clarify middle pan lock boundary
ahead:  3 commits from origin/main
dirty:  Sources/InkbeamApp/Capture/RegionSelectionController.swift
        Tests/InkbeamTests/Capture/RegionSelectionStateTests.swift
```

Those two dirty Swift files belong to the already-tested initial-crosshair fix. Editor workers may read them but must not modify, stage, format, or revert them.

## File Responsibility Map

```text
Packages/editor/src/
├── App.tsx
│   └── owns lock reasons and passes annotation/pan locks into EditorCanvas
├── App.test.tsx
│   └── proves App lock wiring and Escape priority for middle pan
├── canvas/
│   ├── EditorCanvas.tsx
│   │   └── owns pointer classification, capture, pan lifecycle, and cursor feedback
│   ├── EditorCanvas.test.tsx
│   │   └── proves input precedence, raw deltas, cleanup, focus, and non-mutation
│   └── tools/ToolController.ts
│       └── maps semantic viewport-pan state to grab/grabbing cursors
├── components/
│   └── ShortcutHelpDialog.test.tsx
│       └── proves the new help-only gesture is visible to users
├── input/
│   └── shortcutRegistry.ts
│       └── remains the single source of shortcut/help copy
└── interaction/
    ├── InteractionController.ts
    │   └── snapshots semantic viewport-pan intent independent of input device
    └── InteractionController.test.ts
        └── proves pan intent is captured at pointer-down

Packages/editor/tests/visual/
├── entry.tsx
│   └── provides selected-handle, active-textarea, viewport, and state probes
└── editor.middle-pan.spec.ts
    └── exercises real Konva and textarea input with Playwright's middle button

README.md
└── documents Space, middle-button, wheel/trackpad, and zoom navigation
```

## Shared Interfaces Produced by This Plan

```ts
export type InteractionBeginInput = {
  pointerId: number;
  tool: EditorTool;
  point: Point;
  modifiers: InteractionModifiers;
  defaults: EditorDefaults;
  document: EditorDocument;
  selectedIds: readonly string[];
  viewportPan: boolean;
  zoom: number;
};

export type EditorCanvasProps = {
  interactionLocked: boolean;
  viewportPanLocked: boolean;
};

type ViewportPanSource = "space" | "middle";
type ViewportPanState = "inactive" | "ready" | "active";
```

`interactionLocked` blocks ordinary canvas creation, selection, move, resize, and Space-stage entry. `viewportPanLocked` blocks middle pan and any Space-pan attempt if annotation interaction is otherwise allowed. `App` passes:

```tsx
interactionLocked={nudgeSession !== undefined || textLocked}
viewportPanLocked={nudgeSession !== undefined}
```

## Specification Coverage Matrix

| Approved requirement | Plan coverage |
| --- | --- |
| Semantic pan independent of input device | Task 1 controller refactor and focused RED/GREEN |
| Middle drag from every canvas target | Task 2 shell capture and precedence unit tests |
| Raw workspace delta at non-default zoom | Task 2 primary terminal-flush test |
| No annotation, selection, focus, or history mutation | Task 2 history/textarea tests and Task 4 browser probes |
| Transformer-handle precedence | Task 2 unit boundary and Task 4 real Konva anchor test |
| Active textarea precedence with lock split | Task 2 App/canvas tests and Task 4 real textarea test |
| Pointer identity and late-middle isolation | Task 2 stray terminal and active-left tests |
| Pointer-up/cancel/blur/Escape/unmount cleanup | Task 2 lifecycle tests and App Escape test |
| `grabbing` feedback and browser-default suppression | Task 2 cursor and native-event assertions |
| Right/left/Space/wheel/zoom preservation | Task 2 regression suite and Task 5 full gates |
| Shortcut discoverability and current documentation | Task 3 help-dialog test and README |
| Signed-app physical-device acceptance | Task 5 canonical build and user manual gate |

---

### Task 1: Generalize the Semantic Viewport-Pan Intent

**Files:**

- Modify: `Packages/editor/src/interaction/InteractionController.ts:29-214`
- Test: `Packages/editor/src/interaction/InteractionController.test.ts:188-202,254-272`
- Modify: `Packages/editor/src/canvas/tools/ToolController.ts:1-16`
- Test: `Packages/editor/src/canvas/tools/createElement.test.ts:157-163`

**Interfaces:**

- Consumes: existing `InteractionPreview`/`InteractionCommit` viewport variants and `delta(start, point)`.
- Produces: `InteractionBeginInput.viewportPan: boolean`; `ActiveInteraction.viewportPan: boolean`; semantically named `cursorForTool(tool, viewportPanState)` parameter.

- [ ] **Step 1: Write the failing semantic-pan test and update its input fixture**

Replace the keyboard-specific test and `beginInput` default in `InteractionController.test.ts`:

```ts
it("snapshots viewport-pan intent at pointer-down independently of the active tool", () => {
  const controller = new InteractionController();

  expect(controller.begin(beginInput({
    tool: "rectangle",
    viewportPan: true,
  }))).toEqual({
    type: "viewport",
    pan: { x: 0, y: 0 },
  });
  expect(controller.update({ x: 35, y: 55 }, NO_MODIFIERS)).toEqual({
    type: "viewport",
    pan: { x: 25, y: 35 },
  });
  expect(controller.commit({ x: 40, y: 60 }, NO_MODIFIERS)).toEqual({
    type: "viewport",
    pan: { x: 30, y: 40 },
  });
});

function beginInput(
  overrides: Partial<InteractionBeginInput> = {},
): InteractionBeginInput {
  return {
    pointerId: 1,
    tool: "rectangle",
    point: { x: 10, y: 20 },
    modifiers: NO_MODIFIERS,
    defaults: fixtureDocument().defaults,
    document: fixtureDocument({ elements: [] }),
    selectedIds: [],
    viewportPan: false,
    zoom: 1,
    ...overrides,
  };
}
```

- [ ] **Step 2: Run the focused test to verify genuine RED**

Run:

```bash
pnpm --filter @inkbeam/editor exec vitest run \
  src/interaction/InteractionController.test.ts \
  --reporter=verbose
```

Expected: the viewport-pan test fails because production still reads `spaceHeld`, or the compile transform reports that the old `spaceHeld` contract no longer matches the updated fixture. No production file has changed yet.

- [ ] **Step 3: Replace the keyboard-specific controller field with semantic intent**

Apply these exact semantic changes in `InteractionController.ts`:

```ts
export type InteractionBeginInput = {
  pointerId: number;
  tool: EditorTool;
  point: Point;
  modifiers: InteractionModifiers;
  defaults: EditorDefaults;
  document: EditorDocument;
  selectedIds: readonly string[];
  viewportPan: boolean;
  zoom: number;
};

// Inside begin(...)
this.interaction = {
  snapshot: {
    pointerId: input.pointerId,
    tool: input.tool,
    defaults,
    selectedElements,
    start: { ...input.point },
    modifiers: { ...input.modifiers },
    zoom: input.zoom,
  },
  document,
  selectedIds: [...input.selectedIds],
  viewportPan: input.viewportPan,
  points: [{ ...input.point }],
  previewId: createElementId(),
};
const preview = input.viewportPan || input.tool === "numberMarker"
  ? this.previewFor(this.interaction, input.point, input.modifiers, false)
  : { type: "none" } as const;

// In commit(...) and previewFor(...)
if (interaction.viewportPan) {
  return { type: "viewport", pan: delta(interaction.snapshot.start, point) };
}

type ActiveInteraction = {
  snapshot: InteractionSnapshot;
  document: EditorDocument;
  selectedIds: readonly string[];
  viewportPan: boolean;
  points: Point[];
  previewId: string;
};
```

Rename only the parameter in `ToolController.ts`; behavior and the public state union stay unchanged:

```ts
export function cursorForTool(
  tool: EditorTool,
  viewportPanState: "inactive" | "ready" | "active" = "inactive",
): string {
  if (viewportPanState === "active") return "grabbing";
  if (viewportPanState === "ready") return "grab";
  if (tool === "selection") return "default";
  if (tool === "text") return "text";
  return "crosshair";
}
```

- [ ] **Step 4: Run focused GREEN plus type checking**

Run:

```bash
pnpm --filter @inkbeam/editor exec vitest run \
  src/interaction/InteractionController.test.ts \
  src/canvas/tools/createElement.test.ts \
  --reporter=verbose
pnpm --filter @inkbeam/editor typecheck
```

Expected: both test files pass and TypeScript reports no remaining `spaceHeld` consumer.

Verify the old internal name is gone:

```bash
rg -n "spaceHeld" Packages/editor/src
```

Expected: no matches.

- [ ] **Step 5: Commit Task 1 only**

```bash
git add \
  Packages/editor/src/interaction/InteractionController.ts \
  Packages/editor/src/interaction/InteractionController.test.ts \
  Packages/editor/src/canvas/tools/ToolController.ts
git diff --cached --check
git commit -m "refactor(editor): generalize viewport pan intent"
```

Do not stage the unrelated Swift files.

---

### Task 2: Route Middle-Button Input Through the Shared Canvas Lifecycle

**Files:**

- Modify: `Packages/editor/src/canvas/EditorCanvas.tsx:1-452`
- Test: `Packages/editor/src/canvas/EditorCanvas.test.tsx:1-340,481-660,878-936,2431-2480`
- Modify: `Packages/editor/src/App.tsx:564-606`
- Test: `Packages/editor/src/App.test.tsx:29-120,831-859,1000-1030,1257-1295`
- Modify: `Packages/editor/tests/visual/entry.tsx:351-381` only to pass the new required lock until Task 4 adds the editing fixture

**Interfaces:**

- Consumes: `InteractionBeginInput.viewportPan` from Task 1; existing `onViewportPanBy`, `cancelInteraction()`, `ViewportController.panBy`, pointer capture, RAF, and App Escape routing.
- Produces: required `EditorCanvasProps.viewportPanLocked`; shell-owned middle input; `ViewportPanSource = "space" | "middle"`; one shared pointer begin/update/commit/cancel lifecycle.

- [ ] **Step 1: Extend the test seams before adding behavior assertions**

In `EditorCanvas.test.tsx`, import `createEvent`, preserve native button state in the Stage mock, and add an explicit shell-capture helper:

```ts
import {
  act,
  cleanup,
  createEvent,
  fireEvent,
  render,
  screen,
  within,
} from "@testing-library/react";

// Inside eventFor(...)
evt: {
  pointerId: "pointerId" in event ? event.pointerId : 0,
  button: "button" in event ? event.button : 0,
  buttons: "buttons" in event ? event.buttons : 0,
  shiftKey: event.shiftKey,
  altKey: event.altKey,
  metaKey: event.metaKey,
  ctrlKey: event.ctrlKey,
  deltaX: "deltaX" in event ? Number(event.deltaX) : 0,
  deltaY: "deltaY" in event ? Number(event.deltaY) : 0,
  preventDefault: () => {
    konvaControl.preventDefault();
    event.preventDefault();
  },
},

function installCanvasShellPointerCapture() {
  const shell = screen.getByTestId("editor-canvas") as HTMLDivElement;
  const captured = new Set<number>();
  const setPointerCapture = vi.fn((pointerId: number) => captured.add(pointerId));
  const releasePointerCapture = vi.fn((pointerId: number) => captured.delete(pointerId));
  const hasPointerCapture = vi.fn((pointerId: number) => captured.has(pointerId));
  Object.assign(shell, {
    setPointerCapture,
    releasePointerCapture,
    hasPointerCapture,
  });
  return { shell, captured, setPointerCapture, releasePointerCapture };
}
```

Add `viewportPanLocked: false` to `VIEWPORT_PROPS` so every existing canvas test remains explicit.

- [ ] **Step 2: Write the primary middle-pan test and verify RED**

Add beside the existing Space-pan tests:

```tsx
it("pans by raw workspace delta from a middle-button drag at non-default zoom", () => {
  const onViewportPanBy = vi.fn();
  const onInteractionActiveChange = vi.fn();
  const onCommand = vi.fn();
  renderCreationCanvas("rectangle", {
    viewport: { ...VIEWPORT, zoom: 2 },
    onViewportPanBy,
    onInteractionActiveChange,
    onCommand,
  });
  const { shell, setPointerCapture, releasePointerCapture } =
    installCanvasShellPointerCapture();
  const stage = screen.getByTestId("stage");
  const pointerDown = createEvent.pointerDown(stage, {
    button: 1,
    buttons: 4,
    clientX: 110,
    clientY: 120,
    pointerId: 41,
    cancelable: true,
  });

  fireEvent(stage, pointerDown);
  expect(pointerDown.defaultPrevented).toBe(true);
  expect(shell.style.cursor).toBe("grabbing");
  fireEvent.pointerUp(stage, {
    button: 1,
    buttons: 0,
    clientX: 999,
    clientY: 999,
    pointerId: 99,
  });
  expect(onInteractionActiveChange.mock.calls.map(([active]) => active))
    .toEqual([true]);
  fireEvent.pointerMove(stage, {
    button: 1,
    buttons: 4,
    clientX: 145,
    clientY: 168,
    pointerId: 41,
  });
  fireEvent.pointerUp(stage, {
    button: 1,
    buttons: 0,
    clientX: 145,
    clientY: 168,
    pointerId: 41,
  });

  expect(onViewportPanBy).toHaveBeenCalledWith({ x: 35, y: 48 });
  expect(onInteractionActiveChange.mock.calls.map(([active]) => active))
    .toEqual([true, false]);
  expect(onCommand).not.toHaveBeenCalled();
  expect(setPointerCapture).toHaveBeenCalledWith(41);
  expect(releasePointerCapture).toHaveBeenCalledWith(41);
  expect(shell.style.cursor).toBe("crosshair");
});
```

Do not manually flush the queued animation frame in this primary test. Its
`pointerUp` assertion intentionally proves that the terminal path applies the
final pending delta before cleanup.

Run:

```bash
pnpm --filter @inkbeam/editor exec vitest run \
  src/canvas/EditorCanvas.test.tsx \
  -t "middle-button" \
  --reporter=verbose
```

Expected: FAIL because the shell has no middle-button capture lifecycle and the controller receives no viewport-pan request.

- [ ] **Step 3: Add precedence, cleanup, lock, and non-mutation RED tests**

Add the following observable contracts to `EditorCanvas.test.tsx`. Use the existing `renderSelectionCanvas`, `renderCreationCanvas`, history store, Transformer mock, and animation-frame helper; do not assert private refs.

```tsx
it.each([
  ["annotation", "annotation-node"],
  ["transformer handle", "transformer"],
] as const)("gives middle-button pan precedence over a selected %s", (_label, testId) => {
  const initial = fixtureDocument();
  const history = createHistoryStore(initial);
  const onSelect = vi.fn();
  const onViewportPanBy = vi.fn();
  renderSelectionCanvas(initial, history, ["rect-1"], {
    onSelect,
    onViewportPanBy,
  });
  installCanvasShellPointerCapture();
  const target = screen.getByTestId(testId);

  fireEvent.pointerDown(target, {
    button: 1,
    buttons: 4,
    clientX: 200,
    clientY: 210,
    pointerId: 42,
  });
  fireEvent.pointerMove(target, {
    button: 1,
    buttons: 4,
    clientX: 245,
    clientY: 250,
    pointerId: 42,
  });
  flushAnimationFrame();
  fireEvent.pointerUp(target, {
    button: 1,
    buttons: 0,
    clientX: 245,
    clientY: 250,
    pointerId: 42,
  });

  expect(onViewportPanBy).toHaveBeenCalledWith({ x: 45, y: 40 });
  expect(history.document).toEqual(initial);
  expect(history.canUndo).toBe(false);
  expect(onSelect).not.toHaveBeenCalled();
  expect(konvaControl.stopDrag).not.toHaveBeenCalled();
  expect(konvaControl.stopTransform).not.toHaveBeenCalled();
});

it("pans from an active textarea while preserving focus, draft, and edit state", () => {
  const onViewportPanBy = vi.fn();
  const onTextResult = vi.fn();
  renderCreationCanvas("rectangle", {
    interactionLocked: true,
    viewportPanLocked: false,
    onViewportPanBy,
    textEditorOverlay: (
      <textarea
        aria-label="Edit annotation text"
        defaultValue="Draft stays here"
        onBlur={onTextResult}
      />
    ),
  });
  installCanvasShellPointerCapture();
  const textarea = screen.getByRole("textbox", {
    name: "Edit annotation text",
  }) as HTMLTextAreaElement;
  textarea.focus();

  fireEvent.pointerDown(textarea, {
    button: 1,
    buttons: 4,
    clientX: 300,
    clientY: 250,
    pointerId: 43,
  });
  fireEvent.pointerMove(textarea, {
    button: 1,
    buttons: 4,
    clientX: 330,
    clientY: 290,
    pointerId: 43,
  });
  flushAnimationFrame();
  fireEvent.pointerUp(textarea, {
    button: 1,
    buttons: 0,
    clientX: 330,
    clientY: 290,
    pointerId: 43,
  });

  expect(onViewportPanBy).toHaveBeenCalledWith({ x: 30, y: 40 });
  expect(document.activeElement).toBe(textarea);
  expect(textarea.value).toBe("Draft stays here");
  expect(onTextResult).not.toHaveBeenCalled();
});

it("keeps viewport pan locked during a nudge-style lock", () => {
  const onViewportPanBy = vi.fn();
  renderCreationCanvas("rectangle", {
    interactionLocked: true,
    viewportPanLocked: true,
    onViewportPanBy,
  });
  installCanvasShellPointerCapture();
  const stage = screen.getByTestId("stage");

  fireEvent.pointerDown(stage, {
    button: 1,
    buttons: 4,
    pointerId: 44,
  });
  fireEvent.pointerMove(stage, {
    button: 1,
    buttons: 4,
    clientX: 40,
    clientY: 50,
    pointerId: 44,
  });

  expect(onViewportPanBy).not.toHaveBeenCalled();
});
```

Add these lifecycle cases using the same event shape:

```ts
it.each(["pointercancel", "blur"] as const)(
  "ends middle-button pan exactly once on %s and permits the next gesture",
  (terminal) => {
    const onViewportPanBy = vi.fn();
    const onInteractionActiveChange = vi.fn();
    renderCreationCanvas("rectangle", {
      onViewportPanBy,
      onInteractionActiveChange,
    });
    installCanvasShellPointerCapture();
    const stage = screen.getByTestId("stage");

    fireEvent.pointerDown(stage, {
      button: 1,
      buttons: 4,
      clientX: 10,
      clientY: 20,
      pointerId: 51,
    });
    fireEvent.pointerMove(stage, {
      button: 1,
      buttons: 4,
      clientX: 30,
      clientY: 45,
      pointerId: 51,
    });
    flushAnimationFrame();
    if (terminal === "pointercancel") {
      fireEvent.pointerCancel(stage, { pointerId: 51 });
      fireEvent.pointerCancel(stage, { pointerId: 51 });
    } else {
      window.dispatchEvent(new Event("blur"));
      window.dispatchEvent(new Event("blur"));
    }
    fireEvent.pointerMove(stage, {
      button: 1,
      buttons: 4,
      clientX: 80,
      clientY: 90,
      pointerId: 51,
    });
    fireEvent.pointerUp(stage, {
      button: 1,
      buttons: 0,
      clientX: 80,
      clientY: 90,
      pointerId: 51,
    });

    expect(onViewportPanBy).toHaveBeenCalledTimes(1);
    expect(onInteractionActiveChange.mock.calls.map(([active]) => active))
      .toEqual([true, false]);

    fireEvent.pointerDown(stage, {
      button: 1,
      buttons: 4,
      clientX: 100,
      clientY: 110,
      pointerId: 52,
    });
    fireEvent.pointerMove(stage, {
      button: 1,
      buttons: 4,
      clientX: 120,
      clientY: 140,
      pointerId: 52,
    });
    flushAnimationFrame();
    fireEvent.pointerUp(stage, {
      button: 1,
      buttons: 0,
      clientX: 120,
      clientY: 140,
      pointerId: 52,
    });

    expect(onViewportPanBy).toHaveBeenLastCalledWith({ x: 20, y: 30 });
    expect(onInteractionActiveChange.mock.calls.map(([active]) => active))
      .toEqual([true, false, true, false]);
  },
);

it("does not let a late middle press convert an active left-button creation", () => {
  const onCommand = vi.fn();
  const onViewportPanBy = vi.fn();
  renderCreationCanvas("rectangle", { onCommand, onViewportPanBy });
  installCanvasShellPointerCapture();
  const stage = screen.getByTestId("stage");

  fireEvent.pointerDown(stage, {
    button: 0,
    buttons: 1,
    clientX: 10,
    clientY: 20,
    pointerId: 61,
  });
  fireEvent.pointerDown(stage, {
    button: 1,
    buttons: 5,
    clientX: 15,
    clientY: 25,
    pointerId: 62,
  });
  fireEvent.pointerMove(stage, {
    button: 0,
    buttons: 1,
    clientX: 50,
    clientY: 60,
    pointerId: 61,
  });
  fireEvent.pointerUp(stage, {
    button: 0,
    buttons: 0,
    clientX: 50,
    clientY: 60,
    pointerId: 61,
  });

  expect(onCommand).toHaveBeenCalledOnce();
  expect(onCommand).toHaveBeenCalledWith({
    type: "create",
    element: expect.objectContaining({
      type: "rectangle",
      x: 10,
      y: 20,
      width: 40,
      height: 40,
    }),
  });
  expect(onViewportPanBy).not.toHaveBeenCalled();
});

it("keeps right-button input inert and ordinary left creation unchanged", () => {
  const onCommand = vi.fn();
  renderCreationCanvas("rectangle", { onCommand });
  installCanvasShellPointerCapture();
  const stage = screen.getByTestId("stage");

  fireEvent.pointerDown(stage, {
    button: 2,
    buttons: 2,
    clientX: 10,
    clientY: 20,
    pointerId: 63,
  });
  fireEvent.pointerMove(stage, {
    button: 2,
    buttons: 2,
    clientX: 40,
    clientY: 50,
    pointerId: 63,
  });
  fireEvent.pointerUp(stage, {
    button: 2,
    buttons: 0,
    clientX: 40,
    clientY: 50,
    pointerId: 63,
  });
  expect(onCommand).not.toHaveBeenCalled();

  fireEvent.pointerDown(stage, {
    button: 0,
    buttons: 1,
    clientX: 10,
    clientY: 20,
    pointerId: 64,
  });
  fireEvent.pointerUp(stage, {
    button: 0,
    buttons: 0,
    clientX: 40,
    clientY: 50,
    pointerId: 64,
  });
  expect(onCommand).toHaveBeenCalledOnce();
});

it("prevents compatibility mousedown and auxclick for the middle button", () => {
  const onCommand = vi.fn();
  renderCreationCanvas("rectangle", { onCommand });
  installCanvasShellPointerCapture();
  const stage = screen.getByTestId("stage");
  const mouseDown = new MouseEvent("mousedown", {
    bubbles: true,
    button: 1,
    cancelable: true,
  });
  const auxClick = new MouseEvent("auxclick", {
    bubbles: true,
    button: 1,
    cancelable: true,
  });

  fireEvent(stage, mouseDown);
  fireEvent(stage, auxClick);

  expect(mouseDown.defaultPrevented).toBe(true);
  expect(auxClick.defaultPrevented).toBe(true);
  expect(onCommand).not.toHaveBeenCalled();
});

it("releases middle-pointer capture and drops a queued frame on unmount", () => {
  const onCommand = vi.fn();
  const onViewportPanBy = vi.fn();
  const view = renderCreationCanvas("rectangle", {
    onCommand,
    onViewportPanBy,
  });
  const { releasePointerCapture } = installCanvasShellPointerCapture();
  const stage = screen.getByTestId("stage");

  fireEvent.pointerDown(stage, {
    button: 1,
    buttons: 4,
    clientX: 10,
    clientY: 20,
    pointerId: 65,
  });
  fireEvent.pointerMove(stage, {
    button: 1,
    buttons: 4,
    clientX: 40,
    clientY: 55,
    pointerId: 65,
  });
  const queuedFrame = animationFrames.values().next().value as
    | FrameRequestCallback
    | undefined;
  if (!queuedFrame) throw new Error("Expected one queued animation frame");

  view.unmount();
  act(() => queuedFrame(0));

  expect(cancelAnimationFrame).toHaveBeenCalledOnce();
  expect(releasePointerCapture).toHaveBeenCalledWith(65);
  expect(onCommand).not.toHaveBeenCalled();
  expect(onViewportPanBy).not.toHaveBeenCalled();
});
```

Run the complete focused file and retain the RED output showing every new behavior fails for the intended missing routing, not because of a test harness exception:

```bash
pnpm --filter @inkbeam/editor exec vitest run \
  src/canvas/EditorCanvas.test.tsx \
  --reporter=verbose
```

- [ ] **Step 4: Implement one shared pointer lifecycle and shell capture boundary**

In `EditorCanvas.tsx`, add `type PointerEvent as ReactPointerEvent` to the
existing React import, add the required `viewportPanLocked: boolean` line to
`EditorCanvasProps`, destructure it with the other props, and add the semantic
state:

```ts
import {
  forwardRef,
  useEffect,
  useImperativeHandle,
  useMemo,
  useRef,
  useState,
  type PointerEvent as ReactPointerEvent,
  type ReactNode,
} from "react";

viewportPanLocked: boolean;

type ViewportPanSource = "space" | "middle";

const viewportPanSource = useRef<ViewportPanSource>();
const [isViewportPanning, setIsViewportPanning] = useState(false);
```

Replace `spacePanActive`/`isSpacePanning` reads and cleanup with `viewportPanSource`/`isViewportPanning`. A Stage point is a source point only when no viewport pan source is active:

```ts
const interactionPoint = (stage: Konva.Stage): Point => {
  const point = workspacePoint(stage);
  return viewportPanSource.current ? point : toSourcePoint(point);
};

const workspacePointFromPointer = (
  event: ReactPointerEvent<HTMLDivElement>,
): Point => {
  const bounds = event.currentTarget.getBoundingClientRect();
  return {
    x: event.clientX - bounds.left,
    y: event.clientY - bounds.top,
  };
};
```

Extract these shared helpers from the existing Stage handlers. Keep the current RAF and final-delta behavior:

```ts
const beginPointerInteraction = ({
  pointerId,
  point,
  modifiers,
  panSource,
  captureOwner,
}: {
  pointerId: number;
  point: Point;
  modifiers: InteractionModifiers;
  panSource: ViewportPanSource | undefined;
  captureOwner: HTMLDivElement;
}): boolean => {
  if (interactionController.active) return false;
  viewportPanSource.current = panSource;
  appliedViewportPan.current = { x: 0, y: 0 };
  const preview = interactionController.begin({
    pointerId,
    tool,
    point,
    modifiers,
    defaults: document.defaults,
    document,
    selectedIds,
    viewportPan: panSource !== undefined,
    zoom: viewport.zoom,
  });
  captureOwner.setPointerCapture(pointerId);
  captureContainer.current = captureOwner;
  capturedPointerId.current = pointerId;
  if (preview) applyPreview(preview);
  setIsViewportPanning(panSource !== undefined);
  onInteractionActiveChange(true);
  return true;
};

const schedulePointerMove = (
  point: Point,
  modifiers: InteractionModifiers,
): void => {
  latestMove.current = { point, modifiers };
  if (frame.current !== null) return;
  frame.current = requestAnimationFrame(() => {
    frame.current = null;
    if (disposed.current) return;
    const latest = latestMove.current;
    latestMove.current = undefined;
    if (latest) {
      applyPreview(interactionController.update(latest.point, latest.modifiers));
    }
  });
};

const commitPointerInteraction = (
  point: Point,
  modifiers: InteractionModifiers,
): void => {
  try {
    flushScheduledMove();
    applyPreview(interactionController.update(point, modifiers));
    routeCommit(interactionController.commit(point, modifiers));
  } finally {
    finishPointerInteraction();
  }
};
```

Both `finishPointerInteraction` and `cancelPointerInteraction` must reset exactly:

```ts
viewportPanSource.current = undefined;
setIsViewportPanning(false);
```

Add capture handlers to `.canvas-shell`. Non-left input never reaches Konva; only an accepted middle pointer starts pan:

```tsx
<div
  className="canvas-shell"
  data-testid="editor-canvas"
  onPointerDownCapture={(event) => {
    if (event.button === 0) return;
    event.stopPropagation();
    if (event.button !== 1) return;
    event.preventDefault();
    if (
      viewportPanLocked
      || interactionController.active
      || activeAnnotationInteraction.current
      || pendingAnnotationPointer.current
    ) return;
    beginPointerInteraction({
      pointerId: event.pointerId,
      point: workspacePointFromPointer(event),
      modifiers: modifiersFor(event),
      panSource: "middle",
      captureOwner: event.currentTarget,
    });
  }}
  onPointerMoveCapture={(event) => {
    if (
      viewportPanSource.current !== "middle"
      || capturedPointerId.current !== event.pointerId
    ) return;
    event.preventDefault();
    event.stopPropagation();
    schedulePointerMove(workspacePointFromPointer(event), modifiersFor(event));
  }}
  onPointerUpCapture={(event) => {
    if (
      viewportPanSource.current !== "middle"
      || capturedPointerId.current !== event.pointerId
    ) return;
    event.preventDefault();
    event.stopPropagation();
    commitPointerInteraction(workspacePointFromPointer(event), modifiersFor(event));
  }}
  onPointerCancelCapture={(event) => {
    if (
      viewportPanSource.current !== "middle"
      || capturedPointerId.current !== event.pointerId
    ) return;
    event.preventDefault();
    event.stopPropagation();
    cancelPointerInteraction();
  }}
  onMouseDownCapture={(event) => {
    if (event.button === 0) return;
    event.stopPropagation();
    if (event.button === 1) event.preventDefault();
  }}
  onAuxClick={(event) => {
    if (event.button !== 1) return;
    event.preventDefault();
    event.stopPropagation();
  }}
  style={{
    position: "relative",
    cursor: cursorForTool(
      tool,
      isViewportPanning ? "active" : spacePanReady ? "ready" : "inactive",
    ),
  }}
>
```

Update the Stage path to accept ordinary left input only and call the same helpers:

```ts
if (event.evt.button !== 0) return;
if (interactionLocked) return;
if (spacePanReady && viewportPanLocked) return;

const panSource = spacePanReady ? "space" : undefined;
const stagePoint = workspacePoint(stage);
const point = panSource ? stagePoint : toSourcePoint(stagePoint);
beginPointerInteraction({
  pointerId: event.evt.pointerId,
  point,
  modifiers: modifiersFor(event.evt),
  panSource,
  captureOwner: stage.getContent(),
});
```

Use `schedulePointerMove(interactionPoint(stage), modifiersFor(event.evt))` in Stage move and `commitPointerInteraction(interactionPoint(stage), modifiersFor(event.evt))` in Stage up. Retain the existing pending annotation pointer and pointer-identity guards.

- [ ] **Step 5: Split App lock wiring and add App-level RED/GREEN contracts**

Add `viewportPanLocked` to the `EditorCanvas` mock props in `App.test.tsx`, expose it in the mock, and classify the mocked gesture:

```tsx
<output data-testid="canvas-viewport-pan-lock">
  {String(viewportPanLocked === true)}
</output>

const middlePan = event.button === 1;
const spacePan = spacePanReady && event.button === 0;
if (
  pointerGesture.current
  || (middlePan && viewportPanLocked)
  || (!middlePan && interactionLocked)
  || (!middlePan && !spacePan && tool === "selection")
) return;
pointerGesture.current = {
  kind: middlePan || spacePan ? "viewport" : "tool",
  pointerId: event.pointerId,
  tool,
  document: structuredClone(document),
  start: { x: event.clientX, y: event.clientY },
};
onInteractionActiveChange(true);
```

On mocked pointer-up, emit a tool command only when `active.kind === "tool"`.

Pass the production locks in `App.tsx`:

```tsx
<EditorCanvas
  interactionLocked={nudgeSession !== undefined || textLocked}
  viewportPanLocked={nudgeSession !== undefined}
/>
```

Pass `viewportPanLocked={false}` in the visual fixture until Task 4 models a text session.

Add the App Escape contract:

```tsx
it("cancels an active middle-button pan on the first Escape and resumes idle Escape priority", () => {
  const onChange = vi.fn();
  render(<EditorApp
    initialDocument={fixtureDocument({ elements: [] })}
    initialTool="rectangle"
    sourceImageURL="data:image/png;base64,iVBORw0KGgo="
    onChange={onChange}
    onPreferencesChange={() => {}}
  />);
  const canvas = screen.getByTestId("mock-canvas-pointer-surface");
  const rectangle = screen.getByRole("button", {
    name: "Rectangle, shortcut R",
  });
  const selection = screen.getByRole("button", {
    name: "Selection, shortcut V",
  });

  fireEvent.pointerDown(canvas, {
    button: 1,
    buttons: 4,
    clientX: 10,
    clientY: 20,
    pointerId: 72,
  });
  fireEvent.keyDown(window, { code: "Escape", key: "Escape" });
  fireEvent.pointerUp(canvas, {
    button: 1,
    buttons: 0,
    clientX: 40,
    clientY: 50,
    pointerId: 72,
  });

  expect(rectangle.getAttribute("aria-pressed")).toBe("true");
  expect(selection.getAttribute("aria-pressed")).toBe("false");
  expect(onChange).not.toHaveBeenCalled();

  fireEvent.keyDown(window, { code: "Escape", key: "Escape" });
  expect(selection.getAttribute("aria-pressed")).toBe("true");
});
```

Extend the existing text-edit and held-nudge tests with the lock split:

```ts
// While an existing text editor is active:
expect(screen.getByTestId("canvas-interaction-lock").textContent).toBe("true");
expect(screen.getByTestId("canvas-viewport-pan-lock").textContent).toBe("false");

// While a held nudge transaction is active:
expect(screen.getByTestId("canvas-interaction-lock").textContent).toBe("true");
expect(screen.getByTestId("canvas-viewport-pan-lock").textContent).toBe("true");
```

- [ ] **Step 6: Run Task 2 GREEN and mutation-check its primary boundary**

Run:

```bash
pnpm --filter @inkbeam/editor exec vitest run \
  src/canvas/EditorCanvas.test.tsx \
  src/App.test.tsx \
  --reporter=verbose
pnpm --filter @inkbeam/editor typecheck
```

Expected: both files pass; existing Space-pan, annotation move/transform, text edit, and nudge tests remain green.

Perform one manual mutation proof before restoring the implementation: temporarily change the shell classification from `event.button === 1` to `event.button === 2`, rerun only the middle-button tests, and confirm they fail because `onViewportPanBy` is not called. Restore `button === 1` using `apply_patch` and rerun the focused tests to GREEN. Do not use `git checkout` to restore the file.

- [ ] **Step 7: Commit Task 2 only**

```bash
git add \
  Packages/editor/src/canvas/EditorCanvas.tsx \
  Packages/editor/src/canvas/EditorCanvas.test.tsx \
  Packages/editor/src/App.tsx \
  Packages/editor/src/App.test.tsx \
  Packages/editor/tests/visual/entry.tsx
git diff --cached --check
git commit -m "feat(editor): pan canvas with middle button"
```

Do not stage the Swift capture files or either documentation file from another task.

---

### Task 3: Expose the Gesture in Shortcut Help and Current Usage Docs

**Files:**

- Modify: `Packages/editor/src/input/shortcutRegistry.ts:215-227`
- Test: `Packages/editor/src/components/ShortcutHelpDialog.test.tsx:59-82`
- Modify: `README.md:39-53,84-97`

**Interfaces:**

- Consumes: existing `helpOnly(...)`, `SHORTCUT_REGISTRY`, and data-driven `ShortcutHelpDialog`.
- Produces: a current user-visible `Pan with Middle Button` entry whose accessible key label is `Middle Drag`.

- [ ] **Step 1: Write the failing help-dialog assertion**

Extend the modal registry test in `ShortcutHelpDialog.test.tsx`:

```ts
it("shows both Space-drag and middle-button pan in View and Navigation", () => {
  renderEditor();
  fireEvent.keyDown(window, {
    code: "Slash",
    key: "?",
    shiftKey: true,
  });

  const navigationHeading = screen.getByRole("heading", {
    name: "View and Navigation",
  });
  const navigation = navigationHeading.closest("section");
  if (!navigation) throw new Error("View and Navigation section is missing");

  expect(within(navigation).getByText("Pan")).toBeTruthy();
  expect(within(navigation).getByLabelText("Space Drag")).toBeTruthy();
  expect(within(navigation).getByText("Pan with Middle Button")).toBeTruthy();
  expect(within(navigation).getByLabelText("Middle Drag")).toBeTruthy();
});
```

- [ ] **Step 2: Run the focused test to verify RED**

Run:

```bash
pnpm --filter @inkbeam/editor exec vitest run \
  src/components/ShortcutHelpDialog.test.tsx \
  --reporter=verbose
```

Expected: FAIL because `Pan with Middle Button` and `Middle Drag` do not exist.

- [ ] **Step 3: Add one help-only registry entry and update README copy**

Keep the existing Space entry and add exactly:

```ts
helpOnly(
  "view-middle-pan",
  "View and Navigation",
  "Pan with Middle Button",
  ["Middle", "Drag"],
),
```

Update current README text to:

```markdown
- Hold `Space` and drag, drag with the middle mouse button, or scroll to pan.
  Pinch or use `Command`-scroll to zoom around the pointer. `Command-0` sets
  100%, `Shift-1` fits the complete image, and `Shift-2` fits the current
  selection.

- Pan: `Space`-drag, middle-button drag, or scroll
```

Do not edit historical v0.1.0 blocks or historical acceptance documents.

- [ ] **Step 4: Run focused GREEN and documentation contract tests**

Run:

```bash
pnpm --filter @inkbeam/editor exec vitest run \
  src/components/ShortcutHelpDialog.test.tsx \
  --reporter=verbose
node Tests/Release/documentation.test.mjs
node Scripts/verify-clean-cutover.mjs
```

Expected: the shortcut test passes, documentation contracts pass, and the clean-cut scanner reports `clean-cutover: PASS`.

- [ ] **Step 5: Commit Task 3 only**

```bash
git add \
  Packages/editor/src/input/shortcutRegistry.ts \
  Packages/editor/src/components/ShortcutHelpDialog.test.tsx \
  README.md
git diff --cached --check
git commit -m "docs(editor): document middle-button pan"
```

---

### Task 4: Prove Transformer and Textarea Precedence in a Real Browser

**Files:**

- Modify: `Packages/editor/tests/visual/entry.tsx:33-180,220-413`
- Create: `Packages/editor/tests/visual/editor.middle-pan.spec.ts`

**Interfaces:**

- Consumes: the actual React/Konva `EditorCanvas`, `EditorWorkspace`, `TextEditorOverlay`, viewport probe, `selected-rectangle` fixture, and Playwright's `page.mouse` middle-button API.
- Produces: an `editing-text` fixture state, hidden selection/command/text-session probe, and test-only `window.__inkbeamVisualCanvasProbe()` for a real Transformer anchor and selected-node geometry.

- [ ] **Step 1: Add the browser tests first and capture RED**

Create `editor.middle-pan.spec.ts` with complete fixture helpers:

```ts
import { expect, test, type Page } from "@playwright/test";

type ViewportProbe = {
  panX: number;
  panY: number;
  zoom: number;
};

async function gotoFixture(page: Page, state: string): Promise<void> {
  await page.goto(`/tests/visual/visual.html?state=${state}`);
  await expect(page.getByRole("main", { name: "Inkbeam editor" }))
    .toBeVisible();
  await page.waitForFunction(
    (expected) =>
      document.documentElement.dataset.visualFixtureReady === expected,
    state,
  );
}

async function readViewport(page: Page): Promise<ViewportProbe> {
  return page.getByTestId("visual-fixture-viewport").evaluate((element) => ({
    panX: Number(element.dataset.panX),
    panY: Number(element.dataset.panY),
    zoom: Number(element.dataset.zoom),
  }));
}

async function zoomUntilPannable(page: Page): Promise<void> {
  const zoomIn = page.getByRole("button", { name: "Zoom in" });
  for (let index = 0; index < 8; index += 1) {
    await zoomIn.evaluate((button) => (button as HTMLButtonElement).click());
  }
  await expect.poll(async () => (await readViewport(page)).zoom)
    .toBeGreaterThan(1.1);
}

async function middleDrag(
  page: Page,
  start: { x: number; y: number },
  delta: { x: number; y: number },
): Promise<void> {
  await page.mouse.move(start.x, start.y);
  await page.mouse.down({ button: "middle" });
  await page.mouse.move(start.x + delta.x, start.y + delta.y, { steps: 5 });
  await page.mouse.up({ button: "middle" });
}

test("middle-button pan wins over a real Transformer handle", async ({ page }) => {
  await gotoFixture(page, "selected-rectangle");
  await zoomUntilPannable(page);
  const beforeViewport = await readViewport(page);
  const before = await page.evaluate(() => {
    const target = window as typeof window & {
      __inkbeamVisualCanvasProbe?: () => {
        handle: { x: number; y: number };
        geometry: Record<string, number>;
      };
    };
    if (!target.__inkbeamVisualCanvasProbe) {
      throw new Error("Inkbeam visual canvas probe is unavailable");
    }
    return target.__inkbeamVisualCanvasProbe();
  });

  await middleDrag(page, before.handle, { x: -70, y: -55 });

  const afterViewport = await readViewport(page);
  const after = await page.evaluate(() => {
    const target = window as typeof window & {
      __inkbeamVisualCanvasProbe?: () => {
        handle: { x: number; y: number };
        geometry: Record<string, number>;
      };
    };
    return target.__inkbeamVisualCanvasProbe!();
  });
  const state = page.getByTestId("visual-fixture-editor-state");

  expect([afterViewport.panX, afterViewport.panY])
    .not.toEqual([beforeViewport.panX, beforeViewport.panY]);
  expect(afterViewport.zoom).toBe(beforeViewport.zoom);
  expect(after.geometry).toEqual(before.geometry);
  await expect(state).toHaveAttribute("data-selected-ids", "rect-1");
  await expect(state).toHaveAttribute("data-command-count", "0");
});

test("middle-button pan wins over the live text textarea", async ({ page }) => {
  await gotoFixture(page, "editing-text");
  await zoomUntilPannable(page);
  const textarea = page.getByRole("textbox", { name: "Edit annotation text" });
  await expect(textarea).toBeFocused();
  const beforeViewport = await readViewport(page);
  const beforeText = await textarea.evaluate((element) => {
    const input = element as HTMLTextAreaElement;
    return {
      value: input.value,
      selectionStart: input.selectionStart,
      selectionEnd: input.selectionEnd,
    };
  });
  const bounds = await textarea.boundingBox();
  if (!bounds) throw new Error("Text editor bounds are unavailable");

  await middleDrag(page, {
    x: bounds.x + bounds.width / 2,
    y: bounds.y + bounds.height / 2,
  }, { x: -60, y: -50 });

  const afterViewport = await readViewport(page);
  const afterText = await textarea.evaluate((element) => {
    const input = element as HTMLTextAreaElement;
    return {
      value: input.value,
      selectionStart: input.selectionStart,
      selectionEnd: input.selectionEnd,
    };
  });
  const state = page.getByTestId("visual-fixture-editor-state");

  expect([afterViewport.panX, afterViewport.panY])
    .not.toEqual([beforeViewport.panX, beforeViewport.panY]);
  expect(afterText).toEqual(beforeText);
  await expect(textarea).toBeFocused();
  await expect(state).toHaveAttribute("data-text-edit-active", "true");
  await expect(state).toHaveAttribute("data-text-result-count", "0");
  await expect(state).toHaveAttribute("data-command-count", "0");
});
```

Run:

```bash
pnpm --filter @inkbeam/editor test:visual -- --grep "middle-button pan"
```

Expected: RED. `editing-text`, the state probe, and the canvas probe do not exist yet. The failure must occur at those missing approved boundaries, not from a missing browser installation.

- [ ] **Step 2: Extend the visual fixture with real lock and edit-session state**

In `entry.tsx`, import Konva and the actual text editor:

```ts
import Konva from "konva";
import { TextEditorOverlay } from "../../src/components/TextEditorOverlay";
import type { TextEditSession } from "../../src/interaction/textEditSession";
```

Add `editing-text` to `VisualFixtureState`/`VISUAL_STATES`. Extend `Fixture` with `textEditSession?: TextEditSession`. In `fixtureFor(...)`, return:

```ts
case "editing-text":
  return {
    document,
    tool: "selection",
    selectedIds: [text.id],
    shortcutHelpOpen: false,
    textEditSession: {
      kind: "existing",
      element: text,
      initialText: text.text,
    },
  };
```

Do not add `editing-text` to the screenshot matrix in `editor.visual.spec.ts`; it is an interaction fixture, not a new screenshot baseline.

Track only observable harness outcomes:

```ts
const [commandCount, setCommandCount] = useState(0);
const [textEditActive, setTextEditActive] = useState(false);
const [textResultCount, setTextResultCount] = useState(0);

// In the existing configuration frame:
setTextEditActive(fixture.textEditSession !== undefined);
```

Wire the real canvas state:

```tsx
<EditorCanvas
  interactionLocked={textEditActive}
  viewportPanLocked={false}
  onCommand={() => setCommandCount((count) => count + 1)}
  textEditorOverlay={
    textEditActive && fixture.textEditSession
      ? (
          <TextEditorOverlay
            session={fixture.textEditSession}
            zoom={viewport.zoom}
            pan={viewport.pan}
            onResult={() => {
              setTextResultCount((count) => count + 1);
              setTextEditActive(false);
            }}
          />
        )
      : null
  }
/>

<output
  hidden
  data-testid="visual-fixture-editor-state"
  data-selected-ids={selectedIds.join(",")}
  data-command-count={commandCount}
  data-text-edit-active={String(textEditActive)}
  data-text-result-count={textResultCount}
/>
```

- [ ] **Step 3: Expose a test-only real Konva anchor and geometry probe**

Add an effect in `VisualHarness` after configuration. It must throw rather than return fabricated geometry:

```ts
useEffect(() => {
  const target = window as typeof window & {
    __inkbeamVisualCanvasProbe?: () => {
      handle: { x: number; y: number };
      geometry: Record<string, number>;
    };
  };
  target.__inkbeamVisualCanvasProbe = () => {
    const stage = Konva.stages.at(-1);
    if (!stage) throw new Error("Visual fixture Konva stage is unavailable");
    const transformer = stage.findOne(
      (node) => node.getClassName() === "Transformer",
    );
    const anchor = transformer?.findOne(".top-left");
    const selectedNode = stage.findOne(
      (node) => node.getAttr("data-testid") === "element-rect-1",
    );
    if (!anchor || !selectedNode) {
      throw new Error("Selected rectangle Transformer probe is unavailable");
    }
    const stageBounds = stage.container().getBoundingClientRect();
    const handle = anchor.getAbsolutePosition();
    return {
      handle: {
        x: stageBounds.left + handle.x,
        y: stageBounds.top + handle.y,
      },
      geometry: {
        x: selectedNode.x(),
        y: selectedNode.y(),
        scaleX: selectedNode.scaleX(),
        scaleY: selectedNode.scaleY(),
        rotation: selectedNode.rotation(),
      },
    };
  };
  return () => {
    delete target.__inkbeamVisualCanvasProbe;
  };
}, [configurationApplied, selectedIds]);
```

- [ ] **Step 4: Run real-browser GREEN and the complete editor suite**

Run:

```bash
pnpm --filter @inkbeam/editor test:visual -- --grep "middle-button pan"
pnpm --filter @inkbeam/editor test:visual
pnpm --filter @inkbeam/editor test
pnpm --filter @inkbeam/editor typecheck
pnpm --filter @inkbeam/editor build
```

Expected:

- both middle-button Playwright cases pass against real Chromium/Konva;
- the existing visual and accessibility suite remains green without new screenshot files;
- all editor Vitest tests pass;
- typecheck and production build pass, with only the repository's already-known Vite large-chunk warning if it remains present.

- [ ] **Step 5: Commit Task 4 only**

```bash
git add \
  Packages/editor/tests/visual/entry.tsx \
  Packages/editor/tests/visual/editor.middle-pan.spec.ts
git diff --cached --check
git commit -m "test(editor): verify middle pan in browser"
```

---

### Task 5: Run Repository Gates and Produce a User-Testable Signed App

**Files:**

- Verify only; do not create source changes.
- Generated/ignored output: `DerivedData/VerifyInkbeam/Build/Products/Debug/Inkbeam.app`

**Interfaces:**

- Consumes: all Task 1-4 commits and the existing `Scripts/verify-inkbeam.sh` canonical gate.
- Produces: complete automated evidence, a signed Debug app path, and a manual physical-middle-button acceptance gate.

- [ ] **Step 1: Audit scope before the full gate**

Run:

```bash
git status --short --branch
git diff --check
git diff --name-only origin/main...HEAD
git diff --name-only
```

Expected:

- the branch contains the planned editor/documentation commits plus the earlier area-capture commits;
- the only uncommitted paths are the two preserved Swift initial-crosshair files;
- no task accidentally staged or modified unrelated files.

- [ ] **Step 2: Run JavaScript and privacy/release gates**

Run:

```bash
pnpm test
pnpm typecheck
pnpm build
pnpm --filter @inkbeam/editor test:visual
Scripts/verify-privacy.sh
node Scripts/verify-clean-cutover.mjs
pnpm test:release
```

Expected: every command exits `0`; clean cutover prints `clean-cutover: PASS`.

- [ ] **Step 3: Respect the running-app safety gate, then run canonical verification**

Check:

```bash
pgrep -x Inkbeam
```

If a PID is returned, stop and ask the user to save any open document and quit Inkbeam. Do not force-kill a possibly unsaved editor. Once no Inkbeam process remains, run:

```bash
Scripts/verify-inkbeam.sh
```

Expected final output:

```text
Inkbeam automated verification passed.
Signed Debug app: /Users/choegihwan/Documents/MyShottr/.worktrees/myshottr-v1/DerivedData/VerifyInkbeam/Build/Products/Debug/Inkbeam.app
```

- [ ] **Step 4: Verify the artifact and launch it for manual acceptance**

Run:

```bash
codesign --verify --deep --strict --verbose=2 \
  DerivedData/VerifyInkbeam/Build/Products/Debug/Inkbeam.app
open DerivedData/VerifyInkbeam/Build/Products/Debug/Inkbeam.app
```

Manual acceptance sequence for the user:

1. Capture an area and open the editor.
2. Confirm the crosshair is visible before the first click, then drag an area
   and confirm capture opens the editor immediately on release.
3. Select a rectangle and begin middle-button drag directly on a resize handle.
4. Confirm the canvas pans, geometry/selection do not change, and release restores the selection cursor.
5. Enter text editing, keep the textarea focused, and middle-drag from inside it.
6. Confirm the canvas pans while text/focus remain, then press Escape during a separate middle drag and confirm the next shortcut works.
7. Confirm Space-drag, scroll/trackpad pan, Command-scroll zoom, left creation, move, and resize still work.

Do not claim this manual gate or merge the branch until the user confirms the physical gesture.

- [ ] **Step 5: Final review and integration handoff**

After the user confirms both the pre-click crosshair/auto-capture flow and the
middle-button behavior, commit the previously preserved Swift fix separately:

```bash
git add \
  Sources/InkbeamApp/Capture/RegionSelectionController.swift \
  Tests/InkbeamTests/Capture/RegionSelectionStateTests.swift
git diff --cached --check
git commit -m "fix(capture): show crosshair before first click"
```

Request one code-quality review and one test-quality review of
`origin/main...HEAD`. The reviewers must include the now-committed Swift
initial-crosshair change and every middle-pan commit in scope.

After both reviewers report no Critical/Important findings and the user confirms manual acceptance:

```bash
git status --short --branch
git push -u origin worktree/fix-region-auto-capture
gh pr create \
  --base main \
  --head worktree/fix-region-auto-capture \
  --title "feat: polish Inkbeam capture and canvas navigation" \
  --body-file /tmp/inkbeam-capture-pan-pr.md
gh pr checks --watch
gh pr merge --merge --delete-branch
```

Before creating the PR body, write `/tmp/inkbeam-capture-pan-pr.md` with verified scope, exact automated commands/results, the signed app path, and the user's manual acceptance. Do not include unverified claims or the macOS `linkd.autoShortcut` warning as a product failure.
