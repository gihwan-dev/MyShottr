import { describe, expect, it, vi } from "vitest";
import { allElementFixtures, fixtureRect } from "../test/fixtures";
import { beginTransformerInteraction } from "./EditorCanvas";
import { CanvasPointerController, duplicateElementWithinBounds, resizeElementWithinBounds } from "./SelectionController";

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

  it("clamps after resizing so a shrunken element remains visible", () => {
    const rectangle = { ...fixtureRect(), x: -50, y: 20, width: 100, height: 20 };

    const transformed = resizeElementWithinBounds(rectangle, { x: -50, y: 20 }, 0.1, 1, 0, { sourceWidth: 100, sourceHeight: 100 });

    expect(transformed).toMatchObject({ x: -9, y: 20, width: 10, height: 20 });
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
