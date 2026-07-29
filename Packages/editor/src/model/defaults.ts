import type { EditorDefaults, EditorDocument } from "./elements";
import { EditorDocumentSchema } from "./schema";

export const DEFAULT_EDITOR_DEFAULTS: EditorDefaults = {
  color: "#1677FF",
  strokeWidth: 4,
  textSize: 24,
  roughness: 1,
  opacity: 1,
};

export function createEmptyDocument(): EditorDocument {
  return EditorDocumentSchema.parse({
    schemaVersion: 1,
    sourcePixelWidth: 1,
    sourcePixelHeight: 1,
    elements: [],
    defaults: DEFAULT_EDITOR_DEFAULTS,
  });
}
