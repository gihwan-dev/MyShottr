import {
  StrictMode,
  useEffect,
  useMemo,
  useRef,
  useState,
} from "react";
import { createRoot } from "react-dom/client";

import "../../src/styles.css";

import { useNativeAppearance } from "../../src/appearance/useNativeAppearance";
import {
  createNativeBridge,
  NativeBridgeProvider,
  useNativeBridge,
} from "../../src/bridge/nativeBridge";
import { EditorCanvas } from "../../src/canvas/EditorCanvas";
import { cursorForTool } from "../../src/canvas/tools/ToolController";
import { ContextRail } from "../../src/components/ContextRail";
import { deriveContextRailModel } from "../../src/components/contextRailModel";
import {
  EditorFeedback,
  useEditorFeedback,
} from "../../src/components/EditorFeedback";
import { FloatingToolPalette } from "../../src/components/FloatingToolPalette";
import { ShortcutHelpDialog } from "../../src/components/ShortcutHelpDialog";
import {
  EditorWorkspace,
  type EditorWorkspaceHandle,
} from "../../src/components/EditorWorkspace";
import { ZoomControls } from "../../src/components/ZoomControls";
import { unionBounds } from "../../src/interaction/selectionGeometry";
import type {
  EditorCommand,
  EditorDefaults,
  EditorDocument,
  EditorTool,
  Point,
  RectangleElement,
  TextElement,
} from "../../src/model/elements";
import { findElement } from "../../src/model/reducer";
import {
  fixtureDocument,
  fixtureRect,
  fixtureText,
} from "../../src/test/fixtures";

export type VisualFixtureState =
  | "selection-empty"
  | "new-rectangle"
  | "selected-rectangle"
  | "mixed-rectangle-text"
  | "shortcut-help"
  | "save-success"
  | "rail-reduced-motion";

type Fixture = {
  document: EditorDocument;
  tool: EditorTool;
  selectedIds: string[];
  shortcutHelpOpen: boolean;
};

const VISUAL_STATES: readonly VisualFixtureState[] = [
  "selection-empty",
  "new-rectangle",
  "selected-rectangle",
  "mixed-rectangle-text",
  "shortcut-help",
  "save-success",
  "rail-reduced-motion",
];

