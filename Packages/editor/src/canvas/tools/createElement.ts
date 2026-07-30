import type {
  CreationGesture,
  EditorDefaults,
  EditorDocument,
  EditorElement,
  EditorTool,
  Point,
} from "../../model/elements";
import { moveElementsWithinBounds } from "../SelectionController";

export type CreationContext = {
  defaults: EditorDefaults;
  nextNumberMarker: number;
  nextZIndex: number;
  seed: number;
};

export function createElementId(): string {
  return crypto.randomUUID();
}

export function createDuplicateElements(
  document: Pick<EditorDocument, "elements" | "sourcePixelWidth" | "sourcePixelHeight">,
  sources: EditorElement[],
): EditorElement[] {
  if (sources.length === 0) return [];
  const nextSeed = Math.max(0, ...document.elements.map((element) => element.seed)) + 1;
  const nextZIndex = Math.max(-1, ...document.elements.map((element) => element.zIndex)) + 1;
  const existingIds = new Set(document.elements.map((element) => element.id));
  const duplicateIds = sources.map(() => createElementId());
  if (
    new Set(duplicateIds).size !== duplicateIds.length
    || duplicateIds.some((id) => existingIds.has(id))
  ) {
    throw new Error("Duplicate element ids must be unique");
  }
  const offsets = moveElementsWithinBounds(
    sources,
    { x: 12, y: 12 },
    { sourceWidth: document.sourcePixelWidth, sourceHeight: document.sourcePixelHeight },
  );
  return offsets.map((offset, index) => ({
    ...offset,
    id: duplicateIds[index],
    seed: nextSeed + index,
    zIndex: nextZIndex + index,
  }));
}

export function createElement(
  tool: Exclude<EditorTool, "selection">,
  gesture: CreationGesture,
  context: CreationContext,
): EditorElement {
  assertCreationContext(context);
  const base = createBase(tool, gesture, context);

  switch (tool) {
    case "rectangle":
      assertBoxGesture(gesture, tool);
      return {
        ...base,
        type: "rectangle",
        strokeColor: context.defaults.color,
        strokeWidth: context.defaults.strokeWidth,
        fillColor: null,
        roughness: context.defaults.roughness,
      };
    case "arrow":
      assertBoxGesture(gesture, tool);
      return {
        ...base,
        type: "arrow",
        points: [gesture.start, gesture.end],
        strokeColor: context.defaults.color,
        strokeWidth: context.defaults.strokeWidth,
        roughness: context.defaults.roughness,
      };
    case "line":
      assertBoxGesture(gesture, tool);
      return {
        ...base,
        type: "line",
        points: [gesture.start, gesture.end],
        strokeColor: context.defaults.color,
        strokeWidth: context.defaults.strokeWidth,
        roughness: context.defaults.roughness,
      };
    case "text":
      assertPointGesture(gesture, tool);
      return {
        ...base,
        type: "text",
        text: "Text",
        color: context.defaults.color,
        fontSize: context.defaults.textSize,
      };
    case "freehand":
      assertPathGesture(gesture, tool);
      return {
        ...base,
        type: "freehand",
        points: gesture.points,
        color: context.defaults.color,
        strokeWidth: context.defaults.strokeWidth,
      };
    case "highlighter":
      assertPathGesture(gesture, tool);
      return {
        ...base,
        type: "highlighter",
        points: gesture.points,
        color: context.defaults.color,
        strokeWidth: 8,
        opacity: highlighterOpacity(context.defaults.opacity),
      };
    case "blur":
      assertBoxGesture(gesture, tool);
      return { ...base, type: "blur", radius: 12, opacity: 1, rotation: 0 };
    case "redaction":
      assertBoxGesture(gesture, tool);
      return { ...base, type: "redaction", color: "#000000", opacity: 1 };
    case "numberMarker":
      assertPointGesture(gesture, tool);
      return {
        ...base,
        type: "numberMarker",
        number: context.nextNumberMarker,
        color: context.defaults.color,
      };
  }
}

function createBase(
  tool: Exclude<EditorTool, "selection">,
  gesture: CreationGesture,
  context: CreationContext,
) {
  const bounds = boundsFor(tool, gesture);
  return {
    id: createElementId(),
    ...bounds,
    rotation: 0,
    opacity: context.defaults.opacity,
    zIndex: context.nextZIndex,
    seed: context.seed,
  };
}

function boundsFor(tool: Exclude<EditorTool, "selection">, gesture: CreationGesture) {
  if (tool === "rectangle" || tool === "arrow" || tool === "line" || tool === "blur" || tool === "redaction") {
    assertBoxGesture(gesture, tool);
    return boxBounds(gesture.start, gesture.end);
  }
  if (tool === "text" || tool === "numberMarker") {
    assertPointGesture(gesture, tool);
    return tool === "text"
      ? { x: gesture.point.x, y: gesture.point.y, width: 160, height: 36 }
      : { x: gesture.point.x, y: gesture.point.y, width: 32, height: 32 };
  }
  assertPathGesture(gesture, tool);
  return pointsBounds(gesture.points);
}

function boxBounds(start: Point, end: Point) {
  return {
    x: Math.min(start.x, end.x),
    y: Math.min(start.y, end.y),
    width: Math.abs(end.x - start.x),
    height: Math.abs(end.y - start.y),
  };
}

function pointsBounds(points: Point[]) {
  if (points.length === 0) {
    throw new Error("Path creation requires at least one point");
  }
  const xValues = points.map((point) => point.x);
  const yValues = points.map((point) => point.y);
  const x = Math.min(...xValues);
  const y = Math.min(...yValues);
  return { x, y, width: Math.max(...xValues) - x, height: Math.max(...yValues) - y };
}

function highlighterOpacity(opacity: EditorDefaults["opacity"]): 0.25 | 0.5 {
  return opacity === 0.25 || opacity === 0.5 ? opacity : 0.5;
}

function assertCreationContext(context: CreationContext): void {
  [context.nextNumberMarker, context.nextZIndex, context.seed].forEach((value) => {
    if (!Number.isFinite(value)) {
      throw new Error("Creation context values must be finite");
    }
  });
}

function assertBoxGesture(gesture: CreationGesture, tool: string): asserts gesture is Extract<CreationGesture, { kind: "box" }> {
  if (gesture.kind !== "box") {
    throw new Error(`${tool} requires a box gesture`);
  }
}

function assertPathGesture(gesture: CreationGesture, tool: string): asserts gesture is Extract<CreationGesture, { kind: "path" }> {
  if (gesture.kind !== "path" || gesture.points.length === 0) {
    throw new Error(`${tool} requires a non-empty path gesture`);
  }
}

function assertPointGesture(gesture: CreationGesture, tool: string): asserts gesture is Extract<CreationGesture, { kind: "point" }> {
  if (gesture.kind !== "point") {
    throw new Error(`${tool} requires a point gesture`);
  }
}
