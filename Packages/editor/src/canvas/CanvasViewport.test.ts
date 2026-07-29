import { describe, expect, it } from "vitest";
import { CanvasViewport } from "./CanvasViewport";

describe("CanvasViewport", () => {
  it("maps pointer coordinates to source pixels at any zoom", () => {
    const viewport = new CanvasViewport({ sourceWidth: 3000, sourceHeight: 2000 });
    viewport.setTransform({ zoom: 0.5, panX: 100, panY: 50 });

    expect(viewport.toSourcePoint({ x: 600, y: 450 })).toEqual({ x: 1000, y: 800 });
  });

  it("updates pan used by source-coordinate conversion", () => {
    const viewport = new CanvasViewport({ sourceWidth: 3000, sourceHeight: 2000 });
    viewport.setTransform({ zoom: 2, panX: 10, panY: 20 });

    viewport.panBy({ x: 90, y: -40 });

    expect(viewport.getTransform()).toEqual({ zoom: 2, panX: 100, panY: -20 });
    expect(viewport.toSourcePoint({ x: 500, y: 180 })).toEqual({ x: 200, y: 100 });
  });
});
