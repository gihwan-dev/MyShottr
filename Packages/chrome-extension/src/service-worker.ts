import { captureVisibleViewport } from "./captureVisibleViewport";
import { installE2ETestSeam } from "./e2e-test-seam";
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

function startCaptureAction(): void {
  void runCaptureAction().catch(() => undefined);
}

chrome.action.onClicked.addListener(startCaptureAction);
chrome.commands.onCommand.addListener((command) => {
  if (command === "capture-visible-viewport") startCaptureAction();
});

if (__MYSHOTTR_E2E__) {
  installE2ETestSeam(runCaptureAction);
}
