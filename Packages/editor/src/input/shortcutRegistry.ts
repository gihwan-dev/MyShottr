import type { EditorTool } from "../model/elements";

export type ShortcutOwner = "web" | "native";
export type ShortcutGroup =
  | "Tools"
  | "Edit and Selection"
  | "View and Navigation"
  | "Output";

export const SHORTCUT_GROUPS: readonly ShortcutGroup[] = [
  "Tools",
  "Edit and Selection",
  "View and Navigation",
  "Output",
];

export type ShortcutDefinition = {
  id: string;
  owner: ShortcutOwner;
  group: ShortcutGroup;
  label: string;
  displayKeys: readonly string[];
  tool?: EditorTool;
  matches(event: KeyboardEvent): boolean;
};

const hasNoModifiers = (event: KeyboardEvent): boolean =>
  !event.metaKey && !event.ctrlKey && !event.altKey && !event.shiftKey;

const plainCode = (code: string) => (event: KeyboardEvent): boolean =>
  event.code === code && hasNoModifiers(event);

const commandCode = (code: string, shiftKey = false) =>
  (event: KeyboardEvent): boolean =>
    event.code === code
    && event.metaKey
    && event.shiftKey === shiftKey
    && !event.ctrlKey
    && !event.altKey;

const shiftCode = (code: string) => (event: KeyboardEvent): boolean =>
  event.code === code
  && event.shiftKey
  && !event.metaKey
  && !event.ctrlKey
  && !event.altKey;

const toolShortcut = (
  tool: EditorTool,
  label: string,
  code: string,
  displayKey: string,
): ShortcutDefinition => ({
  id: `tool-${tool}`,
  owner: "web",
  group: "Tools",
  label,
  displayKeys: [displayKey],
  tool,
  matches: plainCode(code),
});

const helpOnly = (
  id: string,
  group: ShortcutGroup,
  label: string,
  displayKeys: readonly string[],
  matches: ShortcutDefinition["matches"] = () => false,
): ShortcutDefinition => ({
  id,
  owner: "web",
  group,
  label,
  displayKeys,
  matches,
});

const isArrowCode = (code: string): boolean =>
  code === "ArrowUp"
  || code === "ArrowDown"
  || code === "ArrowLeft"
  || code === "ArrowRight";

