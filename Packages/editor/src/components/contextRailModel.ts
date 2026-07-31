import type {
  EditorDocument,
  EditorElement,
  EditorTool,
  PaletteColor,
} from "../model/elements";

export type RailPropertyKey =
  | "color"
  | "fillColor"
  | "strokeWidth"
  | "roughness"
  | "textSize"
  | "opacity";

export type RailPropertyValueByKey = {
  color: PaletteColor;
  fillColor: PaletteColor | null;
  strokeWidth: 2 | 4 | 8;
  roughness: 0 | 1 | 2;
  textSize: 16 | 24 | 36;
  opacity: 0.25 | 0.5 | 0.75 | 1;
};

export type RailPropertyValue = RailPropertyValueByKey[RailPropertyKey];

export type RailValue<T> =
  | { kind: "single"; value: T }
  | { kind: "mixed" };

export type ContextRailField<K extends RailPropertyKey = RailPropertyKey> = {
  label: string;
  value: RailValue<RailPropertyValueByKey[K]>;
  allowedValues: readonly RailPropertyValueByKey[K][];
};

export type ContextRailFields = {
  [K in RailPropertyKey]?: ContextRailField<K>;
};

export type ContextRailSelectionActions = {
  canBringForward: boolean;
  canSendBackward: boolean;
  canDuplicate: true;
  canDelete: true;
};

export type ContextRailModel =
  | { kind: "hidden" }
  | {
      kind: "defaults";
      title: string;
      fields: ContextRailFields;
      fixedValue?: string;
    }
  | {
      kind: "single" | "multi";
      title: string;
      selectedIds: readonly string[];
      fields: ContextRailFields;
      fixedValue?: string;
      actions: ContextRailSelectionActions;
    };

export const ALL_PROPERTY_KEYS: readonly RailPropertyKey[] = [
  "color",
  "fillColor",
  "strokeWidth",
  "roughness",
  "textSize",
  "opacity",
];

const COLORS = ["#000000", "#FF4D4F", "#1677FF", "#FADB14"] as const;
const FILLS = [null, ...COLORS] as const;
const STROKE_WIDTHS = [2, 4, 8] as const;
const ROUGHNESSES = [0, 1, 2] as const;
const TEXT_SIZES = [16, 24, 36] as const;
const OPACITIES = [0.25, 0.5, 0.75, 1] as const;
const HIGHLIGHTER_OPACITIES = [0.25, 0.5] as const;

const PROPERTY_LABELS: Record<RailPropertyKey, string> = {
  color: "Color",
  fillColor: "Fill",
  strokeWidth: "Stroke width",
  roughness: "Roughness",
  textSize: "Text size",
  opacity: "Opacity",
};

const TYPE_LABELS: Record<EditorElement["type"], string> = {
  rectangle: "Rectangle",
  arrow: "Arrow",
  line: "Line",
  text: "Text",
  freehand: "Freehand",
  highlighter: "Highlighter",
  blur: "Blur",
  redaction: "Redaction",
  numberMarker: "Number Marker",
};

const TOOL_LABELS: Record<Exclude<EditorTool, "selection">, string> = {
  rectangle: "Rectangle",
  arrow: "Arrow",
  line: "Line",
  text: "Text",
  freehand: "Freehand",
  highlighter: "Highlighter",
  blur: "Blur",
  redaction: "Redaction",
  numberMarker: "Number Marker",
};

const TYPE_PROPERTIES: Record<EditorElement["type"], readonly RailPropertyKey[]> = {
  rectangle: ["color", "fillColor", "strokeWidth", "roughness", "opacity"],
  arrow: ["color", "strokeWidth", "roughness", "opacity"],
  line: ["color", "strokeWidth", "roughness", "opacity"],
  text: ["color", "textSize", "opacity"],
  freehand: ["color", "strokeWidth", "opacity"],
  highlighter: ["color", "opacity"],
  blur: [],
  redaction: [],
  numberMarker: ["color", "opacity"],
};

export function deriveContextRailModel({
  tool,
  document,
  selectedIds,
}: {
  tool: EditorTool;
  document: EditorDocument;
  selectedIds: readonly string[];
}): ContextRailModel {
  const selected = resolveSelection(document, selectedIds);
  if (selected.length === 0) {
    if (tool === "selection") return { kind: "hidden" };
    return {
      kind: "defaults",
      title: `New ${TOOL_LABELS[tool]}`,
      fields: defaultFields(tool, document),
      ...fixedValueFor(tool),
    };
  }

  const fields = selectionFields(selected);
  return {
    kind: selected.length === 1 ? "single" : "multi",
    title: selected.length === 1
      ? TYPE_LABELS[selected[0].type]
      : `${selected.length} selected`,
    selectedIds: [...selectedIds],
    fields,
    ...(selected.length === 1 ? fixedValueFor(selected[0].type) : {}),
    actions: reorderActions(document, selectedIds),
  };
}

function resolveSelection(
  document: EditorDocument,
  selectedIds: readonly string[],
): EditorElement[] {
  if (new Set(selectedIds).size !== selectedIds.length) {
    throw new Error("Context Rail selection contains duplicate ids");
  }
  return selectedIds.map((id) => {
    const element = document.elements.find((candidate) => candidate.id === id);
    if (!element) throw new Error(`Context Rail selection is missing element: ${id}`);
    return element;
  });
}

