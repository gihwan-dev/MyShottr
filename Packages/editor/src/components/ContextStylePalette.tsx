import type { EditorDefaults, EditorTool, PaletteColor } from "../model/elements";

const colors: PaletteColor[] = ["#000000", "#FF4D4F", "#1677FF", "#FADB14"];
const strokeWidths: EditorDefaults["strokeWidth"][] = [2, 4, 8];
const textSizes: EditorDefaults["textSize"][] = [16, 24, 36];
const roughnesses: EditorDefaults["roughness"][] = [0, 1, 2];
const opacities: EditorDefaults["opacity"][] = [0.25, 0.5, 0.75, 1];

export function ContextStylePalette({ tool, defaults, onChange }: {
  tool: EditorTool;
  defaults: EditorDefaults;
  onChange: (defaults: EditorDefaults) => void;
}) {
  if (tool === "selection") return null;

  const set = <K extends keyof EditorDefaults>(key: K, value: EditorDefaults[K]) => {
    onChange({ ...defaults, [key]: value });
  };
  const showStroke = tool === "rectangle" || tool === "arrow" || tool === "freehand";
  const showFill = tool === "rectangle";
  const showRoughness = tool === "rectangle" || tool === "arrow";
  const showTextSize = tool === "text";
  const showOpacity = tool !== "redaction";
  const visibleOpacity = tool === "highlighter" && defaults.opacity !== 0.25 && defaults.opacity !== 0.5
    ? 0.5
    : defaults.opacity;

  return (
    <section className="context-style-palette" aria-label={`${tool} style controls`}>
      <label>
        Color
        <select aria-label="Color" value={tool === "redaction" ? "#000000" : defaults.color} disabled={tool === "redaction"} onChange={(event) => set("color", event.target.value as PaletteColor)}>
          {colors.map((color) => <option key={color} value={color}>{color}</option>)}
        </select>
      </label>
      {showStroke && (
        <label>
          Stroke width
          <select aria-label="Stroke width" value={defaults.strokeWidth} onChange={(event) => set("strokeWidth", Number(event.target.value) as EditorDefaults["strokeWidth"])}>
            {strokeWidths.map((width) => <option key={width} value={width}>{width}</option>)}
          </select>
        </label>
      )}
      {showFill && (
        <label>
          Fill
          <select aria-label="Fill" defaultValue="none">
            <option value="none">None</option>
            {colors.map((color) => <option key={color} value={color}>{color}</option>)}
          </select>
        </label>
      )}
      {showRoughness && (
        <label>
          Roughness
          <select aria-label="Roughness" value={defaults.roughness} onChange={(event) => set("roughness", Number(event.target.value) as EditorDefaults["roughness"])}>
            {roughnesses.map((roughness) => <option key={roughness} value={roughness}>{roughness}</option>)}
          </select>
        </label>
      )}
      {showTextSize && (
        <label>
          Text size
          <select aria-label="Text size" value={defaults.textSize} onChange={(event) => set("textSize", Number(event.target.value) as EditorDefaults["textSize"])}>
            {textSizes.map((size) => <option key={size} value={size}>{size}</option>)}
          </select>
        </label>
      )}
      {showOpacity && (
        <label>
          Opacity
          <select aria-label="Opacity" value={visibleOpacity} onChange={(event) => set("opacity", Number(event.target.value) as EditorDefaults["opacity"])}>
            {(tool === "highlighter" ? opacities.slice(0, 2) : opacities).map((opacity) => <option key={opacity} value={opacity}>{opacity}</option>)}
          </select>
        </label>
      )}
    </section>
  );
}
