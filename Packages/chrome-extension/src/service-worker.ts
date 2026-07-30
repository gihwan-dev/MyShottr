import { captureVisibleViewport } from "./captureVisibleViewport";
import { sendCaptureToNativeHost } from "./nativeMessaging";
import {
  CaptureActionError,
  showCaptureFailure,
  showCaptureSuccess,
  toCaptureActionError,
} from "./status";

export type BrowserCaptureMode = "visibleViewport" | "fullPage";

export async function runCaptureAction(
  mode: BrowserCaptureMode = "visibleViewport",
): Promise<void> {
  if (mode === "fullPage") {
    throw new CaptureActionError("UNSUPPORTED_CAPTURE_MODE");
  }

  try {
    const capture = await captureVisibleViewport();
    await sendCaptureToNativeHost(capture);
    await showCaptureSuccess();
  } catch (error) {
    const captureError = toCaptureActionError(error, "CAPTURE_FAILED");
    await showCaptureFailure(captureError.code);
    throw captureError;
  }
}

chrome.action.onClicked.addListener(() => void runCaptureAction());
chrome.commands.onCommand.addListener((command) => {
  if (command === "capture-visible-viewport") void runCaptureAction();
});
