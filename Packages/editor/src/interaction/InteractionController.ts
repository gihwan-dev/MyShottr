import type {
  EditorCommand,
  EditorDefaults,
  EditorDocument,
  EditorElement,
  EditorTool,
  Point,
} from "../model/elements";
import {
  createElementFromDocument,
  createElementId,
} from "../canvas/tools/createElement";
import {
  constrainSquare,
  constrainToNearest45Degrees,
} from "./geometry";
import {
  intersectingElementIds,
  isMarqueeGesture,
  marqueeBounds,
} from "./selectionGeometry";
import type { Rect } from "../viewport/ViewportController";

export type InteractionModifiers = {
  shift: boolean;
  option: boolean;
};

export type InteractionBeginInput = {
  pointerId: number;
  tool: EditorTool;
  point: Point;
  modifiers: InteractionModifiers;
  defaults: EditorDefaults;
  document: EditorDocument;
  selectedIds: readonly string[];
  viewportPan: boolean;
  zoom: number;
};

export type InteractionSnapshot = {
  pointerId: number;
  tool: EditorTool;
  defaults: EditorDefaults;
  selectedElements: readonly EditorElement[];
  start: Point;
  modifiers: InteractionModifiers;
  zoom: number;
};

export type InteractionPreview =
  | { type: "none" }
  | { type: "creation"; element: EditorElement }
  | { type: "marquee"; rect: Rect }
  | { type: "viewport"; pan: Point };

export type InteractionCommit =
  | { type: "none" }
  | {
      type: "command";
      command: EditorCommand;
      selectedIds?: readonly string[];
    }
  | { type: "selection"; selectedIds: readonly string[] }
  | {
      type: "beginNewText";
      point: Point;
      defaults: EditorDefaults;
    }
  | { type: "viewport"; pan: Point };

export class InteractionController {
  private interaction: ActiveInteraction | undefined;
  private currentPreview: InteractionPreview | null = null;

  public get active(): boolean {
    return this.interaction !== undefined;
  }

  public get preview(): InteractionPreview | null {
    return this.currentPreview;
  }

  public begin(input: InteractionBeginInput): InteractionPreview | null {
    if (this.interaction) return this.currentPreview;
    const document = structuredClone(input.document);
    const defaults = structuredClone(input.defaults);
    document.defaults = defaults;
    const selectedElements = input.selectedIds.map((id) => {
      const element = document.elements.find((candidate) => candidate.id === id);
      if (!element) throw new Error(`Cannot snapshot missing element: ${id}`);
      return element;
    });
    this.interaction = {
      snapshot: {
        pointerId: input.pointerId,
        tool: input.tool,
        defaults,
        selectedElements,
        start: { ...input.point },
        modifiers: { ...input.modifiers },
        zoom: input.zoom,
      },
      document,
      selectedIds: [...input.selectedIds],
      viewportPan: input.viewportPan,
      points: [{ ...input.point }],
      previewId: createElementId(),
    };
    const preview = input.viewportPan || input.tool === "numberMarker"
      ? this.previewFor(this.interaction, input.point, input.modifiers, false)
      : { type: "none" } as const;
    this.currentPreview = preview.type === "none" ? null : preview;
    return this.currentPreview;
  }

  public update(point: Point, modifiers: InteractionModifiers): InteractionPreview {
    const interaction = this.interaction;
    if (!interaction) return { type: "none" };
    const preview = this.previewFor(interaction, point, modifiers, true);
    this.currentPreview = preview.type === "none" ? null : preview;
    return preview;
  }

  public commit(point: Point, modifiers: InteractionModifiers): InteractionCommit {
    const interaction = this.interaction;
    if (!interaction) return { type: "none" };
    this.interaction = undefined;
    this.currentPreview = null;

    if (interaction.viewportPan) {
      return { type: "viewport", pan: delta(interaction.snapshot.start, point) };
    }
    if (interaction.snapshot.tool === "selection") {
      return {
        type: "selection",
        selectedIds: isMarqueeGesture(
          interaction.snapshot.start,
          point,
          interaction.snapshot.zoom,
        )
          ? intersectingElementIds(
              interaction.document.elements,
              marqueeBounds(interaction.snapshot.start, point),
            )
          : [],
      };
    }
    if (interaction.snapshot.tool === "text") {
      return {
        type: "beginNewText",
        point: interaction.snapshot.start,
        defaults: interaction.snapshot.defaults,
      };
    }
    const gesture = gestureFor(interaction, point, modifiers, true);
    return {
      type: "command",
      command: {
        type: "create",
        element: createElementFromDocument(
          interaction.document,
          interaction.snapshot.tool,
          gesture,
        ),
      },
    };
  }

  public cancel(): void {
    this.interaction = undefined;
    this.currentPreview = null;
  }

  private previewFor(
    interaction: ActiveInteraction,
    point: Point,
    modifiers: InteractionModifiers,
    appendPathPoint: boolean,
  ): InteractionPreview {
    if (interaction.viewportPan) {
      return { type: "viewport", pan: delta(interaction.snapshot.start, point) };
    }
    const tool = interaction.snapshot.tool;
    if (tool === "selection") {
      return isMarqueeGesture(
        interaction.snapshot.start,
        point,
        interaction.snapshot.zoom,
      )
        ? {
            type: "marquee",
            rect: marqueeBounds(interaction.snapshot.start, point),
          }
        : { type: "none" };
    }
    if (tool === "text") return { type: "none" };
    return {
      type: "creation",
      element: createElementFromDocument(
        interaction.document,
        tool,
        gestureFor(interaction, point, modifiers, appendPathPoint),
        interaction.previewId,
      ),
    };
  }
}

type ActiveInteraction = {
  snapshot: InteractionSnapshot;
  document: EditorDocument;
  selectedIds: readonly string[];
  viewportPan: boolean;
  points: Point[];
  previewId: string;
};

function gestureFor(
  interaction: ActiveInteraction,
  point: Point,
  modifiers: InteractionModifiers,
  appendPathPoint: boolean,
) {
  const { tool, start } = interaction.snapshot;
  if (tool === "freehand" || tool === "highlighter") {
    if (appendPathPoint && !samePoint(interaction.points.at(-1), point)) {
      interaction.points.push({ ...point });
    }
    return { kind: "path", points: interaction.points } as const;
  }
  if (tool === "numberMarker" || tool === "text") {
    return { kind: "point", point: start } as const;
  }
  let end = point;
  if (modifiers.shift && tool === "rectangle") {
    end = constrainSquare(start, point);
  } else if (modifiers.shift && (tool === "arrow" || tool === "line")) {
    end = constrainToNearest45Degrees(start, point);
  }
  return { kind: "box", start, end } as const;
}

function delta(start: Point, end: Point): Point {
  return { x: end.x - start.x, y: end.y - start.y };
}

function samePoint(left: Point | undefined, right: Point): boolean {
  return left?.x === right.x && left.y === right.y;
}
