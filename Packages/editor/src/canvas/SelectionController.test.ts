import { describe, expect, it, vi } from "vitest";
import { allElementFixtures, fixtureLine, fixtureRect, fixtureText } from "../test/fixtures";
import { beginTransformerInteraction } from "./EditorCanvas";
import {
  CanvasPointerController,
  duplicateElementWithinBounds,
  moveElementsWithinBounds,
  resizeElementWithinBounds,
  SelectionController,
} from "./SelectionController";
import { createHistoryStore } from "../model/history";
import { findElement } from "../model/reducer";

describe("canvas element bounds", () => {
  it("offsets every path point when duplicating an arrow", () => {
    const arrow = allElementFixtures().find((element) => element.type === "arrow");
    if (!arrow) throw new Error("Missing arrow fixture");

    const edgeArrow = {
      ...arrow,
      x: 1430,
      points: [{ x: 1430, y: 25 }, { x: 1530, y: 65 }] as [{ x: number; y: number }, { x: number; y: number }],
    };
    const duplicate = duplicateElementWithinBounds(edgeArrow, { x: edgeArrow.x + 12, y: edgeArrow.y + 12 }, { sourceWidth: 1440, sourceHeight: 900 });

    expect(duplicate).toMatchObject({ x: 1439, y: 37, points: [{ x: 1439, y: 37 }, { x: 1539, y: 77 }] });
  });

  it("offsets and scales both line endpoints with its bounds", () => {
    const line = fixtureLine();
    const duplicate = duplicateElementWithinBounds(
      line,
      { x: 30, y: 40 },
      { sourceWidth: 1440, sourceHeight: 900 },
    );
    const transformed = resizeElementWithinBounds(
      duplicate,
      { x: 30, y: 40 },
      2,
      0.5,
      0,
      { sourceWidth: 1440, sourceHeight: 900 },
    );

    expect(transformed).toMatchObject({
      x: 30,
      y: 40,
      width: 180,
      height: 22.5,
      points: [{ x: 30, y: 40 }, { x: 210, y: 62.5 }],
    });
  });

  it("clamps after resizing so a shrunken element remains visible", () => {
    const rectangle = { ...fixtureRect(), x: -50, y: 20, width: 100, height: 20 };

    const transformed = resizeElementWithinBounds(rectangle, { x: -50, y: 20 }, 0.1, 1, 0, { sourceWidth: 100, sourceHeight: 100 });

    expect(transformed).toMatchObject({ x: -9, y: 20, width: 10, height: 20 });
  });

  it("keeps history usable after an opposite-edge transformer attempt", () => {
    const history = createHistoryStore({
      schemaVersion: 2,
      sourcePixelWidth: 100,
      sourcePixelHeight: 100,
      elements: [{ ...fixtureRect(), width: 20, height: 20 }],
      presentation: { type: "none" },
      defaults: {
        color: "#1677FF",
        strokeWidth: 4,
        textSize: 24,
        roughness: 1,
        opacity: 1,
      },
    });

    history.dispatch({
      type: "update",
      element: resizeElementWithinBounds(
        findElement(history.document, "rect-1"),
        { x: 20, y: 20 },
        -0.5,
        1,
        0,
        { sourceWidth: 100, sourceHeight: 100 },
      ),
    });
    history.undo();
    history.redo();

    expect(findElement(history.document, "rect-1").width).toBeGreaterThanOrEqual(0);
  });
});

describe("CanvasPointerController", () => {
  it("routes Shift-drag on a selected element to pan without an annotation move", () => {
    const controller = new CanvasPointerController();

    expect(controller.begin({ shiftKey: true })).toBe("pan");
    expect(controller.shouldDispatchAnnotationDrag()).toBe(false);
    controller.end();

    expect(controller.begin({ shiftKey: false })).toBe("annotation");
    expect(controller.shouldDispatchAnnotationDrag()).toBe(true);
  });

  it("cancels a Shift-pan transformer handle before it can alter the selected node", () => {
    const controller = new CanvasPointerController();
    const transformer = { stopTransform: vi.fn(), forceUpdate: vi.fn() };
    const node = { x: vi.fn(), y: vi.fn(), scaleX: vi.fn(), scaleY: vi.fn(), rotation: vi.fn() };
    const element = fixtureRect();

    controller.begin({ shiftKey: true });
    expect(beginTransformerInteraction(controller, transformer, node, element)).toBe(false);
    expect(transformer.stopTransform).toHaveBeenCalledOnce();
    expect(node.x).toHaveBeenCalledWith(element.x);
    expect(node.y).toHaveBeenCalledWith(element.y);
    expect(node.scaleX).toHaveBeenCalledWith(1);
    expect(node.scaleY).toHaveBeenCalledWith(1);
    expect(node.rotation).toHaveBeenCalledWith(element.rotation);
    expect(transformer.forceUpdate).toHaveBeenCalledOnce();

    controller.end();
    controller.begin({ shiftKey: false });
    expect(beginTransformerInteraction(controller, transformer, node, element)).toBe(true);
    expect(transformer.stopTransform).toHaveBeenCalledOnce();
    expect(node.scaleX).toHaveBeenCalledOnce();
    expect(node.scaleY).toHaveBeenCalledOnce();
  });
});

describe("SelectionController", () => {
  it("shift-click toggles membership without losing the first selection", () => {
    const selection = new SelectionController();

    selection.replace("rect-1");
    selection.toggle("text-1");

    expect(selection.selectedIds).toEqual(["rect-1", "text-1"]);
    selection.toggle("rect-1");
    expect(selection.selectedIds).toEqual(["text-1"]);
  });

  it("rejects empty ids for replacement and toggling", () => {
    const selection = new SelectionController();

    expect(() => selection.replace("")).toThrow("Cannot select an empty element id");
    expect(() => selection.toggle("")).toThrow("Cannot select an empty element id");
  });
});

describe("moveElementsWithinBounds", () => {
  it("clamps one shared delta so every selected element stays inside the source", () => {
    const rectangle = { ...fixtureRect(), x: 0, y: 0, width: 20, height: 20 };
    const text = { ...fixtureText(), x: 70, y: 60, width: 30, height: 40 };

    const moved = moveElementsWithinBounds(
      [rectangle, text],
      { x: 25, y: 30 },
      { sourceWidth: 100, sourceHeight: 100 },
    );

    expect(moved.map(({ x, y }) => ({ x, y }))).toEqual([
      { x: 0, y: 0 },
      { x: 70, y: 60 },
    ]);
  });

  it("moves path points by the same bounded delta as their elements", () => {
    const line = { ...fixtureLine(), x: 10, y: 20, width: 40, height: 30, points: [{ x: 10, y: 20 }, { x: 50, y: 50 }] as [{ x: number; y: number }, { x: number; y: number }] };
    const rectangle = { ...fixtureRect(), x: 50, y: 40, width: 20, height: 20 };

    const moved = moveElementsWithinBounds(
      [line, rectangle],
      { x: 10, y: 12 },
      { sourceWidth: 100, sourceHeight: 100 },
    );

    expect(moved[0]).toMatchObject({
      x: 20,
      y: 32,
      points: [{ x: 20, y: 32 }, { x: 60, y: 62 }],
    });
    expect(moved[1]).toMatchObject({ x: 60, y: 52 });
  });
});
