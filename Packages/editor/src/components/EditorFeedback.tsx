import {
  useCallback,
  useEffect,
  useRef,
  useState,
} from "react";

export type EditorFeedbackStatus =
  | { operation: "save" | "export"; phase: "started" }
  | { operation: "save"; phase: "completed" }
  | { operation: "save"; phase: "superseded" }
  | { operation: "export"; phase: "completed"; displayName: string }
  | { operation: "save" | "export"; phase: "cancelled" | "failed" };

export type EditorFeedbackEvent = {
  requestId: string;
  status: EditorFeedbackStatus;
};

export type FeedbackState =
  | { kind: "idle" }
  | {
      kind: "pending";
      requestId: string;
      operation: "save" | "export";
      progressVisible: boolean;
    }
  | {
      kind: "toast";
      requestId: string;
      message: string;
    };

const idleFeedback: FeedbackState = { kind: "idle" };

export function useEditorFeedback(): {
  state: FeedbackState;
  receive(event: EditorFeedbackEvent): void;
} {
  const [state, setState] = useState<FeedbackState>(idleFeedback);
  const stateRef = useRef<FeedbackState>(idleFeedback);
  const progressTimerRef = useRef<number | undefined>(undefined);
  const toastTimerRef = useRef<number | undefined>(undefined);

  const commit = useCallback((next: FeedbackState) => {
    stateRef.current = next;
    setState(next);
  }, []);

  const clearProgressTimer = useCallback(() => {
    if (progressTimerRef.current === undefined) return;
    window.clearTimeout(progressTimerRef.current);
    progressTimerRef.current = undefined;
  }, []);

  const clearToastTimer = useCallback(() => {
    if (toastTimerRef.current === undefined) return;
    window.clearTimeout(toastTimerRef.current);
    toastTimerRef.current = undefined;
  }, []);

  const clearTimers = useCallback(() => {
    clearProgressTimer();
    clearToastTimer();
  }, [clearProgressTimer, clearToastTimer]);

  const receive = useCallback((event: EditorFeedbackEvent) => {
    const { requestId, status } = event;
    if (status.phase === "started") {
      clearTimers();
      commit({
        kind: "pending",
        requestId,
        operation: status.operation,
        progressVisible: false,
      });
      progressTimerRef.current = window.setTimeout(() => {
        progressTimerRef.current = undefined;
        const current = stateRef.current;
        if (current.kind !== "pending" || current.requestId !== requestId) return;
        commit({ ...current, progressVisible: true });
      }, 150);
      return;
    }

    const current = stateRef.current;
    if (current.kind !== "pending" || current.requestId !== requestId) return;
    clearProgressTimer();

    let messageText: string;
    let duration: number;
    if (status.phase === "completed") {
      messageText = status.operation === "save"
        ? "Saved"
        : `Exported ${status.displayName}`;
      duration = 1500;
    } else if (status.phase === "superseded") {
      messageText = "New changes still need saving";
      duration = 2000;
    } else {
      commit(idleFeedback);
      return;
    }
    commit({ kind: "toast", requestId, message: messageText });
    toastTimerRef.current = window.setTimeout(() => {
      toastTimerRef.current = undefined;
      const latest = stateRef.current;
      if (latest.kind !== "toast" || latest.requestId !== requestId) return;
      commit(idleFeedback);
    }, duration);
  }, [clearProgressTimer, clearTimers, commit]);

  useEffect(() => clearTimers, [clearTimers]);

  return { state, receive };
}

export function EditorFeedback({ state }: { state: FeedbackState }) {
  const message = state.kind === "pending"
    ? state.progressVisible
      ? state.operation === "save" ? "Saving…" : "Exporting…"
      : ""
    : state.kind === "toast"
      ? state.message
      : "";

  return (
    <output
      className="editor-feedback"
      role="status"
      aria-live="polite"
    >
      {message}
    </output>
  );
}
