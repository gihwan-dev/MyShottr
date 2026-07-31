import type { EditorTool } from "../model/elements";
import {
  SHORTCUT_REGISTRY,
  type ShortcutDefinition,
} from "./shortcutRegistry";

export type ShortcutContext = {
  interactionActive: boolean;
  shortcutHelpOpen: boolean;
  textEditing: boolean;
};

export type EditorShortcutCommand =
  | { type: "selectTool"; tool: EditorTool }
  | { type: "delete" }
  | { type: "duplicate" }
  | { type: "copy" }
  | { type: "paste" }
  | { type: "bringForward" }
  | { type: "sendBackward" }
  | { type: "undo" }
  | { type: "redo" }
  | { type: "escape" }
  | { type: "openShortcutHelp" }
  | { type: "zoom100" }
  | { type: "fitImage" }
  | { type: "fitSelection" };

export const isTextEntryTarget = (target: EventTarget | null): boolean => {
  if (!(target instanceof Element)) return false;
  return target.matches("input, textarea, select, [contenteditable]")
    || target.closest("[contenteditable]") !== null;
};

export function keyboardCommandFor(
  event: KeyboardEvent,
  context: ShortcutContext,
): EditorShortcutCommand | undefined {
  if (event.isComposing || isTextEntryTarget(event.target)) return undefined;
  if (context.interactionActive && event.code !== "Escape") return undefined;
  if (
    (context.textEditing || context.shortcutHelpOpen)
    && event.code !== "Escape"
  ) {
    return undefined;
  }

  const definition = SHORTCUT_REGISTRY.find((entry) => entry.matches(event));
  if (!definition || definition.owner === "native") return undefined;
  return commandFromDefinition(definition);
}

function commandFromDefinition(
  definition: ShortcutDefinition,
): EditorShortcutCommand | undefined {
  if (definition.tool) {
    return { type: "selectTool", tool: definition.tool };
  }

  switch (definition.id) {
    case "edit-delete":
      return { type: "delete" };
    case "edit-duplicate":
      return { type: "duplicate" };
    case "edit-copy":
      return { type: "copy" };
    case "edit-paste":
      return { type: "paste" };
    case "edit-bring-forward":
      return { type: "bringForward" };
    case "edit-send-backward":
      return { type: "sendBackward" };
    case "edit-undo":
      return { type: "undo" };
    case "edit-redo":
      return { type: "redo" };
    case "edit-escape":
      return { type: "escape" };
    case "edit-shortcut-help":
      return { type: "openShortcutHelp" };
    case "view-zoom-100":
      return { type: "zoom100" };
    case "view-fit-image":
      return { type: "fitImage" };
    case "view-fit-selection":
      return { type: "fitSelection" };
    default:
      return undefined;
  }
}
