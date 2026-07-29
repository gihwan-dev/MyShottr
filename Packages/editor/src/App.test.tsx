import { cleanup, fireEvent, render, screen } from "@testing-library/react";
import { afterEach, describe, expect, it, vi } from "vitest";

vi.mock("./canvas/EditorCanvas", () => ({
  EditorCanvas: () => <div data-testid="editor-canvas" />,
}));

afterEach(cleanup);
import { EditorApp } from "./App";
import { fixtureDocument } from "./test/fixtures";

describe("EditorApp", () => {
  it("shows the eight canvas tools", () => {
    render(<EditorApp initialDocument={fixtureDocument()} sourceImageURL="data:image/png;base64,iVBORw0KGgo=" onChange={() => {}} />);

    expect(screen.getAllByRole("button", { name: /select|rectangle|arrow|text|freehand|highlighter|redaction|number marker/i })).toHaveLength(8);
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
});
