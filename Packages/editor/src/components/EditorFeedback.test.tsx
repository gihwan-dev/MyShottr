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

import {
  EditorFeedback,
  type EditorFeedbackEvent,
  useEditorFeedback,
} from "./EditorFeedback";

type FeedbackHarnessHandle = {
  receive(event: EditorFeedbackEvent): void;
};

const FeedbackHarness = forwardRef<FeedbackHarnessHandle>(function FeedbackHarness(_, ref) {
  const feedback = useEditorFeedback();
  useImperativeHandle(ref, () => ({ receive: feedback.receive }), [feedback.receive]);
  return <EditorFeedback state={feedback.state} />;
});

function status(
  requestId: string,
  feedbackStatus: EditorFeedbackEvent["status"],
): EditorFeedbackEvent {
  return {
    requestId,
    status: feedbackStatus,
  };
}

function renderFeedback() {
  const ref = createRef<FeedbackHarnessHandle>();
  const view = render(<FeedbackHarness ref={ref} />);
  return {
    ...view,
    receive(event: EditorFeedbackEvent) {
      act(() => {
        if (!ref.current) throw new Error("Feedback harness is not mounted");
        ref.current.receive(event);
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

  it.each([
    ["save", "cancelled"],
    ["save", "failed"],
    ["export", "cancelled"],
    ["export", "failed"],
  ] as const)(
    "never flashes %s progress or error copy after a fast %s terminal",
    (operation, phase) => {
      const view = renderFeedback();
      const requestId = "23232323-2323-4323-8323-232323232323";
      const progress = operation === "save" ? "Saving…" : "Exporting…";
      view.receive(status(requestId, { operation, phase: "started" }));
      advance(149);
      view.receive(status(requestId, { operation, phase }));

      const output = screen.getByRole("status");
      expect(output.textContent).toBe("");
      advance(1);
      expect(output.textContent).toBe("");
      expect(screen.queryByText(progress)).toBeNull();
      advance(2000);
      expect(output.textContent).toBe("");
      expect(output.textContent).not.toContain("error");
    },
  );

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

  it.each(["pending", "toast"] as const)(
    "clears every owned %s timer on unmount without a late update",
    (timerState) => {
      const view = renderFeedback();
      const requestId = "BBBBBBBB-BBBB-4BBB-8BBB-BBBBBBBBBBBB";
      view.receive(status(requestId, {
        operation: "save",
        phase: "started",
      }));
      if (timerState === "toast") {
        view.receive(status(requestId, { operation: "save", phase: "completed" }));
        expect(screen.getByText("Saved")).toBeTruthy();
      }
      expect(vi.getTimerCount()).toBeGreaterThan(0);

      view.unmount();

      expect(vi.getTimerCount()).toBe(0);
      advance(2500);
      expect(screen.queryByRole("status")).toBeNull();
    },
  );
});
