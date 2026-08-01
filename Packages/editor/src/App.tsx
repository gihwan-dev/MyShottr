import {
  forwardRef,
  useCallback,
  useEffect,
  useImperativeHandle,
  useRef,
  useState,
  useSyncExternalStore,
} from "react";
import { EditorCanvas, type EditorCanvasHandle } from "./canvas/EditorCanvas";
import {
  clearSelection,
  replaceSelection,
  toggleSelection,
} from "./canvas/SelectionController";
import { createDuplicateElements } from "./interaction/duplication";
import { cursorForTool } from "./canvas/tools/ToolController";
import { ContextRail, type ContextRailIntent } from "./components/ContextRail";
import {
  allowedValues,
  deriveContextRailModel,
  type RailPropertyKey,
  type RailPropertyValueByKey,
} from "./components/contextRailModel";
import { FloatingToolPalette } from "./components/FloatingToolPalette";
import { EditorFeedback, useEditorFeedback } from "./components/EditorFeedback";
import { ShortcutHelpDialog } from "./components/ShortcutHelpDialog";
import { TextEditorOverlay } from "./components/TextEditorOverlay";
import {
  textEditCommand,
  type TextEditResult,
  type TextEditSession,
} from "./interaction/textEditSession";
import { ZoomControls } from "./components/ZoomControls";
import {
  EditorWorkspace,
  type EditorWorkspaceHandle,
} from "./components/EditorWorkspace";
import { useNativeBridge } from "./bridge/nativeBridge";
import { renderDocumentToBlob } from "./export/renderDocumentToBlob";
import { sendComposite } from "./export/sendComposite";
import {
  createHistoryStore,
  type HistoryAvailability,
  type HistoryStore,
} from "./model/history";
import { applyRailProperty, findElement } from "./model/reducer";
import type { EditorCommand, EditorDefaults, EditorDocument, EditorElement, EditorTool, TextElement } from "./model/elements";
import { KONVA_DEFAULT_FONT_FAMILY, TEXT_LINE_HEIGHT } from "./canvas/renderingConstants";
import { isTextEntryTarget, keyboardCommandFor } from "./input/ShortcutRouter";
import { moveElementsWithinBounds, unionBounds } from "./interaction/selectionGeometry";
import "./styles.css";

export type EditorAppProps = {
  initialDocument: EditorDocument;
  initialTool: EditorTool;
  sourceImageURL: string;
  onChange: (document: EditorDocument) => void;
  onHistoryStateChange?: (state: HistoryAvailability) => void;
  onPreferencesChange: (tool: EditorTool, defaults: EditorDefaults) => void;
};

export type EditorAppHandle = {
  getDocument(): EditorDocument;
  performHistoryAction(action: "undo" | "redo"): boolean;
};