const SOURCE_IMAGE_URL = `data:image/svg+xml;utf8,${encodeURIComponent(`
<svg xmlns="http://www.w3.org/2000/svg" width="1440" height="900" viewBox="0 0 1440 900">
  <defs>
    <linearGradient id="chart" x1="0" x2="0" y1="0" y2="1">
      <stop offset="0%" stop-color="#6aa8ff" stop-opacity="0.55" />
      <stop offset="100%" stop-color="#6aa8ff" stop-opacity="0.06" />
    </linearGradient>
  </defs>
  <rect width="1440" height="900" fill="#f4f7fb" />
  <rect width="1440" height="104" fill="#1f2d44" />
  <text x="120" y="66" fill="#ffffff" font-family="-apple-system, sans-serif" font-size="34" font-weight="700">Project Atlas</text>
  <text x="1080" y="62" fill="#c9d5e8" font-family="-apple-system, sans-serif" font-size="18">A neutral sample workspace</text>
  <rect x="72" y="144" width="620" height="340" rx="12" fill="#ffffff" stroke="#dce3ed" stroke-width="3" />
  <text x="112" y="198" fill="#263752" font-family="-apple-system, sans-serif" font-size="27" font-weight="700">Release readiness</text>
  <text x="112" y="266" fill="#5c6b82" font-family="-apple-system, sans-serif" font-size="18">Capture</text>
  <rect x="240" y="241" width="370" height="20" rx="10" fill="#e8edf4" />
  <rect x="240" y="241" width="300" height="20" rx="10" fill="#ff6b5f" />
  <text x="112" y="338" fill="#5c6b82" font-family="-apple-system, sans-serif" font-size="18">Annotate</text>
  <rect x="240" y="313" width="370" height="20" rx="10" fill="#e8edf4" />
  <rect x="240" y="313" width="250" height="20" rx="10" fill="#287ff0" />
  <text x="112" y="410" fill="#5c6b82" font-family="-apple-system, sans-serif" font-size="18">Review</text>
  <rect x="240" y="385" width="370" height="20" rx="10" fill="#e8edf4" />
  <rect x="240" y="385" width="205" height="20" rx="10" fill="#39b977" />
  <rect x="732" y="144" width="636" height="340" rx="12" fill="#ffffff" stroke="#dce3ed" stroke-width="3" />
  <text x="772" y="198" fill="#263752" font-family="-apple-system, sans-serif" font-size="27" font-weight="700">Weekly signal</text>
  <path d="M780 415 L860 365 L940 397 L1020 300 L1100 345 L1190 235 L1285 285 L1320 260 L1320 430 L780 430 Z" fill="url(#chart)" />
  <polyline points="780,415 860,365 940,397 1020,300 1100,345 1190,235 1285,285 1320,260" fill="none" stroke="#1677ff" stroke-width="8" stroke-linecap="round" stroke-linejoin="round" />
  <rect x="72" y="528" width="1296" height="288" rx="12" fill="#ffffff" stroke="#dce3ed" stroke-width="3" />
  <text x="112" y="588" fill="#263752" font-family="-apple-system, sans-serif" font-size="27" font-weight="700">Visual checklist</text>
  <g opacity="0.9">
    <rect x="112" y="638" width="126" height="22" rx="6" fill="#ffb3ac" />
    <rect x="258" y="638" width="126" height="22" rx="6" fill="#a9caff" />
    <rect x="404" y="638" width="126" height="22" rx="6" fill="#ffe985" />
    <rect x="550" y="638" width="126" height="22" rx="6" fill="#9be0be" />
    <rect x="696" y="638" width="126" height="22" rx="6" fill="#d4b1ff" />
    <rect x="842" y="638" width="126" height="22" rx="6" fill="#ffd4a8" />
    <rect x="988" y="638" width="126" height="22" rx="6" fill="#ffb3ac" />
    <rect x="1134" y="638" width="126" height="22" rx="6" fill="#a9caff" />
    <rect x="112" y="686" width="126" height="22" rx="6" fill="#a9caff" />
    <rect x="258" y="686" width="126" height="22" rx="6" fill="#ffe985" />
    <rect x="404" y="686" width="126" height="22" rx="6" fill="#9be0be" />
    <rect x="550" y="686" width="126" height="22" rx="6" fill="#d4b1ff" />
    <rect x="696" y="686" width="126" height="22" rx="6" fill="#ffd4a8" />
    <rect x="842" y="686" width="126" height="22" rx="6" fill="#ffb3ac" />
    <rect x="988" y="686" width="126" height="22" rx="6" fill="#a9caff" />
    <rect x="1134" y="686" width="126" height="22" rx="6" fill="#ffe985" />
  </g>
</svg>
`)}`;

function parseFixtureState(): VisualFixtureState {
  const state = new URLSearchParams(window.location.search).get("state");
  if (!VISUAL_STATES.includes(state as VisualFixtureState)) {
    throw new Error(`Unknown or missing visual fixture state: ${String(state)}`);
  }
  return state as VisualFixtureState;
}

function visualRectangle(): RectangleElement {
  return {
    ...fixtureRect(),
    x: 120,
    y: 105,
    width: 470,
    height: 290,
    strokeColor: "#FF4D4F",
  };
}

function visualText(): TextElement {
  return {
    ...fixtureText(),
    x: 700,
    y: 510,
    width: 300,
    height: 44,
    zIndex: 1,
    text: "Review this release signal",
    color: "#1677FF",
    opacity: 0.5,
  };
}

