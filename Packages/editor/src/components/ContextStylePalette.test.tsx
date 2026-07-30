import { cleanup, fireEvent, render, screen } from "@testing-library/react";
import { afterEach, describe, expect, it, vi } from "vitest";

import { ContextStylePalette } from "./ContextStylePalette";
import { allElementFixtures, fixtureBlur, fixtureDocument, fixtureRect, fixtureText } from "../test/fixtures";
import type { EditorElement } from "../model/elements";

describe("ContextStylePalette", () => {
  afterEach(cleanup);

  it("recolors only selected element types that support color", () => {
    const onElementsChange = vi.fn();
    render(<ContextStylePalette
      tool="selection"
      defaults={fixtureDocument().defaults}
      selectedElements={[fixtureRect(), fixtureBlur()]}
      onDefaultsChange={() => {}}
      onElementsChange={onElementsChange}
    />);

    fireEvent.change(screen.getByLabelText("Color"), { target: { value: "#FF4D4F" } });

    expect(onElementsChange).toHaveBeenCalledWith([
      expect.objectContaining({ id: "rect-1", strokeColor: "#FF4D4F" }),
      fixtureBlur(),
    ]);
  });

  it.each([
    {
      label: "stroke width",
      selected: [fixtureRect(), fixtureText()],
      control: "Stroke width",
      value: "8",
      verify: (elements: EditorElement[]) => {
        expect(elements[0]).toMatchObject({ strokeWidth: 8 });
        expect(elements[1]).toEqual(fixtureText());
      },
    },
    {
      label: "roughness",
      selected: [fixtureRect(), fixtureText()],
      control: "Roughness",
      value: "2",
      verify: (elements: EditorElement[]) => {
        expect(elements[0]).toMatchObject({ roughness: 2 });
        expect(elements[1]).toEqual(fixtureText());
      },
    },
    {
      label: "text size",
      selected: [fixtureText(), fixtureRect()],
      control: "Text size",
      value: "36",
      verify: (elements: EditorElement[]) => {
        expect(elements[0]).toMatchObject({ fontSize: 36 });
        expect(elements[1]).toEqual(fixtureRect());
      },
    },
  ])("applies $label only to selected types that support it", ({ selected, control, value, verify }) => {
    const onElementsChange = vi.fn();
    render(<ContextStylePalette
      tool="selection"
      defaults={fixtureDocument().defaults}
      selectedElements={selected}
      onDefaultsChange={() => {}}
      onElementsChange={onElementsChange}
    />);

    fireEvent.change(screen.getByLabelText(control), { target: { value } });

    verify(onElementsChange.mock.calls[0][0]);
  });

  it("represents mixed highlighter opacity explicitly and offers only shared values", () => {
    const onElementsChange = vi.fn();
    const highlighter = allElementFixtures().find((element) => element.type === "highlighter")!;
    const rectangle = fixtureRect();
    render(<ContextStylePalette
      tool="selection"
      defaults={fixtureDocument().defaults}
      selectedElements={[highlighter, rectangle]}
      onDefaultsChange={() => {}}
      onElementsChange={onElementsChange}
    />);

    const opacity = screen.getByLabelText("Opacity") as HTMLSelectElement;
    expect(opacity.value).toBe("");
    expect(Array.from(opacity.options).map((option) => option.value)).toEqual(["", "0.25", "0.5"]);
    fireEvent.change(opacity, { target: { value: "0.5" } });

    expect(onElementsChange).toHaveBeenCalledWith([
      expect.objectContaining({ type: "highlighter", opacity: 0.5 }),
      expect.objectContaining({ type: "rectangle", opacity: 0.5 }),
    ]);
  });

  it("leaves blur and redaction unchanged when applying opacity to a mixed selection", () => {
    const onElementsChange = vi.fn();
    const redaction = allElementFixtures().find((element) => element.type === "redaction")!;
    render(<ContextStylePalette
      tool="selection"
      defaults={fixtureDocument().defaults}
      selectedElements={[fixtureRect(), fixtureBlur(), redaction]}
      onDefaultsChange={() => {}}
      onElementsChange={onElementsChange}
    />);

    fireEvent.change(screen.getByLabelText("Opacity"), { target: { value: "0.5" } });

    expect(onElementsChange).toHaveBeenCalledWith([
      expect.objectContaining({ id: "rect-1", opacity: 0.5 }),
      fixtureBlur(),
      redaction,
    ]);
  });
});
