import { useEffect, useMemo, useRef, useState, type ReactNode } from "react";
import type Konva from "konva";
import { Group, Image as KonvaImage, Layer, Rect, Stage, Transformer } from "react-konva";
import type { CreationGesture, EditorCommand, EditorDocument, EditorElement, EditorTool, Point } from "../model/elements";
import { CanvasViewport } from "./CanvasViewport";
import {
  CanvasPointerController,
  moveElementsWithinBounds,
  resizeElementWithinBounds,
} from "./SelectionController";
import { createElement } from "./tools/createElement";
import {
  renderElement,
  type ElementInteractionHandlers,
} from "./renderElement";
import { BLUR_RADIUS_PX, createBlurredSourceCanvas } from "./blurSource";

export function EditorCanvas({ document, sourceImageURL, tool, zoom, pan, selectedIds, onSelect, onEditText, onCommand, onBeginTransaction, onCommitTransaction, onCancelTransaction, onPanChange, textEditorOverlay }: {
  document: EditorDocument;
  sourceImageURL: string;
  tool: EditorTool;
  zoom: number;
  pan: Point;
  selectedIds: readonly string[];
  onSelect: (id: string | undefined, toggle?: boolean) => void;
  onEditText: (id: string) => void;
  onCommand: (command: EditorCommand) => void;
  onBeginTransaction: (label: string) => void;
  onCommitTransaction: () => void;
  onCancelTransaction: () => void;
  onPanChange: (pan: Point) => void;
  textEditorOverlay: ReactNode;
}) {
  const image = useSourceImage(sourceImageURL);
  const blurredSource = useMemo(
    () => image
      ? createBlurredSourceCanvas(
          image,
          document.sourcePixelWidth,
          document.sourcePixelHeight,
          BLUR_RADIUS_PX,
        )
      : undefined,
    [image, document.sourcePixelWidth, document.sourcePixelHeight],
  );
  const viewport = useMemo(() => new CanvasViewport({ sourceWidth: document.sourcePixelWidth, sourceHeight: document.sourcePixelHeight }), [document.sourcePixelWidth, document.sourcePixelHeight]);
  viewport.setTransform({ zoom, panX: pan.x, panY: pan.y });
  const nodes = useRef(new Map<string, Konva.Group>());
  const transformer = useRef<Konva.Transformer | null>(null);
  const gesture = useRef<ActiveCreationGesture | undefined>(undefined);
  const panGesture = useRef<{ start: Point; pan: Point } | undefined>(undefined);
  const pointerController = useRef(new CanvasPointerController());
  const selectionToggle = useRef(false);
  const suppressedAnnotationDrag = useRef(false);
  const suppressedTransform = useRef(false);
  const activeAnnotationInteraction = useRef<ActiveAnnotationInteraction | undefined>(undefined);
  const [isTransforming, setIsTransforming] = useState(false);
  const [creationPreview, setCreationPreview] = useState<EditorElement | undefined>(undefined);

  useEffect(() => {
    const selectedNodes = selectedIds.flatMap((id) => {
      const node = nodes.current.get(id);
      return node ? [node] : [];
    });
    transformer.current?.nodes(selectedNodes);
    transformer.current?.getLayer()?.draw();
  }, [selectedIds, document]);

  const sourcePoint = (stage: Konva.Stage): Point => {
    const pointer = stage.getPointerPosition();
    if (!pointer) {
      throw new Error("Canvas pointer position is unavailable");
    }
    return viewport.toSourcePoint(pointer);
  };
  const finishGesture = (stage: Konva.Stage) => {
    const activeGesture = gesture.current;
    if (!activeGesture) return;
    gesture.current = undefined;
    setCreationPreview(undefined);
    const end = sourcePoint(stage);
    const creationGesture = creationGestureFor(
      tool as Exclude<EditorTool, "selection">,
      activeGesture,
      end,
    );
    onCommand({ type: "create", element: createCanvasElement(document, tool as Exclude<EditorTool, "selection">, creationGesture) });
  };
  const cancelAnnotationTransaction = () => {
    const activeInteraction = activeAnnotationInteraction.current;
    if (!activeInteraction) return;
    activeAnnotationInteraction.current = undefined;
    try {
      cancelAnnotationInteraction(activeInteraction, transformer.current);
    } finally {
      try {
        onCancelTransaction();
      } finally {
        setIsTransforming(false);
      }
    }
  };
  useEffect(() => {
    const clearPointerInteraction = () => {
      gesture.current = undefined;
      setCreationPreview(undefined);
      panGesture.current = undefined;
      pointerController.current.end();
    };
    const cancelPointerInteraction = () => {
      try {
        cancelAnnotationTransaction();
      } finally {
        clearPointerInteraction();
      }
    };
    window.addEventListener("mouseup", clearPointerInteraction);
    window.addEventListener("pointercancel", cancelPointerInteraction);
    return () => {
      window.removeEventListener("mouseup", clearPointerInteraction);
      window.removeEventListener("pointercancel", cancelPointerInteraction);
    };
  });
  const orderedElements = [
    ...document.elements.filter((element) => element.type === "blur").sort(byZIndex),
    ...document.elements.filter((element) => element.type === "highlighter").sort(byZIndex),
    ...document.elements.filter((element) => element.type !== "blur" && element.type !== "highlighter").sort(byZIndex),
  ];
  const selectedElements = selectedIds.map((id) => {
    const element = document.elements.find((candidate) => candidate.id === id);
    if (!element) throw new Error(`Cannot select missing element: ${id}`);
    return element;
  });
  const selectedIdSet = new Set(selectedIds);

  return (
    <div className="canvas-shell" data-testid="editor-canvas" style={{ position: "relative" }}>
      <Stage
        width={Math.ceil(document.sourcePixelWidth * zoom)}
        height={Math.ceil(document.sourcePixelHeight * zoom)}
        onMouseDown={(event) => {
          const stage = event.target.getStage();
          if (!stage) throw new Error("Canvas stage is unavailable");
          selectionToggle.current = event.evt.shiftKey;
          if (pointerController.current.begin({ shiftKey: event.evt.shiftKey }) === "pan") {
            const start = stage.getPointerPosition();
            if (!start) throw new Error("Canvas pointer position is unavailable");
            panGesture.current = { start, pan };
            return;
          }
          if (tool === "selection" || isTransforming) {
            if (event.target === event.target.getStage()) onSelect(undefined);
            return;
          }
          const start = sourcePoint(stage);
          const preview = createCanvasElement(
            document,
            tool as Exclude<EditorTool, "selection">,
            creationGestureFor(
              tool as Exclude<EditorTool, "selection">,
              { start, points: [start] },
              start,
            ),
          );
          gesture.current = {
            start,
            points: [start],
            previewId: preview.id,
          };
        }}
        onMouseMove={(event) => {
          const stage = event.target.getStage();
          if (!stage) throw new Error("Canvas stage is unavailable");
          if (panGesture.current) {
            const pointer = stage.getPointerPosition();
            if (!pointer) throw new Error("Canvas pointer position is unavailable");
            onPanChange({
              x: panGesture.current.pan.x + pointer.x - panGesture.current.start.x,
              y: panGesture.current.pan.y + pointer.y - panGesture.current.start.y,
            });
            return;
          }
          const activeGesture = gesture.current;
          if (!activeGesture) return;
          const end = sourcePoint(stage);
          if (tool === "freehand" || tool === "highlighter") {
            activeGesture.points.push(end);
          }
          setCreationPreview({
            ...createCanvasElement(
              document,
              tool as Exclude<EditorTool, "selection">,
              creationGestureFor(
                tool as Exclude<EditorTool, "selection">,
                activeGesture,
                end,
              ),
            ),
            id: activeGesture.previewId,
          });
        }}
        onMouseUp={(event) => {
          const stage = event.target.getStage();
          if (!stage) throw new Error("Canvas stage is unavailable");
          if (panGesture.current) {
            panGesture.current = undefined;
            pointerController.current.end();
            return;
          }
          finishGesture(stage);
          if (tool !== "selection") pointerController.current.end();
        }}
      >
        <Layer id="sourceLayer" listening={false}>
          <Group x={pan.x} y={pan.y} scaleX={zoom} scaleY={zoom}>
            {image && <KonvaImage image={image} width={document.sourcePixelWidth} height={document.sourcePixelHeight} />}
          </Group>
        </Layer>
        <Layer id="annotationLayer">
          <Group x={pan.x} y={pan.y} scaleX={zoom} scaleY={zoom}>
            {orderedElements.map((element) => renderElement(element, {
              selected: selectedIdSet.has(element.id),
              draggable: tool === "selection" && selectedIdSet.has(element.id),
              textEditingEnabled: tool === "selection",
              onSelect: (id) => {
                onSelect(id, selectionToggle.current);
                selectionToggle.current = false;
              },
              onEditText: (id) => onEditText(id),
              onDragStart: (node) => {
                if (!pointerController.current.shouldDispatchAnnotationDrag()) {
                  suppressedAnnotationDrag.current = true;
                  node.stopDrag();
                  return;
                }
                const elementToMove = selectedElements.find(
                  (candidate) => candidate.id === element.id,
                );
                if (!elementToMove) {
                  throw new Error(`Cannot move missing element: ${element.id}`);
                }
                onBeginTransaction("move");
                activeAnnotationInteraction.current = {
                  kind: "move",
                  node,
                  element: elementToMove,
                  elements: selectedElements,
                  nodes: selectedNodeMap(selectedElements, nodes.current),
                };
              },
              onDragMove: (id, x, y) => {
                if (!pointerController.current.shouldDispatchAnnotationDrag()) return;
                try {
                  const active = activeAnnotationInteraction.current;
                  if (!active || active.kind !== "move") {
                    throw new Error("Cannot move without an active selection");
                  }
                  const elementToMove = active.elements.find((candidate) => candidate.id === id);
                  if (!elementToMove) throw new Error(`Cannot move missing element: ${id}`);
                  onCommand({
                    type: "updateMany",
                    elements: moveElementsWithinBounds(
                      active.elements,
                      { x: x - elementToMove.x, y: y - elementToMove.y },
                      {
                        sourceWidth: document.sourcePixelWidth,
                        sourceHeight: document.sourcePixelHeight,
                      },
                    ),
                  });
                } catch (error) {
                  cancelAnnotationTransaction();
                  pointerController.current.end();
                  throw error;
                }
              },
              onDragEnd: () => {
                if (suppressedAnnotationDrag.current) {
                  suppressedAnnotationDrag.current = false;
                  return;
                }
                if (activeAnnotationInteraction.current?.kind !== "move") return;
                try {
                  onCommitTransaction();
                  activeAnnotationInteraction.current = undefined;
                } catch (error) {
                  cancelAnnotationTransaction();
                  throw error;
                } finally {
                  pointerController.current.end();
                }
              },
              onTransformStart: (id, node) => {
                const activeInteraction = activeAnnotationInteraction.current;
                if (activeInteraction?.kind === "transform") return;
                if (activeInteraction) {
                  throw new Error("Cannot transform during an active move");
                }
                const elementToTransform = selectedElements.find((candidate) => candidate.id === id);
                if (!elementToTransform) throw new Error(`Cannot transform missing element: ${id}`);
                if (!beginTransformerInteraction(pointerController.current, transformer.current, node, elementToTransform)) {
                  suppressedTransform.current = true;
                  return;
                }
                onBeginTransaction("transform");
                activeAnnotationInteraction.current = {
                  kind: "transform",
                  node,
                  element: elementToTransform,
                  elements: selectedElements,
                  nodes: selectedNodeMap(selectedElements, nodes.current),
                };
                setIsTransforming(true);
              },
              onTransformEnd: (id, node) => {
                if (suppressedTransform.current) {
                  suppressedTransform.current = false;
                  return;
                }
                if (activeAnnotationInteraction.current?.kind !== "transform") return;
                try {
                  const active = activeAnnotationInteraction.current;
                  const transformedElements = active.elements.map((elementToTransform) => {
                    const selectedNode = active.nodes.get(elementToTransform.id);
                    if (!selectedNode) {
                      throw new Error(`Cannot transform unregistered element: ${elementToTransform.id}`);
                    }
                    const resized = resizeElementWithinBounds(
                      elementToTransform,
                      { x: selectedNode.x(), y: selectedNode.y() },
                      selectedNode.scaleX(),
                      selectedNode.scaleY(),
                      selectedNode.rotation(),
                      {
                        sourceWidth: document.sourcePixelWidth,
                        sourceHeight: document.sourcePixelHeight,
                      },
                    );
                    selectedNode.scaleX(1);
                    selectedNode.scaleY(1);
                    return resized;
                  });
                  onCommand({
                    type: "updateMany",
                    elements: transformedElements,
                  });
                  onCommitTransaction();
                  activeAnnotationInteraction.current = undefined;
                } catch (error) {
                  cancelAnnotationTransaction();
                  throw error;
                } finally {
                  setIsTransforming(false);
                  pointerController.current.end();
                }
              },
              registerNode: (id, node) => {
                if (node) nodes.current.set(id, node);
                else nodes.current.delete(id);
              },
            }, blurredSource))}
            {creationPreview && (
              <Group listening={false}>
                {renderElement(
                  creationPreview,
                  previewInteractionHandlers,
                  blurredSource,
                )}
              </Group>
            )}
            {selectedElements.map((selected) => (
              <Rect
                key={`selection-outline-${selected.id}`}
                x={selected.x}
                y={selected.y}
                width={selected.width}
                height={selected.height}
                stroke="#1677FF"
                dash={[4, 4]}
                listening={false}
              />
            ))}
            <Transformer
              ref={transformer}
              rotateEnabled={!selectedElements.some((element) => element.type === "blur")}
              flipEnabled={false}
            />
          </Group>
        </Layer>
      </Stage>
      {textEditorOverlay}
    </div>
  );
}

