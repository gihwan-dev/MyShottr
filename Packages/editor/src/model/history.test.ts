import { describe, expect, it, vi } from "vitest";
import { fixtureDocument, fixtureLine, fixtureRect, fixtureText } from "../test/fixtures";
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

  it("creates a batch atomically with unique ids and z-indices", () => {
    const document = fixtureDocument();
    const next = applyCommand(document, {
      type: "createMany",
      elements: [
        { ...fixtureRect(), id: "rect-2", seed: 102, zIndex: 1 },
        { ...fixtureText(), id: "text-2", seed: 103, zIndex: 2 },
      ],
    });

    expect(next.elements.map((element) => element.id)).toEqual(["rect-1", "rect-2", "text-2"]);
    expect(next.elements.map((element) => element.zIndex)).toEqual([0, 1, 2]);
    expect(() => applyCommand(document, {
      type: "createMany",
      elements: [
        { ...fixtureRect(), id: "rect-2", seed: 102, zIndex: 1 },
        { ...fixtureText(), id: "rect-2", seed: 103, zIndex: 2 },
      ],
    })).toThrow();
  });

  it("moves a selected pair forward without duplicate z-indices", () => {
    const document = fixtureDocument({
      elements: [
        fixtureRect(),
        { ...fixtureText(), zIndex: 1 },
        { ...fixtureLine(), zIndex: 2 },
      ],
    });

    const next = applyCommand(document, {
      type: "reorder",
      ids: ["rect-1", "text-1"],
      direction: "forward",
    });

    expect(new Set(next.elements.map((element) => element.zIndex)).size).toBe(next.elements.length);
    expect([...next.elements].sort((left, right) => left.zIndex - right.zIndex).map((element) => element.id))
      .toEqual(["line-1", "rect-1", "text-1"]);
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

  it("keeps one stable snapshot until a validated document mutation", () => {
    const history = createHistoryStore(fixtureDocument());
    const initialSnapshot = history.getSnapshot();

    expect(history.getSnapshot()).toBe(initialSnapshot);

    history.beginTransaction("transform");
    expect(history.isTransactionActive).toBe(true);
    expect(history.canUndo).toBe(false);
    expect(history.canRedo).toBe(false);

    history.dispatch({ type: "update", element: { ...fixtureRect(), x: 20 } });

    expect(history.getSnapshot()).not.toBe(initialSnapshot);
    expect(history.getSnapshot()).toBe(history.document);
    history.commitTransaction();
    history.undo();

    expect(findElement(history.document, "rect-1").x).toBe(0);
  });

  it("notifies subscribers after document and defaults mutations", () => {
    const history = createHistoryStore(fixtureDocument());
    const listener = vi.fn();
    const unsubscribe = history.subscribe(listener);

    history.dispatch({ type: "update", element: { ...fixtureRect(), x: 20 } });
    history.setDefaults({ ...history.document.defaults, strokeWidth: 8 });
    unsubscribe();
    history.undo();

    expect(listener).toHaveBeenCalledTimes(2);
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

  it("applies createMany as one undoable command", () => {
    const history = createHistoryStore(fixtureDocument());
    history.dispatch({
      type: "createMany",
      elements: [
        { ...fixtureRect(), id: "rect-2", seed: 102, zIndex: 1 },
        { ...fixtureText(), id: "text-2", seed: 103, zIndex: 2 },
      ],
    });

    expect(history.document.elements).toHaveLength(3);
    expect(history.undo()).toBe(true);
    expect(history.document.elements.map((element) => element.id)).toEqual(["rect-1"]);
    expect(history.undo()).toBe(false);
  });

  it("keeps the latest defaults when undoing a scene command", () => {
    const history = createHistoryStore(fixtureDocument({ elements: [] }));
    history.dispatch({
      type: "create",
      element: { ...fixtureRect(), id: "new" },
    });
    history.setDefaults({
      ...history.document.defaults,
      rectangleFillColor: "#FADB14",
      highlighterOpacity: 0.25,
    });

    expect(history.undo()).toBe(true);
    expect(history.document.elements).toEqual([]);
    expect(history.document.defaults.rectangleFillColor).toBe("#FADB14");
    expect(history.document.defaults.highlighterOpacity).toBe(0.25);
  });

  it("does not add a history entry when defaults change", () => {
    const history = createHistoryStore(fixtureDocument());

    history.setDefaults({ ...history.document.defaults, strokeWidth: 8 });

    expect(history.canUndo).toBe(false);
    expect(history.canRedo).toBe(false);
  });
});
