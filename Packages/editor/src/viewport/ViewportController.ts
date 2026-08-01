import type { Point } from "../model/elements";

export const MIN_ZOOM = 0.1;
export const MAX_ZOOM = 8;
export const FIT_PADDING = 24;
export const RAIL_REFLOW_DURATION_MS = 160;
export const ZOOM_STEP = 0.1;

export type Size = {
  width: number;
  height: number;
};

export type Rect = Point & Size;

export type SourceBounds = {
  sourceWidth: number;
  sourceHeight: number;
};

export type WorkspaceMetrics = {
  workspace: Size;
  availableRect: Rect;
};

export type ViewportSnapshot = WorkspaceMetrics & {
  zoom: number;
  pan: Point;
};

export class ViewportController {
  private metrics: WorkspaceMetrics;
  private zoom = 1;
  private pan: Point = { x: 0, y: 0 };

  public constructor(
    private readonly source: Size,
    initial: WorkspaceMetrics,
  ) {
    assertSize(source, "source");
    assertMetrics(initial);
    this.metrics = cloneMetrics(initial);
    this.pan = this.clampPan(this.pan, this.zoom);
  }

  public get snapshot(): ViewportSnapshot {
    return {
      ...cloneMetrics(this.metrics),
      zoom: this.zoom,
      pan: { ...this.pan },
    };
  }

  public toSourcePoint(workspacePoint: Point): Point {
    assertPoint(workspacePoint, "workspace point");
    return {
      x: (workspacePoint.x - this.pan.x) / this.zoom,
      y: (workspacePoint.y - this.pan.y) / this.zoom,
    };
  }

  public toWorkspacePoint(sourcePoint: Point): Point {
    assertPoint(sourcePoint, "source point");
    return {
      x: sourcePoint.x * this.zoom + this.pan.x,
      y: sourcePoint.y * this.zoom + this.pan.y,
    };
  }

  public setWorkspace(
    metrics: WorkspaceMetrics,
    options: { preserveCenteredSourcePoint: boolean },
  ): ViewportSnapshot {
    assertMetrics(metrics);
    const centeredSource = options.preserveCenteredSourcePoint
      ? this.toSourcePoint(center(this.metrics.availableRect))
      : undefined;
    this.metrics = cloneMetrics(metrics);
    const proposedPan = centeredSource
      ? {
          x: center(metrics.availableRect).x - centeredSource.x * this.zoom,
          y: center(metrics.availableRect).y - centeredSource.y * this.zoom,
        }
      : this.pan;
    this.pan = this.clampPan(proposedPan, this.zoom);
    return this.snapshot;
  }

  public zoomAt(workspacePoint: Point, zoom: number): ViewportSnapshot {
    assertPoint(workspacePoint, "zoom point");
    assertFinite(zoom, "zoom");
    const sourcePoint = this.toSourcePoint(workspacePoint);
    this.zoom = clamp(zoom, MIN_ZOOM, MAX_ZOOM);
    this.pan = this.clampPan({
      x: workspacePoint.x - sourcePoint.x * this.zoom,
      y: workspacePoint.y - sourcePoint.y * this.zoom,
    }, this.zoom);
    return this.snapshot;
  }

  public zoomIn(): ViewportSnapshot {
    return this.stepZoom(1);
  }

  public zoomOut(): ViewportSnapshot {
    return this.stepZoom(-1);
  }

  public zoomFromWheelAt(workspacePoint: Point, deltaY: number): ViewportSnapshot {
    assertFinite(deltaY, "wheel delta y");
    return this.zoomAt(workspacePoint, this.zoom * Math.exp(-deltaY * 0.001));
  }

  public panBy(delta: Point): ViewportSnapshot {
    assertPoint(delta, "pan delta");
    this.pan = this.clampPan({
      x: this.pan.x + delta.x,
      y: this.pan.y + delta.y,
    }, this.zoom);
    return this.snapshot;
  }

  public set100Percent(): ViewportSnapshot {
    return this.zoomAt(center(this.metrics.availableRect), 1);
  }

  public fitImage(padding = FIT_PADDING): ViewportSnapshot {
    return this.fitBounds({ x: 0, y: 0, ...this.source }, padding, false);
  }

  public fitSelection(bounds: Rect, padding = FIT_PADDING): ViewportSnapshot {
    assertRect(bounds, "selection bounds", true);
    return this.fitBounds(bounds, padding, true);
  }