function defaultFields(
  tool: Exclude<EditorTool, "selection">,
  document: EditorDocument,
): ContextRailFields {
  const fields: ContextRailFields = {};
  for (const property of TYPE_PROPERTIES[tool]) {
    setField(fields, property, {
      label: PROPERTY_LABELS[property],
      value: {
        kind: "single",
        value: defaultValue(document, tool, property),
      },
      allowedValues: allowedValues(tool, property),
    });
  }
  return fields;
}

function selectionFields(selected: readonly EditorElement[]): ContextRailFields {
  const fields: ContextRailFields = {};
  const sharedKeys = commonKeys(selected);
  for (const property of sharedKeys) {
    const domain = propertyDomain(property).filter((value) =>
      selected.every((element) => (
        allowedValues(element.type, property).some((allowed) => Object.is(allowed, value))
      )),
    );
    if (domain.length === 0) continue;
    setField(fields, property, {
      label: PROPERTY_LABELS[property],
      value: deriveValue(selected.map((element) => elementValue(element, property))),
      allowedValues: domain,
    });
  }
  return fields;
}

const commonKeys = (
  selected: readonly EditorElement[],
): RailPropertyKey[] =>
  ALL_PROPERTY_KEYS.filter((key) =>
    selected.every((element) => supportsProperty(element, key)),
  );

const deriveValue = <T>(values: readonly T[]): RailValue<T> => {
  const first = values[0];
  if (first === undefined) {
    throw new Error("Cannot derive a Context Rail value without elements");
  }
  return values.every((value) => Object.is(value, first))
    ? { kind: "single", value: first }
    : { kind: "mixed" };
};

export function supportsProperty(
  element: EditorElement,
  property: RailPropertyKey,
): boolean {
  return TYPE_PROPERTIES[element.type].includes(property);
}

export function allowedValues(
  type: EditorElement["type"],
  property: RailPropertyKey,
): readonly RailPropertyValue[] {
  if (!TYPE_PROPERTIES[type].includes(property)) return [];
  if (property === "opacity" && type === "highlighter") return HIGHLIGHTER_OPACITIES;
  return propertyDomain(property);
}

function propertyDomain(property: RailPropertyKey): readonly RailPropertyValue[] {
  switch (property) {
    case "color":
      return COLORS;
    case "fillColor":
      return FILLS;
    case "strokeWidth":
      return STROKE_WIDTHS;
    case "roughness":
      return ROUGHNESSES;
    case "textSize":
      return TEXT_SIZES;
    case "opacity":
      return OPACITIES;
  }
}

function defaultValue(
  document: EditorDocument,
  tool: Exclude<EditorTool, "selection">,
  property: RailPropertyKey,
): RailPropertyValue {
  if (!TYPE_PROPERTIES[tool].includes(property)) {
    throw new Error(`${TOOL_LABELS[tool]} does not support ${property}`);
  }
  switch (property) {
    case "color":
      return document.defaults.color;
    case "fillColor":
      return document.defaults.rectangleFillColor;
    case "strokeWidth":
      return document.defaults.strokeWidth;
    case "roughness":
      return document.defaults.roughness;
    case "textSize":
      return document.defaults.textSize;
    case "opacity":
      return tool === "highlighter"
        ? document.defaults.highlighterOpacity
        : document.defaults.opacity;
  }
}

function elementValue(
  element: EditorElement,
  property: RailPropertyKey,
): RailPropertyValue {
  if (!supportsProperty(element, property)) {
    throw new Error(`${TYPE_LABELS[element.type]} does not support ${property}`);
  }
  switch (property) {
    case "color":
      if (element.type === "rectangle" || element.type === "arrow" || element.type === "line") {
        return element.strokeColor;
      }
      if (element.type === "text" || element.type === "freehand" || element.type === "highlighter" || element.type === "numberMarker") {
        return element.color;
      }
      break;
    case "fillColor":
      if (element.type === "rectangle") return element.fillColor;
      break;
    case "strokeWidth":
      if (element.type === "rectangle" || element.type === "arrow" || element.type === "line" || element.type === "freehand") {
        return element.strokeWidth;
      }
      break;
    case "roughness":
      if (element.type === "rectangle" || element.type === "arrow" || element.type === "line") {
        return element.roughness;
      }
      break;
    case "textSize":
      if (element.type === "text") return element.fontSize;
      break;
    case "opacity":
      return element.opacity;
  }
  throw new Error(`${TYPE_LABELS[element.type]} does not expose ${property}`);
}

function fixedValueFor(
  type: EditorElement["type"] | Exclude<EditorTool, "selection">,
): { fixedValue: string } | Record<string, never> {
  if (type === "blur") return { fixedValue: "Radius 12 px · Fixed" };
  if (type === "redaction") return { fixedValue: "Opaque black · Fixed" };
  return {};
}

function reorderActions(
  document: EditorDocument,
  selectedIds: readonly string[],
): ContextRailSelectionActions {
  const selected = new Set(selectedIds);
  const ordered = [...document.elements].sort((left, right) => left.zIndex - right.zIndex);
  return {
    canBringForward: ordered.some((element, index) => (
      selected.has(element.id)
      && index < ordered.length - 1
      && !selected.has(ordered[index + 1].id)
    )),
    canSendBackward: ordered.some((element, index) => (
      selected.has(element.id)
      && index > 0
      && !selected.has(ordered[index - 1].id)
    )),
    canDuplicate: true,
    canDelete: true,
  };
}

function setField<K extends RailPropertyKey>(
  fields: ContextRailFields,
  property: K,
  field: ContextRailField<K>,
): void {
  (fields as Record<RailPropertyKey, ContextRailField<K>>)[property] = field;
}
