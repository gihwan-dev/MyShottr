import type { EditorTool } from "../../model/elements";

export type EditorCursor = "default" | "text" | "crosshair" | "grab" | "grabbing";

export function cursorForTool(
  tool: EditorTool,
  viewportPanState: "inactive" | "ready" | "active" = "inactive",
): EditorCursor {
  if (viewportPanState === "active") return "grabbing";
  if (viewportPanState === "ready") return "grab";
  if (tool === "selection") return "default";
  if (tool === "text") return "text";
  return "crosshair";
}
