import { useEffect, useRef, type KeyboardEvent as ReactKeyboardEvent } from "react";

import {
  SHORTCUT_GROUPS,
  SHORTCUT_REGISTRY,
} from "../input/shortcutRegistry";

export function ShortcutHelpDialog({ onClose }: { onClose: () => void }) {
  const dialogRef = useRef<HTMLDivElement>(null);
  const closeButtonRef = useRef<HTMLButtonElement>(null);
  const previousFocusRef = useRef<HTMLElement | null>(
    document.activeElement instanceof HTMLElement
      ? document.activeElement
      : null,
  );

  useEffect(() => {
    closeButtonRef.current?.focus();
    return () => {
      previousFocusRef.current?.focus();
    };
  }, []);

  const trapFocus = (event: ReactKeyboardEvent<HTMLDivElement>) => {
    if (event.key === "Escape" || event.code === "Escape") {
      event.preventDefault();
      event.stopPropagation();
      onClose();
      return;
    }
    if (event.key !== "Tab" && event.code !== "Tab") return;

    const focusable = Array.from(
      dialogRef.current?.querySelectorAll<HTMLElement>(
        "button:not([disabled]), [href], input:not([disabled]), select:not([disabled]), textarea:not([disabled]), [tabindex]:not([tabindex='-1'])",
      ) ?? [],
    );
    if (focusable.length === 0) return;

    const first = focusable[0];
    const last = focusable.at(-1)!;
    if (
      focusable.length === 1
      || (event.shiftKey && document.activeElement === first)
      || (!event.shiftKey && document.activeElement === last)
    ) {
      event.preventDefault();
      (event.shiftKey ? last : first).focus();
    }
  };

  return (
    <div className="shortcut-help-backdrop">
      <div
        ref={dialogRef}
        className="shortcut-help-dialog"
        role="dialog"
        aria-modal="true"
        aria-labelledby="shortcut-help-title"
        onKeyDown={trapFocus}
      >
        <header>
          <h2 id="shortcut-help-title">Keyboard Shortcuts</h2>
          <button
            ref={closeButtonRef}
            type="button"
            aria-label="Close keyboard shortcuts"
            onClick={onClose}
          >
            ×
          </button>
        </header>
        <div className="shortcut-help-groups">
          {SHORTCUT_GROUPS.map((group) => (
            <section key={group} aria-labelledby={`shortcut-group-${slug(group)}`}>
              <h3 id={`shortcut-group-${slug(group)}`}>{group}</h3>
              <dl>
                {SHORTCUT_REGISTRY
                  .filter((entry) => entry.group === group)
                  .map((entry) => (
                    <div key={entry.id}>
                      <dt>{entry.label}</dt>
                      <dd aria-label={entry.displayKeys.join(" ")}>
                        {entry.displayKeys.map((key, index) => (
                          <kbd key={`${entry.id}-${key}-${index}`}>{key}</kbd>
                        ))}
                      </dd>
                    </div>
                  ))}
              </dl>
            </section>
          ))}
        </div>
      </div>
    </div>
  );
}

function slug(value: string): string {
  return value.toLowerCase().replaceAll(" ", "-");
}