const previewInteractionHandlers = {
  selected: false,
  draggable: false,
  textEditingEnabled: false,
  onSelect: () => {},
  onEditText: () => {},
  onDragStart: () => {},
  onDragMove: () => {},
  onDragEnd: () => {},
  onTransformStart: () => {},
  onTransformEnd: () => {},
  registerNode: () => {},
} satisfies ElementInteractionHandlers;

type ActiveCreationGesture = {
  start: Point;
  points: Point[];
  previewId: string;
};

function creationGestureFor(
  tool: Exclude<EditorTool, "selection">,
  gesture: Pick<ActiveCreationGesture, "start" | "points">,
  end: Point,
): CreationGesture {
  if (tool === "freehand" || tool === "highlighter") {
    return {
      kind: "path",
      points: gesture.points.at(-1) === end
        ? gesture.points
        : [...gesture.points, end],
    };
  }
  if (tool === "text" || tool === "numberMarker") {
    return { kind: "point", point: gesture.start };
  }
  return { kind: "box", start: gesture.start, end };
}

function byZIndex(left: EditorElement, right: EditorElement): number {
  return left.zIndex - right.zIndex;
}

type TransformerControl = {
  stopTransform(): void;
  forceUpdate(): void;
};

type TransformableNode = {
  x(value: number): unknown;
  y(value: number): unknown;
  scaleX(value: number): unknown;
  scaleY(value: number): unknown;
  rotation(value: number): unknown;
};