export const SHORTCUT_REGISTRY: readonly ShortcutDefinition[] = [
  toolShortcut("selection", "Selection", "KeyV", "V"),
  toolShortcut("rectangle", "Rectangle", "KeyR", "R"),
  toolShortcut("arrow", "Arrow", "KeyA", "A"),
  toolShortcut("line", "Line", "KeyL", "L"),
  toolShortcut("text", "Text", "KeyT", "T"),
  toolShortcut("freehand", "Freehand", "KeyP", "P"),
  toolShortcut("highlighter", "Highlighter", "KeyH", "H"),
  toolShortcut("blur", "Blur", "KeyB", "B"),
  toolShortcut("redaction", "Redaction", "KeyX", "X"),
  toolShortcut("numberMarker", "Number Marker", "KeyN", "N"),
  {
    id: "edit-undo",
    owner: "web",
    group: "Edit and Selection",
    label: "Undo",
    displayKeys: ["⌘", "Z"],
    matches: commandCode("KeyZ"),
  },
  {
    id: "edit-redo",
    owner: "web",
    group: "Edit and Selection",
    label: "Redo",
    displayKeys: ["⌘", "⇧", "Z"],
    matches: commandCode("KeyZ", true),
  },
  {
    id: "edit-duplicate",
    owner: "web",
    group: "Edit and Selection",
    label: "Duplicate",
    displayKeys: ["⌘", "D"],
    matches: commandCode("KeyD"),
  },
  {
    id: "edit-copy",
    owner: "web",
    group: "Edit and Selection",
    label: "Copy Elements",
    displayKeys: ["⌘", "C"],
    matches: commandCode("KeyC"),
  },
  {
    id: "edit-paste",
    owner: "web",
    group: "Edit and Selection",
    label: "Paste Elements",
    displayKeys: ["⌘", "V"],
    matches: commandCode("KeyV"),
  },
  {
    id: "edit-bring-forward",
    owner: "web",
    group: "Edit and Selection",
    label: "Bring Forward",
    displayKeys: ["⌘", "]"],
    matches: commandCode("BracketRight"),
  },
  {
    id: "edit-send-backward",
    owner: "web",
    group: "Edit and Selection",
    label: "Send Backward",
    displayKeys: ["⌘", "["],
    matches: commandCode("BracketLeft"),
  },
  {
    id: "edit-delete",
    owner: "web",
    group: "Edit and Selection",
    label: "Delete",
    displayKeys: ["Delete", "Backspace"],
    matches: (event) =>
      (event.code === "Delete" || event.code === "Backspace")
      && hasNoModifiers(event),
  },
  helpOnly(
    "edit-nudge",
    "Edit and Selection",
    "Move Selection 1 px",
    ["Arrow keys"],
    (event) => isArrowCode(event.code) && hasNoModifiers(event),
  ),
  helpOnly(
    "edit-nudge-large",
    "Edit and Selection",
    "Move Selection 10 px",
    ["⇧", "Arrow keys"],
    (event) =>
      isArrowCode(event.code)
      && event.shiftKey
      && !event.metaKey
      && !event.ctrlKey
      && !event.altKey,
  ),
  helpOnly(
    "edit-duplicate-drag",
    "Edit and Selection",
    "Duplicate and Drag",
    ["⌥", "Drag"],
  ),
  helpOnly(
    "edit-toggle-selection",
    "Edit and Selection",
    "Toggle Selection",
    ["⇧", "Click"],
  ),
  helpOnly(
    "edit-selected-text",
    "Edit and Selection",
    "Edit Selected Text",
    ["Enter"],
    plainCode("Enter"),
  ),
  {
    id: "edit-escape",
    owner: "web",
    group: "Edit and Selection",
    label: "Cancel or Clear",
    displayKeys: ["Escape"],
    matches: plainCode("Escape"),
  },
  {
    id: "edit-shortcut-help",
    owner: "web",
    group: "Edit and Selection",
    label: "Shortcut Help",
    displayKeys: ["?"],
    matches: shiftCode("Slash"),
  },
  helpOnly(
    "view-pan",
    "View and Navigation",
    "Pan",
    ["Space", "Drag"],
    plainCode("Space"),
  ),
  helpOnly(
    "view-middle-pan",
    "View and Navigation",
    "Pan with Middle Button",
    ["Middle", "Drag"],
  ),
  helpOnly(
    "view-scroll-pan",
    "View and Navigation",
    "Pan View",
    ["Scroll"],
  ),
  helpOnly(
    "view-pointer-zoom",
    "View and Navigation",
    "Zoom Around Pointer",
    ["Pinch", "⌘", "Scroll"],
  ),
  {
    id: "view-zoom-100",
    owner: "web",
    group: "View and Navigation",
    label: "100%",
    displayKeys: ["⌘", "0"],
    matches: commandCode("Digit0"),
  },
  {
    id: "view-fit-image",
    owner: "web",
    group: "View and Navigation",
    label: "Fit Image",
    displayKeys: ["⇧", "1"],
    matches: shiftCode("Digit1"),
  },
  {
    id: "view-fit-selection",
    owner: "web",
    group: "View and Navigation",
    label: "Fit Selection",
    displayKeys: ["⇧", "2"],
    matches: shiftCode("Digit2"),
  },
  {
    id: "output-copy-image",
    owner: "native",
    group: "Output",
    label: "Copy Image",
    displayKeys: ["⌘", "⇧", "C"],
    matches: commandCode("KeyC", true),
  },
  {
    id: "output-save-project",
    owner: "native",
    group: "Output",
    label: "Save Project",
    displayKeys: ["⌘", "S"],
    matches: commandCode("KeyS"),
  },
  {
    id: "output-export-png",
    owner: "native",
    group: "Output",
    label: "Export PNG",
    displayKeys: ["⌘", "E"],
    matches: commandCode("KeyE"),
  },
];

export const TOOL_SHORTCUTS = SHORTCUT_REGISTRY.filter(
  (entry): entry is ShortcutDefinition & { tool: EditorTool } =>
    entry.group === "Tools" && entry.tool !== undefined,
);
