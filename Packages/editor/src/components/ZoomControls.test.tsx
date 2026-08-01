import { cleanup, fireEvent, render, screen } from "@testing-library/react";
import { afterEach, describe, expect, it, vi } from "vitest";

import { ZoomControls } from "./ZoomControls";

afterEach(cleanup);

describe("ZoomControls", () => {
  it("reports the controller zoom without calculating a new value", () => {
    render(<ZoomControls zoom={2.345} onIntent={() => {}} />);

    expect(screen.getByRole("status", { name: "Zoom level" }).textContent)
      .toBe("235%");
  });

  it("emits semantic zoom and fit intents", () => {
    const onIntent = vi.fn();
    render(<ZoomControls zoom={1} onIntent={onIntent} />);

    fireEvent.click(screen.getByRole("button", { name: "Zoom out" }));
    fireEvent.click(screen.getByRole("button", { name: "Zoom in" }));
    fireEvent.click(screen.getByRole("button", { name: "100%" }));
    fireEvent.click(screen.getByRole("button", { name: "Fit Image" }));
    fireEvent.click(screen.getByRole("button", { name: "Fit Selection" }));

    expect(onIntent.mock.calls.map(([intent]) => intent)).toEqual([
      { type: "zoomOut" },
      { type: "zoomIn" },
      { type: "zoom100" },
      { type: "fitImage" },
      { type: "fitSelection" },
    ]);
  });
});
