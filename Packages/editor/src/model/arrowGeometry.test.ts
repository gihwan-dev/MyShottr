import { describe, expect, it } from "vitest";

import type { ArrowElement } from "./elements";
import { arrowSegments } from "./arrowGeometry";

describe("arrowSegments", () => {
  it("returns the rendered shaft and both 30-degree arrowhead legs", () => {
    const arrow = {
      points: [{ x: 20, y: 40 }, { x: 80, y: 40 }],
      strokeWidth: 8,
    } satisfies Pick<ArrowElement, "points" | "strokeWidth">;

    const segments = arrowSegments(arrow);

    expect(segments[0]).toEqual([
      { x: 20, y: 40 },
      { x: 80, y: 40 },
    ]);
    expect(segments[1][0]).toEqual({ x: 80, y: 40 });
    expect(segments[1][1].x).toBeCloseTo(52.287187078897965);
    expect(segments[1][1].y).toBeCloseTo(56);
    expect(segments[2][0]).toEqual({ x: 80, y: 40 });
    expect(segments[2][1].x).toBeCloseTo(52.287187078897965);
    expect(segments[2][1].y).toBeCloseTo(24);
  });
});
