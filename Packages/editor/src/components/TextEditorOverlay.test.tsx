import { cleanup, fireEvent, render, screen } from "@testing-library/react";
import { afterEach, describe, expect, it, vi } from "vitest";

import { TextEditorOverlay } from "./TextEditorOverlay";
import { fixtureText } from "../test/fixtures";

describe("TextEditorOverlay", () => {
  afterEach(cleanup);

  it("commits the entered text once and maps a rotated source element to screen coordinates", () => {
    const onCommit = vi.fn();
    render(<TextEditorOverlay
      element={{ ...fixtureText(), x: 40, y: 50, width: 180, height: 36, rotation: 15 }}
      zoom={1.5}
      pan={{ x: 12, y: 18 }}
      onCommit={onCommit}
      onCancel={() => {}}
    />);

    const editor = screen.getByRole("textbox", { name: "Edit annotation text" });
    expect((editor as HTMLTextAreaElement).style.cssText).toContain("left: 72px");
    expect((editor as HTMLTextAreaElement).style.cssText).toContain("top: 93px");
    expect((editor as HTMLTextAreaElement).style.cssText).toContain("width: 270px");
    expect((editor as HTMLTextAreaElement).style.cssText).toContain("font-size: 36px");
    expect((editor as HTMLTextAreaElement).style.cssText).toContain("transform: rotate(15deg)");
    fireEvent.change(editor, { target: { value: "Ship this" } });
    fireEvent.keyDown(editor, { key: "Enter", metaKey: true });
    fireEvent.blur(editor);

    expect(onCommit).toHaveBeenCalledTimes(1);
    expect(onCommit).toHaveBeenCalledWith("Ship this");
  });

  it("cancels without committing when Escape is pressed", () => {
    const onCommit = vi.fn();
    const onCancel = vi.fn();
    render(<TextEditorOverlay element={fixtureText()} zoom={1} pan={{ x: 0, y: 0 }} onCommit={onCommit} onCancel={onCancel} />);

    fireEvent.keyDown(screen.getByRole("textbox", { name: "Edit annotation text" }), { key: "Escape" });

    expect(onCancel).toHaveBeenCalledOnce();
    expect(onCommit).not.toHaveBeenCalled();
  });
});
