import { act, cleanup, createEvent, fireEvent, render, screen, within } from "@testing-library/react";
import Konva from "konva";
import { createRef, type RefAttributes } from "react";
import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";

import { createHistoryStore } from "../model/history";
import type { EditorTool } from "../model/elements";
import { keyboardCommandFor } from "../input/ShortcutRouter";
import { fixtureBlur, fixtureDocument, fixtureRect, fixtureText } from "../test/fixtures";
import {
  cancelAnnotationInteraction,
  createCanvasElement,
  EditorCanvas,
  type EditorCanvasHandle,
} from "./EditorCanvas";

const konvaControl = vi.hoisted(() => ({
  stopDrag: vi.fn(),
  stopTransform: vi.fn(),
  forceUpdate: vi.fn(),
  draw: vi.fn(),
  preventDefault: vi.fn(),
  setPointerCapture: vi.fn(),
  releasePointerCapture: vi.fn(),
  outerSetPointerCapture: vi.fn(),
  outerReleasePointerCapture: vi.fn(),
  contentSetPointerCapture: vi.fn(),
  contentReleasePointerCapture: vi.fn(),
  capturedPointers: new Set<number>(),
  outerCapturedPointers: new Set<number>(),
  contentCapturedPointers: new Set<number>(),
  annotationStartPointerId: 1,
  annotationEndPointerId: 1,
  annotationLifecyclePointerId: 1 as number | undefined,
  stage: undefined as {
    getPointerPosition: () => { x: number; y: number };
    container: () => {
      setPointerCapture: (pointerId: number) => void;
      releasePointerCapture: (pointerId: number) => void;
      hasPointerCapture: (pointerId: number) => boolean;
    };
    getContent: () => {
      setPointerCapture: (pointerId: number) => void;
      releasePointerCapture: (pointerId: number) => void;
      hasPointerCapture: (pointerId: number) => boolean;
    };
  } | undefined,
  annotationValues: {
    x: 0,
    y: 0,
    scaleX: 1,
    scaleY: 1,
    rotation: 0,
  },
  transformerNodes: [] as unknown[],
  rotateEnabled: true,
  dragTarget: { x: 40, y: 50 },
}));

vi.mock("react-konva", async () => {
  const React = await import("react");
  const primitive = ({ children }: { children?: React.ReactNode }) => React.createElement("div", null, children);
  const Group = React.forwardRef((props: Record<string, unknown> & { children?: React.ReactNode }, ref) => {
    const initialValues = {
      x: Number(props.x ?? 0),
      y: Number(props.y ?? 0),
      scaleX: Number(props.scaleX ?? 1),
      scaleY: Number(props.scaleY ?? 1),
      rotation: Number(props.rotation ?? 0),
    };
    const isAnnotationNode = props.draggable === true;
    if (isAnnotationNode) Object.assign(konvaControl.annotationValues, initialValues);
    const values = React.useRef(
      isAnnotationNode ? konvaControl.annotationValues : initialValues
    );
    const node = React.useMemo(() => ({
      x: (value?: number) => value === undefined ? values.current.x : (values.current.x = value),
      y: (value?: number) => value === undefined ? values.current.y : (values.current.y = value),
      scaleX: (value?: number) => value === undefined ? values.current.scaleX : (values.current.scaleX = value),
      scaleY: (value?: number) => value === undefined ? values.current.scaleY : (values.current.scaleY = value),
      rotation: (value?: number) => value === undefined ? values.current.rotation : (values.current.rotation = value),
      stopDrag: konvaControl.stopDrag,
      getLayer: () => ({ draw: konvaControl.draw }),
      getStage: () => konvaControl.stage,
    }), []);
    React.useImperativeHandle(ref, () => node);
    const onPointerDown = props.onPointerDown as ((event: {
      currentTarget: typeof node;
      evt: PointerEvent;
    }) => void) | undefined;
    const onDragStart = props.onDragStart as ((event: {
      currentTarget: typeof node;
      evt: Event | { pointerId: number };
    }) => void) | undefined;
    const onDragMove = props.onDragMove as ((event: { currentTarget: typeof node }) => void) | undefined;
    const onDragEnd = props.onDragEnd as ((event: {
      currentTarget: typeof node;
      evt: Event | { pointerId: number };
    }) => void) | undefined;
    const onTransformStart = props.onTransformStart as ((event: {
      currentTarget: typeof node;
      evt: Event | { pointerId: number };
    }) => void) | undefined;
    const onTransformEnd = props.onTransformEnd as ((event: {
      currentTarget: typeof node;
      evt: Event | { pointerId: number };
    }) => void) | undefined;
    const onDblClick = props.onDblClick as (() => void) | undefined;
    const onClick = props.onClick as ((event: { evt: MouseEvent }) => void) | undefined;
    if (onDblClick || props["data-testid"] === "element-text-1") return React.createElement("div", {
      "data-testid": props["data-testid"],
      onPointerDown: (event: React.PointerEvent) => onPointerDown?.({
        currentTarget: node,
        evt: event.nativeEvent,
      }),
      onDoubleClick: onDblClick,
      onClick: (event: React.MouseEvent) => onClick?.({ evt: event.nativeEvent }),
      onAuxClick: () => onTransformStart?.({
        currentTarget: node,
        evt: { pointerId: konvaControl.annotationStartPointerId },
      }),
      onContextMenu: (event: React.MouseEvent) => {
        event.preventDefault();
        onTransformEnd?.({
          currentTarget: node,
          evt: { pointerId: konvaControl.annotationEndPointerId },
        });
      },
    }, props.children);
    if (!onDragStart) return React.createElement("div", {
      "data-testid": props["data-testid"],
    }, props.children);
    return React.createElement("div", {
      "data-testid": props["data-testid"] === "element-text-1"
        ? props["data-testid"]
        : "annotation-node",
      "data-element-testid": props["data-testid"],
      draggable: true,
      onPointerDown: (event: React.PointerEvent) => onPointerDown?.({
        currentTarget: node,
        evt: event.nativeEvent,
      }),
      onDragStart: () => onDragStart({
        currentTarget: node,
        evt: annotationLifecycleEvent(),
      }),
      onDrag: () => {
        values.current.x = konvaControl.dragTarget.x;
        values.current.y = konvaControl.dragTarget.y;
        onDragMove?.({ currentTarget: node });
      },
      onDragEnd: () => onDragEnd?.({
        currentTarget: node,
        evt: annotationLifecycleEvent(),
      }),
      onClick: (event: React.MouseEvent) => onClick?.({ evt: event.nativeEvent }),
      onDoubleClick: () => {
        onTransformStart?.({
          currentTarget: node,
          evt: annotationLifecycleEvent(),
        });
        values.current.x = 40;
        values.current.y = 50;
        values.current.scaleX = 0.5;
        values.current.scaleY = 1.25;
        values.current.rotation = 15;
      },
      onContextMenu: (event: React.MouseEvent) => {
        event.preventDefault();
        onTransformEnd?.({
          currentTarget: node,
          evt: annotationLifecycleEvent(),
        });
      },
    }, props.children);
  });
  const Transformer = React.forwardRef((props: {
    rotateEnabled?: boolean;
    onPointerDown?: (event: { currentTarget: unknown; evt: PointerEvent }) => void;
  }, ref) => {
    konvaControl.rotateEnabled = props.rotateEnabled ?? true;
    const node = React.useMemo(() => ({
      nodes: (nodes?: unknown[]) => {
        if (nodes) konvaControl.transformerNodes = nodes;
        return konvaControl.transformerNodes;
      },
      getLayer: () => ({ draw: () => {} }),
      getStage: () => konvaControl.stage,
      stopTransform: konvaControl.stopTransform,
      forceUpdate: konvaControl.forceUpdate,
    }), []);
    React.useImperativeHandle(ref, () => node);
    return React.createElement("div", {
      "data-testid": "transformer",
      onPointerDown: (event: React.PointerEvent) => props.onPointerDown?.({
        currentTarget: node,
        evt: event.nativeEvent,
      }),
    });
  });
  const Stage = ({ children, width, height, onPointerDown, onPointerMove, onPointerUp, onPointerCancel, onWheel }: {
    children?: React.ReactNode;
    width: number;
    height: number;
    onPointerDown?: (event: unknown) => void;
    onPointerMove?: (event: unknown) => void;
    onPointerUp?: (event: unknown) => void;
    onPointerCancel?: (event: unknown) => void;
    onWheel?: (event: unknown) => void;
  }) => {
    const pointer = React.useRef({ x: 0, y: 0 });
    const outerContainer = React.useMemo(() => ({
      setPointerCapture: (pointerId: number) => {
        konvaControl.capturedPointers.add(pointerId);
        konvaControl.outerCapturedPointers.add(pointerId);
        konvaControl.outerSetPointerCapture(pointerId);
        konvaControl.setPointerCapture(pointerId);
      },
      releasePointerCapture: (pointerId: number) => {
        konvaControl.capturedPointers.delete(pointerId);
        konvaControl.outerCapturedPointers.delete(pointerId);
        konvaControl.outerReleasePointerCapture(pointerId);
        konvaControl.releasePointerCapture(pointerId);
      },
      hasPointerCapture: (pointerId: number) => konvaControl.outerCapturedPointers.has(pointerId),
    }), []);
    const content = React.useMemo(() => ({
      setPointerCapture: (pointerId: number) => {
        konvaControl.capturedPointers.add(pointerId);
        konvaControl.contentCapturedPointers.add(pointerId);
        konvaControl.contentSetPointerCapture(pointerId);
        konvaControl.setPointerCapture(pointerId);
      },
      releasePointerCapture: (pointerId: number) => {
        konvaControl.capturedPointers.delete(pointerId);
        konvaControl.contentCapturedPointers.delete(pointerId);
        konvaControl.contentReleasePointerCapture(pointerId);
        konvaControl.releasePointerCapture(pointerId);
      },
      hasPointerCapture: (pointerId: number) => konvaControl.contentCapturedPointers.has(pointerId),
    }), []);
    const stage = React.useMemo(() => {
      const value = {
        getPointerPosition: () => ({ ...pointer.current }),
        container: () => outerContainer,
        getContent: () => content,
        getStage: () => value,
      };
      return value;
    }, [content, outerContainer]);
    konvaControl.stage = stage;
    const eventFor = (event: React.PointerEvent | React.WheelEvent) => {
      pointer.current.x = event.clientX;
      pointer.current.y = event.clientY;
      return {
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
        target: stage,
      };
    };
    return React.createElement("div", {
      "data-testid": "stage",
      "data-width": width,
      "data-height": height,
      onPointerDown: (event: React.PointerEvent) => onPointerDown?.(eventFor(event)),
      onPointerMove: (event: React.PointerEvent) => onPointerMove?.(eventFor(event)),
      onPointerUp: (event: React.PointerEvent) => onPointerUp?.(eventFor(event)),
      onPointerCancel: (event: React.PointerEvent) => onPointerCancel?.(eventFor(event)),
      onWheel: (event: React.WheelEvent) => onWheel?.(eventFor(event)),
    }, children);
  };
  return {
    Circle: primitive,
    Group,
    Image: primitive,
    Layer: primitive,
    Line: primitive,
    Path: primitive,
    Rect: primitive,
    Stage,
    Text: primitive,
    Transformer,
  };
});

const VIEWPORT = {
  workspace: { width: 1000, height: 700 },
  availableRect: { x: 16, y: 76, width: 968, height: 608 },
  zoom: 1,
  pan: { x: 0, y: 0 },
};

const VIEWPORT_PROPS = {
  viewport: VIEWPORT,
  spacePanReady: false,
  interactionLocked: false,
  viewportPanLocked: false,
  onViewportWheel: () => {},
  onViewportPanBy: () => {},
  onInteractionActiveChange: () => {},
  onBeginNewText: () => {},
  toSourcePoint: (point: { x: number; y: number }) => point,
};

let nextAnimationFrame = 1;
const animationFrames = new Map<number, FrameRequestCallback>();

beforeEach(() => {
  nextAnimationFrame = 1;
  animationFrames.clear();
  vi.stubGlobal("PointerEvent", class extends MouseEvent {
    public readonly pointerId: number;

    public constructor(type: string, init: PointerEventInit = {}) {
      super(type, init);
      this.pointerId = init.pointerId ?? 0;
    }
  });
  vi.stubGlobal("requestAnimationFrame", vi.fn((callback: FrameRequestCallback) => {
    const frame = nextAnimationFrame++;
    animationFrames.set(frame, callback);
    return frame;
  }));
  vi.stubGlobal("cancelAnimationFrame", vi.fn((frame: number) => {
    animationFrames.delete(frame);
  }));
});

afterEach(() => {
  cleanup();
  vi.clearAllMocks();
  konvaControl.transformerNodes = [];
  konvaControl.rotateEnabled = true;
  konvaControl.dragTarget = { x: 40, y: 50 };
  konvaControl.annotationStartPointerId = 1;
  konvaControl.annotationEndPointerId = 1;
  konvaControl.annotationLifecyclePointerId = 1;
  konvaControl.stage = undefined;
  konvaControl.capturedPointers.clear();
  konvaControl.outerCapturedPointers.clear();
  konvaControl.contentCapturedPointers.clear();
  animationFrames.clear();
  vi.unstubAllGlobals();
});

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

function annotationLifecycleEvent(): MouseEvent | { pointerId: number } {
  const pointerId = konvaControl.annotationLifecyclePointerId;
  return pointerId === undefined
    ? new MouseEvent("annotation-lifecycle")
    : { pointerId };
}

