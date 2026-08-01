import { useEffect, useId, useRef, type CSSProperties, type KeyboardEvent } from "react";

import type {
  ContextRailField,
  ContextRailModel,
  RailPropertyKey,
  RailPropertyValue,
  RailPropertyValueByKey,
} from "./contextRailModel";

type SetPropertyIntent<T extends "setDefaultProperty" | "setSelectionProperty"> = {
  [K in RailPropertyKey]: {
    type: T;
    property: K;
    value: RailPropertyValueByKey[K];
  };
}[RailPropertyKey];

export type ContextRailIntent =
  | SetPropertyIntent<"setDefaultProperty">
  | SetPropertyIntent<"setSelectionProperty">
  | { type: "previewSelectionOpacity"; value: RailPropertyValueByKey["opacity"] }
  | { type: "commitSelectionOpacity"; value: RailPropertyValueByKey["opacity"] }
  | { type: "cancelSelectionOpacity" }
  | { type: "bringForward" }
  | { type: "sendBackward" }
  | { type: "duplicate" }
  | { type: "delete" };

export function ContextRail({
  model,
  onIntent,
}: {
  model: ContextRailModel;
  onIntent: (intent: ContextRailIntent) => void;
}) {
  if (model.kind === "hidden") return null;
  const isSelection = model.kind === "single" || model.kind === "multi";

  return (
    <aside className="context-rail" aria-label="Context Rail">
      <header className="context-rail-header">
        <h2>{model.title}</h2>
        {model.fixedValue && <p className="context-rail-fixed">{model.fixedValue}</p>}
      </header>
      <div className="context-rail-fields">
        {model.fields.color && (
          <RadioField
            field={model.fields.color}
            property="color"
            isSelection={isSelection}
            onIntent={onIntent}
          />
        )}
        {model.fields.fillColor && (
          <RadioField
            field={model.fields.fillColor}
            property="fillColor"
            isSelection={isSelection}
            onIntent={onIntent}
          />
        )}
        {model.fields.strokeWidth && (
          <RadioField
            field={model.fields.strokeWidth}
            property="strokeWidth"
            isSelection={isSelection}
            onIntent={onIntent}
          />
        )}
        {model.fields.roughness && (
          <RadioField
            field={model.fields.roughness}
            property="roughness"
            isSelection={isSelection}
            onIntent={onIntent}
          />
        )}
        {model.fields.textSize && (
          <RadioField
            field={model.fields.textSize}
            property="textSize"
            isSelection={isSelection}
            onIntent={onIntent}
          />
        )}
        {model.fields.opacity && (
          <OpacityField
            field={model.fields.opacity}
            gestureIdentity={opacityGestureIdentity(model, model.fields.opacity)}
            isSelection={isSelection}
            onIntent={onIntent}
          />
        )}
      </div>
      {isSelection && (
        <div className="context-rail-actions" aria-label="Selection actions">
          <ActionButton
            label="Bring Forward"
            icon="↑"
            disabled={!model.actions.canBringForward}
            onClick={() => onIntent({ type: "bringForward" })}
          />
          <ActionButton
            label="Send Backward"
            icon="↓"
            disabled={!model.actions.canSendBackward}
            onClick={() => onIntent({ type: "sendBackward" })}
          />
          <ActionButton
            label="Duplicate"
            icon="⧉"
            disabled={!model.actions.canDuplicate}
            onClick={() => onIntent({ type: "duplicate" })}
          />
          <ActionButton
            label="Delete"
            icon="×"
            disabled={!model.actions.canDelete}
            onClick={() => onIntent({ type: "delete" })}
          />
        </div>
      )}
    </aside>
  );
}

