import { describe, expect, it } from "vitest";
import { EditorElementSchema } from "../../model/schema";
import { creationGesture, fixtureDocument } from "../../test/fixtures";
import { createElement } from "./createElement";
import { createCanvasElement } from "../EditorCanvas";

const context = {
  defaults: {
    color: "#1677FF",
    strokeWidth: 4,
    textSize: 24,
    roughness: 1,
    opacity: 1,
  } as const,
  nextNumberMarker: 7,
  nextZIndex: 12,
  seed: 99,
};

describe("createElement", () => {
  it.each([
    "rectangle", "arrow", "text", "freehand",
    "highlighter", "redaction", "numberMarker",
  ] as const)("creates a valid %s element", (tool) => {
    expect(() => EditorElementSchema.parse(createElement(tool, creationGesture(tool), context))).not.toThrow();
  });

  it("uses the caller-derived number and z-index for a number marker", () => {
    const element = createElement("numberMarker", creationGesture("numberMarker"), context);

    expect(element).toMatchObject({ type: "numberMarker", number: 7, zIndex: 12, seed: 99 });
  });

  it("applies the active rectangle fill while preserving marker and z-index derivation", () => {
    const existingMarker = createElement("numberMarker", creationGesture("numberMarker"), context);
    if (existingMarker.type !== "numberMarker") throw new Error("Expected a number marker");
    const document = fixtureDocument({ elements: [
      ...fixtureDocument().elements,
      { ...existingMarker, id: "marker-9", zIndex: 9, number: 9 },
    ] });

    const rectangle = createCanvasElement(document, "rectangle", creationGesture("rectangle"), "#FADB14");
    const marker = createCanvasElement(document, "numberMarker", creationGesture("numberMarker"), null);

    expect(rectangle).toMatchObject({ type: "rectangle", fillColor: "#FADB14", zIndex: 10 });
    expect(marker).toMatchObject({ type: "numberMarker", number: 10, zIndex: 10 });
  });

  it("creates a collision-safe id without changing rough seed progression", () => {
    const document = fixtureDocument({
      elements: [
        { ...fixtureDocument().elements[0], id: "rectangle-2", seed: 1, zIndex: 0 },
      ],
    });

    const rectangle = createCanvasElement(document, "rectangle", creationGesture("rectangle"), null);

    expect(rectangle.id).not.toBe("rectangle-2");
    expect(rectangle.seed).toBe(2);
  });
});