describe("cancelAnnotationInteraction", () => {
  it.each(["move", "transform"] as const)(
    "stops a live %s and restores the real Konva node to its authoritative element",
    (kind) => {
      const element = fixtureDocument().elements[0];
      const node = new Konva.Group({
        x: 40,
        y: 50,
        scaleX: 0.5,
        scaleY: 1.25,
        rotation: 15,
      });
      const draw = vi.fn();
      vi.spyOn(node, "getLayer").mockReturnValue({
        batchDraw: vi.fn(),
        draw,
      } as never);
      const stopDrag = vi.spyOn(node, "stopDrag");
      const transformer = {
        stopTransform: vi.fn(),
        forceUpdate: vi.fn(),
      };

      cancelAnnotationInteraction({
        kind,
        node,
        element,
        elements: [element],
        nodes: new Map([[element.id, node]]),
      }, transformer);

      if (kind === "move") {
        expect(stopDrag).toHaveBeenCalledOnce();
        expect(transformer.stopTransform).not.toHaveBeenCalled();
      } else {
        expect(stopDrag).not.toHaveBeenCalled();
        expect(transformer.stopTransform).toHaveBeenCalledOnce();
      }
      expect(node.position()).toEqual({ x: element.x, y: element.y });
      expect(node.scale()).toEqual({ x: 1, y: 1 });
      expect(node.rotation()).toBe(element.rotation);
      expect(transformer.forceUpdate).toHaveBeenCalledOnce();
      expect(draw).toHaveBeenCalledOnce();
    },
  );
});

