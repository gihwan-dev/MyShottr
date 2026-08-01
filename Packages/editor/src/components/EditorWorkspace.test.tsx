import { act, cleanup, fireEvent, render, screen } from "@testing-library/react";
import { createRef } from "react";
import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";

import {
  EditorWorkspace,
  type EditorWorkspaceHandle,
  type EditorWorkspaceRenderState,
} from "./EditorWorkspace";
import { RAIL_REFLOW_DURATION_MS, ViewportController } from "../viewport/ViewportController";

let resizeCallback: ResizeObserverCallback | undefined;

class ResizeObserverMock implements ResizeObserver {
  public constructor(callback: ResizeObserverCallback) {
    resizeCallback = callback;
  }

  public disconnect = vi.fn();
  public observe = vi.fn();
  public unobserve = vi.fn();
}

const triggerResize = (width: number, height: number) => {
  if (!resizeCallback) throw new Error("ResizeObserver was not created");
  act(() => {
    resizeCallback!([{
      contentRect: { width, height },
    } as ResizeObserverEntry], {} as ResizeObserver);
  });
};

function Snapshot({ state }: { state: EditorWorkspaceRenderState }) {
  return (
    <>
      <output
        data-testid="viewport-snapshot"
        data-workspace={`${state.viewport.workspace.width},${state.viewport.workspace.height}`}
        data-available={`${state.viewport.availableRect.x},${state.viewport.availableRect.y},${state.viewport.availableRect.width},${state.viewport.availableRect.height}`}
        data-pan={`${state.viewport.pan.x},${state.viewport.pan.y}`}
        data-zoom={state.viewport.zoom}
        data-space-pan={state.spacePanReady}
      />
      <button
        type="button"
        onClick={() => state.onWheel({
          pointer: { x: 500, y: 350 },
          deltaX: 100,
          deltaY: 50,
          metaKey: false,
          ctrlKey: false,
        })}
      >Pan wheel</button>
      <button
        type="button"
        onClick={() => state.onWheel({
          pointer: { x: 500, y: 350 },
          deltaX: 0,
          deltaY: -100,
          metaKey: false,
          ctrlKey: true,
        })}
      >Zoom wheel</button>
    </>
  );
}

beforeEach(() => {
  resizeCallback = undefined;
  vi.stubGlobal("ResizeObserver", ResizeObserverMock);
  vi.stubGlobal("requestAnimationFrame", vi.fn());
  vi.stubGlobal("cancelAnimationFrame", vi.fn());
  vi.stubGlobal("matchMedia", vi.fn().mockReturnValue({ matches: true }));
});

afterEach(() => {
  cleanup();
  vi.restoreAllMocks();
  vi.unstubAllGlobals();
});

