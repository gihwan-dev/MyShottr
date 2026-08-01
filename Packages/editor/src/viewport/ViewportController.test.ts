import { describe, expect, it } from "vitest";

import {
  FIT_PADDING,
  MAX_ZOOM,
  MIN_ZOOM,
  ViewportController,
  type Rect,
} from "./ViewportController";

const WORKSPACE = { width: 1200, height: 800 };
const AVAILABLE_RECT: Rect = { x: 20, y: 40, width: 1160, height: 720 };

const fixtureViewport = () => new ViewportController(
  { width: 1000, height: 600 },
  { workspace: WORKSPACE, availableRect: AVAILABLE_RECT },
);

const center = (rect: Rect) => ({
  x: rect.x + rect.width / 2,
  y: rect.y + rect.height / 2,
});

describe("ViewportController", () => {
  it("keeps the source point under the pointer while zooming", () => {
    const controller = fixtureViewport();
    const pointer = { x: 640, y: 430 };
    const sourceBefore = controller.toSourcePoint(pointer);

    controller.zoomAt(pointer, 2.4);

    const sourceAfter = controller.toSourcePoint(pointer);
    expect(sourceAfter.x).toBeCloseTo(sourceBefore.x);
    expect(sourceAfter.y).toBeCloseTo(sourceBefore.y);
  });

  it("keeps zoom and centers the previous source point after rail reflow", () => {
    const controller = fixtureViewport();
    controller.zoomAt(center(AVAILABLE_RECT), 1.8);
    controller.panBy({ x: -140, y: -70 });
    const before = controller.snapshot;
    const centeredSource = controller.toSourcePoint(center(before.availableRect));

    controller.setWorkspace({
      workspace: WORKSPACE,
      availableRect: { x: 296, y: 76, width: 888, height: 708 },
    }, {
      preserveCenteredSourcePoint: true,
    });

    expect(controller.snapshot.zoom).toBe(before.zoom);
    const sourceAfter = controller.toSourcePoint(
      center(controller.snapshot.availableRect),
    );
    expect(sourceAfter.x).toBeCloseTo(centeredSource.x);
    expect(sourceAfter.y).toBeCloseTo(centeredSource.y);
  });

  it("clamps direct and stepped zoom to 10–800% in 10-point increments", () => {
    const controller = fixtureViewport();

    controller.zoomAt(center(AVAILABLE_RECT), 0.01);
    expect(controller.snapshot.zoom).toBe(MIN_ZOOM);
    controller.zoomOut();
    expect(controller.snapshot.zoom).toBe(MIN_ZOOM);

    controller.set100Percent();
    controller.zoomIn();
    expect(controller.snapshot.zoom).toBe(1.1);
    controller.zoomOut();
    expect(controller.snapshot.zoom).toBe(1);

    controller.zoomAt(center(AVAILABLE_RECT), 99);
    expect(controller.snapshot.zoom).toBe(MAX_ZOOM);
    controller.zoomIn();
    expect(controller.snapshot.zoom).toBe(MAX_ZOOM);
  });

  it("centers a transformed source axis that is smaller than the available axis", () => {
    const controller = new ViewportController(
      { width: 100, height: 50 },
      {
        workspace: { width: 500, height: 400 },
        availableRect: { x: 20, y: 40, width: 460, height: 320 },
      },
    );

    controller.panBy({ x: 300, y: -300 });

    expect(controller.snapshot.pan).toEqual({ x: 200, y: 175 });
  });

  it("clamps panning on a large transformed axis to keep the source covering the available rect", () => {
    const controller = new ViewportController(
      { width: 1000, height: 800 },
      {
        workspace: { width: 520, height: 440 },
        availableRect: { x: 10, y: 20, width: 500, height: 400 },
      },
    );

    controller.panBy({ x: 500, y: 500 });
    expect(controller.snapshot.pan).toEqual({ x: 10, y: 20 });

    controller.panBy({ x: -5000, y: -5000 });
    expect(controller.snapshot.pan).toEqual({ x: -490, y: -380 });
  });

  it("returns to 100% around the center of the available rect", () => {
    const controller = fixtureViewport();
    controller.zoomAt({ x: 640, y: 430 }, 2.4);

    controller.set100Percent();

    expect(controller.snapshot.zoom).toBe(1);
    expect(controller.snapshot.pan).toEqual({ x: 100, y: 100 });
  });

  it("fits the whole image inside 24px padding", () => {
    const controller = fixtureViewport();

    controller.fitImage();

    expect(FIT_PADDING).toBe(24);
    expect(controller.snapshot.zoom).toBeCloseTo(1.112);
    const topLeft = controller.toWorkspacePoint({ x: 0, y: 0 });
    const bottomRight = controller.toWorkspacePoint({ x: 1000, y: 600 });
    expect(topLeft.x).toBeCloseTo(44);
    expect(topLeft.y).toBeCloseTo(66.4);
    expect(bottomRight.x).toBeCloseTo(1156);
    expect(bottomRight.y).toBeCloseTo(733.6);
  });

  it("fits and centers a selection inside 24px padding", () => {
    const controller = fixtureViewport();

    controller.fitSelection({ x: 100, y: 100, width: 200, height: 100 });

    expect(controller.snapshot.zoom).toBeCloseTo(5.56);
    const topLeft = controller.toWorkspacePoint({ x: 100, y: 100 });
    const bottomRight = controller.toWorkspacePoint({ x: 300, y: 200 });
    expect(topLeft.x).toBeCloseTo(44);
    expect(topLeft.y).toBeCloseTo(122);
    expect(bottomRight.x).toBeCloseTo(1156);
    expect(bottomRight.y).toBeCloseTo(678);
  });

  it("fits a vertical line using its nonzero height", () => {
    const controller = fixtureViewport();

    controller.fitSelection({ x: 100, y: 100, width: 0, height: 100 });

    expect(controller.snapshot.zoom).toBeCloseTo(6.72);
    expect(controller.toWorkspacePoint({ x: 100, y: 150 }))
      .toEqual(center(AVAILABLE_RECT));
  });

  it("fits a horizontal line using its nonzero width", () => {
    const controller = fixtureViewport();

    controller.fitSelection({ x: 100, y: 100, width: 200, height: 0 });

    expect(controller.snapshot.zoom).toBeCloseTo(5.56);
    expect(controller.toWorkspacePoint({ x: 200, y: 100 }))
      .toEqual(center(AVAILABLE_RECT));
  });

  it("fits a point selection at maximum zoom and centers it", () => {
    const controller = fixtureViewport();

    controller.fitSelection({ x: 100, y: 100, width: 0, height: 0 });

    expect(controller.snapshot.zoom).toBe(MAX_ZOOM);
    expect(controller.toWorkspacePoint({ x: 100, y: 100 }))
      .toEqual(center(AVAILABLE_RECT));
  });

  it.each([
    { width: 1, height: 1 },
    { width: 1, height: 8 },
    { width: 48, height: 20 },
  ])("reduces fit padding for a $width×$height available rect without throwing", (available) => {
    const metrics = {
      workspace: { ...available },
      availableRect: { x: 0, y: 0, ...available },
    };

    expect(() => new ViewportController({ width: 100, height: 80 }, metrics).fitImage())
      .not.toThrow();

    for (const bounds of [
      { x: 10, y: 20, width: 0, height: 0 },
      { x: 10, y: 20, width: 0, height: 40 },
      { x: 10, y: 20, width: 30, height: 0 },
    ]) {
      const controller = new ViewportController({ width: 100, height: 80 }, metrics);
      expect(() => controller.fitSelection(bounds)).not.toThrow();
      expect(controller.snapshot.zoom).toBeGreaterThanOrEqual(MIN_ZOOM);
      expect(controller.snapshot.zoom).toBeLessThanOrEqual(MAX_ZOOM);
    }
  });
});
