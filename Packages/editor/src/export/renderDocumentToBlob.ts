import type { EditorDocument, EditorElement, Point } from "../model/elements";
import { roughPathsFor } from "../canvas/roughRenderer";
import { KONVA_DEFAULT_FONT_FAMILY, NUMBER_MARKER_FONT_SIZE, TEXT_LINE_HEIGHT } from "../canvas/renderingConstants";
import { BLUR_RADIUS_PX, createBlurredSourceCanvas } from "../canvas/blurSource";

export async function renderDocumentToBlob(document: EditorDocument, sourceImageURL: string): Promise<Blob> {
  const sourceImage = await loadSourceImage(sourceImageURL);
  if (sourceImage.naturalWidth !== document.sourcePixelWidth || sourceImage.naturalHeight !== document.sourcePixelHeight) {
    throw new Error("Source image dimensions do not match the document");
  }

  const canvas = window.document.createElement("canvas");
  canvas.width = document.sourcePixelWidth;
  canvas.height = document.sourcePixelHeight;
  const context = canvas.getContext("2d");
  if (!context) throw new Error("Unable to create PNG rendering context");

  context.drawImage(sourceImage, 0, 0, canvas.width, canvas.height);
  const blurElements = document.elements.filter((element) => element.type === "blur").sort(byZIndex);
  const blurredSource = blurElements.length > 0
    ? createBlurredSourceCanvas(sourceImage, document.sourcePixelWidth, document.sourcePixelHeight, BLUR_RADIUS_PX)
    : undefined;
  for (const element of blurElements) {
    if (!blurredSource) throw new Error("Blur source is unavailable");
    drawBlurElement(context, element, blurredSource, document);
  }
  const elements = [
    ...document.elements.filter((element) => element.type === "highlighter").sort(byZIndex),
    ...document.elements.filter((element) => element.type !== "blur" && element.type !== "highlighter").sort(byZIndex),
  ];
  for (const element of elements) drawElement(context, element);

  return new Promise((resolve, reject) => {
    canvas.toBlob((blob) => {
      if (blob) resolve(blob);
      else reject(new Error("Unable to encode composite PNG"));
    }, "image/png");
  });
}

function drawBlurElement(
  context: CanvasRenderingContext2D,
  element: Extract<EditorElement, { type: "blur" }>,
  blurredSource: HTMLCanvasElement,
  document: EditorDocument,
): void {
  context.save();
  context.translate(element.x, element.y);
  context.rotate((element.rotation * Math.PI) / 180);
  context.beginPath();
  context.rect(0, 0, element.width, element.height);
  context.clip();
  context.drawImage(blurredSource, -element.x, -element.y, document.sourcePixelWidth, document.sourcePixelHeight);
  context.restore();
}

function loadSourceImage(sourceImageURL: string): Promise<HTMLImageElement> {
  return new Promise((resolve, reject) => {
    const image = new Image();
    image.onload = () => resolve(image);
    image.onerror = () => reject(new Error("Source image could not be loaded"));
    image.src = sourceImageURL;
  });
}

function drawElement(context: CanvasRenderingContext2D, element: EditorElement): void {
  context.save();
  context.translate(element.x, element.y);
  context.rotate((element.rotation * Math.PI) / 180);
  context.globalAlpha = element.opacity;

  switch (element.type) {
    case "rectangle":
    case "arrow":
    case "line":
      drawRoughElement(context, element);
      break;
    case "text":
      context.fillStyle = element.color;
      context.font = `${element.fontSize}px ${KONVA_DEFAULT_FONT_FAMILY}`;
      context.textBaseline = "top";
      element.text.split("\n").forEach((line, index) => {
        context.fillText(line, 0, index * element.fontSize * TEXT_LINE_HEIGHT, element.width);
      });
      break;
    case "freehand":
    case "highlighter":
      drawPath(context, element.points, element.x, element.y, element.color, element.strokeWidth);
      break;
    case "blur":
      throw new Error("Blur elements must render before vector annotations");
    case "redaction":
      context.fillStyle = element.color;
      context.fillRect(0, 0, element.width, element.height);
      break;
    case "numberMarker": {
      const radius = Math.min(element.width, element.height) / 2;
      context.fillStyle = element.color;
      context.beginPath();
      context.arc(element.width / 2, element.height / 2, radius, 0, 2 * Math.PI);
      context.fill();
      context.fillStyle = "#FFFFFF";
      context.font = `${NUMBER_MARKER_FONT_SIZE}px ${KONVA_DEFAULT_FONT_FAMILY}`;
      context.textAlign = "center";
      context.textBaseline = "middle";
      context.fillText(String(element.number), element.width / 2, element.height / 2);
      break;
    }
  }
  context.restore();
}

function drawRoughElement(
  context: CanvasRenderingContext2D,
  element: Extract<EditorElement, { type: "rectangle" | "arrow" | "line" }>,
): void {
  for (const roughPath of roughPathsFor(element)) {
    const path = new Path2D(roughPath.d);
    if (roughPath.fill && roughPath.fill !== "none") {
      context.fillStyle = roughPath.fill;
      context.fill(path);
    }
    context.strokeStyle = roughPath.stroke;
    context.lineWidth = roughPath.strokeWidth;
    context.stroke(path);
  }
}

function drawPath(context: CanvasRenderingContext2D, points: Point[], originX: number, originY: number, color: string, strokeWidth: number): void {
  const first = points[0];
  if (!first) return;
  context.beginPath();
  context.moveTo(first.x - originX, first.y - originY);
  for (const point of points.slice(1)) context.lineTo(point.x - originX, point.y - originY);
  context.strokeStyle = color;
  context.lineWidth = strokeWidth;
  context.lineCap = "round";
  context.lineJoin = "round";
  context.stroke();
}

function byZIndex(left: EditorElement, right: EditorElement): number {
  return left.zIndex - right.zIndex;
}
