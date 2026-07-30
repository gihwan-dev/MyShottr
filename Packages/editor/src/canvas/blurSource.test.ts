import { describe, expect, it, vi } from "vitest";
import { BLUR_RADIUS_PX, createBlurredSourceCanvas } from "./blurSource";

describe("createBlurredSourceCanvas", () => {
  it("builds one source-resolution Gaussian-blurred canvas", () => {
    const canvas = document.createElement("canvas");
    const context = { filter: "none", drawImage: vi.fn() } as unknown as CanvasRenderingContext2D;
    vi.spyOn(document, "createElement").mockReturnValue(canvas);
    vi.spyOn(canvas, "getContext").mockReturnValue(context);
    const sourceImage = document.createElement("img");

    const result = createBlurredSourceCanvas(sourceImage, 1440, 900, BLUR_RADIUS_PX);

    expect(result).toMatchObject({ width: 1440, height: 900 });
    expect(context.filter).toBe("none");
    expect(context.drawImage).toHaveBeenCalledWith(sourceImage, 0, 0, 1440, 900);
  });
});
