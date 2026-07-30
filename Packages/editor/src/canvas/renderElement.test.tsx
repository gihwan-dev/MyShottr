import { render, screen } from "@testing-library/react";
import type { ReactNode } from "react";
import { describe, expect, it, vi } from "vitest";

import { fixtureText } from "../test/fixtures";
import { renderElement, type ElementInteractionHandlers } from "./renderElement";

vi.mock("react-konva", async () => {
  const React = await import("react");
  const primitive = ({ children }: { children?: ReactNode }) => React.createElement("div", null, children);
  return {
    Circle: primitive,
    Group: primitive,
    Image: primitive,
    Line: primitive,
    Path: primitive,
    Rect: primitive,
    Text: ({ text, lineHeight }: { text: string; lineHeight?: number }) => React.createElement(
      "div",
      { "data-testid": "konva-text", "data-line-height": lineHeight },
      text,
    ),
  };
});

describe("renderElement", () => {
  it("previews multiline text with the measured 1.2 line height", () => {
    render(renderElement(
      { ...fixtureText(), text: "First line\nSecond line", height: 58 },
      interactionHandlers(),
    ));

    const text = screen.getByTestId("konva-text");
    expect(text.textContent).toBe("First line\nSecond line");
    expect(text.getAttribute("data-line-height")).toBe("1.2");
  });
});

function interactionHandlers(): ElementInteractionHandlers {
  return {
    selected: false,
    draggable: false,
    textEditingEnabled: false,
    onSelect: vi.fn(),
    onEditText: vi.fn(),
    onDragStart: vi.fn(),
    onDragMove: vi.fn(),
    onDragEnd: vi.fn(),
    onTransformStart: vi.fn(),
    onTransformEnd: vi.fn(),
    registerNode: vi.fn(),
  };
}
