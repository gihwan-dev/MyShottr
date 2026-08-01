import { render, screen } from "@testing-library/react";
import { isValidElement, type ReactNode } from "react";
import { describe, expect, it, vi } from "vitest";

import { fixtureRect, fixtureText } from "../test/fixtures";
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

  it("forwards the exact native pointer owner through drag and transform terminals", () => {
    const handlers = interactionHandlers();
    const container = document.createElement("div");
    const node = {
      getStage: () => ({ container: () => container }),
    };
    const rendered = renderElement(fixtureRect(), handlers);
    if (!isValidElement(rendered)) throw new Error("Expected a rendered element");
    const props = rendered.props as {
      onDragStart: (event: unknown) => void;
      onDragEnd: (event: unknown) => void;
      onTransformStart: (event: unknown) => void;
      onTransformEnd: (event: unknown) => void;
    };
    const event = { currentTarget: node, evt: { pointerId: 7 } };

    props.onDragStart(event);
    props.onDragEnd(event);
    props.onTransformStart(event);
    props.onTransformEnd(event);

    const owner = { pointerId: 7, container };
    expect(handlers.onDragStart).toHaveBeenCalledWith(node, owner);
    expect(handlers.onDragEnd).toHaveBeenCalledWith(owner);
    expect(handlers.onTransformStart).toHaveBeenCalledWith("rect-1", node, owner);
    expect(handlers.onTransformEnd).toHaveBeenCalledWith("rect-1", node, owner);
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
