import type {
  EditorDocument,
  EditorElement,
  Point,
} from "../model/elements";
import { moveElementsWithinBounds } from "./selectionGeometry";
import { createElementId } from "../canvas/tools/createElement";

export function createDuplicateElements(
  document: Pick<
    EditorDocument,
    "elements" | "sourcePixelWidth" | "sourcePixelHeight"
  >,
  sources: readonly EditorElement[],
  delta: Point = { x: 12, y: 12 },
): EditorElement[] {
  if (sources.length === 0) return [];
  const nextSeed = Math.max(
    0,
    ...document.elements.map((element) => element.seed),
  ) + 1;
  const nextZIndex = Math.max(
    -1,
    ...document.elements.map((element) => element.zIndex),
  ) + 1;
  const existingIds = new Set(document.elements.map((element) => element.id));
  const duplicateIds = sources.map(() => createElementId());
  if (
    new Set(duplicateIds).size !== duplicateIds.length
    || duplicateIds.some((id) => existingIds.has(id))
  ) {
    throw new Error("Duplicate element ids must be unique");
  }
  const zIndexOffsets = new Array<number>(sources.length);
  sources
    .map((source, sourceIndex) => ({ source, sourceIndex }))
    .sort((left, right) =>
      left.source.zIndex - right.source.zIndex
      || left.sourceIndex - right.sourceIndex
    )
    .forEach(({ sourceIndex }, stackIndex) => {
      zIndexOffsets[sourceIndex] = stackIndex;
    });
  const offsets = moveElementsWithinBounds(
    sources,
    delta,
    {
      sourceWidth: document.sourcePixelWidth,
      sourceHeight: document.sourcePixelHeight,
    },
  );
  return offsets.map((offset, index) => {
    const zIndexOffset = zIndexOffsets[index];
    if (zIndexOffset === undefined) {
      throw new Error(`Duplicate stack order is unavailable at index ${index}`);
    }
    return {
      ...offset,
      id: duplicateIds[index],
      seed: nextSeed + index,
      zIndex: nextZIndex + zIndexOffset,
    };
  });
}
