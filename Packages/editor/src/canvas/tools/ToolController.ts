import type { EditorTool } from "../../model/elements";

export type EditorCursor = "default" | "text" | "crosshair" | "grab" | "grabbing";

export function cursorForTool(
  tool: EditorTool,
  spacePan: "inactive" | "ready" | "active" = "inactive",
): EditorCursor {
  if (spacePan === "active") return "grabbing";
  if (spacePan === "ready") return "grab";
  if (tool === "selection") return "default";
  if (tool === "text") return "text";
  return "crosshair";
}
