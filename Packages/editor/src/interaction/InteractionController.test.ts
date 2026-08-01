import { describe, expect, it } from "vitest";

import { DEFAULT_EDITOR_DEFAULTS } from "../model/defaults";
import type { EditorDefaults, EditorDocument } from "../model/elements";
import { fixtureDocument, fixtureRect } from "../test/fixtures";
import {
  InteractionController,
  type InteractionBeginInput,
  type InteractionModifiers,
} from "./InteractionController";

const NO_MODIFIERS: InteractionModifiers = { shift: false, option: false };

describe("InteractionController", () => {
  it("commits with the tool and defaults captured at pointer-down", () => {
    const controller = new InteractionController();
    const defaults: EditorDefaults = {
      ...DEFAULT_EDITOR_DEFAULTS,
      rectangleFillColor: "#FADB14",
    };
    const document = fixtureDocument({ elements: [], defaults });

    controller.begin(beginInput({
      pointerId: 7,
      tool: "rectangle",
      point: { x: 10, y: 10 },
      defaults,
      document,
    }));
    controller.update({ x: 80, y: 60 }, NO_MODIFIERS);

    defaults.rectangleFillColor = null;
    document.defaults.rectangleFillColor = null;
    const result = controller.commit({ x: 80, y: 60 }, NO_MODIFIERS);

    expect(result).toMatchObject({
      type: "command",
      command: {
        type: "create",
        element: {
          type: "rectangle",
          fillColor: "#FADB14",
          x: 10,
          y: 10,
          width: 70,
          height: 50,
        },
      },
    });
  });

  it.each(["rectangle", "arrow", "line"] as const)(
    "uses the same Shift constraint for the %s preview and commit",
    (tool) => {
      const controller = new InteractionController();
      controller.begin(beginInput({
        tool,
        point: { x: 10, y: 10 },
        document: fixtureDocument({ elements: [] }),
      }));

      const preview = controller.update(
        { x: 50, y: 30 },
        { shift: true, option: false },
      );
      const result = controller.commit(
        { x: 50, y: 30 },
        { shift: true, option: false },
      );

      expect(preview).toMatchObject({ type: "creation" });
      expect(result).toMatchObject({ type: "command" });
      if (preview.type !== "creation" || result.type !== "command" || result.command.type !== "create") {
        throw new Error("Expected matching creation preview and command");
      }
      expect(result.command.element).toMatchObject({
        x: preview.element.x,
        y: preview.element.y,
        width: preview.element.width,
        height: preview.element.height,
      });
      if (tool === "rectangle") {
        expect(result.command.element).toMatchObject({ width: 40, height: 40 });
      } else {
        expect(result.command.element.type).toBe(tool);
        if (result.command.element.type !== "arrow" && result.command.element.type !== "line") {
          throw new Error("Expected a constrained line element");
        }
        expect(result.command.element.points[1]).toEqual(preview.element.type === tool
          ? preview.element.points[1]
          : undefined);
      }
    },
  );

  it("accumulates freehand points only when updates are flushed", () => {
    const controller = new InteractionController();
    controller.begin(beginInput({
      tool: "freehand",
      point: { x: 1, y: 2 },
      document: fixtureDocument({ elements: [] }),
    }));

    controller.update({ x: 5, y: 6 }, NO_MODIFIERS);
    const result = controller.commit({ x: 9, y: 10 }, NO_MODIFIERS);

    expect(result).toMatchObject({
      type: "command",
      command: {
        type: "create",
        element: {
          type: "freehand",
          points: [
            { x: 1, y: 2 },
            { x: 5, y: 6 },
            { x: 9, y: 10 },
          ],
        },
      },
    });
  });

  it("previews and commits a number marker from one click", () => {
    const controller = new InteractionController();
    const preview = controller.begin(beginInput({
      tool: "numberMarker",
      point: { x: 25, y: 35 },
      document: fixtureDocument({ elements: [] }),
    }));

    expect(preview).toMatchObject({
      type: "creation",
      element: { type: "numberMarker", x: 25, y: 35, number: 1 },
    });
    expect(controller.commit({ x: 90, y: 100 }, NO_MODIFIERS)).toMatchObject({
      type: "command",
      command: {
        type: "create",
        element: { type: "numberMarker", x: 25, y: 35, number: 1 },
      },
    });
  });

  it("emits beginNewText without creating a placeholder element", () => {
    const controller = new InteractionController();
    const document = fixtureDocument({ elements: [] });

    expect(controller.begin(beginInput({
      tool: "text",
      point: { x: 20, y: 30 },
      document,
    }))).toBeNull();
    expect(controller.preview).toBeNull();
    expect(controller.commit({ x: 100, y: 110 }, NO_MODIFIERS)).toEqual({
      type: "beginNewText",
      point: { x: 20, y: 30 },
      defaults: DEFAULT_EDITOR_DEFAULTS,
    });
    expect(document.elements).toEqual([]);
  });

  it("cancels without a command and makes every repeated terminal inert", () => {
    const controller = new InteractionController();
    const document = fixtureDocument({ elements: [] });
    controller.begin(beginInput({ tool: "rectangle", document }));
    controller.update({ x: 40, y: 50 }, NO_MODIFIERS);

    controller.cancel();
    controller.cancel();

    expect(controller.active).toBe(false);
    expect(controller.preview).toBeNull();
    expect(controller.commit({ x: 40, y: 50 }, NO_MODIFIERS)).toEqual({ type: "none" });
    expect(document.elements).toEqual([]);
  });

  it("commits at most once", () => {
    const controller = new InteractionController();
    controller.begin(beginInput({
      tool: "redaction",
      document: fixtureDocument({ elements: [] }),
    }));

    expect(controller.commit({ x: 40, y: 50 }, NO_MODIFIERS).type).toBe("command");
    expect(controller.commit({ x: 80, y: 90 }, NO_MODIFIERS)).toEqual({ type: "none" });
  });

  it("snapshots Space-held at pointer-down as a viewport interaction", () => {
    const controller = new InteractionController();
    expect(controller.begin(beginInput({ spaceHeld: true }))).toEqual({
      type: "viewport",
      pan: { x: 0, y: 0 },
    });
    expect(controller.update({ x: 35, y: 55 }, NO_MODIFIERS)).toEqual({
      type: "viewport",
      pan: { x: 25, y: 35 },
    });
    expect(controller.commit({ x: 40, y: 60 }, NO_MODIFIERS)).toEqual({
      type: "viewport",
      pan: { x: 30, y: 40 },
    });
  });

  it("previews a marquee and replaces selection with rotated AABB intersections", () => {
    const controller = new InteractionController();
    const rectangle = {
      ...fixtureRect(),
      x: 100,
      y: 100,
      width: 80,
      height: 20,
      rotation: 45,
    };
    controller.begin(beginInput({
      tool: "selection",
      point: { x: 150, y: 150 },
      document: fixtureDocument({ elements: [rectangle] }),
      selectedIds: [rectangle.id],
    }));

    expect(controller.update({ x: 160, y: 160 }, NO_MODIFIERS)).toEqual({
      type: "marquee",
      rect: { x: 150, y: 150, width: 10, height: 10 },
    });
    expect(controller.commit({ x: 160, y: 160 }, NO_MODIFIERS)).toEqual({
      type: "selection",
      selectedIds: [rectangle.id],
    });
  });

  it("clears selection when an empty-source gesture stays below 3 CSS pixels", () => {
    const controller = new InteractionController();
    const document = fixtureDocument();
    controller.begin(beginInput({
      tool: "selection",
      point: { x: 10, y: 10 },
      document,
      selectedIds: [document.elements[0].id],
      zoom: 2,
    }));

    expect(controller.update({ x: 11.49, y: 11.49 }, NO_MODIFIERS))
      .toEqual({ type: "none" });
    expect(controller.commit({ x: 11.49, y: 11.49 }, NO_MODIFIERS)).toEqual({
      type: "selection",
      selectedIds: [],
    });
  });
});

function beginInput(overrides: Partial<InteractionBeginInput> = {}): InteractionBeginInput {
  const document = overrides.document ?? fixtureDocument({ elements: [] });
  return {
    pointerId: 1,
    tool: "rectangle",
    point: { x: 10, y: 20 },
    modifiers: NO_MODIFIERS,
    defaults: document.defaults,
    document,
    selectedIds: [],
    spaceHeld: false,
    zoom: 1,
    ...overrides,
  };
}
