import { useEffect, useMemo, useRef, useState, type ReactNode } from "react";
import type Konva from "konva";
import { Group, Image as KonvaImage, Layer, Rect, Stage, Transformer } from "react-konva";
import type { EditorCommand, EditorDefaults, EditorDocument, EditorElement, EditorTool, Point } from "../model/elements";
import {
  InteractionController,
  type InteractionCommit,
  type InteractionModifiers,
  type InteractionPreview,
} from "../interaction/InteractionController";
import type { ViewportSnapshot } from "../viewport/ViewportController";
import {
  moveElementsWithinBounds,
  resizeElementWithinBounds,
} from "./SelectionController";
import { createElementFromDocument } from "./tools/createElement";
import {
  renderElement,
  type ElementInteractionHandlers,
} from "./renderElement";
import { BLUR_RADIUS_PX, createBlurredSourceCanvas } from "./blurSource";
import { cursorForTool } from "./tools/ToolController";

export function EditorCanvas({ document, sourceImageURL, tool, viewport, spacePanReady, selectedIds, onSelect, onEditText, onBeginNewText, onCommand, onBeginTransaction, onCommitTransaction, onCancelTransaction, onViewportWheel, onViewportPanBy, onInteractionActiveChange, toSourcePoint, textEditorOverlay }: {
  document: EditorDocument;
  sourceImageURL: string;
  tool: EditorTool;
  viewport: ViewportSnapshot;
  spacePanReady: boolean;
  selectedIds: readonly string[];
  onSelect: (id: string | undefined, toggle?: boolean) => void;
  onEditText: (id: string) => void;
  onBeginNewText: (point: Point, defaults: EditorDefaults) => void;
  onCommand: (command: EditorCommand) => void;
  onBeginTransaction: (label: string) => void;
  onCommitTransaction: () => void;
  onCancelTransaction: () => void;
  onViewportWheel: (input: {
    pointer: Point;
    deltaX: number;
    deltaY: number;
    metaKey: boolean;
    ctrlKey: boolean;
  }) => void;
  onViewportPanBy: (delta: Point) => void;
  onInteractionActiveChange: (active: boolean) => void;
  toSourcePoint: (workspacePoint: Point) => Point;
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
  const nodes = useRef(new Map<string, Konva.Group>());
  const transformer = useRef<Konva.Transformer | null>(null);
  const interactionControllerRef = useRef<InteractionController | undefined>(undefined);
  if (!interactionControllerRef.current) {
    interactionControllerRef.current = new InteractionController();
  }
  const interactionController = interactionControllerRef.current;
  const captureContainer = useRef<HTMLDivElement | undefined>(undefined);
  const capturedPointerId = useRef<number | undefined>(undefined);
  const spacePanActive = useRef(false);
  const appliedViewportPan = useRef<Point>({ x: 0, y: 0 });
  const latestMove = useRef<{
    point: Point;
    modifiers: InteractionModifiers;
  } | undefined>(undefined);
  const frame = useRef<number | null>(null);
  const selectionToggle = useRef(false);
  const activeAnnotationInteraction = useRef<ActiveAnnotationInteraction | undefined>(undefined);
  const [isTransforming, setIsTransforming] = useState(false);
  const [isSpacePanning, setIsSpacePanning] = useState(false);
  const [creationPreview, setCreationPreview] = useState<EditorElement | undefined>(undefined);

  useEffect(() => {
    const selectedNodes = selectedIds.flatMap((id) => {
      const node = nodes.current.get(id);
      return node ? [node] : [];
    });
    transformer.current?.nodes(selectedNodes);
    transformer.current?.getLayer()?.draw();
  }, [selectedIds, document]);

  const workspacePoint = (stage: Konva.Stage): Point => {
    const pointer = stage.getPointerPosition();
    if (!pointer) {
      throw new Error("Canvas pointer position is unavailable");
    }
    return pointer;
  };
  const interactionPoint = (stage: Konva.Stage): Point => {
    const point = workspacePoint(stage);
    return spacePanActive.current ? point : toSourcePoint(point);
  };
  const applyPreview = (preview: InteractionPreview) => {
    if (preview.type === "creation") {
      setCreationPreview(preview.element);
      return;
    }
    if (preview.type === "viewport") {
      const delta = {
        x: preview.pan.x - appliedViewportPan.current.x,
        y: preview.pan.y - appliedViewportPan.current.y,
      };
      appliedViewportPan.current = preview.pan;
      if (delta.x !== 0 || delta.y !== 0) onViewportPanBy(delta);
    }
  };
  const clearScheduledMove = () => {
    if (frame.current !== null) {
      cancelAnimationFrame(frame.current);
      frame.current = null;
    }
    latestMove.current = undefined;
  };
  const flushScheduledMove = () => {
    if (frame.current !== null) {
      cancelAnimationFrame(frame.current);
      frame.current = null;
    }
    const latest = latestMove.current;
    latestMove.current = undefined;
    if (latest) {
      applyPreview(interactionController.update(latest.point, latest.modifiers));
    }
  };
  const releasePointerCapture = () => {
    const pointerId = capturedPointerId.current;
    if (pointerId === undefined) return;
    const container = captureContainer.current;
    capturedPointerId.current = undefined;
    captureContainer.current = undefined;
    if (container?.hasPointerCapture(pointerId)) {
      container.releasePointerCapture(pointerId);
    }
  };
  const finishPointerInteraction = () => {
    clearScheduledMove();
    setCreationPreview(undefined);
    releasePointerCapture();
    appliedViewportPan.current = { x: 0, y: 0 };
    spacePanActive.current = false;
    setIsSpacePanning(false);
    onInteractionActiveChange(false);
  };
  const routeCommit = (result: InteractionCommit) => {
    switch (result.type) {
      case "none":
        return;
      case "command":
        onCommand(result.command);
        return;
      case "selection":
        if (result.selectedIds.length === 0) onSelect(undefined);
        else result.selectedIds.forEach((id, index) => onSelect(id, index > 0));
        return;
      case "beginNewText":
        onBeginNewText(result.point, result.defaults);
        return;
      case "viewport":
        applyPreview(result);
    }
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
  const cancelPointerInteraction = () => {
    try {
      cancelAnnotationTransaction();
    } finally {
      const wasActive = interactionController.active;
      interactionController.cancel();
      clearScheduledMove();
      setCreationPreview(undefined);
      releasePointerCapture();
      appliedViewportPan.current = { x: 0, y: 0 };
      spacePanActive.current = false;
      setIsSpacePanning(false);
      if (wasActive) onInteractionActiveChange(false);
    }
  };
  useEffect(() => {
    window.addEventListener("blur", cancelPointerInteraction);
    return () => {
      window.removeEventListener("blur", cancelPointerInteraction);
    };
  });
  const orderedElements = [...document.elements].sort(byZIndex);
  const selectedElements = selectedIds.map((id) => {
    const element = document.elements.find((candidate) => candidate.id === id);
    if (!element) throw new Error(`Cannot select missing element: ${id}`);
    return element;
  });
  const selectedIdSet = new Set(selectedIds);

  return (
    <div
      className="canvas-shell"
      data-testid="editor-canvas"
      style={{
        position: "relative",
        cursor: cursorForTool(
          tool,
          isSpacePanning ? "active" : spacePanReady ? "ready" : "inactive",
        ),
      }}
    >
      <Stage
        width={viewport.workspace.width}
        height={viewport.workspace.height}
        onWheel={(event) => {
          const stage = event.target.getStage();
          if (!stage) throw new Error("Canvas stage is unavailable");
          const pointer = stage.getPointerPosition();
          if (!pointer) throw new Error("Canvas pointer position is unavailable");
          event.evt.preventDefault();
          onViewportWheel({
            pointer,
            deltaX: event.evt.deltaX,
            deltaY: event.evt.deltaY,
            metaKey: event.evt.metaKey,
            ctrlKey: event.evt.ctrlKey,
          });
        }}
        onPointerDown={(event) => {
          const stage = event.target.getStage();
          if (!stage) throw new Error("Canvas stage is unavailable");
          selectionToggle.current = event.evt.shiftKey;
          if (!spacePanReady && (tool === "selection" || isTransforming)) {
            if (event.target === event.target.getStage()) onSelect(undefined);
            return;
          }
          if (interactionController.active) return;
          spacePanActive.current = spacePanReady;
          appliedViewportPan.current = { x: 0, y: 0 };
          const start = interactionPoint(stage);
          const preview = interactionController.begin({
            pointerId: event.evt.pointerId,
            tool,
            point: start,
            modifiers: modifiersFor(event.evt),
            defaults: document.defaults,
            document,
            selectedIds,
            spaceHeld: spacePanReady,
          });
          const container = stage.container();
          container.setPointerCapture(event.evt.pointerId);
          captureContainer.current = container;
          capturedPointerId.current = event.evt.pointerId;
          if (preview) applyPreview(preview);
          setIsSpacePanning(spacePanReady);
          onInteractionActiveChange(true);
        }}
        onPointerMove={(event) => {
          if (
            !interactionController.active
            || event.evt.pointerId !== capturedPointerId.current
          ) return;
          const stage = event.target.getStage();
          if (!stage) throw new Error("Canvas stage is unavailable");
          latestMove.current = {
            point: interactionPoint(stage),
            modifiers: modifiersFor(event.evt),
          };
          if (frame.current === null) {
            frame.current = requestAnimationFrame(() => {
              frame.current = null;
              const latest = latestMove.current;
              latestMove.current = undefined;
              if (latest) {
                applyPreview(interactionController.update(latest.point, latest.modifiers));
              }
            });
          }
        }}
        onPointerUp={(event) => {
          if (
            !interactionController.active
            || event.evt.pointerId !== capturedPointerId.current
          ) return;
          const stage = event.target.getStage();
          if (!stage) throw new Error("Canvas stage is unavailable");
          try {
            flushScheduledMove();
            const point = interactionPoint(stage);
            const modifiers = modifiersFor(event.evt);
            applyPreview(interactionController.update(point, modifiers));
            routeCommit(interactionController.commit(point, modifiers));
          } finally {
            finishPointerInteraction();
          }
        }}
        onPointerCancel={(event) => {
          if (
            capturedPointerId.current !== undefined
            && event.evt.pointerId !== capturedPointerId.current
          ) return;
          cancelPointerInteraction();
        }}
      >
        <Layer id="workspaceLayer">
          <Group x={viewport.pan.x} y={viewport.pan.y} scaleX={viewport.zoom} scaleY={viewport.zoom}>
            {image && (
              <KonvaImage
                image={image}
                width={document.sourcePixelWidth}
                height={document.sourcePixelHeight}
                listening={false}
              />
            )}
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
                  throw error;
                }
              },
              onDragEnd: () => {
                if (activeAnnotationInteraction.current?.kind !== "move") return;
                try {
                  onCommitTransaction();
                  activeAnnotationInteraction.current = undefined;
                } catch (error) {
                  cancelAnnotationTransaction();
                  throw error;
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
                }
              },
              registerNode: (id, node) => {
                if (node) nodes.current.set(id, node);
                else nodes.current.delete(id);
              },
            }, blurredSource))}
            {creationPreview && (
              <Group listening={false} data-testid="creation-preview">
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

function byZIndex(left: EditorElement, right: EditorElement): number {
  return left.zIndex - right.zIndex;
}

type TransformerControl = {
  stopTransform(): void;
  forceUpdate(): void;
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

export function createCanvasElement(
  document: EditorDocument,
  tool: Exclude<EditorTool, "selection">,
  gesture: Parameters<typeof createElementFromDocument>[2],
): EditorElement {
  return createElementFromDocument(document, tool, gesture);
}

function modifiersFor(event: Pick<PointerEvent, "shiftKey" | "altKey">): InteractionModifiers {
  return { shift: event.shiftKey, option: event.altKey };
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
