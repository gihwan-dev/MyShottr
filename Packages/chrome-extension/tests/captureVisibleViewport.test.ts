import { beforeEach, describe, expect, it, vi } from "vitest";

import { captureVisibleViewport } from "../src/captureVisibleViewport";

const captureVisibleTab = vi.fn();

describe("captureVisibleViewport", () => {
  beforeEach(() => {
    captureVisibleTab.mockReset();
    vi.stubGlobal("chrome", {
      tabs: {
        captureVisibleTab,
      },
    });
  });

  it("captures the active tab as PNG", async () => {
    captureVisibleTab.mockResolvedValue("data:image/png;base64,iVBORw0KGgo=");

    await expect(captureVisibleViewport()).resolves.toEqual({
      protocolVersion: 1,
      type: "capture",
      captureMode: "visibleViewport",
      mimeType: "image/png",
      dataBase64: "iVBORw0KGgo=",
    });
    expect(captureVisibleTab).toHaveBeenCalledWith({ format: "png" });
  });

  it.each([
    ["a non-PNG data URL", "data:image/jpeg;base64,aGVsbG8="],
    ["an empty base64 body", "data:image/png;base64,"],
  ])("rejects %s", async (_caseName, dataUrl) => {
    captureVisibleTab.mockResolvedValue(dataUrl);

    await expect(captureVisibleViewport()).rejects.toMatchObject({
      code: "INVALID_CAPTURE_DATA",
    });
  });

  it("rejects a PNG whose estimated decoded size exceeds 45 MiB", async () => {
    const oversizedBase64 = "A".repeat(62_914_564);
    captureVisibleTab.mockResolvedValue(`data:image/png;base64,${oversizedBase64}`);

    await expect(captureVisibleViewport()).rejects.toMatchObject({
      code: "CAPTURE_TOO_LARGE",
    });
  });
});
