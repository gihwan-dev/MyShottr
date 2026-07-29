import { describe, expect, it } from "vitest";
import { EditorElementSchema } from "../../model/schema";
import { creationGesture } from "../../test/fixtures";
import { createElement } from "./createElement";

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
});
