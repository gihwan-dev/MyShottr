import rough from "roughjs";
import type { ArrowElement, LineElement, RectangleElement } from "../model/elements";

export type RoughPath = {
  d: string;
  stroke: string;
  strokeWidth: number;
  fill?: string;
};

const generator = rough.generator();

export function roughPathsFor(
  element: RectangleElement | ArrowElement | LineElement,
): RoughPath[] {
  if (element.type === "rectangle") {
    return pathsForDrawable(generator.rectangle(0, 0, element.width, element.height, {
      stroke: element.strokeColor,
      strokeWidth: element.strokeWidth,
      fill: element.fillColor ?? undefined,
      roughness: element.roughness,
      seed: element.seed,
    }));
  }

  const startX = element.points[0].x - element.x;
  const startY = element.points[0].y - element.y;
  const endX = element.points[1].x - element.x;
  const endY = element.points[1].y - element.y;
  const line = (x1: number, y1: number, x2: number, y2: number, seed: number) =>
    pathsForDrawable(generator.line(x1, y1, x2, y2, {
      stroke: element.strokeColor,
      strokeWidth: element.strokeWidth,
      roughness: element.roughness,
      seed,
    }));
  const shaft = line(startX, startY, endX, endY, element.seed);
  if (element.type === "line") return shaft;

  const angle = Math.atan2(endY - startY, endX - startX);
  const headLength = Math.max(12, element.strokeWidth * 4);
  const left = {
    x: endX - headLength * Math.cos(angle - Math.PI / 6),
    y: endY - headLength * Math.sin(angle - Math.PI / 6),
  };
  const right = {
    x: endX - headLength * Math.cos(angle + Math.PI / 6),
    y: endY - headLength * Math.sin(angle + Math.PI / 6),
  };

  return [
    ...shaft,
    ...line(endX, endY, left.x, left.y, element.seed + 1),
    ...line(endX, endY, right.x, right.y, element.seed + 2),
  ];
}

function pathsForDrawable(drawable: ReturnType<typeof generator.line>): RoughPath[] {
  return generator.toPaths(drawable).map((path) => ({
    d: path.d,
    stroke: path.stroke,
    strokeWidth: path.strokeWidth,
    fill: path.fill,
  }));
}