function fixtureFor(state: VisualFixtureState): Fixture {
  const rectangle = visualRectangle();
  const text = visualText();
  const document = fixtureDocument({
    sourcePixelWidth: 1200,
    sourcePixelHeight: 750,
    elements: [rectangle, text],
  });

  switch (state) {
    case "selection-empty":
      return { document, tool: "selection", selectedIds: [], shortcutHelpOpen: false };
    case "new-rectangle":
      return { document, tool: "rectangle", selectedIds: [], shortcutHelpOpen: false };
    case "selected-rectangle":
      return { document, tool: "selection", selectedIds: [rectangle.id], shortcutHelpOpen: false };
    case "mixed-rectangle-text":
      return { document, tool: "selection", selectedIds: [rectangle.id, text.id], shortcutHelpOpen: false };
    case "shortcut-help":
      return { document, tool: "selection", selectedIds: [rectangle.id], shortcutHelpOpen: true };
    case "save-success":
      return { document, tool: "selection", selectedIds: [rectangle.id], shortcutHelpOpen: false };
    case "rail-reduced-motion":
      return { document, tool: "selection", selectedIds: [rectangle.id], shortcutHelpOpen: false };
  }
}

function ViewportProbe({
  transform,
  pan,
  sourceCenter,
  zoom,
  onViewportChange,
}: {
  transform: string;
  pan: Point;
  sourceCenter: Point;
  zoom: number;
  onViewportChange: (signature: string) => void;
}) {
  useEffect(() => {
    onViewportChange([
      transform,
      sourceCenter.x,
      sourceCenter.y,
    ].join(":"));
  }, [onViewportChange, sourceCenter.x, sourceCenter.y, transform]);

  return (
    <output
      aria-hidden="true"
      className="visual-fixture-viewport-probe"
      data-testid="visual-fixture-viewport"
      data-canvas-transform={transform}
      data-pan-x={pan.x}
      data-pan-y={pan.y}
      data-source-center-x={sourceCenter.x}
      data-source-center-y={sourceCenter.y}
      data-zoom={zoom}
    />
  );
}

