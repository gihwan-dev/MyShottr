import {
  act,
  cleanup,
  render,
  screen,
} from "@testing-library/react";
import {
  createRef,
  forwardRef,
  useImperativeHandle,
} from "react";
import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";

import type { NativeToEditorEnvelope } from "../bridge/protocol";
import {
  EditorFeedback,
  useEditorFeedback,
} from "./EditorFeedback";

type OperationStatusEnvelope = Extract<
  NativeToEditorEnvelope,
  { type: "operationStatus" }
>;

type FeedbackHarnessHandle = {
  receive(message: OperationStatusEnvelope): void;
};

const FeedbackHarness = forwardRef<FeedbackHarnessHandle>(function FeedbackHarness(_, ref) {
  const feedback = useEditorFeedback();
  useImperativeHandle(ref, () => ({ receive: feedback.receive }), [feedback.receive]);
  return <EditorFeedback state={feedback.state} />;
});

function status(
  requestId: string,
  payload: OperationStatusEnvelope["payload"],
): OperationStatusEnvelope {
  return {
    protocolVersion: 1,
    requestId,
    type: "operationStatus",
    payload,
  };
}

function renderFeedback() {
  const ref = createRef<FeedbackHarnessHandle>();
  const view = render(<FeedbackHarness ref={ref} />);
  return {
    ...view,
    receive(message: OperationStatusEnvelope) {
      act(() => {
        if (!ref.current) throw new Error("Feedback harness is not mounted");
        ref.current.receive(message);
      });
    },
  };
}

function advance(milliseconds: number): void {
  act(() => vi.advanceTimersByTime(milliseconds));
}

