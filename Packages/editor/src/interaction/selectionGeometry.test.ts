import { describe, expect, it } from "vitest";

import { fixtureLine, fixtureRect } from "../test/fixtures";
import {
  intersectingElementIds,
  isMarqueeGesture,
  rotatedElementBounds,
  unionBounds,
} from "./selectionGeometry";

describe("selection geometry", () => {
  it("rotates box corners around the rendered Konva Group origin", () => {
    const rectangle = {
      ...fixtureRect(),
      x: 100,
      y: 100,
      width: 80,
      height: 20,
      rotation: 45,
    };

    expect(rotatedElementBounds(rectangle)).toEqual({
      x: 85.85786437626905,
      y: 100,
      width: 70.71067811865476,
      height: 70.71067811865476,
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
      width: 143.5685424949238,
      height: 152.71067811865476,
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
