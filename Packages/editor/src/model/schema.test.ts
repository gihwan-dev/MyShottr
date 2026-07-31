import { describe, expect, it } from "vitest";
import {
  allElementFixtures,
  fixtureBlur,
  fixtureDocument,
  fixtureRect,
  schemaOneFixture,
  schemaTwoFixture,
} from "../test/fixtures";
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

  it("migrates schema 1 to schema 3 with approved new defaults", () => {
    const legacy = schemaOneFixture();

    expect(parseEditorDocument(legacy)).toMatchObject({
      schemaVersion: 3,
      presentation: { type: "none" },
      defaults: {
        rectangleFillColor: null,
        highlighterOpacity: 0.5,
      },
    });
  });

  it("migrates schema 2 to schema 3 without changing legacy defaults", () => {
    const legacy = schemaTwoFixture();

    expect(parseEditorDocument(legacy)).toEqual({
      ...legacy,
      schemaVersion: 3,
      defaults: {
        ...legacy.defaults,
        rectangleFillColor: null,
        highlighterOpacity: 0.5,
      },
    });
  });

  it("requires every schema 3 defaults key", () => {
    const current = fixtureDocument();
    const { highlighterOpacity: _removed, ...defaults } = current.defaults;

    expect(() => parseEditorDocument({ ...current, defaults })).toThrow();
  });

  it("rejects schema 4", () => {
    expect(() => parseEditorDocument({ ...fixtureDocument(), schemaVersion: 4 })).toThrow();
  });

  it("requires presentation none in schema 3", () => {
    expect(() => EditorDocumentSchema.parse({
      ...fixtureDocument(),
      presentation: { type: "desktopMockup" },
    })).toThrow();
  });
});
