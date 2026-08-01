import { cleanup, fireEvent, render, screen, within } from "@testing-library/react";
import type { ReactNode } from "react";
import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";

import { App, EditorApp } from "./App";
import { NativeBridgeProvider, type NativeBridge } from "./bridge/nativeBridge";
import { keyboardCommandFor } from "./input/ShortcutRouter";
import type { EditorCommand, EditorDocument } from "./model/elements";
import { fixtureDocument, fixtureLine, fixtureRect, fixtureText } from "./test/fixtures";

vi.mock("./canvas/EditorCanvas", () => ({
  EditorCanvas: ({ document, onCommand, onSelect, onBeginTransaction, onCommitTransaction, onCancelTransaction, onEditText, textEditorOverlay }: {
    document: EditorDocument;
    onCommand: (command: EditorCommand) => void;
    onSelect: (id: string | undefined, toggle?: boolean) => void;
    onBeginTransaction: (label: string) => void;
    onCommitTransaction: () => void;
    onCancelTransaction: () => void;
    onEditText: (id: string) => void;
    textEditorOverlay: ReactNode;
  }) => (
    <>
      <output data-testid="canvas-opacities">
        {document.elements.map((element) => `${element.id}:${element.opacity}`).join(",")}
      </output>
      <button type="button" onClick={() => onSelect("rect-1")}>Select rect-1</button>
      <button type="button" onClick={() => onSelect("text-1", true)}>Shift-select text-1</button>
      <button type="button" onClick={() => onSelect("highlighter-1", true)}>Shift-select highlighter-1</button>
      <button type="button" onClick={() => onEditText("text-1")}>Edit text-1</button>
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
            fillColor: document.defaults.rectangleFillColor,
            roughness: document.defaults.roughness,
          },
        })}
      >
        Create rectangle from canvas
      </button>
      <button
        type="button"
        onClick={() => {
          onBeginTransaction("move");
          onCommand({
            type: "update",
            element: { ...document.elements[0], x: 40, y: 50 },
          });
          onCancelTransaction();
        }}
      >
        Move then cancel
      </button>
      <button type="button" onClick={() => onBeginTransaction("defaults")}>
        Begin defaults transaction
      </button>
      <button type="button" onClick={onCommitTransaction}>
        Commit transaction
      </button>
      <button
        type="button"
        onClick={() => {
          onBeginTransaction("move");
          onCommand({
            type: "update",
            element: { ...document.elements[0], x: 40, y: 50 },
          });
          onCommitTransaction();
        }}
      >
        Move then commit
      </button>
      {textEditorOverlay}
    </>
  ),
}));

beforeEach(() => {
  vi.spyOn(HTMLCanvasElement.prototype, "getContext").mockReturnValue({
    font: "",
    measureText: (text: string) => ({ width: text.length * 12 }),
  } as never);
});

afterEach(() => {
  cleanup();
  vi.restoreAllMocks();
});

