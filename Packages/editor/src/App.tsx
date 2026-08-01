import {
  useCallback,
  useEffect,
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
import { ShortcutHelpDialog } from "./components/ShortcutHelpDialog";
import { TextEditorOverlay } from "./components/TextEditorOverlay";
import {
  textEditCommand,
  type TextEditResult,
  type TextEditSession,
} from "./components/textEditSession";
import { ZoomControls } from "./components/ZoomControls";
import {
  EditorWorkspace,
  type EditorWorkspaceHandle,
} from "./components/EditorWorkspace";
import { useNativeBridge } from "./bridge/nativeBridge";
import { renderDocumentToBlob } from "./export/renderDocumentToBlob";
import { sendComposite } from "./export/sendComposite";
import { createHistoryStore, type HistoryStore } from "./model/history";
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
  onPreferencesChange: (tool: EditorTool, defaults: EditorDefaults) => void;
};

export function EditorApp({ initialDocument, initialTool, sourceImageURL, onChange, onPreferencesChange }: EditorAppProps) {
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

  const publishSceneChange = useCallback(() => {
    onChange(history.getSnapshot());
  }, [history, onChange]);

  const dispatch = useCallback((command: EditorCommand) => {
    setNudgeSession(undefined);
    history.dispatch(command);
    publishSceneChange();
  }, [history, publishSceneChange]);
  const updateDefaults = useCallback((nextDefaults: EditorDefaults) => {
    setNudgeSession(undefined);
    history.setDefaults(nextDefaults);
    onPreferencesChange(tool, history.getSnapshot().defaults);
  }, [history, onPreferencesChange, tool]);
  const select = useCallback((id: string | undefined, toggle = false) => {
    setNudgeSession(undefined);
    setSelectionOpacityPreview(undefined);
    setLocks((current) => ({ ...current, slider: false }));
    setSelectedIds((current) => {
      if (!id) return [...clearSelection()];
      return [...(toggle
        ? toggleSelection(current, id)
        : replaceSelection(id))];
    });
  }, []);
  const selectTool = useCallback((nextTool: EditorTool) => {
    if (textLocked) return;
    setNudgeSession(undefined);
    setTool(nextTool);
    if (nextTool !== "selection") select(undefined);
    onPreferencesChange(nextTool, history.getSnapshot().defaults);
  }, [history, onPreferencesChange, select, textLocked]);
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
    setLocks((current) => ({ ...current, slider: false }));
    setSelectedIds(elements.map((element) => element.id));
  }, [dispatch, history]);
  const reorderSelection = useCallback((direction: "forward" | "backward") => {
    if (selectedIds.length === 0) return;
    dispatch({ type: "reorder", ids: selectedIds, direction });
  }, [dispatch, selectedIds]);
  const beginTextEdit = useCallback((id: string) => {
    const element = findElement(history.document, id);
    if (element.type !== "text") {
      throw new Error(`Cannot edit non-text element: ${id}`);
    }
    const session: TextEditSession = {
      kind: "existing",
      element: structuredClone(element),
      initialText: element.text,
    };
    setNudgeSession(undefined);
    setTextEditSession(session);
  }, [history]);
  const beginNewText = useCallback((point: { x: number; y: number }, defaults: EditorDefaults) => {
    const session: TextEditSession = {
      kind: "new",
      point: { ...point },
      defaults: structuredClone(defaults),
      initialText: "",
    };
    setNudgeSession(undefined);
    setTextEditSession(session);
  }, []);
  const finishTextEdit = useCallback((session: TextEditSession, result: TextEditResult) => {
    setTextEditSession(undefined);
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
  }, [dispatch, history]);
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
        setNudgeSession({ startingElements, previewElements, heldCodes });
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
      const command = keyboardCommandFor(event, {
        interactionActive: history.isTransactionActive
          || locks.slider
          || textLocked
          || nudgeSession !== undefined
          || canvasInteractionActive,
        shortcutHelpOpen,
        textEditing: textLocked,
      });
      if (!command) return;
      event.preventDefault();
      if (command.type === "escape") {
        if (canvasRef.current?.cancelInteraction()) {
          return;
        } else if (nudgeSession) {
          setNudgeSession(undefined);
        } else if (shortcutHelpOpen) {
          setShortcutHelpOpen(false);
        } else if (textEditSession) {
          finishTextEdit(textEditSession, { type: "cancel" });
        } else if (locks.slider) {
          setSelectionOpacityPreview(undefined);
          setLocks((current) => ({ ...current, slider: false }));
        } else if (history.isTransactionActive) {
          if (history.cancelTransaction()) publishSceneChange();
        } else if (tool !== "selection") {
          selectTool("selection");
        } else {
          select(undefined);
        }
        return;
      }
      if (command.type === "openShortcutHelp") {
        setShortcutHelpOpen(true);
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
        if (history[command.type]()) {
          publishSceneChange();
          select(undefined);
        }
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
        setNudgeSession({ ...nudgeSession, heldCodes });
        return;
      }
      const finalElements = nudgeSession.previewElements;
      const changed = finalElements.some((element, index) => {
        const starting = nudgeSession.startingElements[index];
        return !starting || element.x !== starting.x || element.y !== starting.y;
      });
      setNudgeSession(undefined);
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
  }, [beginTextEdit, canvasInteractionActive, copySelection, dispatch, duplicateSelection, finishTextEdit, history, locks.slider, nudgeSession, pasteSelection, publishSceneChange, reorderSelection, select, selectTool, selectedIds, shortcutHelpOpen, textEditSession, textLocked, tool]);

  useEffect(() => {
    const cancelNudge = () => setNudgeSession(undefined);
    window.addEventListener("blur", cancelNudge);
    return () => window.removeEventListener("blur", cancelNudge);
  }, []);

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
        setLocks((current) => ({ ...current, slider: true }));
        return;
      }
      case "commitSelectionOpacity": {
        const selected = selectedIds.map((id) => findElement(history.document, id));
        const elements = applyRailProperty(selected, "opacity", intent.value);
        setSelectionOpacityPreview(undefined);
        setLocks((current) => ({ ...current, slider: false }));
        dispatch({ type: "updateMany", elements });
        return;
      }
      case "cancelSelectionOpacity":
        setSelectionOpacityPreview(undefined);
        setLocks((current) => ({ ...current, slider: false }));
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
  }, [dispatch, document.defaults, duplicateSelection, history, nudgeSession, reorderSelection, select, selectedIds, textLocked, tool, updateDefaults]);

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
              onBeginTransaction={(label) => history.beginTransaction(label)}
              onCommitTransaction={() => {
                history.commitTransaction();
              }}
              onCancelTransaction={() => {
                if (history.cancelTransaction()) {
                  publishSceneChange();
                }
              }}
              onViewportWheel={onWheel}
              onViewportPanBy={panBy}
              onInteractionActiveChange={setCanvasInteractionActive}
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
        <ShortcutHelpDialog onClose={() => setShortcutHelpOpen(false)} />
      )}
    </main>
  );
}

