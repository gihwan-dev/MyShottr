import { describe, expect, it } from "vitest";
import { DEFAULT_EDITOR_DEFAULTS } from "../../model/defaults";
import { EditorElementSchema } from "../../model/schema";
import { creationGesture, fixtureDocument } from "../../test/fixtures";
import { createElement } from "./createElement";
import { createCanvasElement } from "../EditorCanvas";
import { cursorForTool } from "./ToolController";
import { keyboardCommandFor } from "../../input/ShortcutRouter";

const idleShortcutContext = {
  interactionActive: false,
  shortcutHelpOpen: false,
  textEditing: false,
};

const context = {
  defaults: {
    color: "#1677FF",
    strokeWidth: 4,
    textSize: 24,
    roughness: 1,
    opacity: 1,
    rectangleFillColor: null,
    highlighterOpacity: 0.5,
  } as const,
  nextNumberMarker: 7,
  nextZIndex: 12,
  seed: 99,
};

describe("createElement", () => {
  it.each([
    "rectangle", "arrow", "line", "text", "freehand",
    "highlighter", "blur", "redaction", "numberMarker",
  ] as const)("creates a valid %s element", (tool) => {
    expect(() => EditorElementSchema.parse(createElement(tool, creationGesture(tool), context))).not.toThrow();
  });

  it("creates a two-point rough line from a box gesture", () => {
    const line = createElement("line", {
      kind: "box",
      start: { x: 10, y: 20 },
      end: { x: 90, y: 60 },
    }, context);

    expect(line).toMatchObject({
      type: "line",
      x: 10,
      y: 20,
      width: 80,
      height: 40,
      points: [{ x: 10, y: 20 }, { x: 90, y: 60 }],
    });
  });

  it("creates a fixed-radius blur region", () => {
    expect(createElement("blur", {
      kind: "box",
      start: { x: 20, y: 30 },
      end: { x: 120, y: 80 },
    }, context)).toMatchObject({
      type: "blur",
      x: 20,
      y: 30,
      width: 100,
      height: 50,
      radius: 12,
      opacity: 1,
      rotation: 0,
    });
  });

  it("uses the rectangle fill color default for new rectangles", () => {
    expect(createElement("rectangle", creationGesture("rectangle"), {
      ...context,
      defaults: {
        ...DEFAULT_EDITOR_DEFAULTS,
        rectangleFillColor: "#FADB14",
      },
    })).toMatchObject({
      type: "rectangle",
      fillColor: "#FADB14",
    });
  });

  it("uses the highlighter opacity default instead of shared opacity", () => {
    expect(createElement("highlighter", creationGesture("highlighter"), {
      ...context,
      defaults: {
        ...DEFAULT_EDITOR_DEFAULTS,
        opacity: 1,
        highlighterOpacity: 0.25,
      },
    })).toMatchObject({
      type: "highlighter",
      opacity: 0.25,
    });
  });

  it("maps L to line without modifiers", () => {
    expect(keyboardCommandFor(
      new KeyboardEvent("keydown", { code: "KeyL", key: "l" }),
      idleShortcutContext,
    )).toEqual({ type: "selectTool", tool: "line" });
  });

  it("maps B to blur without modifiers", () => {
    expect(keyboardCommandFor(
      new KeyboardEvent("keydown", { code: "KeyB", key: "b" }),
      idleShortcutContext,
    )).toEqual({ type: "selectTool", tool: "blur" });
  });

  it("maps Meta brackets to one-step ordering commands", () => {
    expect(keyboardCommandFor(
      new KeyboardEvent("keydown", {
        code: "BracketRight",
        key: "]",
        metaKey: true,
      }),
      idleShortcutContext,
    )).toEqual({ type: "bringForward" });
    expect(keyboardCommandFor(
      new KeyboardEvent("keydown", {
        code: "BracketLeft",
        key: "[",
        metaKey: true,
      }),
      idleShortcutContext,
    )).toEqual({ type: "sendBackward" });
  });

  it("maps exact unshifted Command-C to annotation copy", () => {
    expect(keyboardCommandFor(
      new KeyboardEvent("keydown", {
        code: "KeyC",
        key: "c",
        metaKey: true,
      }),
      idleShortcutContext,
    )).toEqual({ type: "copy" });
  });

  it("leaves Command-Shift-C unmapped for native Copy Image routing", () => {
    expect(keyboardCommandFor(new KeyboardEvent("keydown", {
      code: "KeyC",
      key: "c",
      metaKey: true,
      shiftKey: true,
    }), idleShortcutContext)).toBeUndefined();
  });

  it("maps tools and Space-pan states to their approved cursors", () => {
    expect(cursorForTool("selection")).toBe("default");
    expect(cursorForTool("text")).toBe("text");
    expect(cursorForTool("rectangle")).toBe("crosshair");
    expect(cursorForTool("selection", "ready")).toBe("grab");
    expect(cursorForTool("rectangle", "active")).toBe("grabbing");
  });

  it("uses the caller-derived number and z-index for a number marker", () => {
    const element = createElement("numberMarker", creationGesture("numberMarker"), context);

    expect(element).toMatchObject({ type: "numberMarker", number: 7, zIndex: 12, seed: 99 });
  });

  it("applies document rectangle fill while preserving marker and z-index derivation", () => {
    const existingMarker = createElement("numberMarker", creationGesture("numberMarker"), context);
    if (existingMarker.type !== "numberMarker") throw new Error("Expected a number marker");
    const document = fixtureDocument({
      defaults: {
        ...fixtureDocument().defaults,
        rectangleFillColor: "#FADB14",
      },
      elements: [
        ...fixtureDocument().elements,
        { ...existingMarker, id: "marker-9", zIndex: 9, number: 9 },
      ],
    });

    const rectangle = createCanvasElement(document, "rectangle", creationGesture("rectangle"));
    const marker = createCanvasElement(document, "numberMarker", creationGesture("numberMarker"));

    expect(rectangle).toMatchObject({ type: "rectangle", fillColor: "#FADB14", zIndex: 10 });
    expect(marker).toMatchObject({ type: "numberMarker", number: 10, zIndex: 10 });
  });

  it("creates a collision-safe id without changing rough seed progression", () => {
    const document = fixtureDocument({
      elements: [
        { ...fixtureDocument().elements[0], id: "rectangle-2", seed: 1, zIndex: 0 },
      ],
    });

    const rectangle = createCanvasElement(document, "rectangle", creationGesture("rectangle"));

    expect(rectangle.id).not.toBe("rectangle-2");
    expect(rectangle.seed).toBe(2);
  });
});