describe("EditorApp", () => {
  it("edits existing text and commits one history command", () => {
    const changes: EditorDocument[] = [];
    render(<EditorApp
      initialDocument={fixtureDocument({ elements: [fixtureText()] })}
      initialTool="selection"
      sourceImageURL="data:image/png;base64,iVBORw0KGgo="
      onChange={(document) => changes.push(document)}
      onPreferencesChange={() => {}}
    />);

    fireEvent.click(screen.getByRole("button", { name: "Edit text-1" }));
    const editor = screen.getByRole("textbox", { name: "Edit annotation text" });
    fireEvent.change(editor, { target: { value: "Ship this" } });
    fireEvent.keyDown(editor, { key: "Enter", metaKey: true });

    expect(changes.at(-1)?.elements[0]).toMatchObject({ type: "text", text: "Ship this" });
    fireEvent.keyDown(window, { code: "KeyZ", key: "z", metaKey: true });
    expect(changes.at(-1)?.elements[0]).toMatchObject({ type: "text", text: "Annotate this" });
  });

  it("escapes text editing without changing the document", () => {
    const onChange = vi.fn();
    render(<EditorApp
      initialDocument={fixtureDocument({ elements: [fixtureText()] })}
      initialTool="selection"
      sourceImageURL="data:image/png;base64,iVBORw0KGgo="
      onChange={onChange}
      onPreferencesChange={() => {}}
    />);

    fireEvent.click(screen.getByRole("button", { name: "Edit text-1" }));
    const editor = screen.getByRole("textbox", { name: "Edit annotation text" });
    fireEvent.change(editor, { target: { value: "Discard me" } });
    fireEvent.keyDown(editor, { key: "Escape" });

    expect(onChange).not.toHaveBeenCalled();
    expect(screen.queryByRole("textbox", { name: "Edit annotation text" })).toBeNull();
  });

  it("deletes a text element when its committed text is empty", () => {
    const changes: EditorDocument[] = [];
    render(<EditorApp
      initialDocument={fixtureDocument({ elements: [fixtureText()] })}
      initialTool="selection"
      sourceImageURL="data:image/png;base64,iVBORw0KGgo="
      onChange={(document) => changes.push(document)}
      onPreferencesChange={() => {}}
    />);

    fireEvent.click(screen.getByRole("button", { name: "Edit text-1" }));
    const editor = screen.getByRole("textbox", { name: "Edit annotation text" });
    fireEvent.change(editor, { target: { value: "   " } });
    fireEvent.keyDown(editor, { key: "Enter", metaKey: true });

    expect(changes.at(-1)?.elements).toEqual([]);
  });

  it("applies a color change to the selected rectangle", () => {
    const changes: EditorDocument[] = [];
    render(<EditorApp
      initialDocument={fixtureDocument()}
      initialTool="selection"
      sourceImageURL="data:image/png;base64,iVBORw0KGgo="
      onChange={(document) => changes.push(document)}
      onPreferencesChange={() => {}}
    />);

    fireEvent.click(screen.getByRole("button", { name: "Select rect-1" }));
    fireEvent.click(within(screen.getByRole("radiogroup", { name: "Color" }))
      .getByRole("radio", { name: "Red" }));

    expect(changes.at(-1)?.elements[0]).toMatchObject({ strokeColor: "#FF4D4F" });
  });

  it("deletes every selected element in one command", () => {
    const changes: EditorDocument[] = [];
    render(<EditorApp
      initialDocument={fixtureDocument({ elements: [fixtureRect(), fixtureText()] })}
      initialTool="selection"
      sourceImageURL="data:image/png;base64,iVBORw0KGgo="
      onChange={(document) => changes.push(document)}
      onPreferencesChange={() => {}}
    />);

    fireEvent.click(screen.getByRole("button", { name: "Select rect-1" }));
    fireEvent.click(screen.getByRole("button", { name: "Shift-select text-1" }));
    fireEvent.keyDown(window, { code: "Delete", key: "Delete" });

    expect(changes.at(-1)?.elements).toEqual([]);
    fireEvent.keyDown(window, { code: "KeyZ", key: "z", metaKey: true });
    expect(changes.at(-1)?.elements.map((element) => element.id)).toEqual(["rect-1", "text-1"]);
  });

  it("duplicates every selected element atomically with unique identities", () => {
    const changes: EditorDocument[] = [];
    render(<EditorApp
      initialDocument={fixtureDocument({ elements: [fixtureRect(), fixtureText()] })}
      initialTool="selection"
      sourceImageURL="data:image/png;base64,iVBORw0KGgo="
      onChange={(document) => changes.push(document)}
      onPreferencesChange={() => {}}
    />);

    fireEvent.click(screen.getByRole("button", { name: "Select rect-1" }));
    fireEvent.click(screen.getByRole("button", { name: "Shift-select text-1" }));
    fireEvent.keyDown(window, { code: "KeyD", key: "d", metaKey: true });

    const duplicated = changes.at(-1)!;
    expect(duplicated.elements).toHaveLength(4);
    expect(new Set(duplicated.elements.map((element) => element.id)).size).toBe(4);
    expect(duplicated.elements.slice(2).map((element) => element.seed)).toEqual([104, 105]);
    expect(duplicated.elements.slice(2).map((element) => element.zIndex)).toEqual([4, 5]);
    expect(duplicated.elements.slice(2).map(({ x, y }) => ({ x, y }))).toEqual([
      { x: 12, y: 12 },
      { x: 52, y: 62 },
    ]);
    fireEvent.keyDown(window, { code: "KeyZ", key: "z", metaKey: true });
    expect(changes.at(-1)?.elements).toHaveLength(2);
  });

  it("selects rail duplicates returned by the one createMany command", () => {
    const changes: EditorDocument[] = [];
    render(<EditorApp
      initialDocument={fixtureDocument({ elements: [fixtureRect(), fixtureText()] })}
      initialTool="selection"
      sourceImageURL="data:image/png;base64,iVBORw0KGgo="
      onChange={(document) => changes.push(document)}
      onPreferencesChange={() => {}}
    />);

    fireEvent.click(screen.getByRole("button", { name: "Select rect-1" }));
    fireEvent.click(screen.getByRole("button", { name: "Shift-select text-1" }));
    fireEvent.click(screen.getByRole("button", { name: "Duplicate" }));
    expect(changes).toHaveLength(1);
    expect(changes[0].elements).toHaveLength(4);

    fireEvent.click(screen.getByRole("button", { name: "Delete" }));

    expect(changes).toHaveLength(2);
    expect(changes[1].elements.map((element) => element.id)).toEqual(["rect-1", "text-1"]);
  });

  it("copies and pastes a selected annotation without replacing its identity", () => {
    const changes: EditorDocument[] = [];
    render(<EditorApp
      initialDocument={fixtureDocument()}
      initialTool="selection"
      sourceImageURL="data:image/png;base64,iVBORw0KGgo="
      onChange={(document) => changes.push(document)}
      onPreferencesChange={() => {}}
    />);

    fireEvent.click(screen.getByRole("button", { name: "Select rect-1" }));
    fireEvent.keyDown(window, { code: "KeyC", key: "c", metaKey: true });
    fireEvent.keyDown(window, { code: "KeyV", key: "v", metaKey: true });

    const elements = changes.at(-1)?.elements ?? [];
    expect(elements).toHaveLength(2);
    expect(elements[1]).toMatchObject({ x: 12, y: 12 });
    expect(elements[1]?.id).not.toBe(elements[0]?.id);
  });

  it("does not turn command-v into the selection tool", () => {
    expect(keyboardCommandFor(
      new KeyboardEvent("keydown", { code: "KeyV", key: "v", metaKey: true }),
      {
        interactionActive: false,
        shortcutHelpOpen: false,
        textEditing: false,
      },
    )).toEqual({ type: "paste" });
  });

  it("uses one bounded duplicate offset for the whole selection", () => {
    const changes: EditorDocument[] = [];
    render(<EditorApp
      initialDocument={fixtureDocument({
        sourcePixelWidth: 100,
        sourcePixelHeight: 100,
        elements: [
          { ...fixtureRect(), width: 20, height: 20 },
          { ...fixtureText(), x: 70, y: 70, width: 30, height: 30, zIndex: 1 },
        ],
      })}
      initialTool="selection"
      sourceImageURL="data:image/png;base64,iVBORw0KGgo="
      onChange={(document) => changes.push(document)}
      onPreferencesChange={() => {}}
    />);

    fireEvent.click(screen.getByRole("button", { name: "Select rect-1" }));
    fireEvent.click(screen.getByRole("button", { name: "Shift-select text-1" }));
    fireEvent.keyDown(window, { code: "KeyD", key: "d", metaKey: true });

    expect(changes.at(-1)?.elements.slice(2).map(({ x, y }) => ({ x, y }))).toEqual([
      { x: 0, y: 0 },
      { x: 70, y: 70 },
    ]);
  });

  it("reorders every selected element from shortcuts and palette controls", () => {
    const changes: EditorDocument[] = [];
    render(<EditorApp
      initialDocument={fixtureDocument({
        elements: [fixtureRect(), { ...fixtureText(), zIndex: 1 }, { ...fixtureLine(), zIndex: 2 }],
      })}
      initialTool="selection"
      sourceImageURL="data:image/png;base64,iVBORw0KGgo="
      onChange={(document) => changes.push(document)}
      onPreferencesChange={() => {}}
    />);

    fireEvent.click(screen.getByRole("button", { name: "Select rect-1" }));
    fireEvent.click(screen.getByRole("button", { name: "Shift-select text-1" }));
    fireEvent.keyDown(window, { code: "BracketRight", key: "]", metaKey: true });

    expect([...changes.at(-1)!.elements].sort((left, right) => left.zIndex - right.zIndex).map((element) => element.id))
      .toEqual(["line-1", "rect-1", "text-1"]);

    fireEvent.click(screen.getByRole("button", { name: "Send Backward" }));
    expect([...changes.at(-1)!.elements].sort((left, right) => left.zIndex - right.zIndex).map((element) => element.id))
      .toEqual(["rect-1", "text-1", "line-1"]);
  });

  it("publishes selected tools and defaults as preferences without changing the document", () => {
    const onChange = vi.fn();
    const onPreferencesChange = vi.fn();
    render(<EditorApp
      initialDocument={fixtureDocument()}
      initialTool="arrow"
      sourceImageURL="data:image/png;base64,iVBORw0KGgo="
      onChange={onChange}
      onPreferencesChange={onPreferencesChange}
    />);

    expect(screen.getByRole("button", { name: "Arrow, shortcut A" }).getAttribute("aria-pressed")).toBe("true");
    fireEvent.click(within(screen.getByRole("radiogroup", { name: "Color" }))
      .getByRole("radio", { name: "Red" }));

    expect(onPreferencesChange).toHaveBeenLastCalledWith("arrow", expect.objectContaining({ color: "#FF4D4F" }));
    expect(onChange).not.toHaveBeenCalled();
  });

  it("publishes rectangle fill defaults to preferences without marking the document modified", () => {
    const onChange = vi.fn();
    const onPreferencesChange = vi.fn();
    render(<EditorApp
      initialDocument={fixtureDocument()}
      initialTool="rectangle"
      sourceImageURL="data:image/png;base64,iVBORw0KGgo="
      onChange={onChange}
      onPreferencesChange={onPreferencesChange}
    />);

    fireEvent.click(within(screen.getByRole("radiogroup", { name: "Fill" }))
      .getByRole("radio", { name: "Yellow" }));

    expect(onPreferencesChange).toHaveBeenLastCalledWith(
      "rectangle",
      expect.objectContaining({ rectangleFillColor: "#FADB14" }),
    );
    expect(onChange).not.toHaveBeenCalled();
  });

  it("updates highlighter color without replacing the shared opacity default", () => {
    const onPreferencesChange = vi.fn();
    render(<EditorApp
      initialDocument={fixtureDocument()}
      initialTool="highlighter"
      sourceImageURL="data:image/png;base64,iVBORw0KGgo="
      onChange={() => {}}
      onPreferencesChange={onPreferencesChange}
    />);

    fireEvent.click(within(screen.getByRole("radiogroup", { name: "Color" }))
      .getByRole("radio", { name: "Red" }));

    expect(onPreferencesChange).toHaveBeenLastCalledWith("highlighter", {
      ...fixtureDocument().defaults,
      color: "#FF4D4F",
    });
  });

  it("publishes a creation opacity default only when the slider gesture ends", () => {
    const onPreferencesChange = vi.fn();
    render(<EditorApp
      initialDocument={fixtureDocument()}
      initialTool="highlighter"
      sourceImageURL="data:image/png;base64,iVBORw0KGgo="
      onChange={() => {}}
      onPreferencesChange={onPreferencesChange}
    />);
    const slider = screen.getByRole("slider", { name: "Opacity" });

    fireEvent.input(slider, { target: { value: "25" } });
    expect(onPreferencesChange).not.toHaveBeenCalled();
    fireEvent.pointerUp(slider);

    expect(onPreferencesChange).toHaveBeenCalledOnce();
    expect(onPreferencesChange).toHaveBeenCalledWith(
      "highlighter",
      expect.objectContaining({
        opacity: 1,
        highlighterOpacity: 0.25,
      }),
    );
  });

  it("shows the ten canvas tools including blur and line", () => {
    render(<EditorApp initialDocument={fixtureDocument()} initialTool="selection" sourceImageURL="data:image/png;base64,iVBORw0KGgo=" onChange={() => {}} onPreferencesChange={() => {}} />);

    const palette = within(screen.getByRole("navigation", { name: "Annotation tools" }));
    expect(palette.getAllByRole("button")).toHaveLength(10);
    expect(palette.getByRole("button", { name: "Line, shortcut L" })).toBeTruthy();
    expect(palette.getByRole("button", { name: "Blur, shortcut B" })).toBeTruthy();
  });

  it("renders every tool as an icon button with label and shortcut", () => {
    render(<EditorApp initialDocument={fixtureDocument()} initialTool="selection" sourceImageURL="data:image/png;base64,iVBORw0KGgo=" onChange={() => {}} onPreferencesChange={() => {}} />);

    expect(screen.getByRole("button", { name: "Rectangle, shortcut R" }).getAttribute("aria-describedby"))
      .toBe("tool-tip-rectangle");
    expect(screen.getByRole("tooltip", { name: "Rectangle · R" })).toBeTruthy();
    expect(screen.getByRole("tooltip", { name: "Blur · B" })).toBeTruthy();
  });

  it("shows rectangle style controls and omits opacity for redaction", () => {
    render(<EditorApp initialDocument={fixtureDocument()} initialTool="selection" sourceImageURL="data:image/png;base64,iVBORw0KGgo=" onChange={() => {}} onPreferencesChange={() => {}} />);

    fireEvent.click(screen.getByRole("button", { name: "Rectangle, shortcut R" }));
    expect(screen.getByRole("radiogroup", { name: "Color" })).toBeTruthy();
    expect(screen.getByRole("radiogroup", { name: "Stroke width" })).toBeTruthy();
    expect(screen.getByRole("radiogroup", { name: "Fill" })).toBeTruthy();
    expect(screen.getByRole("radiogroup", { name: "Roughness" })).toBeTruthy();
    expect(screen.getByRole("slider", { name: "Opacity" })).toBeTruthy();

    fireEvent.click(screen.getByRole("button", { name: "Redaction, shortcut X" }));
    expect(screen.queryByRole("slider", { name: "Opacity" })).toBeNull();
    expect(screen.getByText("Opaque black · Fixed")).toBeTruthy();
  });

  it("keeps contextual defaults and rectangle fill through commands and undo", () => {
    const changes: EditorDocument[] = [];
    render(<EditorApp initialDocument={fixtureDocument()} initialTool="selection" sourceImageURL="data:image/png;base64,iVBORw0KGgo=" onChange={(document) => changes.push(document)} onPreferencesChange={() => {}} />);

    fireEvent.click(screen.getByRole("button", { name: "Rectangle, shortcut R" }));
    fireEvent.click(within(screen.getByRole("radiogroup", { name: "Color" }))
      .getByRole("radio", { name: "Red" }));
    fireEvent.click(within(screen.getByRole("radiogroup", { name: "Fill" }))
      .getByRole("radio", { name: "Yellow" }));
    fireEvent.click(screen.getByRole("button", { name: "Create rectangle from canvas" }));

    expect(changes.at(-1)).toMatchObject({
      defaults: { color: "#FF4D4F" },
      elements: [{ id: "rect-1" }, { strokeColor: "#FF4D4F", fillColor: "#FADB14" }],
    });

    fireEvent.keyDown(window, { code: "KeyZ", key: "z", metaKey: true });
    expect(changes.at(-1)).toMatchObject({ defaults: { color: "#FF4D4F" }, elements: [{ id: "rect-1" }] });
  });

  it("does not publish a document change for no-op undo or redo", () => {
    const onChange = vi.fn();
    render(<EditorApp initialDocument={fixtureDocument()} initialTool="selection" sourceImageURL="data:image/png;base64,iVBORw0KGgo=" onChange={onChange} onPreferencesChange={() => {}} />);

    fireEvent.keyDown(window, { code: "KeyZ", key: "z", metaKey: true });
    fireEvent.keyDown(window, { code: "KeyY", key: "y", metaKey: true });

    expect(onChange).not.toHaveBeenCalled();
  });

  it("leaves native Copy, Save, and Export shortcuts unprevented", () => {
    render(<EditorApp initialDocument={fixtureDocument()} initialTool="selection" sourceImageURL="data:image/png;base64,iVBORw0KGgo=" onChange={() => {}} onPreferencesChange={() => {}} />);

    [
      { code: "KeyC", metaKey: true, shiftKey: true },
      { code: "KeyS", metaKey: true },
      { code: "KeyE", metaKey: true },
    ].forEach((init) => {
      const event = new KeyboardEvent("keydown", {
        bubbles: true,
        cancelable: true,
        ...init,
      });
      window.dispatchEvent(event);
      expect(event.defaultPrevented).toBe(false);
    });
  });

  it("applies Escape priority one state at a time", () => {
    render(<EditorApp initialDocument={fixtureDocument()} initialTool="rectangle" sourceImageURL="data:image/png;base64,iVBORw0KGgo=" onChange={() => {}} onPreferencesChange={() => {}} />);

    fireEvent.keyDown(window, {
      code: "Slash",
      key: "?",
      shiftKey: true,
    });
    expect(screen.getByRole("dialog", { name: "Keyboard Shortcuts" }))
      .toBeTruthy();

    fireEvent.keyDown(
      screen.getByRole("button", { name: "Close keyboard shortcuts" }),
      { code: "Escape", key: "Escape" },
    );
    expect(screen.queryByRole("dialog", { name: "Keyboard Shortcuts" }))
      .toBeNull();
    expect(screen.getByRole("button", {
      name: "Rectangle, shortcut R",
    }).getAttribute("aria-pressed")).toBe("true");

    fireEvent.click(screen.getByRole("button", {
      name: "Begin defaults transaction",
    }));
    fireEvent.keyDown(window, { code: "Escape", key: "Escape" });
    expect(screen.getByRole("button", {
      name: "Rectangle, shortcut R",
    }).getAttribute("aria-pressed")).toBe("true");

    fireEvent.keyDown(window, { code: "Escape", key: "Escape" });
    expect(screen.getByRole("button", {
      name: "Selection, shortcut V",
    }).getAttribute("aria-pressed")).toBe("true");
  });

  it("clears selection only after Escape reaches the final priority", () => {
    render(<EditorApp initialDocument={fixtureDocument()} initialTool="selection" sourceImageURL="data:image/png;base64,iVBORw0KGgo=" onChange={() => {}} onPreferencesChange={() => {}} />);

    fireEvent.click(screen.getByRole("button", { name: "Select rect-1" }));
    expect(screen.getByRole("button", { name: "Send Backward" }))
      .toBeTruthy();

    fireEvent.keyDown(window, { code: "Escape", key: "Escape" });

    expect(screen.queryByRole("button", { name: "Send Backward" })).toBeNull();
  });

  it("previews selected opacity ephemerally and commits exactly one updateMany on release", () => {
    const changes: EditorDocument[] = [];
    render(<EditorApp
      initialDocument={fixtureDocument()}
      initialTool="selection"
      sourceImageURL="data:image/png;base64,iVBORw0KGgo="
      onChange={(document) => changes.push(document)}
      onPreferencesChange={() => {}}
    />);
    fireEvent.click(screen.getByRole("button", { name: "Select rect-1" }));
    const slider = screen.getByRole("slider", { name: "Opacity" });

    fireEvent.input(slider, { target: { value: "50" } });
    expect(screen.getByTestId("canvas-opacities").textContent).toBe("rect-1:0.5");
    expect(changes).toHaveLength(0);

    fireEvent.pointerUp(screen.getByRole("slider", { name: "Opacity" }), {
      target: { value: "50" },
    });
    expect(changes).toHaveLength(1);
    expect(changes[0].elements[0]).toMatchObject({ id: "rect-1", opacity: 0.5 });
  });

  it("discards a selected opacity preview on Escape without changing history", () => {
    const changes: EditorDocument[] = [];
    render(<EditorApp
      initialDocument={fixtureDocument()}
      initialTool="selection"
      sourceImageURL="data:image/png;base64,iVBORw0KGgo="
      onChange={(document) => changes.push(document)}
      onPreferencesChange={() => {}}
    />);
    fireEvent.click(screen.getByRole("button", { name: "Select rect-1" }));
    const slider = screen.getByRole("slider", { name: "Opacity" });

    fireEvent.input(slider, { target: { value: "50" } });
    fireEvent.keyDown(slider, { code: "Escape", key: "Escape" });

    expect(screen.getByTestId("canvas-opacities").textContent).toBe("rect-1:1");
    expect(changes).toHaveLength(0);
    fireEvent.keyDown(window, { code: "KeyZ", key: "z", metaKey: true });
    expect(changes).toHaveLength(0);
  });

  it("clears opacity preview and lock when selection and domain change mid-gesture", () => {
    const changes: EditorDocument[] = [];
    const highlighter = {
      id: "highlighter-1",
      type: "highlighter" as const,
      x: 80,
      y: 140,
      width: 120,
      height: 30,
      rotation: 0,
      opacity: 0.25 as const,
      zIndex: 1,
      seed: 105,
      points: [{ x: 80, y: 140 }, { x: 200, y: 170 }],
      color: "#FADB14" as const,
      strokeWidth: 8 as const,
    };
    render(<EditorApp
      initialDocument={fixtureDocument({ elements: [fixtureRect(), highlighter] })}
      initialTool="selection"
      sourceImageURL="data:image/png;base64,iVBORw0KGgo="
      onChange={(document) => changes.push(document)}
      onPreferencesChange={() => {}}
    />);
    fireEvent.click(screen.getByRole("button", { name: "Select rect-1" }));
    fireEvent.input(screen.getByRole("slider", { name: "Opacity" }), {
      target: { value: "75" },
    });
    expect(screen.getByTestId("canvas-opacities").textContent)
      .toBe("rect-1:0.75,highlighter-1:0.25");

    fireEvent.click(screen.getByRole("button", { name: "Shift-select highlighter-1" }));
    expect(screen.getByTestId("canvas-opacities").textContent)
      .toBe("rect-1:1,highlighter-1:0.25");
    expect(() => {
      fireEvent.pointerUp(screen.getByRole("slider", { name: "Opacity" }));
    }).not.toThrow();
    expect(changes).toHaveLength(0);

    fireEvent.keyDown(window, { code: "Escape", key: "Escape" });
    expect(screen.queryByLabelText("Context Rail")).toBeNull();
    expect(changes).toHaveLength(0);
  });

  it("ignores a late native opacity change after selection narrows the domain", () => {
    const changes: EditorDocument[] = [];
    const highlighter = {
      id: "highlighter-1",
      type: "highlighter" as const,
      x: 80,
      y: 140,
      width: 120,
      height: 30,
      rotation: 0,
      opacity: 0.25 as const,
      zIndex: 1,
      seed: 105,
      points: [{ x: 80, y: 140 }, { x: 200, y: 170 }],
      color: "#FADB14" as const,
      strokeWidth: 8 as const,
    };
    render(<EditorApp
      initialDocument={fixtureDocument({ elements: [fixtureRect(), highlighter] })}
      initialTool="selection"
      sourceImageURL="data:image/png;base64,iVBORw0KGgo="
      onChange={(document) => changes.push(document)}
      onPreferencesChange={() => {}}
    />);
    fireEvent.click(screen.getByRole("button", { name: "Select rect-1" }));
    fireEvent.input(screen.getByRole("slider", { name: "Opacity" }), {
      target: { value: "75" },
    });
    fireEvent.click(screen.getByRole("button", { name: "Shift-select highlighter-1" }));
    const narrowedSlider = screen.getByRole("slider", { name: "Opacity" });

    expect(() => {
      fireEvent.change(narrowedSlider, { target: { value: "50" } });
    }).not.toThrow();
    expect(screen.getByTestId("canvas-opacities").textContent)
      .toBe("rect-1:1,highlighter-1:0.25");
    expect(changes).toHaveLength(0);

    fireEvent.keyDown(window, { code: "Escape", key: "Escape" });
    expect(screen.queryByLabelText("Context Rail")).toBeNull();
    fireEvent.click(screen.getByRole("button", { name: "Select rect-1" }));
    fireEvent.click(screen.getByRole("button", { name: "Shift-select highlighter-1" }));
    const freshSlider = screen.getByRole("slider", { name: "Opacity" });
    fireEvent.input(freshSlider, { target: { value: "50" } });
    fireEvent.change(freshSlider, { target: { value: "25" } });

    expect(changes).toHaveLength(1);
    expect(changes[0].elements).toEqual([
      expect.objectContaining({ id: "rect-1", opacity: 0.5 }),
      expect.objectContaining({ id: "highlighter-1", opacity: 0.5 }),
    ]);
  });

  it("publishes the restored document when an active annotation transaction is cancelled", () => {
    const changes: EditorDocument[] = [];
    const initial = fixtureDocument();
    render(<EditorApp initialDocument={initial} initialTool="selection" sourceImageURL="data:image/png;base64,iVBORw0KGgo=" onChange={(document) => changes.push(document)} onPreferencesChange={() => {}} />);

    fireEvent.click(screen.getByRole("button", { name: "Move then cancel" }));

    expect(changes).toHaveLength(2);
    expect(changes[0].elements[0]).toMatchObject({ x: 40, y: 50 });
    expect(changes[1].elements).toEqual(initial.elements);
  });

  it("does not publish a scene change when a defaults-only transaction commits", () => {
    const onChange = vi.fn();
    const onPreferencesChange = vi.fn();
    render(<EditorApp
      initialDocument={fixtureDocument()}
      initialTool="rectangle"
      sourceImageURL="data:image/png;base64,iVBORw0KGgo="
      onChange={onChange}
      onPreferencesChange={onPreferencesChange}
    />);

    fireEvent.click(screen.getByRole("button", {
      name: "Begin defaults transaction",
    }));
    fireEvent.click(within(screen.getByRole("radiogroup", { name: "Fill" }))
      .getByRole("radio", { name: "Yellow" }));
    fireEvent.click(screen.getByRole("button", { name: "Commit transaction" }));

    expect(onPreferencesChange).toHaveBeenLastCalledWith(
      "rectangle",
      expect.objectContaining({ rectangleFillColor: "#FADB14" }),
    );
    expect(onChange).not.toHaveBeenCalled();
  });

  it("publishes a real scene transaction once through its scene command", () => {
    const onChange = vi.fn();
    render(<EditorApp
      initialDocument={fixtureDocument()}
      initialTool="selection"
      sourceImageURL="data:image/png;base64,iVBORw0KGgo="
      onChange={onChange}
      onPreferencesChange={() => {}}
    />);

    fireEvent.click(screen.getByRole("button", { name: "Move then commit" }));

    expect(onChange).toHaveBeenCalledOnce();
    expect(onChange).toHaveBeenCalledWith(
      expect.objectContaining({
        elements: [expect.objectContaining({ id: "rect-1", x: 40, y: 50 })],
      }),
    );
  });

  it("duplicates with an id that cannot collide with arbitrary loaded ids", () => {
    const changes: EditorDocument[] = [];
    const document = fixtureDocument({
      elements: [
        fixtureDocument().elements[0],
        { ...fixtureDocument().elements[0], id: "rectangle-102", x: 100, seed: 2, zIndex: 1 },
      ],
    });
    render(<EditorApp initialDocument={document} initialTool="selection" sourceImageURL="data:image/png;base64,iVBORw0KGgo=" onChange={(next) => changes.push(next)} onPreferencesChange={() => {}} />);

    fireEvent.click(screen.getByRole("button", { name: "Select rect-1" }));
    fireEvent.keyDown(window, { code: "KeyD", key: "d", metaKey: true });

    const duplicated = changes.at(-1)?.elements.at(-1);
    expect(duplicated?.id).not.toBe("rectangle-102");
    expect(new Set(changes.at(-1)?.elements.map((element) => element.id)).size).toBe(3);
    expect(duplicated?.seed).toBe(102);
  });

  it("acknowledges an accepted native document with the correlated snapshot", async () => {
    vi.stubGlobal("Image", class {
      naturalWidth = 1440;
      naturalHeight = 900;
      onload: (() => void) | null = null;
      set src(_value: string) { queueMicrotask(() => this.onload?.()); }
    });
    let receiveNative: ((message: Parameters<NativeBridge["subscribe"]>[0] extends (message: infer Message) => void ? Message : never) => void) | undefined;
    const sent: Array<{ requestId?: string; type: string; payload: unknown }> = [];
    const bridge: NativeBridge = {
      send: async (type, payload) => { sent.push({ type, payload }); },
      sendCorrelated: async (requestId, type, payload) => { sent.push({ requestId, type, payload }); },
      subscribe: (handler) => {
        receiveNative = handler;
        return () => { receiveNative = undefined; };
      },
    };

    render(<NativeBridgeProvider bridge={bridge}><App /></NativeBridgeProvider>);
    expect(sent).toContainEqual({ type: "editorReady", payload: {} });

    receiveNative!({
      protocolVersion: 1,
      requestId: "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE",
      type: "loadDocument",
      payload: {
        documentId: "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE",
        sourceImageURL: "myshottr-editor://editor/document/AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE/original.png",
        annotationDocument: fixtureDocument(),
        initialTool: "selection",
      },
    });

    expect(await screen.findByRole("main", { name: "MyShottr editor" })).toBeTruthy();
    expect(sent).toContainEqual({
      requestId: "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE",
      type: "annotationSnapshot",
      payload: { document: fixtureDocument() },
    });
  });

  it("returns a correlated annotation snapshot through the local native request event", async () => {
    vi.stubGlobal("Image", class {
      naturalWidth = 1440;
      naturalHeight = 900;
      onload: (() => void) | null = null;
      set src(_value: string) { queueMicrotask(() => this.onload?.()); }
    });
    let receiveNative: ((message: Parameters<NativeBridge["subscribe"]>[0] extends (message: infer Message) => void ? Message : never) => void) | undefined;
    const sent: Array<{ requestId?: string; type: string; payload: unknown }> = [];
    const bridge: NativeBridge = {
      send: async (type, payload) => { sent.push({ type, payload }); },
      sendCorrelated: async (requestId, type, payload) => { sent.push({ requestId, type, payload }); },
      subscribe: (handler) => { receiveNative = handler; return () => { receiveNative = undefined; }; },
    };

    render(<NativeBridgeProvider bridge={bridge}><App /></NativeBridgeProvider>);
    receiveNative!({
      protocolVersion: 1,
      requestId: "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE",
      type: "loadDocument",
      payload: {
        documentId: "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE",
        sourceImageURL: "myshottr-editor://editor/document/AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE/original.png",
        annotationDocument: fixtureDocument(),
        initialTool: "selection",
      },
    });
    await screen.findByRole("main", { name: "MyShottr editor" });

    window.dispatchEvent(new CustomEvent("myshottr:request-annotation-snapshot", {
      detail: { requestId: "FFFFFFFF-EEEE-DDDD-CCCC-BBBBBBBBBBBB" },
    }));

    await vi.waitFor(() => expect(sent).toContainEqual({
      requestId: "FFFFFFFF-EEEE-DDDD-CCCC-BBBBBBBBBBBB",
      type: "annotationSnapshot",
      payload: { document: fixtureDocument() },
    }));
  });

  it("returns the latest highlighter defaults in a later annotation snapshot", async () => {
    vi.stubGlobal("Image", class {
      naturalWidth = 1440;
      naturalHeight = 900;
      onload: (() => void) | null = null;
      set src(_value: string) { queueMicrotask(() => this.onload?.()); }
    });
    let receiveNative: ((message: Parameters<NativeBridge["subscribe"]>[0] extends (message: infer Message) => void ? Message : never) => void) | undefined;
    const sent: Array<{ requestId?: string; type: string; payload: unknown }> = [];
    const bridge: NativeBridge = {
      send: async (type, payload) => { sent.push({ type, payload }); },
      sendCorrelated: async (requestId, type, payload) => {
        sent.push({ requestId, type, payload });
      },
      subscribe: (handler) => {
        receiveNative = handler;
        return () => { receiveNative = undefined; };
      },
    };

    render(<NativeBridgeProvider bridge={bridge}><App /></NativeBridgeProvider>);
    receiveNative!({
      protocolVersion: 1,
      requestId: "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE",
      type: "loadDocument",
      payload: {
        documentId: "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE",
        sourceImageURL: "myshottr-editor://editor/document/AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE/original.png",
        annotationDocument: fixtureDocument(),
        initialTool: "selection",
      },
    });
    await screen.findByRole("main", { name: "MyShottr editor" });
    fireEvent.click(screen.getByRole("button", { name: "Highlighter, shortcut H" }));
    fireEvent.change(screen.getByRole("slider", { name: "Opacity" }), {
      target: { value: "25" },
    });

    window.dispatchEvent(new CustomEvent("myshottr:request-annotation-snapshot", {
      detail: { requestId: "FFFFFFFF-EEEE-DDDD-CCCC-BBBBBBBBBBBB" },
    }));

    await vi.waitFor(() => expect(sent).toContainEqual({
      requestId: "FFFFFFFF-EEEE-DDDD-CCCC-BBBBBBBBBBBB",
      type: "annotationSnapshot",
      payload: {
        document: {
          ...fixtureDocument(),
          defaults: {
            ...fixtureDocument().defaults,
            highlighterOpacity: 0.25,
          },
        },
      },
    }));
    expect(sent.some(({ type }) => type === "documentChanged")).toBe(false);
  });

  it("reports INVALID_DOCUMENT when the source image dimensions differ", async () => {
    vi.stubGlobal("Image", class {
      naturalWidth = 2;
      naturalHeight = 2;
      onload: (() => void) | null = null;
      set src(_value: string) { queueMicrotask(() => this.onload?.()); }
    });
    let receiveNative: ((message: Parameters<NativeBridge["subscribe"]>[0] extends (message: infer Message) => void ? Message : never) => void) | undefined;
    const sent: Array<{ requestId?: string; type: string; payload: unknown }> = [];
    const bridge: NativeBridge = {
      send: async (type, payload) => { sent.push({ type, payload }); },
      sendCorrelated: async (requestId, type, payload) => { sent.push({ requestId, type, payload }); },
      subscribe: (handler) => { receiveNative = handler; return () => { receiveNative = undefined; }; },
    };

    render(<NativeBridgeProvider bridge={bridge}><App /></NativeBridgeProvider>);
    receiveNative!({
      protocolVersion: 1,
      requestId: "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE",
      type: "loadDocument",
      payload: {
        documentId: "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE",
        sourceImageURL: "myshottr-editor://editor/document/AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE/original.png",
        annotationDocument: fixtureDocument(),
        initialTool: "selection",
      },
    });

    await vi.waitFor(() => expect(sent).toContainEqual({
      requestId: "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE",
      type: "bridgeError",
      payload: { code: "INVALID_DOCUMENT", message: "Source image dimensions do not match the document" },
    }));
    expect(screen.queryByRole("navigation", { name: "Annotation tools" })).toBeNull();
  });
});