function VisualHarness() {
  useNativeAppearance();

  const bridge = useNativeBridge();
  const viewportRef = useRef<EditorWorkspaceHandle>(null);
  const fixtureState = parseFixtureState();
  const fixture = useMemo(() => fixtureFor(fixtureState), [fixtureState]);
  const [tool, setTool] = useState<EditorTool>("selection");
  const [selectedIds, setSelectedIds] = useState<string[]>([]);
  const [shortcutHelpOpen, setShortcutHelpOpen] = useState(false);
  const [sourceReady, setSourceReady] = useState(false);
  const [sourceError, setSourceError] = useState<Error>();
  const [configurationApplied, setConfigurationApplied] = useState(false);
  const [viewportSignature, setViewportSignature] = useState<string>();
  const [viewportStable, setViewportStable] = useState(false);
  const {
    state: feedbackState,
    receive: receiveOperationStatus,
  } = useEditorFeedback();

  if (sourceError) throw sourceError;

  useEffect(() => {
    const image = new Image();
    image.onload = () => setSourceReady(true);
    image.onerror = () => setSourceError(
      new Error("Visual fixture source image failed to load"),
    );
    image.src = SOURCE_IMAGE_URL;
    return () => {
      image.onload = null;
      image.onerror = null;
    };
  }, []);

  useEffect(() => {
    if (!sourceReady || !viewportSignature || configurationApplied) return;
    const frame = requestAnimationFrame(() => {
      setTool(fixture.tool);
      setSelectedIds(fixture.selectedIds);
      setShortcutHelpOpen(fixture.shortcutHelpOpen);
      setConfigurationApplied(true);
    });
    return () => cancelAnimationFrame(frame);
  }, [
    configurationApplied,
    fixture.selectedIds,
    fixture.shortcutHelpOpen,
    fixture.tool,
    sourceReady,
    viewportSignature,
  ]);

  useEffect(() => {
    setViewportStable(false);
    if (!configurationApplied || !sourceReady || !viewportSignature) return;
    const timer = window.setTimeout(() => setViewportStable(true), 64);
    return () => window.clearTimeout(timer);
  }, [configurationApplied, sourceReady, viewportSignature]);

  useEffect(
    () => bridge.subscribe((message) => {
      if (message.type === "operationStatus") {
        receiveOperationStatus({
          requestId: message.requestId,
          status: message.payload,
        });
        return;
      }
    }),
    [bridge, receiveOperationStatus],
  );

  useEffect(() => {
    const openShortcutHelp = (event: KeyboardEvent) => {
      if (event.code !== "Slash" || !event.shiftKey) return;
      event.preventDefault();
      setShortcutHelpOpen(true);
    };
    window.addEventListener("keydown", openShortcutHelp);
    return () => window.removeEventListener("keydown", openShortcutHelp);
  }, []);

  useEffect(() => {
    if (!viewportStable) {
      delete document.documentElement.dataset.visualFixtureReady;
      return;
    }
    document.documentElement.dataset.visualFixtureReady = fixtureState;
    return () => {
      delete document.documentElement.dataset.visualFixtureReady;
    };
  }, [fixtureState, viewportStable]);

  const selectedElements = selectedIds.map((id) =>
    findElement(fixture.document, id),
  );
  const contextRailModel = deriveContextRailModel({
    tool,
    document: fixture.document,
    selectedIds,
  });

  return (
    <>
      <main
        className="editor-app"
        aria-label="Inkbeam editor"
        data-fixture-state={fixtureState}
        data-rail-visible={contextRailModel.kind !== "hidden"}
        style={{ cursor: cursorForTool(tool) }}
      >
        <EditorWorkspace
          ref={viewportRef}
          source={{
            width: fixture.document.sourcePixelWidth,
            height: fixture.document.sourcePixelHeight,
          }}
          railVisible={contextRailModel.kind !== "hidden"}
          selectionBounds={unionBounds(selectedElements)}
        >
          {({ viewport, spacePanReady, onWheel, panBy, toSourcePoint }) => {
            const availableCenter = {
              x: viewport.availableRect.x + viewport.availableRect.width / 2,
              y: viewport.availableRect.y + viewport.availableRect.height / 2,
            };
            const sourceCenter = toSourcePoint(availableCenter);
            return (
              <>
                <EditorCanvas
                  document={fixture.document}
                  sourceImageURL={SOURCE_IMAGE_URL}
                  tool={tool}
                  viewport={viewport}
                  spacePanReady={spacePanReady}
                  interactionLocked={false}
                  selectedIds={selectedIds}
                  onSelect={(id, toggle = false) => {
                    if (!id) {
                      setSelectedIds([]);
                      return;
                    }
                    setSelectedIds((current) => toggle
                      ? current.includes(id)
                        ? current.filter((candidate) => candidate !== id)
                        : [...current, id]
                      : [id]);
                  }}
                  onEditText={() => {}}
                  onBeginNewText={(_: Point, __: EditorDefaults) => {}}
                  onCommand={(_: EditorCommand) => {}}
                  onBeginTransaction={() => {}}
                  onCommitTransaction={() => {}}
                  onCancelTransaction={() => {}}
                  onViewportWheel={onWheel}
                  onViewportPanBy={panBy}
                  onInteractionActiveChange={() => {}}
                  toSourcePoint={toSourcePoint}
                  textEditorOverlay={null}
                />
                <ViewportProbe
                  transform={`translate(${viewport.pan.x},${viewport.pan.y}) scale(${viewport.zoom})`}
                  pan={viewport.pan}
                  sourceCenter={sourceCenter}
                  zoom={viewport.zoom}
                  onViewportChange={setViewportSignature}
                />
                <ZoomControls
                  zoom={viewport.zoom}
                  onIntent={(intent) => viewportRef.current?.applyIntent(intent)}
                />
              </>
            );
          }}
        </EditorWorkspace>
        <FloatingToolPalette
          tool={tool}
          onSelect={(nextTool) => {
            setTool(nextTool);
            if (nextTool !== "selection") setSelectedIds([]);
          }}
          interactionLocked={false}
        />
        <ContextRail model={contextRailModel} onIntent={() => {}} />
        {shortcutHelpOpen && (
          <ShortcutHelpDialog onClose={() => setShortcutHelpOpen(false)} />
        )}
      </main>
      <EditorFeedback state={feedbackState} />
    </>
  );
}

const root = document.getElementById("root");
if (!root) throw new Error("Missing #root");

createRoot(root).render(
  <StrictMode>
    <NativeBridgeProvider bridge={createNativeBridge()}>
      <VisualHarness />
    </NativeBridgeProvider>
  </StrictMode>,
);
