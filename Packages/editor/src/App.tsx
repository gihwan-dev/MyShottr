import { useCallback, useEffect, useRef, useState } from "react";
import { EditorCanvas } from "./canvas/EditorCanvas";
import { duplicateElementWithinBounds, SelectionController } from "./canvas/SelectionController";
import { createElementId } from "./canvas/tools/createElement";
import { keyboardCommandFor, isTextEntryTarget } from "./canvas/tools/ToolController";
import { ContextStylePalette } from "./components/ContextStylePalette";
import { FloatingToolPalette } from "./components/FloatingToolPalette";
import { ZoomControls } from "./components/ZoomControls";
import { useNativeBridge } from "./bridge/nativeBridge";
import { renderDocumentToBlob } from "./export/renderDocumentToBlob";
import { sendComposite } from "./export/sendComposite";
import { createHistoryStore, type HistoryStore } from "./model/history";
import { findElement } from "./model/reducer";
import type { EditorCommand, EditorDocument, EditorTool, PaletteColor, Point } from "./model/elements";
import "./styles.css";

export type EditorAppProps = {
  initialDocument: EditorDocument;
  sourceImageURL: string;
  onChange: (document: EditorDocument) => void;
};

export function EditorApp({ initialDocument, sourceImageURL, onChange }: EditorAppProps) {
  const history = useRef<HistoryStore | undefined>(undefined);
  if (!history.current) history.current = createHistoryStore(initialDocument);
  const defaults = useRef(initialDocument.defaults);
  const selection = useRef(new SelectionController());
  const [document, setDocument] = useState(() => ({ ...history.current!.document, defaults: defaults.current }));
  const [selectedId, setSelectedId] = useState<string>();
  const [tool, setTool] = useState<EditorTool>("selection");
  const [zoom, setZoom] = useState(1);
  const [pan, setPan] = useState<Point>({ x: 0, y: 0 });
  const [rectangleFillColor, setRectangleFillColor] = useState<PaletteColor | null>(null);

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
    publishDocument();
  }, [publishDocument]);
  const select = useCallback((id: string | undefined) => {
    if (id) selection.current.select(id);
    else selection.current.clear();
    setSelectedId(selection.current.selectedElementId);
  }, []);
  const selectTool = useCallback((nextTool: EditorTool) => {
    setTool(nextTool);
    if (nextTool !== "selection") select(undefined);
  }, [select]);
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
      />
      <FloatingToolPalette tool={tool} onSelect={selectTool} />
      <ContextStylePalette tool={tool} defaults={document.defaults} fillColor={rectangleFillColor} onChange={setDefaults} onFillChange={setRectangleFillColor} />
      <ZoomControls zoom={zoom} onChange={setZoom} />
    </main>
  );
}

export function App() {
  const bridge = useNativeBridge();
  const [loadedDocument, setLoadedDocument] = useState<{ document: EditorDocument; sourceImageURL: string }>();
  const loadedDocumentRef = useRef<{ document: EditorDocument; sourceImageURL: string } | undefined>(undefined);

  useEffect(() => {
    const acceptLoad = async (message: Extract<Parameters<typeof bridge.subscribe>[0] extends (message: infer T) => void ? T : never, { type: "loadDocument" }>) => {
      const { annotationDocument, sourceImageURL } = message.payload;
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
      const nextDocument = { document: annotationDocument, sourceImageURL };
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
    sourceImageURL={loadedDocument.sourceImageURL}
    onChange={(document) => {
      if (loadedDocumentRef.current) {
        loadedDocumentRef.current = { ...loadedDocumentRef.current, document };
      }
      void bridge.send("documentChanged", {});
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
