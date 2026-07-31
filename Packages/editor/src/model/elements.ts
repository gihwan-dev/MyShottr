export type Point = { x: number; y: number };

export type PaletteColor = "#000000" | "#FF4D4F" | "#1677FF" | "#FADB14";

export type EditorDefaults = {
  color: PaletteColor;
  strokeWidth: 2 | 4 | 8;
  textSize: 16 | 24 | 36;
  roughness: 0 | 1 | 2;
  opacity: 0.25 | 0.5 | 0.75 | 1;
  rectangleFillColor: PaletteColor | null;
  highlighterOpacity: 0.25 | 0.5;
};

export type ElementBase = {
  id: string;
  x: number;
  y: number;
  width: number;
  height: number;
  rotation: number;
  opacity: 0.25 | 0.5 | 0.75 | 1;
  zIndex: number;
  seed: number;
};

export type RectangleElement = ElementBase & {
  type: "rectangle";
  strokeColor: PaletteColor;
  strokeWidth: 2 | 4 | 8;
  fillColor: PaletteColor | null;
  roughness: 0 | 1 | 2;
};

export type ArrowElement = ElementBase & {
  type: "arrow";
  points: [Point, Point];
  strokeColor: PaletteColor;
  strokeWidth: 2 | 4 | 8;
  roughness: 0 | 1 | 2;
};

export type LineElement = ElementBase & {
  type: "line";
  points: [Point, Point];
  strokeColor: PaletteColor;
  strokeWidth: 2 | 4 | 8;
  roughness: 0 | 1 | 2;
};

export type TextElement = ElementBase & {
  type: "text";
  text: string;
  color: PaletteColor;
  fontSize: 16 | 24 | 36;
};

export type FreehandElement = ElementBase & {
  type: "freehand";
  points: Point[];
  color: PaletteColor;
  strokeWidth: 2 | 4 | 8;
};

export type HighlighterElement = ElementBase & {
  type: "highlighter";
  points: Point[];
  color: PaletteColor;
  strokeWidth: 8;
  opacity: 0.25 | 0.5;
};

export type BlurElement = ElementBase & {
  type: "blur";
  radius: 12;
  rotation: 0;
  opacity: 1;
};

export type RedactionElement = ElementBase & {
  type: "redaction";
  color: "#000000";
  opacity: 1;
};

export type NumberMarkerElement = ElementBase & {
  type: "numberMarker";
  number: number;
  color: PaletteColor;
};

export type EditorElement =
  | RectangleElement
  | ArrowElement
  | LineElement
  | TextElement
  | FreehandElement
  | HighlighterElement
  | BlurElement
  | RedactionElement
  | NumberMarkerElement;

export type EditorTool =
  | "selection"
  | "rectangle"
  | "arrow"
  | "line"
  | "text"
  | "freehand"
  | "highlighter"
  | "blur"
  | "redaction"
  | "numberMarker";

export type CreationGesture =
  | { kind: "box"; start: Point; end: Point }
  | { kind: "path"; points: Point[] }
  | { kind: "point"; point: Point };

export type EditorDocument = {
  schemaVersion: 3;
  sourcePixelWidth: number;
  sourcePixelHeight: number;
  elements: EditorElement[];
  presentation: Presentation;
  defaults: EditorDefaults;
};

export type Presentation = { type: "none" };

export type EditorCommand =
  | { type: "create"; element: EditorElement }
  | { type: "createMany"; elements: EditorElement[] }
  | { type: "update"; element: EditorElement }
  | { type: "updateMany"; elements: EditorElement[] }
  | { type: "delete"; ids: string[] }
  | { type: "reorder"; ids: string[]; direction: "forward" | "backward" };