describe("EditorFeedback", () => {
  beforeEach(() => {
    vi.useFakeTimers();
  });

  afterEach(() => {
    cleanup();
    vi.clearAllTimers();
    vi.useRealTimers();
  });

  it("starts with one real, empty polite status region", () => {
    renderFeedback();

    const output = screen.getByRole("status");
    expect(output.tagName).toBe("OUTPUT");
    expect(output.getAttribute("aria-live")).toBe("polite");
    expect(output.textContent).toBe("");
  });

  it.each([
    ["save", "Saving…"],
    ["export", "Exporting…"],
  ] as const)("shows %s progress only at the exact 150 ms boundary", (operation, message) => {
    const view = renderFeedback();
    view.receive(status("11111111-1111-4111-8111-111111111111", {
      operation,
      phase: "started",
    }));

    advance(149);
    expect(screen.queryByText(message)).toBeNull();
    expect(screen.getByRole("status").textContent).toBe("");

    advance(1);
    expect(screen.getByText(message)).toBeTruthy();
  });

  it.each([
    ["save", { operation: "save", phase: "completed" } as const, "Saved"],
    [
      "export",
      { operation: "export", phase: "completed", displayName: "Capture.png" } as const,
      "Exported Capture.png",
    ],
  ] as const)("never flashes %s progress after a fast completion", (operation, terminal, message) => {
    const view = renderFeedback();
    const requestId = "22222222-2222-4222-8222-222222222222";
    view.receive(status(requestId, { operation, phase: "started" }));
    advance(149);
    view.receive(status(requestId, terminal));

    expect(screen.getByText(message)).toBeTruthy();
    expect(screen.queryByText(operation === "save" ? "Saving…" : "Exporting…")).toBeNull();
    advance(1);
    expect(screen.queryByText(operation === "save" ? "Saving…" : "Exporting…")).toBeNull();
  });

  it("shows a completed save for exactly 1500 ms", () => {
    const view = renderFeedback();
    const requestId = "33333333-3333-4333-8333-333333333333";
    view.receive(status(requestId, { operation: "save", phase: "started" }));
    view.receive(status(requestId, { operation: "save", phase: "completed" }));

    expect(screen.getByText("Saved")).toBeTruthy();
    advance(1499);
    expect(screen.getByText("Saved")).toBeTruthy();
    advance(1);
    expect(screen.queryByText("Saved")).toBeNull();
    expect(screen.getByRole("status").textContent).toBe("");
  });

  it("shows a superseded save for exactly 2000 ms", () => {
    const view = renderFeedback();
    const requestId = "44444444-4444-4444-8444-444444444444";
    view.receive(status(requestId, { operation: "save", phase: "started" }));
    view.receive(status(requestId, { operation: "save", phase: "superseded" }));

    expect(screen.getByText("New changes still need saving")).toBeTruthy();
    advance(1999);
    expect(screen.getByText("New changes still need saving")).toBeTruthy();
    advance(1);
    expect(screen.queryByText("New changes still need saving")).toBeNull();
  });

  it("renders the native export display name as plain React text for exactly 1500 ms", () => {
    const view = renderFeedback();
    const requestId = "55555555-5555-4555-8555-555555555555";
    view.receive(status(requestId, { operation: "export", phase: "started" }));
    view.receive(status(requestId, {
      operation: "export",
      phase: "completed",
      displayName: "Capture <b>final</b>.png",
    }));

    const output = screen.getByRole("status");
    expect(output.textContent).toBe("Exported Capture <b>final</b>.png");
    expect(output.querySelector("b")).toBeNull();
    advance(1499);
    expect(output.textContent).toBe("Exported Capture <b>final</b>.png");
    advance(1);
    expect(output.textContent).toBe("");
  });

  it.each(["cancelled", "failed"] as const)(
    "clears a %s operation immediately without web error copy",
    (phase) => {
      const view = renderFeedback();
      const requestId = "66666666-6666-4666-8666-666666666666";
      view.receive(status(requestId, { operation: "export", phase: "started" }));
      advance(150);
      expect(screen.getByText("Exporting…")).toBeTruthy();

      view.receive(status(requestId, { operation: "export", phase }));

      const output = screen.getByRole("status");
      expect(output.textContent).toBe("");
      expect(output.textContent).not.toContain("error");
      advance(1500);
      expect(output.textContent).toBe("");
    },
  );

  it("ignores stale terminal IDs without clearing or replacing the current request", () => {
    const view = renderFeedback();
    const staleRequestId = "77777777-7777-4777-8777-777777777777";
    const currentRequestId = "88888888-8888-4888-8888-888888888888";
    view.receive(status(staleRequestId, { operation: "save", phase: "started" }));
    view.receive(status(currentRequestId, { operation: "export", phase: "started" }));
    advance(150);
    expect(screen.getByText("Exporting…")).toBeTruthy();

    view.receive(status(staleRequestId, { operation: "save", phase: "completed" }));
    expect(screen.getByText("Exporting…")).toBeTruthy();
    expect(screen.queryByText("Saved")).toBeNull();

    view.receive(status(currentRequestId, {
      operation: "export",
      phase: "completed",
      displayName: "Current.png",
    }));
    expect(screen.getByText("Exported Current.png")).toBeTruthy();
  });

  it("lets a new start clear an old toast and invalidate its timer", () => {
    const view = renderFeedback();
    const oldRequestId = "99999999-9999-4999-8999-999999999999";
    const newRequestId = "AAAAAAAA-AAAA-4AAA-8AAA-AAAAAAAAAAAA";
    view.receive(status(oldRequestId, { operation: "save", phase: "started" }));
    view.receive(status(oldRequestId, { operation: "save", phase: "completed" }));
    expect(screen.getByText("Saved")).toBeTruthy();
    advance(1000);

    view.receive(status(newRequestId, { operation: "export", phase: "started" }));
    expect(screen.queryByText("Saved")).toBeNull();
    expect(screen.getByRole("status").textContent).toBe("");
    advance(150);
    expect(screen.getByText("Exporting…")).toBeTruthy();
    advance(350);
    expect(screen.getByText("Exporting…")).toBeTruthy();
  });

  it("clears owned timers on unmount without a late update", () => {
    const view = renderFeedback();
    view.receive(status("BBBBBBBB-BBBB-4BBB-8BBB-BBBBBBBBBBBB", {
      operation: "save",
      phase: "started",
    }));
    expect(vi.getTimerCount()).toBe(1);

    view.unmount();

    expect(vi.getTimerCount()).toBe(0);
    advance(2000);
    expect(screen.queryByRole("status")).toBeNull();
  });
});
