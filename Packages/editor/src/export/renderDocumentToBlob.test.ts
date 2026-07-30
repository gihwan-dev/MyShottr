import { afterEach, describe, expect, it, vi } from "vitest";
import * as roughRenderer from "../canvas/roughRenderer";
import { roughPathsFor } from "../canvas/roughRenderer";
import { fixtureBlur, fixtureDocument, fixtureLine, fixtureRect } from "../test/fixtures";
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
      drawImage: vi.fn(), beginPath: vi.fn(), rect: vi.fn(), clip: vi.fn(), stroke: vi.fn(), fill: vi.fn(),
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
    vi.stubGlobal("Path2D", class { constructor(_path: string) {} });

    const blob = await renderDocumentToBlob(fixtureDocument({
      sourcePixelWidth: 3000,
      sourcePixelHeight: 2000,
    }), "myshottr-editor://editor/document/AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE/original.png");

    expect(canvas.width).toBe(3000);
    expect(canvas.height).toBe(2000);
    expect(blob.type).toBe("image/png");
  });

  it("uses the live rough path generator for seeded rectangles and arrows", async () => {
    const canvas = document.createElement("canvas");
    const context = canvasContext();
    const pathData: string[] = [];
    vi.spyOn(document, "createElement").mockReturnValue(canvas);
    vi.spyOn(canvas, "getContext").mockReturnValue(context);
    vi.spyOn(canvas, "toBlob").mockImplementation((callback) => callback(new Blob(["png"], { type: "image/png" })));
    vi.stubGlobal("Image", loadedImage(1440, 900));
    vi.stubGlobal("Path2D", class {
      constructor(path: string) { pathData.push(path); }
    });
    const rectangle = { ...fixtureRect(), fillColor: "#FADB14" as const, roughness: 2 as const, seed: 711 };
    const arrow = {
      id: "arrow-1", type: "arrow" as const, x: 20, y: 25, width: 100, height: 40,
      rotation: 0, opacity: 1 as const, zIndex: 1, seed: 712,
      points: [{ x: 20, y: 25 }, { x: 120, y: 65 }] as [{ x: number; y: number }, { x: number; y: number }],
      strokeColor: "#FF4D4F" as const, strokeWidth: 2 as const, roughness: 1 as const,
    };

    await renderDocumentToBlob(fixtureDocument({ elements: [arrow, rectangle] }), "source.png");

    expect(pathData).toEqual([...roughPathsFor(rectangle), ...roughPathsFor(arrow)].map((path) => path.d));
    expect(context.stroke).toHaveBeenCalledTimes(pathData.length);
  });

  it("exports line with its stored rough seed", async () => {
    const canvas = document.createElement("canvas");
    const context = canvasContext();
    const path2D = vi.fn();
    vi.spyOn(document, "createElement").mockReturnValue(canvas);
    vi.spyOn(canvas, "getContext").mockReturnValue(context);
    vi.spyOn(canvas, "toBlob").mockImplementation((callback) => callback(new Blob(["png"], { type: "image/png" })));
    vi.stubGlobal("Image", loadedImage(1440, 900));
    vi.stubGlobal("Path2D", class {
      constructor(path: string) { path2D(path); }
    });

    await renderDocumentToBlob(fixtureDocument({ elements: [fixtureLine()] }), "source.png");

    expect(path2D).toHaveBeenCalledWith(expect.stringMatching(/\S+/));
    expect(path2D).toHaveBeenCalledTimes(1);
  });

  it("renders one seeded line shaft and three seeded arrow parts", () => {
    const arrow = {
      id: "arrow-parts", type: "arrow" as const, x: 20, y: 25, width: 100, height: 40,
      rotation: 0, opacity: 1 as const, zIndex: 1, seed: 712,
      points: [{ x: 20, y: 25 }, { x: 120, y: 65 }] as [{ x: number; y: number }, { x: number; y: number }],
      strokeColor: "#FF4D4F" as const, strokeWidth: 2 as const, roughness: 1 as const,
    };

    expect(roughPathsFor(fixtureLine())).toHaveLength(1);
    expect(roughPathsFor(arrow)).toHaveLength(3);
  });

  it("does not fill rough paths whose sentinel is none", async () => {
    const unfilledCanvas = document.createElement("canvas");
    const filledCanvas = document.createElement("canvas");
    const unfilledContext = canvasContext();
    const unfilledFillStyles: string[] = [];
    const createElement = vi.spyOn(document, "createElement").mockReturnValue(unfilledCanvas);
    vi.spyOn(unfilledCanvas, "getContext").mockReturnValue(unfilledContext);
    vi.spyOn(unfilledCanvas, "toBlob").mockImplementation((callback) => callback(new Blob(["png"], { type: "image/png" })));
    vi.stubGlobal("Image", loadedImage(1440, 900));
    vi.stubGlobal("Path2D", class { constructor(_path: string) {} });
    unfilledContext.fill.mockImplementation(() => unfilledFillStyles.push(unfilledContext.fillStyle as string));
    const unfilledRectangle = { ...fixtureRect(), fillColor: null, seed: 713 };
    const arrow = {
      id: "arrow-unfilled", type: "arrow" as const, x: 20, y: 25, width: 100, height: 40,
      rotation: 0, opacity: 1 as const, zIndex: 1, seed: 714,
      points: [{ x: 20, y: 25 }, { x: 120, y: 65 }] as [{ x: number; y: number }, { x: number; y: number }],
      strokeColor: "#FF4D4F" as const, strokeWidth: 2 as const, roughness: 1 as const,
    };

    await renderDocumentToBlob(fixtureDocument({ elements: [unfilledRectangle, arrow] }), "source.png");

    expect(roughPathsFor(unfilledRectangle).some((path) => path.fill === "none")).toBe(true);
    expect(roughPathsFor(arrow).some((path) => path.fill === "none")).toBe(true);
    expect(unfilledContext.fill).not.toHaveBeenCalled();
    expect(unfilledFillStyles).not.toContain("none");

    const filledContext = canvasContext();
    const filledFillStyles: string[] = [];
    createElement.mockReturnValue(filledCanvas);
    vi.spyOn(filledCanvas, "getContext").mockReturnValue(filledContext);
    vi.spyOn(filledCanvas, "toBlob").mockImplementation((callback) => callback(new Blob(["png"], { type: "image/png" })));
    filledContext.fill.mockImplementation(() => filledFillStyles.push(filledContext.fillStyle as string));
    const filledRectangle = { ...fixtureRect(), fillColor: "#FADB14" as const, seed: 715 };
    const filledPath = {
      d: roughPathsFor(filledRectangle)[0].d,
      fill: "#FADB14",
      stroke: "none",
      strokeWidth: 0,
    };
    const roughPathsForSpy = vi.spyOn(roughRenderer, "roughPathsFor").mockReturnValue([filledPath]);

    await renderDocumentToBlob(fixtureDocument({ elements: [filledRectangle] }), "source.png");

    expect(filledContext.fill).toHaveBeenCalledTimes(1);
    expect(filledFillStyles).toContain("#FADB14");
    roughPathsForSpy.mockRestore();
  });

  it("uses the live number-marker text size", async () => {
    const canvas = document.createElement("canvas");
    const context = canvasContext();
    const fonts: string[] = [];
    Object.defineProperty(context, "font", { set: (value: string) => fonts.push(value) });
    vi.spyOn(document, "createElement").mockReturnValue(canvas);
    vi.spyOn(canvas, "getContext").mockReturnValue(context);
    vi.spyOn(canvas, "toBlob").mockImplementation((callback) => callback(new Blob(["png"], { type: "image/png" })));
    vi.stubGlobal("Image", loadedImage(1440, 900));
    const marker = {
      id: "marker-1", type: "numberMarker" as const, x: 20, y: 25, width: 32, height: 32,
      rotation: 0, opacity: 1 as const, zIndex: 0, seed: 1, number: 1, color: "#FF4D4F" as const,
    };

    await renderDocumentToBlob(fixtureDocument({ elements: [marker] }), "source.png");

    expect(fonts).toContain("12px Arial");
  });

  it("exports each multiline text line at the measured 1.2 line height", async () => {
    const canvas = document.createElement("canvas");
    const context = canvasContext();
    vi.spyOn(document, "createElement").mockReturnValue(canvas);
    vi.spyOn(canvas, "getContext").mockReturnValue(context);
    vi.spyOn(canvas, "toBlob").mockImplementation((callback) => callback(new Blob(["png"], { type: "image/png" })));
    vi.stubGlobal("Image", loadedImage(1440, 900));
    const text = {
      id: "text-multiline",
      type: "text" as const,
      x: 40,
      y: 50,
      width: 180,
      height: 58,
      rotation: 0,
      opacity: 1 as const,
      zIndex: 0,
      seed: 11,
      text: "First line\nSecond line",
      color: "#000000" as const,
      fontSize: 24 as const,
    };

    await renderDocumentToBlob(fixtureDocument({ elements: [text] }), "source.png");

    expect(context.fillText).toHaveBeenNthCalledWith(1, "First line", 0, 0, 180);
    expect(context.fillText).toHaveBeenNthCalledWith(2, "Second line", 0, expect.any(Number), 180);
    expect(vi.mocked(context.fillText).mock.calls[1][2]).toBeCloseTo(28.8);
    expect(context.fillText).toHaveBeenCalledTimes(2);
  });

  it("draws blur before vector annotations during export", async () => {
    const outputCanvas = document.createElement("canvas");
    const drawOperations: string[] = [];
    const outputContext = canvasContext();
    const drawImage = outputContext.drawImage as unknown as { mockImplementation: (implementation: (image: unknown) => void) => void };
    const fillText = outputContext.fillText as unknown as { mockImplementation: (implementation: () => void) => void };
    drawImage.mockImplementation((image: unknown) => {
      if (outputContext.filter === "blur(12px)") return;
      drawOperations.push(image === outputCanvas ? "blurred-source-crop" : "source");
    });
    const createElement = vi.spyOn(document, "createElement").mockReturnValue(outputCanvas);
    vi.spyOn(outputCanvas, "getContext").mockReturnValue(outputContext);
    vi.spyOn(outputCanvas, "toBlob").mockImplementation((callback) => callback(new Blob(["png"], { type: "image/png" })));
    vi.stubGlobal("Image", loadedImage(1440, 900));
    const text = { ...fixtureDocument().elements[0], id: "text-1", type: "text" as const, x: 40, y: 50, width: 180, height: 36, zIndex: 1, text: "After blur", color: "#000000" as const, fontSize: 24 as const };
    fillText.mockImplementation(() => drawOperations.push("text"));

    await renderDocumentToBlob(fixtureDocument({ elements: [text, fixtureBlur()] }), "source.png");

    expect(createElement).toHaveBeenCalledTimes(2);
    expect(drawOperations).toEqual(["source", "blurred-source-crop", "text"]);
  });
});

function canvasContext(): CanvasRenderingContext2D & { stroke: ReturnType<typeof vi.fn>; fill: ReturnType<typeof vi.fn> } {
  return {
    globalAlpha: 1,
    save: vi.fn(), restore: vi.fn(), translate: vi.fn(), rotate: vi.fn(),
    drawImage: vi.fn(), beginPath: vi.fn(), rect: vi.fn(), clip: vi.fn(), stroke: vi.fn(), fill: vi.fn(),
    moveTo: vi.fn(), lineTo: vi.fn(), fillText: vi.fn(), arc: vi.fn(),
    closePath: vi.fn(), fillRect: vi.fn(), strokeRect: vi.fn(),
  } as unknown as CanvasRenderingContext2D & { stroke: ReturnType<typeof vi.fn>; fill: ReturnType<typeof vi.fn> };
}

function loadedImage(width: number, height: number) {
  return class {
    naturalWidth = width;
    naturalHeight = height;
    onload: (() => void) | null = null;
    onerror: (() => void) | null = null;
    set src(_value: string) { queueMicrotask(() => this.onload?.()); }
  };
}
