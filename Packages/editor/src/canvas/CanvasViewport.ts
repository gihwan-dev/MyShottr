import type { Point } from "../model/elements";

export type CanvasTransform = {
  zoom: number;
  panX: number;
  panY: number;
};

export type SourceBounds = {
  sourceWidth: number;
  sourceHeight: number;
};

export class CanvasViewport {
  private transform: CanvasTransform = { zoom: 1, panX: 0, panY: 0 };

  public constructor(private readonly bounds: SourceBounds) {
    assertPositiveFinite(bounds.sourceWidth, "sourceWidth");
    assertPositiveFinite(bounds.sourceHeight, "sourceHeight");
  }

  public setTransform(transform: CanvasTransform): void {
    assertPositiveFinite(transform.zoom, "zoom");
    assertFinite(transform.panX, "panX");
    assertFinite(transform.panY, "panY");
    this.transform = { ...transform };
  }

  public getTransform(): CanvasTransform {
    return { ...this.transform };
  }

  public toSourcePoint(point: Point): Point {
    assertFinite(point.x, "pointer x");
    assertFinite(point.y, "pointer y");
    return {
      x: (point.x - this.transform.panX) / this.transform.zoom,
      y: (point.y - this.transform.panY) / this.transform.zoom,
    };
  }

  public toCanvasPoint(point: Point): Point {
    assertFinite(point.x, "source x");
    assertFinite(point.y, "source y");
    return {
      x: point.x * this.transform.zoom + this.transform.panX,
      y: point.y * this.transform.zoom + this.transform.panY,
    };
  }
}

function assertFinite(value: number, name: string): void {
  if (!Number.isFinite(value)) {
    throw new Error(`${name} must be finite`);
  }
}

function assertPositiveFinite(value: number, name: string): void {
  assertFinite(value, name);
  if (value <= 0) {
    throw new Error(`${name} must be greater than zero`);
  }
}
