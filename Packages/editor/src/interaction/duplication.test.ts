import { describe, expect, it } from "vitest";

import { fixtureDocument, fixtureRect, fixtureText } from "../test/fixtures";
import { createDuplicateElements } from "./duplication";

describe("createDuplicateElements", () => {
  it("uses the default 12 by 12 source-space delta and fresh identities", () => {
    const source = fixtureRect();
    const copies = createDuplicateElements(
      fixtureDocument({ elements: [source] }),
      [source],
    );

    expect(copies).toHaveLength(1);
    expect(copies[0].id).not.toBe(source.id);
    expect(copies[0]).toMatchObject({
      x: source.x + 12,
      y: source.y + 12,
      zIndex: source.zIndex + 1,
      seed: source.seed + 1,
    });
  });

  it("assigns unique ids, z-indices, and seeds to every copy", () => {
    const rectangle = fixtureRect();
    const text = { ...fixtureText(), zIndex: 4, seed: 200 };

    const copies = createDuplicateElements(
      fixtureDocument({ elements: [rectangle, text] }),
      [rectangle, text],
    );

    expect(new Set(copies.map((element) => element.id)).size).toBe(2);
    expect(copies.every((element) => ![rectangle.id, text.id].includes(element.id))).toBe(true);
    expect(copies.map((element) => element.zIndex)).toEqual([5, 6]);
    expect(copies.map((element) => element.seed)).toEqual([201, 202]);
  });

  it("preserves source stacking when selection order is reversed", () => {
    const lower = { ...fixtureRect(), zIndex: 2 };
    const upper = { ...fixtureText(), zIndex: 9 };

    const [upperCopy, lowerCopy] = createDuplicateElements(
      fixtureDocument({ elements: [lower, upper] }),
      [upper, lower],
    );

    expect(upperCopy.id).not.toBe(upper.id);
    expect(lowerCopy.id).not.toBe(lower.id);
    expect(upperCopy.zIndex).toBeGreaterThan(lowerCopy.zIndex);
  });

  it("clamps one shared delta and preserves multi-selection spacing", () => {
    const rectangle = { ...fixtureRect(), width: 20, height: 20 };
    const text = {
      ...fixtureText(),
      x: 70,
      y: 70,
      width: 30,
      height: 30,
      zIndex: 1,
    };

    const copies = createDuplicateElements(
      fixtureDocument({
        sourcePixelWidth: 100,
        sourcePixelHeight: 100,
        elements: [rectangle, text],
      }),
      [rectangle, text],
    );

    expect(copies.map(({ x, y }) => ({ x, y }))).toEqual([
      { x: 0, y: 0 },
      { x: 70, y: 70 },
    ]);
    expect(copies[1].x - copies[0].x).toBe(70);
    expect(copies[1].y - copies[0].y).toBe(70);
  });

  it("uses the actual source-space Option-drag delta instead of the default", () => {
    const source = { ...fixtureRect(), x: 40, y: 50 };

    const [copy] = createDuplicateElements(
      fixtureDocument({ elements: [source] }),
      [source],
      { x: 25, y: -7 },
    );

    expect(copy).toMatchObject({ x: 65, y: 43 });
    expect(source).toMatchObject({ x: 40, y: 50 });
  });
});
