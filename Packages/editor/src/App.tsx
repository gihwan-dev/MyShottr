import {
  useCallback,
  useEffect,
  useRef,
  useState,
  useSyncExternalStore,
} from "react";
import { EditorCanvas } from "./canvas/EditorCanvas";
import { createDuplicateElements } from "./canvas/tools/createElement";
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
import { ZoomControls } from "./components/ZoomControls";
import { useNativeBridge } from "./bridge/nativeBridge";
import { renderDocumentToBlob } from "./export/renderDocumentToBlob";
import { sendComposite } from "./export/sendComposite";
import { createHistoryStore, type HistoryStore } from "./model/history";
import { applyRailProperty, findElement } from "./model/reducer";
import type { EditorCommand, EditorDefaults, EditorDocument, EditorElement, EditorTool, Point, TextElement } from "./model/elements";
import { KONVA_DEFAULT_FONT_FAMILY, TEXT_LINE_HEIGHT } from "./canvas/renderingConstants";
import { keyboardCommandFor } from "./input/ShortcutRouter";
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
  const copiedElements = useRef<EditorElement[]>([]);
  const document = useSyncExternalStore(
    history.subscribe,
    history.getSnapshot,
    history.getSnapshot,
  );
  const [selectedIds, setSelectedIds] = useState<string[]>([]);
  const [tool, setTool] = useState<EditorTool>(initialTool);
  const [zoom, setZoom] = useState(1);
  const [pan, setPan] = useState<Point>({ x: 0, y: 0 });
  const [editingTextId, setEditingTextId] = useState<string>();
  const [shortcutHelpOpen, setShortcutHelpOpen] = useState(false);
  const [selectionOpacityPreview, setSelectionOpacityPreview] = useState<{
    value: RailPropertyValueByKey["opacity"];
  }>();
  const [locks, setLocks] = useState({ slider: false });

  const publishSceneChange = useCallback(() => {
    onChange(history.getSnapshot());
  }, [history, onChange]);

  const dispatch = useCallback((command: EditorCommand) => {
    history.dispatch(command);
    publishSceneChange();
  }, [history, publishSceneChange]);
  const updateDefaults = useCallback((nextDefaults: EditorDefaults) => {
    history.setDefaults(nextDefaults);
    onPreferencesChange(tool, history.getSnapshot().defaults);
  }, [history, onPreferencesChange, tool]);
  const select = useCallback((id: string | undefined, toggle = false) => {
    setSelectionOpacityPreview(undefined);
    setLocks({ slider: false });
    setSelectedIds((current) => {
      if (!id) return [];
      if (!toggle) return [id];
      return current.includes(id)
        ? current.filter((candidate) => candidate !== id)
        : [...current, id];
    });
  }, []);
  const selectTool = useCallback((nextTool: EditorTool) => {
    setTool(nextTool);
    if (nextTool !== "selection") select(undefined);
    onPreferencesChange(nextTool, history.getSnapshot().defaults);
  }, [history, onPreferencesChange, select]);
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
    setLocks({ slider: false });
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
    setEditingTextId(id);
  }, [history]);
  const commitTextEdit = useCallback((text: string) => {
    const id = editingTextId;
    if (!id) return;
    const element = findElement(history.document, id);
    if (element.type !== "text") {
      throw new Error(`Cannot edit non-text element: ${id}`);
    }
    const nextText = text.trim();
    if (nextText.length === 0) {
      dispatch({ type: "delete", ids: [id] });
      select(undefined);
    } else {
      dispatch({ type: "update", element: { ...element, text: nextText, ...measureTextBounds(nextText, element.fontSize) } });
    }
    setEditingTextId(undefined);
  }, [dispatch, editingTextId, history, select]);
  const selectedElements = selectedIds.map((id) => findElement(document, id));
  const previewElements = selectionOpacityPreview
    ? applyRailProperty(selectedElements, "opacity", selectionOpacityPreview.value)
    : selectedElements;
  const previewById = new Map(previewElements.map((element) => [element.id, element]));
  const renderedDocument = selectionOpacityPreview
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
  const editingText = editingTextId
    ? document.elements.find((element): element is TextElement => element.id === editingTextId && element.type === "text")
    : undefined;

  useEffect(() => {
    const onKeyDown = (event: KeyboardEvent) => {
      const command = keyboardCommandFor(event, {
        interactionActive: history.isTransactionActive || locks.slider,
        shortcutHelpOpen,
        textEditing: editingTextId !== undefined,
      });
      if (!command) return;
      event.preventDefault();
      if (command.type === "escape") {
        if (shortcutHelpOpen) {
          setShortcutHelpOpen(false);
        } else if (editingTextId) {
          setEditingTextId(undefined);
        } else if (locks.slider) {
          setSelectionOpacityPreview(undefined);
          setLocks({ slider: false });
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
        setZoom(1);
        return;
      }
      if (command.type === "fitImage" || command.type === "fitSelection") {
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
    window.addEventListener("keydown", onKeyDown);
    return () => window.removeEventListener("keydown", onKeyDown);
  }, [copySelection, dispatch, duplicateSelection, editingTextId, history, locks.slider, pasteSelection, publishSceneChange, reorderSelection, select, selectTool, selectedIds, shortcutHelpOpen, tool]);

  const handleContextRailIntent = useCallback((intent: ContextRailIntent) => {
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
        setLocks({ slider: true });
        return;
      }
      case "commitSelectionOpacity": {
        const selected = selectedIds.map((id) => findElement(history.document, id));
        const elements = applyRailProperty(selected, "opacity", intent.value);
        setSelectionOpacityPreview(undefined);
        setLocks({ slider: false });
        dispatch({ type: "updateMany", elements });
        return;
      }
      case "cancelSelectionOpacity":
        setSelectionOpacityPreview(undefined);
        setLocks({ slider: false });
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
  }, [dispatch, document.defaults, duplicateSelection, history, reorderSelection, select, selectedIds, tool, updateDefaults]);

  return (
    <main
      className="editor-app"
      aria-label="MyShottr editor"
      style={{ cursor: cursorForTool(tool) }}
    >
      <EditorCanvas
        document={renderedDocument}
        sourceImageURL={sourceImageURL}
        tool={tool}
        zoom={zoom}
        pan={pan}
        selectedIds={selectedIds}
        onSelect={select}
        onEditText={beginTextEdit}
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
        onPanChange={setPan}
        textEditorOverlay={editingText && <TextEditorOverlay
          element={editingText}
          zoom={zoom}
          pan={pan}
          onCommit={commitTextEdit}
          onCancel={() => setEditingTextId(undefined)}
        />}
      />
      <FloatingToolPalette tool={tool} onSelect={selectTool} />
      <ContextRail model={contextRailModel} onIntent={handleContextRailIntent} />
      <ZoomControls zoom={zoom} onChange={setZoom} />
      {shortcutHelpOpen && (
        <ShortcutHelpDialog onClose={() => setShortcutHelpOpen(false)} />
      )}
    </main>
  );
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
  const [loadedDocument, setLoadedDocument] = useState<{ document: EditorDocument; sourceImageURL: string; initialTool: EditorTool }>();
  const loadedDocumentRef = useRef<{ document: EditorDocument; sourceImageURL: string; initialTool: EditorTool } | undefined>(undefined);

  useEffect(() => {
    const acceptLoad = async (message: Extract<Parameters<typeof bridge.subscribe>[0] extends (message: infer T) => void ? T : never, { type: "loadDocument" }>) => {
      const { annotationDocument, sourceImageURL, initialTool } = message.payload;
      try {
        const dimensions = await sourceDimensions(sourceImageURL);
        if (dimensions.width !== annotationDocument.sourcePixelWidth || dimensions.height !== annotationDocument.sourcePixelHeight) {
          throw new Error("Source image dimensions do not match the document");
        }
      } catch (error) {
        await bridge.sendCorrelated(message.requestId, "bridgeError", {
          code: "INVALID_DOCUMENT",
          message: error instanceof Error ? error.message : "Source image could not be loaded",
        });
        return;
      }
      const nextDocument = { document: annotationDocument, sourceImageURL, initialTool };
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
      unsubscribe();
      window.removeEventListener("myshottr:request-annotation-snapshot", receiveAnnotationSnapshotRequest);
    };
  }, [bridge]);

  if (!loadedDocument) return <main aria-label="MyShottr editor">Waiting for document</main>;
  return <EditorApp
    key={loadedDocument.sourceImageURL}
    initialDocument={loadedDocument.document}
    initialTool={loadedDocument.initialTool}
    sourceImageURL={loadedDocument.sourceImageURL}
    onChange={(document) => {
      if (loadedDocumentRef.current) {
        loadedDocumentRef.current = { ...loadedDocumentRef.current, document };
      }
      void bridge.send("documentChanged", {});
    }}
    onPreferencesChange={(tool, defaults) => {
      const loaded = loadedDocumentRef.current;
      if (loaded) {
        loadedDocumentRef.current = {
          ...loaded,
          document: { ...loaded.document, defaults },
        };
      }
      void bridge.send("editorPreferencesChanged", { tool, defaults });
    }}
  />;
}

function sourceDimensions(sourceImageURL: string): Promise<{ width: number; height: number }> {
  return new Promise((resolve, reject) => {
    const image = new Image();
    image.onload = () => resolve({ width: image.naturalWidth, height: image.naturalHeight });
    image.onerror = () => reject(new Error("Source image could not be loaded"));
    image.src = sourceImageURL;
  });
}
