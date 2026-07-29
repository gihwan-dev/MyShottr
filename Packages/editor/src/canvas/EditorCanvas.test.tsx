import { cleanup, fireEvent, render, screen } from "@testing-library/react";
import { afterEach, describe, expect, it, vi } from "vitest";

import { createHistoryStore } from "../model/history";
import { fixtureDocument } from "../test/fixtures";
import { EditorCanvas } from "./EditorCanvas";

vi.mock("react-konva", async () => {
  const React = await import("react");
  const primitive = ({ children }: { children?: React.ReactNode }) => React.createElement("div", null, children);
  const Transformer = React.forwardRef((_props, ref) => {
    React.useImperativeHandle(ref, () => ({
      nodes: () => {},
      getLayer: () => ({ draw: () => {} }),
    }));
    return React.createElement("div");
  });
  const Stage = ({ children, onMouseDown, onMouseMove, onMouseUp }: {
    children?: React.ReactNode;
    onMouseDown?: (event: unknown) => void;
    onMouseMove?: (event: unknown) => void;
    onMouseUp?: (event: unknown) => void;
  }) => {
    const pointer = { x: 0, y: 0 };
    const stage = {
      getPointerPosition: () => ({ ...pointer }),
    };
    const eventFor = (event: React.MouseEvent) => {
      pointer.x = event.clientX;
      pointer.y = event.clientY;
      return {
        evt: { shiftKey: event.shiftKey },
        target: {
          getStage: () => stage,
        },
      };
    };
    return React.createElement("div", {
      "data-testid": "stage",
      onMouseDown: (event: React.MouseEvent) => onMouseDown?.(eventFor(event)),
      onMouseMove: (event: React.MouseEvent) => onMouseMove?.(eventFor(event)),
      onMouseUp: (event: React.MouseEvent) => onMouseUp?.(eventFor(event)),
    }, children);
  };
  return {
    Circle: primitive,
    Group: primitive,
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

afterEach(cleanup);

describe("EditorCanvas gesture terminals", () => {
  it.each(["mouseup", "pointercancel"] as const)(
    "clears an abandoned creation on window %s so create undo and redo remain usable",
    (terminalEvent) => {
      const initial = fixtureDocument({ elements: [] });
      const history = createHistoryStore(initial);
      render(
        <EditorCanvas
          document={initial}
          sourceImageURL="data:image/png;base64,iVBORw0KGgo="
          tool="rectangle"
          zoom={1}
          pan={{ x: 0, y: 0 }}
          rectangleFillColor={null}
          selectedId={undefined}
          onSelect={() => {}}
          onCommand={(command) => history.dispatch(command)}
          onBeginTransaction={(label) => history.beginTransaction(label)}
          onCommitTransaction={() => history.commitTransaction()}
          onPanChange={() => {}}
        />,
      );
      const stage = screen.getByTestId("stage");

      fireEvent.mouseDown(stage, { clientX: 10, clientY: 10 });
      window.dispatchEvent(new Event(terminalEvent, { bubbles: true, cancelable: true }));
      expect(() => fireEvent.mouseDown(stage, { clientX: 20, clientY: 20 })).not.toThrow();
      fireEvent.mouseUp(stage, { clientX: 40, clientY: 40 });

      expect(history.document.elements).toHaveLength(1);
      history.undo();
      expect(history.document.elements).toHaveLength(0);
      history.redo();
      expect(history.document.elements).toHaveLength(1);
    },
  );
});
