import { describe, expect, it } from "vitest";
import {
  allElementFixtures,
  fixtureBlur,
  fixtureDocument,
  fixtureRect,
} from "../test/fixtures";
import { EditorDocumentSchema, EditorElementSchema } from "./schema";

describe("EditorDocumentSchema", () => {
  it("rejects an unknown element type", () => {
    const value = fixtureDocument({ elements: [{ ...fixtureRect(), type: "video" } as never] });

    expect(() => EditorDocumentSchema.parse(value)).toThrow();
  });

  it("round-trips every supported element", () => {
    const document = fixtureDocument({ elements: allElementFixtures() });

    expect(EditorDocumentSchema.parse(JSON.parse(JSON.stringify(document)))).toEqual(document);
  });

  it("rejects non-finite numbers and negative sizes", () => {
    expect(() => EditorElementSchema.parse({ ...fixtureRect(), x: Number.POSITIVE_INFINITY })).toThrow();
    expect(() => EditorElementSchema.parse({ ...fixtureRect(), width: -1 })).toThrow();
    expect(() => EditorElementSchema.parse({ ...fixtureRect(), height: -1 })).toThrow();
  });

  it("rejects empty freehand paths", () => {
    const freehand = allElementFixtures().find((element) => element.type === "freehand");
    expect(() => EditorElementSchema.parse({ ...freehand, points: [] })).toThrow();
  });

  it("accepts only the fixed, axis-aligned blur shape", () => {
    expect(() => EditorElementSchema.parse(fixtureBlur())).not.toThrow();
    expect(() => EditorElementSchema.parse({ ...fixtureBlur(), radius: 8 })).toThrow();
    expect(() => EditorElementSchema.parse({ ...fixtureBlur(), width: -1 })).toThrow();
    expect(() => EditorElementSchema.parse({ ...fixtureBlur(), unexpected: true })).toThrow();
    expect(() => EditorElementSchema.parse({ ...fixtureBlur(), opacity: 0.5 })).toThrow();
    expect(() => EditorElementSchema.parse({ ...fixtureBlur(), rotation: 15 })).toThrow();
  });

  it("rejects duplicate element ids and z-index values", () => {
    expect(() => EditorDocumentSchema.parse(fixtureDocument({
      elements: [fixtureRect(), { ...fixtureRect(), id: "rect-2", zIndex: 0 }],
    }))).toThrow();
    expect(() => EditorDocumentSchema.parse(fixtureDocument({
      elements: [fixtureRect(), { ...fixtureRect(), zIndex: 1 }],
    }))).toThrow();
  });

  it("rejects schema 1 without injecting current defaults", () => {
    const {
      presentation: _presentation,
      defaults: currentDefaults,
      ...document
    } = fixtureDocument();
    const {
      rectangleFillColor: _rectangleFillColor,
      highlighterOpacity: _highlighterOpacity,
      ...legacyDefaults
    } = currentDefaults;
    const legacy = { ...document, schemaVersion: 1, defaults: legacyDefaults };
    const original = structuredClone(legacy);

    expect(EditorDocumentSchema.safeParse(legacy).success).toBe(false);
    expect(legacy).toEqual(original);
    expect(legacy.defaults).not.toHaveProperty("rectangleFillColor");
    expect(legacy.defaults).not.toHaveProperty("highlighterOpacity");
  });

  it("rejects schema 2 without injecting current defaults", () => {
    const { defaults: currentDefaults, ...document } = fixtureDocument();
    const {
      rectangleFillColor: _rectangleFillColor,
      highlighterOpacity: _highlighterOpacity,
      ...legacyDefaults
    } = currentDefaults;
    const legacy = { ...document, schemaVersion: 2, defaults: legacyDefaults };
    const original = structuredClone(legacy);

    expect(EditorDocumentSchema.safeParse(legacy).success).toBe(false);
    expect(legacy).toEqual(original);
    expect(legacy.defaults).not.toHaveProperty("rectangleFillColor");
    expect(legacy.defaults).not.toHaveProperty("highlighterOpacity");
  });

  it("requires every schema 3 defaults key", () => {
    const current = fixtureDocument();
    const { highlighterOpacity: _removed, ...defaults } = current.defaults;

    expect(() => EditorDocumentSchema.parse({ ...current, defaults })).toThrow();
  });

  it("rejects schema 4", () => {
    expect(() => EditorDocumentSchema.parse({ ...fixtureDocument(), schemaVersion: 4 })).toThrow();
  });

  it("requires presentation none in schema 3", () => {
    expect(() => EditorDocumentSchema.parse({
      ...fixtureDocument(),
      presentation: { type: "desktopMockup" },
    })).toThrow();
  });
});
