import type { EditorTool } from "../../model/elements";

export const shortcuts = {
  select: "v",
  rectangle: "r",
  arrow: "a",
  line: "l",
  text: "t",
  freehand: "p",
  highlighter: "h",
  blur: "b",
  redaction: "x",
  numberMarker: "n",
  delete: ["Backspace", "Delete"],
  duplicate: "Meta+d",
  bringForward: "Meta+]",
  sendBackward: "Meta+[",
  undo: "Meta+z",
  redo: ["Meta+Shift+z", "Meta+y"],
} as const;

export type KeyboardCommand =
  | EditorTool
  | "delete"
  | "duplicate"
  | "bringForward"
  | "sendBackward"
  | "undo"
  | "redo";

export function keyboardCommandFor(event: KeyboardEvent): KeyboardCommand | undefined {
  if (event.metaKey) {
    if (event.key === "]") return "bringForward";
    if (event.key === "[") return "sendBackward";
    if (event.key.toLowerCase() === "d") return "duplicate";
    if (event.key.toLowerCase() === "z" && event.shiftKey) return "redo";
    if (event.key.toLowerCase() === "z") return "undo";
    if (event.key.toLowerCase() === "y") return "redo";
    return undefined;
  }
  if (event.key === "Backspace" || event.key === "Delete") return "delete";
  if (event.ctrlKey || event.altKey || event.shiftKey) return undefined;

  switch (event.key.toLowerCase()) {
    case "v": return "selection";
    case "r": return "rectangle";
    case "a": return "arrow";
    case "l": return "line";
    case "t": return "text";
    case "p": return "freehand";
    case "h": return "highlighter";
    case "b": return "blur";
    case "x": return "redaction";
    case "n": return "numberMarker";
    default: return undefined;
  }
}

export function isTextEntryTarget(target: EventTarget | null): boolean {
  return target instanceof HTMLInputElement || target instanceof HTMLTextAreaElement || target instanceof HTMLSelectElement;
}
