import type { EditorCommand, EditorDocument, EditorElement } from "./elements";
import { EditorDocumentSchema, EditorElementSchema } from "./schema";

export function findElement(document: EditorDocument, id: string): EditorElement {
  const element = document.elements.find((candidate) => candidate.id === id);
  if (!element) {
    throw new Error(`Element not found: ${id}`);
  }
  return element;
}

export function applyCommand(document: EditorDocument, command: EditorCommand): EditorDocument {
  EditorDocumentSchema.parse(document);
  const current = document;

  switch (command.type) {
    case "create": {
      const element = EditorElementSchema.parse(command.element) as EditorElement;
      return EditorDocumentSchema.parse({ ...current, elements: [...current.elements, element] }) as EditorDocument;
    }
    case "update": {
      const element = EditorElementSchema.parse(command.element) as EditorElement;
      const index = current.elements.findIndex((candidate) => candidate.id === element.id);
      if (index === -1) {
        throw new Error(`Cannot update missing element: ${element.id}`);
      }
      if (current.elements[index].type !== element.type) {
        throw new Error(`Cannot change element type for: ${element.id}`);
      }
      const elements = current.elements.map((candidate) => (
        candidate.id === element.id ? element : candidate
      ));
      return EditorDocumentSchema.parse({ ...current, elements }) as EditorDocument;
    }
    case "updateMany": {
      assertCommandIds(current, command.elements.map((element) => element.id), "updateMany");
      const updates = new Map(command.elements.map((candidate) => {
        const element = EditorElementSchema.parse(candidate) as EditorElement;
        const currentElement = findElement(current, element.id);
        if (currentElement.type !== element.type) {
          throw new Error(`Cannot change element type for: ${element.id}`);
        }
        return [element.id, { ...element, zIndex: currentElement.zIndex }];
      }));
      const elements = current.elements.map((candidate) => updates.get(candidate.id) ?? candidate);
      return EditorDocumentSchema.parse({ ...current, elements }) as EditorDocument;
    }
    case "delete": {
      assertCommandIds(current, command.ids, "delete");
      const deleted = new Set(command.ids);
      return EditorDocumentSchema.parse({
        ...current,
        elements: current.elements.filter((element) => !deleted.has(element.id)),
      }) as EditorDocument;
    }
    case "reorder":
      return reorder(current, command.ids, command.direction);
  }
}

function assertCommandIds(document: EditorDocument, ids: string[], operation: string): void {
  if (ids.length === 0) {
    throw new Error(`Cannot ${operation} without element ids`);
  }
  const uniqueIds = new Set(ids);
  if (uniqueIds.size !== ids.length) {
    throw new Error(`Cannot ${operation} duplicate element ids`);
  }
  ids.forEach((id) => findElement(document, id));
}

function reorder(
  document: EditorDocument,
  ids: string[],
  direction: "forward" | "backward",
): EditorDocument {
  assertCommandIds(document, ids, "reorder");
  const selected = new Set(ids);
  const ordered = [...document.elements].sort((left, right) => left.zIndex - right.zIndex);
  let moved = false;

  if (direction === "forward") {
    for (let index = ordered.length - 2; index >= 0; index -= 1) {
      if (selected.has(ordered[index].id) && !selected.has(ordered[index + 1].id)) {
        [ordered[index], ordered[index + 1]] = [ordered[index + 1], ordered[index]];
        moved = true;
      }
    }
  } else {
    for (let index = 1; index < ordered.length; index += 1) {
      if (selected.has(ordered[index].id) && !selected.has(ordered[index - 1].id)) {
        [ordered[index - 1], ordered[index]] = [ordered[index], ordered[index - 1]];
        moved = true;
      }
    }
  }

  if (!moved) {
    return document;
  }

  const zIndices = [...document.elements]
    .sort((left, right) => left.zIndex - right.zIndex)
    .map((element) => element.zIndex);
  const reorderedById = new Map(ordered.map((element, index) => [
    element.id,
    { ...element, zIndex: zIndices[index] },
  ]));
  const elements = document.elements.map((element) => {
    const reordered = reorderedById.get(element.id);
    if (!reordered) {
      throw new Error(`Reorder lost element: ${element.id}`);
    }
    return reordered;
  });

  return EditorDocumentSchema.parse({ ...document, elements }) as EditorDocument;
}
