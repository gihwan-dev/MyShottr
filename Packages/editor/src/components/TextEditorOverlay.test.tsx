import { cleanup, fireEvent, render, screen } from "@testing-library/react";
import { afterEach, describe, expect, it, vi } from "vitest";

import { TextEditorOverlay } from "./TextEditorOverlay";
import type { TextEditSession } from "./textEditSession";
import { fixtureDocument, fixtureText } from "../test/fixtures";

describe("TextEditorOverlay", () => {
  afterEach(cleanup);

  it("focuses one existing session and commits its exact value once when blur follows Command-Enter", () => {
    const onResult = vi.fn();
    render(<TextEditorOverlay
      session={existingSession()}
      zoom={1.5}
      pan={{ x: 12, y: 18 }}
      onResult={onResult}
    />);

    const editor = screen.getByRole("textbox", { name: "Edit annotation text" });
    expect(document.activeElement).toBe(editor);
    expect((editor as HTMLTextAreaElement).value).toBe("Annotate this");
    fireEvent.change(editor, { target: { value: "  Ship this\nnow  " } });
    fireEvent.keyDown(editor, { key: "Enter", metaKey: true });
    fireEvent.blur(editor);

    expect(onResult).toHaveBeenCalledOnce();
    expect(onResult).toHaveBeenCalledWith({
      type: "commit",
      text: "  Ship this\nnow  ",
    });
  });

  it("cancels once without a later blur commit", () => {
    const onResult = vi.fn();
    render(<TextEditorOverlay
      session={existingSession()}
      zoom={1}
      pan={{ x: 0, y: 0 }}
      onResult={onResult}
    />);

    const editor = screen.getByRole("textbox", { name: "Edit annotation text" });
    fireEvent.change(editor, { target: { value: "Discard me" } });
    fireEvent.keyDown(editor, { key: "Escape" });
    fireEvent.blur(editor);

    expect(onResult).toHaveBeenCalledOnce();
    expect(onResult).toHaveBeenCalledWith({ type: "cancel" });
  });

  it("leaves plain Return to the textarea so multiline text can be committed", () => {
    const onResult = vi.fn();
    render(<TextEditorOverlay
      session={newSession()}
      zoom={1}
      pan={{ x: 0, y: 0 }}
      onResult={onResult}
    />);

    const editor = screen.getByRole("textbox", { name: "Edit annotation text" });
    const plainReturn = new KeyboardEvent("keydown", {
      key: "Enter",
      bubbles: true,
      cancelable: true,
    });
    editor.dispatchEvent(plainReturn);
    expect(plainReturn.defaultPrevented).toBe(false);

    fireEvent.change(editor, { target: { value: "first\nsecond" } });
    fireEvent.blur(editor);
    expect(onResult).toHaveBeenCalledWith({
      type: "commit",
      text: "first\nsecond",
    });
  });

  it("positions a new session from its source anchor and recomputes after pan and zoom", () => {
    const onResult = vi.fn();
    const { rerender } = render(<TextEditorOverlay
      session={newSession()}
      zoom={1}
      pan={{ x: 4, y: 6 }}
      onResult={onResult}
    />);

    const editor = screen.getByRole("textbox", { name: "Edit annotation text" }) as HTMLTextAreaElement;
    expect(editor.style.left).toBe("44px");
    expect(editor.style.top).toBe("56px");
    expect(editor.style.width).toBe("160px");
    expect(editor.style.fontSize).toBe("24px");
    expect(editor.style.color).toBe("rgb(22, 119, 255)");

    rerender(<TextEditorOverlay
      session={newSession()}
      zoom={2}
      pan={{ x: 10, y: 20 }}
      onResult={onResult}
    />);

    expect(editor.style.left).toBe("90px");
    expect(editor.style.top).toBe("120px");
    expect(editor.style.width).toBe("320px");
    expect(editor.style.fontSize).toBe("48px");
    expect(onResult).not.toHaveBeenCalled();
  });

  it("positions a rotated existing session from its source element", () => {
    const session = existingSession();
    if (session.kind !== "existing") throw new Error("Expected existing text session");
    session.element = {
      ...session.element,
      x: 40,
      y: 50,
      width: 180,
      height: 36,
      rotation: 15,
    };
    render(<TextEditorOverlay
      session={session}
      zoom={1.5}
      pan={{ x: 12, y: 18 }}
      onResult={() => {}}
    />);

    const editor = screen.getByRole("textbox", { name: "Edit annotation text" }) as HTMLTextAreaElement;
    expect(editor.style.left).toBe("72px");
    expect(editor.style.top).toBe("93px");
    expect(editor.style.width).toBe("270px");
    expect(editor.style.fontSize).toBe("36px");
    expect(editor.style.transform).toBe("rotate(15deg)");
  });
});

function newSession(): TextEditSession {
  return {
    kind: "new",
    point: { x: 40, y: 50 },
    defaults: structuredClone(fixtureDocument().defaults),
    initialText: "",
  };
}

function existingSession(): TextEditSession {
  const element = fixtureText();
  return {
    kind: "existing",
    element,
    initialText: element.text,
  };
}
