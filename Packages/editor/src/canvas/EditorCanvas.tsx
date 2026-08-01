import { forwardRef, useEffect, useImperativeHandle, useMemo, useRef, useState, type ReactNode } from "react";
import type Konva from "konva";
import { Group, Image as KonvaImage, Layer, Rect, Stage, Transformer } from "react-konva";
import type { EditorCommand, EditorDefaults, EditorDocument, EditorElement, EditorTool, Point } from "../model/elements";
import {
  InteractionController,
  type InteractionCommit,
  type InteractionModifiers,
  type InteractionPreview,
} from "../interaction/InteractionController";
import type { Rect as SourceRect, ViewportSnapshot } from "../viewport/ViewportController";
import { resizeElementWithinBounds } from "./SelectionController";
import { createDuplicateElements } from "../interaction/duplication";
import { moveElementsWithinBounds, rotatedElementBounds } from "../interaction/selectionGeometry";
import { createElementFromDocument } from "./tools/createElement";
import {
  pointerOwnerFor,
  renderElement,
  type ElementInteractionHandlers,
  type ElementPointerOwner,
} from "./renderElement";
import { BLUR_RADIUS_PX, createBlurredSourceCanvas } from "./blurSource";
import { cursorForTool } from "./tools/ToolController";

export type EditorCanvasHandle = {
  cancelInteraction(): boolean;
};

export type EditorCanvasProps = {
  document: EditorDocument;
  sourceImageURL: string;
  tool: EditorTool;
  viewport: ViewportSnapshot;
  spacePanReady: boolean;
  interactionLocked: boolean;
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
};

