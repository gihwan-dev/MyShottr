import { describe, expect, it } from "vitest";
import { CanvasViewport } from "./CanvasViewport";

describe("CanvasViewport", () => {
  it("maps pointer coordinates to source pixels at any zoom", () => {
    const viewport = new CanvasViewport({ sourceWidth: 3000, sourceHeight: 2000 });
    viewport.setTransform({ zoom: 0.5, panX: 100, panY: 50 });

    expect(viewport.toSourcePoint({ x: 600, y: 450 })).toEqual({ x: 1000, y: 800 });
  });
});
