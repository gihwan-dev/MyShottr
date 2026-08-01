import {
  useCallback,
  useEffect,
  useImperativeHandle,
  useLayoutEffect,
  useRef,
  useState,
  forwardRef,
  type ReactNode,
} from "react";

import {
  RAIL_REFLOW_DURATION_MS,
  ViewportController,
  type Size,
  type Rect,
  type ViewportSnapshot,
  type WorkspaceMetrics,
} from "../viewport/ViewportController";
import type { Point } from "../model/elements";
import type { ZoomControlIntent } from "./ZoomControls";

const WORKSPACE_INSET = 16;
const WORKSPACE_TOP_INSET = 76;
const CONTEXT_RAIL_WIDTH = 248;
const CONTEXT_RAIL_GAP = 16;

export type EditorWorkspaceRenderState = {
  viewport: ViewportSnapshot;
  spacePanReady: boolean;
  onWheel: (input: {
    pointer: Point;
    deltaX: number;
    deltaY: number;
    metaKey: boolean;
    ctrlKey: boolean;
  }) => void;
  panBy: (delta: Point) => void;
  toSourcePoint: (workspacePoint: Point) => Point;
};

export type EditorWorkspaceHandle = {
  applyIntent: (intent: ZoomControlIntent) => void;
};

type EditorWorkspaceProps = {
  source: Size;
  railVisible: boolean;
  selectionBounds?: Rect;
  children: (state: EditorWorkspaceRenderState) => ReactNode;
};

