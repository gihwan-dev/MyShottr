import type { CaptureMessage } from "./captureVisibleViewport";
import { CaptureActionError } from "./status";

const NATIVE_HOST_NAME = "com.myshottr.capture";

export async function sendCaptureToNativeHost(
  message: CaptureMessage,
): Promise<void> {
  try {
    await chrome.runtime.sendNativeMessage(NATIVE_HOST_NAME, message);
  } catch {
    throw new CaptureActionError("HOST_UNAVAILABLE");
  }
}
