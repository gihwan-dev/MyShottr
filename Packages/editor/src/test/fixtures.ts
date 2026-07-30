import type {
  ArrowElement,
  CreationGesture,
  EditorDocument,
  EditorElement,
  EditorTool,
  FreehandElement,
  HighlighterElement,
  LineElement,
  NumberMarkerElement,
  RectangleElement,
  RedactionElement,
  TextElement,
} from "../model/elements";

const defaults = {
  color: "#1677FF",
  strokeWidth: 4,
  textSize: 24,
  roughness: 1,
  opacity: 1,
} as const;

export function fixtureRect(): RectangleElement {
  return {
    id: "rect-1",
    type: "rectangle",
    x: 0,
    y: 0,
    width: 120,
    height: 80,
    rotation: 0,
    opacity: 1,
    zIndex: 0,
    seed: 101,
    strokeColor: "#1677FF",
    strokeWidth: 4,
    fillColor: null,
    roughness: 1,
  };
}

export function fixtureLine(): LineElement {
  return {
    id: "line-1",
    type: "line",
    x: 15,
    y: 20,
    width: 90,
    height: 45,
    rotation: 0,
    opacity: 1,
    zIndex: 2,
    seed: 108,
    points: [{ x: 15, y: 20 }, { x: 105, y: 65 }],
    strokeColor: "#1677FF",
    strokeWidth: 4,
    roughness: 1,
  };
}

export function allElementFixtures(): EditorElement[] {
  const arrow: ArrowElement = {
    id: "arrow-1",
    type: "arrow",
    x: 20,
    y: 25,
    width: 100,
    height: 40,
    rotation: 0,
    opacity: 1,
    zIndex: 1,
    seed: 102,
    points: [{ x: 20, y: 25 }, { x: 120, y: 65 }],
    strokeColor: "#FF4D4F",
    strokeWidth: 2,
    roughness: 2,
  };
  const text: TextElement = {
    id: "text-1",
    type: "text",
    x: 40,
    y: 50,
    width: 180,
    height: 36,
    rotation: 0,
    opacity: 1,
    zIndex: 3,
    seed: 103,
    text: "Annotate this",
    color: "#000000",
    fontSize: 24,
  };
  const freehand: FreehandElement = {
    id: "freehand-1",
    type: "freehand",
    x: 60,
    y: 80,
    width: 100,
    height: 45,
    rotation: 0,
    opacity: 1,
    zIndex: 4,
    seed: 104,
    points: [{ x: 60, y: 80 }, { x: 100, y: 100 }, { x: 160, y: 125 }],
    color: "#FADB14",
    strokeWidth: 8,
  };
  const highlighter: HighlighterElement = {
    id: "highlighter-1",
    type: "highlighter",
    x: 80,
    y: 140,
    width: 120,
    height: 30,
    rotation: 0,
    opacity: 0.25,
    zIndex: 5,
    seed: 105,
    points: [{ x: 80, y: 140 }, { x: 200, y: 170 }],
    color: "#FADB14",
    strokeWidth: 8,
  };
  const redaction: RedactionElement = {
    id: "redaction-1",
    type: "redaction",
    x: 100,
    y: 180,
    width: 160,
    height: 40,
    rotation: 0,
    opacity: 1,
    zIndex: 6,
    seed: 106,
    color: "#000000",
  };
  const numberMarker: NumberMarkerElement = {
    id: "marker-1",
    type: "numberMarker",
    x: 220,
    y: 240,
    width: 32,
    height: 32,
    rotation: 0,
    opacity: 1,
    zIndex: 7,
    seed: 107,
    number: 1,
    color: "#FF4D4F",
  };

  return [fixtureRect(), arrow, fixtureLine(), text, freehand, highlighter, redaction, numberMarker];
}

export function fixtureDocument(
  overrides: Partial<EditorDocument> = {},
): EditorDocument {
  return {
    schemaVersion: 2,
    sourcePixelWidth: 1440,
    sourcePixelHeight: 900,
    elements: [fixtureRect()],
    presentation: { type: "none" },
    defaults,
    ...overrides,
  };
}

export function creationGesture(
  tool: Exclude<EditorTool, "selection">,
): CreationGesture {
  switch (tool) {
    case "rectangle":
    case "arrow":
    case "line":
    case "redaction":
      return { kind: "box", start: { x: 10, y: 20 }, end: { x: 110, y: 70 } };
    case "freehand":
    case "highlighter":
      return { kind: "path", points: [{ x: 10, y: 20 }, { x: 60, y: 45 }] };
    case "text":
    case "numberMarker":
      return { kind: "point", point: { x: 10, y: 20 } };
  }
}
