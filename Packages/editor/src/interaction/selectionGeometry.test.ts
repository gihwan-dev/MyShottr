import { describe, expect, it } from "vitest";

import { allElementFixtures, fixtureLine, fixtureRect } from "../test/fixtures";
import {
  intersectingElementIds,
  isMarqueeGesture,
  rotatedElementBounds,
  unionBounds,
} from "./selectionGeometry";

describe("selection geometry", () => {
  it("rotates rectangle corners around the Konva Group origin and expands its visible stroke", () => {
    const rectangle = {
      ...fixtureRect(),
      x: 100,
      y: 100,
      width: 80,
      height: 20,
      rotation: 45,
      strokeWidth: 8 as const,
    };

    expect(rotatedElementBounds(rectangle)).toEqual({
      x: 81.85786437626905,
      y: 96,
      width: 78.71067811865476,
      height: 78.71067811865476,
    });
  });

  it("selects by rotated AABB intersection instead of containment", () => {
    const rectangle = {
      ...fixtureRect(),
      x: 100,
      y: 100,
      width: 80,
      height: 20,
      rotation: 45,
    };

    expect(intersectingElementIds(
      [rectangle],
      { x: 154, y: 152, width: 8, height: 8 },
    )).toEqual([rectangle.id]);
  });

  it("selects a rectangle through a marquee intersecting only its visible thick stroke", () => {
    const rectangle = {
      ...fixtureRect(),
      x: 100,
      y: 100,
      width: 80,
      height: 20,
      strokeWidth: 8 as const,
    };

    expect(intersectingElementIds(
      [rectangle],
      { x: 97, y: 105, width: 1, height: 1 },
    )).toEqual([rectangle.id]);
  });

  it("derives rotated line bounds from endpoints and expands them by half the stroke", () => {
    const line = {
      ...fixtureLine(),
      x: 15,
      y: 20,
      rotation: 90,
      points: [
        { x: 15, y: 20 },
        { x: 105, y: 65 },
      ] as [{ x: number; y: number }, { x: number; y: number }],
    };

    const bounds = rotatedElementBounds(line);
    expect(bounds.x).toBeCloseTo(-32);
    expect(bounds.y).toBeCloseTo(18);
    expect(bounds.width).toBeCloseTo(49);
    expect(bounds.height).toBeCloseTo(94);
  });

  it("selects an arrow through a rotated arrowhead-only marquee intersection", () => {
    const fixture = allElementFixtures().find((element) => element.type === "arrow");
    if (!fixture) throw new Error("Missing arrow fixture");
    const arrow = {
      ...fixture,
      x: 20,
      y: 50,
      width: 80,
      height: 0,
      rotation: 90,
      points: [
        { x: 20, y: 50 },
        { x: 100, y: 50 },
      ] as [{ x: number; y: number }, { x: number; y: number }],
    };

    expect(intersectingElementIds(
      [arrow],
      { x: 13.5, y: 119, width: 1, height: 1 },
    )).toEqual([arrow.id]);
  });

  it("uses the same rotated primitive when forming selection union bounds", () => {
    const rectangle = {
      ...fixtureRect(),
      x: 100,
      y: 100,
      width: 80,
      height: 20,
      rotation: 45,
    };
    const line = {
      ...fixtureLine(),
      x: 15,
      y: 20,
      points: [
        { x: 15, y: 20 },
        { x: 105, y: 65 },
      ] as [{ x: number; y: number }, { x: number; y: number }],
    };

    expect(unionBounds([rectangle, line])).toEqual({
      x: 13,
      y: 18,
      width: 145.5685424949238,
      height: 154.71067811865476,
    });
    expect(unionBounds([])).toBeUndefined();
  });

  it("converts the three CSS pixel marquee threshold into source space", () => {
    expect(isMarqueeGesture(
      { x: 10, y: 10 },
      { x: 11.49, y: 11.49 },
      2,
    )).toBe(false);
    expect(isMarqueeGesture(
      { x: 10, y: 10 },
      { x: 11.5, y: 10 },
      2,
    )).toBe(true);
    expect(isMarqueeGesture(
      { x: 10, y: 10 },
      { x: 10, y: 12 },
      2,
    )).toBe(true);
  });
});