export const EditorApp = forwardRef<EditorAppHandle, EditorAppProps>(function EditorApp({ initialDocument, initialTool, sourceImageURL, onChange, onHistoryStateChange, onPreferencesChange }, ref) {
  const historyRef = useRef<HistoryStore | undefined>(undefined);
  if (!historyRef.current) historyRef.current = createHistoryStore(initialDocument);
  const history = historyRef.current;
  const viewportRef = useRef<EditorWorkspaceHandle>(null);
  const canvasRef = useRef<EditorCanvasHandle>(null);
  const copiedElements = useRef<EditorElement[]>([]);
  const document = useSyncExternalStore(
    history.subscribe,
    history.getSnapshot,
    history.getSnapshot,
  );
  const [selectedIds, setSelectedIds] = useState<string[]>([]);
  const [tool, setTool] = useState<EditorTool>(initialTool);
  const [textEditSession, setTextEditSession] = useState<TextEditSession>();
  const [shortcutHelpOpen, setShortcutHelpOpen] = useState(false);
  const [canvasInteractionActive, setCanvasInteractionActive] = useState(false);
  const [selectionOpacityPreview, setSelectionOpacityPreview] = useState<{
    value: RailPropertyValueByKey["opacity"];
  }>();
  const [locks, setLocks] = useState({ slider: false });
  const [nudgeSession, setNudgeSession] = useState<NudgeSession>();
  const textLocked = textEditSession !== undefined;
  const lastHistoryState = useRef<HistoryAvailability | undefined>(undefined);
  const historyLocksRef = useRef<HistoryLocks>({
    canvasInteraction: false,
    nudge: false,
    text: false,
    slider: false,
    shortcutHelp: false,
    transaction: false,
  });
  historyLocksRef.current = {
    canvasInteraction: canvasInteractionActive,
    nudge: nudgeSession !== undefined,
    text: textLocked,
    slider: locks.slider,
    shortcutHelp: shortcutHelpOpen,
    transaction: history.isTransactionActive,
  };

  const publishHistoryState = useCallback(() => {
    if (!onHistoryStateChange) return;
    const currentLocks = {
      ...historyLocksRef.current,
      transaction: history.isTransactionActive,
    };
    const next: HistoryAvailability = isHistoryLocked(currentLocks)
      ? { canUndo: false, canRedo: false }
      : { canUndo: history.canUndo, canRedo: history.canRedo };
    if (
      lastHistoryState.current?.canUndo === next.canUndo
      && lastHistoryState.current?.canRedo === next.canRedo
    ) return;
    lastHistoryState.current = next;
    onHistoryStateChange(next);
  }, [history, onHistoryStateChange]);

  const transitionHistoryLock = useCallback((key: Exclude<keyof HistoryLocks, "transaction">, active: boolean) => {
    historyLocksRef.current = {
      ...historyLocksRef.current,
      [key]: active,
      transaction: history.isTransactionActive,
    };
    publishHistoryState();
  }, [history, publishHistoryState]);
  const updateNudgeSession = useCallback((next: NudgeSession | undefined) => {
    transitionHistoryLock("nudge", next !== undefined);
    setNudgeSession(next);
  }, [transitionHistoryLock]);
  const updateTextEditSession = useCallback((next: TextEditSession | undefined) => {
    transitionHistoryLock("text", next !== undefined);
    setTextEditSession(next);
  }, [transitionHistoryLock]);
  const updateSliderLock = useCallback((active: boolean) => {
    transitionHistoryLock("slider", active);
    setLocks((current) => ({ ...current, slider: active }));
  }, [transitionHistoryLock]);
  const updateShortcutHelp = useCallback((active: boolean) => {
    transitionHistoryLock("shortcutHelp", active);
    setShortcutHelpOpen(active);
  }, [transitionHistoryLock]);
  const updateCanvasInteraction = useCallback((active: boolean) => {
    transitionHistoryLock("canvasInteraction", active);
    setCanvasInteractionActive(active);
  }, [transitionHistoryLock]);

  const publishSceneChange = useCallback(() => {
    onChange(history.getSnapshot());
  }, [history, onChange]);

  const dispatch = useCallback((command: EditorCommand) => {
    updateNudgeSession(undefined);
    history.dispatch(command);
    publishSceneChange();
    publishHistoryState();
  }, [history, publishHistoryState, publishSceneChange, updateNudgeSession]);
  const updateDefaults = useCallback((nextDefaults: EditorDefaults) => {
    updateNudgeSession(undefined);
    history.setDefaults(nextDefaults);
    onPreferencesChange(tool, history.getSnapshot().defaults);
    publishHistoryState();
  }, [history, onPreferencesChange, publishHistoryState, tool, updateNudgeSession]);
  const select = useCallback((id: string | undefined, toggle = false) => {
    updateNudgeSession(undefined);
    setSelectionOpacityPreview(undefined);
    updateSliderLock(false);
    setSelectedIds((current) => {
      if (!id) return [...clearSelection()];
      return [...(toggle
        ? toggleSelection(current, id)
        : replaceSelection(id))];
    });
  }, [updateNudgeSession, updateSliderLock]);
  const selectTool = useCallback((nextTool: EditorTool) => {
    if (textLocked) return;
    updateNudgeSession(undefined);
    setTool(nextTool);
    if (nextTool !== "selection") select(undefined);
    onPreferencesChange(nextTool, history.getSnapshot().defaults);
  }, [history, onPreferencesChange, select, textLocked, updateNudgeSession]);
  const duplicateSelection = useCallback(() => {
    if (selectedIds.length === 0) return;
    const current = history.document;
    const sources = selectedIds.map((id) => findElement(current, id));
    const elements = createDuplicateElements(current, sources);
    dispatch({ type: "createMany", elements });
    setSelectedIds(elements.map((element) => element.id));
  }, [dispatch, history, selectedIds]);
  const copySelection = useCallback(() => {
    if (selectedIds.length === 0) return;
    const current = history.document;
    copiedElements.current = selectedIds.map((id) => structuredClone(findElement(current, id)));
  }, [history, selectedIds]);
  const pasteSelection = useCallback(() => {
    if (copiedElements.current.length === 0) return;
    const elements = createDuplicateElements(history.document, copiedElements.current);
    dispatch({ type: "createMany", elements });
    setSelectionOpacityPreview(undefined);
    updateSliderLock(false);
    setSelectedIds(elements.map((element) => element.id));
  }, [dispatch, history, updateSliderLock]);
  const reorderSelection = useCallback((direction: "forward" | "backward") => {
    if (selectedIds.length === 0) return;
    dispatch({ type: "reorder", ids: selectedIds, direction });
  }, [dispatch, selectedIds]);
  const beginTextEdit = useCallback((id: string) => {
    if (selectedIds.length !== 1 || selectedIds[0] !== id) return;
    const element = findElement(history.document, id);
    if (element.type !== "text") {
      throw new Error(`Cannot edit non-text element: ${id}`);
    }
    const session: TextEditSession = {
      kind: "existing",
      element: structuredClone(element),
      initialText: element.text,
    };
    updateNudgeSession(undefined);
    updateTextEditSession(session);
  }, [history, selectedIds, updateNudgeSession, updateTextEditSession]);
  const beginNewText = useCallback((point: { x: number; y: number }, defaults: EditorDefaults) => {
    const session: TextEditSession = {
      kind: "new",
      point: { ...point },
      defaults: structuredClone(defaults),
      initialText: "",
    };
    updateNudgeSession(undefined);
    updateTextEditSession(session);
  }, [updateNudgeSession, updateTextEditSession]);
  const finishTextEdit = useCallback((session: TextEditSession, result: TextEditResult) => {
    updateTextEditSession(undefined);
    const command = textEditCommand(
      history.document,
      session,
      result,
      measureTextBounds,
    );
    if (!command) return;

    dispatch(command);
    if (command.type === "delete") {
      setSelectedIds((current) => current.filter(
        (id) => !command.ids.includes(id),
      ));
    }
  }, [dispatch, history, updateTextEditSession]);
  const selectedElements = selectedIds.map((id) => findElement(document, id));
  const scenePreviewElements = nudgeSession
    ? nudgeSession.previewElements
    : selectionOpacityPreview
      ? applyRailProperty(selectedElements, "opacity", selectionOpacityPreview.value)
      : undefined;
  const previewById = scenePreviewElements
    ? new Map(scenePreviewElements.map((element) => [element.id, element]))
    : new Map<string, EditorElement>();
  const renderedDocument = scenePreviewElements
    ? {
        ...document,
        elements: document.elements.map((element) => previewById.get(element.id) ?? element),
      }
    : document;
  const contextRailModel = deriveContextRailModel({
    tool,
    document: renderedDocument,
    selectedIds,
  });
  const performHistoryAction = useCallback((action: "undo" | "redo"): boolean => {
    const currentLocks = {
      ...historyLocksRef.current,
      transaction: history.isTransactionActive,
    };
    if (isHistoryLocked(currentLocks)) {
      publishHistoryState();
      return false;
    }
    const changed = action === "undo" ? history.undo() : history.redo();
    if (!changed) {
      publishHistoryState();
      return false;
    }
    setSelectedIds([]);
    publishSceneChange();
    publishHistoryState();
    return true;
  }, [history, publishHistoryState, publishSceneChange]);

  useImperativeHandle(ref, () => ({
    getDocument: history.getSnapshot,
    performHistoryAction,
  }), [history, performHistoryAction]);

  useEffect(() => {
    publishHistoryState();
  }, [
    canvasInteractionActive,
    locks.slider,
    nudgeSession,
    publishHistoryState,
    shortcutHelpOpen,
    textLocked,
  ]);

  useEffect(() => {
    const onKeyDown = (event: KeyboardEvent) => {
      if (isNudgeCode(event.code)) {
        if (
          event.isComposing
          || isTextEntryTarget(event.target)
          || event.metaKey
          || event.ctrlKey
          || event.altKey
        ) return;
        const canStartNudge = tool === "selection"
          && selectedIds.length > 0
          && !history.isTransactionActive
          && !locks.slider
          && !textLocked
          && !canvasInteractionActive
          && !shortcutHelpOpen;
        if (!nudgeSession && !canStartNudge) return;
        event.preventDefault();
        const startingElements = nudgeSession
          ? nudgeSession.startingElements
          : selectedIds.map((id) => structuredClone(findElement(history.document, id)));
        const previewElements = moveElementsWithinBounds(
          nudgeSession ? nudgeSession.previewElements : startingElements,
          nudgeDelta(event.code, event.shiftKey),
          {
            sourceWidth: history.document.sourcePixelWidth,
            sourceHeight: history.document.sourcePixelHeight,
          },
        );
        const heldCodes = nudgeSession
          ? new Set(nudgeSession.heldCodes)
          : new Set<string>();
        heldCodes.add(event.code);
        updateNudgeSession({ startingElements, previewElements, heldCodes });
        return;
      }
      if (
        event.code === "Enter"
        && !event.isComposing
        && !isTextEntryTarget(event.target)
        && !event.metaKey
        && !event.ctrlKey
        && !event.altKey
        && !event.shiftKey
        && tool === "selection"
        && selectedIds.length === 1
        && !history.isTransactionActive
        && !locks.slider
        && !textLocked
        && nudgeSession === undefined
        && !canvasInteractionActive
        && !shortcutHelpOpen
      ) {
        const selected = findElement(history.document, selectedIds[0]);
        if (selected.type === "text") {
          event.preventDefault();
          beginTextEdit(selected.id);
        }
        return;
      }
      const commandContext = {
        interactionActive: history.isTransactionActive
          || locks.slider
          || textLocked
          || nudgeSession !== undefined
          || canvasInteractionActive,
        shortcutHelpOpen,
        textEditing: textLocked,
      };
      const routedCommand = keyboardCommandFor(event, commandContext);
      const otherwiseSuppressedCommand = routedCommand
        ? undefined
        : keyboardCommandFor(event, {
            interactionActive: false,
            shortcutHelpOpen: false,
            textEditing: false,
          });
      const command = routedCommand ?? (
        otherwiseSuppressedCommand?.type === "undo"
          || otherwiseSuppressedCommand?.type === "redo"
          ? otherwiseSuppressedCommand
          : undefined
      );
      if (!command) return;
      event.preventDefault();
      if (command.type === "escape") {
        if (canvasRef.current?.cancelInteraction()) {
          return;
        } else if (nudgeSession) {
          updateNudgeSession(undefined);
        } else if (shortcutHelpOpen) {
          updateShortcutHelp(false);
        } else if (textEditSession) {
          finishTextEdit(textEditSession, { type: "cancel" });
        } else if (locks.slider) {
          setSelectionOpacityPreview(undefined);
          updateSliderLock(false);
        } else if (history.isTransactionActive) {
          if (history.cancelTransaction()) publishSceneChange();
          publishHistoryState();
        } else if (tool !== "selection") {
          selectTool("selection");
        } else {
          select(undefined);
        }
        return;
      }
      if (command.type === "openShortcutHelp") {
        updateShortcutHelp(true);
        return;
      }
      if (command.type === "zoom100") {
        viewportRef.current?.applyIntent(command);
        return;
      }
      if (command.type === "fitImage" || command.type === "fitSelection") {
        viewportRef.current?.applyIntent(command);
        return;
      }
      if (command.type === "delete") {
        if (selectedIds.length > 0) {
          dispatch({ type: "delete", ids: selectedIds });
          select(undefined);
        }
        return;
      }
      if (command.type === "duplicate") {
        duplicateSelection();
        return;
      }
      if (command.type === "copy") {
        copySelection();
        return;
      }
      if (command.type === "paste") {
        pasteSelection();
        return;
      }
      if (command.type === "bringForward" || command.type === "sendBackward") {
        reorderSelection(command.type === "bringForward" ? "forward" : "backward");
        return;
      }
      if (command.type === "undo" || command.type === "redo") {
        performHistoryAction(command.type);
        return;
      }
      selectTool(command.tool);
    };
    const onKeyUp = (event: KeyboardEvent) => {
      if (!isNudgeCode(event.code) || !nudgeSession?.heldCodes.has(event.code)) {
        return;
      }
      event.preventDefault();
      const heldCodes = new Set(nudgeSession.heldCodes);
      heldCodes.delete(event.code);
      if (heldCodes.size > 0) {
        updateNudgeSession({ ...nudgeSession, heldCodes });
        return;
      }
      const finalElements = nudgeSession.previewElements;
      const changed = finalElements.some((element, index) => {
        const starting = nudgeSession.startingElements[index];
        return !starting || element.x !== starting.x || element.y !== starting.y;
      });
      updateNudgeSession(undefined);
      if (changed) {
        dispatch({ type: "updateMany", elements: [...finalElements] });
      }
    };
    window.addEventListener("keydown", onKeyDown);
    window.addEventListener("keyup", onKeyUp);
    return () => {
      window.removeEventListener("keydown", onKeyDown);
      window.removeEventListener("keyup", onKeyUp);
    };
  }, [beginTextEdit, canvasInteractionActive, copySelection, dispatch, duplicateSelection, finishTextEdit, history, locks.slider, nudgeSession, pasteSelection, performHistoryAction, publishHistoryState, publishSceneChange, reorderSelection, select, selectTool, selectedIds, shortcutHelpOpen, textEditSession, textLocked, tool, updateNudgeSession, updateShortcutHelp, updateSliderLock]);

  useEffect(() => {
    const cancelNudge = () => updateNudgeSession(undefined);
    window.addEventListener("blur", cancelNudge);
    return () => window.removeEventListener("blur", cancelNudge);
  }, [updateNudgeSession]);

  const handleContextRailIntent = useCallback((intent: ContextRailIntent) => {
    if (nudgeSession || textLocked) return;
    switch (intent.type) {
      case "setDefaultProperty":
        updateDefaults(applyRailDefault(document.defaults, tool, intent.property, intent.value));
        return;
      case "setSelectionProperty": {
        const selected = selectedIds.map((id) => findElement(history.document, id));
        dispatch({
          type: "updateMany",
          elements: applyRailProperty(selected, intent.property, intent.value),
        });
        return;
      }
      case "previewSelectionOpacity": {
        const selected = selectedIds.map((id) => findElement(history.document, id));
        applyRailProperty(selected, "opacity", intent.value);
        setSelectionOpacityPreview({ value: intent.value });
        updateSliderLock(true);
        return;
      }
      case "commitSelectionOpacity": {
        const selected = selectedIds.map((id) => findElement(history.document, id));
        const elements = applyRailProperty(selected, "opacity", intent.value);
        setSelectionOpacityPreview(undefined);
        updateSliderLock(false);
        dispatch({ type: "updateMany", elements });
        return;
      }
      case "cancelSelectionOpacity":
        setSelectionOpacityPreview(undefined);
        updateSliderLock(false);
        return;
      case "bringForward":
        reorderSelection("forward");
        return;
      case "sendBackward":
        reorderSelection("backward");
        return;
      case "duplicate":
        duplicateSelection();
        return;
      case "delete":
        if (selectedIds.length === 0) return;
        dispatch({ type: "delete", ids: selectedIds });
        select(undefined);
        return;
    }
  }, [dispatch, document.defaults, duplicateSelection, history, nudgeSession, reorderSelection, select, selectedIds, textLocked, tool, updateDefaults, updateSliderLock]);

  return (
    <main
      className="editor-app"
      aria-label="MyShottr editor"
      style={{ cursor: cursorForTool(tool) }}
    >
      <EditorWorkspace
        ref={viewportRef}
        source={{
          width: document.sourcePixelWidth,
          height: document.sourcePixelHeight,
        }}
        railVisible={contextRailModel.kind !== "hidden"}
        selectionBounds={unionBounds(selectedElements)}
      >
        {({ viewport, spacePanReady, onWheel, panBy, toSourcePoint }) => (
          <>
            <EditorCanvas
              ref={canvasRef}
              document={renderedDocument}
              sourceImageURL={sourceImageURL}
              tool={tool}
              viewport={viewport}
              spacePanReady={spacePanReady}
              interactionLocked={nudgeSession !== undefined || textLocked}
              selectedIds={selectedIds}
              onSelect={select}
              onEditText={beginTextEdit}
              onBeginNewText={beginNewText}
              onCommand={dispatch}
              onBeginTransaction={(label) => {
                history.beginTransaction(label);
                publishHistoryState();
              }}
              onCommitTransaction={() => {
                history.commitTransaction();
                publishHistoryState();
              }}
              onCancelTransaction={() => {
                if (history.cancelTransaction()) {
                  publishSceneChange();
                }
                publishHistoryState();
              }}
              onViewportWheel={onWheel}
              onViewportPanBy={panBy}
              onInteractionActiveChange={updateCanvasInteraction}
              toSourcePoint={toSourcePoint}
              textEditorOverlay={textEditSession && <TextEditorOverlay
                key={textEditSession.kind === "new"
                  ? `new:${textEditSession.point.x}:${textEditSession.point.y}`
                  : `existing:${textEditSession.element.id}`}
                session={textEditSession}
                zoom={viewport.zoom}
                pan={viewport.pan}
                onResult={(result) => finishTextEdit(textEditSession, result)}
              />}
            />
            <ZoomControls
              zoom={viewport.zoom}
              onIntent={(intent) => viewportRef.current?.applyIntent(intent)}
            />
          </>
        )}
      </EditorWorkspace>
      <FloatingToolPalette
        tool={tool}
        interactionLocked={textLocked}
        onSelect={selectTool}
      />
      <ContextRail model={contextRailModel} onIntent={handleContextRailIntent} />
      {shortcutHelpOpen && (
        <ShortcutHelpDialog onClose={() => updateShortcutHelp(false)} />
      )}
    </main>
  );
});

