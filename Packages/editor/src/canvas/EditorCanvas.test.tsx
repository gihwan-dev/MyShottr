import { cleanup, fireEvent, render, screen } from "@testing-library/react";
import Konva from "konva";
import { afterEach, describe, expect, it, vi } from "vitest";

import { createHistoryStore } from "../model/history";
import { keyboardCommandFor } from "../input/ShortcutRouter";
import { fixtureBlur, fixtureDocument, fixtureText } from "../test/fixtures";
import { cancelAnnotationInteraction, EditorCanvas } from "./EditorCanvas";

const konvaControl = vi.hoisted(() => ({
  stopDrag: vi.fn(),
  stopTransform: vi.fn(),
  forceUpdate: vi.fn(),
  draw: vi.fn(),
  preventDefault: vi.fn(),
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
    const isAnnotationNode = typeof props.onDragStart === "function";
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
    }), []);
    React.useImperativeHandle(ref, () => node);
    const onDragStart = props.onDragStart as ((event: { currentTarget: typeof node }) => void) | undefined;
    const onDragMove = props.onDragMove as ((event: { currentTarget: typeof node }) => void) | undefined;
    const onDragEnd = props.onDragEnd as (() => void) | undefined;
    const onTransformStart = props.onTransformStart as ((event: { currentTarget: typeof node }) => void) | undefined;
    const onTransformEnd = props.onTransformEnd as ((event: { currentTarget: typeof node }) => void) | undefined;
    const onDblClick = props.onDblClick as (() => void) | undefined;
    const onClick = props.onClick as (() => void) | undefined;
    if (onDblClick || props["data-testid"] === "element-text-1") return React.createElement("div", {
      "data-testid": props["data-testid"],
      onDoubleClick: onDblClick,
      onClick,
      onAuxClick: () => onTransformStart?.({ currentTarget: node }),
      onContextMenu: (event: React.MouseEvent) => {
        event.preventDefault();
        onTransformEnd?.({ currentTarget: node });
      },
    }, props.children);
    if (!onDragStart) return React.createElement("div", null, props.children);
    return React.createElement("div", {
      "data-testid": props["data-testid"] === "element-text-1"
        ? props["data-testid"]
        : "annotation-node",
      draggable: true,
      onDragStart: () => onDragStart({ currentTarget: node }),
      onDrag: () => {
        values.current.x = konvaControl.dragTarget.x;
        values.current.y = konvaControl.dragTarget.y;
        onDragMove?.({ currentTarget: node });
      },
      onDragEnd,
      onClick,
      onDoubleClick: () => {
        onTransformStart?.({ currentTarget: node });
        values.current.x = 40;
        values.current.y = 50;
        values.current.scaleX = 0.5;
        values.current.scaleY = 1.25;
        values.current.rotation = 15;
      },
      onContextMenu: (event: React.MouseEvent) => {
        event.preventDefault();
        onTransformEnd?.({ currentTarget: node });
      },
    }, props.children);
  });
  const Transformer = React.forwardRef((props: { rotateEnabled?: boolean }, ref) => {
    konvaControl.rotateEnabled = props.rotateEnabled ?? true;
    React.useImperativeHandle(ref, () => ({
      nodes: (nodes?: unknown[]) => {
        if (nodes) konvaControl.transformerNodes = nodes;
        return konvaControl.transformerNodes;
      },
      getLayer: () => ({ draw: () => {} }),
      stopTransform: konvaControl.stopTransform,
      forceUpdate: konvaControl.forceUpdate,
    }));
    return React.createElement("div");
  });
  const Stage = ({ children, width, height, onMouseDown, onMouseMove, onMouseUp, onWheel }: {
    children?: React.ReactNode;
    width: number;
    height: number;
    onMouseDown?: (event: unknown) => void;
    onMouseMove?: (event: unknown) => void;
    onMouseUp?: (event: unknown) => void;
    onWheel?: (event: unknown) => void;
  }) => {
    const pointer = { x: 0, y: 0 };
    const stage = {
      getPointerPosition: () => ({ ...pointer }),
    };
    const eventFor = (event: React.MouseEvent) => {
      pointer.x = event.clientX;
      pointer.y = event.clientY;
      return {
        evt: {
          shiftKey: event.shiftKey,
          metaKey: event.metaKey,
          ctrlKey: event.ctrlKey,
          deltaX: "deltaX" in event ? Number(event.deltaX) : 0,
          deltaY: "deltaY" in event ? Number(event.deltaY) : 0,
          preventDefault: () => {
            konvaControl.preventDefault();
            event.preventDefault();
          },
        },
        target: {
          getStage: () => stage,
        },
      };
    };
    return React.createElement("div", {
      "data-testid": "stage",
      "data-width": width,
      "data-height": height,
      onMouseDown: (event: React.MouseEvent) => onMouseDown?.(eventFor(event)),
      onMouseMove: (event: React.MouseEvent) => onMouseMove?.(eventFor(event)),
      onMouseUp: (event: React.MouseEvent) => onMouseUp?.(eventFor(event)),
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
  onViewportWheel: () => {},
  onViewportPanBy: () => {},
  onInteractionActiveChange: () => {},
  toSourcePoint: (point: { x: number; y: number }) => point,
};

afterEach(() => {
  cleanup();
  vi.clearAllMocks();
  konvaControl.transformerNodes = [];
  konvaControl.rotateEnabled = true;
  konvaControl.dragTarget = { x: 40, y: 50 };
});

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

    fireEvent.mouseDown(stage, { clientX: 10, clientY: 20 });
    fireEvent.mouseMove(stage, { clientX: 40, clientY: 55 });
    fireEvent.mouseUp(stage, { clientX: 40, clientY: 55 });

    expect(onViewportPanBy).toHaveBeenCalledWith({ x: 30, y: 35 });
    expect(onInteractionActiveChange.mock.calls.map(([active]) => active))
      .toEqual([true, false]);
    expect(history.document.elements).toHaveLength(0);
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

    fireEvent.mouseDown(stage, { clientX: 10, clientY: 20 });
    fireEvent.mouseMove(stage, { clientX: 30, clientY: 45 });
    window.dispatchEvent(new Event("blur"));
    window.dispatchEvent(new Event("blur"));
    fireEvent.mouseMove(stage, { clientX: 80, clientY: 90 });

    expect(onViewportPanBy).toHaveBeenCalledTimes(1);
    expect(onInteractionActiveChange.mock.calls.map(([active]) => active))
      .toEqual([true, false]);
    expect(keyboardCommandFor(new KeyboardEvent("keydown", { code: "KeyR", key: "r" }), {
      interactionActive,
      shortcutHelpOpen: false,
      textEditing: false,
    })).toEqual({ type: "selectTool", tool: "rectangle" });

    fireEvent.mouseDown(stage, { clientX: 100, clientY: 110 });
    fireEvent.mouseMove(stage, { clientX: 120, clientY: 140 });
    fireEvent.mouseUp(stage, { clientX: 120, clientY: 140 });
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
    fireEvent.mouseDown(stage, { clientX: 10, clientY: 20 });
    expect(canvas.style.cursor).toBe("grabbing");
    fireEvent.mouseUp(stage, { clientX: 10, clientY: 20 });
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

    fireEvent.mouseDown(stage, { clientX: 10, clientY: 20 });
    view.rerender(canvas(true));
    fireEvent.mouseMove(stage, { clientX: 40, clientY: 55 });
    fireEvent.mouseUp(stage, { clientX: 40, clientY: 55 });

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

    fireEvent.mouseDown(stage, { clientX: 10, clientY: 20, shiftKey: true });
    fireEvent.mouseMove(stage, { clientX: 40, clientY: 55, shiftKey: true });

    expect(onViewportPanBy).not.toHaveBeenCalled();
  });

  it("renders a rectangle preview during drag before committing the element", () => {
    const initial = fixtureDocument({ elements: [] });
    const history = createHistoryStore(initial);
    const onInteractionActiveChange = vi.fn();
    render(
      <EditorCanvas
        document={initial}
        sourceImageURL="data:image/png;base64,iVBORw0KGgo="
        tool="rectangle"
        {...VIEWPORT_PROPS}
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

    fireEvent.mouseDown(stage, { clientX: 10, clientY: 20 });
    fireEvent.mouseMove(stage, { clientX: 70, clientY: 90 });

    expect(screen.getByTestId("annotation-node")).toBeTruthy();
    expect(history.document.elements).toHaveLength(0);

    fireEvent.mouseUp(stage, { clientX: 70, clientY: 90 });

    expect(history.document.elements).toEqual([
      expect.objectContaining({
        type: "rectangle",
        x: 10,
        y: 20,
        width: 60,
        height: 70,
      }),
    ]);
    expect(onInteractionActiveChange.mock.calls.map(([active]) => active))
      .toEqual([true, false]);
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
        selectedIds={[]}
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

  it.each(["mouseup", "pointercancel", "blur"] as const)(
    "clears an abandoned creation on window %s so create undo and redo remain usable",
    (terminalEvent) => {
      const initial = fixtureDocument({ elements: [] });
      const history = createHistoryStore(initial);
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
          onCommand={(command) => history.dispatch(command)}
          onBeginTransaction={(label) => history.beginTransaction(label)}
          onCommitTransaction={() => history.commitTransaction()}
          onCancelTransaction={() => history.cancelTransaction()}
          onInteractionActiveChange={onInteractionActiveChange}
          textEditorOverlay={undefined}
        />,
      );
      const stage = screen.getByTestId("stage");

      fireEvent.mouseDown(stage, { clientX: 10, clientY: 10 });
      window.dispatchEvent(new Event(terminalEvent, { bubbles: true, cancelable: true }));
      window.dispatchEvent(new Event(terminalEvent, { bubbles: true, cancelable: true }));
      expect(onInteractionActiveChange.mock.calls.map(([active]) => active))
        .toEqual([true, false]);
      expect(() => fireEvent.mouseDown(stage, { clientX: 20, clientY: 20 })).not.toThrow();
      fireEvent.mouseUp(stage, { clientX: 40, clientY: 40 });

      expect(history.document.elements).toHaveLength(1);
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
    renderSelectionCanvas(initial, history);
    const stage = screen.getByTestId("stage");
    const annotation = screen.getByTestId("annotation-node");

    fireEvent.mouseDown(stage);
    fireEvent.dragStart(annotation);
    fireEvent.drag(annotation, { clientX: 40, clientY: 50 });
    expect(history.document.elements[0]).toMatchObject({ x: 40, y: 50 });
    window.dispatchEvent(new Event("pointercancel", { bubbles: true, cancelable: true }));
    window.dispatchEvent(new Event("pointercancel", { bubbles: true, cancelable: true }));
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
    history.dispatch({
      type: "create",
      element: { ...initial.elements[0], id: "rect-2", seed: 102, zIndex: 1 },
    });

    expect(() => history.undo()).not.toThrow();
    expect(history.document.elements).toEqual(initial.elements);
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

    fireEvent.dragStart(annotation);
    fireEvent.drag(annotation);
    expect(history.isTransactionActive).toBe(true);
    expect(history.document.elements[0]).toMatchObject({ x: 40, y: 50 });

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
    fireEvent(window, new Event("pointercancel"));
    expect(onCancelTransaction).toHaveBeenCalledOnce();

    konvaControl.dragTarget = { x: 25, y: 35 };
    fireEvent.dragStart(annotation);
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

    fireEvent.mouseDown(screen.getByTestId("stage"), { shiftKey: true });
    fireEvent.click(screen.getByTestId("element-text-1"));

    expect(onSelect).toHaveBeenCalledWith("text-1", true);
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
    const stage = screen.getByTestId("stage");
    const annotation = screen.getByTestId("annotation-node");

    fireEvent.mouseDown(stage);
    fireEvent.dragStart(annotation);
    fireEvent.drag(annotation);
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

  it("commits one updateMany command for a group transform", () => {
    const initial = fixtureDocument({ elements: [fixtureDocument().elements[0], fixtureText()] });
    const onCommand = vi.fn();
    const onBeginTransaction = vi.fn();
    const onCommitTransaction = vi.fn();
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

    fireEvent.mouseDown(screen.getByTestId("stage"));
    fireEvent.doubleClick(annotation);
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

    fireEvent.mouseDown(screen.getByTestId("stage"));
    fireEvent.doubleClick(annotations[0]);
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

    fireEvent.mouseDown(stage);
    fireEvent.doubleClick(annotation);
    window.dispatchEvent(new Event("pointercancel", { bubbles: true, cancelable: true }));
    window.dispatchEvent(new Event("pointercancel", { bubbles: true, cancelable: true }));
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

    fireEvent.doubleClick(annotation);
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
    fireEvent(window, new Event("pointercancel"));
    expect(onCancelTransaction).toHaveBeenCalledOnce();

    fireEvent.doubleClick(annotation);
    fireEvent.contextMenu(annotation);
    expect(history.isTransactionActive).toBe(false);
    expect(history.undo()).toBe(true);
    expect(history.document.elements).toEqual(initial.elements);
  });
});

function renderSelectionCanvas(
  document: ReturnType<typeof fixtureDocument>,
  history: ReturnType<typeof createHistoryStore>,
  selectedIds = ["rect-1"],
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
    />,
  );
}
