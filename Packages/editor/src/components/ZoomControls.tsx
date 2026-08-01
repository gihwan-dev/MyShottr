export type ZoomControlIntent =
  | { type: "zoomIn" }
  | { type: "zoomOut" }
  | { type: "zoom100" }
  | { type: "fitImage" }
  | { type: "fitSelection" };

export function ZoomControls({
  zoom,
  onIntent,
}: {
  zoom: number;
  onIntent: (intent: ZoomControlIntent) => void;
}) {
  return (
    <div className="zoom-controls" aria-label="Canvas zoom controls">
      <button type="button" aria-label="Zoom out" title="Zoom out" onClick={() => onIntent({ type: "zoomOut" })}>−</button>
      <output role="status" aria-label="Zoom level">{Math.round(zoom * 100)}%</output>
      <button type="button" aria-label="Zoom in" title="Zoom in" onClick={() => onIntent({ type: "zoomIn" })}>+</button>
      <button type="button" aria-label="100%" title="100%" onClick={() => onIntent({ type: "zoom100" })}>100%</button>
      <button type="button" aria-label="Fit Image" title="Fit Image" onClick={() => onIntent({ type: "fitImage" })}>Fit Image</button>
      <button type="button" aria-label="Fit Selection" title="Fit Selection" onClick={() => onIntent({ type: "fitSelection" })}>Fit Selection</button>
    </div>
  );
}