export const EditorCanvas = forwardRef<EditorCanvasHandle, EditorCanvasProps>(function EditorCanvas({ document, sourceImageURL, tool, viewport, spacePanReady, interactionLocked, selectedIds, onSelect, onEditText, onBeginNewText, onCommand, onBeginTransaction, onCommitTransaction, onCancelTransaction, onViewportWheel, onViewportPanBy, onInteractionActiveChange, toSourcePoint, textEditorOverlay }, ref) {
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
  const disposed = useRef(false);
  const pendingAnnotationPointer = useRef<AnnotationPointerSnapshot | undefined>(undefined);
  const activeAnnotationInteraction = useRef<ActiveAnnotationInteraction | undefined>(undefined);
  const [isTransforming, setIsTransforming] = useState(false);
  const [isSpacePanning, setIsSpacePanning] = useState(false);
  const [creationPreview, setCreationPreview] = useState<EditorElement | undefined>(undefined);
  const [marqueePreview, setMarqueePreview] = useState<SourceRect | undefined>(undefined);
  const [duplicationPreview, setDuplicationPreview] = useState<readonly EditorElement[]>([]);

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
  const consumeMovePointer = (
    elementId: string,
    node: Konva.Group,
  ): MovePointerSnapshot => {
    const snapshot = pendingAnnotationPointer.current;
    pendingAnnotationPointer.current = undefined;
    if (
      snapshot?.kind !== "move"
      || snapshot.elementId !== elementId
      || snapshot.node !== node
    ) {
      throw new Error(`Annotation move requires pointerdown on ${elementId}`);
    }
    return snapshot;
  };
  const consumeTransformPointer = (node: Konva.Group): TransformPointerSnapshot => {
    const snapshot = pendingAnnotationPointer.current;
    pendingAnnotationPointer.current = undefined;
    if (snapshot?.kind !== "transform" || !snapshot.nodes.has(node)) {
      throw new Error("Annotation transform requires pointerdown on its Transformer");
    }
    return snapshot;
  };
  const applyPreview = (preview: InteractionPreview) => {
    if (preview.type === "creation") {
      setCreationPreview(preview.element);
      setMarqueePreview(undefined);
      return;
    }
    if (preview.type === "marquee") {
      setCreationPreview(undefined);
      setMarqueePreview(preview.rect);
      return;
    }
    if (preview.type === "viewport") {
      const delta = {
        x: preview.pan.x - appliedViewportPan.current.x,
        y: preview.pan.y - appliedViewportPan.current.y,
      };
      appliedViewportPan.current = preview.pan;
      if (delta.x !== 0 || delta.y !== 0) onViewportPanBy(delta);
      return;
    }
    setCreationPreview(undefined);
    setMarqueePreview(undefined);
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
    setMarqueePreview(undefined);
    setDuplicationPreview([]);
    releasePointerCapture();
    appliedViewportPan.current = { x: 0, y: 0 };
    spacePanActive.current = false;
    setIsSpacePanning(false);
    onInteractionActiveChange(false);
  };
  const routeSelection = (nextSelectedIds: readonly string[]) => {
    if (nextSelectedIds.length === 0) {
      onSelect(undefined);
      return;
    }
    nextSelectedIds.forEach((id, index) => onSelect(id, index > 0));
  };
  const routeCommit = (result: InteractionCommit) => {
    switch (result.type) {
      case "none":
        return;
      case "command":
        onCommand(result.command);
        if (result.selectedIds) routeSelection(result.selectedIds);
        return;
      case "selection":
        routeSelection(result.selectedIds);
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
      cancelAnnotationInteraction(activeInteraction, activeInteraction.cancelTransformer);
    } finally {
      try {
        releaseAnnotationPointerCapture(activeInteraction);
      } finally {
        try {
          onCancelTransaction();
        } finally {
          if (!disposed.current) setIsTransforming(false);
        }
      }
    }
  };
  const cancelPointerInteraction = () => {
    const pointerWasActive = interactionController.active;
    const wasActive = pointerWasActive
      || activeAnnotationInteraction.current !== undefined;
    pendingAnnotationPointer.current = undefined;
    if (!wasActive) return false;
    try {
      cancelAnnotationTransaction();
    } finally {
      interactionController.cancel();
      clearScheduledMove();
      setCreationPreview(undefined);
      setMarqueePreview(undefined);
      setDuplicationPreview([]);
      releasePointerCapture();
      appliedViewportPan.current = { x: 0, y: 0 };
      spacePanActive.current = false;
      setIsSpacePanning(false);
      if (pointerWasActive) onInteractionActiveChange(false);
    }
    return true;
  };
  useImperativeHandle(ref, () => ({
    cancelInteraction: cancelPointerInteraction,
  }));
  useEffect(() => {
    window.addEventListener("blur", cancelPointerInteraction);
    return () => {
      window.removeEventListener("blur", cancelPointerInteraction);
    };
  });
  useEffect(() => {
    const activeInteraction = activeAnnotationInteraction.current;
    if (
      activeInteraction
      && (
        interactionLocked
        || activeInteraction.tool !== tool
        || activeInteraction.documentIdentity !== document
        || !sameOrderedIds(activeInteraction.selectedIds, selectedIds)
      )
    ) {
      cancelPointerInteraction();
      return;
    }
    const pendingPointer = pendingAnnotationPointer.current;
    if (
      pendingPointer
      && (
        interactionLocked
        || pendingPointer.tool !== tool
        || pendingPointer.documentIdentity !== document
        || !sameOrderedIds(pendingPointer.selectedIds, selectedIds)
      )
    ) {
      pendingAnnotationPointer.current = undefined;
    }
  }, [document, interactionLocked, selectedIds, tool]);
  useEffect(() => {
    disposed.current = false;
    return () => {
      disposed.current = true;
      interactionController.cancel();
      clearScheduledMove();
      releasePointerCapture();
      pendingAnnotationPointer.current = undefined;
      cancelAnnotationTransaction();
    };
  }, []);
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
          if (interactionLocked) return;
          if (!spacePanReady && tool === "selection") {
            const pendingPointer = pendingAnnotationPointer.current;
            if (pendingPointer) {
              if (pendingPointer.owner.pointerId === event.evt.pointerId) {
                pendingPointer.modifiers = modifiersFor(event.evt);
              }
              return;
            }
            if (event.target !== stage || isTransforming) return;
          } else if (!spacePanReady && isTransforming) {
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
            zoom: viewport.zoom,
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
              if (disposed.current) return;
              const latest = latestMove.current;
              latestMove.current = undefined;
              if (latest) {
                applyPreview(interactionController.update(latest.point, latest.modifiers));
              }
            });
          }
        }}
        onPointerUp={(event) => {
          const pendingPointer = pendingAnnotationPointer.current;
          if (
            pendingPointer
            && event.evt.pointerId === pendingPointer.owner.pointerId
          ) {
            pendingAnnotationPointer.current = undefined;
          }
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
          const annotationInteraction = activeAnnotationInteraction.current;
          if (
            annotationInteraction
            && event.evt.pointerId !== annotationInteraction.owner.pointerId
          ) return;
          const pendingPointer = pendingAnnotationPointer.current;
          if (
            pendingPointer
            && event.evt.pointerId !== pendingPointer.owner.pointerId
          ) return;
          pendingAnnotationPointer.current = undefined;
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
              draggable: !interactionLocked && tool === "selection" && selectedIdSet.has(element.id),
              textEditingEnabled: !interactionLocked && tool === "selection",
              onSelect: (id, toggle) => {
                if (interactionLocked) return;
                onSelect(id, toggle);
              },
              onEditText: (id) => onEditText(id),
              onPointerDown: (id, node, owner) => {
                if (
                  interactionLocked
                  || tool !== "selection"
                  || activeAnnotationInteraction.current
                  || pendingAnnotationPointer.current
                ) return;
                pendingAnnotationPointer.current = {
                  kind: "move",
                  elementId: id,
                  node,
                  owner,
                  cancelTransformer: transformer.current,
                  modifiers: undefined,
                  selectedIds: [...selectedIds],
                  tool,
                  documentIdentity: document,
                };
              },
              onDragStart: (id, node) => {
                const pointer = consumeMovePointer(id, node);
                if (!pointer.modifiers) {
                  throw new Error("Annotation move modifiers are unavailable");
                }
                const snapshotElements = structuredClone(selectedElements);
                const elementToMove = snapshotElements.find(
                  (candidate) => candidate.id === id,
                );
                if (!elementToMove) {
                  throw new Error(`Cannot move missing element: ${id}`);
                }
                onBeginTransaction("move");
                pointer.owner.container.setPointerCapture(pointer.owner.pointerId);
                activeAnnotationInteraction.current = {
                  kind: "move",
                  node,
                  element: elementToMove,
                  elements: snapshotElements,
                  nodes: selectedNodeMap(snapshotElements, nodes.current),
                  owner: pointer.owner,
                  cancelTransformer: pointer.cancelTransformer,
                  optionDuplicate: pointer.modifiers.option,
                  previewElements: undefined,
                  previewDelta: undefined,
                  selectedIds: pointer.selectedIds,
                  tool: pointer.tool,
                  document: structuredClone(document),
                  documentIdentity: pointer.documentIdentity,
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
                  const delta = {
                    x: x - elementToMove.x,
                    y: y - elementToMove.y,
                  };
                  if (active.optionDuplicate) {
                    const copies = active.previewElements
                      ? moveElementsWithinBounds(
                          active.previewElements,
                          deltaFromPreviousPreview(active, delta),
                          sourceBoundsFor(active.document),
                        )
                      : createDuplicateElements(
                          active.document,
                          active.elements,
                          delta,
                        );
                    active.previewDelta = previewDeltaFromStart(active.elements, copies);
                    active.previewElements = copies;
                    applyElementGeometryToNodes(active.elements, active.nodes);
                    setDuplicationPreview(copies);
                    return;
                  }
                  const moved = moveElementsWithinBounds(
                    active.elements,
                    delta,
                    sourceBoundsFor(active.document),
                  );
                  active.previewElements = moved;
                  applyElementGeometryToNodes(moved, active.nodes);
                } catch (error) {
                  cancelAnnotationTransaction();
                  throw error;
                }
              },
              onDragEnd: (id, node) => {
                const activeInteraction = activeAnnotationInteraction.current;
                if (
                  activeInteraction?.kind !== "move"
                  || activeInteraction.element.id !== id
                  || activeInteraction.node !== node
                ) return;
                let duplicatedIds: readonly string[] | undefined;
                try {
                  const previewElements = activeInteraction.previewElements;
                  if (!previewElements) {
                    cancelAnnotationTransaction();
                    return;
                  }
                  const changed = (() => {
                    if (!activeInteraction.optionDuplicate) {
                      return !sameElementSnapshots(activeInteraction.elements, previewElements);
                    }
                    const previewDelta = activeInteraction.previewDelta;
                    if (!previewDelta) {
                      throw new Error("Option-drag preview delta is unavailable");
                    }
                    return previewDelta.x !== 0 || previewDelta.y !== 0;
                  })();
                  if (!changed) {
                    cancelAnnotationTransaction();
                    return;
                  }
                  onCommand(activeInteraction.optionDuplicate
                    ? { type: "createMany", elements: [...previewElements] }
                    : { type: "updateMany", elements: [...previewElements] });
                  if (activeInteraction.optionDuplicate) {
                    duplicatedIds = previewElements.map((element) => element.id);
                  }
                  onCommitTransaction();
                  releaseAnnotationPointerCapture(activeInteraction);
                  activeAnnotationInteraction.current = undefined;
                } catch (error) {
                  cancelAnnotationTransaction();
                  throw error;
                } finally {
                  setDuplicationPreview([]);
                }
                if (duplicatedIds) routeSelection(duplicatedIds);
              },
              onTransformStart: (id, node) => {
                const activeInteraction = activeAnnotationInteraction.current;
                if (activeInteraction?.kind === "transform") return;
                if (activeInteraction) {
                  throw new Error("Cannot transform during an active move");
                }
                const pointer = consumeTransformPointer(node);
                if (!pointer.modifiers) {
                  throw new Error("Annotation transform modifiers are unavailable");
                }
                const snapshotElements = structuredClone(selectedElements);
                const elementToTransform = snapshotElements.find((candidate) => candidate.id === id);
                if (!elementToTransform) throw new Error(`Cannot transform missing element: ${id}`);
                onBeginTransaction("transform");
                pointer.owner.container.setPointerCapture(pointer.owner.pointerId);
                activeAnnotationInteraction.current = {
                  kind: "transform",
                  node,
                  element: elementToTransform,
                  elements: snapshotElements,
                  nodes: selectedNodeMap(snapshotElements, nodes.current),
                  owner: pointer.owner,
                  cancelTransformer: pointer.cancelTransformer,
                  optionDuplicate: false,
                  previewElements: undefined,
                  previewDelta: undefined,
                  selectedIds: pointer.selectedIds,
                  tool: pointer.tool,
                  document: structuredClone(document),
                  documentIdentity: pointer.documentIdentity,
                };
                setIsTransforming(true);
              },
              onTransformEnd: (id, node) => {
                const currentInteraction = activeAnnotationInteraction.current;
                if (
                  currentInteraction?.kind !== "transform"
                  || currentInteraction.nodes.get(id) !== node
                ) return;
                try {
                  const active = currentInteraction;
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
                  if (sameElementSnapshots(active.elements, transformedElements)) {
                    cancelAnnotationTransaction();
                    return;
                  }
                  onCommand({
                    type: "updateMany",
                    elements: transformedElements,
                  });
                  onCommitTransaction();
                  releaseAnnotationPointerCapture(active);
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
            {duplicationPreview.length > 0 && (
              <Group listening={false} data-testid="duplication-preview">
                {duplicationPreview.map((element) => renderElement(
                  element,
                  previewInteractionHandlers,
                  blurredSource,
                ))}
              </Group>
            )}
            {marqueePreview && (
              <Group listening={false} data-testid="marquee-preview">
                <Rect
                  x={marqueePreview.x}
                  y={marqueePreview.y}
                  width={marqueePreview.width}
                  height={marqueePreview.height}
                  fill="rgba(22, 119, 255, 0.08)"
                  stroke="#1677FF"
                  dash={[4, 4]}
                />
              </Group>
            )}
            {selectedElements.map((selected) => (
              <SelectionOutline key={`selection-outline-${selected.id}`} element={selected} />
            ))}
            <Transformer
              ref={transformer}
              rotateEnabled={!selectedElements.some((element) => element.type === "blur")}
              flipEnabled={false}
              onPointerDown={(event) => {
                if (
                  interactionLocked
                  || tool !== "selection"
                  || activeAnnotationInteraction.current
                  || pendingAnnotationPointer.current
                ) return;
                const transformerNode = event.currentTarget as Konva.Transformer;
                const transformNodes = transformerNode.nodes() as Konva.Group[];
                if (transformNodes.length === 0) {
                  throw new Error("Annotation transform requires a selected target");
                }
                pendingAnnotationPointer.current = {
                  kind: "transform",
                  nodes: new Set(transformNodes),
                  owner: pointerOwnerFor(transformerNode, event.evt),
                  cancelTransformer: transformerNode,
                  modifiers: undefined,
                  selectedIds: [...selectedIds],
                  tool,
                  documentIdentity: document,
                };
              }}
            />
          </Group>
        </Layer>
      </Stage>
      {textEditorOverlay}
    </div>
  );
});

function SelectionOutline({ element }: { element: EditorElement }) {
  const bounds = rotatedElementBounds(element);
  return (
    <Rect
      x={bounds.x}
      y={bounds.y}
      width={bounds.width}
      height={bounds.height}
      stroke="#1677FF"
      dash={[4, 4]}
      listening={false}
    />
  );
}

const previewInteractionHandlers = {
  selected: false,
  draggable: false,
  textEditingEnabled: false,
  onSelect: () => {},
  onEditText: () => {},
  onPointerDown: () => {},
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

type MovePointerSnapshot = {
  kind: "move";
  elementId: string;
  node: Konva.Group;
  owner: ElementPointerOwner;
  cancelTransformer: TransformerControl | null;
  modifiers: InteractionModifiers | undefined;
  selectedIds: readonly string[];
  tool: EditorTool;
  documentIdentity: EditorDocument;
};

type TransformPointerSnapshot = {
  kind: "transform";
  nodes: ReadonlySet<Konva.Group>;
  owner: ElementPointerOwner;
  cancelTransformer: TransformerControl;
  modifiers: InteractionModifiers | undefined;
  selectedIds: readonly string[];
  tool: EditorTool;
  documentIdentity: EditorDocument;
};

type AnnotationPointerSnapshot = MovePointerSnapshot | TransformPointerSnapshot;

type AnnotationInteractionState = {
  kind: "move" | "transform";
  node: Konva.Group;
  element: EditorElement;
  elements: EditorElement[];
  nodes: Map<string, Konva.Group>;
};

type ActiveAnnotationInteraction = AnnotationInteractionState & {
  owner: ElementPointerOwner;
  cancelTransformer: TransformerControl | null;
  optionDuplicate: boolean;
  previewElements: readonly EditorElement[] | undefined;
  previewDelta: Point | undefined;
  selectedIds: readonly string[];
  tool: EditorTool;
  document: EditorDocument;
  documentIdentity: EditorDocument;
};

export function cancelAnnotationInteraction(
  interaction: AnnotationInteractionState,
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
  elements: readonly EditorElement[],
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

function applyElementGeometryToNodes(
  elements: readonly EditorElement[],
  registeredNodes: Map<string, Konva.Group>,
): void {
  elements.forEach((element) => {
    const node = registeredNodes.get(element.id);
    if (!node) {
      throw new Error(`Cannot preview unregistered element: ${element.id}`);
    }
    node.x(element.x);
    node.y(element.y);
    node.scaleX(1);
    node.scaleY(1);
    node.rotation(element.rotation);
  });
}

function deltaFromPreviousPreview(
  interaction: ActiveAnnotationInteraction,
  requestedDelta: Point,
): Point {
  const previewDelta = interaction.previewDelta;
  if (!previewDelta) {
    throw new Error("Option-drag preview delta is unavailable");
  }
  return {
    x: requestedDelta.x - previewDelta.x,
    y: requestedDelta.y - previewDelta.y,
  };
}

function previewDeltaFromStart(
  startingElements: readonly EditorElement[],
  previewElements: readonly EditorElement[],
): Point {
  const startingElement = startingElements[0];
  const previewElement = previewElements[0];
  if (!startingElement || !previewElement) {
    throw new Error("Option-drag requires a non-empty selection preview");
  }
  return {
    x: previewElement.x - startingElement.x,
    y: previewElement.y - startingElement.y,
  };
}

function sourceBoundsFor(document: EditorDocument) {
  return {
    sourceWidth: document.sourcePixelWidth,
    sourceHeight: document.sourcePixelHeight,
  };
}

function releaseAnnotationPointerCapture(
  interaction: ActiveAnnotationInteraction,
): void {
  const { container, pointerId } = interaction.owner;
  if (container.hasPointerCapture(pointerId)) {
    container.releasePointerCapture(pointerId);
  }
}

function sameOrderedIds(
  left: readonly string[],
  right: readonly string[],
): boolean {
  return left.length === right.length
    && left.every((id, index) => id === right[index]);
}

function sameElementSnapshots(
  left: readonly EditorElement[],
  right: readonly EditorElement[],
): boolean {
  return left.length === right.length
    && left.every((element, index) => JSON.stringify(element) === JSON.stringify(right[index]));
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