describe("EditorCanvas gesture terminals", () => {
  it("sizes the Stage to the full measured workspace instead of source pixels times zoom", () => {
    const initial = fixtureDocument();
    render(
      <EditorCanvas
        document={initial}
        sourceImageURL="data:image/png;base64,iVBORw0KGgo="
        tool="selection"
        {...VIEWPORT_PROPS}
        viewport={{ ...VIEWPORT, zoom: 2 }}
        selectedIds={[]}
        onSelect={() => {}}
        onEditText={() => {}}
        onCommand={() => {}}
        onBeginTransaction={() => {}}
        onCommitTransaction={() => {}}
        onCancelTransaction={() => {}}
        textEditorOverlay={undefined}
      />,
    );

    expect(screen.getByTestId("stage").getAttribute("data-width")).toBe("1000");
    expect(screen.getByTestId("stage").getAttribute("data-height")).toBe("700");
  });

  it.each([
    ["ordinary trackpad pan", false, false],
    ["control-wheel zoom", false, true],
    ["command-wheel zoom", true, false],
  ] as const)("prevents the browser default and routes %s", (_label, metaKey, ctrlKey) => {
    const onViewportWheel = vi.fn();
    render(
      <EditorCanvas
        document={fixtureDocument()}
        sourceImageURL="data:image/png;base64,iVBORw0KGgo="
        tool="selection"
        {...VIEWPORT_PROPS}
        onViewportWheel={onViewportWheel}
        selectedIds={[]}
        onSelect={() => {}}
        onEditText={() => {}}
        onCommand={() => {}}
        onBeginTransaction={() => {}}
        onCommitTransaction={() => {}}
        onCancelTransaction={() => {}}
        textEditorOverlay={undefined}
      />,
    );
    const event = new WheelEvent("wheel", {
      bubbles: true,
      cancelable: true,
      clientX: 320,
      clientY: 240,
      deltaX: 12,
      deltaY: -30,
      metaKey,
      ctrlKey,
    });

    fireEvent(screen.getByTestId("stage"), event);

    expect(konvaControl.preventDefault).toHaveBeenCalledOnce();
    expect(onViewportWheel).toHaveBeenCalledWith({
      pointer: { x: 320, y: 240 },
      deltaX: 12,
      deltaY: -30,
      metaKey,
      ctrlKey,
    });
  });

  it("starts panning only when Space was already held at pointer-down", () => {
    const initial = fixtureDocument({ elements: [] });
    const history = createHistoryStore(initial);
    const onViewportPanBy = vi.fn();
    const onInteractionActiveChange = vi.fn();
    render(
      <EditorCanvas
        document={initial}
        sourceImageURL="data:image/png;base64,iVBORw0KGgo="
        tool="rectangle"
        {...VIEWPORT_PROPS}
        spacePanReady
        onViewportPanBy={onViewportPanBy}
        onInteractionActiveChange={onInteractionActiveChange}
        selectedIds={[]}
        onSelect={() => {}}
        onEditText={() => {}}
        onCommand={(command) => history.dispatch(command)}
        onBeginTransaction={(label) => history.beginTransaction(label)}
        onCommitTransaction={() => history.commitTransaction()}
        onCancelTransaction={() => history.cancelTransaction()}
        textEditorOverlay={undefined}
      />,
    );
    const stage = screen.getByTestId("stage");

    fireEvent.pointerDown(stage, { clientX: 10, clientY: 20, pointerId: 1 });
    fireEvent.pointerMove(stage, { clientX: 40, clientY: 55, pointerId: 1 });
    flushAnimationFrame();
    fireEvent.pointerUp(stage, { clientX: 40, clientY: 55, pointerId: 1 });

    expect(onViewportPanBy).toHaveBeenCalledWith({ x: 30, y: 35 });
    expect(onInteractionActiveChange.mock.calls.map(([active]) => active))
      .toEqual([true, false]);
    expect(history.document.elements).toHaveLength(0);
  });

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
    const { shell, setPointerCapture, releasePointerCapture } = installCanvasShellPointerCapture();
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
    expect(onInteractionActiveChange.mock.calls.map(([active]) => active)).toEqual([true]);
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
    expect(onInteractionActiveChange.mock.calls.map(([active]) => active)).toEqual([true, false]);
    expect(onCommand).not.toHaveBeenCalled();
    expect(setPointerCapture).toHaveBeenCalledWith(41);
    expect(releasePointerCapture).toHaveBeenCalledWith(41);
    expect(shell.style.cursor).toBe("crosshair");
  });

  it.each([
    ["annotation", "annotation-node"],
    ["transformer handle", "transformer"],
  ] as const)("gives middle-button pan precedence over a selected %s", (_label, testId) => {
    const initial = fixtureDocument();
    const history = createHistoryStore(initial);
    const onSelect = vi.fn();
    const onViewportPanBy = vi.fn();
    renderSelectionCanvas(initial, history, ["rect-1"], { onSelect, onViewportPanBy });
    installCanvasShellPointerCapture();
    const target = screen.getByTestId(testId);

    fireEvent.pointerDown(target, {
      button: 1, buttons: 4, clientX: 200, clientY: 210, pointerId: 42,
    });
    fireEvent.pointerMove(target, {
      button: 1, buttons: 4, clientX: 245, clientY: 250, pointerId: 42,
    });
    flushAnimationFrame();
    fireEvent.pointerUp(target, {
      button: 1, buttons: 0, clientX: 245, clientY: 250, pointerId: 42,
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
      textEditorOverlay: <textarea aria-label="Edit annotation text" defaultValue="Draft stays here" onBlur={onTextResult} />,
    });
    installCanvasShellPointerCapture();
    const textarea = screen.getByRole("textbox", { name: "Edit annotation text" }) as HTMLTextAreaElement;
    textarea.focus();

    fireEvent.pointerDown(textarea, {
      button: 1, buttons: 4, clientX: 300, clientY: 250, pointerId: 43,
    });
    fireEvent.pointerMove(textarea, {
      button: 1, buttons: 4, clientX: 330, clientY: 290, pointerId: 43,
    });
    flushAnimationFrame();
    fireEvent.pointerUp(textarea, {
      button: 1, buttons: 0, clientX: 330, clientY: 290, pointerId: 43,
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

    fireEvent.pointerDown(stage, { button: 1, buttons: 4, pointerId: 44 });
    fireEvent.pointerMove(stage, { button: 1, buttons: 4, clientX: 40, clientY: 50, pointerId: 44 });

    expect(onViewportPanBy).not.toHaveBeenCalled();
  });

  it.each(["pointercancel", "blur"] as const)(
    "ends middle-button pan exactly once on %s and permits the next gesture",
    (terminal) => {
      const onViewportPanBy = vi.fn();
      const onInteractionActiveChange = vi.fn();
      renderCreationCanvas("rectangle", { onViewportPanBy, onInteractionActiveChange });
      installCanvasShellPointerCapture();
      const stage = screen.getByTestId("stage");

      fireEvent.pointerDown(stage, { button: 1, buttons: 4, clientX: 10, clientY: 20, pointerId: 51 });
      fireEvent.pointerMove(stage, { button: 1, buttons: 4, clientX: 30, clientY: 45, pointerId: 51 });
      flushAnimationFrame();
      if (terminal === "pointercancel") {
        fireEvent.pointerCancel(stage, { pointerId: 51 });
        fireEvent.pointerCancel(stage, { pointerId: 51 });
      } else {
        window.dispatchEvent(new Event("blur"));
        window.dispatchEvent(new Event("blur"));
      }
      fireEvent.pointerMove(stage, { button: 1, buttons: 4, clientX: 80, clientY: 90, pointerId: 51 });
      fireEvent.pointerUp(stage, { button: 1, buttons: 0, clientX: 80, clientY: 90, pointerId: 51 });

      expect(onViewportPanBy).toHaveBeenCalledTimes(1);
      expect(onInteractionActiveChange.mock.calls.map(([active]) => active)).toEqual([true, false]);

      fireEvent.pointerDown(stage, { button: 1, buttons: 4, clientX: 100, clientY: 110, pointerId: 52 });
      fireEvent.pointerMove(stage, { button: 1, buttons: 4, clientX: 120, clientY: 140, pointerId: 52 });
      flushAnimationFrame();
      fireEvent.pointerUp(stage, { button: 1, buttons: 0, clientX: 120, clientY: 140, pointerId: 52 });

      expect(onViewportPanBy).toHaveBeenLastCalledWith({ x: 20, y: 30 });
      expect(onInteractionActiveChange.mock.calls.map(([active]) => active)).toEqual([true, false, true, false]);
    },
  );

  it("does not let a late middle press convert an active left-button creation", () => {
    const onCommand = vi.fn();
    const onViewportPanBy = vi.fn();
    renderCreationCanvas("rectangle", { onCommand, onViewportPanBy });
    installCanvasShellPointerCapture();
    const stage = screen.getByTestId("stage");

    fireEvent.pointerDown(stage, { button: 0, buttons: 1, clientX: 10, clientY: 20, pointerId: 61 });
    fireEvent.pointerDown(stage, { button: 1, buttons: 5, clientX: 15, clientY: 25, pointerId: 62 });
    fireEvent.pointerMove(stage, { button: 0, buttons: 1, clientX: 50, clientY: 60, pointerId: 61 });
    fireEvent.pointerUp(stage, { button: 0, buttons: 0, clientX: 50, clientY: 60, pointerId: 61 });

    expect(onCommand).toHaveBeenCalledOnce();
    expect(onCommand).toHaveBeenCalledWith({
      type: "create",
      element: expect.objectContaining({ type: "rectangle", x: 10, y: 20, width: 40, height: 40 }),
    });
    expect(onViewportPanBy).not.toHaveBeenCalled();
  });

  it("keeps right-button input inert and ordinary left creation unchanged", () => {
    const onCommand = vi.fn();
    renderCreationCanvas("rectangle", { onCommand });
    installCanvasShellPointerCapture();
    const stage = screen.getByTestId("stage");

    fireEvent.pointerDown(stage, { button: 2, buttons: 2, clientX: 10, clientY: 20, pointerId: 63 });
    fireEvent.pointerMove(stage, { button: 2, buttons: 2, clientX: 40, clientY: 50, pointerId: 63 });
    fireEvent.pointerUp(stage, { button: 2, buttons: 0, clientX: 40, clientY: 50, pointerId: 63 });
    expect(onCommand).not.toHaveBeenCalled();

    fireEvent.pointerDown(stage, { button: 0, buttons: 1, clientX: 10, clientY: 20, pointerId: 64 });
    fireEvent.pointerUp(stage, { button: 0, buttons: 0, clientX: 40, clientY: 50, pointerId: 64 });
    expect(onCommand).toHaveBeenCalledOnce();
  });

  it("prevents compatibility mousedown and auxclick for the middle button", () => {
    const onCommand = vi.fn();
    renderCreationCanvas("rectangle", { onCommand });
    installCanvasShellPointerCapture();
    const stage = screen.getByTestId("stage");
    const mouseDown = new MouseEvent("mousedown", { bubbles: true, button: 1, cancelable: true });
    const auxClick = new MouseEvent("auxclick", { bubbles: true, button: 1, cancelable: true });

    fireEvent(stage, mouseDown);
    fireEvent(stage, auxClick);

    expect(mouseDown.defaultPrevented).toBe(true);
    expect(auxClick.defaultPrevented).toBe(true);
    expect(onCommand).not.toHaveBeenCalled();
  });

  it("releases middle-pointer capture and drops a queued frame on unmount", () => {
    const onCommand = vi.fn();
    const onViewportPanBy = vi.fn();
    const view = renderCreationCanvas("rectangle", { onCommand, onViewportPanBy });
    const { releasePointerCapture } = installCanvasShellPointerCapture();
    const stage = screen.getByTestId("stage");

    fireEvent.pointerDown(stage, { button: 1, buttons: 4, clientX: 10, clientY: 20, pointerId: 65 });
    fireEvent.pointerMove(stage, { button: 1, buttons: 4, clientX: 40, clientY: 55, pointerId: 65 });
    const queuedFrame = animationFrames.values().next().value as FrameRequestCallback | undefined;
    if (!queuedFrame) throw new Error("Expected one queued animation frame");

    view.unmount();
    act(() => queuedFrame(0));

    expect(cancelAnimationFrame).toHaveBeenCalledOnce();
    expect(releasePointerCapture).toHaveBeenCalledWith(65);
    expect(onCommand).not.toHaveBeenCalled();
    expect(onViewportPanBy).not.toHaveBeenCalled();
  });

  it("ends Space-pan exactly once on window blur so shortcuts and the next pan recover", () => {
    const onViewportPanBy = vi.fn();
    const onInteractionActiveChange = vi.fn();
    let interactionActive = false;
    onInteractionActiveChange.mockImplementation((active: boolean) => {
      interactionActive = active;
    });
    render(
      <EditorCanvas
        document={fixtureDocument({ elements: [] })}
        sourceImageURL="data:image/png;base64,iVBORw0KGgo="
        tool="rectangle"
        {...VIEWPORT_PROPS}
        spacePanReady
        onViewportPanBy={onViewportPanBy}
        onInteractionActiveChange={onInteractionActiveChange}
        selectedIds={[]}
        onSelect={() => {}}
        onEditText={() => {}}
        onCommand={() => {}}
        onBeginTransaction={() => {}}
        onCommitTransaction={() => {}}
        onCancelTransaction={() => {}}
        textEditorOverlay={undefined}
      />,
    );
    const stage = screen.getByTestId("stage");

    fireEvent.pointerDown(stage, { clientX: 10, clientY: 20, pointerId: 1 });
    fireEvent.pointerMove(stage, { clientX: 30, clientY: 45, pointerId: 1 });
    flushAnimationFrame();
    window.dispatchEvent(new Event("blur"));
    window.dispatchEvent(new Event("blur"));
    fireEvent.pointerMove(stage, { clientX: 80, clientY: 90, pointerId: 1 });

    expect(onViewportPanBy).toHaveBeenCalledTimes(1);
    expect(onInteractionActiveChange.mock.calls.map(([active]) => active))
      .toEqual([true, false]);
    expect(keyboardCommandFor(new KeyboardEvent("keydown", { code: "KeyR", key: "r" }), {
      interactionActive,
      shortcutHelpOpen: false,
      textEditing: false,
    })).toEqual({ type: "selectTool", tool: "rectangle" });

    fireEvent.pointerDown(stage, { clientX: 100, clientY: 110, pointerId: 2 });
    fireEvent.pointerMove(stage, { clientX: 120, clientY: 140, pointerId: 2 });
    flushAnimationFrame();
    fireEvent.pointerUp(stage, { clientX: 120, clientY: 140, pointerId: 2 });
    expect(onViewportPanBy).toHaveBeenLastCalledWith({ x: 20, y: 30 });
    expect(onInteractionActiveChange.mock.calls.map(([active]) => active))
      .toEqual([true, false, true, false]);
  });

  it("shows grab while Space is ready and grabbing only during its pan", () => {
    render(
      <EditorCanvas
        document={fixtureDocument()}
        sourceImageURL="data:image/png;base64,iVBORw0KGgo="
        tool="selection"
        {...VIEWPORT_PROPS}
        spacePanReady
        selectedIds={[]}
        onSelect={() => {}}
        onEditText={() => {}}
        onCommand={() => {}}
        onBeginTransaction={() => {}}
        onCommitTransaction={() => {}}
        onCancelTransaction={() => {}}
        textEditorOverlay={undefined}
      />,
    );
    const canvas = screen.getByTestId("editor-canvas");
    const stage = screen.getByTestId("stage");

    expect(canvas.style.cursor).toBe("grab");
    fireEvent.pointerDown(stage, { clientX: 10, clientY: 20, pointerId: 1 });
    expect(canvas.style.cursor).toBe("grabbing");
    fireEvent.pointerUp(stage, { clientX: 10, clientY: 20, pointerId: 1 });
    expect(canvas.style.cursor).toBe("grab");
  });

  it("does not convert an in-progress annotation drag when Space is pressed late", () => {
    const initial = fixtureDocument({ elements: [] });
    const history = createHistoryStore(initial);
    const onViewportPanBy = vi.fn();
    const canvas = (spacePanReady: boolean) => (
      <EditorCanvas
        document={initial}
        sourceImageURL="data:image/png;base64,iVBORw0KGgo="
        tool="rectangle"
        {...VIEWPORT_PROPS}
        spacePanReady={spacePanReady}
        onViewportPanBy={onViewportPanBy}
        selectedIds={[]}
        onSelect={() => {}}
        onEditText={() => {}}
        onCommand={(command) => history.dispatch(command)}
        onBeginTransaction={(label) => history.beginTransaction(label)}
        onCommitTransaction={() => history.commitTransaction()}
        onCancelTransaction={() => history.cancelTransaction()}
        textEditorOverlay={undefined}
      />
    );
    const view = render(canvas(false));
    const stage = screen.getByTestId("stage");

    fireEvent.pointerDown(stage, { clientX: 10, clientY: 20, pointerId: 1 });
    view.rerender(canvas(true));
    fireEvent.pointerMove(stage, { clientX: 40, clientY: 55, pointerId: 1 });
    fireEvent.pointerUp(stage, { clientX: 40, clientY: 55, pointerId: 1 });

    expect(onViewportPanBy).not.toHaveBeenCalled();
    expect(history.document.elements).toEqual([
      expect.objectContaining({ x: 10, y: 20, width: 30, height: 35 }),
    ]);
  });

  it("does not route Shift-drag into viewport pan", () => {
    const onViewportPanBy = vi.fn();
    render(
      <EditorCanvas
        document={fixtureDocument()}
        sourceImageURL="data:image/png;base64,iVBORw0KGgo="
        tool="selection"
        {...VIEWPORT_PROPS}
        onViewportPanBy={onViewportPanBy}
        selectedIds={[]}
        onSelect={() => {}}
        onEditText={() => {}}
        onCommand={() => {}}
        onBeginTransaction={() => {}}
        onCommitTransaction={() => {}}
        onCancelTransaction={() => {}}
        textEditorOverlay={undefined}
      />,
    );
    const stage = screen.getByTestId("stage");

    fireEvent.pointerDown(stage, { clientX: 10, clientY: 20, shiftKey: true, pointerId: 1 });
    fireEvent.pointerMove(stage, { clientX: 40, clientY: 55, shiftKey: true, pointerId: 1 });

    expect(onViewportPanBy).not.toHaveBeenCalled();
  });

  it.each([
    "rectangle",
    "arrow",
    "line",
    "freehand",
    "highlighter",
    "blur",
    "redaction",
  ] as const)("previews %s without changing the document", (tool) => {
    const onCommand = vi.fn();
    renderCreationCanvas(tool, { onCommand });
    const stage = screen.getByTestId("stage");

    fireEvent.pointerDown(stage, { clientX: 20, clientY: 30, pointerId: 1 });
    fireEvent.pointerMove(stage, { clientX: 80, clientY: 70, pointerId: 1 });
    fireEvent.pointerMove(stage, { clientX: 120, clientY: 90, pointerId: 1 });

    expect(requestAnimationFrame).toHaveBeenCalledOnce();
    expect(screen.queryByTestId("creation-preview")).toBeNull();
    expect(onCommand).not.toHaveBeenCalled();
    flushAnimationFrame();
    expect(screen.getByTestId("creation-preview")).toBeTruthy();
    expect(onCommand).not.toHaveBeenCalled();

    fireEvent.pointerUp(stage, { clientX: 120, clientY: 90, pointerId: 1 });
    expect(onCommand).toHaveBeenCalledOnce();
    expect(onCommand).toHaveBeenCalledWith({
      type: "create",
      element: expect.objectContaining({ type: tool }),
    });
  });

  it("previews and commits a number marker from a click", () => {
    const onCommand = vi.fn();
    renderCreationCanvas("numberMarker", { onCommand });
    const stage = screen.getByTestId("stage");

    fireEvent.pointerDown(stage, { clientX: 25, clientY: 35, pointerId: 3 });
    expect(screen.getByTestId("creation-preview")).toBeTruthy();
    expect(onCommand).not.toHaveBeenCalled();
    fireEvent.pointerUp(stage, { clientX: 25, clientY: 35, pointerId: 3 });

    expect(onCommand).toHaveBeenCalledWith({
      type: "create",
      element: expect.objectContaining({ type: "numberMarker", x: 25, y: 35 }),
    });
  });

  it("emits beginNewText without previewing or committing a placeholder element", () => {
    const onCommand = vi.fn();
    const onBeginNewText = vi.fn();
    renderCreationCanvas("text", { onCommand, onBeginNewText });
    const stage = screen.getByTestId("stage");

    fireEvent.pointerDown(stage, { clientX: 20, clientY: 30, pointerId: 4 });
    fireEvent.pointerMove(stage, { clientX: 100, clientY: 110, pointerId: 4 });
    flushAnimationFrame();
    expect(screen.queryByTestId("creation-preview")).toBeNull();
    fireEvent.pointerUp(stage, { clientX: 100, clientY: 110, pointerId: 4 });

    expect(onCommand).not.toHaveBeenCalled();
    expect(onBeginNewText).toHaveBeenCalledWith({ x: 20, y: 30 }, fixtureDocument().defaults);
  });

  it("keeps placeholder Text creation out of the exported canvas factory", () => {
    if (false) {
      // @ts-expect-error Canvas creation must route Text through beginNewText.
      createCanvasElement(fixtureDocument(), "text", {
        kind: "point",
        point: { x: 20, y: 30 },
      });
    }
  });

  it("commits the source-space Shift preview with the pointer-down tool and defaults", () => {
    const onCommand = vi.fn();
    const initial = fixtureDocument({
      elements: [],
      defaults: { ...fixtureDocument().defaults, rectangleFillColor: "#FADB14" },
    });
    const canvas = (tool: EditorTool, document = initial) => (
      <EditorCanvas
        document={document}
        sourceImageURL="data:image/png;base64,iVBORw0KGgo="
        tool={tool}
        {...VIEWPORT_PROPS}
        selectedIds={[]}
        onSelect={() => {}}
        onEditText={() => {}}
        onCommand={onCommand}
        onBeginTransaction={() => {}}
        onCommitTransaction={() => {}}
        onCancelTransaction={() => {}}
        textEditorOverlay={undefined}
      />
    );
    const view = render(canvas("rectangle"));
    const stage = screen.getByTestId("stage");

    fireEvent.pointerDown(stage, { clientX: 10, clientY: 10, pointerId: 7 });
    fireEvent.pointerMove(stage, { clientX: 50, clientY: 30, pointerId: 7, shiftKey: true });
    flushAnimationFrame();
    view.rerender(canvas("arrow", fixtureDocument({
      elements: [],
      defaults: { ...fixtureDocument().defaults, rectangleFillColor: null },
    })));
    fireEvent.pointerUp(stage, { clientX: 50, clientY: 30, pointerId: 7, shiftKey: true });

    expect(onCommand).toHaveBeenCalledWith({
      type: "create",
      element: expect.objectContaining({
        type: "rectangle",
        fillColor: "#FADB14",
        width: 40,
        height: 40,
      }),
    });
  });

  it("applies Shift constraints after converting workspace points to source space", () => {
    const onCommand = vi.fn();
    render(
      <EditorCanvas
        document={fixtureDocument({ elements: [] })}
        sourceImageURL="data:image/png;base64,iVBORw0KGgo="
        tool="rectangle"
        {...VIEWPORT_PROPS}
        toSourcePoint={(point) => ({
          x: (point.x - 100) / 2,
          y: (point.y - 50) / 2,
        })}
        selectedIds={[]}
        onSelect={() => {}}
        onEditText={() => {}}
        onCommand={onCommand}
        onBeginTransaction={() => {}}
        onCommitTransaction={() => {}}
        onCancelTransaction={() => {}}
        textEditorOverlay={undefined}
      />,
    );
    const stage = screen.getByTestId("stage");

    fireEvent.pointerDown(stage, { clientX: 120, clientY: 70, pointerId: 1 });
    fireEvent.pointerMove(stage, { clientX: 200, clientY: 110, pointerId: 1, shiftKey: true });
    flushAnimationFrame();
    fireEvent.pointerUp(stage, { clientX: 200, clientY: 110, pointerId: 1, shiftKey: true });

    expect(onCommand).toHaveBeenCalledWith({
      type: "create",
      element: expect.objectContaining({
        x: 10,
        y: 10,
        width: 40,
        height: 40,
      }),
    });
  });

  it("ignores wrong pointer ids and repeated terminals while capture owns the gesture", () => {
    const onCommand = vi.fn();
    const onInteractionActiveChange = vi.fn();
    renderCreationCanvas("rectangle", { onCommand, onInteractionActiveChange });
    const stage = screen.getByTestId("stage");

    fireEvent.pointerDown(stage, { clientX: 10, clientY: 10, pointerId: 7 });
    fireEvent.pointerMove(stage, { clientX: 40, clientY: 50, pointerId: 8 });
    fireEvent.pointerUp(stage, { clientX: 40, clientY: 50, pointerId: 8 });
    expect(onCommand).not.toHaveBeenCalled();
    expect(onInteractionActiveChange).toHaveBeenCalledTimes(1);
    expect(konvaControl.releasePointerCapture).not.toHaveBeenCalled();

    fireEvent.pointerUp(stage, { clientX: 40, clientY: 50, pointerId: 7 });
    fireEvent.pointerUp(stage, { clientX: 80, clientY: 90, pointerId: 7 });
    fireEvent.pointerCancel(stage, { pointerId: 7 });

    expect(konvaControl.setPointerCapture).toHaveBeenCalledWith(7);
    expect(konvaControl.releasePointerCapture).toHaveBeenCalledOnce();
    expect(onCommand).toHaveBeenCalledOnce();
    expect(onInteractionActiveChange.mock.calls.map(([active]) => active)).toEqual([true, false]);
  });

  it("captures main Stage creation gestures on the Konva event content", () => {
    const onCommand = vi.fn();
    renderCreationCanvas("rectangle", { onCommand });
    const stage = screen.getByTestId("stage");

    fireEvent.pointerDown(stage, { clientX: 10, clientY: 20, pointerId: 7 });

    expect(konvaControl.contentSetPointerCapture).toHaveBeenCalledWith(7);
    expect(konvaControl.outerSetPointerCapture).not.toHaveBeenCalled();

    fireEvent.pointerUp(stage, { clientX: 40, clientY: 50, pointerId: 7 });

    expect(konvaControl.contentReleasePointerCapture).toHaveBeenCalledWith(7);
    expect(konvaControl.outerReleasePointerCapture).not.toHaveBeenCalled();
    expect(onCommand).toHaveBeenCalledOnce();
  });

  it("does not treat window mouseup as a competing terminal", () => {
    const onCommand = vi.fn();
    const onInteractionActiveChange = vi.fn();
    renderCreationCanvas("rectangle", { onCommand, onInteractionActiveChange });
    const stage = screen.getByTestId("stage");

    fireEvent.pointerDown(stage, { clientX: 10, clientY: 10, pointerId: 9 });
    fireEvent(window, new MouseEvent("mouseup"));
    expect(onInteractionActiveChange.mock.calls.map(([active]) => active)).toEqual([true]);
    fireEvent.pointerUp(stage, { clientX: 30, clientY: 40, pointerId: 9 });

    expect(onCommand).toHaveBeenCalledOnce();
    expect(onInteractionActiveChange.mock.calls.map(([active]) => active)).toEqual([true, false]);
  });

  it.each([
    ["creation", false],
    ["Space-pan", true],
  ] as const)("cancels an active %s through the handle and makes late terminals inert", (_label, spacePanReady) => {
    const handle = createRef<EditorCanvasHandle>();
    const onCommand = vi.fn();
    const onViewportPanBy = vi.fn();
    const onInteractionActiveChange = vi.fn();
    renderCreationCanvas("rectangle", {
      ref: handle,
      spacePanReady,
      onCommand,
      onViewportPanBy,
      onInteractionActiveChange,
    });
    const stage = screen.getByTestId("stage");

    fireEvent.pointerDown(stage, { clientX: 10, clientY: 20, pointerId: 7 });
    fireEvent.pointerMove(stage, { clientX: 50, clientY: 60, pointerId: 7 });
    act(() => {
      expect(handle.current?.cancelInteraction()).toBe(true);
      expect(handle.current?.cancelInteraction()).toBe(false);
    });
    flushAnimationFrame();
    fireEvent.pointerUp(stage, { clientX: 50, clientY: 60, pointerId: 7 });
    fireEvent.pointerCancel(stage, { pointerId: 7 });

    expect(onCommand).not.toHaveBeenCalled();
    expect(onViewportPanBy).not.toHaveBeenCalled();
    expect(cancelAnimationFrame).toHaveBeenCalledOnce();
    expect(konvaControl.releasePointerCapture).toHaveBeenCalledOnce();
    expect(onInteractionActiveChange.mock.calls.map(([active]) => active)).toEqual([true, false]);
  });

  it.each([
    ["creation", false],
    ["Space-pan", true],
  ] as const)("disposes a queued %s frame and capture without late callbacks on unmount", (_label, spacePanReady) => {
    const onCommand = vi.fn();
    const onViewportPanBy = vi.fn();
    const onInteractionActiveChange = vi.fn();
    const view = renderCreationCanvas("rectangle", {
      spacePanReady,
      onCommand,
      onViewportPanBy,
      onInteractionActiveChange,
    });
    const stage = screen.getByTestId("stage");

    fireEvent.pointerDown(stage, { clientX: 10, clientY: 20, pointerId: 9 });
    fireEvent.pointerMove(stage, { clientX: 40, clientY: 55, pointerId: 9 });
    const queuedFrame = animationFrames.values().next().value;
    if (!queuedFrame) throw new Error("Expected one queued animation frame");

    view.unmount();
    act(() => queuedFrame(0));

    expect(cancelAnimationFrame).toHaveBeenCalledOnce();
    expect(konvaControl.releasePointerCapture).toHaveBeenCalledOnce();
    expect(onCommand).not.toHaveBeenCalled();
    expect(onViewportPanBy).not.toHaveBeenCalled();
    expect(onInteractionActiveChange.mock.calls.map(([active]) => active)).toEqual([true]);
  });

  it("cancels and restores an active annotation move exactly once on unmount", () => {
    const initial = fixtureDocument();
    const history = createHistoryStore(initial);
    const onCommand = vi.fn((command) => history.dispatch(command));
    const onCommitTransaction = vi.fn(() => history.commitTransaction());
    const onCancelTransaction = vi.fn(() => history.cancelTransaction());
    const view = render(
      <EditorCanvas
        document={initial}
        sourceImageURL="data:image/png;base64,iVBORw0KGgo="
        tool="selection"
        {...VIEWPORT_PROPS}
        selectedIds={["rect-1"]}
        onSelect={() => {}}
        onEditText={() => {}}
        onCommand={onCommand}
        onBeginTransaction={(label) => history.beginTransaction(label)}
        onCommitTransaction={onCommitTransaction}
        onCancelTransaction={onCancelTransaction}
        textEditorOverlay={undefined}
      />,
    );
    const annotation = screen.getByTestId("annotation-node");

    konvaControl.annotationStartPointerId = 7;
    fireEvent.pointerDown(annotation, { pointerId: 7 });
    fireEvent.dragStart(annotation);
    Object.assign(konvaControl.annotationValues, {
      x: 40,
      y: 50,
      scaleX: 0.5,
      scaleY: 1.25,
      rotation: 15,
    });
    expect(history.isTransactionActive).toBe(true);
    expect(konvaControl.capturedPointers).toEqual(new Set([7]));

    view.unmount();
    fireEvent.dragEnd(annotation);
    fireEvent(window, new Event("blur"));

    expect(history.isTransactionActive).toBe(false);
    expect(history.document.elements).toEqual(initial.elements);
    expect(konvaControl.stopDrag).toHaveBeenCalledOnce();
    expect(konvaControl.annotationValues).toMatchObject({
      x: initial.elements[0].x,
      y: initial.elements[0].y,
      scaleX: 1,
      scaleY: 1,
      rotation: initial.elements[0].rotation,
    });
    expect(konvaControl.draw).toHaveBeenCalledOnce();
    expect(konvaControl.forceUpdate).toHaveBeenCalledOnce();
    expect(konvaControl.releasePointerCapture).toHaveBeenCalledOnce();
    expect(konvaControl.releasePointerCapture).toHaveBeenCalledWith(7);
    expect(konvaControl.capturedPointers).toEqual(new Set());
    expect(onCancelTransaction).toHaveBeenCalledOnce();
    expect(onCommitTransaction).not.toHaveBeenCalled();
    expect(onCommand).not.toHaveBeenCalled();
  });

  it("cancels and restores an active annotation transform exactly once on unmount", () => {
    const initial = fixtureDocument();
    const history = createHistoryStore(initial);
    const onCommand = vi.fn((command) => history.dispatch(command));
    const onCommitTransaction = vi.fn(() => history.commitTransaction());
    const onCancelTransaction = vi.fn(() => history.cancelTransaction());
    const view = render(
      <EditorCanvas
        document={initial}
        sourceImageURL="data:image/png;base64,iVBORw0KGgo="
        tool="selection"
        {...VIEWPORT_PROPS}
        selectedIds={["rect-1"]}
        onSelect={() => {}}
        onEditText={() => {}}
        onCommand={onCommand}
        onBeginTransaction={(label) => history.beginTransaction(label)}
        onCommitTransaction={onCommitTransaction}
        onCancelTransaction={onCancelTransaction}
        textEditorOverlay={undefined}
      />,
    );
    const annotation = screen.getByTestId("annotation-node");

    konvaControl.annotationStartPointerId = 11;
    fireEvent.pointerDown(screen.getByTestId("transformer"), { pointerId: 11 });
    fireEvent.doubleClick(annotation);
    expect(history.isTransactionActive).toBe(true);
    expect(konvaControl.capturedPointers).toEqual(new Set([11]));

    view.unmount();
    fireEvent.contextMenu(annotation);
    fireEvent(window, new Event("blur"));

    expect(history.isTransactionActive).toBe(false);
    expect(history.document.elements).toEqual(initial.elements);
    expect(konvaControl.stopTransform).toHaveBeenCalledOnce();
    expect(konvaControl.annotationValues).toMatchObject({
      x: initial.elements[0].x,
      y: initial.elements[0].y,
      scaleX: 1,
      scaleY: 1,
      rotation: initial.elements[0].rotation,
    });
    expect(konvaControl.draw).toHaveBeenCalledOnce();
    expect(konvaControl.forceUpdate).toHaveBeenCalledOnce();
    expect(konvaControl.releasePointerCapture).toHaveBeenCalledOnce();
    expect(konvaControl.releasePointerCapture).toHaveBeenCalledWith(11);
    expect(konvaControl.capturedPointers).toEqual(new Set());
    expect(onCancelTransaction).toHaveBeenCalledOnce();
    expect(onCommitTransaction).not.toHaveBeenCalled();
    expect(onCommand).not.toHaveBeenCalled();
  });

  it("uses the pointerdown owner when drag lifecycle events are MouseEvent-like", () => {
    const initial = fixtureDocument();
    const history = createHistoryStore(initial);
    const onCommand = vi.fn((command) => history.dispatch(command));
    const onCommitTransaction = vi.fn(() => history.commitTransaction());
    const onCancelTransaction = vi.fn(() => history.cancelTransaction());
    render(
      <EditorCanvas
        document={initial}
        sourceImageURL="data:image/png;base64,iVBORw0KGgo="
        tool="selection"
        {...VIEWPORT_PROPS}
        selectedIds={["rect-1"]}
        onSelect={() => {}}
        onEditText={() => {}}
        onCommand={onCommand}
        onBeginTransaction={(label) => history.beginTransaction(label)}
        onCommitTransaction={onCommitTransaction}
        onCancelTransaction={onCancelTransaction}
        textEditorOverlay={undefined}
      />,
    );
    const annotation = screen.getByTestId("annotation-node");
    konvaControl.annotationLifecyclePointerId = undefined;

    fireEvent.pointerDown(annotation, { pointerId: 7 });
    expect(() => fireEvent.dragStart(annotation)).not.toThrow();
    expect(() => fireEvent.dragEnd(annotation)).not.toThrow();

    expect(history.isTransactionActive).toBe(false);
    expect(konvaControl.setPointerCapture).toHaveBeenCalledOnce();
    expect(konvaControl.setPointerCapture).toHaveBeenCalledWith(7);
    expect(konvaControl.releasePointerCapture).toHaveBeenCalledOnce();
    expect(konvaControl.releasePointerCapture).toHaveBeenCalledWith(7);
    expect(onCommitTransaction).not.toHaveBeenCalled();
    expect(onCancelTransaction).toHaveBeenCalledOnce();
    expect(onCommand).not.toHaveBeenCalled();
  });

  it("keeps the first pending annotation owner when another pointer goes down", () => {
    const initial = fixtureDocument();
    const history = createHistoryStore(initial);
    const onCancelTransaction = vi.fn(() => history.cancelTransaction());
    render(
      <EditorCanvas
        document={initial}
        sourceImageURL="data:image/png;base64,iVBORw0KGgo="
        tool="selection"
        {...VIEWPORT_PROPS}
        selectedIds={["rect-1"]}
        onSelect={() => {}}
        onEditText={() => {}}
        onCommand={(command) => history.dispatch(command)}
        onBeginTransaction={(label) => history.beginTransaction(label)}
        onCommitTransaction={() => history.commitTransaction()}
        onCancelTransaction={onCancelTransaction}
        textEditorOverlay={undefined}
      />,
    );
    const annotation = screen.getByTestId("annotation-node");
    const stage = screen.getByTestId("stage");
    konvaControl.annotationLifecyclePointerId = undefined;

    fireEvent.pointerDown(annotation, { pointerId: 7 });
    fireEvent.pointerDown(annotation, { pointerId: 8 });
    fireEvent.dragStart(annotation);

    expect(konvaControl.setPointerCapture).toHaveBeenCalledOnce();
    expect(konvaControl.setPointerCapture).toHaveBeenCalledWith(7);
    fireEvent.pointerCancel(stage, { pointerId: 8 });
    expect(history.isTransactionActive).toBe(true);
    expect(onCancelTransaction).not.toHaveBeenCalled();
    expect(konvaControl.releasePointerCapture).not.toHaveBeenCalled();

    fireEvent.pointerCancel(stage, { pointerId: 7 });
    expect(history.isTransactionActive).toBe(false);
    expect(onCancelTransaction).toHaveBeenCalledOnce();
    expect(konvaControl.releasePointerCapture).toHaveBeenCalledOnce();
    expect(konvaControl.releasePointerCapture).toHaveBeenCalledWith(7);
  });

  it("uses the Transformer pointerdown owner and ignores another pointer cancel", () => {
    const initial = fixtureDocument();
    const history = createHistoryStore(initial);
    const onCommand = vi.fn((command) => history.dispatch(command));
    const onCommitTransaction = vi.fn(() => history.commitTransaction());
    const onCancelTransaction = vi.fn(() => history.cancelTransaction());
    render(
      <EditorCanvas
        document={initial}
        sourceImageURL="data:image/png;base64,iVBORw0KGgo="
        tool="selection"
        {...VIEWPORT_PROPS}
        selectedIds={["rect-1"]}
        onSelect={() => {}}
        onEditText={() => {}}
        onCommand={onCommand}
        onBeginTransaction={(label) => history.beginTransaction(label)}
        onCommitTransaction={onCommitTransaction}
        onCancelTransaction={onCancelTransaction}
        textEditorOverlay={undefined}
      />,
    );
    const annotation = screen.getByTestId("annotation-node");
    const stage = screen.getByTestId("stage");
    konvaControl.annotationLifecyclePointerId = undefined;

    fireEvent.pointerDown(screen.getByTestId("transformer"), { pointerId: 11 });
    expect(() => fireEvent.doubleClick(annotation)).not.toThrow();
    fireEvent.pointerCancel(stage, { pointerId: 12 });

    expect(history.isTransactionActive).toBe(true);
    expect(konvaControl.setPointerCapture).toHaveBeenCalledWith(11);
    expect(konvaControl.releasePointerCapture).not.toHaveBeenCalled();
    expect(onCancelTransaction).not.toHaveBeenCalled();

    fireEvent.pointerCancel(stage, { pointerId: 11 });

    expect(history.isTransactionActive).toBe(false);
    expect(konvaControl.releasePointerCapture).toHaveBeenCalledOnce();
    expect(konvaControl.releasePointerCapture).toHaveBeenCalledWith(11);
    expect(onCancelTransaction).toHaveBeenCalledOnce();
    expect(onCommitTransaction).not.toHaveBeenCalled();
    expect(onCommand).not.toHaveBeenCalled();
  });

  it("routes a Selection-tool Text double-click into one existing edit without a document command", () => {
    const document = fixtureDocument({ elements: [fixtureText()] });
    const onEditText = vi.fn();
    const onCommand = vi.fn();
    const onBeginTransaction = vi.fn();
    const onCommitTransaction = vi.fn();
    const onCancelTransaction = vi.fn();
    render(
      <EditorCanvas
        document={document}
        sourceImageURL="data:image/png;base64,iVBORw0KGgo="
        tool="selection"
        {...VIEWPORT_PROPS}
        selectedIds={["text-1"]}
        onSelect={() => {}}
        onEditText={onEditText}
        onCommand={onCommand}
        onBeginTransaction={onBeginTransaction}
        onCommitTransaction={onCommitTransaction}
        onCancelTransaction={onCancelTransaction}
        textEditorOverlay={undefined}
      />,
    );

    fireEvent.doubleClick(screen.getByTestId("element-text-1"));

    expect(onEditText).toHaveBeenCalledOnce();
    expect(onEditText).toHaveBeenCalledWith("text-1");
    expect(onCommand).not.toHaveBeenCalled();
    expect(onBeginTransaction).not.toHaveBeenCalled();
    expect(onCommitTransaction).not.toHaveBeenCalled();
    expect(onCancelTransaction).not.toHaveBeenCalled();
  });

  it.each([
    { label: "the selection is empty", selectedIds: [] },
    { label: "a different element is selected", selectedIds: ["rect-1"] },
    { label: "multiple elements are selected", selectedIds: ["rect-1", "text-1"] },
  ] as const)(
    "keeps a Text double-click inert when $label",
    ({ selectedIds }) => {
      const document = fixtureDocument({ elements: [fixtureRect(), fixtureText()] });
      const onEditText = vi.fn();
      const onCommand = vi.fn();
      const onBeginTransaction = vi.fn();
      const onCommitTransaction = vi.fn();
      const onCancelTransaction = vi.fn();
      render(
        <EditorCanvas
          document={document}
          sourceImageURL="data:image/png;base64,iVBORw0KGgo="
          tool="selection"
          {...VIEWPORT_PROPS}
          selectedIds={selectedIds}
          onSelect={() => {}}
          onEditText={onEditText}
          onCommand={onCommand}
          onBeginTransaction={onBeginTransaction}
          onCommitTransaction={onCommitTransaction}
          onCancelTransaction={onCancelTransaction}
          textEditorOverlay={undefined}
        />,
      );

      fireEvent.doubleClick(screen.getByTestId("element-text-1"));

      expect(onEditText).not.toHaveBeenCalled();
      expect(onCommand).not.toHaveBeenCalled();
      expect(onBeginTransaction).not.toHaveBeenCalled();
      expect(onCommitTransaction).not.toHaveBeenCalled();
      expect(onCancelTransaction).not.toHaveBeenCalled();
    },
  );

  it("blocks an existing Text double-click while canvas interaction is locked", () => {
    const document = fixtureDocument({ elements: [fixtureText()] });
    const onEditText = vi.fn();
    const onCommand = vi.fn();
    const onBeginTransaction = vi.fn();
    const onCommitTransaction = vi.fn();
    const onCancelTransaction = vi.fn();
    render(
      <EditorCanvas
        document={document}
        sourceImageURL="data:image/png;base64,iVBORw0KGgo="
        tool="selection"
        {...VIEWPORT_PROPS}
        interactionLocked
        selectedIds={["text-1"]}
        onSelect={() => {}}
        onEditText={onEditText}
        onCommand={onCommand}
        onBeginTransaction={onBeginTransaction}
        onCommitTransaction={onCommitTransaction}
        onCancelTransaction={onCancelTransaction}
        textEditorOverlay={undefined}
      />,
    );

    fireEvent.doubleClick(screen.getByTestId("element-text-1"));

    expect(onEditText).not.toHaveBeenCalled();
    expect(onCommand).not.toHaveBeenCalled();
    expect(onBeginTransaction).not.toHaveBeenCalled();
    expect(onCommitTransaction).not.toHaveBeenCalled();
    expect(onCancelTransaction).not.toHaveBeenCalled();
  });

  it("blocks ordinary element selection clicks while canvas interaction is locked", () => {
    const document = fixtureDocument({ elements: [fixtureRect()] });
    const onSelect = vi.fn();
    render(
      <EditorCanvas
        document={document}
        sourceImageURL="data:image/png;base64,iVBORw0KGgo="
        tool="selection"
        {...VIEWPORT_PROPS}
        interactionLocked
        selectedIds={[]}
        onSelect={onSelect}
        onEditText={() => {}}
        onCommand={() => {}}
        onBeginTransaction={() => {}}
        onCommitTransaction={() => {}}
        onCancelTransaction={() => {}}
        textEditorOverlay={undefined}
      />,
    );

    fireEvent.click(screen.getByTestId("annotation-node"));

    expect(onSelect).not.toHaveBeenCalled();
  });

  it("blocks a new Text pointer entry while canvas interaction is locked", () => {
    const onBeginNewText = vi.fn();
    const onCommand = vi.fn();
    const onBeginTransaction = vi.fn();
    const onCommitTransaction = vi.fn();
    const onCancelTransaction = vi.fn();
    renderCreationCanvas("text", {
      interactionLocked: true,
      onBeginNewText,
      onCommand,
      onBeginTransaction,
      onCommitTransaction,
      onCancelTransaction,
    });
    const stage = screen.getByTestId("stage");

    fireEvent.pointerDown(stage, { clientX: 20, clientY: 30, pointerId: 4 });
    fireEvent.pointerMove(stage, { clientX: 100, clientY: 110, pointerId: 4 });
    flushAnimationFrame();
    fireEvent.pointerUp(stage, { clientX: 100, clientY: 110, pointerId: 4 });

    expect(onBeginNewText).not.toHaveBeenCalled();
    expect(onCommand).not.toHaveBeenCalled();
    expect(onBeginTransaction).not.toHaveBeenCalled();
    expect(onCommitTransaction).not.toHaveBeenCalled();
    expect(onCancelTransaction).not.toHaveBeenCalled();
  });

  it("does not begin text editing from a non-selection tool", () => {
    const document = fixtureDocument({ elements: [fixtureText()] });
    const history = createHistoryStore(document);
    const onEditText = vi.fn();
    render(
      <EditorCanvas
        document={document}
        sourceImageURL="data:image/png;base64,iVBORw0KGgo="
        tool="rectangle"
        {...VIEWPORT_PROPS}
        selectedIds={["text-1"]}
        onSelect={() => {}}
        onEditText={onEditText}
        onCommand={(command) => history.dispatch(command)}
        onBeginTransaction={(label) => history.beginTransaction(label)}
        onCommitTransaction={() => history.commitTransaction()}
        onCancelTransaction={() => history.cancelTransaction()}
        textEditorOverlay={undefined}
      />,
    );

    fireEvent.doubleClick(screen.getByTestId("element-text-1"));

    expect(onEditText).not.toHaveBeenCalled();
    expect(history.undo()).toBe(false);
    expect(history.document.elements).toEqual(document.elements);
  });

  it.each(["pointercancel", "blur"] as const)(
    "clears an abandoned creation on %s so create undo and redo remain usable",
    (terminalEvent) => {
      const initial = fixtureDocument({ elements: [] });
      const history = createHistoryStore(initial);
      const onCommand = vi.fn((command) => history.dispatch(command));
      const onInteractionActiveChange = vi.fn();
      render(
        <EditorCanvas
          document={initial}
          sourceImageURL="data:image/png;base64,iVBORw0KGgo="
          tool="rectangle"
          {...VIEWPORT_PROPS}
          selectedIds={[]}
          onSelect={() => {}}
          onEditText={() => {}}
          onCommand={onCommand}
          onBeginTransaction={(label) => history.beginTransaction(label)}
          onCommitTransaction={() => history.commitTransaction()}
          onCancelTransaction={() => history.cancelTransaction()}
          onInteractionActiveChange={onInteractionActiveChange}
          textEditorOverlay={undefined}
        />,
      );
      const stage = screen.getByTestId("stage");

      fireEvent.pointerDown(stage, { clientX: 10, clientY: 10, pointerId: 1 });
      fireEvent.pointerMove(stage, { clientX: 30, clientY: 30, pointerId: 1 });
      if (terminalEvent === "pointercancel") {
        fireEvent.pointerCancel(stage, { pointerId: 1 });
        fireEvent.pointerCancel(stage, { pointerId: 1 });
      } else {
        fireEvent(window, new Event("blur"));
        fireEvent(window, new Event("blur"));
      }
      expect(onInteractionActiveChange.mock.calls.map(([active]) => active))
        .toEqual([true, false]);
      expect(cancelAnimationFrame).toHaveBeenCalledOnce();
      expect(onCommand).not.toHaveBeenCalled();
      expect(() => fireEvent.pointerDown(stage, { clientX: 20, clientY: 20, pointerId: 2 })).not.toThrow();
      fireEvent.pointerUp(stage, { clientX: 40, clientY: 40, pointerId: 2 });

      expect(history.document.elements).toHaveLength(1);
      expect(onCommand).toHaveBeenCalledOnce();
      expect(onInteractionActiveChange.mock.calls.map(([active]) => active))
        .toEqual([true, false, true, false]);
      history.undo();
      expect(history.document.elements).toHaveLength(0);
      history.redo();
      expect(history.document.elements).toHaveLength(1);
    },
  );

  it("cancels an active annotation move on pointercancel and leaves history usable", () => {
    const initial = fixtureDocument();
    const history = createHistoryStore(initial);
    const onCommand = vi.fn((command) => history.dispatch(command));
    renderSelectionCanvas(initial, history, ["rect-1"], { onCommand });
    const stage = screen.getByTestId("stage");
    const annotation = screen.getByTestId("annotation-node");

    startAnnotationMove(annotation, 1);
    fireEvent.drag(annotation, { clientX: 40, clientY: 50 });
    expect(history.document.elements).toEqual(initial.elements);
    expect(onCommand).not.toHaveBeenCalled();
    fireEvent.pointerCancel(stage, { pointerId: 1 });
    fireEvent.pointerCancel(stage, { pointerId: 1 });
    expect(konvaControl.stopDrag).toHaveBeenCalledOnce();
    expect(konvaControl.annotationValues).toMatchObject({
      x: initial.elements[0].x,
      y: initial.elements[0].y,
      scaleX: 1,
      scaleY: 1,
      rotation: initial.elements[0].rotation,
    });
    expect(konvaControl.forceUpdate).toHaveBeenCalledOnce();
    expect(konvaControl.draw).toHaveBeenCalledOnce();
    expect(onCommand).not.toHaveBeenCalled();
    history.dispatch({
      type: "create",
      element: { ...initial.elements[0], id: "rect-2", seed: 102, zIndex: 1 },
    });

    expect(() => history.undo()).not.toThrow();
    expect(history.document.elements).toEqual(initial.elements);
  });

  it("keeps annotation move ownership with pointer 1 across pointer 2 up and cancel", () => {
    const initial = fixtureDocument();
    const history = createHistoryStore(initial);
    const onCancelTransaction = vi.fn(() => history.cancelTransaction());
    render(
      <EditorCanvas
        document={initial}
        sourceImageURL="data:image/png;base64,iVBORw0KGgo="
        tool="selection"
        {...VIEWPORT_PROPS}
        selectedIds={["rect-1"]}
        onSelect={() => {}}
        onEditText={() => {}}
        onCommand={(command) => history.dispatch(command)}
        onBeginTransaction={(label) => history.beginTransaction(label)}
        onCommitTransaction={() => history.commitTransaction()}
        onCancelTransaction={onCancelTransaction}
        textEditorOverlay={undefined}
      />,
    );
    const stage = screen.getByTestId("stage");
    const annotation = screen.getByTestId("annotation-node");

    konvaControl.annotationStartPointerId = 1;
    startAnnotationMove(annotation, 1);
    expect(konvaControl.contentSetPointerCapture).toHaveBeenCalledWith(1);
    expect(konvaControl.outerSetPointerCapture).not.toHaveBeenCalled();
    fireEvent.drag(annotation);
    fireEvent.pointerUp(stage, { pointerId: 2 });
    fireEvent.pointerCancel(stage, { pointerId: 2 });

    expect(history.isTransactionActive).toBe(true);
    expect(onCancelTransaction).not.toHaveBeenCalled();
    expect(konvaControl.setPointerCapture).toHaveBeenCalledWith(1);
    expect(konvaControl.releasePointerCapture).not.toHaveBeenCalled();

    fireEvent.pointerCancel(stage, { pointerId: 1 });
    fireEvent.pointerCancel(stage, { pointerId: 1 });
    expect(history.isTransactionActive).toBe(false);
    expect(history.document.elements).toEqual(initial.elements);
    expect(onCancelTransaction).toHaveBeenCalledOnce();
    expect(konvaControl.releasePointerCapture).toHaveBeenCalledOnce();
    expect(konvaControl.contentReleasePointerCapture).toHaveBeenCalledWith(1);
    expect(konvaControl.outerReleasePointerCapture).not.toHaveBeenCalled();
  });

  it("cancels an active annotation move through the same handle exactly once", () => {
    const handle = createRef<EditorCanvasHandle>();
    const initial = fixtureDocument();
    const history = createHistoryStore(initial);
    const onCancelTransaction = vi.fn(() => history.cancelTransaction());
    render(
      <EditorCanvas
        ref={handle}
        document={initial}
        sourceImageURL="data:image/png;base64,iVBORw0KGgo="
        tool="selection"
        {...VIEWPORT_PROPS}
        selectedIds={["rect-1"]}
        onSelect={() => {}}
        onEditText={() => {}}
        onCommand={(command) => history.dispatch(command)}
        onBeginTransaction={(label) => history.beginTransaction(label)}
        onCommitTransaction={() => history.commitTransaction()}
        onCancelTransaction={onCancelTransaction}
        textEditorOverlay={undefined}
      />,
    );
    const annotation = screen.getByTestId("annotation-node");

    startAnnotationMove(annotation);
    fireEvent.drag(annotation);
    act(() => {
      expect(handle.current?.cancelInteraction()).toBe(true);
      expect(handle.current?.cancelInteraction()).toBe(false);
    });
    fireEvent.dragEnd(annotation);

    expect(history.isTransactionActive).toBe(false);
    expect(history.document.elements).toEqual(initial.elements);
    expect(onCancelTransaction).toHaveBeenCalledOnce();
    expect(konvaControl.stopDrag).toHaveBeenCalledOnce();
    expect(konvaControl.releasePointerCapture).toHaveBeenCalledOnce();
  });

  it("cancels an active annotation move on blur once and permits shortcuts and the next move", () => {
    const initial = fixtureDocument();
    const history = createHistoryStore(initial);
    const onCancelTransaction = vi.fn(() => history.cancelTransaction());
    render(
      <EditorCanvas
        document={initial}
        sourceImageURL="data:image/png;base64,iVBORw0KGgo="
        tool="selection"
        {...VIEWPORT_PROPS}
        selectedIds={["rect-1"]}
        onSelect={() => {}}
        onEditText={() => {}}
        onCommand={(command) => history.dispatch(command)}
        onBeginTransaction={(label) => history.beginTransaction(label)}
        onCommitTransaction={() => history.commitTransaction()}
        onCancelTransaction={onCancelTransaction}
        textEditorOverlay={undefined}
      />,
    );
    const annotation = screen.getByTestId("annotation-node");

    startAnnotationMove(annotation);
    fireEvent.drag(annotation);
    expect(history.isTransactionActive).toBe(true);
    expect(history.document.elements).toEqual(initial.elements);

    fireEvent(window, new Event("blur"));

    expect(history.isTransactionActive).toBe(false);
    expect(history.document.elements).toEqual(initial.elements);
    expect(konvaControl.stopDrag).toHaveBeenCalledOnce();
    expect(konvaControl.annotationValues).toMatchObject({
      x: initial.elements[0].x,
      y: initial.elements[0].y,
      scaleX: 1,
      scaleY: 1,
      rotation: initial.elements[0].rotation,
    });
    expect(onCancelTransaction).toHaveBeenCalledOnce();
    expect(keyboardCommandFor(new KeyboardEvent("keydown", { code: "KeyR", key: "r" }), {
      interactionActive: history.isTransactionActive,
      shortcutHelpOpen: false,
      textEditing: false,
    })).toEqual({ type: "selectTool", tool: "rectangle" });

    fireEvent(window, new Event("blur"));
    fireEvent(window, new Event("mouseup"));
    fireEvent.pointerCancel(screen.getByTestId("stage"), { pointerId: 1 });
    expect(onCancelTransaction).toHaveBeenCalledOnce();

    konvaControl.dragTarget = { x: 25, y: 35 };
    startAnnotationMove(annotation);
    fireEvent.drag(annotation);
    fireEvent.dragEnd(annotation);
    expect(history.isTransactionActive).toBe(false);
    expect(history.document.elements[0]).toMatchObject({ x: 25, y: 35 });
    expect(history.undo()).toBe(true);
    expect(history.document.elements).toEqual(initial.elements);
  });

  it("attaches the Transformer to every registered selected group", () => {
    const initial = fixtureDocument({ elements: [fixtureDocument().elements[0], fixtureText()] });
    const history = createHistoryStore(initial);

    renderSelectionCanvas(initial, history, ["rect-1", "text-1"]);

    expect(konvaControl.transformerNodes).toHaveLength(2);
  });

  it("passes Shift-click as an ordered selection toggle", () => {
    const initial = fixtureDocument({ elements: [fixtureDocument().elements[0], fixtureText()] });
    const history = createHistoryStore(initial);
    const onSelect = vi.fn();
    render(
      <EditorCanvas
        document={initial}
        sourceImageURL="data:image/png;base64,iVBORw0KGgo="
        tool="selection"
        {...VIEWPORT_PROPS}
        selectedIds={["rect-1"]}
        onSelect={onSelect}
        onEditText={() => {}}
        onCommand={(command) => history.dispatch(command)}
        onBeginTransaction={(label) => history.beginTransaction(label)}
        onCommitTransaction={() => history.commitTransaction()}
        onCancelTransaction={() => history.cancelTransaction()}
        textEditorOverlay={undefined}
      />,
    );

    fireEvent.click(screen.getByTestId("element-text-1"), { shiftKey: true });

    expect(onSelect).toHaveBeenCalledWith("text-1", true);
  });

  it("keeps an empty-source click selected until release and then clears below 3 CSS pixels", () => {
    const initial = fixtureDocument();
    const onSelect = vi.fn();
    render(
      <EditorCanvas
        document={initial}
        sourceImageURL="data:image/png;base64,iVBORw0KGgo="
        tool="selection"
        {...VIEWPORT_PROPS}
        viewport={{ ...VIEWPORT, zoom: 2 }}
        toSourcePoint={(point) => ({ x: point.x / 2, y: point.y / 2 })}
        selectedIds={["rect-1"]}
        onSelect={onSelect}
        onEditText={() => {}}
        onCommand={() => {}}
        onBeginTransaction={() => {}}
        onCommitTransaction={() => {}}
        onCancelTransaction={() => {}}
        textEditorOverlay={undefined}
      />,
    );
    const stage = screen.getByTestId("stage");

    fireEvent.pointerDown(stage, { clientX: 20, clientY: 20, pointerId: 7 });
    expect(onSelect).not.toHaveBeenCalled();
    fireEvent.pointerMove(stage, { clientX: 22.9, clientY: 22.9, pointerId: 7 });
    flushAnimationFrame();
    expect(screen.queryByTestId("marquee-preview")).toBeNull();
    fireEvent.pointerUp(stage, { clientX: 22.9, clientY: 22.9, pointerId: 7 });

    expect(onSelect).toHaveBeenCalledOnce();
    expect(onSelect).toHaveBeenCalledWith(undefined);
  });

  it("previews marquee ephemerally and selects rotated AABB intersections on release", () => {
    const rotated = {
      ...fixtureRect(),
      x: 100,
      y: 100,
      width: 80,
      height: 20,
      rotation: 45,
    };
    const initial = fixtureDocument({ elements: [rotated] });
    const onSelect = vi.fn();
    const onCommand = vi.fn();
    render(
      <EditorCanvas
        document={initial}
        sourceImageURL="data:image/png;base64,iVBORw0KGgo="
        tool="selection"
        {...VIEWPORT_PROPS}
        selectedIds={[]}
        onSelect={onSelect}
        onEditText={() => {}}
        onCommand={onCommand}
        onBeginTransaction={() => {}}
        onCommitTransaction={() => {}}
        onCancelTransaction={() => {}}
        textEditorOverlay={undefined}
      />,
    );
    const stage = screen.getByTestId("stage");

    fireEvent.pointerDown(stage, { clientX: 150, clientY: 150, pointerId: 7 });
    fireEvent.pointerMove(stage, { clientX: 160, clientY: 160, pointerId: 7 });
    flushAnimationFrame();

    expect(screen.getByTestId("marquee-preview")).toBeTruthy();
    expect(onSelect).not.toHaveBeenCalled();
    expect(onCommand).not.toHaveBeenCalled();

    fireEvent.pointerUp(stage, { clientX: 160, clientY: 160, pointerId: 7 });
    expect(screen.queryByTestId("marquee-preview")).toBeNull();
    expect(onSelect).toHaveBeenCalledWith(rotated.id, false);
    expect(onCommand).not.toHaveBeenCalled();
  });

  it("keeps marquee ownership across a wrong pointer terminal", () => {
    const onSelect = vi.fn();
    renderCreationCanvas("rectangle", {
      tool: "selection",
      document: fixtureDocument(),
      selectedIds: [],
      onSelect,
    });
    const stage = screen.getByTestId("stage");

    fireEvent.pointerDown(stage, { clientX: 0, clientY: 0, pointerId: 7 });
    fireEvent.pointerMove(stage, { clientX: 130, clientY: 100, pointerId: 7 });
    flushAnimationFrame();
    fireEvent.pointerUp(stage, { clientX: 130, clientY: 100, pointerId: 8 });
    fireEvent.pointerCancel(stage, { pointerId: 8 });
    expect(onSelect).not.toHaveBeenCalled();
    expect(konvaControl.releasePointerCapture).not.toHaveBeenCalled();

    fireEvent.pointerUp(stage, { clientX: 130, clientY: 100, pointerId: 7 });
    expect(onSelect).toHaveBeenCalledWith("rect-1", false);
    expect(konvaControl.releasePointerCapture).toHaveBeenCalledOnce();
  });

  it("disables rotation when any selected element is blur", () => {
    const initial = fixtureDocument({ elements: [fixtureDocument().elements[0], fixtureBlur()] });
    const history = createHistoryStore(initial);

    renderSelectionCanvas(initial, history, ["rect-1", "blur-1"]);

    expect(konvaControl.rotateEnabled).toBe(false);
  });

  it("moves a selected pair by one shared delta and undoes once", () => {
    const initial = fixtureDocument({ elements: [fixtureDocument().elements[0], fixtureText()] });
    const history = createHistoryStore(initial);
    konvaControl.dragTarget = { x: 20, y: 12 };
    renderSelectionCanvas(initial, history, ["rect-1", "text-1"]);
    const annotation = screen.getByTestId("annotation-node");

    startAnnotationMove(annotation, 1);
    fireEvent.drag(annotation);

    expect(history.document.elements).toEqual(initial.elements);
    fireEvent.dragEnd(annotation);

    expect(history.document.elements.map(({ x, y }) => ({ x, y }))).toEqual([
      { x: 20, y: 12 },
      { x: 60, y: 62 },
    ]);
    expect(history.undo()).toBe(true);
    expect(history.document.elements.map(({ x, y }) => ({ x, y }))).toEqual([
      { x: 0, y: 0 },
      { x: 40, y: 50 },
    ]);
    expect(history.undo()).toBe(false);
  });

  it("keeps move preview ephemeral and emits one updateMany only on release", () => {
    const initial = fixtureDocument();
    const history = createHistoryStore(initial);
    const onCommand = vi.fn((command) => history.dispatch(command));
    konvaControl.dragTarget = { x: 25, y: 35 };
    render(
      <EditorCanvas
        document={initial}
        sourceImageURL="data:image/png;base64,iVBORw0KGgo="
        tool="selection"
        {...VIEWPORT_PROPS}
        selectedIds={["rect-1"]}
        onSelect={() => {}}
        onEditText={() => {}}
        onCommand={onCommand}
        onBeginTransaction={(label) => history.beginTransaction(label)}
        onCommitTransaction={() => history.commitTransaction()}
        onCancelTransaction={() => history.cancelTransaction()}
        textEditorOverlay={undefined}
      />,
    );
    const annotation = screen.getByTestId("annotation-node");

    startAnnotationMove(annotation, 1);
    fireEvent.drag(annotation);

    expect(history.document.elements).toEqual(initial.elements);
    expect(onCommand).not.toHaveBeenCalled();
    expect(konvaControl.annotationValues).toMatchObject({ x: 25, y: 35 });

    fireEvent.dragEnd(annotation);
    expect(onCommand).toHaveBeenCalledOnce();
    expect(onCommand).toHaveBeenCalledWith({
      type: "updateMany",
      elements: [expect.objectContaining({ id: "rect-1", x: 25, y: 35 })],
    });
    expect(history.document.elements[0]).toMatchObject({ x: 25, y: 35 });
    expect(history.undo()).toBe(true);
    expect(history.document.elements).toEqual(initial.elements);
    expect(history.undo()).toBe(false);
  });

  it("keeps an oversized move axis fixed and commits one fit-axis update on release", () => {
    const oversized = {
      ...fixtureRect(),
      x: -25,
      y: 10,
      width: 150,
      height: 20,
    };
    const initial = fixtureDocument({
      sourcePixelWidth: 100,
      sourcePixelHeight: 100,
      elements: [oversized],
    });
    const history = createHistoryStore(initial);
    const onCommand = vi.fn((command) => history.dispatch(command));
    konvaControl.dragTarget = { x: 20, y: 30 };
    render(
      <EditorCanvas
        document={initial}
        sourceImageURL="data:image/png;base64,iVBORw0KGgo="
        tool="selection"
        {...VIEWPORT_PROPS}
        selectedIds={["rect-1"]}
        onSelect={() => {}}
        onEditText={() => {}}
        onCommand={onCommand}
        onBeginTransaction={(label) => history.beginTransaction(label)}
        onCommitTransaction={() => history.commitTransaction()}
        onCancelTransaction={() => history.cancelTransaction()}
        textEditorOverlay={undefined}
      />,
    );
    const annotation = screen.getByTestId("annotation-node");

    startAnnotationMove(annotation, 1);
    expect(() => fireEvent.drag(annotation)).not.toThrow();

    expect(history.document.elements).toEqual(initial.elements);
    expect(onCommand).not.toHaveBeenCalled();
    expect(konvaControl.annotationValues).toMatchObject({ x: -25, y: 30 });

    fireEvent.dragEnd(annotation);
    expect(onCommand).toHaveBeenCalledOnce();
    expect(onCommand).toHaveBeenCalledWith({
      type: "updateMany",
      elements: [expect.objectContaining({ id: "rect-1", x: -25, y: 30 })],
    });
    expect(history.undo()).toBe(true);
    expect(history.document.elements).toEqual(initial.elements);
    expect(history.undo()).toBe(false);
  });

  it("cancels an x-only oversized move without a command, commit, publication, or Undo entry", () => {
    const oversized = {
      ...fixtureRect(),
      x: -25,
      y: 10,
      width: 150,
      height: 20,
    };
    const initial = fixtureDocument({
      sourcePixelWidth: 100,
      sourcePixelHeight: 100,
      elements: [oversized],
    });
    const history = createHistoryStore(initial);
    const onCommand = vi.fn((command) => history.dispatch(command));
    const onCommitTransaction = vi.fn(() => history.commitTransaction());
    const onCancelTransaction = vi.fn(() => history.cancelTransaction());
    const onHistoryChange = vi.fn();
    history.subscribe(onHistoryChange);
    konvaControl.dragTarget = { x: 20, y: 10 };
    render(
      <EditorCanvas
        document={initial}
        sourceImageURL="data:image/png;base64,iVBORw0KGgo="
        tool="selection"
        {...VIEWPORT_PROPS}
        selectedIds={["rect-1"]}
        onSelect={() => {}}
        onEditText={() => {}}
        onCommand={onCommand}
        onBeginTransaction={(label) => history.beginTransaction(label)}
        onCommitTransaction={onCommitTransaction}
        onCancelTransaction={onCancelTransaction}
        textEditorOverlay={undefined}
      />,
    );
    const annotation = screen.getByTestId("annotation-node");

    startAnnotationMove(annotation, 1);
    fireEvent.drag(annotation);
    expect(konvaControl.annotationValues).toMatchObject({ x: -25, y: 10 });

    fireEvent.dragEnd(annotation);

    expect(onCommand).not.toHaveBeenCalled();
    expect(onCommitTransaction).not.toHaveBeenCalled();
    expect(onCancelTransaction).toHaveBeenCalledOnce();
    expect(onHistoryChange).not.toHaveBeenCalled();
    expect(history.document.elements).toEqual(initial.elements);
    expect(history.isTransactionActive).toBe(false);
    expect(history.undo()).toBe(false);
  });

  it("cancels an x-only oversized Option-drag without creating an overlapping copy", () => {
    const oversized = {
      ...fixtureRect(),
      x: -25,
      y: 10,
      width: 150,
      height: 20,
    };
    const initial = fixtureDocument({
      sourcePixelWidth: 100,
      sourcePixelHeight: 100,
      elements: [oversized],
    });
    const history = createHistoryStore(initial);
    const onCommand = vi.fn((command) => history.dispatch(command));
    const onCommitTransaction = vi.fn(() => history.commitTransaction());
    const onCancelTransaction = vi.fn(() => history.cancelTransaction());
    const onSelect = vi.fn();
    konvaControl.dragTarget = { x: 20, y: 10 };
    render(
      <EditorCanvas
        document={initial}
        sourceImageURL="data:image/png;base64,iVBORw0KGgo="
        tool="selection"
        {...VIEWPORT_PROPS}
        selectedIds={["rect-1"]}
        onSelect={onSelect}
        onEditText={() => {}}
        onCommand={onCommand}
        onBeginTransaction={(label) => history.beginTransaction(label)}
        onCommitTransaction={onCommitTransaction}
        onCancelTransaction={onCancelTransaction}
        textEditorOverlay={undefined}
      />,
    );
    const annotation = screen.getByTestId("annotation-node");

    startAnnotationMove(annotation, 1, { altKey: true });
    fireEvent.drag(annotation);
    expect(screen.getByTestId("duplication-preview")).toBeTruthy();

    fireEvent.dragEnd(annotation);

    expect(onCommand).not.toHaveBeenCalled();
    expect(onCommitTransaction).not.toHaveBeenCalled();
    expect(onCancelTransaction).toHaveBeenCalledOnce();
    expect(onSelect).not.toHaveBeenCalled();
    expect(history.document.elements).toEqual(initial.elements);
    expect(history.undo()).toBe(false);
  });

  it("previews Option-drag copies while originals stay exact and commits one createMany", () => {
    const initial = fixtureDocument();
    const history = createHistoryStore(initial);
    const onCommand = vi.fn((command) => history.dispatch(command));
    const onSelect = vi.fn();
    konvaControl.dragTarget = { x: 30, y: 20 };
    render(
      <EditorCanvas
        document={initial}
        sourceImageURL="data:image/png;base64,iVBORw0KGgo="
        tool="selection"
        {...VIEWPORT_PROPS}
        selectedIds={["rect-1"]}
        onSelect={onSelect}
        onEditText={() => {}}
        onCommand={onCommand}
        onBeginTransaction={(label) => history.beginTransaction(label)}
        onCommitTransaction={() => history.commitTransaction()}
        onCancelTransaction={() => history.cancelTransaction()}
        textEditorOverlay={undefined}
      />,
    );
    const annotation = screen.getByTestId("annotation-node");

    startAnnotationMove(annotation, 1, { altKey: true });
    fireEvent.drag(annotation);

    expect(history.document.elements).toEqual(initial.elements);
    expect(onCommand).not.toHaveBeenCalled();
    expect(konvaControl.annotationValues).toMatchObject({
      x: initial.elements[0].x,
      y: initial.elements[0].y,
    });
    expect(screen.getByTestId("duplication-preview")).toBeTruthy();

    const firstPreviewIdentity = within(screen.getByTestId("duplication-preview"))
      .getByTestId("annotation-node")
      .getAttribute("data-element-testid");
    konvaControl.dragTarget = { x: 45, y: 25 };
    fireEvent.drag(annotation);
    const secondPreviewIdentity = within(screen.getByTestId("duplication-preview"))
      .getByTestId("annotation-node")
      .getAttribute("data-element-testid");

    expect(secondPreviewIdentity).toBe(firstPreviewIdentity);

    fireEvent.dragEnd(annotation);

    expect(onCommand).toHaveBeenCalledOnce();
    const command = onCommand.mock.calls[0][0];
    expect(command).toMatchObject({
      type: "createMany",
      elements: [expect.objectContaining({ x: 45, y: 25 })],
    });
    if (command.type !== "createMany") throw new Error("Expected createMany");
    expect(`element-${command.elements[0].id}`).toBe(firstPreviewIdentity);
    expect(history.document.elements[0]).toEqual(initial.elements[0]);
    expect(history.document.elements).toHaveLength(2);
    expect(onSelect).toHaveBeenLastCalledWith(command.elements[0].id, false);
    expect(history.undo()).toBe(true);
    expect(history.document.elements).toEqual(initial.elements);
  });

  it("cancels an active move when the backing document identity changes", () => {
    const initial = fixtureDocument();
    const replacement = fixtureDocument({
      elements: [{ ...fixtureRect(), x: 70, y: 80 }],
    });
    const history = createHistoryStore(initial);
    const onCommand = vi.fn();
    const onCancelTransaction = vi.fn(() => history.cancelTransaction());
    const renderCanvas = (document = initial) => (
      <EditorCanvas
        document={document}
        sourceImageURL="data:image/png;base64,iVBORw0KGgo="
        tool="selection"
        {...VIEWPORT_PROPS}
        selectedIds={["rect-1"]}
        onSelect={() => {}}
        onEditText={() => {}}
        onCommand={onCommand}
        onBeginTransaction={(label) => history.beginTransaction(label)}
        onCommitTransaction={() => history.commitTransaction()}
        onCancelTransaction={onCancelTransaction}
        textEditorOverlay={undefined}
      />
    );
    const view = render(renderCanvas());
    const annotation = screen.getByTestId("annotation-node");

    startAnnotationMove(annotation, 7);
    fireEvent.drag(annotation);
    expect(history.isTransactionActive).toBe(true);

    view.rerender(renderCanvas(replacement));
    fireEvent.dragEnd(annotation);

    expect(onCancelTransaction).toHaveBeenCalledOnce();
    expect(onCommand).not.toHaveBeenCalled();
    expect(history.isTransactionActive).toBe(false);
    expect(konvaControl.annotationValues).toMatchObject({
      x: replacement.elements[0].x,
      y: replacement.elements[0].y,
    });
  });

  it("replaces a pending pointer owner after the backing document identity changes", () => {
    const initial = fixtureDocument();
    const replacement = fixtureDocument({
      elements: [{ ...fixtureRect(), x: 70, y: 80 }],
    });
    const history = createHistoryStore(initial);
    const renderCanvas = (document = initial) => (
      <EditorCanvas
        document={document}
        sourceImageURL="data:image/png;base64,iVBORw0KGgo="
        tool="selection"
        {...VIEWPORT_PROPS}
        selectedIds={["rect-1"]}
        onSelect={() => {}}
        onEditText={() => {}}
        onCommand={(command) => history.dispatch(command)}
        onBeginTransaction={(label) => history.beginTransaction(label)}
        onCommitTransaction={() => history.commitTransaction()}
        onCancelTransaction={() => history.cancelTransaction()}
        textEditorOverlay={undefined}
      />
    );
    const view = render(renderCanvas());
    let annotation = screen.getByTestId("annotation-node");

    fireEvent.pointerDown(annotation, { pointerId: 7 });
    view.rerender(renderCanvas(replacement));
    annotation = screen.getByTestId("annotation-node");
    fireEvent.pointerDown(annotation, { pointerId: 8 });
    fireEvent.dragStart(annotation);

    expect(konvaControl.setPointerCapture).toHaveBeenCalledWith(8);
  });

  it("restores Option-drag on Escape without a command or Undo entry", () => {
    const handle = createRef<EditorCanvasHandle>();
    const initial = fixtureDocument();
    const history = createHistoryStore(initial);
    const onCommand = vi.fn((command) => history.dispatch(command));
    const onCancelTransaction = vi.fn(() => history.cancelTransaction());
    konvaControl.dragTarget = { x: 30, y: 20 };
    render(
      <EditorCanvas
        ref={handle}
        document={initial}
        sourceImageURL="data:image/png;base64,iVBORw0KGgo="
        tool="selection"
        {...VIEWPORT_PROPS}
        selectedIds={["rect-1"]}
        onSelect={() => {}}
        onEditText={() => {}}
        onCommand={onCommand}
        onBeginTransaction={(label) => history.beginTransaction(label)}
        onCommitTransaction={() => history.commitTransaction()}
        onCancelTransaction={onCancelTransaction}
        textEditorOverlay={undefined}
      />,
    );
    const annotation = screen.getByTestId("annotation-node");

    startAnnotationMove(annotation, 7, { altKey: true });
    fireEvent.drag(annotation);
    expect(screen.getByTestId("duplication-preview")).toBeTruthy();

    act(() => expect(handle.current?.cancelInteraction()).toBe(true));
    fireEvent.dragEnd(annotation);

    expect(screen.queryByTestId("duplication-preview")).toBeNull();
    expect(history.document.elements).toEqual(initial.elements);
    expect(onCommand).not.toHaveBeenCalled();
    expect(onCancelTransaction).toHaveBeenCalledOnce();
    expect(history.undo()).toBe(false);
  });

  it("cancels an identity transform terminal without publishing history", () => {
    const initial = fixtureDocument();
    const startingElement = initial.elements[0];
    const history = createHistoryStore(initial);
    const onCommand = vi.fn((command) => history.dispatch(command));
    const onCommitTransaction = vi.fn(() => history.commitTransaction());
    const onCancelTransaction = vi.fn(() => history.cancelTransaction());
    const onHistoryChange = vi.fn();
    history.subscribe(onHistoryChange);
    render(
      <EditorCanvas
        document={initial}
        sourceImageURL="data:image/png;base64,iVBORw0KGgo="
        tool="selection"
        {...VIEWPORT_PROPS}
        selectedIds={["rect-1"]}
        onSelect={() => {}}
        onEditText={() => {}}
        onCommand={onCommand}
        onBeginTransaction={(label) => history.beginTransaction(label)}
        onCommitTransaction={onCommitTransaction}
        onCancelTransaction={onCancelTransaction}
        textEditorOverlay={undefined}
      />,
    );
    const stage = screen.getByTestId("stage");
    const annotation = screen.getByTestId("annotation-node");

    startAnnotationTransform(annotation, 7);
    Object.assign(konvaControl.annotationValues, {
      x: startingElement.x,
      y: startingElement.y,
      scaleX: 1,
      scaleY: 1,
      rotation: startingElement.rotation,
    });
    fireEvent.contextMenu(annotation);
    fireEvent.contextMenu(annotation);
    fireEvent.pointerCancel(stage, { pointerId: 7 });
    fireEvent(window, new Event("blur"));

    expect(onCommand).not.toHaveBeenCalled();
    expect(onCommitTransaction).not.toHaveBeenCalled();
    expect(onCancelTransaction).toHaveBeenCalledOnce();
    expect(onHistoryChange).not.toHaveBeenCalled();
    expect(history.document.elements).toEqual(initial.elements);
    expect(history.isTransactionActive).toBe(false);
    expect(history.undo()).toBe(false);
  });

  it("commits one updateMany command for a group transform", () => {
    const initial = fixtureDocument({ elements: [fixtureDocument().elements[0], fixtureText()] });
    const history = createHistoryStore(initial);
    const onCommand = vi.fn((command) => history.dispatch(command));
    const onBeginTransaction = vi.fn((label: string) => history.beginTransaction(label));
    const onCommitTransaction = vi.fn(() => history.commitTransaction());
    render(
      <EditorCanvas
        document={initial}
        sourceImageURL="data:image/png;base64,iVBORw0KGgo="
        tool="selection"
        {...VIEWPORT_PROPS}
        selectedIds={["rect-1", "text-1"]}
        onSelect={() => {}}
        onEditText={() => {}}
        onCommand={onCommand}
        onBeginTransaction={onBeginTransaction}
        onCommitTransaction={onCommitTransaction}
        onCancelTransaction={() => {}}
        textEditorOverlay={undefined}
      />,
    );
    const annotation = screen.getByTestId("annotation-node");

    startAnnotationTransform(annotation, 1);
    expect(onCommand).not.toHaveBeenCalled();
    expect(history.document.elements).toEqual(initial.elements);
    fireEvent.contextMenu(annotation);

    expect(onBeginTransaction).toHaveBeenCalledOnce();
    expect(onCommand).toHaveBeenCalledWith({
      type: "updateMany",
      elements: expect.arrayContaining([
        expect.objectContaining({ id: "rect-1" }),
        expect.objectContaining({ id: "text-1" }),
      ]),
    });
    expect(onCommitTransaction).toHaveBeenCalledOnce();
    expect(history.document.elements).not.toEqual(initial.elements);
    expect(history.undo()).toBe(true);
    expect(history.document.elements).toEqual(initial.elements);
    expect(history.undo()).toBe(false);
  });

  it("keeps annotation transform ownership with pointer 1 across pointer 2 cancel", () => {
    const initial = fixtureDocument();
    const history = createHistoryStore(initial);
    const onCommitTransaction = vi.fn(() => history.commitTransaction());
    const onCancelTransaction = vi.fn(() => history.cancelTransaction());
    render(
      <EditorCanvas
        document={initial}
        sourceImageURL="data:image/png;base64,iVBORw0KGgo="
        tool="selection"
        {...VIEWPORT_PROPS}
        selectedIds={["rect-1"]}
        onSelect={() => {}}
        onEditText={() => {}}
        onCommand={(command) => history.dispatch(command)}
        onBeginTransaction={(label) => history.beginTransaction(label)}
        onCommitTransaction={onCommitTransaction}
        onCancelTransaction={onCancelTransaction}
        textEditorOverlay={undefined}
      />,
    );
    const stage = screen.getByTestId("stage");
    const annotation = screen.getByTestId("annotation-node");

    konvaControl.annotationStartPointerId = 1;
    startAnnotationTransform(annotation, 1);
    fireEvent.pointerCancel(stage, { pointerId: 2 });

    expect(history.isTransactionActive).toBe(true);
    expect(onCommitTransaction).not.toHaveBeenCalled();
    expect(onCancelTransaction).not.toHaveBeenCalled();
    expect(konvaControl.setPointerCapture).toHaveBeenCalledWith(1);
    expect(konvaControl.releasePointerCapture).not.toHaveBeenCalled();

    fireEvent.contextMenu(annotation);
    fireEvent.contextMenu(annotation);
    expect(history.isTransactionActive).toBe(false);
    expect(onCommitTransaction).toHaveBeenCalledOnce();
    expect(onCancelTransaction).not.toHaveBeenCalled();
    expect(konvaControl.releasePointerCapture).toHaveBeenCalledOnce();
  });

  it("deduplicates per-node transform events into one transaction and one undo entry", () => {
    const initial = fixtureDocument({ elements: [fixtureDocument().elements[0], fixtureText()] });
    const history = createHistoryStore(initial);
    const onBeginTransaction = vi.fn((label: string) => history.beginTransaction(label));
    const onCommitTransaction = vi.fn(() => history.commitTransaction());
    render(
      <EditorCanvas
        document={initial}
        sourceImageURL="data:image/png;base64,iVBORw0KGgo="
        tool="selection"
        {...VIEWPORT_PROPS}
        selectedIds={["rect-1", "text-1"]}
        onSelect={() => {}}
        onEditText={() => {}}
        onCommand={(command) => history.dispatch(command)}
        onBeginTransaction={onBeginTransaction}
        onCommitTransaction={onCommitTransaction}
        onCancelTransaction={() => history.cancelTransaction()}
        textEditorOverlay={undefined}
      />,
    );
    const annotations = [
      screen.getByTestId("annotation-node"),
      screen.getByTestId("element-text-1"),
    ];

    startAnnotationTransform(annotations[0], 1);
    fireEvent(annotations[1], new MouseEvent("auxclick", { bubbles: true }));
    annotations.forEach((annotation) => fireEvent.contextMenu(annotation));

    expect(onBeginTransaction).toHaveBeenCalledOnce();
    expect(onCommitTransaction).toHaveBeenCalledOnce();
    expect(history.undo()).toBe(true);
    expect(history.document.elements).toEqual(initial.elements);
    expect(history.undo()).toBe(false);
  });

  it("cancels an active transform on pointercancel and leaves history usable", () => {
    const initial = fixtureDocument();
    const history = createHistoryStore(initial);
    renderSelectionCanvas(initial, history);
    const stage = screen.getByTestId("stage");
    const annotation = screen.getByTestId("annotation-node");

    startAnnotationTransform(annotation, 1);
    fireEvent.pointerCancel(stage, { pointerId: 1 });
    fireEvent.pointerCancel(stage, { pointerId: 1 });
    expect(konvaControl.stopTransform).toHaveBeenCalledOnce();
    expect(konvaControl.annotationValues).toMatchObject({
      x: initial.elements[0].x,
      y: initial.elements[0].y,
      scaleX: 1,
      scaleY: 1,
      rotation: initial.elements[0].rotation,
    });
    expect(konvaControl.forceUpdate).toHaveBeenCalledOnce();
    expect(konvaControl.draw).toHaveBeenCalledOnce();
    history.dispatch({
      type: "create",
      element: { ...initial.elements[0], id: "rect-2", seed: 102, zIndex: 1 },
    });

    expect(() => history.undo()).not.toThrow();
    expect(history.document.elements).toEqual(initial.elements);
  });

  it("cancels an active transform on blur once and permits shortcuts and the next transform", () => {
    const initial = fixtureDocument();
    const history = createHistoryStore(initial);
    const onCancelTransaction = vi.fn(() => history.cancelTransaction());
    render(
      <EditorCanvas
        document={initial}
        sourceImageURL="data:image/png;base64,iVBORw0KGgo="
        tool="selection"
        {...VIEWPORT_PROPS}
        selectedIds={["rect-1"]}
        onSelect={() => {}}
        onEditText={() => {}}
        onCommand={(command) => history.dispatch(command)}
        onBeginTransaction={(label) => history.beginTransaction(label)}
        onCommitTransaction={() => history.commitTransaction()}
        onCancelTransaction={onCancelTransaction}
        textEditorOverlay={undefined}
      />,
    );
    const annotation = screen.getByTestId("annotation-node");

    startAnnotationTransform(annotation);
    expect(history.isTransactionActive).toBe(true);

    fireEvent(window, new Event("blur"));

    expect(history.isTransactionActive).toBe(false);
    expect(konvaControl.stopTransform).toHaveBeenCalledOnce();
    expect(konvaControl.annotationValues).toMatchObject({
      x: initial.elements[0].x,
      y: initial.elements[0].y,
      scaleX: 1,
      scaleY: 1,
      rotation: initial.elements[0].rotation,
    });
    expect(onCancelTransaction).toHaveBeenCalledOnce();
    expect(keyboardCommandFor(new KeyboardEvent("keydown", { code: "KeyR", key: "r" }), {
      interactionActive: history.isTransactionActive,
      shortcutHelpOpen: false,
      textEditing: false,
    })).toEqual({ type: "selectTool", tool: "rectangle" });

    fireEvent(window, new Event("blur"));
    fireEvent(window, new Event("mouseup"));
    fireEvent.pointerCancel(screen.getByTestId("stage"), { pointerId: 1 });
    expect(onCancelTransaction).toHaveBeenCalledOnce();

    startAnnotationTransform(annotation);
    fireEvent.contextMenu(annotation);
    expect(history.isTransactionActive).toBe(false);
    expect(history.undo()).toBe(true);
    expect(history.document.elements).toEqual(initial.elements);
  });
});

