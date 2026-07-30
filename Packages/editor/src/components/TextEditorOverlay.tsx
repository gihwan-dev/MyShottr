import { useEffect, useRef, useState } from "react";
import type { TextElement } from "../model/elements";
import { TEXT_LINE_HEIGHT } from "../canvas/renderingConstants";

export function TextEditorOverlay({
  element,
  zoom,
  pan,
  onCommit,
  onCancel,
}: {
  element: TextElement;
  zoom: number;
  pan: { x: number; y: number };
  onCommit: (text: string) => void;
  onCancel: () => void;
}) {
  const [value, setValue] = useState(element.text);
  const ref = useRef<HTMLTextAreaElement>(null);
  const completed = useRef(false);

  useEffect(() => {
    ref.current?.focus();
    ref.current?.select();
  }, []);

  const commit = () => {
    if (completed.current) return;
    completed.current = true;
    onCommit(value);
  };
  const cancel = () => {
    if (completed.current) return;
    completed.current = true;
    onCancel();
  };

  return (
    <textarea
      ref={ref}
      aria-label="Edit annotation text"
      value={value}
      style={{
        position: "absolute",
        left: pan.x + element.x * zoom,
        top: pan.y + element.y * zoom,
        width: Math.max(48, element.width * zoom),
        minHeight: Math.max(32, element.height * zoom),
        fontSize: element.fontSize * zoom,
        lineHeight: TEXT_LINE_HEIGHT,
        color: element.color,
        transform: `rotate(${element.rotation}deg)`,
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
