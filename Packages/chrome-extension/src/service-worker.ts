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
export type BrowserCaptureRequest = {
  mode: BrowserCaptureMode;
};

export async function handleCaptureRequest(request: unknown): Promise<void> {
  const { mode } = parseCaptureRequest(request);
  switch (mode) {
    case "fullPage":
      throw new CaptureActionError("UNSUPPORTED_CAPTURE_MODE");
    case "visibleViewport":
      break;
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
  void handleCaptureRequest({ mode: "visibleViewport" }).catch(
    () => undefined,
  );
}

chrome.action.onClicked.addListener(startCaptureAction);
chrome.commands.onCommand.addListener((command) => {
  if (command === "capture-visible-viewport") startCaptureAction();
});

if (__INKBEAM_E2E__) {
  installE2ETestSeam(handleCaptureRequest);
}

function parseCaptureRequest(request: unknown): BrowserCaptureRequest {
  if (
    typeof request !== "object"
    || request === null
    || Array.isArray(request)
    || Object.keys(request).length !== 1
    || !("mode" in request)
    || (request.mode !== "visibleViewport" && request.mode !== "fullPage")
  ) {
    throw new CaptureActionError("UNSUPPORTED_CAPTURE_MODE");
  }
  return { mode: request.mode };
}
