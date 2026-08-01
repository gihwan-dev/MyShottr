import type { ArrowElement, Point } from "./elements";

export type ArrowSegment = readonly [Point, Point];

export function arrowSegments(
  element: Pick<ArrowElement, "points" | "strokeWidth">,
): readonly [ArrowSegment, ArrowSegment, ArrowSegment] {
  const start = element.points[0];
  const end = element.points[1];
  const angle = Math.atan2(end.y - start.y, end.x - start.x);
  const headLength = Math.max(12, element.strokeWidth * 4);
  const left = {
    x: end.x - headLength * Math.cos(angle - Math.PI / 6),
    y: end.y - headLength * Math.sin(angle - Math.PI / 6),
  };
  const right = {
    x: end.x - headLength * Math.cos(angle + Math.PI / 6),
    y: end.y - headLength * Math.sin(angle + Math.PI / 6),
  };

  return [
    [start, end],
    [end, left],
    [end, right],
  ];
}
