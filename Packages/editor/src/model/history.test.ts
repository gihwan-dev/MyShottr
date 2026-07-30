import { describe, expect, it } from "vitest";
import { fixtureDocument, fixtureRect, fixtureText } from "../test/fixtures";
import type { EditorElement } from "./elements";
import { findElement, applyCommand } from "./reducer";
import { createHistoryStore } from "./history";

describe("applyCommand", () => {
  it("returns a new document without mutating the input", () => {
    const document = fixtureDocument();
    const next = applyCommand(document, {
      type: "create",
      element: { ...fixtureRect(), id: "rect-2", zIndex: 1 },
    });

    expect(next).not.toBe(document);
    expect(next.elements).toHaveLength(2);
    expect(document.elements).toHaveLength(1);
  });

  it("rejects updates for missing ids and type-changing replacements", () => {
    const document = fixtureDocument();
    const rectangle = fixtureRect();
    const typeChanged: EditorElement = {
      id: rectangle.id,
      type: "redaction",
      x: rectangle.x,
      y: rectangle.y,
      width: rectangle.width,
      height: rectangle.height,
      rotation: rectangle.rotation,
      opacity: 1,
      zIndex: rectangle.zIndex,
      seed: rectangle.seed,
      color: "#000000",
    };

    expect(() => applyCommand(document, {
      type: "update",
      element: { ...fixtureRect(), id: "missing" },
    })).toThrow();
    expect(() => applyCommand(document, {
      type: "update",
      element: typeChanged,
    })).toThrow("Cannot change element type");
  });

  it("rejects commands that reference missing elements", () => {
    const document = fixtureDocument();

    expect(() => applyCommand(document, { type: "delete", ids: ["missing"] })).toThrow();
    expect(() => applyCommand(document, { type: "reorder", ids: ["missing"], direction: "forward" })).toThrow();
  });

  it("rejects updateMany commands with duplicate or missing element ids", () => {
    const document = fixtureDocument({ elements: [fixtureRect(), fixtureText()] });

    expect(() => applyCommand(document, {
      type: "updateMany",
      elements: [{ ...fixtureRect(), opacity: 0.5 }, { ...fixtureRect(), opacity: 0.5 }],
    })).toThrow("Cannot updateMany duplicate element ids");
    expect(() => applyCommand(document, {
      type: "updateMany",
      elements: [{ ...fixtureRect(), id: "missing" }],
    })).toThrow("Element not found: missing");
  });

  it("preserves existing z-index values for updateMany replacements", () => {
    const document = fixtureDocument({ elements: [fixtureRect(), fixtureText()] });

    const next = applyCommand(document, {
      type: "updateMany",
      elements: [
        { ...fixtureRect(), opacity: 0.5, zIndex: 99 },
        { ...fixtureText(), opacity: 0.5, zIndex: 100 },
      ],
    });

    expect(next.elements.map((element) => element.zIndex)).toEqual([0, 3]);
    expect(next.elements.map((element) => element.opacity)).toEqual([0.5, 0.5]);
  });
});

describe("createHistoryStore", () => {
  it("coalesces a transform drag into one undo entry", () => {
    const history = createHistoryStore(fixtureDocument());
    history.beginTransaction("transform");
    history.dispatch({
      type: "update",
      element: { ...findElement(history.document, "rect-1"), x: 10 },
    });
    history.dispatch({
      type: "update",
      element: { ...findElement(history.document, "rect-1"), x: 20 },
    });
    history.commitTransaction();

    history.undo();

    expect(findElement(history.document, "rect-1").x).toBe(0);
  });

  it("restores the transaction result on redo", () => {
    const history = createHistoryStore(fixtureDocument());
    history.beginTransaction("transform");
    history.dispatch({ type: "update", element: { ...fixtureRect(), x: 20 } });
    history.commitTransaction();
    history.undo();

    history.redo();

    expect(findElement(history.document, "rect-1").x).toBe(20);
  });

  it("clears redo history after a new command", () => {
    const history = createHistoryStore(fixtureDocument());
    history.dispatch({ type: "update", element: { ...fixtureRect(), x: 10 } });
    history.undo();
    history.dispatch({ type: "update", element: { ...fixtureRect(), x: 30 } });
    history.redo();

    expect(findElement(history.document, "rect-1").x).toBe(30);
  });

  it("isolates external document mutations from current and transaction history", () => {
    const history = createHistoryStore(fixtureDocument());
    history.beginTransaction("transform");
    findElement(history.document, "rect-1").x = 99;

    expect(findElement(history.document, "rect-1").x).toBe(0);

    history.dispatch({ type: "update", element: { ...fixtureRect(), x: 20 } });
    history.commitTransaction();
    history.undo();

    expect(findElement(history.document, "rect-1").x).toBe(0);
  });

  it("preserves redo and undo depth after a boundary reorder no-op", () => {
    const history = createHistoryStore(fixtureDocument());
    history.dispatch({ type: "update", element: { ...fixtureRect(), x: 10 } });
    history.undo();
    const beforeReorder = history.document;

    history.dispatch({ type: "reorder", ids: ["rect-1"], direction: "forward" });

    expect(history.document).toEqual(beforeReorder);
    history.redo();
    expect(findElement(history.document, "rect-1").x).toBe(10);
    history.undo();
    history.undo();
    expect(findElement(history.document, "rect-1").x).toBe(0);
  });

  it("applies updateMany as one undoable command", () => {
    const history = createHistoryStore(fixtureDocument({
      elements: [fixtureRect(), fixtureText()],
    }));
    history.dispatch({
      type: "updateMany",
      elements: [
        { ...fixtureRect(), opacity: 0.5 },
        { ...fixtureText(), opacity: 0.5 },
      ],
    });

    expect(history.undo()).toBe(true);
    expect(history.document.elements.map((element) => element.opacity)).toEqual([1, 1]);
  });
});