type ActiveAnnotationInteraction = {
  kind: "move" | "transform";
  node: Konva.Group;
  element: EditorElement;
  elements: EditorElement[];
  nodes: Map<string, Konva.Group>;
};

export function cancelAnnotationInteraction(
  interaction: ActiveAnnotationInteraction,
  transformer: TransformerControl | null,
): void {
  if (interaction.kind === "move") {
    interaction.node.stopDrag();
  } else {
    if (!transformer) throw new Error("Transformer is unavailable for cancellation");
    transformer.stopTransform();
  }
  interaction.elements.forEach((element) => {
    const node = interaction.nodes.get(element.id);
    if (!node) {
      throw new Error(`Cannot restore unregistered element: ${element.id}`);
    }
    node.x(element.x);
    node.y(element.y);
    node.scaleX(1);
    node.scaleY(1);
    node.rotation(element.rotation);
    node.getLayer()?.draw();
  });
  transformer?.forceUpdate();
}

function selectedNodeMap(
  elements: EditorElement[],
  registeredNodes: Map<string, Konva.Group>,
): Map<string, Konva.Group> {
  return new Map(elements.map((element) => {
    const node = registeredNodes.get(element.id);
    if (!node) {
      throw new Error(`Cannot interact with unregistered element: ${element.id}`);
    }
    return [element.id, node];
  }));
}

