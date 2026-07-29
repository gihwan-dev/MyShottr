import { afterEach, describe, expect, it, vi } from "vitest";
import { fixtureDocument } from "../test/fixtures";
import { renderDocumentToBlob } from "./renderDocumentToBlob";

describe("renderDocumentToBlob", () => {
  afterEach(() => {
    vi.unstubAllGlobals();
  });

  it("renders at the source pixel dimensions independently of viewport zoom", async () => {
    const canvas = document.createElement("canvas");
    const context = {
      globalAlpha: 1,
      save: vi.fn(), restore: vi.fn(), translate: vi.fn(), rotate: vi.fn(),
      drawImage: vi.fn(), beginPath: vi.fn(), rect: vi.fn(), stroke: vi.fn(), fill: vi.fn(),
      moveTo: vi.fn(), lineTo: vi.fn(), fillText: vi.fn(), arc: vi.fn(),
      closePath: vi.fn(),
      fillRect: vi.fn(), strokeRect: vi.fn(),
    } as unknown as CanvasRenderingContext2D;
    vi.spyOn(document, "createElement").mockReturnValue(canvas);
    vi.spyOn(canvas, "getContext").mockReturnValue(context);
    vi.spyOn(canvas, "toBlob").mockImplementation((callback) => callback(new Blob(["png"], { type: "image/png" })));
    vi.stubGlobal("Image", class {
      naturalWidth = 3000;
      naturalHeight = 2000;
      onload: (() => void) | null = null;
      onerror: (() => void) | null = null;
      set src(_value: string) { queueMicrotask(() => this.onload?.()); }
    });

    const blob = await renderDocumentToBlob(fixtureDocument({
      sourcePixelWidth: 3000,
      sourcePixelHeight: 2000,
    }), "myshottr-resource://document/AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE/original.png");

    expect(canvas.width).toBe(3000);
    expect(canvas.height).toBe(2000);
    expect(blob.type).toBe("image/png");
  });
});
