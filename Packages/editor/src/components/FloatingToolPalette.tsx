import type { EditorTool } from "../model/elements";

const tools: Array<{ tool: EditorTool; label: string }> = [
  { tool: "selection", label: "Select" },
  { tool: "rectangle", label: "Rectangle" },
  { tool: "arrow", label: "Arrow" },
  { tool: "line", label: "Line" },
  { tool: "text", label: "Text" },
  { tool: "freehand", label: "Freehand" },
  { tool: "highlighter", label: "Highlighter" },
  { tool: "blur", label: "Blur" },
  { tool: "redaction", label: "Redaction" },
  { tool: "numberMarker", label: "Number marker" },
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
          aria-pressed={tool === entry.tool}
          onClick={() => onSelect(entry.tool)}
        >
          {entry.label}
        </button>
      ))}
    </nav>
  );
}