type NudgeSession = {
  startingElements: readonly EditorElement[];
  previewElements: readonly EditorElement[];
  heldCodes: Set<string>;
};

type HistoryLocks = {
  canvasInteraction: boolean;
  nudge: boolean;
  text: boolean;
  slider: boolean;
  shortcutHelp: boolean;
  transaction: boolean;
};

function isHistoryLocked(locks: HistoryLocks): boolean {
  return locks.canvasInteraction
    || locks.nudge
    || locks.text
    || locks.slider
    || locks.shortcutHelp
    || locks.transaction;
}

type NudgeCode = "ArrowLeft" | "ArrowRight" | "ArrowUp" | "ArrowDown";

function isNudgeCode(code: string): code is NudgeCode {
  return code === "ArrowLeft"
    || code === "ArrowRight"
    || code === "ArrowUp"
    || code === "ArrowDown";
}

function nudgeDelta(code: NudgeCode, shiftKey: boolean) {
  const step = shiftKey ? 10 : 1;
  switch (code) {
    case "ArrowLeft":
      return { x: -step, y: 0 };
    case "ArrowRight":
      return { x: step, y: 0 };
    case "ArrowUp":
      return { x: 0, y: -step };
    case "ArrowDown":
      return { x: 0, y: step };
  }
}

