import type {
  EditorCommand,
  EditorDefaults,
  EditorDocument,
  Point,
  TextElement,
} from "../model/elements";
import {
  createTextDraftPresentation,
  createTextElementFromDocument,
} from "../canvas/tools/createElement";

export type TextEditSession =
  | {
      kind: "new";
      point: Point;
      defaults: EditorDefaults;
      initialText: "";
    }
  | {
      kind: "existing";
      element: TextElement;
      initialText: string;
    };

export type TextEditResult =
  | { type: "cancel" }
  | { type: "commit"; text: string };

export type TextEditTransition =
  | { type: "none" }
  | {
      type: "create";
      point: Point;
      defaults: EditorDefaults;
      text: string;
    }
  | {
      type: "update";
      element: TextElement;
      text: string;
    }
  | { type: "delete"; id: string };

export type TextEditPresentation = Pick<
  TextElement,
  "x" | "y" | "width" | "height" | "rotation" | "color" | "fontSize"
>;

export type MeasureText = (
  text: string,
  fontSize: TextElement["fontSize"],
) => Pick<TextElement, "width" | "height">;

export function transitionTextEditSession(
  session: TextEditSession,
  result: TextEditResult,
): TextEditTransition {
  if (result.type === "cancel") return { type: "none" };

  const blank = result.text.trim().length === 0;
  if (session.kind === "new") {
    return blank
      ? { type: "none" }
      : {
          type: "create",
          point: session.point,
          defaults: session.defaults,
          text: result.text,
        };
  }

  return blank
    ? { type: "delete", id: session.element.id }
    : {
        type: "update",
        element: session.element,
        text: result.text,
      };
}

export function textEditPresentation(
  session: TextEditSession,
): TextEditPresentation {
  if (session.kind === "existing") {
    const { x, y, width, height, rotation, color, fontSize } = session.element;
    return { x, y, width, height, rotation, color, fontSize };
  }
  return createTextDraftPresentation(session.point, session.defaults);
}

export function textEditCommand(
  document: EditorDocument,
  session: TextEditSession,
  result: TextEditResult,
  measureText: MeasureText,
): EditorCommand | undefined {
  const transition = transitionTextEditSession(session, result);
  switch (transition.type) {
    case "none":
      return undefined;
    case "create": {
      const presentation = createTextDraftPresentation(
        transition.point,
        transition.defaults,
      );
      return {
        type: "create",
        element: createTextElementFromDocument(document, {
          point: transition.point,
          defaults: transition.defaults,
          text: transition.text,
          bounds: measureText(transition.text, presentation.fontSize),
        }),
      };
    }
    case "update":
      return {
        type: "update",
        element: {
          ...transition.element,
          text: transition.text,
          ...measureText(transition.text, transition.element.fontSize),
        },
      };
    case "delete":
      return { type: "delete", ids: [transition.id] };
  }
}
