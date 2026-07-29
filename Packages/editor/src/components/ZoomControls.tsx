export function ZoomControls({ zoom, onChange }: { zoom: number; onChange: (zoom: number) => void }) {
  const update = (next: number) => {
    if (!Number.isFinite(next) || next <= 0) {
      throw new Error("Zoom must be a positive finite number");
    }
    onChange(Number(next.toFixed(2)));
  };

  return (
    <div className="zoom-controls" aria-label="Canvas zoom controls">
      <button type="button" aria-label="Zoom out" onClick={() => update(Math.max(0.1, zoom - 0.1))}>−</button>
      <output aria-label="Zoom level">{Math.round(zoom * 100)}%</output>
      <button type="button" aria-label="Zoom in" onClick={() => update(zoom + 0.1)}>+</button>
      <button type="button" aria-label="Reset zoom" onClick={() => update(1)}>Reset</button>
    </div>
  );
}
