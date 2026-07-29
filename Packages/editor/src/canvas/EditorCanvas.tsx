import { useEffect, useMemo, useRef, useState } from "react";
import type Konva from "konva";
import { Group, Image as KonvaImage, Layer, Rect, Stage, Transformer } from "react-konva";
import type { CreationGesture, EditorCommand, EditorDocument, EditorElement, EditorTool, PaletteColor, Point } from "../model/elements";
import { CanvasViewport } from "./CanvasViewport";
import { CanvasPointerController, moveElementWithinBounds, resizeElementWithinBounds } from "./SelectionController";
import { createElement } from "./tools/createElement";
import { renderElement } from "./renderElement";

export function EditorCanvas({ document, sourceImageURL, tool, zoom, pan, rectangleFillColor, selectedId, onSelect, onCommand, onBeginTransaction, onCommitTransaction, onPanChange }: {
  document: EditorDocument;
  sourceImageURL: string;
  tool: EditorTool;
  zoom: number;
  pan: Point;
  rectangleFillColor: PaletteColor | null;
  selectedId: string | undefined;
  onSelect: (id: string | undefined) => void;
  onCommand: (command: EditorCommand) => void;
  onBeginTransaction: (label: string) => void;
  onCommitTransaction: () => void;
  onPanChange: (pan: Point) => void;
}) {
  const image = useSourceImage(sourceImageURL);
  const viewport = useMemo(() => new CanvasViewport({ sourceWidth: document.sourcePixelWidth, sourceHeight: document.sourcePixelHeight }), [document.sourcePixelWidth, document.sourcePixelHeight]);
  viewport.setTransform({ zoom, panX: pan.x, panY: pan.y });
  const nodes = useRef(new Map<string, Konva.Group>());
  const transformer = useRef<Konva.Transformer | null>(null);
  const gesture = useRef<{ start: Point; points: Point[] } | undefined>(undefined);
  const panGesture = useRef<{ start: Point; pan: Point } | undefined>(undefined);
  const pointerController = useRef(new CanvasPointerController());
  const suppressedAnnotationDrag = useRef(false);
  const suppressedTransform = useRef(false);
  const [isTransforming, setIsTransforming] = useState(false);

  useEffect(() => {
    const selectedNode = selectedId ? nodes.current.get(selectedId) : undefined;
    transformer.current?.nodes(selectedNode ? [selectedNode] : []);
    transformer.current?.getLayer()?.batchDraw();
  }, [selectedId, document]);

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
    const end = sourcePoint(stage);
    const creationGesture = tool === "freehand" || tool === "highlighter"
      ? { kind: "path" as const, points: [...activeGesture.points, end] }
      : tool === "text" || tool === "numberMarker"
        ? { kind: "point" as const, point: activeGesture.start }
        : { kind: "box" as const, start: activeGesture.start, end };
    onCommand({ type: "create", element: createCanvasElement(document, tool as Exclude<EditorTool, "selection">, creationGesture, rectangleFillColor) });
    gesture.current = undefined;
    onCommitTransaction();
  };
  const orderedElements = [
    ...document.elements.filter((element) => element.type === "highlighter").sort(byZIndex),
    ...document.elements.filter((element) => element.type !== "highlighter").sort(byZIndex),
  ];

  return (
    <div className="canvas-shell" data-testid="editor-canvas">
      <Stage
        width={Math.ceil(document.sourcePixelWidth * zoom)}
        height={Math.ceil(document.sourcePixelHeight * zoom)}
        onMouseDown={(event) => {
          const stage = event.target.getStage();
          if (!stage) throw new Error("Canvas stage is unavailable");
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
          gesture.current = { start, points: [start] };
          onBeginTransaction("create");
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
          if (!gesture.current || (tool !== "freehand" && tool !== "highlighter")) return;
          gesture.current.points.push(sourcePoint(stage));
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
              selected: selectedId === element.id,
              draggable: tool === "selection" && selectedId === element.id,
              onSelect: (id) => onSelect(id),
              onDragStart: (node) => {
                if (!pointerController.current.shouldDispatchAnnotationDrag()) {
                  suppressedAnnotationDrag.current = true;
                  node.stopDrag();
                  return;
                }
                onBeginTransaction("move");
              },
              onDragMove: (id, x, y) => {
                if (!pointerController.current.shouldDispatchAnnotationDrag()) return;
                const elementToMove = document.elements.find((candidate) => candidate.id === id);
                if (!elementToMove) throw new Error(`Cannot move missing element: ${id}`);
                onCommand({ type: "update", element: moveElementWithinBounds(elementToMove, { x, y }, { sourceWidth: document.sourcePixelWidth, sourceHeight: document.sourcePixelHeight }) });
              },
              onDragEnd: () => {
                if (suppressedAnnotationDrag.current) {
                  suppressedAnnotationDrag.current = false;
                  return;
                }
                if (!pointerController.current.shouldDispatchAnnotationDrag()) return;
                onCommitTransaction();
                pointerController.current.end();
              },
              onTransformStart: () => {
                if (!pointerController.current.shouldDispatchAnnotationDrag()) {
                  suppressedTransform.current = true;
                  return;
                }
                setIsTransforming(true);
                onBeginTransaction("transform");
              },
              onTransformEnd: (id, node) => {
                if (suppressedTransform.current) {
                  suppressedTransform.current = false;
                  return;
                }
                if (!pointerController.current.shouldDispatchAnnotationDrag()) return;
                const elementToTransform = document.elements.find((candidate) => candidate.id === id);
                if (!elementToTransform) throw new Error(`Cannot transform missing element: ${id}`);
                onCommand({
                  type: "update",
                  element: resizeElementWithinBounds(
                    elementToTransform,
                    { x: node.x(), y: node.y() },
                    node.scaleX(),
                    node.scaleY(),
                    node.rotation(),
                    { sourceWidth: document.sourcePixelWidth, sourceHeight: document.sourcePixelHeight },
                  ),
                });
                setIsTransforming(false);
                onCommitTransaction();
                pointerController.current.end();
              },
              registerNode: (id, node) => {
                if (node) nodes.current.set(id, node);
                else nodes.current.delete(id);
              },
            }))}
            {selectedId && document.elements.find((element) => element.id === selectedId) && (() => {
              const selected = document.elements.find((element) => element.id === selectedId);
              if (!selected) throw new Error(`Cannot outline missing selected element: ${selectedId}`);
              return <Rect x={selected.x} y={selected.y} width={selected.width} height={selected.height} stroke="#1677FF" dash={[4, 4]} listening={false} />;
            })()}
            <Transformer ref={transformer} rotateEnabled={true} />
          </Group>
        </Layer>
      </Stage>
    </div>
  );
}

function byZIndex(left: EditorElement, right: EditorElement): number {
  return left.zIndex - right.zIndex;
}

export function createCanvasElement(
  document: EditorDocument,
  tool: Exclude<EditorTool, "selection">,
  gesture: CreationGesture,
  rectangleFillColor: PaletteColor | null,
): EditorElement {
  const element = createElement(tool, gesture, {
    defaults: document.defaults,
    nextNumberMarker: Math.max(0, ...document.elements.filter((candidate) => candidate.type === "numberMarker").map((candidate) => candidate.number)) + 1,
    nextZIndex: Math.max(-1, ...document.elements.map((candidate) => candidate.zIndex)) + 1,
    seed: Math.max(0, ...document.elements.map((candidate) => candidate.seed)) + 1,
  });
  return element.type === "rectangle" ? { ...element, fillColor: rectangleFillColor } : element;
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
