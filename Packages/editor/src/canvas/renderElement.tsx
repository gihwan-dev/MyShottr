import type { ComponentProps } from "react";
import type Konva from "konva";
import { Circle, Group, Image as KonvaImage, Line, Path, Rect, Text } from "react-konva";
import type { EditorElement } from "../model/elements";
import { roughPathsFor } from "./roughRenderer";
import { KONVA_DEFAULT_FONT_FAMILY, NUMBER_MARKER_FONT_SIZE, TEXT_LINE_HEIGHT } from "./renderingConstants";

export type ElementInteractionHandlers = {
  selected: boolean;
  draggable: boolean;
  textEditingEnabled: boolean;
  onSelect: (id: string) => void;
  onEditText: (id: string) => void;
  onPointerDown: (id: string, node: Konva.Group, owner: ElementPointerOwner) => void;
  onDragStart: (id: string, node: Konva.Group) => void;
  onDragMove: (id: string, x: number, y: number) => void;
  onDragEnd: (id: string, node: Konva.Group) => void;
  onTransformStart: (id: string, node: Konva.Group) => void;
  onTransformEnd: (id: string, node: Konva.Group) => void;
  registerNode: (id: string, node: Konva.Group | null) => void;
};

export type ElementPointerOwner = {
  pointerId: number;
  container: HTMLDivElement;
};

export function renderElement(
  element: EditorElement,
  handlers: ElementInteractionHandlers,
  blurredSource?: HTMLCanvasElement,
) {
  const groupProps: ComponentProps<typeof Group> = {
    ref: (node: Konva.Group | null) => handlers.registerNode(element.id, node),
    x: element.x,
    y: element.y,
    rotation: element.rotation,
    opacity: element.opacity,
    scaleX: 1,
    scaleY: 1,
    draggable: handlers.draggable,
    onClick: () => handlers.onSelect(element.id),
    onTap: () => handlers.onSelect(element.id),
    "data-testid": `element-${element.id}`,
    onPointerDown: (event) => {
      const node = event.currentTarget as Konva.Group;
      handlers.onPointerDown(element.id, node, pointerOwnerFor(node, event.evt));
    },
    onDragStart: (event) => {
      const node = event.currentTarget as Konva.Group;
      handlers.onDragStart(element.id, node);
    },
    onDragMove: (event) => {
      const group = event.currentTarget as Konva.Group;
      handlers.onDragMove(element.id, group.x(), group.y());
    },
    onDragEnd: (event) => {
      const node = event.currentTarget as Konva.Group;
      handlers.onDragEnd(element.id, node);
    },
    onTransformStart: (event) => {
      const node = event.currentTarget as Konva.Group;
      handlers.onTransformStart(element.id, node);
    },
    onTransformEnd: (event) => {
      const node = event.currentTarget as Konva.Group;
      handlers.onTransformEnd(element.id, node);
    },
  };

  if (element.type === "text" && handlers.textEditingEnabled) {
    groupProps.onDblClick = () => handlers.onEditText(element.id);
  }

  switch (element.type) {
    case "rectangle":
    case "arrow":
    case "line":
      return (
        <Group key={element.id} {...groupProps}>
          {roughPathsFor(element).map((path, index) => (
            <Path key={index} data={path.d} stroke={path.stroke} strokeWidth={path.strokeWidth} fill={path.fill} />
          ))}
        </Group>
      );
    case "text":
      return <Group key={element.id} {...groupProps}><Text text={element.text} fill={element.color} fontFamily={KONVA_DEFAULT_FONT_FAMILY} fontSize={element.fontSize} lineHeight={TEXT_LINE_HEIGHT} width={element.width} height={element.height} /></Group>;
    case "freehand":
      return <Group key={element.id} {...groupProps}><Line points={relativePoints(element.points, element.x, element.y)} stroke={element.color} strokeWidth={element.strokeWidth} lineCap="round" lineJoin="round" /></Group>;
    case "highlighter":
      return <Group key={element.id} {...groupProps}><Line points={relativePoints(element.points, element.x, element.y)} stroke={element.color} strokeWidth={8} lineCap="round" lineJoin="round" /></Group>;
    case "blur":
      if (!blurredSource) return null;
      return (
        <Group key={element.id} {...groupProps} clipX={0} clipY={0} clipWidth={element.width} clipHeight={element.height}>
          <KonvaImage image={blurredSource} x={-element.x} y={-element.y} width={blurredSource.width} height={blurredSource.height} />
        </Group>
      );
    case "redaction":
      return <Group key={element.id} {...groupProps}><Rect width={element.width} height={element.height} fill={element.color} /></Group>;
    case "numberMarker":
      return (
        <Group key={element.id} {...groupProps}>
          <Circle x={element.width / 2} y={element.height / 2} radius={Math.min(element.width, element.height) / 2} fill={element.color} />
          <Text text={String(element.number)} width={element.width} height={element.height} align="center" verticalAlign="middle" fontFamily={KONVA_DEFAULT_FONT_FAMILY} fontSize={NUMBER_MARKER_FONT_SIZE} fill="#FFFFFF" />
        </Group>
      );
  }
}

function relativePoints(points: Array<{ x: number; y: number }>, originX: number, originY: number): number[] {
  return points.flatMap((point) => [point.x - originX, point.y - originY]);
}

export function pointerOwnerFor(
  node: Konva.Node,
  event: PointerEvent,
): ElementPointerOwner {
  const pointerId = event.pointerId;
  if (!Number.isInteger(pointerId)) {
    throw new Error("Annotation interaction requires a pointer owner");
  }
  const stage = node.getStage();
  if (!stage) throw new Error("Annotation interaction stage is unavailable");
  return {
    pointerId,
    container: stage.container(),
  };
}
