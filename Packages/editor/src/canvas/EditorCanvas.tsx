import { useEffect, useMemo, useRef, useState } from "react";
import type Konva from "konva";
import { Group, Image as KonvaImage, Layer, Rect, Stage, Transformer } from "react-konva";
import type { EditorCommand, EditorDocument, EditorElement, EditorTool, Point } from "../model/elements";
import { CanvasViewport } from "./CanvasViewport";
import { moveElementWithinBounds } from "./SelectionController";
import { createElement } from "./tools/createElement";
import { renderElement } from "./renderElement";

export function EditorCanvas({ document, sourceImageURL, tool, zoom, selectedId, onSelect, onCommand, onBeginTransaction, onCommitTransaction }: {
  document: EditorDocument;
  sourceImageURL: string;
  tool: EditorTool;
  zoom: number;
  selectedId: string | undefined;
  onSelect: (id: string | undefined) => void;
  onCommand: (command: EditorCommand) => void;
  onBeginTransaction: (label: string) => void;
  onCommitTransaction: () => void;
}) {
  const image = useSourceImage(sourceImageURL);
  const viewport = useMemo(() => new CanvasViewport({ sourceWidth: document.sourcePixelWidth, sourceHeight: document.sourcePixelHeight }), [document.sourcePixelWidth, document.sourcePixelHeight]);
  viewport.setTransform({ zoom, panX: 0, panY: 0 });
  const nodes = useRef(new Map<string, Konva.Group>());
  const transformer = useRef<Konva.Transformer | null>(null);
  const gesture = useRef<{ start: Point; points: Point[] } | undefined>(undefined);
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
  const creationContext = () => ({
    defaults: document.defaults,
    nextNumberMarker: Math.max(0, ...document.elements.filter((element) => element.type === "numberMarker").map((element) => element.number)) + 1,
    nextZIndex: Math.max(-1, ...document.elements.map((element) => element.zIndex)) + 1,
    seed: Math.max(0, ...document.elements.map((element) => element.seed)) + 1,
  });
  const finishGesture = (stage: Konva.Stage) => {
    const activeGesture = gesture.current;
    if (!activeGesture) return;
    const end = sourcePoint(stage);
    const creationGesture = tool === "freehand" || tool === "highlighter"
      ? { kind: "path" as const, points: [...activeGesture.points, end] }
      : tool === "text" || tool === "numberMarker"
        ? { kind: "point" as const, point: activeGesture.start }
        : { kind: "box" as const, start: activeGesture.start, end };
    onCommand({ type: "create", element: createElement(tool as Exclude<EditorTool, "selection">, creationGesture, creationContext()) });
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
          if (tool === "selection" || isTransforming) {
            if (event.target === event.target.getStage()) onSelect(undefined);
            return;
          }
          const stage = event.target.getStage();
          if (!stage) throw new Error("Canvas stage is unavailable");
          const start = sourcePoint(stage);
          gesture.current = { start, points: [start] };
          onBeginTransaction("create");
        }}
        onMouseMove={(event) => {
          if (!gesture.current || (tool !== "freehand" && tool !== "highlighter")) return;
          const stage = event.target.getStage();
          if (!stage) throw new Error("Canvas stage is unavailable");
          gesture.current.points.push(sourcePoint(stage));
        }}
        onMouseUp={(event) => {
          const stage = event.target.getStage();
          if (!stage) throw new Error("Canvas stage is unavailable");
          finishGesture(stage);
        }}
      >
        <Layer id="sourceLayer" listening={false}>
          <Group scaleX={zoom} scaleY={zoom}>
            {image && <KonvaImage image={image} width={document.sourcePixelWidth} height={document.sourcePixelHeight} />}
          </Group>
        </Layer>
        <Layer id="annotationLayer">
          <Group scaleX={zoom} scaleY={zoom}>
            {orderedElements.map((element) => renderElement(element, {
              selected: selectedId === element.id,
              draggable: tool === "selection" && selectedId === element.id,
              onSelect: (id) => onSelect(id),
              onDragStart: () => onBeginTransaction("move"),
              onDragMove: (id, x, y) => {
                const elementToMove = document.elements.find((candidate) => candidate.id === id);
                if (!elementToMove) throw new Error(`Cannot move missing element: ${id}`);
                onCommand({ type: "update", element: moveElementWithinBounds(elementToMove, { x, y }, { sourceWidth: document.sourcePixelWidth, sourceHeight: document.sourcePixelHeight }) });
              },
              onDragEnd: onCommitTransaction,
              onTransformStart: () => {
                setIsTransforming(true);
                onBeginTransaction("transform");
              },
              onTransformEnd: (id, node) => {
                const elementToTransform = document.elements.find((candidate) => candidate.id === id);
                if (!elementToTransform) throw new Error(`Cannot transform missing element: ${id}`);
                const positioned = moveElementWithinBounds(elementToTransform, { x: node.x(), y: node.y() }, { sourceWidth: document.sourcePixelWidth, sourceHeight: document.sourcePixelHeight });
                onCommand({
                  type: "update",
                  element: resizeElement(positioned, node.scaleX(), node.scaleY(), node.rotation()),
                });
                setIsTransforming(false);
                onCommitTransaction();
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

function resizeElement(element: EditorElement, scaleX: number, scaleY: number, rotation: number): EditorElement {
  if (!Number.isFinite(scaleX) || !Number.isFinite(scaleY) || scaleX < 0 || scaleY < 0) {
    throw new Error("Transform scale must be a non-negative finite number");
  }
  const dimensions = { width: element.width * scaleX, height: element.height * scaleY, rotation };
  switch (element.type) {
    case "arrow":
      return {
        ...element,
        ...dimensions,
        points: [scalePoint(element.points[0], element, scaleX, scaleY), scalePoint(element.points[1], element, scaleX, scaleY)],
      };
    case "freehand":
    case "highlighter":
      return { ...element, ...dimensions, points: element.points.map((point) => scalePoint(point, element, scaleX, scaleY)) };
    default:
      return { ...element, ...dimensions };
  }
}

function scalePoint(point: Point, element: EditorElement, scaleX: number, scaleY: number): Point {
  return {
    x: element.x + (point.x - element.x) * scaleX,
    y: element.y + (point.y - element.y) * scaleY,
  };
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
