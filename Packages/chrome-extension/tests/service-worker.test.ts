import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";

const captureVisibleTab = vi.fn();
const sendNativeMessage = vi.fn();
const setBadgeText = vi.fn();
const setTitle = vi.fn();
const onClickedAddListener = vi.fn();
const onCommandAddListener = vi.fn();
const captureId = "12345678-1234-1234-1234-123456789ABC";

async function loadServiceWorker() {
  return import("../src/service-worker");
}

describe("runCaptureAction", () => {
  beforeEach(() => {
    vi.resetModules();
    vi.useFakeTimers();
    captureVisibleTab.mockReset();
    sendNativeMessage.mockReset();
    setBadgeText.mockReset().mockResolvedValue(undefined);
    setTitle.mockReset().mockResolvedValue(undefined);
    onClickedAddListener.mockReset();
    onCommandAddListener.mockReset();
    vi.stubGlobal("chrome", {
      action: {
        onClicked: { addListener: onClickedAddListener },
        setBadgeText,
        setTitle,
      },
      commands: {
        onCommand: { addListener: onCommandAddListener },
      },
      runtime: {
        sendNativeMessage,
      },
      tabs: {
        captureVisibleTab,
      },
    });
  });

  afterEach(() => {
    vi.useRealTimers();
    vi.unstubAllGlobals();
  });

  it("rejects full-page mode before taking a viewport capture", async () => {
    const { runCaptureAction } = await loadServiceWorker();

    await expect(runCaptureAction("fullPage")).rejects.toMatchObject({
      code: "UNSUPPORTED_CAPTURE_MODE",
    });
    expect(captureVisibleTab).not.toHaveBeenCalled();
    expect(sendNativeMessage).not.toHaveBeenCalled();
  });

  it("captures once and sends one native message", async () => {
    captureVisibleTab.mockResolvedValue("data:image/png;base64,iVBORw0KGgo=");
    sendNativeMessage.mockResolvedValue({ ok: true, captureId });
    const { runCaptureAction } = await loadServiceWorker();

    await runCaptureAction();

    expect(captureVisibleTab).toHaveBeenCalledTimes(1);
    expect(sendNativeMessage).toHaveBeenCalledTimes(1);
    expect(sendNativeMessage).toHaveBeenCalledWith("com.myshottr.capture", {
      protocolVersion: 1,
      type: "capture",
      captureMode: "visibleViewport",
      mimeType: "image/png",
      dataBase64: "iVBORw0KGgo=",
    });
    expect(setBadgeText).toHaveBeenCalledWith({ text: "OK" });
    expect(setTitle).toHaveBeenCalledWith({
      title: "Captured visible viewport in MyShottr",
    });

    await vi.advanceTimersByTimeAsync(3_000);
    expect(setBadgeText).toHaveBeenLastCalledWith({ text: "" });
  });

  it.each([
    ["INVALID_MESSAGE", "MyShottr rejected the capture request."],
    [
      "UNSUPPORTED_CAPTURE_MODE",
      "Only visible viewport capture is supported.",
    ],
    ["INVALID_IMAGE", "MyShottr could not read the captured PNG."],
    ["IMAGE_TOO_LARGE", "Capture is too large for MyShottr."],
    ["STAGING_FAILED", "MyShottr could not import the capture."],
    [
      "APP_ACTIVATION_FAILED",
      "Capture saved. Open MyShottr to import.",
    ],
  ] as const)(
    "shows the bounded helper failure %s instead of reporting success",
    async (code, title) => {
      captureVisibleTab.mockResolvedValue("data:image/png;base64,iVBORw0KGgo=");
      sendNativeMessage.mockResolvedValue({
        ok: false,
        code,
      });
      const { runCaptureAction } = await loadServiceWorker();

      await expect(runCaptureAction()).rejects.toMatchObject({ code });
      expect(captureVisibleTab).toHaveBeenCalledTimes(1);
      expect(sendNativeMessage).toHaveBeenCalledTimes(1);
      expect(setBadgeText).toHaveBeenCalledWith({ text: "ERR" });
      expect(setBadgeText).not.toHaveBeenCalledWith({ text: "OK" });
      expect(setTitle).toHaveBeenCalledWith({ title });
    },
  );

  it("shows a sanitized bounded title for malformed host responses", async () => {
    captureVisibleTab.mockResolvedValue("data:image/png;base64,iVBORw0KGgo=");
    sendNativeMessage.mockResolvedValue({
      ok: false,
      code: "UNKNOWN",
      detail: "sensitive raw host detail",
    });
    const { runCaptureAction } = await loadServiceWorker();

    await expect(runCaptureAction()).rejects.toMatchObject({
      code: "INVALID_HOST_RESPONSE",
    });
    expect(captureVisibleTab).toHaveBeenCalledTimes(1);
    expect(sendNativeMessage).toHaveBeenCalledTimes(1);
    expect(setTitle).toHaveBeenCalledWith({
      title: "MyShottr returned an invalid response.",
    });
    expect(JSON.stringify(setTitle.mock.calls)).not.toContain("sensitive");
  });

  it("does not send a fallback capture when native messaging fails", async () => {
    captureVisibleTab.mockResolvedValue("data:image/png;base64,iVBORw0KGgo=");
    sendNativeMessage.mockRejectedValue(new Error("host not found"));
    const { runCaptureAction } = await loadServiceWorker();

    await expect(runCaptureAction()).rejects.toMatchObject({
      code: "HOST_UNAVAILABLE",
    });
    expect(captureVisibleTab).toHaveBeenCalledTimes(1);
    expect(sendNativeMessage).toHaveBeenCalledTimes(1);
    expect(setBadgeText).toHaveBeenCalledWith({ text: "ERR" });
    expect(setTitle).toHaveBeenCalledWith({
      title: "Open MyShottr once, then retry.",
    });
    expect(JSON.stringify(setTitle.mock.calls)).not.toContain("host not found");
  });

  it("consumes expected action-listener rejections after showing status", async () => {
    captureVisibleTab.mockResolvedValue("data:image/png;base64,iVBORw0KGgo=");
    sendNativeMessage.mockRejectedValue(new Error("host not found"));
    await loadServiceWorker();
    const onClicked = onClickedAddListener.mock.calls[0]?.[0] as
      | (() => void)
      | undefined;

    expect(onClicked).toBeTypeOf("function");
    expect(onClicked?.()).toBeUndefined();

    await vi.waitFor(() => {
      expect(setTitle).toHaveBeenCalledWith({
        title: "Open MyShottr once, then retry.",
      });
    });
    expect(captureVisibleTab).toHaveBeenCalledTimes(1);
    expect(sendNativeMessage).toHaveBeenCalledTimes(1);
  });
});
