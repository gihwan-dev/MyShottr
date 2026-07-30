import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";

const captureVisibleTab = vi.fn();
const sendNativeMessage = vi.fn();
const setBadgeText = vi.fn();
const setTitle = vi.fn();
const onClickedAddListener = vi.fn();
const onCommandAddListener = vi.fn();

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
    sendNativeMessage.mockResolvedValue({ accepted: true });
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
      title: "MyShottr capture failed: HOST_UNAVAILABLE",
    });
    expect(JSON.stringify(setTitle.mock.calls)).not.toContain("host not found");
  });
});
