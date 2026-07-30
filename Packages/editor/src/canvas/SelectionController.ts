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

export class CanvasPointerController {
  private mode: "annotation" | "idle" | "pan" = "idle";

  public begin(event: { shiftKey: boolean }): "annotation" | "pan" {
    this.mode = event.shiftKey ? "pan" : "annotation";
    return this.mode;
  }

  public shouldDispatchAnnotationDrag(): boolean {
    return this.mode === "annotation";
  }

  public end(): void {
    this.mode = "idle";
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
    case "line":
      return { ...element, x, y, points: [translate(element.points[0]), translate(element.points[1])] };
    case "freehand":
    case "highlighter":
      return { ...element, x, y, points: element.points.map(translate) };
    default:
      return { ...element, x, y };
  }
}

export function duplicateElementWithinBounds(
  element: EditorElement,
  targetPosition: Point,
  bounds: SourceBounds,
): EditorElement {
  return moveElementWithinBounds(element, targetPosition, bounds);
}

export function resizeElementWithinBounds(
  element: EditorElement,
  targetPosition: Point,
  scaleX: number,
  scaleY: number,
  rotation: number,
  bounds: SourceBounds,
): EditorElement {
  if (!Number.isFinite(scaleX) || !Number.isFinite(scaleY)) {
    throw new Error("Transform scale must be finite");
  }
  if (!Number.isFinite(rotation)) {
    throw new Error("Transform rotation must be finite");
  }
  assertFinite(targetPosition.x, "target x");
  assertFinite(targetPosition.y, "target y");
  scaleX = Math.max(0, scaleX);
  scaleY = Math.max(0, scaleY);
  const translated = translateElement(element, targetPosition);
  const dimensions = { width: translated.width * scaleX, height: translated.height * scaleY, rotation };
  const resized = (() => {
    switch (translated.type) {
      case "arrow":
      case "line":
        return {
          ...translated,
          ...dimensions,
          points: [scalePoint(translated.points[0], translated, scaleX, scaleY), scalePoint(translated.points[1], translated, scaleX, scaleY)] as [Point, Point],
        };
      case "freehand":
      case "highlighter":
        return { ...translated, ...dimensions, points: translated.points.map((point) => scalePoint(point, translated, scaleX, scaleY)) };
      default:
        return { ...translated, ...dimensions };
    }
  })();

  return moveElementWithinBounds(resized, { x: resized.x, y: resized.y }, bounds);
}

function translateElement(element: EditorElement, targetPosition: Point): EditorElement {
  const deltaX = targetPosition.x - element.x;
  const deltaY = targetPosition.y - element.y;
  const translate = (point: Point): Point => ({ x: point.x + deltaX, y: point.y + deltaY });
  switch (element.type) {
    case "arrow":
    case "line":
      return { ...element, x: targetPosition.x, y: targetPosition.y, points: [translate(element.points[0]), translate(element.points[1])] };
    case "freehand":
    case "highlighter":
      return { ...element, x: targetPosition.x, y: targetPosition.y, points: element.points.map(translate) };
    default:
      return { ...element, x: targetPosition.x, y: targetPosition.y };
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

function scalePoint(point: Point, element: EditorElement, scaleX: number, scaleY: number): Point {
  return {
    x: element.x + (point.x - element.x) * scaleX,
    y: element.y + (point.y - element.y) * scaleY,
  };
}
