import type { CaptureMessage } from "./captureVisibleViewport";
import { CaptureActionError } from "./status";

const NATIVE_HOST_NAME = "com.myshottr.capture";

type SendNativeMessageOperation = (
  hostName: string,
  message: CaptureMessage,
) => Promise<unknown>;

let sendNativeMessage: SendNativeMessageOperation = (hostName, message) =>
  chrome.runtime.sendNativeMessage(hostName, message);

export async function sendCaptureToNativeHost(
  message: CaptureMessage,
): Promise<void> {
  try {
    await sendNativeMessage(NATIVE_HOST_NAME, message);
  } catch {
    throw new CaptureActionError("HOST_UNAVAILABLE");
  }
}

export function setSendNativeMessageForTesting(
  operation: SendNativeMessageOperation,
): void {
  sendNativeMessage = operation;
}
