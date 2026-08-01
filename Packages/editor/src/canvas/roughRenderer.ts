import rough from "roughjs";
import type { ArrowElement, LineElement, RectangleElement } from "../model/elements";
import { arrowSegments } from "../model/arrowGeometry";

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

  const line = (x1: number, y1: number, x2: number, y2: number, seed: number) =>
    pathsForDrawable(generator.line(x1, y1, x2, y2, {
      stroke: element.strokeColor,
      strokeWidth: element.strokeWidth,
      roughness: element.roughness,
      seed,
    }));
  const segments = element.type === "arrow"
    ? arrowSegments(element)
    : [[element.points[0], element.points[1]]] as const;

  return segments.flatMap(([start, end], index) =>
    line(
      start.x - element.x,
      start.y - element.y,
      end.x - element.x,
      end.y - element.y,
      element.seed + index,
    )
  );
}

function pathsForDrawable(drawable: ReturnType<typeof generator.line>): RoughPath[] {
  return generator.toPaths(drawable).map((path) => ({
    d: path.d,
    stroke: path.stroke,
    strokeWidth: path.strokeWidth,
    fill: path.fill,
  }));
}
