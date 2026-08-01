import { describe, expect, it } from "vitest";

import {
  constrainSquare,
  constrainToNearest45Degrees,
} from "./geometry";

describe("interaction geometry", () => {
  it.each([
    [{ x: 10, y: 10 }, { x: 40, y: 30 }, { x: 40, y: 40 }],
    [{ x: 10, y: 10 }, { x: -20, y: 30 }, { x: -20, y: 40 }],
    [{ x: 10, y: 10 }, { x: 30, y: -40 }, { x: 60, y: -40 }],
  ] as const)(
    "constrains rectangle endpoints to a square in the original drag quadrant",
    (start, end, expected) => {
      expect(constrainSquare(start, end)).toEqual(expected);
    },
  );

  it.each([
    [{ x: 0, y: 0 }, { x: 10, y: 3 }, 0],
    [{ x: 0, y: 0 }, { x: 8, y: 7 }, 45],
    [{ x: 5, y: 5 }, { x: 2, y: 15 }, 90],
    [{ x: 0, y: 0 }, { x: -9, y: -7 }, -135],
  ] as const)(
    "constrains line endpoints to the nearest 45-degree angle",
    (start, end, expectedDegrees) => {
      const constrained = constrainToNearest45Degrees(start, end);
      const angle = Math.atan2(
        constrained.y - start.y,
        constrained.x - start.x,
      ) * 180 / Math.PI;
      expect(angle).toBeCloseTo(expectedDegrees);
      expect(Math.hypot(
        constrained.x - start.x,
        constrained.y - start.y,
      )).toBeCloseTo(Math.hypot(end.x - start.x, end.y - start.y));
    },
  );
});
