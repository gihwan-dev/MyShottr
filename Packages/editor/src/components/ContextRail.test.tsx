import { cleanup, fireEvent, render, screen, within } from "@testing-library/react";
import { afterEach, describe, expect, it, vi } from "vitest";

import { fixtureDocument, fixtureRect, fixtureText } from "../test/fixtures";
import { ContextRail, type ContextRailIntent } from "./ContextRail";
import { deriveContextRailModel, type ContextRailModel } from "./contextRailModel";

describe("ContextRail", () => {
  afterEach(cleanup);

  it("renders direct accessible controls without a select", () => {
    const onIntent = vi.fn();
    render(<ContextRail
      model={deriveContextRailModel({
        tool: "rectangle",
        document: fixtureDocument(),
        selectedIds: [],
      })}
      onIntent={onIntent}
    />);

    const color = screen.getByRole("radiogroup", { name: "Color" });
    const blue = within(color).getByRole("radio", { name: "Blue" });
    expect(blue.getAttribute("aria-checked")).toBe("true");
    expect(screen.getByRole("radiogroup", { name: "Fill" })).toBeTruthy();
    expect(screen.getByRole("radiogroup", { name: "Stroke width" })).toBeTruthy();
    expect(screen.getByRole("radiogroup", { name: "Roughness" })).toBeTruthy();
    expect(screen.getByRole("slider", { name: "Opacity" })).toBeTruthy();
    expect(document.querySelector("select")).toBeNull();
    expect(screen.queryByRole("button", { name: "Delete" })).toBeNull();
  });

  it("emits one semantic property intent for one segmented-control activation", () => {
    const onIntent = vi.fn();
    render(<ContextRail
      model={deriveContextRailModel({
        tool: "selection",
        document: fixtureDocument(),
        selectedIds: ["rect-1"],
      })}
      onIntent={onIntent}
    />);

    fireEvent.click(within(screen.getByRole("radiogroup", { name: "Stroke width" }))
      .getByRole("radio", { name: "8 px" }));

    expect(onIntent).toHaveBeenCalledWith({
      type: "setSelectionProperty",
      property: "strokeWidth",
      value: 8,
    });
    expect(onIntent).toHaveBeenCalledTimes(1);
  });

  it("shows visible and accessible Mixed state with no selected option", () => {
    const second = {
      ...fixtureRect(),
      id: "rect-2",
      zIndex: 1,
      strokeColor: "#FF4D4F" as const,
      opacity: 0.5 as const,
    };
    render(<ContextRail
      model={deriveContextRailModel({
        tool: "selection",
        document: fixtureDocument({ elements: [fixtureRect(), second] }),
        selectedIds: ["rect-1", "rect-2"],
      })}
      onIntent={() => {}}
    />);

    const color = screen.getByRole("radiogroup", { name: "Color" });
    expect(within(color).getAllByRole("radio").every((radio) => radio.getAttribute("aria-checked") === "false")).toBe(true);
    const mixedDescription = document.getElementById(color.getAttribute("aria-describedby")!);
    expect(mixedDescription?.textContent).toBe("Mixed");
    expect(screen.getAllByText("Mixed").length).toBeGreaterThan(0);
    expect(screen.getByRole("slider", { name: "Opacity" }).getAttribute("aria-valuetext")).toBe("Mixed");
  });

  it("exposes a discrete opacity slider and selected preview/commit intents", () => {
    const onIntent = vi.fn();
    render(<ContextRail
      model={deriveContextRailModel({
        tool: "selection",
        document: fixtureDocument(),
        selectedIds: ["rect-1"],
      })}
      onIntent={onIntent}
    />);

    const slider = screen.getByRole("slider", { name: "Opacity" });
    expect(slider).toMatchObject({ min: "25", max: "100", step: "25" });
    expect(slider.getAttribute("aria-valuetext")).toBe("100%");

    fireEvent.input(slider, { target: { value: "50" } });
    expect(onIntent).toHaveBeenLastCalledWith({
      type: "previewSelectionOpacity",
      value: 0.5,
    });
    fireEvent.pointerUp(slider, { target: { value: "50" } });
    expect(onIntent).toHaveBeenLastCalledWith({
      type: "commitSelectionOpacity",
      value: 0.5,
    });
  });

  it("cancels a selected opacity gesture on Escape without a commit intent", () => {
    const intents: ContextRailIntent[] = [];
    render(<ContextRail
      model={deriveContextRailModel({
        tool: "selection",
        document: fixtureDocument(),
        selectedIds: ["rect-1"],
      })}
      onIntent={(intent) => intents.push(intent)}
    />);
    const slider = screen.getByRole("slider", { name: "Opacity" });

    fireEvent.input(slider, { target: { value: "50" } });
    fireEvent.keyDown(slider, { key: "Escape", code: "Escape" });

    expect(intents).toEqual([
      { type: "previewSelectionOpacity", value: 0.5 },
      { type: "cancelSelectionOpacity" },
    ]);
  });

  it("commits a keyboard opacity gesture once when the key is released", () => {
    const intents: ContextRailIntent[] = [];
    render(<ContextRail
      model={deriveContextRailModel({
        tool: "selection",
        document: fixtureDocument(),
        selectedIds: ["rect-1"],
      })}
      onIntent={(intent) => intents.push(intent)}
    />);
    const slider = screen.getByRole("slider", { name: "Opacity" });

    fireEvent.input(slider, { target: { value: "75" } });
    fireEvent.keyUp(slider, { key: "ArrowLeft", code: "ArrowLeft" });

    expect(intents).toEqual([
      { type: "previewSelectionOpacity", value: 0.75 },
      { type: "commitSelectionOpacity", value: 0.75 },
    ]);
  });

  it("cancels instead of committing when selection identity changes mid-gesture", () => {
    const intents: ContextRailIntent[] = [];
    const onIntent = (intent: ContextRailIntent) => intents.push(intent);
    const { rerender } = render(<ContextRail
      model={deriveContextRailModel({
        tool: "selection",
        document: fixtureDocument({
          elements: [fixtureRect(), fixtureText()],
        }),
        selectedIds: ["rect-1"],
      })}
      onIntent={onIntent}
    />);

    fireEvent.input(screen.getByRole("slider", { name: "Opacity" }), {
      target: { value: "75" },
    });
    rerender(<ContextRail
      model={deriveContextRailModel({
        tool: "selection",
        document: fixtureDocument({
          elements: [fixtureRect(), fixtureText()],
        }),
        selectedIds: ["text-1"],
      })}
      onIntent={onIntent}
    />);
    fireEvent.pointerUp(screen.getByRole("slider", { name: "Opacity" }));

    expect(intents).toEqual([
      { type: "previewSelectionOpacity", value: 0.75 },
      { type: "cancelSelectionOpacity" },
    ]);
  });

  it("cancels a stale gesture before a narrowed domain can parse its old value", () => {
    const intents: ContextRailIntent[] = [];
    const onIntent = (intent: ContextRailIntent) => intents.push(intent);
    const initialModel = deriveContextRailModel({
      tool: "selection",
      document: fixtureDocument(),
      selectedIds: ["rect-1"],
    });
    if (initialModel.kind !== "single" || !initialModel.fields.opacity) {
      throw new Error("Expected a selected Rectangle opacity field");
    }
    const narrowedModel = {
      ...initialModel,
      fields: {
        ...initialModel.fields,
        opacity: {
          ...initialModel.fields.opacity,
          value: { kind: "single", value: 0.5 },
          allowedValues: [0.25, 0.5],
        },
      },
    } satisfies ContextRailModel;
    const { rerender } = render(<ContextRail
      model={initialModel}
      onIntent={onIntent}
    />);

    fireEvent.input(screen.getByRole("slider", { name: "Opacity" }), {
      target: { value: "75" },
    });
    rerender(<ContextRail model={narrowedModel} onIntent={onIntent} />);

    expect(() => {
      fireEvent.pointerUp(screen.getByRole("slider", { name: "Opacity" }));
    }).not.toThrow();
    expect(intents).toEqual([
      { type: "previewSelectionOpacity", value: 0.75 },
      { type: "cancelSelectionOpacity" },
    ]);
  });

  it("ignores late native changes after a domain change until fresh input starts", () => {
    const intents: ContextRailIntent[] = [];
    const onIntent = (intent: ContextRailIntent) => intents.push(intent);
    const initialModel = deriveContextRailModel({
      tool: "selection",
      document: fixtureDocument(),
      selectedIds: ["rect-1"],
    });
    if (initialModel.kind !== "single" || !initialModel.fields.opacity) {
      throw new Error("Expected a selected Rectangle opacity field");
    }
    const narrowedModel = {
      ...initialModel,
      fields: {
        ...initialModel.fields,
        opacity: {
          ...initialModel.fields.opacity,
          value: { kind: "single", value: 0.5 },
          allowedValues: [0.25, 0.5],
        },
      },
    } satisfies ContextRailModel;
    const { rerender } = render(<ContextRail
      model={initialModel}
      onIntent={onIntent}
    />);

    fireEvent.input(screen.getByRole("slider", { name: "Opacity" }), {
      target: { value: "75" },
    });
    rerender(<ContextRail model={narrowedModel} onIntent={onIntent} />);
    const narrowedSlider = screen.getByRole("slider", { name: "Opacity" });

    expect(() => {
      fireEvent.change(narrowedSlider, { target: { value: "25" } });
      fireEvent.change(narrowedSlider, { target: { value: "50" } });
    }).not.toThrow();
    expect(intents).toEqual([
      { type: "previewSelectionOpacity", value: 0.75 },
      { type: "cancelSelectionOpacity" },
    ]);

    fireEvent.input(narrowedSlider, { target: { value: "50" } });
    fireEvent.change(narrowedSlider, { target: { value: "25" } });
    expect(intents).toEqual([
      { type: "previewSelectionOpacity", value: 0.75 },
      { type: "cancelSelectionOpacity" },
      { type: "previewSelectionOpacity", value: 0.5 },
      { type: "commitSelectionOpacity", value: 0.5 },
    ]);
  });

  it("renders exact selection action names and their edge enablement", () => {
    render(<ContextRail
      model={deriveContextRailModel({
        tool: "selection",
        document: fixtureDocument({
          elements: [fixtureRect(), { ...fixtureText(), zIndex: 1 }],
        }),
        selectedIds: ["rect-1"],
      })}
      onIntent={() => {}}
    />);

    expect(screen.getByRole("button", { name: "Bring Forward" }).hasAttribute("disabled")).toBe(false);
    expect(screen.getByRole("button", { name: "Send Backward" }).hasAttribute("disabled")).toBe(true);
    expect(screen.getByRole("button", { name: "Duplicate" })).toBeTruthy();
    expect(screen.getByRole("button", { name: "Delete" })).toBeTruthy();
  });
});
