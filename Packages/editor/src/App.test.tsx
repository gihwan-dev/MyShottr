import { act, cleanup, createEvent, fireEvent, render, screen, within } from "@testing-library/react";
import { createRef, forwardRef, useImperativeHandle, useRef, type ReactNode } from "react";
import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";

import { App, EditorApp, type EditorAppHandle } from "./App";
import { NativeBridgeProvider, type NativeBridge } from "./bridge/nativeBridge";
import type { EditorCanvasHandle } from "./canvas/EditorCanvas";
import { keyboardCommandFor } from "./input/ShortcutRouter";
import type { EditorCommand, EditorDefaults, EditorDocument, EditorTool, Point } from "./model/elements";
import { fixtureDocument, fixtureLine, fixtureRect, fixtureText } from "./test/fixtures";
import type { ViewportSnapshot } from "./viewport/ViewportController";

const exportMocks = vi.hoisted(() => ({
  renderDocumentToBlob: vi.fn(async () => new Blob(["png"], { type: "image/png" })),
  sendComposite: vi.fn(async () => {}),
}));

vi.mock("./export/renderDocumentToBlob", () => ({
  renderDocumentToBlob: exportMocks.renderDocumentToBlob,
}));

vi.mock("./export/sendComposite", () => ({
  sendComposite: exportMocks.sendComposite,
}));

vi.mock("./canvas/EditorCanvas", async () => {
  const { createElementFromDocument } = await import("./canvas/tools/createElement");
  return {
    EditorCanvas: forwardRef<EditorCanvasHandle, {
    document: EditorDocument;
    tool: EditorTool;
    viewport: ViewportSnapshot;
    spacePanReady: boolean;
    interactionLocked: boolean;
    selectedIds: readonly string[];
    onCommand: (command: EditorCommand) => void;
    onSelect: (id: string | undefined, toggle?: boolean) => void;
    onBeginTransaction: (label: string) => void;
    onCommitTransaction: () => void;
    onCancelTransaction: () => void;
    onEditText: (id: string) => void;
    onBeginNewText: (point: Point, defaults: EditorDefaults) => void;
    onInteractionActiveChange: (active: boolean) => void;
    textEditorOverlay: ReactNode;
    }>(function MockEditorCanvas({ document, tool, viewport, spacePanReady, interactionLocked, selectedIds, onCommand, onSelect, onBeginTransaction, onCommitTransaction, onCancelTransaction, onEditText, onBeginNewText, onInteractionActiveChange, textEditorOverlay }, ref) {
      const pointerGesture = useRef<{
        pointerId: number;
        tool: EditorTool;
        document: EditorDocument;
        start: Point;
      } | undefined>(undefined);
      useImperativeHandle(ref, () => ({
        cancelInteraction: () => {
          if (!pointerGesture.current) return false;
          pointerGesture.current = undefined;
          onInteractionActiveChange(false);
          return true;
        },
      }), [onInteractionActiveChange]);
      return (
      <>
      <output data-testid="canvas-opacities">
        {document.elements.map((element) => `${element.id}:${element.opacity}`).join(",")}
      </output>
      <output data-testid="canvas-positions">
        {document.elements.map((element) => `${element.id}:${element.x},${element.y}`).join(";")}
      </output>
      <output data-testid="canvas-selection">{selectedIds.join(",")}</output>
      <output data-testid="canvas-interaction-lock">{String(interactionLocked === true)}</output>
      <output
        data-testid="canvas-viewport"
        data-available={`${viewport.availableRect.x},${viewport.availableRect.y},${viewport.availableRect.width},${viewport.availableRect.height}`}
        data-pan={`${viewport.pan.x},${viewport.pan.y}`}
        data-zoom={viewport.zoom}
      />
      <button type="button" onClick={() => onSelect("rect-1")}>Select rect-1</button>
      <button type="button" onClick={() => onSelect("line-1")}>Select line-1</button>
      <button type="button" onClick={() => onSelect("text-1", true)}>Shift-select text-1</button>
      <button type="button" onClick={() => onSelect("highlighter-1", true)}>Shift-select highlighter-1</button>
      <button type="button" onClick={() => onEditText("text-1")}>Edit text-1</button>
      <button type="button" onClick={() => onInteractionActiveChange(true)}>Begin canvas interaction</button>
      <button type="button" onClick={() => onInteractionActiveChange(false)}>End canvas interaction</button>
      <div
        data-testid="mock-canvas-pointer-surface"
        onPointerDown={(event) => {
          if (
            interactionLocked
            || (!spacePanReady && tool === "selection")
            || pointerGesture.current
          ) return;
          pointerGesture.current = {
            pointerId: event.pointerId,
            tool,
            document: structuredClone(document),
            start: { x: event.clientX, y: event.clientY },
          };
          onInteractionActiveChange(true);
        }}
        onPointerMove={() => {}}
        onPointerUp={(event) => {
          const active = pointerGesture.current;
          if (!active || active.pointerId !== event.pointerId) return;
          pointerGesture.current = undefined;
          const end = { x: event.clientX, y: event.clientY };
          if (active.tool === "text") {
            onBeginNewText(active.start, active.document.defaults);
          } else if (active.tool !== "selection") {
            const gesture = active.tool === "freehand" || active.tool === "highlighter"
              ? { kind: "path" as const, points: [active.start, end] }
              : active.tool === "numberMarker"
                ? { kind: "point" as const, point: active.start }
                : { kind: "box" as const, start: active.start, end };
            onCommand({
              type: "create",
              element: createElementFromDocument(active.document, active.tool, gesture),
            });
          }
          onInteractionActiveChange(false);
        }}
      />
      <button
        type="button"
        onClick={() => onCommand({
          type: "create",
          element: {
            id: "rect-2",
            type: "rectangle",
            x: 10,
            y: 10,
            width: 20,
            height: 20,
            rotation: 0,
            opacity: document.defaults.opacity,
            zIndex: 1,
            seed: 2,
            strokeColor: document.defaults.color,
            strokeWidth: document.defaults.strokeWidth,
            fillColor: document.defaults.rectangleFillColor,
            roughness: document.defaults.roughness,
          },
        })}
      >
        Create rectangle from canvas
      </button>
      <button
        type="button"
        onClick={() => {
          onBeginTransaction("move");
          onCommand({
            type: "update",
            element: { ...document.elements[0], x: 40, y: 50 },
          });
          onCancelTransaction();
        }}
      >
        Move then cancel
      </button>
      <button type="button" onClick={() => onBeginTransaction("defaults")}>
        Begin defaults transaction
      </button>
      <button type="button" onClick={onCommitTransaction}>
        Commit transaction
      </button>
      <button
        type="button"
        onClick={() => onCommand({
          type: "update",
          element: { ...document.elements[0], x: document.elements[0].x + 1 },
        })}
      >
        Update first element
      </button>
      <button
        type="button"
        onClick={() => {
          onBeginTransaction("move");
          onCommand({
            type: "update",
            element: { ...document.elements[0], x: 40, y: 50 },
          });
          onCommitTransaction();
        }}
      >
        Move then commit
      </button>
      {textEditorOverlay}
      </>
      );
    }),
  };
});

beforeEach(() => {
  exportMocks.renderDocumentToBlob.mockClear();
  exportMocks.sendComposite.mockClear();
  vi.stubGlobal("ResizeObserver", class implements ResizeObserver {
    public constructor(private readonly callback: ResizeObserverCallback) {}
    public disconnect() {}
    public observe() {
      this.callback([{
        contentRect: { width: 1000, height: 700 },
      } as ResizeObserverEntry], this);
    }
    public unobserve() {}
  });
  vi.stubGlobal("matchMedia", vi.fn().mockReturnValue({ matches: true }));
  vi.stubGlobal("PointerEvent", class extends MouseEvent {
    public readonly pointerId: number;

    public constructor(type: string, init: PointerEventInit = {}) {
      super(type, init);
      this.pointerId = init.pointerId ?? 0;
    }
  });
  vi.stubGlobal("requestAnimationFrame", vi.fn());
  vi.stubGlobal("cancelAnimationFrame", vi.fn());
  vi.spyOn(HTMLCanvasElement.prototype, "getContext").mockReturnValue({
    font: "",
    measureText: (text: string) => ({ width: text.length * 12 }),
  } as never);
});

afterEach(() => {
  cleanup();
  vi.restoreAllMocks();
  vi.unstubAllGlobals();
});

type NativeMessage = Parameters<NativeBridge["subscribe"]>[0] extends
  (message: infer Message) => void ? Message : never;

type SentBridgeMessage = {
  requestId?: string;
  type: string;
  payload: unknown;
};

function createNativeBridgeHarness() {
  let receiveNative: ((message: NativeMessage) => void) | undefined;
  let onMessageSent: ((message: SentBridgeMessage) => void) | undefined;
  let subscribeCalls = 0;
  const sent: SentBridgeMessage[] = [];
  const record = (message: SentBridgeMessage) => {
    sent.push(message);
    onMessageSent?.(message);
  };
  const bridge: NativeBridge = {
    send: async (type, payload) => { record({ type, payload }); },
    sendCorrelated: async (requestId, type, payload) => {
      record({ requestId, type, payload });
    },
    subscribe: (handler) => {
      subscribeCalls += 1;
      receiveNative = handler;
      return () => { receiveNative = undefined; };
    },
  };
  return {
    bridge,
    sent,
    get subscribeCalls() {
      return subscribeCalls;
    },
    receive(message: NativeMessage) {
      if (!receiveNative) throw new Error("Native bridge is not subscribed");
      receiveNative(message);
    },
    messages(type: string) {
      return sent.filter((message) => message.type === type);
    },
    observeSent(observer: (message: SentBridgeMessage) => void) {
      onMessageSent = observer;
    },
  };
}

function stubImmediatelyLoadedSourceImage(): void {
  vi.stubGlobal("Image", class {
    naturalWidth = 1440;
    naturalHeight = 900;
    onload: (() => void) | null = null;
    set src(_value: string) { queueMicrotask(() => this.onload?.()); }
  });
}

const primaryDocumentId = "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE";
const secondaryRequestId = "FFFFFFFF-EEEE-DDDD-CCCC-BBBBBBBBBBBB";

function nativeLoadMessage(
  annotationDocument: EditorDocument,
  initialTool: EditorTool = "selection",
  requestId = primaryDocumentId,
): Extract<NativeMessage, { type: "loadDocument" }> {
  return {
    protocolVersion: 1,
    requestId,
    type: "loadDocument",
    payload: {
      documentId: primaryDocumentId,
      sourceImageURL: `myshottr-editor://editor/document/${primaryDocumentId}/original.png`,
      annotationDocument,
      initialTool,
    },
  };
}

function nativeHistoryMessage(action: "undo" | "redo"): Extract<NativeMessage, { type: "performHistoryAction" }> {
  return {
    protocolVersion: 1,
    requestId: secondaryRequestId,
    type: "performHistoryAction",
    payload: { action },
  };
}

function nativeOperationStatusMessage(
  requestId: string,
  payload: Extract<NativeMessage, { type: "operationStatus" }>["payload"],
): Extract<NativeMessage, { type: "operationStatus" }> {
  return {
    protocolVersion: 1,
    requestId,
    type: "operationStatus",
    payload,
  };
}

function editorFeedbackStatus(): HTMLOutputElement | null {
  return document.querySelector<HTMLOutputElement>("output.editor-feedback[role='status']");
}

function historyStatePayloads(harness: ReturnType<typeof createNativeBridgeHarness>) {
  return harness.messages("historyStateChanged").map((message) => message.payload);
}

async function renderAcceptedNativeEditor(
  initialDocument: EditorDocument = fixtureDocument(),
  initialTool: EditorTool = "selection",
) {
  stubImmediatelyLoadedSourceImage();
  const harness = createNativeBridgeHarness();
  render(<NativeBridgeProvider bridge={harness.bridge}><App /></NativeBridgeProvider>);
  harness.receive(nativeLoadMessage(initialDocument, initialTool));
  await screen.findByRole("button", { name: "Create rectangle from canvas" });
  await vi.waitFor(() => expect(historyStatePayloads(harness)).toEqual([
    { canUndo: false, canRedo: false },
  ]));
  return harness;
}

const historyLockCases = [
  {
    name: "pointer",
    document: () => fixtureDocument(),
    select: () => fireEvent.click(screen.getByRole("button", { name: "Select rect-1" })),
    enter: () => screen.getByRole("button", { name: "Begin canvas interaction" })
      .dispatchEvent(new MouseEvent("click", { bubbles: true })),
    leave: () => fireEvent.click(screen.getByRole("button", { name: "End canvas interaction" })),
  },
  {
    name: "nudge",
    document: () => fixtureDocument(),
    select: () => fireEvent.click(screen.getByRole("button", { name: "Select rect-1" })),
    enter: () => window.dispatchEvent(new KeyboardEvent("keydown", {
      code: "ArrowRight",
      key: "ArrowRight",
      bubbles: true,
      cancelable: true,
    })),
    leave: () => window.dispatchEvent(new Event("blur")),
  },
  {
    name: "text",
    document: () => fixtureDocument({ elements: [fixtureText()] }),
    select: () => fireEvent.click(screen.getByRole("button", { name: "Shift-select text-1" })),
    enter: () => screen.getByRole("button", { name: "Edit text-1" })
      .dispatchEvent(new MouseEvent("click", { bubbles: true })),
    leave: () => fireEvent.keyDown(screen.getByRole("textbox", { name: "Edit annotation text" }), {
      code: "Escape",
      key: "Escape",
    }),
  },
  {
    name: "slider",
    document: () => fixtureDocument(),
    select: () => fireEvent.click(screen.getByRole("button", { name: "Select rect-1" })),
    enter: () => {
      const slider = screen.getByRole("slider", { name: "Opacity" }) as HTMLInputElement;
      slider.value = "50";
      return slider.dispatchEvent(new Event("input", { bubbles: true }));
    },
    leave: () => fireEvent.keyDown(screen.getByRole("slider", { name: "Opacity" }), {
      code: "Escape",
      key: "Escape",
    }),
  },
  {
    name: "shortcut help",
    document: () => fixtureDocument(),
    select: () => fireEvent.click(screen.getByRole("button", { name: "Select rect-1" })),
    enter: () => window.dispatchEvent(new KeyboardEvent("keydown", {
      code: "Slash",
      key: "?",
      shiftKey: true,
      bubbles: true,
      cancelable: true,
    })),
    leave: () => fireEvent.click(screen.getByRole("button", { name: "Close keyboard shortcuts" })),
  },
  {
    name: "transaction",
    document: () => fixtureDocument(),
    select: () => fireEvent.click(screen.getByRole("button", { name: "Select rect-1" })),
    enter: () => screen.getByRole("button", { name: "Begin defaults transaction" })
      .dispatchEvent(new MouseEvent("click", { bubbles: true })),
    leave: () => fireEvent.keyDown(window, { code: "Escape", key: "Escape" }),
  },
] as const;