function startAnnotationMove(
  annotation: HTMLElement,
  pointerId = 1,
  modifiers: { altKey?: boolean; shiftKey?: boolean } = {},
): void {
  fireEvent.pointerDown(annotation, { pointerId, ...modifiers });
  fireEvent.dragStart(annotation);
}

function startAnnotationTransform(annotation: HTMLElement, pointerId = 1): void {
  fireEvent.pointerDown(screen.getByTestId("transformer"), { pointerId });
  fireEvent.doubleClick(annotation);
  Object.assign(konvaControl.annotationValues, {
    x: 40,
    y: 50,
    scaleX: 0.5,
    scaleY: 1.25,
    rotation: 15,
  });
}

function renderSelectionCanvas(
  document: ReturnType<typeof fixtureDocument>,
  history: ReturnType<typeof createHistoryStore>,
  selectedIds = ["rect-1"],
  overrides: Partial<Parameters<typeof EditorCanvas>[0]> = {},
) {
  render(
    <EditorCanvas
      document={document}
      sourceImageURL="data:image/png;base64,iVBORw0KGgo="
      tool="selection"
      {...VIEWPORT_PROPS}
    selectedIds={selectedIds}
    onSelect={() => {}}
    onEditText={() => {}}
      onCommand={(command) => history.dispatch(command)}
      onBeginTransaction={(label) => history.beginTransaction(label)}
      onCommitTransaction={() => history.commitTransaction()}
      onCancelTransaction={() => history.cancelTransaction()}
    textEditorOverlay={undefined}
      {...overrides}
    />,
  );
}

function renderCreationCanvas(
  tool: Exclude<EditorTool, "selection" | "text"> | "text",
  overrides: Partial<Parameters<typeof EditorCanvas>[0]>
    & Partial<RefAttributes<EditorCanvasHandle>> = {},
) {
  const document = fixtureDocument({ elements: [] });
  return render(
    <EditorCanvas
      document={document}
      sourceImageURL="data:image/png;base64,iVBORw0KGgo="
      tool={tool}
      {...VIEWPORT_PROPS}
      selectedIds={[]}
      onSelect={() => {}}
      onEditText={() => {}}
      onCommand={() => {}}
      onBeginTransaction={() => {}}
      onCommitTransaction={() => {}}
      onCancelTransaction={() => {}}
      textEditorOverlay={undefined}
      {...overrides}
    />,
  );
}

function flushAnimationFrame(): void {
  const next = animationFrames.entries().next().value as
    | [number, FrameRequestCallback]
    | undefined;
  if (!next) return;
  const [frame, callback] = next;
  animationFrames.delete(frame);
  act(() => callback(0));
}
