import type { EditorElement, Point } from "../model/elements";
import type { SourceBounds } from "./CanvasViewport";

export class SelectionController {
  private selectedId: string | undefined;

  public select(id: string): void {
    if (id.length === 0) {
      throw new Error("Cannot select an empty element id");
    }
    this.selectedId = id;
  }

  public clear(): void {
    this.selectedId = undefined;
  }

  public get selectedElementId(): string | undefined {
    return this.selectedId;
  }
}

export function moveElementWithinBounds(
  element: EditorElement,
  targetPosition: Point,
  bounds: SourceBounds,
): EditorElement {
  assertSourceBounds(bounds);
  assertFinite(targetPosition.x, "target x");
  assertFinite(targetPosition.y, "target y");

  const x = clampKeepingOnePixelVisible(targetPosition.x, element.width, bounds.sourceWidth);
  const y = clampKeepingOnePixelVisible(targetPosition.y, element.height, bounds.sourceHeight);
  const deltaX = x - element.x;
  const deltaY = y - element.y;
  const translate = (point: Point): Point => ({ x: point.x + deltaX, y: point.y + deltaY });

  switch (element.type) {
    case "arrow":
      return { ...element, x, y, points: [translate(element.points[0]), translate(element.points[1])] };
    case "freehand":
    case "highlighter":
      return { ...element, x, y, points: element.points.map(translate) };
    default:
      return { ...element, x, y };
  }
}

function clampKeepingOnePixelVisible(position: number, size: number, sourceSize: number): number {
  return Math.min(Math.max(position, 1 - size), sourceSize - 1);
}

function assertSourceBounds(bounds: SourceBounds): void {
  if (!Number.isFinite(bounds.sourceWidth) || bounds.sourceWidth <= 0) {
    throw new Error("sourceWidth must be a positive finite number");
  }
  if (!Number.isFinite(bounds.sourceHeight) || bounds.sourceHeight <= 0) {
    throw new Error("sourceHeight must be a positive finite number");
  }
}

function assertFinite(value: number, name: string): void {
  if (!Number.isFinite(value)) {
    throw new Error(`${name} must be finite`);
  }
}