function RadioField<K extends Exclude<RailPropertyKey, "opacity">>({
  field,
  property,
  isSelection,
  onIntent,
}: {
  field: ContextRailField<K>;
  property: K;
  isSelection: boolean;
  onIntent: (intent: ContextRailIntent) => void;
}) {
  const mixedId = useId();
  const mixed = field.value.kind === "mixed";
  return (
    <fieldset className={`context-rail-field context-rail-${property}`}>
      <legend>{field.label}</legend>
      {mixed && <span className="context-rail-mixed" id={mixedId}>Mixed</span>}
      <div
        className="context-rail-options"
        role="radiogroup"
        aria-label={field.label}
        aria-describedby={mixed ? mixedId : undefined}
      >
        {field.allowedValues.map((value) => {
          const option = optionPresentation(property, value);
          const selected = field.value.kind === "single" && Object.is(field.value.value, value);
          return (
            <button
              key={option.key}
              className={`context-rail-option context-rail-option-${property}`}
              type="button"
              role="radio"
              aria-checked={selected}
              aria-label={option.label}
              title={option.label}
              style={option.style}
              onClick={() => {
                onIntent({
                  type: isSelection ? "setSelectionProperty" : "setDefaultProperty",
                  property,
                  value,
                } as ContextRailIntent);
              }}
            >
              {property === "strokeWidth" && typeof value === "number" && (
                <span
                  aria-hidden="true"
                  className="context-rail-stroke-sample"
                  style={{ borderBlockEndWidth: value }}
                />
              )}
              {option.content}
            </button>
          );
        })}
      </div>
    </fieldset>
  );
}

function OpacityField({
  field,
  gestureIdentity,
  isSelection,
  onIntent,
}: {
  field: ContextRailField<"opacity">;
  gestureIdentity: string;
  isSelection: boolean;
  onIntent: (intent: ContextRailIntent) => void;
}) {
  const mixedId = useId();
  const latestOnIntent = useRef(onIntent);
  latestOnIntent.current = onIntent;
  const gesture = useRef<{
    active: boolean;
    identity?: string;
    ignoreChangeUntilInput: boolean;
    isSelection?: boolean;
    suppressNextChange: boolean;
    value?: string;
  }>({ active: false, ignoreChangeUntilInput: false, suppressNextChange: false });
  const mixed = field.value.kind === "mixed";
  const percentages = field.allowedValues.map((value) => value * 100);
  const current = field.value.kind === "single"
    ? field.value.value * 100
    : percentages[0];
  const valueText = mixed ? "Mixed" : `${current}%`;
  const parseValue = (value: string): RailPropertyValueByKey["opacity"] => {
    const opacity = Number(value) / 100 as RailPropertyValueByKey["opacity"];
    if (!field.allowedValues.includes(opacity)) {
      throw new Error(`Opacity ${value}% is outside the shared Context Rail domain`);
    }
    return opacity;
  };
  const resetGesture = () => {
    gesture.current.active = false;
    gesture.current.identity = undefined;
    gesture.current.ignoreChangeUntilInput = true;
    gesture.current.isSelection = undefined;
    gesture.current.suppressNextChange = false;
    gesture.current.value = undefined;
  };
  const cancel = () => {
    if (!gesture.current.active) return;
    const shouldNotify = gesture.current.isSelection === true;
    resetGesture();
    if (shouldNotify) latestOnIntent.current({ type: "cancelSelectionOpacity" });
  };
  const cancelIfStale = () => {
    if (!gesture.current.active || gesture.current.identity === gestureIdentity) return false;
    cancel();
    return true;
  };
  const commit = (value: string) => {
    const opacity = parseValue(value);
    onIntent(isSelection
      ? { type: "commitSelectionOpacity", value: opacity }
      : { type: "setDefaultProperty", property: "opacity", value: opacity });
  };
  const finishGesture = (value: string) => {
    if (cancelIfStale() || !gesture.current.active) return;
    commit(gesture.current.value ?? value);
    gesture.current.active = false;
    gesture.current.identity = undefined;
    gesture.current.isSelection = undefined;
    gesture.current.suppressNextChange = true;
    gesture.current.value = undefined;
  };
  const handleEscape = (event: KeyboardEvent<HTMLInputElement>) => {
    if (event.key !== "Escape" || !isSelection || cancelIfStale() || !gesture.current.active) return;
    event.preventDefault();
    event.stopPropagation();
    cancel();
  };

  useEffect(() => {
    cancelIfStale();
  }, [gestureIdentity]);
  useEffect(() => () => {
    cancel();
  }, []);

  return (
    <fieldset className="context-rail-field context-rail-opacity">
      <legend>{field.label}</legend>
      <div className="context-rail-slider-heading">
        <output id={mixedId} className={mixed ? "context-rail-mixed" : undefined}>
          {valueText}
        </output>
      </div>
      <input
        type="range"
        aria-label={field.label}
        aria-describedby={mixed ? mixedId : undefined}
        aria-valuetext={valueText}
        min={percentages[0]}
        max={percentages.at(-1)}
        step={percentages.length > 1 ? percentages[1] - percentages[0] : 1}
        value={current}
        onInput={(event) => {
          cancelIfStale();
          gesture.current.active = true;
          gesture.current.identity = gestureIdentity;
          gesture.current.ignoreChangeUntilInput = false;
          gesture.current.isSelection = isSelection;
          gesture.current.suppressNextChange = false;
          gesture.current.value = event.currentTarget.value;
          if (isSelection) {
            onIntent({
              type: "previewSelectionOpacity",
              value: parseValue(event.currentTarget.value),
            });
          }
        }}
        onPointerUp={(event) => {
          finishGesture(event.currentTarget.value);
        }}
        onChange={(event) => {
          if (event.nativeEvent.type !== "change") return;
          if (gesture.current.ignoreChangeUntilInput) return;
          if (cancelIfStale()) return;
          if (gesture.current.suppressNextChange) {
            gesture.current.suppressNextChange = false;
            return;
          }
          gesture.current.active = false;
          commit(gesture.current.value ?? event.currentTarget.value);
          gesture.current.value = undefined;
        }}
        onPointerCancel={() => {
          if (!cancelIfStale()) cancel();
        }}
        onKeyDown={handleEscape}
        onKeyUp={(event) => {
          if (event.key === "Escape") return;
          finishGesture(event.currentTarget.value);
        }}
      />
      <div className="context-rail-slider-scale" aria-hidden="true">
        {percentages.map((percentage) => <span key={percentage}>{percentage}%</span>)}
      </div>
    </fieldset>
  );
}

