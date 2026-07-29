import type { EditorDocument, EditorElement, Point } from "../model/elements";

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
  const elements = [
    ...document.elements.filter((element) => element.type === "highlighter").sort(byZIndex),
    ...document.elements.filter((element) => element.type !== "highlighter").sort(byZIndex),
  ];
  for (const element of elements) drawElement(context, element);

  return new Promise((resolve, reject) => {
    canvas.toBlob((blob) => {
      if (blob) resolve(blob);
      else reject(new Error("Unable to encode composite PNG"));
    }, "image/png");
  });
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
      context.lineWidth = element.strokeWidth;
      context.strokeStyle = element.strokeColor;
      if (element.fillColor) {
        context.fillStyle = element.fillColor;
        context.fillRect(0, 0, element.width, element.height);
      }
      context.strokeRect(0, 0, element.width, element.height);
      break;
    case "arrow":
      drawPath(context, element.points, element.x, element.y, element.strokeColor, element.strokeWidth);
      break;
    case "text":
      context.fillStyle = element.color;
      context.font = `${element.fontSize}px sans-serif`;
      context.textBaseline = "top";
      context.fillText(element.text, 0, 0, element.width);
      break;
    case "freehand":
    case "highlighter":
      drawPath(context, element.points, element.x, element.y, element.color, element.strokeWidth);
      break;
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
      context.font = `${Math.floor(radius)}px sans-serif`;
      context.textAlign = "center";
      context.textBaseline = "middle";
      context.fillText(String(element.number), element.width / 2, element.height / 2);
      break;
    }
  }
  context.restore();
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