export function beginTransformerInteraction(
  pointerController: CanvasPointerController,
  transformer: TransformerControl | null,
  node: TransformableNode,
  element: EditorElement,
): boolean {
  if (pointerController.shouldDispatchAnnotationDrag()) return true;
  if (!transformer) throw new Error("Transformer is unavailable for pan cancellation");

  transformer.stopTransform();
  node.x(element.x);
  node.y(element.y);
  node.scaleX(1);
  node.scaleY(1);
  node.rotation(element.rotation);
  transformer.forceUpdate();
  return false;
}

export function createCanvasElement(
  document: EditorDocument,
  tool: Exclude<EditorTool, "selection">,
  gesture: CreationGesture,
): EditorElement {
  return createElement(tool, gesture, {
    defaults: document.defaults,
    nextNumberMarker: Math.max(0, ...document.elements.filter((candidate) => candidate.type === "numberMarker").map((candidate) => candidate.number)) + 1,
    nextZIndex: Math.max(-1, ...document.elements.map((candidate) => candidate.zIndex)) + 1,
    seed: Math.max(0, ...document.elements.map((candidate) => candidate.seed)) + 1,
  });
}

function useSourceImage(sourceImageURL: string): HTMLImageElement | undefined {
  const [image, setImage] = useState<HTMLImageElement>();

  useEffect(() => {
    const nextImage = new window.Image();
    nextImage.onload = () => setImage(nextImage);
    nextImage.onerror = () => {
      throw new Error("Unable to load the editor source image");
    };
    nextImage.src = sourceImageURL;
    return () => {
      nextImage.onload = null;
      nextImage.onerror = null;
    };
  }, [sourceImageURL]);

  return image;
}
