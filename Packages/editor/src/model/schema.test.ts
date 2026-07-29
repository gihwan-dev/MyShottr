import { describe, expect, it } from "vitest";
import { allElementFixtures, fixtureDocument, fixtureRect } from "../test/fixtures";
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

  it("rejects duplicate element ids and z-index values", () => {
    expect(() => EditorDocumentSchema.parse(fixtureDocument({
      elements: [fixtureRect(), { ...fixtureRect(), id: "rect-2", zIndex: 0 }],
    }))).toThrow();
    expect(() => EditorDocumentSchema.parse(fixtureDocument({
      elements: [fixtureRect(), { ...fixtureRect(), zIndex: 1 }],
    }))).toThrow();
  });
});
