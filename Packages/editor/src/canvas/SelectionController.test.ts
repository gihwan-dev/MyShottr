import { describe, expect, it } from "vitest";
import { allElementFixtures, fixtureLine, fixtureRect, fixtureText } from "../test/fixtures";
import {
  duplicateElementWithinBounds,
  moveElementsWithinBounds,
  resizeElementWithinBounds,
  clearSelection,
  replaceSelection,
  toggleSelection,
} from "./SelectionController";
import { createHistoryStore } from "../model/history";
import { findElement } from "../model/reducer";
import { rotatedElementBounds } from "../interaction/selectionGeometry";

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
      schemaVersion: 3,
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
        rectangleFillColor: null,
        highlighterOpacity: 0.5,
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

describe("selection helpers", () => {
  it("shift-click toggles membership without losing the first selection", () => {
    const selected = toggleSelection(replaceSelection("rect-1"), "text-1");

    expect(selected).toEqual(["rect-1", "text-1"]);
    expect(toggleSelection(selected, "rect-1")).toEqual(["text-1"]);
  });

  it("returns new replacement and empty selections without retaining mutable state", () => {
    const selected = replaceSelection("rect-1");

    expect(selected).toEqual(["rect-1"]);
    expect(clearSelection()).toEqual([]);
    expect(selected).toEqual(["rect-1"]);
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

  it("clamps a rotated rectangle by its rendered AABB at the source edge", () => {
    const rectangle = {
      ...fixtureRect(),
      x: 50,
      y: 50,
      width: 40,
      height: 20,
      rotation: 45,
    };

    const [moved] = moveElementsWithinBounds(
      [rectangle],
      { x: 100, y: 100 },
      { sourceWidth: 100, sourceHeight: 100 },
    );

    const renderedBounds = rotatedElementBounds(moved);
    expect(renderedBounds.x + renderedBounds.width).toBeCloseTo(100);
    expect(renderedBounds.y + renderedBounds.height).toBeCloseTo(100);
  });

  it("clamps a rotated stroked line by its endpoint AABB at the source edge", () => {
    const line = {
      ...fixtureLine(),
      x: 60,
      y: 20,
      rotation: 90,
      points: [
        { x: 60, y: 20 },
        { x: 150, y: 65 },
      ] as [{ x: number; y: number }, { x: number; y: number }],
    };

    const [moved] = moveElementsWithinBounds(
      [line],
      { x: -100, y: 100 },
      { sourceWidth: 200, sourceHeight: 200 },
    );

    const renderedBounds = rotatedElementBounds(moved);
    expect(renderedBounds.x).toBeCloseTo(0);
    expect(renderedBounds.y + renderedBounds.height).toBeCloseTo(200);
  });
});
