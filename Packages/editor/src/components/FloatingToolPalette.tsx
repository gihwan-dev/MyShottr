import type { EditorTool } from "../model/elements";
import { ToolIcon } from "./ToolIcon";
import { VisuallyHidden } from "./VisuallyHidden";

const tools: Array<{ tool: EditorTool; label: string; shortcut: string }> = [
  { tool: "selection", label: "Select", shortcut: "v" },
  { tool: "rectangle", label: "Rectangle", shortcut: "r" },
  { tool: "arrow", label: "Arrow", shortcut: "a" },
  { tool: "line", label: "Line", shortcut: "l" },
  { tool: "text", label: "Text", shortcut: "t" },
  { tool: "freehand", label: "Freehand", shortcut: "p" },
  { tool: "highlighter", label: "Highlighter", shortcut: "h" },
  { tool: "blur", label: "Blur", shortcut: "b" },
  { tool: "redaction", label: "Redaction", shortcut: "x" },
  { tool: "numberMarker", label: "Number marker", shortcut: "n" },
];

export function FloatingToolPalette({ tool, onSelect }: {
  tool: EditorTool;
  onSelect: (tool: EditorTool) => void;
}) {
  return (
    <nav className="floating-tool-palette" aria-label="Annotation tools">
      {tools.map((entry) => (
        <button
          key={entry.tool}
          type="button"
          aria-label={`${entry.label} (${entry.shortcut.toUpperCase()})`}
          title={`${entry.label} (${entry.shortcut.toUpperCase()})`}
          aria-pressed={tool === entry.tool}
          onClick={() => onSelect(entry.tool)}
        >
          <ToolIcon tool={entry.tool} />
          <VisuallyHidden>{entry.label}</VisuallyHidden>
        </button>
      ))}
    </nav>
  );
}
