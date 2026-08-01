import { describe, expect, it } from "vitest";

import {
  textEditCommand,
  textEditPresentation,
  transitionTextEditSession,
  type TextEditSession,
} from "./textEditSession";
import { fixtureDocument, fixtureText } from "../test/fixtures";

describe("transitionTextEditSession", () => {
  const newSession = (): TextEditSession => ({
    kind: "new",
    point: { x: 32, y: 48 },
    defaults: structuredClone(fixtureDocument().defaults),
    initialText: "",
  });

  const existingSession = (): TextEditSession => {
    const element = fixtureText();
    return {
      kind: "existing",
      element,
      initialText: element.text,
    };
  };

  it("turns a non-empty new draft into one exact create transition", () => {
    expect(transitionTextEditSession(newSession(), {
      type: "commit",
      text: "  first line\nsecond line  ",
    })).toEqual({
      type: "create",
      point: { x: 32, y: 48 },
      defaults: fixtureDocument().defaults,
      text: "  first line\nsecond line  ",
    });
  });

  it("turns a blank new draft into a no-op", () => {
    expect(transitionTextEditSession(newSession(), {
      type: "commit",
      text: " \n\t ",
    })).toEqual({ type: "none" });
  });

  it("turns a non-empty existing draft into an exact update transition", () => {
    expect(transitionTextEditSession(existingSession(), {
      type: "commit",
      text: "  revised\ncopy  ",
    })).toEqual({
      type: "update",
      element: fixtureText(),
      text: "  revised\ncopy  ",
    });
  });

  it("turns a blank existing draft into a delete transition", () => {
    expect(transitionTextEditSession(existingSession(), {
      type: "commit",
      text: "\n   ",
    })).toEqual({ type: "delete", id: "text-1" });
  });

  it.each([newSession(), existingSession()])(
    "keeps the document untouched when a $kind session is cancelled",
    (session) => {
      const before = structuredClone(session);

      expect(transitionTextEditSession(session, { type: "cancel" }))
        .toEqual({ type: "none" });
      expect(session).toEqual(before);
    },
  );

  it("materializes a new commit as one complete create command", () => {
    const document = fixtureDocument({ elements: [] });

    expect(textEditCommand(
      document,
      newSession(),
      { type: "commit", text: "  exact\ntext  " },
      () => ({ width: 222, height: 66 }),
    )).toEqual({
      type: "create",
      element: {
        id: expect.any(String),
        type: "text",
        x: 32,
        y: 48,
        width: 222,
        height: 66,
        rotation: 0,
        opacity: 1,
        zIndex: 0,
        seed: 1,
        text: "  exact\ntext  ",
        color: "#1677FF",
        fontSize: 24,
      },
    });
  });

  it("derives the new overlay presentation from the same session policy", () => {
    expect(textEditPresentation(newSession())).toEqual({
      x: 32,
      y: 48,
      width: 160,
      height: 36,
      rotation: 0,
      color: "#1677FF",
      fontSize: 24,
    });
  });
});