describe("EditorApp", () => {
  it("routes every zoom control intent through the measured viewport", () => {
    render(<EditorApp
      initialDocument={fixtureDocument()}
      initialTool="selection"
      sourceImageURL="data:image/png;base64,iVBORw0KGgo="
      onChange={() => {}}
      onPreferencesChange={() => {}}
    />);

    expect(screen.getByRole("status", { name: "Zoom level" }).textContent).toBe("100%");
    fireEvent.click(screen.getByRole("button", { name: "Zoom in" }));
    expect(screen.getByRole("status", { name: "Zoom level" }).textContent).toBe("110%");
    fireEvent.click(screen.getByRole("button", { name: "Zoom out" }));
    expect(screen.getByRole("status", { name: "Zoom level" }).textContent).toBe("100%");
    fireEvent.click(screen.getByRole("button", { name: "Fit Image" }));
    expect(screen.getByRole("status", { name: "Zoom level" }).textContent).toBe("62%");
    fireEvent.click(screen.getByRole("button", { name: "100%" }));
    expect(screen.getByRole("status", { name: "Zoom level" }).textContent).toBe("100%");
  });

  it("routes registry fit commands and leaves empty-selection fit unchanged", () => {
    render(<EditorApp
      initialDocument={fixtureDocument()}
      initialTool="selection"
      sourceImageURL="data:image/png;base64,iVBORw0KGgo="
      onChange={() => {}}
      onPreferencesChange={() => {}}
    />);

    fireEvent.keyDown(window, { code: "Digit2", key: "@", shiftKey: true });
    expect(screen.getByRole("status", { name: "Zoom level" }).textContent).toBe("100%");

    fireEvent.click(screen.getByRole("button", { name: "Select rect-1" }));
    fireEvent.keyDown(window, { code: "Digit2", key: "@", shiftKey: true });
    expect(screen.getByRole("status", { name: "Zoom level" }).textContent).toBe("529%");
    fireEvent.keyDown(window, { code: "Digit1", key: "!", shiftKey: true });
    expect(screen.getByRole("status", { name: "Zoom level" }).textContent).toBe("46%");
    fireEvent.keyDown(window, { code: "Digit0", key: "0", metaKey: true });
    expect(screen.getByRole("status", { name: "Zoom level" }).textContent).toBe("100%");
  });

  it.each([
    {
      label: "a rectangle rotated 90° around its Konva Group origin",
      element: { ...fixtureRect(), x: 500, y: 300, rotation: 90 },
      selectName: "Select rect-1",
      bounds: { x: 418, y: 298, width: 84, height: 124 },
    },
    {
      label: "a line rotated 30° around its Konva Group origin",
      element: {
        ...fixtureLine(),
        x: 500,
        y: 300,
        rotation: 30,
        points: [{ x: 500, y: 300 }, { x: 590, y: 345 }] as [{ x: number; y: number }, { x: number; y: number }],
      },
      selectName: "Select line-1",
      bounds: {
        x: 498,
        y: 298,
        width: 59.44228634059948,
        height: 87.97114317029974,
      },
    },
  ])("fits and centers $label with at least 24px padding", ({ element, selectName, bounds }) => {
    render(<EditorApp
      initialDocument={fixtureDocument({ elements: [element] })}
      initialTool="selection"
      sourceImageURL="data:image/png;base64,iVBORw0KGgo="
      onChange={() => {}}
      onPreferencesChange={() => {}}
    />);

    fireEvent.click(screen.getByRole("button", { name: selectName }));
    fireEvent.click(screen.getByRole("button", { name: "Fit Selection" }));

    const output = screen.getByTestId("canvas-viewport");
    const [availableX, availableY, availableWidth, availableHeight] = output
      .getAttribute("data-available")!.split(",").map(Number);
    const [panX, panY] = output.getAttribute("data-pan")!.split(",").map(Number);
    const zoom = Number(output.getAttribute("data-zoom"));
    const transformed = {
      left: bounds.x * zoom + panX,
      top: bounds.y * zoom + panY,
      right: (bounds.x + bounds.width) * zoom + panX,
      bottom: (bounds.y + bounds.height) * zoom + panY,
    };

    expect((transformed.left + transformed.right) / 2)
      .toBeCloseTo(availableX + availableWidth / 2);
    expect((transformed.top + transformed.bottom) / 2)
      .toBeCloseTo(availableY + availableHeight / 2);
    expect(transformed.left).toBeGreaterThanOrEqual(availableX + 24 - 0.001);
    expect(transformed.top).toBeGreaterThanOrEqual(availableY + 24 - 0.001);
    expect(transformed.right).toBeLessThanOrEqual(availableX + availableWidth - 24 + 0.001);
    expect(transformed.bottom).toBeLessThanOrEqual(availableY + availableHeight - 24 + 0.001);
    expect(Math.min(
      transformed.left - availableX,
      transformed.top - availableY,
      availableX + availableWidth - transformed.right,
      availableY + availableHeight - transformed.bottom,
    )).toBeCloseTo(24);
  });

  it("suppresses shortcuts while a creation or Space-pan interaction is active", () => {
    render(<EditorApp
      initialDocument={fixtureDocument()}
      initialTool="selection"
      sourceImageURL="data:image/png;base64,iVBORw0KGgo="
      onChange={() => {}}
      onPreferencesChange={() => {}}
    />);

    fireEvent.click(screen.getByRole("button", { name: "Begin canvas interaction" }));
    fireEvent.keyDown(window, { code: "KeyR", key: "r" });
    expect(screen.getByRole("button", { name: "Selection, shortcut V" }).getAttribute("aria-pressed"))
      .toBe("true");

    fireEvent.click(screen.getByRole("button", { name: "End canvas interaction" }));
    fireEvent.keyDown(window, { code: "KeyR", key: "r" });
    expect(screen.getByRole("button", { name: "Rectangle, shortcut R" }).getAttribute("aria-pressed"))
      .toBe("true");
  });

  it.each([
    ["rectangle", "Rectangle, shortcut R"],
    ["arrow", "Arrow, shortcut A"],
    ["line", "Line, shortcut L"],
    ["freehand", "Freehand, shortcut P"],
    ["highlighter", "Highlighter, shortcut H"],
    ["blur", "Blur, shortcut B"],
    ["redaction", "Redaction, shortcut X"],
  ] as const)("keeps %s active for repeated pointer creation", (_tool, buttonName) => {
    const changes: EditorDocument[] = [];
    render(<EditorApp
      initialDocument={fixtureDocument({ elements: [] })}
      initialTool="selection"
      sourceImageURL="data:image/png;base64,iVBORw0KGgo="
      onChange={(document) => changes.push(document)}
      onPreferencesChange={() => {}}
    />);
    const toolButton = screen.getByRole("button", { name: buttonName });
    const selectionButton = screen.getByRole("button", { name: "Selection, shortcut V" });
    const canvas = screen.getByTestId("mock-canvas-pointer-surface");

    fireEvent.click(toolButton);
    fireEvent.pointerDown(canvas, { clientX: 10, clientY: 20, pointerId: 1 });
    fireEvent.pointerMove(canvas, { clientX: 40, clientY: 50, pointerId: 1 });
    fireEvent.pointerUp(canvas, { clientX: 40, clientY: 50, pointerId: 1 });

    expect(toolButton.getAttribute("aria-pressed")).toBe("true");
    expect(selectionButton.getAttribute("aria-pressed")).toBe("false");
    expect(changes.at(-1)?.elements).toHaveLength(1);

    fireEvent.pointerDown(canvas, { clientX: 60, clientY: 70, pointerId: 2 });
    fireEvent.pointerMove(canvas, { clientX: 90, clientY: 100, pointerId: 2 });
    fireEvent.pointerUp(canvas, { clientX: 90, clientY: 100, pointerId: 2 });

    expect(toolButton.getAttribute("aria-pressed")).toBe("true");
    expect(changes.at(-1)?.elements).toHaveLength(2);
    expect(changes).toHaveLength(2);
  });

  it("keeps Number Marker active for repeated click creation", () => {
    const changes: EditorDocument[] = [];
    render(<EditorApp
      initialDocument={fixtureDocument({ elements: [] })}
      initialTool="selection"
      sourceImageURL="data:image/png;base64,iVBORw0KGgo="
      onChange={(document) => changes.push(document)}
      onPreferencesChange={() => {}}
    />);
    const markerButton = screen.getByRole("button", { name: "Number Marker, shortcut N" });
    const canvas = screen.getByTestId("mock-canvas-pointer-surface");

    fireEvent.click(markerButton);
    fireEvent.pointerDown(canvas, { clientX: 25, clientY: 35, pointerId: 1 });
    fireEvent.pointerUp(canvas, { clientX: 25, clientY: 35, pointerId: 1 });
    fireEvent.pointerDown(canvas, { clientX: 45, clientY: 55, pointerId: 2 });
    fireEvent.pointerUp(canvas, { clientX: 45, clientY: 55, pointerId: 2 });

    expect(markerButton.getAttribute("aria-pressed")).toBe("true");
    expect(changes.at(-1)?.elements).toEqual([
      expect.objectContaining({ type: "numberMarker", number: 1 }),
      expect.objectContaining({ type: "numberMarker", number: 2 }),
    ]);
  });

  it("opens a locked new Text draft without a placeholder, then creates exactly one undoable element", () => {
    const changes: EditorDocument[] = [];
    render(<EditorApp
      initialDocument={fixtureDocument({ elements: [] })}
      initialTool="text"
      sourceImageURL="data:image/png;base64,iVBORw0KGgo="
      onChange={(document) => changes.push(document)}
      onPreferencesChange={() => {}}
    />);
    const canvas = screen.getByTestId("mock-canvas-pointer-surface");

    fireEvent.pointerDown(canvas, { clientX: 20, clientY: 30, pointerId: 1 });
    fireEvent.pointerUp(canvas, { clientX: 80, clientY: 90, pointerId: 1 });

    const editor = screen.getByRole("textbox", { name: "Edit annotation text" });
    expect(document.activeElement).toBe(editor);
    expect((editor as HTMLTextAreaElement).value).toBe("");
    expect(screen.getByTestId("canvas-positions").textContent).toBe("");
    expect(screen.getByTestId("canvas-interaction-lock").textContent).toBe("true");
    expect(changes).toHaveLength(0);

    fireEvent.keyDown(window, { code: "KeyD", key: "d", metaKey: true });
    fireEvent.pointerDown(canvas, { clientX: 200, clientY: 210, pointerId: 2 });
    fireEvent.pointerUp(canvas, { clientX: 200, clientY: 210, pointerId: 2 });
    expect(changes).toHaveLength(0);
    expect(screen.getAllByRole("textbox", { name: "Edit annotation text" })).toHaveLength(1);

    fireEvent.change(editor, { target: { value: "  first line\nsecond line  " } });
    fireEvent.keyDown(editor, { key: "Enter", metaKey: true });
    fireEvent.blur(editor);

    expect(changes).toHaveLength(1);
    expect(changes[0].elements).toEqual([
      expect.objectContaining({
        type: "text",
        x: 20,
        y: 30,
        text: "  first line\nsecond line  ",
        color: "#1677FF",
        fontSize: 24,
      }),
    ]);
    expect(screen.getByTestId("canvas-interaction-lock").textContent).toBe("false");
    expect(screen.getByRole("button", { name: "Text, shortcut T" }).getAttribute("aria-pressed"))
      .toBe("true");

    fireEvent.keyDown(window, { code: "KeyZ", key: "z", metaKey: true });
    expect(changes).toHaveLength(2);
    expect(changes[1].elements).toEqual([]);
    fireEvent.keyDown(window, { code: "KeyZ", key: "z", metaKey: true, shiftKey: true });
    expect(changes).toHaveLength(3);
    expect(changes[2].elements[0]).toMatchObject({
      type: "text",
      text: "  first line\nsecond line  ",
    });
  });

  it("closes a blank new Text draft without publishing or creating Undo history", () => {
    const onChange = vi.fn();
    render(<EditorApp
      initialDocument={fixtureDocument({ elements: [] })}
      initialTool="text"
      sourceImageURL="data:image/png;base64,iVBORw0KGgo="
      onChange={onChange}
      onPreferencesChange={() => {}}
    />);
    const canvas = screen.getByTestId("mock-canvas-pointer-surface");

    fireEvent.pointerDown(canvas, { clientX: 20, clientY: 30, pointerId: 1 });
    fireEvent.pointerUp(canvas, { clientX: 20, clientY: 30, pointerId: 1 });
    const editor = screen.getByRole("textbox", { name: "Edit annotation text" });
    fireEvent.change(editor, { target: { value: " \n\t " } });
    fireEvent.blur(editor);

    expect(screen.queryByRole("textbox", { name: "Edit annotation text" })).toBeNull();
    expect(screen.getByTestId("canvas-positions").textContent).toBe("");
    expect(screen.getByTestId("canvas-interaction-lock").textContent).toBe("false");
    expect(onChange).not.toHaveBeenCalled();
    fireEvent.keyDown(window, { code: "KeyZ", key: "z", metaKey: true });
    expect(onChange).not.toHaveBeenCalled();
  });

  it("cancels a new Text draft on the first Escape without changing its tool or selection", () => {
    const onChange = vi.fn();
    render(<EditorApp
      initialDocument={fixtureDocument({ elements: [] })}
      initialTool="text"
      sourceImageURL="data:image/png;base64,iVBORw0KGgo="
      onChange={onChange}
      onPreferencesChange={() => {}}
    />);
    const canvas = screen.getByTestId("mock-canvas-pointer-surface");
    fireEvent.pointerDown(canvas, { clientX: 20, clientY: 30, pointerId: 1 });
    fireEvent.pointerUp(canvas, { clientX: 20, clientY: 30, pointerId: 1 });

    const editor = screen.getByRole("textbox", { name: "Edit annotation text" });
    fireEvent.change(editor, { target: { value: "Discard me" } });
    fireEvent.keyDown(editor, { code: "Escape", key: "Escape" });
    fireEvent.blur(editor);

    expect(screen.queryByRole("textbox", { name: "Edit annotation text" })).toBeNull();
    expect(screen.getByRole("button", { name: "Text, shortcut T" }).getAttribute("aria-pressed"))
      .toBe("true");
    expect(screen.getByTestId("canvas-selection").textContent).toBe("");
    expect(screen.getByTestId("canvas-interaction-lock").textContent).toBe("false");
    expect(onChange).not.toHaveBeenCalled();
  });

  it("keeps the Text tool when another palette tool is pressed during its locked draft", () => {
    const onPreferencesChange = vi.fn();
    render(<EditorApp
      initialDocument={fixtureDocument({ elements: [] })}
      initialTool="text"
      sourceImageURL="data:image/png;base64,iVBORw0KGgo="
      onChange={() => {}}
      onPreferencesChange={onPreferencesChange}
    />);
    const canvas = screen.getByTestId("mock-canvas-pointer-surface");
    fireEvent.pointerDown(canvas, { clientX: 20, clientY: 30, pointerId: 1 });
    fireEvent.pointerUp(canvas, { clientX: 20, clientY: 30, pointerId: 1 });

    const editor = screen.getByRole("textbox", { name: "Edit annotation text" });
    fireEvent.change(editor, { target: { value: "Draft stays open" } });
    const rectangle = screen.getByRole("button", { name: "Rectangle, shortcut R" });
    const lockedMouseDown = createEvent.mouseDown(rectangle);
    fireEvent(rectangle, lockedMouseDown);
    fireEvent.click(rectangle);

    expect(screen.getByRole("button", { name: "Text, shortcut T" }).getAttribute("aria-pressed"))
      .toBe("true");
    expect(rectangle.getAttribute("aria-pressed"))
      .toBe("false");
    expect(rectangle.getAttribute("aria-disabled")).toBe("true");
    expect(rectangle.tabIndex).toBe(-1);
    expect(lockedMouseDown.defaultPrevented).toBe(true);
    expect((editor as HTMLTextAreaElement).value).toBe("Draft stays open");
    expect(onPreferencesChange).not.toHaveBeenCalled();

    fireEvent.keyDown(editor, { code: "Escape", key: "Escape" });
    const unlockedMouseDown = createEvent.mouseDown(rectangle);
    fireEvent(rectangle, unlockedMouseDown);
    fireEvent.click(rectangle);

    expect(screen.getByRole("button", { name: "Text, shortcut T" }).getAttribute("aria-pressed"))
      .toBe("false");
    expect(rectangle.getAttribute("aria-pressed"))
      .toBe("true");
    expect(rectangle.getAttribute("aria-disabled")).toBe("false");
    expect(rectangle.tabIndex).toBe(0);
    expect(unlockedMouseDown.defaultPrevented).toBe(false);
    expect(onPreferencesChange).toHaveBeenCalledOnce();
    expect(onPreferencesChange.mock.calls[0]?.[0]).toBe("rectangle");
  });

  it("keeps the active tool through an existing Text draft and unlocks the palette after cancel", () => {
    const onPreferencesChange = vi.fn();
    render(<EditorApp
      initialDocument={fixtureDocument({ elements: [fixtureText()] })}
      initialTool="selection"
      sourceImageURL="data:image/png;base64,iVBORw0KGgo="
      onChange={() => {}}
      onPreferencesChange={onPreferencesChange}
    />);

    fireEvent.click(screen.getByRole("button", { name: "Shift-select text-1" }));
    fireEvent.click(screen.getByRole("button", { name: "Edit text-1" }));
    const editor = screen.getByRole("textbox", { name: "Edit annotation text" });
    fireEvent.change(editor, { target: { value: "Existing stays open" } });
    const rectangle = screen.getByRole("button", { name: "Rectangle, shortcut R" });
    const lockedMouseDown = createEvent.mouseDown(rectangle);
    fireEvent(rectangle, lockedMouseDown);
    fireEvent.click(rectangle);

    expect(screen.getByRole("button", { name: "Selection, shortcut V" }).getAttribute("aria-pressed"))
      .toBe("true");
    expect(lockedMouseDown.defaultPrevented).toBe(true);
    expect((editor as HTMLTextAreaElement).value).toBe("Existing stays open");
    expect(onPreferencesChange).not.toHaveBeenCalled();

    fireEvent.keyDown(editor, { code: "Escape", key: "Escape" });
    const unlockedMouseDown = createEvent.mouseDown(rectangle);
    fireEvent(rectangle, unlockedMouseDown);
    fireEvent.click(rectangle);

    expect(screen.getByRole("button", { name: "Selection, shortcut V" }).getAttribute("aria-pressed"))
      .toBe("false");
    expect(rectangle.getAttribute("aria-pressed"))
      .toBe("true");
    expect(unlockedMouseDown.defaultPrevented).toBe(false);
    expect(onPreferencesChange).toHaveBeenCalledOnce();
    expect(onPreferencesChange.mock.calls[0]?.[0]).toBe("rectangle");
  });

  it("cancels an active creation on the first Escape and changes tool only on the second idle Escape", () => {
    const onChange = vi.fn();
    render(<EditorApp
      initialDocument={fixtureDocument({ elements: [] })}
      initialTool="rectangle"
      sourceImageURL="data:image/png;base64,iVBORw0KGgo="
      onChange={onChange}
      onPreferencesChange={() => {}}
    />);
    const canvas = screen.getByTestId("mock-canvas-pointer-surface");
    const rectangle = screen.getByRole("button", { name: "Rectangle, shortcut R" });
    const selection = screen.getByRole("button", { name: "Selection, shortcut V" });

    fireEvent.pointerDown(canvas, { clientX: 10, clientY: 20, pointerId: 1 });
    fireEvent.pointerMove(canvas, { clientX: 50, clientY: 60, pointerId: 1 });
    fireEvent.keyDown(window, { code: "Escape", key: "Escape" });
    fireEvent.pointerUp(canvas, { clientX: 50, clientY: 60, pointerId: 1 });

    expect(rectangle.getAttribute("aria-pressed")).toBe("true");
    expect(selection.getAttribute("aria-pressed")).toBe("false");
    expect(onChange).not.toHaveBeenCalled();

    fireEvent.keyDown(window, { code: "Escape", key: "Escape" });
    expect(selection.getAttribute("aria-pressed")).toBe("true");
    expect(onChange).not.toHaveBeenCalled();
  });

  it("cancels an active Space-pan on the first Escape and changes tool only after it is idle", () => {
    const onChange = vi.fn();
    render(<EditorApp
      initialDocument={fixtureDocument({ elements: [] })}
      initialTool="rectangle"
      sourceImageURL="data:image/png;base64,iVBORw0KGgo="
      onChange={onChange}
      onPreferencesChange={() => {}}
    />);
    const canvas = screen.getByTestId("mock-canvas-pointer-surface");
    const rectangle = screen.getByRole("button", { name: "Rectangle, shortcut R" });
    const selection = screen.getByRole("button", { name: "Selection, shortcut V" });

    fireEvent.keyDown(window, { code: "Space", key: " " });
    fireEvent.pointerDown(canvas, { clientX: 10, clientY: 20, pointerId: 2 });
    fireEvent.pointerMove(canvas, { clientX: 30, clientY: 45, pointerId: 2 });
    fireEvent.keyDown(window, { code: "Escape", key: "Escape" });
    fireEvent.pointerUp(canvas, { clientX: 30, clientY: 45, pointerId: 2 });

    expect(rectangle.getAttribute("aria-pressed")).toBe("true");
    expect(selection.getAttribute("aria-pressed")).toBe("false");
    expect(onChange).not.toHaveBeenCalled();

    fireEvent.keyUp(window, { code: "Space", key: " " });
    fireEvent.keyDown(window, { code: "Escape", key: "Escape" });
    expect(selection.getAttribute("aria-pressed")).toBe("true");
  });

  it("accepts a direct existing-Text edit callback only for that sole selection", () => {
    render(<EditorApp
      initialDocument={fixtureDocument({ elements: [fixtureRect(), fixtureText()] })}
      initialTool="selection"
      sourceImageURL="data:image/png;base64,iVBORw0KGgo="
      onChange={() => {}}
      onPreferencesChange={() => {}}
    />);
    const editText = screen.getByRole("button", { name: "Edit text-1" });

    fireEvent.click(editText);
    expect(screen.queryByRole("textbox", { name: "Edit annotation text" })).toBeNull();

    fireEvent.click(screen.getByRole("button", { name: "Select rect-1" }));
    fireEvent.click(editText);
    expect(screen.queryByRole("textbox", { name: "Edit annotation text" })).toBeNull();

    fireEvent.click(screen.getByRole("button", { name: "Shift-select text-1" }));
    fireEvent.click(editText);
    expect(screen.queryByRole("textbox", { name: "Edit annotation text" })).toBeNull();

    fireEvent.keyDown(window, { code: "Escape", key: "Escape" });
    fireEvent.click(screen.getByRole("button", { name: "Shift-select text-1" }));
    fireEvent.click(editText);

    const editor = screen.getByRole("textbox", { name: "Edit annotation text" });
    expect(document.activeElement).toBe(editor);
    expect((editor as HTMLTextAreaElement).value).toBe("Annotate this");
  });

  it("edits existing text with exact whitespace and multiline content in one history command", () => {
    const changes: EditorDocument[] = [];
    render(<EditorApp
      initialDocument={fixtureDocument({ elements: [fixtureText()] })}
      initialTool="selection"
      sourceImageURL="data:image/png;base64,iVBORw0KGgo="
      onChange={(document) => changes.push(document)}
      onPreferencesChange={() => {}}
    />);

    fireEvent.click(screen.getByRole("button", { name: "Shift-select text-1" }));
    fireEvent.click(screen.getByRole("button", { name: "Edit text-1" }));
    const editor = screen.getByRole("textbox", { name: "Edit annotation text" });
    expect(document.activeElement).toBe(editor);
    expect(screen.getByTestId("canvas-interaction-lock").textContent).toBe("true");
    fireEvent.change(editor, { target: { value: "  Ship this\nnow  " } });
    fireEvent.keyDown(editor, { key: "Enter", metaKey: true });
    fireEvent.blur(editor);

    expect(changes).toHaveLength(1);
    expect(changes.at(-1)?.elements[0]).toMatchObject({
      type: "text",
      text: "  Ship this\nnow  ",
    });
    fireEvent.keyDown(window, { code: "KeyZ", key: "z", metaKey: true });
    expect(changes.at(-1)?.elements[0]).toMatchObject({ type: "text", text: "Annotate this" });
    fireEvent.keyDown(window, { code: "KeyZ", key: "z", metaKey: true, shiftKey: true });
    expect(changes.at(-1)?.elements[0]).toMatchObject({
      type: "text",
      text: "  Ship this\nnow  ",
    });
  });

  it("keeps an identical existing text commit as one explicit update and Undo entry", () => {
    const changes: EditorDocument[] = [];
    const text = { ...fixtureText(), width: 156, height: 29 };
    render(<EditorApp
      initialDocument={fixtureDocument({ elements: [text] })}
      initialTool="selection"
      sourceImageURL="data:image/png;base64,iVBORw0KGgo="
      onChange={(document) => changes.push(document)}
      onPreferencesChange={() => {}}
    />);

    fireEvent.click(screen.getByRole("button", { name: "Shift-select text-1" }));
    fireEvent.click(screen.getByRole("button", { name: "Edit text-1" }));
    fireEvent.keyDown(
      screen.getByRole("textbox", { name: "Edit annotation text" }),
      { key: "Enter", metaKey: true },
    );

    expect(changes).toHaveLength(1);
    expect(changes[0].elements).toEqual([text]);
    fireEvent.keyDown(window, { code: "KeyZ", key: "z", metaKey: true });
    expect(changes).toHaveLength(2);
    expect(changes[1].elements).toEqual([text]);
  });

  it("escapes text editing without changing the document", () => {
    const onChange = vi.fn();
    render(<EditorApp
      initialDocument={fixtureDocument({ elements: [fixtureText()] })}
      initialTool="selection"
      sourceImageURL="data:image/png;base64,iVBORw0KGgo="
      onChange={onChange}
      onPreferencesChange={() => {}}
    />);

    fireEvent.click(screen.getByRole("button", { name: "Shift-select text-1" }));
    fireEvent.click(screen.getByRole("button", { name: "Edit text-1" }));
    const editor = screen.getByRole("textbox", { name: "Edit annotation text" });
    fireEvent.change(editor, { target: { value: "Discard me" } });
    fireEvent.keyDown(editor, { key: "Escape" });
    fireEvent.blur(editor);

    expect(onChange).not.toHaveBeenCalled();
    expect(screen.queryByRole("textbox", { name: "Edit annotation text" })).toBeNull();
  });

  it("cannot publish a late existing-text blur after the editor unmounts", () => {
    const onChange = vi.fn();
    const { unmount } = render(<EditorApp
      initialDocument={fixtureDocument({ elements: [fixtureText()] })}
      initialTool="selection"
      sourceImageURL="data:image/png;base64,iVBORw0KGgo="
      onChange={onChange}
      onPreferencesChange={() => {}}
    />);

    fireEvent.click(screen.getByRole("button", { name: "Shift-select text-1" }));
    fireEvent.click(screen.getByRole("button", { name: "Edit text-1" }));
    const staleEditor = screen.getByRole("textbox", { name: "Edit annotation text" });
    fireEvent.change(staleEditor, { target: { value: "must not publish" } });
    unmount();
    fireEvent.blur(staleEditor);

    expect(onChange).not.toHaveBeenCalled();
  });

  it("deletes a selected existing text when blank, clears selection, and records one Undo", () => {
    const changes: EditorDocument[] = [];
    render(<EditorApp
      initialDocument={fixtureDocument({ elements: [fixtureText()] })}
      initialTool="selection"
      sourceImageURL="data:image/png;base64,iVBORw0KGgo="
      onChange={(document) => changes.push(document)}
      onPreferencesChange={() => {}}
    />);

    fireEvent.click(screen.getByRole("button", { name: "Shift-select text-1" }));
    expect(screen.getByTestId("canvas-selection").textContent).toBe("text-1");
    fireEvent.click(screen.getByRole("button", { name: "Edit text-1" }));
    const editor = screen.getByRole("textbox", { name: "Edit annotation text" });
    fireEvent.change(editor, { target: { value: "   " } });
    fireEvent.keyDown(editor, { key: "Enter", metaKey: true });

    expect(changes).toHaveLength(1);
    expect(changes.at(-1)?.elements).toEqual([]);
    expect(screen.getByTestId("canvas-selection").textContent).toBe("");
    expect(screen.getByTestId("canvas-interaction-lock").textContent).toBe("false");

    fireEvent.keyDown(window, { code: "KeyZ", key: "z", metaKey: true });
    expect(changes).toHaveLength(2);
    expect(changes.at(-1)?.elements[0]).toMatchObject({
      id: "text-1",
      text: "Annotate this",
    });
    expect(screen.getByTestId("canvas-selection").textContent).toBe("");
  });

  it("opens existing text with Enter only for exactly one selected Text element", () => {
    render(<EditorApp
      initialDocument={fixtureDocument({ elements: [fixtureRect(), fixtureText()] })}
      initialTool="selection"
      sourceImageURL="data:image/png;base64,iVBORw0KGgo="
      onChange={() => {}}
      onPreferencesChange={() => {}}
    />);

    fireEvent.click(screen.getByRole("button", { name: "Select rect-1" }));
    fireEvent.keyDown(window, { code: "Enter", key: "Enter" });
    expect(screen.queryByRole("textbox", { name: "Edit annotation text" })).toBeNull();

    fireEvent.click(screen.getByRole("button", { name: "Shift-select text-1" }));
    fireEvent.keyDown(window, { code: "Enter", key: "Enter" });
    expect(screen.queryByRole("textbox", { name: "Edit annotation text" })).toBeNull();

    fireEvent.keyDown(window, { code: "Escape", key: "Escape" });
    fireEvent.click(screen.getByRole("button", { name: "Shift-select text-1" }));
    fireEvent.keyDown(window, { code: "Enter", key: "Enter" });

    const editor = screen.getByRole("textbox", { name: "Edit annotation text" });
    expect(document.activeElement).toBe(editor);
    expect((editor as HTMLTextAreaElement).value).toBe("Annotate this");
  });

  it("starts consecutive new Text sessions from fresh empty drafts and source anchors", () => {
    render(<EditorApp
      initialDocument={fixtureDocument({ elements: [] })}
      initialTool="text"
      sourceImageURL="data:image/png;base64,iVBORw0KGgo="
      onChange={() => {}}
      onPreferencesChange={() => {}}
    />);
    const canvas = screen.getByTestId("mock-canvas-pointer-surface");

    fireEvent.pointerDown(canvas, { clientX: 20, clientY: 30, pointerId: 1 });
    fireEvent.pointerUp(canvas, { clientX: 20, clientY: 30, pointerId: 1 });
    const firstEditor = screen.getByRole("textbox", { name: "Edit annotation text" }) as HTMLTextAreaElement;
    const firstLeft = firstEditor.style.left;
    fireEvent.change(firstEditor, { target: { value: "stale" } });
    fireEvent.keyDown(firstEditor, { code: "Escape", key: "Escape" });

    fireEvent.pointerDown(canvas, { clientX: 100, clientY: 110, pointerId: 2 });
    fireEvent.pointerUp(canvas, { clientX: 100, clientY: 110, pointerId: 2 });
    const secondEditor = screen.getByRole("textbox", { name: "Edit annotation text" }) as HTMLTextAreaElement;

    expect(secondEditor.value).toBe("");
    expect(secondEditor.style.left).not.toBe(firstLeft);
  });

  it("applies a color change to the selected rectangle", () => {
    const changes: EditorDocument[] = [];
    render(<EditorApp
      initialDocument={fixtureDocument()}
      initialTool="selection"
      sourceImageURL="data:image/png;base64,iVBORw0KGgo="
      onChange={(document) => changes.push(document)}
      onPreferencesChange={() => {}}
    />);

    fireEvent.click(screen.getByRole("button", { name: "Select rect-1" }));
    fireEvent.click(within(screen.getByRole("radiogroup", { name: "Color" }))
      .getByRole("radio", { name: "Red" }));

    expect(changes.at(-1)?.elements[0]).toMatchObject({ strokeColor: "#FF4D4F" });
  });

  it("deletes every selected element in one command", () => {
    const changes: EditorDocument[] = [];
    render(<EditorApp
      initialDocument={fixtureDocument({ elements: [fixtureRect(), fixtureText()] })}
      initialTool="selection"
      sourceImageURL="data:image/png;base64,iVBORw0KGgo="
      onChange={(document) => changes.push(document)}
      onPreferencesChange={() => {}}
    />);

    fireEvent.click(screen.getByRole("button", { name: "Select rect-1" }));
    fireEvent.click(screen.getByRole("button", { name: "Shift-select text-1" }));
    fireEvent.keyDown(window, { code: "Delete", key: "Delete" });

    expect(changes.at(-1)?.elements).toEqual([]);
    fireEvent.keyDown(window, { code: "KeyZ", key: "z", metaKey: true });
    expect(changes.at(-1)?.elements.map((element) => element.id)).toEqual(["rect-1", "text-1"]);
  });

  it("duplicates every selected element atomically with unique identities", () => {
    const changes: EditorDocument[] = [];
    render(<EditorApp
      initialDocument={fixtureDocument({ elements: [fixtureRect(), fixtureText()] })}
      initialTool="selection"
      sourceImageURL="data:image/png;base64,iVBORw0KGgo="
      onChange={(document) => changes.push(document)}
      onPreferencesChange={() => {}}
    />);

    fireEvent.click(screen.getByRole("button", { name: "Select rect-1" }));
    fireEvent.click(screen.getByRole("button", { name: "Shift-select text-1" }));
    fireEvent.keyDown(window, { code: "KeyD", key: "d", metaKey: true });

    const duplicated = changes.at(-1)!;
    expect(duplicated.elements).toHaveLength(4);
    expect(new Set(duplicated.elements.map((element) => element.id)).size).toBe(4);
    expect(duplicated.elements.slice(2).map((element) => element.seed)).toEqual([104, 105]);
    expect(duplicated.elements.slice(2).map((element) => element.zIndex)).toEqual([4, 5]);
    expect(duplicated.elements.slice(2).map(({ x, y }) => ({ x, y }))).toEqual([
      { x: 12, y: 12 },
      { x: 52, y: 62 },
    ]);
    expect(screen.getByTestId("canvas-selection").textContent).toBe(
      duplicated.elements.slice(2).map((element) => element.id).join(","),
    );
    fireEvent.keyDown(window, { code: "KeyZ", key: "z", metaKey: true });
    expect(changes.at(-1)?.elements).toHaveLength(2);
  });

  it("selects rail duplicates returned by the one createMany command", () => {
    const changes: EditorDocument[] = [];
    render(<EditorApp
      initialDocument={fixtureDocument({ elements: [fixtureRect(), fixtureText()] })}
      initialTool="selection"
      sourceImageURL="data:image/png;base64,iVBORw0KGgo="
      onChange={(document) => changes.push(document)}
      onPreferencesChange={() => {}}
    />);

    fireEvent.click(screen.getByRole("button", { name: "Select rect-1" }));
    fireEvent.click(screen.getByRole("button", { name: "Shift-select text-1" }));
    fireEvent.click(screen.getByRole("button", { name: "Duplicate" }));
    expect(changes).toHaveLength(1);
    expect(changes[0].elements).toHaveLength(4);
    expect(screen.getByTestId("canvas-selection").textContent).toBe(
      changes[0].elements.slice(2).map((element) => element.id).join(","),
    );

    fireEvent.click(screen.getByRole("button", { name: "Delete" }));

    expect(changes).toHaveLength(2);
    expect(changes[1].elements.map((element) => element.id)).toEqual(["rect-1", "text-1"]);
  });

  it("copies and pastes a selected annotation without replacing its identity", () => {
    const changes: EditorDocument[] = [];
    render(<EditorApp
      initialDocument={fixtureDocument()}
      initialTool="selection"
      sourceImageURL="data:image/png;base64,iVBORw0KGgo="
      onChange={(document) => changes.push(document)}
      onPreferencesChange={() => {}}
    />);

    fireEvent.click(screen.getByRole("button", { name: "Select rect-1" }));
    fireEvent.keyDown(window, { code: "KeyC", key: "c", metaKey: true });
    fireEvent.keyDown(window, { code: "KeyV", key: "v", metaKey: true });

    const elements = changes.at(-1)?.elements ?? [];
    expect(elements).toHaveLength(2);
    expect(elements[1]).toMatchObject({ x: 12, y: 12 });
    expect(elements[1]?.id).not.toBe(elements[0]?.id);
  });

  it("does not turn command-v into the selection tool", () => {
    expect(keyboardCommandFor(
      new KeyboardEvent("keydown", { code: "KeyV", key: "v", metaKey: true }),
      {
        interactionActive: false,
        shortcutHelpOpen: false,
        textEditing: false,
      },
    )).toEqual({ type: "paste" });
  });

  it("uses one bounded duplicate offset for the whole selection", () => {
    const changes: EditorDocument[] = [];
    render(<EditorApp
      initialDocument={fixtureDocument({
        sourcePixelWidth: 100,
        sourcePixelHeight: 100,
        elements: [
          { ...fixtureRect(), width: 20, height: 20 },
          { ...fixtureText(), x: 70, y: 70, width: 30, height: 30, zIndex: 1 },
        ],
      })}
      initialTool="selection"
      sourceImageURL="data:image/png;base64,iVBORw0KGgo="
      onChange={(document) => changes.push(document)}
      onPreferencesChange={() => {}}
    />);

    fireEvent.click(screen.getByRole("button", { name: "Select rect-1" }));
    fireEvent.click(screen.getByRole("button", { name: "Shift-select text-1" }));
    fireEvent.keyDown(window, { code: "KeyD", key: "d", metaKey: true });

    expect(changes.at(-1)?.elements.slice(2).map(({ x, y }) => ({ x, y }))).toEqual([
      { x: 0, y: 0 },
      { x: 70, y: 70 },
    ]);
  });

  it("duplicates an oversized loaded selection with one command and one Undo entry", () => {
    const oversized = {
      ...fixtureRect(),
      x: -25,
      y: 10,
      width: 150,
      height: 20,
    };
    const changes: EditorDocument[] = [];
    render(<EditorApp
      initialDocument={fixtureDocument({
        sourcePixelWidth: 100,
        sourcePixelHeight: 100,
        elements: [oversized],
      })}
      initialTool="selection"
      sourceImageURL="data:image/png;base64,iVBORw0KGgo="
      onChange={(document) => changes.push(document)}
      onPreferencesChange={() => {}}
    />);
    fireEvent.click(screen.getByRole("button", { name: "Select rect-1" }));

    expect(() => fireEvent.keyDown(window, {
      code: "KeyD",
      key: "d",
      metaKey: true,
    })).not.toThrow();

    expect(changes).toHaveLength(1);
    expect(changes[0].elements).toHaveLength(2);
    expect(changes[0].elements[1]).toMatchObject({ x: -25, y: 22 });
    fireEvent.keyDown(window, { code: "KeyZ", key: "z", metaKey: true });
    expect(changes).toHaveLength(2);
    expect(changes[1].elements).toEqual([oversized]);
    fireEvent.keyDown(window, { code: "KeyZ", key: "z", metaKey: true });
    expect(changes).toHaveLength(2);
  });

  it("previews repeated held-key nudges and commits one updateMany on final keyup", () => {
    const rectangle = { ...fixtureRect(), x: 20, y: 20, width: 20, height: 20 };
    const changes: EditorDocument[] = [];
    render(<EditorApp
      initialDocument={fixtureDocument({
        sourcePixelWidth: 100,
        sourcePixelHeight: 100,
        elements: [rectangle],
      })}
      initialTool="selection"
      sourceImageURL="data:image/png;base64,iVBORw0KGgo="
      onChange={(document) => changes.push(document)}
      onPreferencesChange={() => {}}
    />);
    fireEvent.click(screen.getByRole("button", { name: "Select rect-1" }));

    fireEvent.keyDown(window, { code: "ArrowRight", key: "ArrowRight" });
    fireEvent.keyDown(window, { code: "ArrowRight", key: "ArrowRight", repeat: true });
    fireEvent.keyDown(window, {
      code: "ArrowDown",
      key: "ArrowDown",
      repeat: true,
      shiftKey: true,
    });

    expect(screen.getByTestId("canvas-positions").textContent).toBe("rect-1:22,30");
    expect(screen.getByTestId("canvas-interaction-lock").textContent).toBe("true");
    expect(changes).toHaveLength(0);

    fireEvent.keyUp(window, { code: "ArrowRight", key: "ArrowRight" });
    expect(changes).toHaveLength(0);
    fireEvent.keyUp(window, { code: "ArrowDown", key: "ArrowDown" });

    expect(changes).toHaveLength(1);
    expect(changes[0].elements[0]).toMatchObject({ x: 22, y: 30 });
    expect(screen.getByTestId("canvas-interaction-lock").textContent).toBe("false");

    fireEvent.keyDown(window, { code: "KeyZ", key: "z", metaKey: true });
    expect(changes).toHaveLength(2);
    expect(changes[1].elements[0]).toMatchObject({ x: 20, y: 20 });
    fireEvent.keyDown(window, { code: "KeyZ", key: "z", metaKey: true });
    expect(changes).toHaveLength(2);
  });

  it("clamps held Shift-nudge to source bounds before one release commit", () => {
    const rectangle = { ...fixtureRect(), x: 77, y: 20, width: 20, height: 20 };
    const changes: EditorDocument[] = [];
    render(<EditorApp
      initialDocument={fixtureDocument({
        sourcePixelWidth: 100,
        sourcePixelHeight: 100,
        elements: [rectangle],
      })}
      initialTool="selection"
      sourceImageURL="data:image/png;base64,iVBORw0KGgo="
      onChange={(document) => changes.push(document)}
      onPreferencesChange={() => {}}
    />);
    fireEvent.click(screen.getByRole("button", { name: "Select rect-1" }));

    fireEvent.keyDown(window, {
      code: "ArrowRight",
      key: "ArrowRight",
      shiftKey: true,
    });
    fireEvent.keyDown(window, {
      code: "ArrowRight",
      key: "ArrowRight",
      shiftKey: true,
      repeat: true,
    });
    expect(screen.getByTestId("canvas-positions").textContent).toBe("rect-1:78,20");
    expect(changes).toHaveLength(0);

    fireEvent.keyUp(window, { code: "ArrowRight", key: "ArrowRight" });
    expect(changes).toHaveLength(1);
    expect(changes[0].elements[0]).toMatchObject({ x: 78, y: 20 });
  });

  it("keeps an oversized nudge axis fixed without adding no-op history", () => {
    const oversized = {
      ...fixtureRect(),
      x: -25,
      y: 10,
      width: 150,
      height: 20,
    };
    const changes: EditorDocument[] = [];
    render(<EditorApp
      initialDocument={fixtureDocument({
        sourcePixelWidth: 100,
        sourcePixelHeight: 100,
        elements: [oversized],
      })}
      initialTool="selection"
      sourceImageURL="data:image/png;base64,iVBORw0KGgo="
      onChange={(document) => changes.push(document)}
      onPreferencesChange={() => {}}
    />);
    fireEvent.click(screen.getByRole("button", { name: "Select rect-1" }));

    expect(() => fireEvent.keyDown(window, {
      code: "ArrowRight",
      key: "ArrowRight",
    })).not.toThrow();
    fireEvent.keyUp(window, { code: "ArrowRight", key: "ArrowRight" });
    expect(screen.getByTestId("canvas-positions").textContent).toBe("rect-1:-25,10");
    expect(changes).toHaveLength(0);
    fireEvent.keyDown(window, { code: "KeyZ", key: "z", metaKey: true });
    expect(changes).toHaveLength(0);

    fireEvent.keyDown(window, { code: "ArrowDown", key: "ArrowDown" });
    fireEvent.keyUp(window, { code: "ArrowDown", key: "ArrowDown" });
    expect(changes).toHaveLength(1);
    expect(changes[0].elements[0]).toMatchObject({ x: -25, y: 11 });
    fireEvent.keyDown(window, { code: "KeyZ", key: "z", metaKey: true });
    expect(changes).toHaveLength(2);
    expect(changes[1].elements[0]).toMatchObject({ x: -25, y: 10 });
    fireEvent.keyDown(window, { code: "KeyZ", key: "z", metaKey: true });
    expect(changes).toHaveLength(2);
  });

  it.each(["Escape", "blur"] as const)(
    "restores a nudge preview on %s without a command or Undo entry",
    (terminal) => {
      const rectangle = { ...fixtureRect(), x: 20, y: 20, width: 20, height: 20 };
      const changes: EditorDocument[] = [];
      render(<EditorApp
        initialDocument={fixtureDocument({
          sourcePixelWidth: 100,
          sourcePixelHeight: 100,
          elements: [rectangle],
        })}
        initialTool="selection"
        sourceImageURL="data:image/png;base64,iVBORw0KGgo="
        onChange={(document) => changes.push(document)}
        onPreferencesChange={() => {}}
      />);
      fireEvent.click(screen.getByRole("button", { name: "Select rect-1" }));
      fireEvent.keyDown(window, { code: "ArrowLeft", key: "ArrowLeft" });
      expect(screen.getByTestId("canvas-positions").textContent).toBe("rect-1:19,20");

      if (terminal === "Escape") {
        fireEvent.keyDown(window, { code: "Escape", key: "Escape" });
      } else {
        fireEvent(window, new Event("blur"));
      }
      fireEvent.keyUp(window, { code: "ArrowLeft", key: "ArrowLeft" });

      expect(screen.getByTestId("canvas-positions").textContent).toBe("rect-1:20,20");
      expect(changes).toHaveLength(0);
      fireEvent.keyDown(window, { code: "KeyZ", key: "z", metaKey: true });
      expect(changes).toHaveLength(0);
    },
  );

  it("locks other shortcuts and cancels a held nudge when selection identity changes", () => {
    const rectangle = { ...fixtureRect(), x: 20, y: 20, width: 20, height: 20 };
    const line = { ...fixtureLine(), x: 50, y: 50, width: 20, height: 20 };
    const changes: EditorDocument[] = [];
    render(<EditorApp
      initialDocument={fixtureDocument({
        sourcePixelWidth: 100,
        sourcePixelHeight: 100,
        elements: [rectangle, line],
      })}
      initialTool="selection"
      sourceImageURL="data:image/png;base64,iVBORw0KGgo="
      onChange={(document) => changes.push(document)}
      onPreferencesChange={() => {}}
    />);
    fireEvent.click(screen.getByRole("button", { name: "Select rect-1" }));
    fireEvent.keyDown(window, { code: "ArrowRight", key: "ArrowRight" });

    fireEvent.keyDown(window, { code: "KeyD", key: "d", metaKey: true });
    fireEvent.keyDown(window, { code: "KeyR", key: "r" });
    expect(changes).toHaveLength(0);
    expect(screen.getByRole("button", { name: "Selection, shortcut V" }).getAttribute("aria-pressed"))
      .toBe("true");

    fireEvent.click(screen.getByRole("button", { name: "Select line-1" }));
    fireEvent.keyUp(window, { code: "ArrowRight", key: "ArrowRight" });

    expect(screen.getByTestId("canvas-positions").textContent)
      .toBe("rect-1:20,20;line-1:50,50");
    expect(screen.getByTestId("canvas-selection").textContent).toBe("line-1");
    expect(changes).toHaveLength(0);
  });

  it("keeps Enter inert for selected Text until a held nudge commits", () => {
    const text = { ...fixtureText(), x: 20, y: 20, width: 20, height: 20 };
    const changes: EditorDocument[] = [];
    render(<EditorApp
      initialDocument={fixtureDocument({
        sourcePixelWidth: 100,
        sourcePixelHeight: 100,
        elements: [text],
      })}
      initialTool="selection"
      sourceImageURL="data:image/png;base64,iVBORw0KGgo="
      onChange={(document) => changes.push(document)}
      onPreferencesChange={() => {}}
    />);
    fireEvent.click(screen.getByRole("button", { name: "Shift-select text-1" }));
    fireEvent.keyDown(window, { code: "ArrowRight", key: "ArrowRight" });

    fireEvent.keyDown(window, { code: "Enter", key: "Enter" });

    expect(screen.queryByRole("textbox", { name: "Edit annotation text" })).toBeNull();
    expect(screen.getByTestId("canvas-positions").textContent).toBe("text-1:21,20");
    expect(screen.getByTestId("canvas-interaction-lock").textContent).toBe("true");
    expect(changes).toHaveLength(0);

    fireEvent.keyUp(window, { code: "ArrowRight", key: "ArrowRight" });

    expect(changes).toHaveLength(1);
    expect(changes[0].elements[0]).toMatchObject({ id: "text-1", x: 21, y: 20 });
    expect(screen.getByTestId("canvas-interaction-lock").textContent).toBe("false");
  });

  it("cancels a held nudge on tool switch so late keyup cannot create history", () => {
    const onChange = vi.fn();
    render(<EditorApp
      initialDocument={fixtureDocument({
        elements: [{ ...fixtureRect(), x: 20, y: 20 }],
      })}
      initialTool="selection"
      sourceImageURL="data:image/png;base64,iVBORw0KGgo="
      onChange={onChange}
      onPreferencesChange={() => {}}
    />);
    fireEvent.click(screen.getByRole("button", { name: "Select rect-1" }));

    fireEvent.keyDown(window, { code: "ArrowRight", key: "ArrowRight" });
    expect(screen.getByTestId("canvas-positions").textContent).toBe("rect-1:21,20");

    fireEvent.click(screen.getByRole("button", { name: "Rectangle, shortcut R" }));
    fireEvent.keyUp(window, { code: "ArrowRight", key: "ArrowRight" });
    fireEvent.keyDown(window, { code: "KeyZ", key: "z", metaKey: true });

    expect(screen.getByTestId("canvas-positions").textContent).toBe("rect-1:20,20");
    expect(screen.getByTestId("canvas-selection").textContent).toBe("");
    expect(onChange).not.toHaveBeenCalled();
  });

  it("removes a held nudge owner on unmount so late keyup cannot publish", () => {
    const onChange = vi.fn();
    const view = render(<EditorApp
      initialDocument={fixtureDocument({
        elements: [{ ...fixtureRect(), x: 20, y: 20 }],
      })}
      initialTool="selection"
      sourceImageURL="data:image/png;base64,iVBORw0KGgo="
      onChange={onChange}
      onPreferencesChange={() => {}}
    />);
    fireEvent.click(screen.getByRole("button", { name: "Select rect-1" }));
    fireEvent.keyDown(window, { code: "ArrowRight", key: "ArrowRight" });
    expect(screen.getByTestId("canvas-positions").textContent).toBe("rect-1:21,20");

    view.unmount();
    fireEvent.keyUp(window, { code: "ArrowRight", key: "ArrowRight" });
    fireEvent.keyDown(window, { code: "KeyZ", key: "z", metaKey: true });

    expect(onChange).not.toHaveBeenCalled();
  });

  it("reorders every selected element from shortcuts and palette controls", () => {
    const changes: EditorDocument[] = [];
    render(<EditorApp
      initialDocument={fixtureDocument({
        elements: [fixtureRect(), { ...fixtureText(), zIndex: 1 }, { ...fixtureLine(), zIndex: 2 }],
      })}
      initialTool="selection"
      sourceImageURL="data:image/png;base64,iVBORw0KGgo="
      onChange={(document) => changes.push(document)}
      onPreferencesChange={() => {}}
    />);

    fireEvent.click(screen.getByRole("button", { name: "Select rect-1" }));
    fireEvent.click(screen.getByRole("button", { name: "Shift-select text-1" }));
    fireEvent.keyDown(window, { code: "BracketRight", key: "]", metaKey: true });

    expect([...changes.at(-1)!.elements].sort((left, right) => left.zIndex - right.zIndex).map((element) => element.id))
      .toEqual(["line-1", "rect-1", "text-1"]);

    fireEvent.click(screen.getByRole("button", { name: "Send Backward" }));
    expect([...changes.at(-1)!.elements].sort((left, right) => left.zIndex - right.zIndex).map((element) => element.id))
      .toEqual(["rect-1", "text-1", "line-1"]);
  });

  it("publishes selected tools and defaults as preferences without changing the document", () => {
    const onChange = vi.fn();
    const onPreferencesChange = vi.fn();
    render(<EditorApp
      initialDocument={fixtureDocument()}
      initialTool="arrow"
      sourceImageURL="data:image/png;base64,iVBORw0KGgo="
      onChange={onChange}
      onPreferencesChange={onPreferencesChange}
    />);

    expect(screen.getByRole("button", { name: "Arrow, shortcut A" }).getAttribute("aria-pressed")).toBe("true");
    fireEvent.click(within(screen.getByRole("radiogroup", { name: "Color" }))
      .getByRole("radio", { name: "Red" }));

    expect(onPreferencesChange).toHaveBeenLastCalledWith("arrow", expect.objectContaining({ color: "#FF4D4F" }));
    expect(onChange).not.toHaveBeenCalled();
  });

  it("publishes rectangle fill defaults to preferences without marking the document modified", () => {
    const onChange = vi.fn();
    const onPreferencesChange = vi.fn();
    render(<EditorApp
      initialDocument={fixtureDocument()}
      initialTool="rectangle"
      sourceImageURL="data:image/png;base64,iVBORw0KGgo="
      onChange={onChange}
      onPreferencesChange={onPreferencesChange}
    />);

    fireEvent.click(within(screen.getByRole("radiogroup", { name: "Fill" }))
      .getByRole("radio", { name: "Yellow" }));

    expect(onPreferencesChange).toHaveBeenLastCalledWith(
      "rectangle",
      expect.objectContaining({ rectangleFillColor: "#FADB14" }),
    );
    expect(onChange).not.toHaveBeenCalled();
  });

  it("updates highlighter color without replacing the shared opacity default", () => {
    const onPreferencesChange = vi.fn();
    render(<EditorApp
      initialDocument={fixtureDocument()}
      initialTool="highlighter"
      sourceImageURL="data:image/png;base64,iVBORw0KGgo="
      onChange={() => {}}
      onPreferencesChange={onPreferencesChange}
    />);

    fireEvent.click(within(screen.getByRole("radiogroup", { name: "Color" }))
      .getByRole("radio", { name: "Red" }));

    expect(onPreferencesChange).toHaveBeenLastCalledWith("highlighter", {
      ...fixtureDocument().defaults,
      color: "#FF4D4F",
    });
  });

  it("publishes a creation opacity default only when the slider gesture ends", () => {
    const onPreferencesChange = vi.fn();
    render(<EditorApp
      initialDocument={fixtureDocument()}
      initialTool="highlighter"
      sourceImageURL="data:image/png;base64,iVBORw0KGgo="
      onChange={() => {}}
      onPreferencesChange={onPreferencesChange}
    />);
    const slider = screen.getByRole("slider", { name: "Opacity" });

    fireEvent.input(slider, { target: { value: "25" } });
    expect(onPreferencesChange).not.toHaveBeenCalled();
    fireEvent.pointerUp(slider);

    expect(onPreferencesChange).toHaveBeenCalledOnce();
    expect(onPreferencesChange).toHaveBeenCalledWith(
      "highlighter",
      expect.objectContaining({
        opacity: 1,
        highlighterOpacity: 0.25,
      }),
    );
  });

  it("shows the ten canvas tools including blur and line", () => {
    render(<EditorApp initialDocument={fixtureDocument()} initialTool="selection" sourceImageURL="data:image/png;base64,iVBORw0KGgo=" onChange={() => {}} onPreferencesChange={() => {}} />);

    const palette = within(screen.getByRole("navigation", { name: "Annotation tools" }));
    expect(palette.getAllByRole("button")).toHaveLength(10);
    expect(palette.getByRole("button", { name: "Line, shortcut L" })).toBeTruthy();
    expect(palette.getByRole("button", { name: "Blur, shortcut B" })).toBeTruthy();
  });

  it("renders every tool as an icon button with label and shortcut", () => {
    render(<EditorApp initialDocument={fixtureDocument()} initialTool="selection" sourceImageURL="data:image/png;base64,iVBORw0KGgo=" onChange={() => {}} onPreferencesChange={() => {}} />);

    expect(screen.getByRole("button", { name: "Rectangle, shortcut R" }).getAttribute("aria-describedby"))
      .toBe("tool-tip-rectangle");
    expect(screen.getByRole("tooltip", { name: "Rectangle · R" })).toBeTruthy();
    expect(screen.getByRole("tooltip", { name: "Blur · B" })).toBeTruthy();
  });

  it("shows rectangle style controls and omits opacity for redaction", () => {
    render(<EditorApp initialDocument={fixtureDocument()} initialTool="selection" sourceImageURL="data:image/png;base64,iVBORw0KGgo=" onChange={() => {}} onPreferencesChange={() => {}} />);

    fireEvent.click(screen.getByRole("button", { name: "Rectangle, shortcut R" }));
    expect(screen.getByRole("radiogroup", { name: "Color" })).toBeTruthy();
    expect(screen.getByRole("radiogroup", { name: "Stroke width" })).toBeTruthy();
    expect(screen.getByRole("radiogroup", { name: "Fill" })).toBeTruthy();
    expect(screen.getByRole("radiogroup", { name: "Roughness" })).toBeTruthy();
    expect(screen.getByRole("slider", { name: "Opacity" })).toBeTruthy();

    fireEvent.click(screen.getByRole("button", { name: "Redaction, shortcut X" }));
    expect(screen.queryByRole("slider", { name: "Opacity" })).toBeNull();
    expect(screen.getByText("Opaque black · Fixed")).toBeTruthy();
  });

  it("keeps contextual defaults and rectangle fill through commands and undo", () => {
    const changes: EditorDocument[] = [];
    render(<EditorApp initialDocument={fixtureDocument()} initialTool="selection" sourceImageURL="data:image/png;base64,iVBORw0KGgo=" onChange={(document) => changes.push(document)} onPreferencesChange={() => {}} />);

    fireEvent.click(screen.getByRole("button", { name: "Rectangle, shortcut R" }));
    fireEvent.click(within(screen.getByRole("radiogroup", { name: "Color" }))
      .getByRole("radio", { name: "Red" }));
    fireEvent.click(within(screen.getByRole("radiogroup", { name: "Fill" }))
      .getByRole("radio", { name: "Yellow" }));
    fireEvent.click(screen.getByRole("button", { name: "Create rectangle from canvas" }));

    expect(changes.at(-1)).toMatchObject({
      defaults: { color: "#FF4D4F" },
      elements: [{ id: "rect-1" }, { strokeColor: "#FF4D4F", fillColor: "#FADB14" }],
    });

    fireEvent.keyDown(window, { code: "KeyZ", key: "z", metaKey: true });
    expect(changes.at(-1)).toMatchObject({ defaults: { color: "#FF4D4F" }, elements: [{ id: "rect-1" }] });
  });

  it("does not publish a document change for no-op undo or redo", () => {
    const onChange = vi.fn();
    render(<EditorApp initialDocument={fixtureDocument()} initialTool="selection" sourceImageURL="data:image/png;base64,iVBORw0KGgo=" onChange={onChange} onPreferencesChange={() => {}} />);

    fireEvent.keyDown(window, { code: "KeyZ", key: "z", metaKey: true });
    fireEvent.keyDown(window, { code: "KeyY", key: "y", metaKey: true });

    expect(onChange).not.toHaveBeenCalled();
  });

  it("leaves native Copy, Save, and Export shortcuts unprevented", () => {
    render(<EditorApp initialDocument={fixtureDocument()} initialTool="selection" sourceImageURL="data:image/png;base64,iVBORw0KGgo=" onChange={() => {}} onPreferencesChange={() => {}} />);

    [
      { code: "KeyC", metaKey: true, shiftKey: true },
      { code: "KeyS", metaKey: true },
      { code: "KeyE", metaKey: true },
    ].forEach((init) => {
      const event = new KeyboardEvent("keydown", {
        bubbles: true,
        cancelable: true,
        ...init,
      });
      window.dispatchEvent(event);
      expect(event.defaultPrevented).toBe(false);
    });
  });

  it("leaves Space native on zoom-toolbar and shortcut-dialog buttons while canvas Space arms pan", () => {
    render(<EditorApp initialDocument={fixtureDocument()} initialTool="selection" sourceImageURL="data:image/png;base64,iVBORw0KGgo=" onChange={() => {}} onPreferencesChange={() => {}} />);

    const toolbarSpace = new KeyboardEvent("keydown", {
      code: "Space",
      key: " ",
      bubbles: true,
      cancelable: true,
    });
    screen.getByRole("button", { name: "Zoom in" }).dispatchEvent(toolbarSpace);
    expect(toolbarSpace.defaultPrevented).toBe(false);

    fireEvent.keyDown(window, { code: "Slash", key: "?", shiftKey: true });
    const dialogSpace = new KeyboardEvent("keydown", {
      code: "Space",
      key: " ",
      bubbles: true,
      cancelable: true,
    });
    screen.getByRole("button", { name: "Close keyboard shortcuts" })
      .dispatchEvent(dialogSpace);
    expect(dialogSpace.defaultPrevented).toBe(false);
    expect(screen.getByRole("dialog", { name: "Keyboard Shortcuts" })).toBeTruthy();

    fireEvent.click(screen.getByRole("button", { name: "Close keyboard shortcuts" }));
    const canvasSpace = new KeyboardEvent("keydown", {
      code: "Space",
      key: " ",
      bubbles: true,
      cancelable: true,
    });
    window.dispatchEvent(canvasSpace);
    expect(canvasSpace.defaultPrevented).toBe(true);
  });

  it("applies Escape priority one state at a time", () => {
    render(<EditorApp initialDocument={fixtureDocument()} initialTool="rectangle" sourceImageURL="data:image/png;base64,iVBORw0KGgo=" onChange={() => {}} onPreferencesChange={() => {}} />);

    fireEvent.keyDown(window, {
      code: "Slash",
      key: "?",
      shiftKey: true,
    });
    expect(screen.getByRole("dialog", { name: "Keyboard Shortcuts" }))
      .toBeTruthy();

    fireEvent.keyDown(
      screen.getByRole("button", { name: "Close keyboard shortcuts" }),
      { code: "Escape", key: "Escape" },
    );
    expect(screen.queryByRole("dialog", { name: "Keyboard Shortcuts" }))
      .toBeNull();
    expect(screen.getByRole("button", {
      name: "Rectangle, shortcut R",
    }).getAttribute("aria-pressed")).toBe("true");

    fireEvent.click(screen.getByRole("button", {
      name: "Begin defaults transaction",
    }));
    fireEvent.keyDown(window, { code: "Escape", key: "Escape" });
    expect(screen.getByRole("button", {
      name: "Rectangle, shortcut R",
    }).getAttribute("aria-pressed")).toBe("true");

    fireEvent.keyDown(window, { code: "Escape", key: "Escape" });
    expect(screen.getByRole("button", {
      name: "Selection, shortcut V",
    }).getAttribute("aria-pressed")).toBe("true");
  });

  it("clears selection only after Escape reaches the final priority", () => {
    render(<EditorApp initialDocument={fixtureDocument()} initialTool="selection" sourceImageURL="data:image/png;base64,iVBORw0KGgo=" onChange={() => {}} onPreferencesChange={() => {}} />);

    fireEvent.click(screen.getByRole("button", { name: "Select rect-1" }));
    expect(screen.getByRole("button", { name: "Send Backward" }))
      .toBeTruthy();

    fireEvent.keyDown(window, { code: "Escape", key: "Escape" });

    expect(screen.queryByRole("button", { name: "Send Backward" })).toBeNull();
  });

  it("previews selected opacity ephemerally and commits exactly one updateMany on release", () => {
    const changes: EditorDocument[] = [];
    render(<EditorApp
      initialDocument={fixtureDocument()}
      initialTool="selection"
      sourceImageURL="data:image/png;base64,iVBORw0KGgo="
      onChange={(document) => changes.push(document)}
      onPreferencesChange={() => {}}
    />);
    fireEvent.click(screen.getByRole("button", { name: "Select rect-1" }));
    const slider = screen.getByRole("slider", { name: "Opacity" });

    fireEvent.input(slider, { target: { value: "50" } });
    expect(screen.getByTestId("canvas-opacities").textContent).toBe("rect-1:0.5");
    expect(changes).toHaveLength(0);

    fireEvent.pointerUp(screen.getByRole("slider", { name: "Opacity" }), {
      target: { value: "50" },
    });
    expect(changes).toHaveLength(1);
    expect(changes[0].elements[0]).toMatchObject({ id: "rect-1", opacity: 0.5 });
  });

  it("discards a selected opacity preview on Escape without changing history", () => {
    const changes: EditorDocument[] = [];
    render(<EditorApp
      initialDocument={fixtureDocument()}
      initialTool="selection"
      sourceImageURL="data:image/png;base64,iVBORw0KGgo="
      onChange={(document) => changes.push(document)}
      onPreferencesChange={() => {}}
    />);
    fireEvent.click(screen.getByRole("button", { name: "Select rect-1" }));
    const slider = screen.getByRole("slider", { name: "Opacity" });

    fireEvent.input(slider, { target: { value: "50" } });
    fireEvent.keyDown(slider, { code: "Escape", key: "Escape" });

    expect(screen.getByTestId("canvas-opacities").textContent).toBe("rect-1:1");
    expect(changes).toHaveLength(0);
    fireEvent.keyDown(window, { code: "KeyZ", key: "z", metaKey: true });
    expect(changes).toHaveLength(0);
  });

  it("clears opacity preview and lock when selection and domain change mid-gesture", () => {
    const changes: EditorDocument[] = [];
    const highlighter = {
      id: "highlighter-1",
      type: "highlighter" as const,
      x: 80,
      y: 140,
      width: 120,
      height: 30,
      rotation: 0,
      opacity: 0.25 as const,
      zIndex: 1,
      seed: 105,
      points: [{ x: 80, y: 140 }, { x: 200, y: 170 }],
      color: "#FADB14" as const,
      strokeWidth: 8 as const,
    };
    render(<EditorApp
      initialDocument={fixtureDocument({ elements: [fixtureRect(), highlighter] })}
      initialTool="selection"
      sourceImageURL="data:image/png;base64,iVBORw0KGgo="
      onChange={(document) => changes.push(document)}
      onPreferencesChange={() => {}}
    />);
    fireEvent.click(screen.getByRole("button", { name: "Select rect-1" }));
    fireEvent.input(screen.getByRole("slider", { name: "Opacity" }), {
      target: { value: "75" },
    });
    expect(screen.getByTestId("canvas-opacities").textContent)
      .toBe("rect-1:0.75,highlighter-1:0.25");

    fireEvent.click(screen.getByRole("button", { name: "Shift-select highlighter-1" }));
    expect(screen.getByTestId("canvas-opacities").textContent)
      .toBe("rect-1:1,highlighter-1:0.25");
    expect(() => {
      fireEvent.pointerUp(screen.getByRole("slider", { name: "Opacity" }));
    }).not.toThrow();
    expect(changes).toHaveLength(0);

    fireEvent.keyDown(window, { code: "Escape", key: "Escape" });
    expect(screen.queryByLabelText("Context Rail")).toBeNull();
    expect(changes).toHaveLength(0);
  });

  it("ignores a late native opacity change after selection narrows the domain", () => {
    const changes: EditorDocument[] = [];
    const highlighter = {
      id: "highlighter-1",
      type: "highlighter" as const,
      x: 80,
      y: 140,
      width: 120,
      height: 30,
      rotation: 0,
      opacity: 0.25 as const,
      zIndex: 1,
      seed: 105,
      points: [{ x: 80, y: 140 }, { x: 200, y: 170 }],
      color: "#FADB14" as const,
      strokeWidth: 8 as const,
    };
    render(<EditorApp
      initialDocument={fixtureDocument({ elements: [fixtureRect(), highlighter] })}
      initialTool="selection"
      sourceImageURL="data:image/png;base64,iVBORw0KGgo="
      onChange={(document) => changes.push(document)}
      onPreferencesChange={() => {}}
    />);
    fireEvent.click(screen.getByRole("button", { name: "Select rect-1" }));
    fireEvent.input(screen.getByRole("slider", { name: "Opacity" }), {
      target: { value: "75" },
    });
    fireEvent.click(screen.getByRole("button", { name: "Shift-select highlighter-1" }));
    const narrowedSlider = screen.getByRole("slider", { name: "Opacity" });

    expect(() => {
      fireEvent.change(narrowedSlider, { target: { value: "50" } });
    }).not.toThrow();
    expect(screen.getByTestId("canvas-opacities").textContent)
      .toBe("rect-1:1,highlighter-1:0.25");
    expect(changes).toHaveLength(0);

    fireEvent.keyDown(window, { code: "Escape", key: "Escape" });
    expect(screen.queryByLabelText("Context Rail")).toBeNull();
    fireEvent.click(screen.getByRole("button", { name: "Select rect-1" }));
    fireEvent.click(screen.getByRole("button", { name: "Shift-select highlighter-1" }));
    const freshSlider = screen.getByRole("slider", { name: "Opacity" });
    fireEvent.input(freshSlider, { target: { value: "50" } });
    fireEvent.change(freshSlider, { target: { value: "25" } });

    expect(changes).toHaveLength(1);
    expect(changes[0].elements).toEqual([
      expect.objectContaining({ id: "rect-1", opacity: 0.5 }),
      expect.objectContaining({ id: "highlighter-1", opacity: 0.5 }),
    ]);
  });

  it("publishes the restored document when an active annotation transaction is cancelled", () => {
    const changes: EditorDocument[] = [];
    const initial = fixtureDocument();
    render(<EditorApp initialDocument={initial} initialTool="selection" sourceImageURL="data:image/png;base64,iVBORw0KGgo=" onChange={(document) => changes.push(document)} onPreferencesChange={() => {}} />);

    fireEvent.click(screen.getByRole("button", { name: "Move then cancel" }));

    expect(changes).toHaveLength(2);
    expect(changes[0].elements[0]).toMatchObject({ x: 40, y: 50 });
    expect(changes[1].elements).toEqual(initial.elements);
  });

  it("does not publish a scene change when a defaults-only transaction commits", () => {
    const onChange = vi.fn();
    const onPreferencesChange = vi.fn();
    render(<EditorApp
      initialDocument={fixtureDocument()}
      initialTool="rectangle"
      sourceImageURL="data:image/png;base64,iVBORw0KGgo="
      onChange={onChange}
      onPreferencesChange={onPreferencesChange}
    />);

    fireEvent.click(screen.getByRole("button", {
      name: "Begin defaults transaction",
    }));
    fireEvent.click(within(screen.getByRole("radiogroup", { name: "Fill" }))
      .getByRole("radio", { name: "Yellow" }));
    fireEvent.click(screen.getByRole("button", { name: "Commit transaction" }));

    expect(onPreferencesChange).toHaveBeenLastCalledWith(
      "rectangle",
      expect.objectContaining({ rectangleFillColor: "#FADB14" }),
    );
    expect(onChange).not.toHaveBeenCalled();
  });

  it("publishes a real scene transaction once through its scene command", () => {
    const onChange = vi.fn();
    render(<EditorApp
      initialDocument={fixtureDocument()}
      initialTool="selection"
      sourceImageURL="data:image/png;base64,iVBORw0KGgo="
      onChange={onChange}
      onPreferencesChange={() => {}}
    />);

    fireEvent.click(screen.getByRole("button", { name: "Move then commit" }));

    expect(onChange).toHaveBeenCalledOnce();
    expect(onChange).toHaveBeenCalledWith(
      expect.objectContaining({
        elements: [expect.objectContaining({ id: "rect-1", x: 40, y: 50 })],
      }),
    );
  });

  it("duplicates with an id that cannot collide with arbitrary loaded ids", () => {
    const changes: EditorDocument[] = [];
    const document = fixtureDocument({
      elements: [
        fixtureDocument().elements[0],
        { ...fixtureDocument().elements[0], id: "rectangle-102", x: 100, seed: 2, zIndex: 1 },
      ],
    });
    render(<EditorApp initialDocument={document} initialTool="selection" sourceImageURL="data:image/png;base64,iVBORw0KGgo=" onChange={(next) => changes.push(next)} onPreferencesChange={() => {}} />);

    fireEvent.click(screen.getByRole("button", { name: "Select rect-1" }));
    fireEvent.keyDown(window, { code: "KeyD", key: "d", metaKey: true });

    const duplicated = changes.at(-1)?.elements.at(-1);
    expect(duplicated?.id).not.toBe("rectangle-102");
    expect(new Set(changes.at(-1)?.elements.map((element) => element.id)).size).toBe(3);
    expect(duplicated?.seed).toBe(102);
  });

  it.each(["keyboard", "native"] as const)(
    "performs Undo through one shared action for %s",
    async (source) => {
      const harness = await renderAcceptedNativeEditor();

      fireEvent.click(screen.getByRole("button", { name: "Create rectangle from canvas" }));
      fireEvent.click(screen.getByRole("button", { name: "Select rect-1" }));
      await vi.waitFor(() => expect(historyStatePayloads(harness).at(-1)).toEqual({
        canUndo: true,
        canRedo: false,
      }));
      harness.sent.length = 0;

      if (source === "keyboard") {
        fireEvent.keyDown(window, { code: "KeyZ", key: "z", metaKey: true });
      } else {
        harness.receive(nativeHistoryMessage("undo"));
      }

      await vi.waitFor(() => expect(screen.getByTestId("canvas-positions").textContent)
        .toBe("rect-1:0,0"));
      expect(screen.getByTestId("canvas-selection").textContent).toBe("");
      expect(harness.messages("documentChanged")).toHaveLength(1);
      expect(historyStatePayloads(harness)).toEqual([
        { canUndo: false, canRedo: true },
      ]);
    },
  );

  it.each(historyLockCases)(
    "publishes and enforces the $name history lock without duplicate state",
    async (lockCase) => {
      const harness = await renderAcceptedNativeEditor(lockCase.document());
      fireEvent.click(screen.getByRole("button", { name: "Create rectangle from canvas" }));
      lockCase.select();
      await vi.waitFor(() => expect(historyStatePayloads(harness).at(-1)).toEqual({
        canUndo: true,
        canRedo: false,
      }));
      harness.sent.length = 0;

      act(() => {
        lockCase.enter();
        harness.receive(nativeHistoryMessage("undo"));
      });

      await vi.waitFor(() => expect(historyStatePayloads(harness)).toEqual([
        { canUndo: false, canRedo: false },
      ]));
      const lockedPositions = screen.getByTestId("canvas-positions").textContent;
      const lockedSelection = screen.getByTestId("canvas-selection").textContent;

      fireEvent.keyDown(window, { code: "KeyZ", key: "z", metaKey: true });

      expect(screen.getByTestId("canvas-positions").textContent).toBe(lockedPositions);
      expect(screen.getByTestId("canvas-selection").textContent).toBe(lockedSelection);
      expect(harness.messages("documentChanged")).toEqual([]);
      expect(historyStatePayloads(harness)).toEqual([
        { canUndo: false, canRedo: false },
      ]);

      lockCase.leave();

      await vi.waitFor(() => expect(historyStatePayloads(harness)).toEqual([
        { canUndo: false, canRedo: false },
        { canUndo: true, canRedo: false },
      ]));
    },
  );

  it("publishes transaction begin, changed commit, and changed cancel boundaries exactly", async () => {
    const harness = await renderAcceptedNativeEditor();

    fireEvent.click(screen.getByRole("button", { name: "Begin defaults transaction" }));
    fireEvent.click(screen.getByRole("button", { name: "Update first element" }));
    expect(historyStatePayloads(harness)).toEqual([{ canUndo: false, canRedo: false }]);
    fireEvent.click(screen.getByRole("button", { name: "Commit transaction" }));
    expect(historyStatePayloads(harness)).toEqual([
      { canUndo: false, canRedo: false },
      { canUndo: true, canRedo: false },
    ]);

    fireEvent.click(screen.getByRole("button", { name: "Begin defaults transaction" }));
    fireEvent.click(screen.getByRole("button", { name: "Update first element" }));
    expect(historyStatePayloads(harness).at(-1)).toEqual({ canUndo: false, canRedo: false });
    fireEvent.keyDown(window, { code: "Escape", key: "Escape" });
    expect(historyStatePayloads(harness).slice(-2)).toEqual([
      { canUndo: false, canRedo: false },
      { canUndo: true, canRedo: false },
    ]);
  });

  it("publishes Undo, Redo, and redo-clearing new-command availability", async () => {
    const harness = await renderAcceptedNativeEditor();

    fireEvent.click(screen.getByRole("button", { name: "Create rectangle from canvas" }));
    fireEvent.keyDown(window, { code: "KeyZ", key: "z", metaKey: true });
    fireEvent.keyDown(window, {
      code: "KeyZ",
      key: "z",
      metaKey: true,
      shiftKey: true,
    });
    harness.receive(nativeHistoryMessage("undo"));
    await vi.waitFor(() => expect(screen.getByTestId("canvas-positions").textContent)
      .toBe("rect-1:0,0"));
    fireEvent.click(screen.getByRole("button", { name: "Update first element" }));

    expect(historyStatePayloads(harness)).toEqual([
      { canUndo: false, canRedo: false },
      { canUndo: true, canRedo: false },
      { canUndo: false, canRedo: true },
      { canUndo: true, canRedo: false },
      { canUndo: false, canRedo: true },
      { canUndo: true, canRedo: false },
    ]);
    harness.receive(nativeHistoryMessage("redo"));
    expect(screen.getByTestId("canvas-positions").textContent).toBe("rect-1:1,0");
    expect(historyStatePayloads(harness).at(-1)).toEqual({
      canUndo: true,
      canRedo: false,
    });
  });

  it("deduplicates impossible Undo and Redo while preserving selection and document", async () => {
    const harness = await renderAcceptedNativeEditor();
    fireEvent.click(screen.getByRole("button", { name: "Select rect-1" }));
    harness.sent.length = 0;

    harness.receive(nativeHistoryMessage("undo"));
    harness.receive(nativeHistoryMessage("redo"));
    fireEvent.keyDown(window, { code: "KeyZ", key: "z", metaKey: true });
    fireEvent.keyDown(window, {
      code: "KeyZ",
      key: "z",
      metaKey: true,
      shiftKey: true,
    });

    expect(screen.getByTestId("canvas-positions").textContent).toBe("rect-1:0,0");
    expect(screen.getByTestId("canvas-selection").textContent).toBe("rect-1");
    expect(harness.messages("documentChanged")).toEqual([]);
    expect(historyStatePayloads(harness)).toEqual([]);
  });

  it("returns the latest canonical document through one stable editor handle", () => {
    const editorRef = createRef<EditorAppHandle>();
    const view = render(<EditorApp
      ref={editorRef}
      initialDocument={fixtureDocument()}
      initialTool="selection"
      sourceImageURL="data:image/png;base64,iVBORw0KGgo="
      onChange={() => {}}
      onPreferencesChange={() => {}}
    />);
    const handle = editorRef.current;
    if (!handle) throw new Error("Editor handle was not installed");

    expect(handle.getDocument().elements.map((element) => element.id)).toEqual(["rect-1"]);
    expect(handle.performHistoryAction("undo")).toBe(false);
    fireEvent.click(screen.getByRole("button", { name: "Create rectangle from canvas" }));
    expect(handle.getDocument().elements.map((element) => element.id)).toEqual(["rect-1", "rect-2"]);
    expect(handle.performHistoryAction("undo")).toBe(true);
    expect(handle.getDocument().elements.map((element) => element.id)).toEqual(["rect-1"]);
    expect(handle.performHistoryAction("redo")).toBe(true);
    expect(handle.getDocument().elements.map((element) => element.id)).toEqual(["rect-1", "rect-2"]);
    expect(handle.performHistoryAction("redo")).toBe(false);

    view.unmount();
    expect(editorRef.current).toBeNull();
  });

  it("uses the replaced editor handle's latest document for snapshot and composite output", async () => {
    stubImmediatelyLoadedSourceImage();
    const harness = createNativeBridgeHarness();
    render(<NativeBridgeProvider bridge={harness.bridge}><App /></NativeBridgeProvider>);
    const firstDocument = fixtureDocument({ elements: [{ ...fixtureRect(), x: 20 }] });
    const secondDocument = fixtureDocument({ elements: [{ ...fixtureRect(), x: 200 }] });
    harness.receive(nativeLoadMessage(firstDocument));
    await vi.waitFor(() => expect(screen.getByTestId("canvas-positions").textContent)
      .toBe("rect-1:20,0"));
    harness.receive(nativeLoadMessage(secondDocument, "selection", secondaryRequestId));
    await vi.waitFor(() => expect(screen.getByTestId("canvas-positions").textContent)
      .toBe("rect-1:200,0"));
    fireEvent.click(screen.getByRole("button", { name: "Update first element" }));
    expect(screen.getByTestId("canvas-positions").textContent).toBe("rect-1:201,0");

    window.dispatchEvent(new CustomEvent("myshottr:request-annotation-snapshot", {
      detail: { requestId: secondaryRequestId },
    }));
    harness.receive({
      protocolVersion: 1,
      requestId: secondaryRequestId,
      type: "requestComposite",
      payload: { requestId: secondaryRequestId },
    });

    await vi.waitFor(() => expect(harness.sent).toContainEqual({
      requestId: secondaryRequestId,
      type: "annotationSnapshot",
      payload: {
        document: expect.objectContaining({
          elements: [expect.objectContaining({ id: "rect-1", x: 201 })],
        }),
      },
    }));
    expect(exportMocks.renderDocumentToBlob).toHaveBeenCalledWith(
      expect.objectContaining({
        elements: [expect.objectContaining({ id: "rect-1", x: 201 })],
      }),
      `myshottr-editor://editor/document/${primaryDocumentId}/original.png`,
    );
    await vi.waitFor(() => expect(exportMocks.sendComposite).toHaveBeenCalledOnce());
    expect(historyStatePayloads(harness)).toEqual([
      { canUndo: false, canRedo: false },
      { canUndo: false, canRedo: false },
      { canUndo: true, canRedo: false },
    ]);
  });

  it("routes strict output feedback above document remounts through one bridge subscription", async () => {
    const harness = await renderAcceptedNativeEditor();
    const feedback = editorFeedbackStatus();
    expect(feedback).not.toBeNull();
    expect(feedback?.textContent).toBe("");
    expect(harness.subscribeCalls).toBe(1);

    act(() => {
      harness.receive({
        protocolVersion: 1,
        requestId: "11111111-2222-4333-8444-555555555555",
        type: "saveCompleted",
        payload: { requestId: "11111111-2222-4333-8444-555555555555" },
      });
      harness.receive({
        protocolVersion: 1,
        requestId: "66666666-7777-4888-8999-AAAAAAAAAAAA",
        type: "saveFailed",
        payload: {
          requestId: "66666666-7777-4888-8999-AAAAAAAAAAAA",
          message: "Native owns this alert",
        },
      });
    });
    expect(feedback?.textContent).toBe("");

    const saveRequestId = "BBBBBBBB-CCCC-4DDD-8EEE-FFFFFFFFFFFF";
    act(() => {
      harness.receive(nativeOperationStatusMessage(saveRequestId, {
        operation: "save",
        phase: "started",
      }));
      harness.receive(nativeOperationStatusMessage(saveRequestId, {
        operation: "save",
        phase: "completed",
      }));
    });
    expect(feedback?.textContent).toBe("Saved");

    const replacement = fixtureDocument({ elements: [fixtureLine()] });
    act(() => {
      harness.receive(nativeLoadMessage(replacement, "line", secondaryRequestId));
    });
    await vi.waitFor(() => expect(screen.getByTestId("canvas-positions").textContent)
      .toBe("line-1:15,20"));

    expect(editorFeedbackStatus()).toBe(feedback);
    expect(feedback?.textContent).toBe("Saved");
    expect(harness.subscribeCalls).toBe(1);
  });

  it("returns total correlated outcomes and keeps history inert during the accepted-load remount gap", async () => {
    stubImmediatelyLoadedSourceImage();
    const harness = createNativeBridgeHarness();
    render(<NativeBridgeProvider bridge={harness.bridge}><App /></NativeBridgeProvider>);
    harness.receive(nativeLoadMessage(fixtureDocument()));
    await vi.waitFor(() => expect(screen.getByTestId("canvas-positions").textContent)
      .toBe("rect-1:0,0"));
    fireEvent.click(screen.getByRole("button", { name: "Create rectangle from canvas" }));
    harness.sent.length = 0;
    const gapSnapshotRequestId = "11111111-2222-3333-4444-555555555555";
    const gapCompositeRequestId = "66666666-7777-8888-9999-AAAAAAAAAAAA";
    let exercisedGap = false;
    harness.observeSent((message) => {
      if (
        exercisedGap
        || message.type !== "annotationSnapshot"
        || message.requestId !== secondaryRequestId
      ) return;
      exercisedGap = true;
      harness.receive(nativeHistoryMessage("undo"));
      window.dispatchEvent(new CustomEvent("myshottr:request-annotation-snapshot", {
        detail: { requestId: gapSnapshotRequestId },
      }));
      harness.receive({
        protocolVersion: 1,
        requestId: gapCompositeRequestId,
        type: "requestComposite",
        payload: { requestId: gapCompositeRequestId },
      });
    });

    const replacement = fixtureDocument({ elements: [{ ...fixtureRect(), x: 200 }] });
    harness.receive(nativeLoadMessage(replacement, "selection", secondaryRequestId));
    await vi.waitFor(() => expect(screen.getByTestId("canvas-positions").textContent)
      .toBe("rect-1:200,0"));

    expect(exercisedGap).toBe(true);
    expect(harness.messages("documentChanged")).toEqual([]);
    expect(harness.messages("bridgeError")).toEqual(expect.arrayContaining([
      {
        requestId: gapSnapshotRequestId,
        type: "bridgeError",
        payload: { code: "INVALID_DOCUMENT", message: "No editor document is loaded" },
      },
      {
        requestId: gapCompositeRequestId,
        type: "bridgeError",
        payload: { code: "RENDER_FAILED", message: "No editor document is loaded" },
      },
    ]));
    expect(exportMocks.renderDocumentToBlob).not.toHaveBeenCalled();
    expect(historyStatePayloads(harness).at(-1)).toEqual({ canUndo: false, canRedo: false });
  });

  it("acknowledges an accepted native document with the correlated snapshot", async () => {
    vi.stubGlobal("Image", class {
      naturalWidth = 1440;
      naturalHeight = 900;
      onload: (() => void) | null = null;
      set src(_value: string) { queueMicrotask(() => this.onload?.()); }
    });
    let receiveNative: ((message: Parameters<NativeBridge["subscribe"]>[0] extends (message: infer Message) => void ? Message : never) => void) | undefined;
    const sent: Array<{ requestId?: string; type: string; payload: unknown }> = [];
    const bridge: NativeBridge = {
      send: async (type, payload) => { sent.push({ type, payload }); },
      sendCorrelated: async (requestId, type, payload) => { sent.push({ requestId, type, payload }); },
      subscribe: (handler) => {
        receiveNative = handler;
        return () => { receiveNative = undefined; };
      },
    };

    render(<NativeBridgeProvider bridge={bridge}><App /></NativeBridgeProvider>);
    expect(sent).toContainEqual({ type: "editorReady", payload: {} });

    receiveNative!({
      protocolVersion: 1,
      requestId: "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE",
      type: "loadDocument",
      payload: {
        documentId: "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE",
        sourceImageURL: "myshottr-editor://editor/document/AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE/original.png",
        annotationDocument: fixtureDocument(),
        initialTool: "selection",
      },
    });

    expect(await screen.findByRole("main", { name: "MyShottr editor" })).toBeTruthy();
    expect(sent).toContainEqual({
      requestId: "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE",
      type: "annotationSnapshot",
      payload: { document: fixtureDocument() },
    });
    await vi.waitFor(() => expect(sent.filter(({ type }) => type === "historyStateChanged"))
      .toEqual([{
        type: "historyStateChanged",
        payload: { canUndo: false, canRedo: false },
      }]));
  });

  it("replaces editor state for every accepted same-URL load instance", async () => {
    vi.stubGlobal("Image", class {
      naturalWidth = 1440;
      naturalHeight = 900;
      onload: (() => void) | null = null;
      set src(_value: string) { queueMicrotask(() => this.onload?.()); }
    });
    let receiveNative: ((message: Parameters<NativeBridge["subscribe"]>[0] extends (message: infer Message) => void ? Message : never) => void) | undefined;
    const sent: Array<{ requestId?: string; type: string; payload: unknown }> = [];
    const bridge: NativeBridge = {
      send: async (type, payload) => { sent.push({ type, payload }); },
      sendCorrelated: async (requestId, type, payload) => { sent.push({ requestId, type, payload }); },
      subscribe: (handler) => {
        receiveNative = handler;
        return () => { receiveNative = undefined; };
      },
    };
    const sourceImageURL = "myshottr-editor://editor/document/AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE/original.png";
    const firstDocument = fixtureDocument({
      elements: [{ ...fixtureRect(), x: 20, y: 20 }],
    });
    const secondDocument = fixtureDocument({ elements: [fixtureLine()] });

    render(<NativeBridgeProvider bridge={bridge}><App /></NativeBridgeProvider>);
    receiveNative!({
      protocolVersion: 1,
      requestId: "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE",
      type: "loadDocument",
      payload: {
        documentId: "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE",
        sourceImageURL,
        annotationDocument: firstDocument,
        initialTool: "selection",
      },
    });
    await vi.waitFor(() => expect(screen.getByTestId("canvas-positions").textContent)
      .toBe("rect-1:20,20"));
    fireEvent.click(screen.getByRole("button", { name: "Select rect-1" }));
    fireEvent.keyDown(window, { code: "ArrowRight", key: "ArrowRight" });
    expect(screen.getByTestId("canvas-positions").textContent).toBe("rect-1:21,20");
    expect(screen.getByTestId("canvas-interaction-lock").textContent).toBe("true");

    receiveNative!({
      protocolVersion: 1,
      requestId: "FFFFFFFF-EEEE-DDDD-CCCC-BBBBBBBBBBBB",
      type: "loadDocument",
      payload: {
        documentId: "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE",
        sourceImageURL,
        annotationDocument: secondDocument,
        initialTool: "line",
      },
    });
    await vi.waitFor(() => expect(sent).toContainEqual({
      requestId: "FFFFFFFF-EEEE-DDDD-CCCC-BBBBBBBBBBBB",
      type: "annotationSnapshot",
      payload: { document: secondDocument },
    }));
    fireEvent.keyUp(window, { code: "ArrowRight", key: "ArrowRight" });

    expect(screen.getByTestId("canvas-positions").textContent).toBe("line-1:15,20");
    expect(screen.getByTestId("canvas-selection").textContent).toBe("");
    expect(screen.getByTestId("canvas-interaction-lock").textContent).toBe("false");
    expect(screen.getByRole("button", { name: "Line, shortcut L" }).getAttribute("aria-pressed"))
      .toBe("true");
    expect(sent.filter(({ type }) => type === "documentChanged")).toEqual([]);
  });

  it("discards an existing-text session when a native document replacement unmounts it", async () => {
    vi.stubGlobal("Image", class {
      naturalWidth = 1440;
      naturalHeight = 900;
      onload: (() => void) | null = null;
      set src(_value: string) { queueMicrotask(() => this.onload?.()); }
    });
    let receiveNative: ((message: Parameters<NativeBridge["subscribe"]>[0] extends (message: infer Message) => void ? Message : never) => void) | undefined;
    const sent: Array<{ requestId?: string; type: string; payload: unknown }> = [];
    const bridge: NativeBridge = {
      send: async (type, payload) => { sent.push({ type, payload }); },
      sendCorrelated: async (requestId, type, payload) => { sent.push({ requestId, type, payload }); },
      subscribe: (handler) => {
        receiveNative = handler;
        return () => { receiveNative = undefined; };
      },
    };
    const sourceImageURL = "myshottr-editor://editor/document/AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE/original.png";
    const firstRequestId = "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE";
    const secondRequestId = "FFFFFFFF-EEEE-DDDD-CCCC-BBBBBBBBBBBB";
    const firstDocument = fixtureDocument({ elements: [fixtureText()] });
    const secondDocument = fixtureDocument({ elements: [fixtureLine()] });

    render(<NativeBridgeProvider bridge={bridge}><App /></NativeBridgeProvider>);
    receiveNative!({
      protocolVersion: 1,
      requestId: firstRequestId,
      type: "loadDocument",
      payload: {
        documentId: firstRequestId,
        sourceImageURL,
        annotationDocument: firstDocument,
        initialTool: "selection",
      },
    });
    await vi.waitFor(() => expect(screen.getByTestId("canvas-positions").textContent)
      .toBe("text-1:40,50"));
    fireEvent.click(screen.getByRole("button", { name: "Shift-select text-1" }));
    fireEvent.click(screen.getByRole("button", { name: "Edit text-1" }));
    const staleEditor = screen.getByRole("textbox", { name: "Edit annotation text" });
    fireEvent.change(staleEditor, { target: { value: "must not cross documents" } });

    receiveNative!({
      protocolVersion: 1,
      requestId: secondRequestId,
      type: "loadDocument",
      payload: {
        documentId: secondRequestId,
        sourceImageURL,
        annotationDocument: secondDocument,
        initialTool: "line",
      },
    });
    await vi.waitFor(() => expect(screen.getByTestId("canvas-positions").textContent)
      .toBe("line-1:15,20"));
    expect(screen.queryByRole("textbox", { name: "Edit annotation text" })).toBeNull();
    fireEvent.blur(staleEditor);

    expect(sent.filter(({ type }) => type === "documentChanged")).toEqual([]);
  });

  it("ignores an older load that finishes source validation after a newer load", async () => {
    const pendingImages = new Map<string, () => void>();
    vi.stubGlobal("Image", class {
      naturalWidth = 1440;
      naturalHeight = 900;
      onload: (() => void) | null = null;
      set src(value: string) {
        pendingImages.set(value, () => this.onload?.());
      }
    });
    let receiveNative: ((message: Parameters<NativeBridge["subscribe"]>[0] extends (message: infer Message) => void ? Message : never) => void) | undefined;
    const sent: Array<{ requestId?: string; type: string; payload: unknown }> = [];
    const bridge: NativeBridge = {
      send: async (type, payload) => { sent.push({ type, payload }); },
      sendCorrelated: async (requestId, type, payload) => { sent.push({ requestId, type, payload }); },
      subscribe: (handler) => {
        receiveNative = handler;
        return () => { receiveNative = undefined; };
      },
    };
    const firstRequestId = "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE";
    const secondRequestId = "FFFFFFFF-EEEE-DDDD-CCCC-BBBBBBBBBBBB";
    const firstSourceURL = `myshottr-editor://editor/document/${firstRequestId}/original.png`;
    const secondSourceURL = `myshottr-editor://editor/document/${secondRequestId}/original.png`;
    const firstDocument = fixtureDocument();
    const secondDocument = fixtureDocument({ elements: [fixtureLine()] });

    render(<NativeBridgeProvider bridge={bridge}><App /></NativeBridgeProvider>);
    receiveNative!({
      protocolVersion: 1,
      requestId: firstRequestId,
      type: "loadDocument",
      payload: {
        documentId: firstRequestId,
        sourceImageURL: firstSourceURL,
        annotationDocument: firstDocument,
        initialTool: "selection",
      },
    });
    receiveNative!({
      protocolVersion: 1,
      requestId: secondRequestId,
      type: "loadDocument",
      payload: {
        documentId: secondRequestId,
        sourceImageURL: secondSourceURL,
        annotationDocument: secondDocument,
        initialTool: "line",
      },
    });

    const finishSecondLoad = pendingImages.get(secondSourceURL);
    if (!finishSecondLoad) throw new Error("Missing second pending source image");
    finishSecondLoad();
    await vi.waitFor(() => expect(screen.getByTestId("canvas-positions").textContent)
      .toBe("line-1:15,20"));

    const finishFirstLoad = pendingImages.get(firstSourceURL);
    if (!finishFirstLoad) throw new Error("Missing first pending source image");
    finishFirstLoad();
    await new Promise<void>((resolve) => queueMicrotask(resolve));
    await vi.waitFor(() => expect(sent.filter(({ type }) => type === "annotationSnapshot"))
      .toEqual([{
        requestId: secondRequestId,
        type: "annotationSnapshot",
        payload: { document: secondDocument },
      }]));

    expect(screen.getByTestId("canvas-positions").textContent).toBe("line-1:15,20");
    expect(screen.getByRole("button", { name: "Line, shortcut L" }).getAttribute("aria-pressed"))
      .toBe("true");
    expect(sent.filter(({ type }) => type === "historyStateChanged")).toEqual([{
      type: "historyStateChanged",
      payload: { canUndo: false, canRedo: false },
    }]);
  });

  it("returns a correlated annotation snapshot through the local native request event", async () => {
    vi.stubGlobal("Image", class {
      naturalWidth = 1440;
      naturalHeight = 900;
      onload: (() => void) | null = null;
      set src(_value: string) { queueMicrotask(() => this.onload?.()); }
    });
    let receiveNative: ((message: Parameters<NativeBridge["subscribe"]>[0] extends (message: infer Message) => void ? Message : never) => void) | undefined;
    const sent: Array<{ requestId?: string; type: string; payload: unknown }> = [];
    const bridge: NativeBridge = {
      send: async (type, payload) => { sent.push({ type, payload }); },
      sendCorrelated: async (requestId, type, payload) => { sent.push({ requestId, type, payload }); },
      subscribe: (handler) => { receiveNative = handler; return () => { receiveNative = undefined; }; },
    };

    render(<NativeBridgeProvider bridge={bridge}><App /></NativeBridgeProvider>);
    receiveNative!({
      protocolVersion: 1,
      requestId: "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE",
      type: "loadDocument",
      payload: {
        documentId: "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE",
        sourceImageURL: "myshottr-editor://editor/document/AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE/original.png",
        annotationDocument: fixtureDocument(),
        initialTool: "selection",
      },
    });
    await screen.findByRole("main", { name: "MyShottr editor" });

    window.dispatchEvent(new CustomEvent("myshottr:request-annotation-snapshot", {
      detail: { requestId: "FFFFFFFF-EEEE-DDDD-CCCC-BBBBBBBBBBBB" },
    }));

    await vi.waitFor(() => expect(sent).toContainEqual({
      requestId: "FFFFFFFF-EEEE-DDDD-CCCC-BBBBBBBBBBBB",
      type: "annotationSnapshot",
      payload: { document: fixtureDocument() },
    }));
  });

  it("returns the latest highlighter defaults in a later annotation snapshot", async () => {
    vi.stubGlobal("Image", class {
      naturalWidth = 1440;
      naturalHeight = 900;
      onload: (() => void) | null = null;
      set src(_value: string) { queueMicrotask(() => this.onload?.()); }
    });
    let receiveNative: ((message: Parameters<NativeBridge["subscribe"]>[0] extends (message: infer Message) => void ? Message : never) => void) | undefined;
    const sent: Array<{ requestId?: string; type: string; payload: unknown }> = [];
    const bridge: NativeBridge = {
      send: async (type, payload) => { sent.push({ type, payload }); },
      sendCorrelated: async (requestId, type, payload) => {
        sent.push({ requestId, type, payload });
      },
      subscribe: (handler) => {
        receiveNative = handler;
        return () => { receiveNative = undefined; };
      },
    };

    render(<NativeBridgeProvider bridge={bridge}><App /></NativeBridgeProvider>);
    receiveNative!({
      protocolVersion: 1,
      requestId: "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE",
      type: "loadDocument",
      payload: {
        documentId: "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE",
        sourceImageURL: "myshottr-editor://editor/document/AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE/original.png",
        annotationDocument: fixtureDocument(),
        initialTool: "selection",
      },
    });
    await screen.findByRole("main", { name: "MyShottr editor" });
    fireEvent.click(screen.getByRole("button", { name: "Highlighter, shortcut H" }));
    fireEvent.change(screen.getByRole("slider", { name: "Opacity" }), {
      target: { value: "25" },
    });

    window.dispatchEvent(new CustomEvent("myshottr:request-annotation-snapshot", {
      detail: { requestId: "FFFFFFFF-EEEE-DDDD-CCCC-BBBBBBBBBBBB" },
    }));

    await vi.waitFor(() => expect(sent).toContainEqual({
      requestId: "FFFFFFFF-EEEE-DDDD-CCCC-BBBBBBBBBBBB",
      type: "annotationSnapshot",
      payload: {
        document: {
          ...fixtureDocument(),
          defaults: {
            ...fixtureDocument().defaults,
            highlighterOpacity: 0.25,
          },
        },
      },
    }));
    expect(sent.some(({ type }) => type === "documentChanged")).toBe(false);
  });

  it("reports INVALID_DOCUMENT when the source image dimensions differ", async () => {
    vi.stubGlobal("Image", class {
      naturalWidth = 2;
      naturalHeight = 2;
      onload: (() => void) | null = null;
      set src(_value: string) { queueMicrotask(() => this.onload?.()); }
    });
    let receiveNative: ((message: Parameters<NativeBridge["subscribe"]>[0] extends (message: infer Message) => void ? Message : never) => void) | undefined;
    const sent: Array<{ requestId?: string; type: string; payload: unknown }> = [];
    const bridge: NativeBridge = {
      send: async (type, payload) => { sent.push({ type, payload }); },
      sendCorrelated: async (requestId, type, payload) => { sent.push({ requestId, type, payload }); },
      subscribe: (handler) => { receiveNative = handler; return () => { receiveNative = undefined; }; },
    };

    render(<NativeBridgeProvider bridge={bridge}><App /></NativeBridgeProvider>);
    receiveNative!({
      protocolVersion: 1,
      requestId: "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE",
      type: "loadDocument",
      payload: {
        documentId: "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE",
        sourceImageURL: "myshottr-editor://editor/document/AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE/original.png",
        annotationDocument: fixtureDocument(),
        initialTool: "selection",
      },
    });

    await vi.waitFor(() => expect(sent).toContainEqual({
      requestId: "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE",
      type: "bridgeError",
      payload: { code: "INVALID_DOCUMENT", message: "Source image dimensions do not match the document" },
    }));
    expect(screen.queryByRole("navigation", { name: "Annotation tools" })).toBeNull();
  });
});
