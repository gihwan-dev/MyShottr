import rough from "roughjs";
import type { ArrowElement, RectangleElement } from "../model/elements";

export type RoughPath = {
  d: string;
  stroke: string;
  strokeWidth: number;
  fill?: string;
};

const generator = rough.generator();

export function roughPathsFor(element: RectangleElement | ArrowElement): RoughPath[] {
  const drawable = element.type === "rectangle"
    ? generator.rectangle(0, 0, element.width, element.height, {
      stroke: element.strokeColor,
      strokeWidth: element.strokeWidth,
      fill: element.fillColor ?? undefined,
      roughness: element.roughness,
      seed: element.seed,
    })
    : generator.linearPath(element.points.map((point) => [point.x - element.x, point.y - element.y]), {
      stroke: element.strokeColor,
      strokeWidth: element.strokeWidth,
      roughness: element.roughness,
      seed: element.seed,
    });

  return generator.toPaths(drawable).map((path) => ({
    d: path.d,
    stroke: path.stroke,
    strokeWidth: path.strokeWidth,
    fill: path.fill,
  }));
}