describe("EditorWorkspace", () => {
  it("passes the full measured web-content size through as the Stage workspace", () => {
    render(
      <EditorWorkspace source={{ width: 2000, height: 1000 }} railVisible={false}>
        {(state) => <Snapshot state={state} />}
      </EditorWorkspace>,
    );

    expect(screen.queryByTestId("viewport-snapshot")).toBeNull();
    triggerResize(1000, 700);

    expect(screen.getByTestId("viewport-snapshot").getAttribute("data-workspace"))
      .toBe("1000,700");
  });

  it("uses the full safe canvas rect when the Context Rail is hidden", () => {
    render(
      <EditorWorkspace source={{ width: 2000, height: 1000 }} railVisible={false}>
        {(state) => <Snapshot state={state} />}
      </EditorWorkspace>,
    );

    triggerResize(1000, 700);

    expect(screen.getByTestId("viewport-snapshot").getAttribute("data-available"))
      .toBe("16,76,968,608");
  });

  it("reserves the visible 248px rail plus the 16px inset and gap", () => {
    render(
      <EditorWorkspace source={{ width: 2000, height: 1000 }} railVisible>
        {(state) => <Snapshot state={state} />}
      </EditorWorkspace>,
    );

    triggerResize(1000, 700);

    expect(screen.getByTestId("viewport-snapshot").getAttribute("data-available"))
      .toBe("280,76,704,608");
  });

  it("keeps a 1px in-bounds safe area when the workspace is narrower than the rail reservation", () => {
    render(
      <EditorWorkspace source={{ width: 2000, height: 1000 }} railVisible>
        {(state) => <Snapshot state={state} />}
      </EditorWorkspace>,
    );

    triggerResize(250, 100);

    expect(screen.getByTestId("viewport-snapshot").getAttribute("data-workspace"))
      .toBe("250,100");
    expect(screen.getByTestId("viewport-snapshot").getAttribute("data-available"))
      .toBe("249,76,1,8");
  });

  it("normalizes a zero-size measurement to one in-bounds Stage pixel", () => {
    render(
      <EditorWorkspace source={{ width: 2000, height: 1000 }} railVisible>
        {(state) => <Snapshot state={state} />}
      </EditorWorkspace>,
    );

    triggerResize(0, 0);

    expect(screen.getByTestId("viewport-snapshot").getAttribute("data-workspace"))
      .toBe("1,1");
    expect(screen.getByTestId("viewport-snapshot").getAttribute("data-available"))
      .toBe("0,0,1,1");
  });

  it("preserves the centered source point when rail visibility reflows", () => {
    const setWorkspace = vi.spyOn(ViewportController.prototype, "setWorkspace");
    const view = render(
      <EditorWorkspace source={{ width: 2000, height: 1000 }} railVisible={false}>
        {(state) => <Snapshot state={state} />}
      </EditorWorkspace>,
    );
    triggerResize(1000, 700);

    view.rerender(
      <EditorWorkspace source={{ width: 2000, height: 1000 }} railVisible>
        {(state) => <Snapshot state={state} />}
      </EditorWorkspace>,
    );

    expect(setWorkspace).toHaveBeenLastCalledWith({
      workspace: { width: 1000, height: 700 },
      availableRect: { x: 280, y: 76, width: 704, height: 608 },
    }, {
      preserveCenteredSourcePoint: true,
    });
    expect(screen.getByTestId("viewport-snapshot").getAttribute("data-pan"))
      .toBe("132,0");
  });

  it("applies rail reflow immediately when reduced motion is requested", () => {
    const view = render(
      <EditorWorkspace source={{ width: 2000, height: 1000 }} railVisible={false}>
        {(state) => <Snapshot state={state} />}
      </EditorWorkspace>,
    );
    triggerResize(1000, 700);

    view.rerender(
      <EditorWorkspace source={{ width: 2000, height: 1000 }} railVisible>
        {(state) => <Snapshot state={state} />}
      </EditorWorkspace>,
    );

    expect(screen.getByTestId("viewport-snapshot").getAttribute("data-pan"))
      .toBe("132,0");
    expect(requestAnimationFrame).not.toHaveBeenCalled();
  });

  it("interpolates only pan for exactly 160ms while zoom stays fixed", () => {
    vi.mocked(matchMedia).mockReturnValue({ matches: false } as MediaQueryList);
    vi.spyOn(performance, "now").mockReturnValue(0);
    const frames: FrameRequestCallback[] = [];
    vi.mocked(requestAnimationFrame).mockImplementation((callback) => {
      frames.push(callback);
      return frames.length;
    });
    const view = render(
      <EditorWorkspace source={{ width: 2000, height: 1000 }} railVisible={false}>
        {(state) => <Snapshot state={state} />}
      </EditorWorkspace>,
    );
    triggerResize(1000, 700);
    const beforeZoom = screen.getByTestId("viewport-snapshot").getAttribute("data-zoom");

    view.rerender(
      <EditorWorkspace source={{ width: 2000, height: 1000 }} railVisible>
        {(state) => <Snapshot state={state} />}
      </EditorWorkspace>,
    );

    expect(RAIL_REFLOW_DURATION_MS).toBe(160);
    expect(screen.getByTestId("viewport-snapshot").getAttribute("data-pan"))
      .toBe("0,0");
    expect(screen.getByTestId("viewport-snapshot").getAttribute("data-zoom"))
      .toBe(beforeZoom);

    act(() => frames.shift()?.(80));
    expect(screen.getByTestId("viewport-snapshot").getAttribute("data-pan"))
      .toBe("66,0");
    expect(screen.getByTestId("viewport-snapshot").getAttribute("data-zoom"))
      .toBe(beforeZoom);

    act(() => frames.shift()?.(160));
    expect(screen.getByTestId("viewport-snapshot").getAttribute("data-pan"))
      .toBe("132,0");
    expect(screen.getByTestId("viewport-snapshot").getAttribute("data-zoom"))
      .toBe(beforeZoom);
  });

  it("routes an ordinary wheel as bounded two-axis trackpad pan", () => {
    render(
      <EditorWorkspace source={{ width: 2000, height: 1000 }} railVisible={false}>
        {(state) => <Snapshot state={state} />}
      </EditorWorkspace>,
    );
    triggerResize(1000, 700);

    fireEvent.click(screen.getByRole("button", { name: "Pan wheel" }));

    expect(screen.getByTestId("viewport-snapshot").getAttribute("data-pan"))
      .toBe("-100,-50");
  });

  it("routes a control-wheel as pointer-anchored zoom", () => {
    render(
      <EditorWorkspace source={{ width: 2000, height: 1000 }} railVisible={false}>
        {(state) => <Snapshot state={state} />}
      </EditorWorkspace>,
    );
    triggerResize(1000, 700);

    fireEvent.click(screen.getByRole("button", { name: "Zoom wheel" }));

    expect(Number(screen.getByTestId("viewport-snapshot").getAttribute("data-zoom")))
      .toBeCloseTo(Math.exp(0.1));
  });

  it("exposes Space-pan readiness only while Space is held", () => {
    render(
      <EditorWorkspace source={{ width: 2000, height: 1000 }} railVisible={false}>
        {(state) => <Snapshot state={state} />}
      </EditorWorkspace>,
    );
    triggerResize(1000, 700);

    fireEvent.keyDown(window, { code: "Space" });
    expect(screen.getByTestId("viewport-snapshot").getAttribute("data-space-pan"))
      .toBe("true");

    fireEvent.keyUp(window, { code: "Space" });
    expect(screen.getByTestId("viewport-snapshot").getAttribute("data-space-pan"))
      .toBe("false");
  });

  it("routes semantic zoom and fit commands through the sole controller", () => {
    const workspaceRef = createRef<EditorWorkspaceHandle>();
    render(
      <EditorWorkspace
        ref={workspaceRef}
        source={{ width: 2000, height: 1000 }}
        railVisible={false}
        selectionBounds={{ x: 400, y: 200, width: 200, height: 100 }}
      >
        {(state) => <Snapshot state={state} />}
      </EditorWorkspace>,
    );
    triggerResize(1000, 700);

    act(() => workspaceRef.current?.applyIntent({ type: "zoomIn" }));
    expect(screen.getByTestId("viewport-snapshot").getAttribute("data-zoom"))
      .toBe("1.1");
    act(() => workspaceRef.current?.applyIntent({ type: "zoom100" }));
    expect(screen.getByTestId("viewport-snapshot").getAttribute("data-zoom"))
      .toBe("1");
    act(() => workspaceRef.current?.applyIntent({ type: "fitImage" }));
    expect(screen.getByTestId("viewport-snapshot").getAttribute("data-zoom"))
      .toBe("0.46");
    act(() => workspaceRef.current?.applyIntent({ type: "fitSelection" }));
    expect(screen.getByTestId("viewport-snapshot").getAttribute("data-zoom"))
      .toBe("4.6");
  });
});
