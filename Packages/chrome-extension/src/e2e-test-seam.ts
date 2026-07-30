import {
  setCaptureVisibleTabForTesting,
  type CaptureMessage,
} from "./captureVisibleViewport";
import { setSendNativeMessageForTesting } from "./nativeMessaging";
import type { BrowserCaptureMode } from "./service-worker";

const TEST_PNG_DATA_URL =
  "data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII=";

type TestSeamSnapshot = {
  captureVisibleTabInvocationCount: number;
  nativeMessageInvocationCount: number;
};

type RunCaptureAction = (mode?: BrowserCaptureMode) => Promise<void>;

export function installE2ETestSeam(runCaptureAction: RunCaptureAction): void {
  let captureVisibleTabInvocationCount = 0;
  let nativeMessageInvocationCount = 0;

  setCaptureVisibleTabForTesting(async (options) => {
    if (options.format !== "png") {
      throw new Error("E2E seam accepts only PNG viewport capture");
    }
    captureVisibleTabInvocationCount += 1;
    return TEST_PNG_DATA_URL;
  });
  setSendNativeMessageForTesting(async (hostName, message) => {
    assertNativeMessage(hostName, message);
    nativeMessageInvocationCount += 1;
    return { ok: true };
  });

  Object.defineProperty(globalThis, "__myshottrE2E", {
    configurable: false,
    enumerable: false,
    writable: false,
    value: {
      async runCaptureAction(): Promise<TestSeamSnapshot> {
        await runCaptureAction();
        return {
          captureVisibleTabInvocationCount,
          nativeMessageInvocationCount,
        };
      },
    },
  });
}

function assertNativeMessage(
  hostName: string,
  message: CaptureMessage,
): void {
  if (
    hostName !== "com.myshottr.capture"
    || message.protocolVersion !== 1
    || message.type !== "capture"
    || message.captureMode !== "visibleViewport"
    || message.mimeType !== "image/png"
  ) {
    throw new Error("E2E seam received an invalid native capture message");
  }
}