function applyRailDefault<K extends RailPropertyKey>(
  defaults: EditorDefaults,
  tool: Exclude<EditorTool, "selection"> | EditorTool,
  property: K,
  value: RailPropertyValueByKey[K],
): EditorDefaults {
  if (tool === "selection" || !allowedValues(tool, property).some((allowed) => Object.is(allowed, value))) {
    throw new Error(`${tool} does not allow ${String(value)} for ${property}`);
  }
  switch (property) {
    case "color":
      return { ...defaults, color: value as RailPropertyValueByKey["color"] };
    case "fillColor":
      if (tool !== "rectangle") throw new Error(`${tool} does not support fillColor`);
      return { ...defaults, rectangleFillColor: value as RailPropertyValueByKey["fillColor"] };
    case "strokeWidth":
      return { ...defaults, strokeWidth: value as RailPropertyValueByKey["strokeWidth"] };
    case "roughness":
      return { ...defaults, roughness: value as RailPropertyValueByKey["roughness"] };
    case "textSize":
      return { ...defaults, textSize: value as RailPropertyValueByKey["textSize"] };
    case "opacity":
      return tool === "highlighter"
        ? { ...defaults, highlighterOpacity: value as EditorDefaults["highlighterOpacity"] }
        : { ...defaults, opacity: value as EditorDefaults["opacity"] };
  }
}

