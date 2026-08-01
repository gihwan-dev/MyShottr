import type { EditorElement, Point } from "../model/elements";
import { arrowSegments } from "../model/arrowGeometry";
import type { Rect, SourceBounds } from "../viewport/ViewportController";

const MARQUEE_THRESHOLD_CSS_PX = 3;

export function isMarqueeGesture(
  start: Point,
  end: Point,
  zoom: number,
): boolean {
  if (!Number.isFinite(zoom) || zoom <= 0) {
    throw new Error("Marquee zoom must be a positive finite number");
  }
  const sourceThreshold = MARQUEE_THRESHOLD_CSS_PX / zoom;
  return Math.abs(end.x - start.x) >= sourceThreshold
    || Math.abs(end.y - start.y) >= sourceThreshold;
}

export function marqueeBounds(start: Point, end: Point): Rect {
  return {
    x: Math.min(start.x, end.x),
    y: Math.min(start.y, end.y),
    width: Math.abs(end.x - start.x),
    height: Math.abs(end.y - start.y),
  };
}

export function rotatedElementBounds(element: EditorElement): Rect {
  const points = pointsForBounds(element).map((point) =>
    rotateAroundElementOrigin(element, point),
  );
  const minimumX = Math.min(...points.map((point) => point.x));
  const maximumX = Math.max(...points.map((point) => point.x));
  const minimumY = Math.min(...points.map((point) => point.y));
  const maximumY = Math.max(...points.map((point) => point.y));
  const strokeExpansion = strokeExpansionFor(element);
  return {
    x: minimumX - strokeExpansion,
    y: minimumY - strokeExpansion,
    width: maximumX - minimumX + strokeExpansion * 2,
    height: maximumY - minimumY + strokeExpansion * 2,
  };
}

export function intersectingElementIds(
  elements: readonly EditorElement[],
  marquee: Rect,
): readonly string[] {
  const normalizedMarquee = normalizeRect(marquee);
  return elements
    .filter((element) => intersects(rotatedElementBounds(element), normalizedMarquee))
    .map((element) => element.id);
}

export function unionBounds(
  elements: readonly EditorElement[],
): Rect | undefined {
  if (elements.length === 0) return undefined;
  const bounds = elements.map(rotatedElementBounds);
  const minimumX = Math.min(...bounds.map((rect) => rect.x));
  const maximumX = Math.max(...bounds.map((rect) => rect.x + rect.width));
  const minimumY = Math.min(...bounds.map((rect) => rect.y));
  const maximumY = Math.max(...bounds.map((rect) => rect.y + rect.height));
  return {
    x: minimumX,
    y: minimumY,
    width: maximumX - minimumX,
    height: maximumY - minimumY,
  };
}

export function moveElementsWithinBounds(
  elements: readonly EditorElement[],
  delta: Point,
  bounds: SourceBounds,
): EditorElement[] {
  assertSourceBounds(bounds);
  assertFinite(delta.x, "delta x");
  assertFinite(delta.y, "delta y");
  if (elements.length === 0) {
    throw new Error("Cannot move an empty element selection");
  }

  const renderedBounds = elements.map(rotatedElementBounds);
  const minimumDeltaX = Math.max(...renderedBounds.map((elementBounds) => -elementBounds.x));
  const maximumDeltaX = Math.min(
    ...renderedBounds.map(
      (elementBounds) => bounds.sourceWidth - elementBounds.x - elementBounds.width,
    ),
  );
  const minimumDeltaY = Math.max(...renderedBounds.map((elementBounds) => -elementBounds.y));
  const maximumDeltaY = Math.min(
    ...renderedBounds.map(
      (elementBounds) => bounds.sourceHeight - elementBounds.y - elementBounds.height,
    ),
  );
  const boundedDelta = {
    x: boundedAxisDelta(delta.x, minimumDeltaX, maximumDeltaX),
    y: boundedAxisDelta(delta.y, minimumDeltaY, maximumDeltaY),
  };

  return elements.map((element) => translateElement(element, boundedDelta));
}

function pointsForBounds(element: EditorElement): readonly Point[] {
  switch (element.type) {
    case "arrow":
      return arrowSegments(element).flatMap(([start, end]) => [start, end]);
    case "line":
    case "freehand":
    case "highlighter":
      if (element.points.length === 0) {
        throw new Error(`Cannot derive bounds for empty ${element.type} points`);
      }
      return element.points;
    default:
      return [
        { x: element.x, y: element.y },
        { x: element.x + element.width, y: element.y },
        { x: element.x + element.width, y: element.y + element.height },
        { x: element.x, y: element.y + element.height },
      ];
  }
}

function boundedAxisDelta(
  requestedDelta: number,
  minimumDelta: number,
  maximumDelta: number,
): number {
  if (minimumDelta > maximumDelta) return 0;
  return Math.min(Math.max(requestedDelta, minimumDelta), maximumDelta);
}

function translateElement(element: EditorElement, delta: Point): EditorElement {
  const translate = (point: Point): Point => ({
    x: point.x + delta.x,
    y: point.y + delta.y,
  });
  switch (element.type) {
    case "arrow":
    case "line":
      return {
        ...element,
        x: element.x + delta.x,
        y: element.y + delta.y,
        points: [translate(element.points[0]), translate(element.points[1])],
      };
    case "freehand":
    case "highlighter":
      return {
        ...element,
        x: element.x + delta.x,
        y: element.y + delta.y,
        points: element.points.map(translate),
      };
    default:
      return {
        ...element,
        x: element.x + delta.x,
        y: element.y + delta.y,
      };
  }
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

function rotateAroundElementOrigin(
  element: EditorElement,
  point: Point,
): Point {
  const radians = element.rotation * Math.PI / 180;
  const cosine = Math.cos(radians);
  const sine = Math.sin(radians);
  const localX = point.x - element.x;
  const localY = point.y - element.y;
  return {
    x: element.x + localX * cosine - localY * sine,
    y: element.y + localX * sine + localY * cosine,
  };
}

function strokeExpansionFor(element: EditorElement): number {
  switch (element.type) {
    case "arrow":
    case "line":
    case "freehand":
    case "highlighter":
      return element.strokeWidth / 2;
    default:
      return 0;
  }
}

function normalizeRect(rect: Rect): Rect {
  const x = rect.width < 0 ? rect.x + rect.width : rect.x;
  const y = rect.height < 0 ? rect.y + rect.height : rect.y;
  return {
    x,
    y,
    width: Math.abs(rect.width),
    height: Math.abs(rect.height),
  };
}

function intersects(left: Rect, right: Rect): boolean {
  return left.x <= right.x + right.width
    && left.x + left.width >= right.x
    && left.y <= right.y + right.height
    && left.y + left.height >= right.y;
}
