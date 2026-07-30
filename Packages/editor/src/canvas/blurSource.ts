export const BLUR_RADIUS_PX = 12 as const;

export function createBlurredSourceCanvas(
  source: CanvasImageSource,
  width: number,
  height: number,
  radius: typeof BLUR_RADIUS_PX,
): HTMLCanvasElement {
  const canvas = document.createElement("canvas");
  canvas.width = width;
  canvas.height = height;
  const context = canvas.getContext("2d");
  if (!context) throw new Error("Unable to create blur rendering context");
  context.filter = `blur(${radius}px)`;
  context.drawImage(source, 0, 0, width, height);
  context.filter = "none";
  return canvas;
}
