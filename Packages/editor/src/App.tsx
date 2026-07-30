import { useCallback, useEffect, useRef, useState } from "react";
import { EditorCanvas } from "./canvas/EditorCanvas";
import { duplicateElementWithinBounds, SelectionController } from "./canvas/SelectionController";
import { createElementId } from "./canvas/tools/createElement";
import { keyboardCommandFor, isTextEntryTarget } from "./canvas/tools/ToolController";
import { ContextStylePalette } from "./components/ContextStylePalette";
import { FloatingToolPalette } from "./components/FloatingToolPalette";
import { TextEditorOverlay } from "./components/TextEditorOverlay";
import { ZoomControls } from "./components/ZoomControls";
import { useNativeBridge } from "./bridge/nativeBridge";
import { renderDocumentToBlob } from "./export/renderDocumentToBlob";
import { sendComposite } from "./export/sendComposite";
import { createHistoryStore, type HistoryStore } from "./model/history";
import { findElement } from "./model/reducer";
import type { EditorCommand, EditorDefaults, EditorDocument, EditorTool, PaletteColor, Point, TextElement } from "./model/elements";
import { KONVA_DEFAULT_FONT_FAMILY } from "./canvas/renderingConstants";
import "./styles.css";

export type EditorAppProps = {
  initialDocument: EditorDocument;
  initialTool: EditorTool;
  sourceImageURL: string;
  onChange: (document: EditorDocument) => void;
  onPreferencesChange: (tool: EditorTool, defaults: EditorDefaults) => void;
};

export function EditorApp({ initialDocument, initialTool, sourceImageURL, onChange, onPreferencesChange }: EditorAppProps) {
  const history = useRef<HistoryStore | undefined>(undefined);
  if (!history.current) history.current = createHistoryStore(initialDocument);
  const defaults = useRef(initialDocument.defaults);
  const selection = useRef(new SelectionController());
  const [document, setDocument] = useState(() => ({ ...history.current!.document, defaults: defaults.current }));
  const [selectedId, setSelectedId] = useState<string>();
  const [tool, setTool] = useState<EditorTool>(initialTool);
  const [zoom, setZoom] = useState(1);
  const [pan, setPan] = useState<Point>({ x: 0, y: 0 });
  const [rectangleFillColor, setRectangleFillColor] = useState<PaletteColor | null>(null);
  const [editingTextId, setEditingTextId] = useState<string>();

  const publishDocument = useCallback(() => {
    const next = { ...history.current!.document, defaults: defaults.current };
    setDocument(next);
    onChange(next);
    return next;
  }, [onChange]);

  const dispatch = useCallback((command: EditorCommand) => {
    history.current!.dispatch(command);
    publishDocument();
  }, [publishDocument]);
  const setDefaults = useCallback((nextDefaults: EditorDocument["defaults"]) => {
    defaults.current = nextDefaults;
    setDocument((current) => ({ ...current, defaults: nextDefaults }));
    onPreferencesChange(tool, nextDefaults);
  }, [onPreferencesChange, tool]);
  const select = useCallback((id: string | undefined) => {
    if (id) selection.current.select(id);
    else selection.current.clear();
    setSelectedId(selection.current.selectedElementId);
  }, []);
  const selectTool = useCallback((nextTool: EditorTool) => {
    setTool(nextTool);
    if (nextTool !== "selection") select(undefined);
    onPreferencesChange(nextTool, defaults.current);
  }, [onPreferencesChange, select]);
  const duplicateSelection = useCallback(() => {
    if (!selectedId) return;
    const source = findElement(history.current!.document, selectedId);
    const nextSeed = Math.max(0, ...document.elements.map((element) => element.seed)) + 1;
    const nextZIndex = Math.max(-1, ...document.elements.map((element) => element.zIndex)) + 1;
    const offset = duplicateElementWithinBounds(
      source,
      { x: source.x + 12, y: source.y + 12 },
      { sourceWidth: document.sourcePixelWidth, sourceHeight: document.sourcePixelHeight },
    );
    dispatch({ type: "create", element: { ...offset, id: createElementId(), seed: nextSeed, zIndex: nextZIndex } });
  }, [dispatch, document.elements, selectedId]);
  const beginTextEdit = useCallback((id: string) => {
    const element = findElement(history.current!.document, id);
    if (element.type !== "text") {
      throw new Error(`Cannot edit non-text element: ${id}`);
    }
    setEditingTextId(id);
  }, []);
  const commitTextEdit = useCallback((text: string) => {
    const id = editingTextId;
    if (!id) return;
    const element = findElement(history.current!.document, id);
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
  }, [dispatch, editingTextId, select]);
  const selectedElements = selectedId
    ? document.elements.filter((element) => element.id === selectedId)
    : [];
  const editingText = editingTextId
    ? document.elements.find((element): element is TextElement => element.id === editingTextId && element.type === "text")
    : undefined;

  useEffect(() => {
    const onKeyDown = (event: KeyboardEvent) => {
      if (isTextEntryTarget(event.target)) return;
      const command = keyboardCommandFor(event);
      if (!command) return;
      event.preventDefault();
      if (command === "delete") {
        if (selectedId) {
          dispatch({ type: "delete", ids: [selectedId] });
          select(undefined);
        }
        return;
      }
      if (command === "duplicate") {
        duplicateSelection();
        return;
      }
      if (command === "undo" || command === "redo") {
        if (history.current![command]()) {
          publishDocument();
          select(undefined);
        }
        return;
      }
      selectTool(command);
    };
    window.addEventListener("keydown", onKeyDown);
    return () => window.removeEventListener("keydown", onKeyDown);
  }, [dispatch, duplicateSelection, publishDocument, select, selectTool, selectedId]);

  return (
    <main className="editor-app" aria-label="MyShottr editor">
      <EditorCanvas
        document={document}
        sourceImageURL={sourceImageURL}
        tool={tool}
        zoom={zoom}
        pan={pan}
        rectangleFillColor={rectangleFillColor}
        selectedId={selectedId}
        onSelect={select}
        onEditText={beginTextEdit}
        onCommand={dispatch}
        onBeginTransaction={(label) => history.current!.beginTransaction(label)}
        onCommitTransaction={() => {
          history.current!.commitTransaction();
          publishDocument();
        }}
        onCancelTransaction={() => {
          if (history.current!.cancelTransaction()) {
            publishDocument();
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
      <ContextStylePalette
        tool={tool}
        defaults={document.defaults}
        selectedElements={selectedElements}
        onDefaultsChange={setDefaults}
        onElementsChange={(elements) => dispatch({ type: "updateMany", elements })}
        fillColor={rectangleFillColor}
        onFillChange={setRectangleFillColor}
      />
      <ZoomControls zoom={zoom} onChange={setZoom} />
    </main>
  );
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
    height: Math.ceil(lines.length * fontSize * 1.2),
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