function measureTextBounds(text: string, fontSize: TextElement["fontSize"]): Pick<TextElement, "width" | "height"> {
  const canvas = document.createElement("canvas");
  const context = canvas.getContext("2d");
  if (!context) {
    throw new Error("Text measurement context is unavailable");
  }
  context.font = `${fontSize}px ${KONVA_DEFAULT_FONT_FAMILY}`;
  const lines = text.split("\n");
  return {
    width: Math.max(1, ...lines.map((line) => Math.ceil(context.measureText(line).width))),
    height: Math.ceil(lines.length * fontSize * TEXT_LINE_HEIGHT),
  };
}

export function App() {
  const bridge = useNativeBridge();
  const editorRef = useRef<EditorAppHandle>(null);
  const { state: feedbackState, receive: receiveOperationStatus } = useEditorFeedback();
  const [loadedDocument, setLoadedDocument] = useState<LoadedDocument>();
  const loadedDocumentRef = useRef<LoadedDocumentIdentity | undefined>(undefined);
  const acceptedLoadSequence = useRef(0);
  const latestLoadRequestSequence = useRef(0);

  useEffect(() => {
    const acceptLoad = async (message: Extract<Parameters<typeof bridge.subscribe>[0] extends (message: infer T) => void ? T : never, { type: "loadDocument" }>) => {
      latestLoadRequestSequence.current += 1;
      const loadRequestSequence = latestLoadRequestSequence.current;
      const { annotationDocument, sourceImageURL, initialTool } = message.payload;
      try {
        const dimensions = await sourceDimensions(sourceImageURL);
        if (loadRequestSequence !== latestLoadRequestSequence.current) return;
        if (dimensions.width !== annotationDocument.sourcePixelWidth || dimensions.height !== annotationDocument.sourcePixelHeight) {
          throw new Error("Source image dimensions do not match the document");
        }
      } catch (error) {
        if (loadRequestSequence !== latestLoadRequestSequence.current) return;
        await bridge.sendCorrelated(message.requestId, "bridgeError", {
          code: "INVALID_DOCUMENT",
          message: error instanceof Error ? error.message : "Source image could not be loaded",
        });
        return;
      }
      acceptedLoadSequence.current += 1;
      const nextDocument = {
        initialDocument: annotationDocument,
        sourceImageURL,
        initialTool,
        loadInstanceId: acceptedLoadSequence.current,
      };
      editorRef.current = null;
      loadedDocumentRef.current = {
        sourceImageURL,
        loadInstanceId: nextDocument.loadInstanceId,
      };
      setLoadedDocument(nextDocument);
      await bridge.sendCorrelated(message.requestId, "annotationSnapshot", { document: annotationDocument });
    };
    const receiveAnnotationSnapshotRequest = (event: Event) => {
      if (!(event instanceof CustomEvent) || typeof event.detail?.requestId !== "string") return;
      const currentDocument = editorRef.current?.getDocument();
      if (!currentDocument) {
        void bridge.sendCorrelated(event.detail.requestId, "bridgeError", {
          code: "INVALID_DOCUMENT",
          message: "No editor document is loaded",
        });
        return;
      }
      void bridge.sendCorrelated(event.detail.requestId, "annotationSnapshot", { document: currentDocument });
    };
    void bridge.send("editorReady", {});
    const unsubscribe = bridge.subscribe((message) => {
      if (message.type === "operationStatus") {
        receiveOperationStatus(message);
        return;
      }
      if (message.type === "loadDocument") {
        void acceptLoad(message);
        return;
      }
      if (message.type === "performHistoryAction") {
        editorRef.current?.performHistoryAction(message.payload.action);
        return;
      }
      if (message.type === "requestComposite") {
        if (!loadedDocumentRef.current || !editorRef.current) {
          void bridge.sendCorrelated(message.requestId, "bridgeError", {
            code: "RENDER_FAILED",
            message: "No editor document is loaded",
          });
          return;
        }
        const loaded = loadedDocumentRef.current;
        const currentDocument = editorRef.current.getDocument();
        void renderDocumentToBlob(currentDocument, loaded.sourceImageURL)
          .then((blob) => sendComposite({ requestId: message.requestId, blob, sendCorrelated: bridge.sendCorrelated }))
          .catch((error: unknown) => bridge.sendCorrelated(message.requestId, "bridgeError", {
            code: "RENDER_FAILED",
            message: error instanceof Error ? error.message : "Unable to render composite PNG",
          }));
        return;
      }
    });
    window.addEventListener("myshottr:request-annotation-snapshot", receiveAnnotationSnapshotRequest);
    return () => {
      latestLoadRequestSequence.current += 1;
      unsubscribe();
      window.removeEventListener("myshottr:request-annotation-snapshot", receiveAnnotationSnapshotRequest);
    };
  }, [bridge, receiveOperationStatus]);

  return (
    <>
      {loadedDocument
        ? <EditorApp
            ref={editorRef}
            key={loadedDocument.loadInstanceId}
            initialDocument={loadedDocument.initialDocument}
            initialTool={loadedDocument.initialTool}
            sourceImageURL={loadedDocument.sourceImageURL}
            onChange={(document) => {
              const loaded = loadedDocumentRef.current;
              if (!loaded || loaded.loadInstanceId !== loadedDocument.loadInstanceId) return;
              if (editorRef.current?.getDocument() !== document) return;
              void bridge.send("documentChanged", {});
            }}
            onHistoryStateChange={(state) => {
              const loaded = loadedDocumentRef.current;
              if (!loaded || loaded.loadInstanceId !== loadedDocument.loadInstanceId) return;
              void bridge.send("historyStateChanged", state);
            }}
            onPreferencesChange={(tool, defaults) => {
              const loaded = loadedDocumentRef.current;
              if (!loaded || loaded.loadInstanceId !== loadedDocument.loadInstanceId) return;
              void bridge.send("editorPreferencesChanged", { tool, defaults });
            }}
          />
        : <main aria-label="MyShottr editor">Waiting for document</main>}
      <EditorFeedback state={feedbackState} />
    </>
  );
}

type LoadedDocument = {
  initialDocument: EditorDocument;
  sourceImageURL: string;
  initialTool: EditorTool;
  loadInstanceId: number;
};

type LoadedDocumentIdentity = Pick<LoadedDocument, "sourceImageURL" | "loadInstanceId">;

function sourceDimensions(sourceImageURL: string): Promise<{ width: number; height: number }> {
  return new Promise((resolve, reject) => {
    const image = new Image();
    image.onload = () => resolve({ width: image.naturalWidth, height: image.naturalHeight });
    image.onerror = () => reject(new Error("Source image could not be loaded"));
    image.src = sourceImageURL;
  });
}
