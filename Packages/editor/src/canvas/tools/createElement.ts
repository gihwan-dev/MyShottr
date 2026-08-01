import type {
  CreationGesture,
  EditorDefaults,
  EditorDocument,
  EditorElement,
  EditorTool,
  Point,
  TextElement,
} from "../../model/elements";

export type TextDraftPresentation = Pick<
  TextElement,
  "x" | "y" | "width" | "height" | "rotation" | "color" | "fontSize"
>;

export type CreateTextElementInput = {
  point: Point;
  defaults: EditorDefaults;
  text: string;
  bounds: Pick<TextElement, "width" | "height">;
};

export type NonTextCreationTool = Exclude<
  EditorTool,
  "selection" | "text"
>;

export type NonTextEditorElement = Exclude<EditorElement, TextElement>;

export type CreationContext = {
  defaults: EditorDefaults;
  nextNumberMarker: number;
  nextZIndex: number;
  seed: number;
  id?: string;
};

export function createElementId(): string {
  return crypto.randomUUID();
}

export function createTextDraftPresentation(
  point: Point,
  defaults: EditorDefaults,
): TextDraftPresentation {
  return {
    x: point.x,
    y: point.y,
    width: 160,
    height: 36,
    rotation: 0,
    color: defaults.color,
    fontSize: defaults.textSize,
  };
}

export function createElement(
  tool: NonTextCreationTool,
  gesture: CreationGesture,
  context: CreationContext,
): NonTextEditorElement {
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
        fillColor: context.defaults.rectangleFillColor,
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
        opacity: context.defaults.highlighterOpacity,
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

export function createElementFromDocument(
  document: EditorDocument,
  tool: NonTextCreationTool,
  gesture: CreationGesture,
  id?: string,
): NonTextEditorElement {
  return createElement(tool, gesture, creationContextFor(document, id));
}

export function createTextElementFromDocument(
  document: EditorDocument,
  input: CreateTextElementInput,
): TextElement {
  const context = creationContextFor(
    document,
    undefined,
    input.defaults,
  );
  assertCreationContext(context);
  const presentation = createTextDraftPresentation(
    input.point,
    input.defaults,
  );
  return {
    id: context.id ?? createElementId(),
    type: "text",
    x: presentation.x,
    y: presentation.y,
    ...input.bounds,
    rotation: presentation.rotation,
    opacity: input.defaults.opacity,
    zIndex: context.nextZIndex,
    seed: context.seed,
    text: input.text,
    color: presentation.color,
    fontSize: presentation.fontSize,
  };
}

function creationContextFor(
  document: EditorDocument,
  id?: string,
  defaults: EditorDefaults = document.defaults,
): CreationContext {
  return {
    defaults,
    nextNumberMarker: Math.max(
      0,
      ...document.elements
        .filter((candidate) => candidate.type === "numberMarker")
        .map((candidate) => candidate.number),
    ) + 1,
    nextZIndex: Math.max(
      -1,
      ...document.elements.map((candidate) => candidate.zIndex),
    ) + 1,
    seed: Math.max(
      0,
      ...document.elements.map((candidate) => candidate.seed),
    ) + 1,
    id,
  };
}

function createBase(
  tool: NonTextCreationTool,
  gesture: CreationGesture,
  context: CreationContext,
) {
  const bounds = boundsFor(tool, gesture);
  return {
    id: context.id ?? createElementId(),
    ...bounds,
    rotation: 0,
    opacity: context.defaults.opacity,
    zIndex: context.nextZIndex,
    seed: context.seed,
  };
}

function boundsFor(
  tool: NonTextCreationTool,
  gesture: CreationGesture,
) {
  if (tool === "rectangle" || tool === "arrow" || tool === "line" || tool === "blur" || tool === "redaction") {
    assertBoxGesture(gesture, tool);
    return boxBounds(gesture.start, gesture.end);
  }
  if (tool === "numberMarker") {
    assertPointGesture(gesture, tool);
    return { x: gesture.point.x, y: gesture.point.y, width: 32, height: 32 };
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
