import { describe, expect, it } from "vitest";

import { DEFAULT_EDITOR_DEFAULTS } from "../model/defaults";
import type { EditorElement } from "../model/elements";
import {
  deriveContextRailModel,
  type ContextRailFields,
  type RailPropertyKey,
} from "./contextRailModel";
import {
  allElementFixtures,
  fixtureBlur,
  fixtureDocument,
  fixtureRect,
  fixtureText,
} from "../test/fixtures";

describe("deriveContextRailModel", () => {
  it("is hidden for Selection with no selection", () => {
    expect(deriveContextRailModel({
      tool: "selection",
      document: fixtureDocument(),
      selectedIds: [],
    })).toEqual({ kind: "hidden" });
  });

  it("shows new Rectangle defaults with fill", () => {
    expect(deriveContextRailModel({
      tool: "rectangle",
      document: fixtureDocument({
        defaults: {
          ...DEFAULT_EDITOR_DEFAULTS,
          rectangleFillColor: "#FADB14",
        },
      }),
      selectedIds: [],
    })).toMatchObject({
      kind: "defaults",
      title: "New Rectangle",
      fields: {
        fillColor: { value: { kind: "single", value: "#FADB14" } },
      },
    });
  });

  it("derives every actual Rectangle property for a single selection", () => {
    const model = deriveContextRailModel({
      tool: "selection",
      document: fixtureDocument(),
      selectedIds: ["rect-1"],
    });

    expect(model).toMatchObject({
      kind: "single",
      title: "Rectangle",
      selectedIds: ["rect-1"],
      fields: {
        color: { value: { kind: "single", value: "#1677FF" } },
        fillColor: { value: { kind: "single", value: null } },
        strokeWidth: { value: { kind: "single", value: 4 } },
        roughness: { value: { kind: "single", value: 1 } },
        opacity: { value: { kind: "single", value: 1 } },
      },
    });
  });

  it.each([
    ["blur", "New Blur", "Radius 12 px · Fixed"],
    ["redaction", "New Redaction", "Opaque black · Fixed"],
  ] as const)("shows the fixed %s creation value", (tool, title, fixedValue) => {
    expect(deriveContextRailModel({
      tool,
      document: fixtureDocument(),
      selectedIds: [],
    })).toEqual({
      kind: "defaults",
      title,
      fields: {},
      fixedValue,
    });
  });

  it.each([
    [fixtureBlur(), "Blur", "Radius 12 px · Fixed"],
    [allElementFixtures().find((element) => element.type === "redaction")!, "Redaction", "Opaque black · Fixed"],
  ] as const)("shows the fixed value for a selected $type", (element, title, fixedValue) => {
    expect(deriveContextRailModel({
      tool: "selection",
      document: fixtureDocument({ elements: [element] }),
      selectedIds: [element.id],
    })).toMatchObject({
      kind: "single",
      title,
      fields: {},
      fixedValue,
    });
  });

  it("derives mixed values from every same-type selected element", () => {
    const first = fixtureRect();
    const second = {
      ...fixtureRect(),
      id: "rect-2",
      zIndex: 1,
      strokeColor: "#FF4D4F" as const,
      fillColor: "#FADB14" as const,
      strokeWidth: 8 as const,
      roughness: 2 as const,
      opacity: 0.5 as const,
    };
    const model = deriveContextRailModel({
      tool: "selection",
      document: fixtureDocument({ elements: [first, second] }),
      selectedIds: [first.id, second.id],
    });

    expect(model).toMatchObject({
      kind: "multi",
      title: "2 selected",
      fields: {
        color: { value: { kind: "mixed" } },
        fillColor: { value: { kind: "mixed" } },
        strokeWidth: { value: { kind: "mixed" } },
        roughness: { value: { kind: "mixed" } },
        opacity: { value: { kind: "mixed" } },
      },
    });
  });

  it("uses property intersection for Rectangle and Text", () => {
    const model = deriveContextRailModel({
      tool: "selection",
      document: fixtureDocument({ elements: [fixtureRect(), fixtureText()] }),
      selectedIds: ["rect-1", "text-1"],
    });

    expect(Object.keys(model.kind === "multi" ? model.fields : {})).toEqual([
      "color",
      "opacity",
    ]);
  });

  it("hides every unsupported field for Rectangle and Blur", () => {
    const model = deriveContextRailModel({
      tool: "selection",
      document: fixtureDocument({ elements: [fixtureRect(), fixtureBlur()] }),
      selectedIds: ["rect-1", "blur-1"],
    });

    expect(model).toMatchObject({ kind: "multi", fields: {} });
  });

  it("intersects allowed-value domains instead of copying the first type", () => {
    const highlighter = allElementFixtures().find((element) => element.type === "highlighter")!;
    const model = deriveContextRailModel({
      tool: "selection",
      document: fixtureDocument({ elements: [fixtureText(), highlighter] }),
      selectedIds: ["text-1", "highlighter-1"],
    });

    expect(model.kind === "multi" && model.fields.opacity?.allowedValues).toEqual([0.25, 0.5]);
  });

  it.each([
    ["color", [
      { ...fixtureRect(), strokeColor: "#000000" as const },
      { ...fixtureRect(), id: "rect-2", zIndex: 1, strokeColor: "#FF4D4F" as const },
    ]],
    ["fillColor", [
      { ...fixtureRect(), fillColor: null },
      { ...fixtureRect(), id: "rect-2", zIndex: 1, fillColor: "#1677FF" as const },
    ]],
    ["strokeWidth", [
      { ...fixtureRect(), strokeWidth: 2 as const },
      { ...fixtureRect(), id: "rect-2", zIndex: 1, strokeWidth: 8 as const },
    ]],
    ["roughness", [
      { ...fixtureRect(), roughness: 0 as const },
      { ...fixtureRect(), id: "rect-2", zIndex: 1, roughness: 2 as const },
    ]],
    ["textSize", [
      { ...fixtureText(), fontSize: 16 as const },
      { ...fixtureText(), id: "text-2", zIndex: 4, fontSize: 36 as const },
    ]],
    ["opacity", [
      { ...fixtureText(), opacity: 0.25 as const },
      { ...fixtureText(), id: "text-2", zIndex: 4, opacity: 1 as const },
    ]],
  ] satisfies Array<[RailPropertyKey, EditorElement[]]>)("represents mixed %s explicitly", (property, elements) => {
    const model = deriveContextRailModel({
      tool: "selection",
      document: fixtureDocument({ elements }),
      selectedIds: elements.map((element) => element.id),
    });

    const fields = model.kind === "multi" ? model.fields : {} as ContextRailFields;
    expect(fields[property]?.value).toEqual({ kind: "mixed" });
  });

  it("enables reorder actions only when the selection can cross a z-order edge", () => {
    const elements = [
      fixtureRect(),
      { ...fixtureText(), zIndex: 1 },
      { ...allElementFixtures().find((element) => element.type === "numberMarker")!, zIndex: 2 },
    ];
    const bottom = deriveContextRailModel({
      tool: "selection",
      document: fixtureDocument({ elements }),
      selectedIds: ["rect-1"],
    });
    const middle = deriveContextRailModel({
      tool: "selection",
      document: fixtureDocument({ elements }),
      selectedIds: ["text-1"],
    });
    const top = deriveContextRailModel({
      tool: "selection",
      document: fixtureDocument({ elements }),
      selectedIds: ["marker-1"],
    });

    expect(bottom.kind === "single" && bottom.actions).toMatchObject({
      canBringForward: true,
      canSendBackward: false,
    });
    expect(middle.kind === "single" && middle.actions).toMatchObject({
      canBringForward: true,
      canSendBackward: true,
    });
    expect(top.kind === "single" && top.actions).toMatchObject({
      canBringForward: false,
      canSendBackward: true,
    });
  });
});