export const EditorWorkspace = forwardRef<EditorWorkspaceHandle, EditorWorkspaceProps>(function EditorWorkspace({
  source,
  railVisible,
  selectionBounds,
  children,
}, ref) {
  const sourceWidth = source.width;
  const sourceHeight = source.height;
  const element = useRef<HTMLDivElement | null>(null);
  const controller = useRef<ViewportController | undefined>(undefined);
  const measuredWorkspace = useRef<Size | undefined>(undefined);
  const railVisibleRef = useRef(railVisible);
  railVisibleRef.current = railVisible;
  const animationFrame = useRef<number | undefined>(undefined);
  const [viewport, setViewport] = useState<ViewportSnapshot>();
  const viewportRef = useRef<ViewportSnapshot | undefined>(undefined);
  const [spacePanReady, setSpacePanReady] = useState(false);
  const selectionBoundsRef = useRef(selectionBounds);
  selectionBoundsRef.current = selectionBounds;

  const setDisplayedViewport = useCallback((next: ViewportSnapshot) => {
    viewportRef.current = next;
    setViewport(next);
  }, []);

  const cancelPanAnimation = useCallback(() => {
    if (animationFrame.current !== undefined) {
      cancelAnimationFrame(animationFrame.current);
      animationFrame.current = undefined;
    }
  }, []);

  const publishReflow = useCallback((next: ViewportSnapshot) => {
    cancelPanAnimation();
    const previous = viewportRef.current;
    if (
      !previous
      || window.matchMedia("(prefers-reduced-motion: reduce)").matches
      || (previous.pan.x === next.pan.x && previous.pan.y === next.pan.y)
    ) {
      setDisplayedViewport(next);
      return;
    }

    const startedAt = performance.now();
    setDisplayedViewport({ ...next, pan: { ...previous.pan } });
    const tick = (timestamp: number) => {
      const progress = Math.min(
        Math.max((timestamp - startedAt) / RAIL_REFLOW_DURATION_MS, 0),
        1,
      );
      setDisplayedViewport({
        ...next,
        pan: {
          x: previous.pan.x + (next.pan.x - previous.pan.x) * progress,
          y: previous.pan.y + (next.pan.y - previous.pan.y) * progress,
        },
      });
      if (progress < 1) {
        animationFrame.current = requestAnimationFrame(tick);
      } else {
        animationFrame.current = undefined;
      }
    };
    animationFrame.current = requestAnimationFrame(tick);
  }, [cancelPanAnimation, setDisplayedViewport]);

  const applyWorkspace = useCallback((workspace: Size) => {
    const metrics = metricsFor(workspace, railVisibleRef.current);
    measuredWorkspace.current = { ...workspace };
    if (!controller.current) {
      controller.current = new ViewportController({
        width: sourceWidth,
        height: sourceHeight,
      }, metrics);
      setDisplayedViewport(controller.current.snapshot);
      return;
    }
    publishReflow(controller.current.setWorkspace(metrics, {
      preserveCenteredSourcePoint: true,
    }));
  }, [publishReflow, setDisplayedViewport, sourceHeight, sourceWidth]);

  const publishMutation = useCallback((mutate: (current: ViewportController) => ViewportSnapshot) => {
    const current = controller.current;
    if (!current) throw new Error("ViewportController is unavailable before workspace measurement");
    cancelPanAnimation();
    setDisplayedViewport(mutate(current));
  }, [cancelPanAnimation, setDisplayedViewport]);

  const onWheel = useCallback((input: {
    pointer: Point;
    deltaX: number;
    deltaY: number;
    metaKey: boolean;
    ctrlKey: boolean;
  }) => {
    publishMutation((current) => input.metaKey || input.ctrlKey
      ? current.zoomFromWheelAt(input.pointer, input.deltaY)
      : current.panBy({ x: -input.deltaX, y: -input.deltaY }));
  }, [publishMutation]);

  const panBy = useCallback((delta: Point) => {
    publishMutation((current) => current.panBy(delta));
  }, [publishMutation]);

  const toSourcePoint = useCallback((workspacePoint: Point): Point => {
    const current = controller.current;
    if (!current) throw new Error("ViewportController is unavailable before workspace measurement");
    return current.toSourcePoint(workspacePoint);
  }, []);

  useImperativeHandle(ref, () => ({
    applyIntent: (intent) => {
      publishMutation((current) => {
        switch (intent.type) {
          case "zoomIn":
            return current.zoomIn();
          case "zoomOut":
            return current.zoomOut();
          case "zoom100":
            return current.set100Percent();
          case "fitImage":
            return current.fitImage();
          case "fitSelection": {
            const bounds = selectionBoundsRef.current;
            return bounds ? current.fitSelection(bounds) : current.snapshot;
          }
        }
      });
    },
  }), [publishMutation]);

  useLayoutEffect(() => {
    const workspace = measuredWorkspace.current;
    if (!workspace || !controller.current) return;
    publishReflow(controller.current.setWorkspace(
      metricsFor(workspace, railVisible),
      { preserveCenteredSourcePoint: true },
    ));
  }, [publishReflow, railVisible]);

  useEffect(() => {
    const target = element.current;
    if (!target) throw new Error("Editor workspace element is unavailable");
    const observer = new ResizeObserver((entries) => {
      const entry = entries[0];
      if (!entry) throw new Error("Editor workspace measurement is unavailable");
      applyWorkspace({
        width: entry.contentRect.width,
        height: entry.contentRect.height,
      });
    });
    observer.observe(target);
    return () => observer.disconnect();
  }, [applyWorkspace]);

  useEffect(() => cancelPanAnimation, [cancelPanAnimation]);

  useEffect(() => {
    const onKeyDown = (event: KeyboardEvent) => {
      if (
        event.code !== "Space"
        || event.metaKey
        || event.ctrlKey
        || event.altKey
        || event.shiftKey
        || isTextEntryTarget(event.target)
      ) return;
      event.preventDefault();
      setSpacePanReady(true);
    };
    const onKeyUp = (event: KeyboardEvent) => {
      if (event.code === "Space") setSpacePanReady(false);
    };
    const onBlur = () => setSpacePanReady(false);
    window.addEventListener("keydown", onKeyDown);
    window.addEventListener("keyup", onKeyUp);
    window.addEventListener("blur", onBlur);
    return () => {
      window.removeEventListener("keydown", onKeyDown);
      window.removeEventListener("keyup", onKeyUp);
      window.removeEventListener("blur", onBlur);
    };
  }, []);

  return (
    <div ref={element} className="editor-workspace" data-testid="editor-workspace">
      {viewport && children({
        viewport,
        spacePanReady,
        onWheel,
        panBy,
        toSourcePoint,
      })}
    </div>
  );
});

function isTextEntryTarget(target: EventTarget | null): boolean {
  if (!(target instanceof Element)) return false;
  return target.matches("input, textarea, select, [contenteditable]")
    || target.closest("[contenteditable]") !== null;
}

function metricsFor(workspace: Size, railVisible: boolean): WorkspaceMetrics {
  const normalizedWorkspace = {
    width: Math.max(1, workspace.width),
    height: Math.max(1, workspace.height),
  };
  const desiredAvailableX = railVisible
    ? WORKSPACE_INSET + CONTEXT_RAIL_WIDTH + CONTEXT_RAIL_GAP
    : WORKSPACE_INSET;
  const availableX = Math.min(
    desiredAvailableX,
    normalizedWorkspace.width - 1,
  );
  const availableY = Math.min(
    WORKSPACE_TOP_INSET,
    normalizedWorkspace.height - 1,
  );
  return {
    workspace: normalizedWorkspace,
    availableRect: {
      x: availableX,
      y: availableY,
      width: Math.max(
        1,
        normalizedWorkspace.width - availableX - WORKSPACE_INSET,
      ),
      height: Math.max(
        1,
        normalizedWorkspace.height - availableY - WORKSPACE_INSET,
      ),
    },
  };
}
