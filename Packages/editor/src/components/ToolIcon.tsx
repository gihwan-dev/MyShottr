import type { EditorTool } from "../model/elements";

const paths: Record<EditorTool, string[]> = {
  selection: ["M5 3l13 9-6 2-2 6z"],
  rectangle: ["M4 5h16v14H4z"],
  arrow: ["M5 18 19 6", "m13 0h6v6"],
  line: ["M5 18 19 6"],
  text: ["M5 5h14", "M12 5v14", "M8 19h8"],
  freehand: ["M4 17c4-10 6 4 9-5s4-5 7-5"],
  highlighter: ["m5 15 8-8 4 4-8 8H5z", "M4 21h16"],
  blur: ["M7 7h2M12 7h1M16 7h1M7 12h1M11 12h2M16 12h1M7 17h2M12 17h1M16 17h2"],
  redaction: ["M4 6h16v12H4z", "M7 9h10M7 12h10M7 15h10"],
  numberMarker: ["M12 21a9 9 0 1 0 0-18 9 9 0 0 0 0 18", "M10 9l2-1v8", "M10 16h4"],
};

export function ToolIcon({ tool }: { tool: EditorTool }) {
  return (
    <svg
      viewBox="0 0 24 24"
      width="20"
      height="20"
      fill="none"
      stroke="currentColor"
      strokeWidth="1.8"
      strokeLinecap="round"
      strokeLinejoin="round"
      aria-hidden="true"
    >
      {paths[tool].map((path) => <path key={path} d={path} />)}
    </svg>
  );
}
