import { describe, expect, it } from "vitest";

import { keyboardCommandFor } from "./ShortcutRouter";

const idleContext = {
  interactionActive: false,
  shortcutHelpOpen: false,
  textEditing: false,
};

function commandFor(
  init: KeyboardEventInit,
  context = idleContext,
  target?: Element,
) {
  const event = new KeyboardEvent("keydown", {
    bubbles: true,
    cancelable: true,
    ...init,
  });
  if (target) {
    Object.defineProperty(event, "target", { value: target });
  }
  return keyboardCommandFor(event, context);
}

describe("keyboardCommandFor", () => {
  const toolCases = [
    ["KeyV", "selection"],
    ["KeyR", "rectangle"],
    ["KeyA", "arrow"],
    ["KeyL", "line"],
    ["KeyT", "text"],
    ["KeyP", "freehand"],
    ["KeyH", "highlighter"],
    ["KeyB", "blur"],
    ["KeyX", "redaction"],
    ["KeyN", "numberMarker"],
  ] as const;

  it.each(toolCases)("maps %s by code", (code, tool) => {
    expect(commandFor({ code, key: "Process" })).toEqual({
      type: "selectTool",
      tool,
    });
  });

  it("maps approved view and help shortcuts by code", () => {
    expect(commandFor({ code: "Digit1", key: "!", shiftKey: true }))
      .toEqual({ type: "fitImage" });
    expect(commandFor({ code: "Digit2", key: "@", shiftKey: true }))
      .toEqual({ type: "fitSelection" });
    expect(commandFor({ code: "Slash", key: "?", shiftKey: true }))
      .toEqual({ type: "openShortcutHelp" });
    expect(commandFor({ code: "Digit0", key: "0", metaKey: true }))
      .toEqual({ type: "zoom100" });
  });

  it("maps edit commands without adding Command-Y", () => {
    expect(commandFor({ code: "KeyZ", metaKey: true }))
      .toEqual({ type: "undo" });
    expect(commandFor({ code: "KeyZ", metaKey: true, shiftKey: true }))
      .toEqual({ type: "redo" });
    expect(commandFor({ code: "KeyD", metaKey: true }))
      .toEqual({ type: "duplicate" });
    expect(commandFor({ code: "KeyC", metaKey: true }))
      .toEqual({ type: "copy" });
    expect(commandFor({ code: "KeyV", metaKey: true }))
      .toEqual({ type: "paste" });
    expect(commandFor({ code: "BracketRight", metaKey: true }))
      .toEqual({ type: "bringForward" });
    expect(commandFor({ code: "BracketLeft", metaKey: true }))
      .toEqual({ type: "sendBackward" });
    expect(commandFor({ code: "Delete" })).toEqual({ type: "delete" });
    expect(commandFor({ code: "Backspace" })).toEqual({ type: "delete" });
    expect(commandFor({ code: "KeyY", metaKey: true })).toBeUndefined();
  });

  it.each([
    ["Copy Image", { code: "KeyC", metaKey: true, shiftKey: true }],
    ["Save Project", { code: "KeyS", metaKey: true }],
    ["Export PNG", { code: "KeyE", metaKey: true }],
  ] as const)("leaves native-owned %s untouched", (_label, init) => {
    const event = new KeyboardEvent("keydown", {
      bubbles: true,
      cancelable: true,
      ...init,
    });

    expect(keyboardCommandFor(event, idleContext)).toBeUndefined();
    expect(event.defaultPrevented).toBe(false);
  });

  it("suppresses composing events", () => {
    expect(commandFor({ code: "KeyR", isComposing: true }))
      .toBeUndefined();
  });

  it.each([
    ["input", document.createElement("input")],
    ["textarea", document.createElement("textarea")],
    ["select", document.createElement("select")],
  ])("suppresses events from %s", (_label, target) => {
    expect(commandFor({ code: "KeyR" }, idleContext, target))
      .toBeUndefined();
  });

  it("suppresses a contenteditable element and any of its descendants", () => {
    const editable = document.createElement("div");
    editable.setAttribute("contenteditable", "true");
    const child = document.createElement("span");
    editable.append(child);

    expect(commandFor({ code: "KeyR" }, idleContext, editable))
      .toBeUndefined();
    expect(commandFor({ code: "KeyR" }, idleContext, child))
      .toBeUndefined();
  });

  it("routes only Escape during an active interaction", () => {
    const context = { ...idleContext, interactionActive: true };

    expect(commandFor({ code: "KeyR" }, context)).toBeUndefined();
    expect(commandFor({ code: "KeyZ", metaKey: true }, context))
      .toBeUndefined();
    expect(commandFor({ code: "Escape" }, context))
      .toEqual({ type: "escape" });
  });

  it("routes only Escape while shortcut help is open", () => {
    const context = { ...idleContext, shortcutHelpOpen: true };

    expect(commandFor({ code: "KeyR" }, context)).toBeUndefined();
    expect(commandFor({ code: "Slash", shiftKey: true }, context))
      .toBeUndefined();
    expect(commandFor({ code: "Escape" }, context))
      .toEqual({ type: "escape" });
  });

  it("suppresses element Copy, Paste, and tool keys during inline text editing", () => {
    const context = { ...idleContext, textEditing: true };

    expect(commandFor({ code: "KeyC", metaKey: true }, context))
      .toBeUndefined();
    expect(commandFor({ code: "KeyV", metaKey: true }, context))
      .toBeUndefined();
    expect(commandFor({ code: "KeyR" }, context)).toBeUndefined();
    expect(commandFor({ code: "Escape" }, context))
      .toEqual({ type: "escape" });
  });
});
