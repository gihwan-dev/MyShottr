import { useEffect, useRef, useState } from "react";
import { TEXT_LINE_HEIGHT } from "../canvas/renderingConstants";
import type {
  TextEditResult,
  TextEditSession,
} from "../interaction/textEditSession";
import { textEditPresentation } from "../interaction/textEditSession";

export function TextEditorOverlay({
  session,
  zoom,
  pan,
  onResult,
}: {
  session: TextEditSession;
  zoom: number;
  pan: { x: number; y: number };
  onResult: (result: TextEditResult) => void;
}) {
  const [value, setValue] = useState(session.initialText);
  const ref = useRef<HTMLTextAreaElement>(null);
  const completed = useRef(false);
  const presentation = textEditPresentation(session);

  useEffect(() => {
    ref.current?.focus();
    ref.current?.select();
  }, []);

  const commit = () => {
    if (completed.current) return;
    completed.current = true;
    onResult({ type: "commit", text: value });
  };
  const cancel = () => {
    if (completed.current) return;
    completed.current = true;
    onResult({ type: "cancel" });
  };

  return (
    <textarea
      ref={ref}
      aria-label="Edit annotation text"
      value={value}
      style={{
        position: "absolute",
        left: pan.x + presentation.x * zoom,
        top: pan.y + presentation.y * zoom,
        width: Math.max(48, presentation.width * zoom),
        minHeight: Math.max(32, presentation.height * zoom),
        fontSize: presentation.fontSize * zoom,
        lineHeight: TEXT_LINE_HEIGHT,
        color: presentation.color,
        transform: `rotate(${presentation.rotation}deg)`,
        transformOrigin: "top left",
      }}
      onChange={(event) => setValue(event.target.value)}
      onBlur={commit}
      onKeyDown={(event) => {
        if (event.key === "Escape") {
          event.preventDefault();
          cancel();
        } else if (event.key === "Enter" && event.metaKey) {
          event.preventDefault();
          commit();
        }
      }}
    />
  );
}