type NudgeSession = {
  startingElements: readonly EditorElement[];
  previewElements: readonly EditorElement[];
  heldCodes: Set<string>;
};

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
  const [loadedDocument, setLoadedDocument] = useState<LoadedDocument>();
  const loadedDocumentRef = useRef<LoadedDocument | undefined>(undefined);
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
        document: annotationDocument,
        sourceImageURL,
        initialTool,
        loadInstanceId: acceptedLoadSequence.current,
      };
      loadedDocumentRef.current = nextDocument;
      setLoadedDocument(nextDocument);
      await bridge.sendCorrelated(message.requestId, "annotationSnapshot", { document: annotationDocument });
    };
    const receiveAnnotationSnapshotRequest = (event: Event) => {
      if (!(event instanceof CustomEvent) || typeof event.detail?.requestId !== "string") return;
      const loaded = loadedDocumentRef.current;
      if (!loaded) {
        void bridge.sendCorrelated(event.detail.requestId, "bridgeError", {
          code: "INVALID_DOCUMENT",
          message: "No editor document is loaded",
        });
        return;
      }
      void bridge.sendCorrelated(event.detail.requestId, "annotationSnapshot", { document: loaded.document });
    };
    void bridge.send("editorReady", {});
    const unsubscribe = bridge.subscribe((message) => {
      if (message.type === "loadDocument") {
        void acceptLoad(message);
        return;
      }
      if (message.type === "requestComposite" && loadedDocumentRef.current) {
        const loaded = loadedDocumentRef.current;
        void renderDocumentToBlob(loaded.document, loaded.sourceImageURL)
          .then((blob) => sendComposite({ requestId: message.requestId, blob, sendCorrelated: bridge.sendCorrelated }))
          .catch((error: unknown) => bridge.sendCorrelated(message.requestId, "bridgeError", {
            code: "RENDER_FAILED",
            message: error instanceof Error ? error.message : "Unable to render composite PNG",
          }));
      }
    });
    window.addEventListener("myshottr:request-annotation-snapshot", receiveAnnotationSnapshotRequest);
    return () => {
      latestLoadRequestSequence.current += 1;
      unsubscribe();
      window.removeEventListener("myshottr:request-annotation-snapshot", receiveAnnotationSnapshotRequest);
    };
  }, [bridge]);

  if (!loadedDocument) return <main aria-label="MyShottr editor">Waiting for document</main>;
  return <EditorApp
    key={loadedDocument.loadInstanceId}
    initialDocument={loadedDocument.document}
    initialTool={loadedDocument.initialTool}
    sourceImageURL={loadedDocument.sourceImageURL}
    onChange={(document) => {
      const loaded = loadedDocumentRef.current;
      if (!loaded || loaded.loadInstanceId !== loadedDocument.loadInstanceId) return;
      loadedDocumentRef.current = { ...loaded, document };
      void bridge.send("documentChanged", {});
    }}
    onPreferencesChange={(tool, defaults) => {
      const loaded = loadedDocumentRef.current;
      if (!loaded || loaded.loadInstanceId !== loadedDocument.loadInstanceId) return;
      loadedDocumentRef.current = {
        ...loaded,
        document: { ...loaded.document, defaults },
      };
      void bridge.send("editorPreferencesChanged", { tool, defaults });
    }}
  />;
}

type LoadedDocument = {
  document: EditorDocument;
  sourceImageURL: string;
  initialTool: EditorTool;
  loadInstanceId: number;
};

function sourceDimensions(sourceImageURL: string): Promise<{ width: number; height: number }> {
  return new Promise((resolve, reject) => {
    const image = new Image();
    image.onload = () => resolve({ width: image.naturalWidth, height: image.naturalHeight });
    image.onerror = () => reject(new Error("Source image could not be loaded"));
    image.src = sourceImageURL;
  });
}
