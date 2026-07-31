import { cleanup, fireEvent, render, screen } from "@testing-library/react";
import { type ReactNode } from "react";
import { afterEach, describe, expect, it, vi } from "vitest";

import { EditorApp } from "../App";
import type { EditorCommand, EditorDocument } from "../model/elements";
import { fixtureDocument } from "../test/fixtures";

vi.mock("../canvas/EditorCanvas", () => ({
  EditorCanvas: ({ textEditorOverlay }: {
    document: EditorDocument;
    onCommand: (command: EditorCommand) => void;
    textEditorOverlay: ReactNode;
  }) => <div data-testid="editor-canvas">{textEditorOverlay}</div>,
}));

afterEach(() => {
  cleanup();
  vi.restoreAllMocks();
});

function renderEditor(initialTool: "selection" | "rectangle" = "selection") {
  return render(
    <EditorApp
      initialDocument={fixtureDocument()}
      initialTool={initialTool}
      sourceImageURL="data:image/png;base64,iVBORw0KGgo="
      onChange={() => {}}
      onPreferencesChange={() => {}}
    />,
  );
}

describe("shortcut UI", () => {
  it("renders palette hints and accessible tool state from the registry", () => {
    renderEditor("rectangle");

    const rectangle = screen.getByRole("button", {
      name: "Rectangle, shortcut R",
    });
    expect(rectangle.getAttribute("aria-pressed")).toBe("true");
    expect(rectangle.getAttribute("aria-describedby"))
      .toBe("tool-tip-rectangle");
    expect(screen.getByText("R").tagName).toBe("KBD");
    expect(screen.getByText("R").getAttribute("aria-hidden")).toBe("true");
    expect(screen.getByRole("tooltip", { name: "Rectangle · R" })).toBeTruthy();
  });

  it("opens a modal registry dialog and focuses its close button", () => {
    renderEditor();

    fireEvent.keyDown(window, {
      code: "Slash",
      key: "?",
      shiftKey: true,
    });

    const dialog = screen.getByRole("dialog", { name: "Keyboard Shortcuts" });
    expect(dialog.getAttribute("aria-modal")).toBe("true");
    expect(screen.getByRole("button", { name: "Close keyboard shortcuts" }))
      .toBe(document.activeElement);
    expect(screen.getByRole("heading", { name: "Output" })).toBeTruthy();
    expect(screen.getByText("Copy Image")).toBeTruthy();
    expect(screen.getByText("Save Project")).toBeTruthy();
    expect(screen.getByText("Export PNG")).toBeTruthy();
  });

  it("traps Tab and Shift-Tab within the dialog", () => {
    renderEditor();
    fireEvent.keyDown(window, { code: "Slash", shiftKey: true });
    const close = screen.getByRole("button", {
      name: "Close keyboard shortcuts",
    });

    fireEvent.keyDown(close, { code: "Tab", key: "Tab" });
    expect(document.activeElement).toBe(close);

    fireEvent.keyDown(close, {
      code: "Tab",
      key: "Tab",
      shiftKey: true,
    });
    expect(document.activeElement).toBe(close);
  });

  it("closes on Escape and restores the previously focused control", () => {
    renderEditor();
    const rectangle = screen.getByRole("button", {
      name: "Rectangle, shortcut R",
    });
    rectangle.focus();

    fireEvent.keyDown(window, { code: "Slash", shiftKey: true });
    expect(screen.getByRole("dialog", { name: "Keyboard Shortcuts" }))
      .toBeTruthy();

    fireEvent.keyDown(document.activeElement ?? window, {
      code: "Escape",
      key: "Escape",
    });

    expect(screen.queryByRole("dialog", { name: "Keyboard Shortcuts" }))
      .toBeNull();
    expect(document.activeElement).toBe(rectangle);
  });
});