function opacityGestureIdentity(
  model: Exclude<ContextRailModel, { kind: "hidden" }>,
  field: ContextRailField<"opacity">,
): string {
  return JSON.stringify(model.kind === "defaults"
    ? [model.kind, model.title, field.allowedValues]
    : [model.kind, model.selectedIds, field.allowedValues]);
}

function ActionButton({
  label,
  icon,
  disabled,
  onClick,
}: {
  label: string;
  icon: string;
  disabled: boolean;
  onClick: () => void;
}) {
  return (
    <button
      type="button"
      aria-label={label}
      title={label}
      disabled={disabled}
      onClick={onClick}
    >
      <span aria-hidden="true">{icon}</span>
    </button>
  );
}

function optionPresentation(
  property: Exclude<RailPropertyKey, "opacity">,
  value: RailPropertyValue,
): {
  key: string;
  label: string;
  content: string;
  style?: CSSProperties;
} {
  if (property === "color" || property === "fillColor") {
    if (value === null) {
      return { key: "none", label: "None", content: "None" };
    }
    if (typeof value !== "string") {
      throw new Error(`${property} requires a color value`);
    }
    return {
      key: value,
      label: COLOR_NAMES[value],
      content: COLOR_NAMES[value],
      style: { "--swatch-color": value } as CSSProperties,
    };
  }
  if (typeof value !== "number") {
    throw new Error(`${property} requires a numeric value`);
  }
  if (property === "strokeWidth") {
    return { key: String(value), label: `${value} px`, content: String(value) };
  }
  if (property === "roughness") {
    const label = ROUGHNESS_NAMES[value];
    if (!label) throw new Error(`Unknown roughness: ${value}`);
    return { key: String(value), label, content: label };
  }
  return { key: String(value), label: `${value} px`, content: String(value) };
}

const COLOR_NAMES = {
  "#000000": "Black",
  "#FF4D4F": "Red",
  "#1677FF": "Blue",
  "#FADB14": "Yellow",
} as const;

const ROUGHNESS_NAMES: Partial<Record<number, string>> = {
  0: "Clean",
  1: "Sketch",
  2: "Rough",
};
