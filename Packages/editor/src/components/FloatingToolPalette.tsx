import type { EditorTool } from "../model/elements";
import { TOOL_SHORTCUTS } from "../input/shortcutRegistry";
import { ToolIcon } from "./ToolIcon";

export function FloatingToolPalette({ tool, onSelect, interactionLocked = false }: {
  tool: EditorTool;
  onSelect: (tool: EditorTool) => void;
  interactionLocked?: boolean;
}) {
  const preventFocusSteal = (event: { preventDefault: () => void }) => {
    if (interactionLocked) event.preventDefault();
  };

  return (
    <nav className="floating-tool-palette" aria-label="Annotation tools">
      {TOOL_SHORTCUTS.map((entry) => (
        <button
          key={entry.tool}
          type="button"
          aria-label={`${entry.label}, shortcut ${entry.displayKeys[0]}`}
          aria-pressed={tool === entry.tool}
          aria-disabled={interactionLocked}
          aria-describedby={`tool-tip-${entry.tool}`}
          tabIndex={interactionLocked ? -1 : undefined}
          onMouseDown={preventFocusSteal}
          onPointerDown={preventFocusSteal}
          onClick={() => {
            if (!interactionLocked) onSelect(entry.tool);
          }}
        >
          <ToolIcon tool={entry.tool} />
          <kbd aria-hidden="true">{entry.displayKeys[0]}</kbd>
          <span
            className="tool-palette-tooltip"
            role="tooltip"
            id={`tool-tip-${entry.tool}`}
          >
            {entry.label} · {entry.displayKeys[0]}
          </span>
        </button>
      ))}
    </nav>
  );
}
