import { describe, expect, it } from "vitest";
import { allElementFixtures, fixtureBlur, fixtureDocument, fixtureRect } from "../test/fixtures";
import { EditorDocumentSchema, EditorElementSchema, parseEditorDocument } from "./schema";

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

  it("migrates a schema-1 document to presentation none", () => {
    const legacy = {
      ...fixtureDocument(),
      schemaVersion: 1,
    };
    delete (legacy as Record<string, unknown>).presentation;

    expect(parseEditorDocument(legacy)).toMatchObject({
      schemaVersion: 2,
      presentation: { type: "none" },
    });
  });

  it("rejects an unsupported newer document", () => {
    expect(() => parseEditorDocument({
      ...fixtureDocument(),
      schemaVersion: 3,
    })).toThrow();
  });

  it("requires presentation none in schema 2", () => {
    expect(() => EditorDocumentSchema.parse({
      ...fixtureDocument(),
      presentation: { type: "desktopMockup" },
    })).toThrow();
  });
});
