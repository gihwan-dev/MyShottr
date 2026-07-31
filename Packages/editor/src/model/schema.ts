import { z } from "zod";
import type { EditorDefaults, EditorDocument } from "./elements";

const PaletteColorSchema = z.enum(["#000000", "#FF4D4F", "#1677FF", "#FADB14"]);
const StrokeWidthSchema = z.union([z.literal(2), z.literal(4), z.literal(8)]);
const TextSizeSchema = z.union([z.literal(16), z.literal(24), z.literal(36)]);
const RoughnessSchema = z.union([z.literal(0), z.literal(1), z.literal(2)]);
const OpacitySchema = z.union([
  z.literal(0.25),
  z.literal(0.5),
  z.literal(0.75),
  z.literal(1),
]);
const FiniteNumberSchema = z.number().finite();
const PointSchema = z.object({
  x: FiniteNumberSchema,
  y: FiniteNumberSchema,
}).strict();

const ElementBaseSchema = z.object({
  id: z.string().min(1),
  x: FiniteNumberSchema,
  y: FiniteNumberSchema,
  width: FiniteNumberSchema.nonnegative(),
  height: FiniteNumberSchema.nonnegative(),
  rotation: FiniteNumberSchema,
  opacity: OpacitySchema,
  zIndex: FiniteNumberSchema,
  seed: FiniteNumberSchema,
});

const RectangleElementSchema = ElementBaseSchema.extend({
  type: z.literal("rectangle"),
  strokeColor: PaletteColorSchema,
  strokeWidth: StrokeWidthSchema,
  fillColor: PaletteColorSchema.nullable(),
  roughness: RoughnessSchema,
}).strict();

const ArrowElementSchema = ElementBaseSchema.extend({
  type: z.literal("arrow"),
  points: z.tuple([PointSchema, PointSchema]),
  strokeColor: PaletteColorSchema,
  strokeWidth: StrokeWidthSchema,
  roughness: RoughnessSchema,
}).strict();

const LineElementSchema = ElementBaseSchema.extend({
  type: z.literal("line"),
  points: z.tuple([PointSchema, PointSchema]),
  strokeColor: PaletteColorSchema,
  strokeWidth: StrokeWidthSchema,
  roughness: RoughnessSchema,
}).strict();

const TextElementSchema = ElementBaseSchema.extend({
  type: z.literal("text"),
  text: z.string(),
  color: PaletteColorSchema,
  fontSize: TextSizeSchema,
}).strict();

const FreehandElementSchema = ElementBaseSchema.extend({
  type: z.literal("freehand"),
  points: z.array(PointSchema).min(1),
  color: PaletteColorSchema,
  strokeWidth: StrokeWidthSchema,
}).strict();

const HighlighterElementSchema = ElementBaseSchema.extend({
  type: z.literal("highlighter"),
  points: z.array(PointSchema).min(1),
  color: PaletteColorSchema,
  strokeWidth: z.literal(8),
  opacity: z.union([z.literal(0.25), z.literal(0.5)]),
}).strict();

const BlurElementSchema = ElementBaseSchema.extend({
  type: z.literal("blur"),
  radius: z.literal(12),
  rotation: z.literal(0),
  opacity: z.literal(1),
}).strict();

const RedactionElementSchema = ElementBaseSchema.extend({
  type: z.literal("redaction"),
  color: z.literal("#000000"),
  opacity: z.literal(1),
}).strict();

const NumberMarkerElementSchema = ElementBaseSchema.extend({
  type: z.literal("numberMarker"),
  number: FiniteNumberSchema,
  color: PaletteColorSchema,
}).strict();

export const EditorElementSchema = z.discriminatedUnion("type", [
  RectangleElementSchema,
  ArrowElementSchema,
  LineElementSchema,
  TextElementSchema,
  FreehandElementSchema,
  HighlighterElementSchema,
  BlurElementSchema,
  RedactionElementSchema,
  NumberMarkerElementSchema,
]);

const LegacyEditorDefaultsSchema = z.object({
  color: PaletteColorSchema,
  strokeWidth: StrokeWidthSchema,
  textSize: TextSizeSchema,
  roughness: RoughnessSchema,
  opacity: OpacitySchema,
}).strict();

export const EditorDefaultsSchema = LegacyEditorDefaultsSchema.extend({
  rectangleFillColor: PaletteColorSchema.nullable(),
  highlighterOpacity: z.union([z.literal(0.25), z.literal(0.5)]),
}).strict();

const PresentationSchema = z.object({
  type: z.literal("none"),
}).strict();

const documentBody = {
  sourcePixelWidth: FiniteNumberSchema.positive(),
  sourcePixelHeight: FiniteNumberSchema.positive(),
  elements: z.array(EditorElementSchema),
};

function validateUniqueElementIdentity(
  document: { elements: Array<{ id: string; zIndex: number }> },
  context: z.RefinementCtx,
): void {
  const ids = new Set<string>();
  const zIndices = new Set<number>();

  document.elements.forEach((element, index) => {
    if (ids.has(element.id)) {
      context.addIssue({
        code: z.ZodIssueCode.custom,
        path: ["elements", index, "id"],
        message: `Duplicate element id: ${element.id}`,
      });
    }
    ids.add(element.id);

    if (zIndices.has(element.zIndex)) {
      context.addIssue({
        code: z.ZodIssueCode.custom,
        path: ["elements", index, "zIndex"],
        message: `Duplicate element z-index: ${element.zIndex}`,
      });
    }
    zIndices.add(element.zIndex);
  });
}

export const EditorDocumentSchema = z.object({
  schemaVersion: z.literal(3),
  ...documentBody,
  presentation: PresentationSchema,
  defaults: EditorDefaultsSchema,
}).strict().superRefine(validateUniqueElementIdentity);

const SchemaOneDocumentSchema = z.object({
  schemaVersion: z.literal(1),
  ...documentBody,
  defaults: LegacyEditorDefaultsSchema,
}).strict().superRefine(validateUniqueElementIdentity);

const SchemaTwoDocumentSchema = z.object({
  schemaVersion: z.literal(2),
  ...documentBody,
  presentation: PresentationSchema,
  defaults: LegacyEditorDefaultsSchema,
}).strict().superRefine(validateUniqueElementIdentity);

const upgradeLegacyDefaults = (
  defaults: z.infer<typeof LegacyEditorDefaultsSchema>,
): EditorDefaults => ({
  ...defaults,
  rectangleFillColor: null,
  highlighterOpacity: 0.5,
});

export function parseEditorDocument(input: unknown): EditorDocument {
  const current = EditorDocumentSchema.safeParse(input);
  if (current.success) return current.data;

  const versionTwo = SchemaTwoDocumentSchema.safeParse(input);
  if (versionTwo.success) {
    return EditorDocumentSchema.parse({
      ...versionTwo.data,
      schemaVersion: 3,
      defaults: upgradeLegacyDefaults(versionTwo.data.defaults),
    });
  }

  const versionOne = SchemaOneDocumentSchema.safeParse(input);
  if (versionOne.success) {
    return EditorDocumentSchema.parse({
      ...versionOne.data,
      schemaVersion: 3,
      presentation: { type: "none" },
      defaults: upgradeLegacyDefaults(versionOne.data.defaults),
    });
  }

  throw current.error;
}
