import { fireEvent, render, screen } from "@testing-library/react";
import { describe, expect, it, vi } from "vitest";

import { ContextStylePalette } from "./ContextStylePalette";
import { fixtureBlur, fixtureDocument, fixtureRect } from "../test/fixtures";

describe("ContextStylePalette", () => {
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
});