  private stepZoom(direction: -1 | 1): ViewportSnapshot {
    const next = Math.round((this.zoom + direction * ZOOM_STEP) * 100) / 100;
    return this.zoomAt(center(this.metrics.availableRect), next);
  }

  private fitBounds(
    bounds: Rect,
    padding: number,
    allowDegenerateAxes: boolean,
  ): ViewportSnapshot {
    assertRect(bounds, "fit bounds", allowDegenerateAxes);
    assertFinite(padding, "fit padding");
    if (padding < 0) throw new Error("fit padding must not be negative");
    const fitWidth = this.metrics.availableRect.width - padding * 2;
    const fitHeight = this.metrics.availableRect.height - padding * 2;
    if (fitWidth <= 0 || fitHeight <= 0) {
      throw new Error("fit padding must leave a positive available area");
    }
    this.zoom = clamp(
      Math.min(
        bounds.width === 0 ? Number.POSITIVE_INFINITY : fitWidth / bounds.width,
        bounds.height === 0 ? Number.POSITIVE_INFINITY : fitHeight / bounds.height,
      ),
      MIN_ZOOM,
      MAX_ZOOM,
    );
    const availableCenter = center(this.metrics.availableRect);
    this.pan = this.clampPan({
      x: availableCenter.x - (bounds.x + bounds.width / 2) * this.zoom,
      y: availableCenter.y - (bounds.y + bounds.height / 2) * this.zoom,
    }, this.zoom);
    return this.snapshot;
  }

  private clampPan(proposed: Point, zoom: number): Point {
    return {
      x: clampAxis(
        this.metrics.availableRect.x,
        this.metrics.availableRect.width,
        this.source.width * zoom,
        proposed.x,
      ),
      y: clampAxis(
        this.metrics.availableRect.y,
        this.metrics.availableRect.height,
        this.source.height * zoom,
        proposed.y,
      ),
    };
  }
}

const clampAxis = (
  availableStart: number,
  availableSize: number,
  transformedSize: number,
  proposedPan: number,
): number =>
  transformedSize <= availableSize
    ? availableStart + (availableSize - transformedSize) / 2
    : clamp(
        proposedPan,
        availableStart + availableSize - transformedSize,
        availableStart,
      );

const center = (rect: Rect): Point => ({
  x: rect.x + rect.width / 2,
  y: rect.y + rect.height / 2,
});

const clamp = (value: number, minimum: number, maximum: number): number =>
  Math.min(Math.max(value, minimum), maximum);

function cloneMetrics(metrics: WorkspaceMetrics): WorkspaceMetrics {
  return {
    workspace: { ...metrics.workspace },
    availableRect: { ...metrics.availableRect },
  };
}

function assertMetrics(metrics: WorkspaceMetrics): void {
  assertSize(metrics.workspace, "workspace");
  assertRect(metrics.availableRect, "available rect", false);
  if (
    metrics.availableRect.x < 0
    || metrics.availableRect.y < 0
    || metrics.availableRect.x + metrics.availableRect.width > metrics.workspace.width
    || metrics.availableRect.y + metrics.availableRect.height > metrics.workspace.height
  ) {
    throw new Error("available rect must be inside the workspace");
  }
}

function assertSize(size: Size, name: string): void {
  assertFinite(size.width, `${name} width`);
  assertFinite(size.height, `${name} height`);
  if (size.width <= 0 || size.height <= 0) {
    throw new Error(`${name} dimensions must be greater than zero`);
  }
}

function assertRect(rect: Rect, name: string, allowEmpty: boolean): void {
  assertPoint(rect, name);
  assertFinite(rect.width, `${name} width`);
  assertFinite(rect.height, `${name} height`);
  const minimum = allowEmpty ? 0 : Number.MIN_VALUE;
  if (rect.width < minimum || rect.height < minimum) {
    throw new Error(`${name} dimensions must ${allowEmpty ? "not be negative" : "be greater than zero"}`);
  }
}

function assertPoint(point: Point, name: string): void {
  assertFinite(point.x, `${name} x`);
  assertFinite(point.y, `${name} y`);
}

function assertFinite(value: number, name: string): void {
  if (!Number.isFinite(value)) throw new Error(`${name} must be finite`);
}
