import type { EditorDefaults, EditorElement, EditorTool, PaletteColor } from "../model/elements";

const colors: PaletteColor[] = ["#000000", "#FF4D4F", "#1677FF", "#FADB14"];
const strokeWidths: EditorDefaults["strokeWidth"][] = [2, 4, 8];
const textSizes: EditorDefaults["textSize"][] = [16, 24, 36];
const roughnesses: EditorDefaults["roughness"][] = [0, 1, 2];
const opacities: EditorDefaults["opacity"][] = [0.25, 0.5, 0.75, 1];
const highlighterOpacities: EditorDefaults["opacity"][] = [0.25, 0.5];

export function ContextStylePalette({
  tool,
  defaults,
  selectedElements,
  onDefaultsChange,
  onElementsChange,
  fillColor,
  onFillChange,
}: {
  tool: EditorTool;
  defaults: EditorDefaults;
  selectedElements: EditorElement[];
  onDefaultsChange: (defaults: EditorDefaults) => void;
  onElementsChange: (elements: EditorElement[]) => void;
  fillColor?: PaletteColor | null;
  onFillChange?: (color: PaletteColor | null) => void;
}) {
  const isSelection = selectedElements.length > 0;
  const setDefault = <K extends keyof EditorDefaults>(key: K, value: EditorDefaults[K]) => {
    onDefaultsChange({ ...defaults, [key]: value });
  };
  const apply = (change: (element: EditorElement) => EditorElement) => {
    onElementsChange(selectedElements.map(change));
  };

  const defaultShowStroke = tool === "rectangle" || tool === "arrow" || tool === "line" || tool === "freehand";
  const defaultShowFill = tool === "rectangle";
  const defaultShowRoughness = tool === "rectangle" || tool === "arrow" || tool === "line";
  const defaultShowTextSize = tool === "text";
  const defaultShowOpacity = tool !== "redaction";
  if (!isSelection && (tool === "selection" || tool === "blur")) return null;

  const showColor = isSelection ? selectedElements.some(supportsColor) : true;
  const showStroke = isSelection ? selectedElements.some(supportsStrokeWidth) : defaultShowStroke;
  const showFill = !isSelection && defaultShowFill;
  const showRoughness = isSelection ? selectedElements.some(supportsRoughness) : defaultShowRoughness;
  const showTextSize = isSelection ? selectedElements.some(supportsTextSize) : defaultShowTextSize;
  const showOpacity = isSelection ? selectedElements.some(supportsOpacity) : defaultShowOpacity;
  const opacityValues = isSelection
    ? selectedElements.some((element) => element.type === "highlighter") ? highlighterOpacities : opacities
    : tool === "highlighter" ? highlighterOpacities : opacities;
  const firstColor = selectedElements.find(supportsColor);
  const firstStrokeWidth = selectedElements.find(supportsStrokeWidth);
  const firstRoughness = selectedElements.find(supportsRoughness);
  const firstTextSize = selectedElements.find(supportsTextSize);
  const opacityValue = isSelection
    ? selectedOpacity(selectedElements)
    : opacityValues.includes(defaults.opacity) ? defaults.opacity : "";

  return (
    <section className="context-style-palette" aria-label={`${isSelection ? "selection" : tool} style controls`}>
      {showColor && (
        <label>
          Color
          <select
            aria-label="Color"
            value={isSelection ? colorOf(firstColor!) : defaults.color}
            disabled={!isSelection && tool === "redaction"}
            onChange={(event) => isSelection
              ? apply((element) => recolor(element, event.target.value as PaletteColor))
              : setDefault("color", event.target.value as PaletteColor)}
          >
            {colors.map((color) => <option key={color} value={color}>{color}</option>)}
          </select>
        </label>
      )}
      {showStroke && (
        <label>
          Stroke width
          <select
            aria-label="Stroke width"
            value={isSelection ? firstStrokeWidth!.strokeWidth : defaults.strokeWidth}
            onChange={(event) => isSelection
              ? apply((element) => setStrokeWidth(element, Number(event.target.value) as EditorDefaults["strokeWidth"]))
              : setDefault("strokeWidth", Number(event.target.value) as EditorDefaults["strokeWidth"])}
          >
            {strokeWidths.map((width) => <option key={width} value={width}>{width}</option>)}
          </select>
        </label>
      )}
      {showFill && onFillChange && (
        <label>
          Fill
          <select aria-label="Fill" value={fillColor ?? "none"} onChange={(event) => onFillChange(parseFillColor(event.target.value))}>
            <option value="none">None</option>
            {colors.map((color) => <option key={color} value={color}>{color}</option>)}
          </select>
        </label>
      )}
      {showRoughness && (
        <label>
          Roughness
          <select
            aria-label="Roughness"
            value={isSelection ? firstRoughness!.roughness : defaults.roughness}
            onChange={(event) => isSelection
              ? apply((element) => setRoughness(element, Number(event.target.value) as EditorDefaults["roughness"]))
              : setDefault("roughness", Number(event.target.value) as EditorDefaults["roughness"])}
          >
            {roughnesses.map((roughness) => <option key={roughness} value={roughness}>{roughness}</option>)}
          </select>
        </label>
      )}
      {showTextSize && (
        <label>
          Text size
          <select
            aria-label="Text size"
            value={isSelection ? firstTextSize!.fontSize : defaults.textSize}
            onChange={(event) => isSelection
              ? apply((element) => setTextSize(element, Number(event.target.value) as EditorDefaults["textSize"]))
              : setDefault("textSize", Number(event.target.value) as EditorDefaults["textSize"])}
          >
            {textSizes.map((size) => <option key={size} value={size}>{size}</option>)}
          </select>
        </label>
      )}
      {showOpacity && (
        <label>
          Opacity
          <select
            aria-label="Opacity"
            value={opacityValue}
            onChange={(event) => {
              const opacity = parseOpacity(event.target.value, opacityValues);
              if (isSelection) apply((element) => setOpacity(element, opacity));
              else setDefault("opacity", opacity);
            }}
          >
            {opacityValue === "" && <option value="" disabled>Mixed</option>}
            {opacityValues.map((opacity) => <option key={opacity} value={opacity}>{opacity}</option>)}
          </select>
        </label>
      )}
    </section>
  );
}

