import { cleanup, fireEvent, render, screen, within } from "@testing-library/react";
import { afterEach, describe, expect, it, vi } from "vitest";

import { EditorApp } from "./App";
import type { EditorCommand, EditorDocument, PaletteColor } from "./model/elements";
import { fixtureDocument } from "./test/fixtures";

vi.mock("./canvas/EditorCanvas", () => ({
  EditorCanvas: ({ document, onCommand, rectangleFillColor }: {
    document: EditorDocument;
    onCommand: (command: EditorCommand) => void;
    rectangleFillColor: PaletteColor | null;
  }) => (
    <button
      type="button"
      onClick={() => onCommand({
        type: "create",
        element: {
          id: "rect-2",
          type: "rectangle",
          x: 10,
          y: 10,
          width: 20,
          height: 20,
          rotation: 0,
          opacity: document.defaults.opacity,
          zIndex: 1,
          seed: 2,
          strokeColor: document.defaults.color,
          strokeWidth: document.defaults.strokeWidth,
          fillColor: rectangleFillColor,
          roughness: document.defaults.roughness,
        },
      })}
    >
      Create rectangle from canvas
    </button>
  ),
}));

afterEach(cleanup);

describe("EditorApp", () => {
  it("shows the eight canvas tools", () => {
    render(<EditorApp initialDocument={fixtureDocument()} sourceImageURL="data:image/png;base64,iVBORw0KGgo=" onChange={() => {}} />);

    expect(within(screen.getByRole("navigation", { name: "Annotation tools" })).getAllByRole("button")).toHaveLength(8);
  });

  it("shows rectangle style controls and omits opacity for redaction", () => {
    render(<EditorApp initialDocument={fixtureDocument()} sourceImageURL="data:image/png;base64,iVBORw0KGgo=" onChange={() => {}} />);

    fireEvent.click(screen.getByRole("button", { name: "Rectangle" }));
    expect(screen.getByLabelText("Color")).toBeTruthy();
    expect(screen.getByLabelText("Stroke width")).toBeTruthy();
    expect(screen.getByLabelText("Fill")).toBeTruthy();
    expect(screen.getByLabelText("Roughness")).toBeTruthy();
    expect(screen.getByLabelText("Opacity")).toBeTruthy();

    fireEvent.click(screen.getByRole("button", { name: "Redaction" }));
    expect(screen.queryByLabelText("Opacity")).toBeNull();
  });

  it("keeps contextual defaults and rectangle fill through commands and undo", () => {
    const changes: EditorDocument[] = [];
    render(<EditorApp initialDocument={fixtureDocument()} sourceImageURL="data:image/png;base64,iVBORw0KGgo=" onChange={(document) => changes.push(document)} />);

    fireEvent.click(screen.getByRole("button", { name: "Rectangle" }));
    fireEvent.change(screen.getByLabelText("Color"), { target: { value: "#FF4D4F" } });
    fireEvent.change(screen.getByLabelText("Fill"), { target: { value: "#FADB14" } });
    fireEvent.click(screen.getByRole("button", { name: "Create rectangle from canvas" }));

    expect(changes.at(-1)).toMatchObject({
      defaults: { color: "#FF4D4F" },
      elements: [{ id: "rect-1" }, { strokeColor: "#FF4D4F", fillColor: "#FADB14" }],
    });

    fireEvent.keyDown(window, { key: "z", metaKey: true });
    expect(changes.at(-1)).toMatchObject({ defaults: { color: "#FF4D4F" }, elements: [{ id: "rect-1" }] });
  });
});
