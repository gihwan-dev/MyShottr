import { useCallback, useEffect, useRef, useState } from "react";
import { EditorCanvas } from "./canvas/EditorCanvas";
import { SelectionController } from "./canvas/SelectionController";
import { keyboardCommandFor, isTextEntryTarget } from "./canvas/tools/ToolController";
import { ContextStylePalette } from "./components/ContextStylePalette";
import { FloatingToolPalette } from "./components/FloatingToolPalette";
import { ZoomControls } from "./components/ZoomControls";
import { createEmptyDocument } from "./model/defaults";
import { createHistoryStore, type HistoryStore } from "./model/history";
import { findElement } from "./model/reducer";
import type { EditorCommand, EditorDocument, EditorTool } from "./model/elements";
import "./styles.css";

export type EditorAppProps = {
  initialDocument: EditorDocument;
  sourceImageURL: string;
  onChange: (document: EditorDocument) => void;
};

export function EditorApp({ initialDocument, sourceImageURL, onChange }: EditorAppProps) {
  const history = useRef<HistoryStore | undefined>(undefined);
  if (!history.current) history.current = createHistoryStore(initialDocument);
  const selection = useRef(new SelectionController());
  const [document, setDocument] = useState(() => history.current!.document);
  const [selectedId, setSelectedId] = useState<string>();
  const [tool, setTool] = useState<EditorTool>("selection");
  const [zoom, setZoom] = useState(1);

  const dispatch = useCallback((command: EditorCommand) => {
    history.current!.dispatch(command);
    const next = history.current!.document;
    setDocument(next);
    onChange(next);
  }, [onChange]);
  const setDefaults = useCallback((defaults: EditorDocument["defaults"]) => {
    const next = { ...document, defaults };
    setDocument(next);
    onChange(next);
  }, [document, onChange]);
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
    dispatch({ type: "create", element: { ...source, id: `${source.type}-${nextSeed}`, seed: nextSeed, zIndex: nextZIndex, x: source.x + 12, y: source.y + 12 } });
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
        history.current![command]();
        const next = history.current!.document;
        setDocument(next);
        onChange(next);
        select(undefined);
        return;
      }
      selectTool(command);
    };
    window.addEventListener("keydown", onKeyDown);
    return () => window.removeEventListener("keydown", onKeyDown);
  }, [dispatch, duplicateSelection, onChange, select, selectTool, selectedId]);

  return (
    <main className="editor-app" aria-label="MyShottr editor">
      <EditorCanvas
        document={document}
        sourceImageURL={sourceImageURL}
        tool={tool}
        zoom={zoom}
        selectedId={selectedId}
        onSelect={select}
        onCommand={dispatch}
        onBeginTransaction={(label) => history.current!.beginTransaction(label)}
        onCommitTransaction={() => {
          history.current!.commitTransaction();
          const next = history.current!.document;
          setDocument(next);
          onChange(next);
        }}
      />
      <FloatingToolPalette tool={tool} onSelect={selectTool} />
      <ContextStylePalette tool={tool} defaults={document.defaults} onChange={setDefaults} />
      <ZoomControls zoom={zoom} onChange={setZoom} />
    </main>
  );
}

const blankSourceImage = "data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVQIHWP4z8DwHwAFgAI/ScL5xQAAAABJRU5ErkJggg==";

export function App() {
  return <EditorApp initialDocument={createEmptyDocument()} sourceImageURL={blankSourceImage} onChange={() => {}} />;
}