function supportsColor(element: EditorElement): element is Exclude<EditorElement, { type: "blur" | "redaction" }> {
  return element.type !== "blur" && element.type !== "redaction";
}

function colorOf(element: Exclude<EditorElement, { type: "blur" | "redaction" }>): PaletteColor {
  return element.type === "rectangle" || element.type === "arrow" || element.type === "line"
    ? element.strokeColor
    : element.color;
}

function recolor(element: EditorElement, color: PaletteColor): EditorElement {
  switch (element.type) {
    case "rectangle":
    case "arrow":
    case "line":
      return { ...element, strokeColor: color };
    case "text":
    case "freehand":
    case "highlighter":
    case "numberMarker":
      return { ...element, color };
    case "blur":
    case "redaction":
      return element;
  }
}

function supportsStrokeWidth(element: EditorElement): element is Extract<EditorElement, { type: "rectangle" | "arrow" | "line" | "freehand" }> {
  return element.type === "rectangle" || element.type === "arrow" || element.type === "line" || element.type === "freehand";
}

function setStrokeWidth(element: EditorElement, strokeWidth: EditorDefaults["strokeWidth"]): EditorElement {
  return supportsStrokeWidth(element) ? { ...element, strokeWidth } : element;
}

function supportsRoughness(element: EditorElement): element is Extract<EditorElement, { type: "rectangle" | "arrow" | "line" }> {
  return element.type === "rectangle" || element.type === "arrow" || element.type === "line";
}

function setRoughness(element: EditorElement, roughness: EditorDefaults["roughness"]): EditorElement {
  return supportsRoughness(element) ? { ...element, roughness } : element;
}

function supportsTextSize(element: EditorElement): element is Extract<EditorElement, { type: "text" }> {
  return element.type === "text";
}

function setTextSize(element: EditorElement, fontSize: EditorDefaults["textSize"]): EditorElement {
  return supportsTextSize(element) ? { ...element, fontSize } : element;
}

function supportsOpacity(element: EditorElement): element is Exclude<EditorElement, { type: "blur" | "redaction" }> {
  return element.type !== "blur" && element.type !== "redaction";
}

function setOpacity(element: EditorElement, opacity: EditorDefaults["opacity"]): EditorElement {
  if (!supportsOpacity(element)) return element;
  if (element.type === "highlighter") {
    if (opacity !== 0.25 && opacity !== 0.5) {
      throw new Error(`Unsupported highlighter opacity: ${opacity}`);
    }
    return { ...element, opacity };
  }
  return { ...element, opacity };
}

function selectedOpacity(elements: EditorElement[]): EditorDefaults["opacity"] | "" {
  const values = new Set(elements.filter(supportsOpacity).map((element) => element.opacity));
  return values.size === 1 ? [...values][0]! : "";
}

function parseOpacity(value: string, allowed: EditorDefaults["opacity"][]): EditorDefaults["opacity"] {
  const opacity = Number(value) as EditorDefaults["opacity"];
  if (!allowed.includes(opacity)) {
    throw new Error(`Unsupported opacity: ${value}`);
  }
  return opacity;
}

function parseFillColor(value: string): PaletteColor | null {
  if (value === "none") return null;
  if (colors.includes(value as PaletteColor)) return value as PaletteColor;
  throw new Error(`Unsupported fill color: ${value}`);
}
