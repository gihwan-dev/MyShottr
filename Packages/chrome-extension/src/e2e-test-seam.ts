import {
  setCaptureVisibleTabForTesting,
  type CaptureMessage,
} from "./captureVisibleViewport";
import { setSendNativeMessageForTesting } from "./nativeMessaging";

const TEST_PNG_DATA_URL =
  "data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII=";
const DEFAULT_NATIVE_CAPTURE_REPLY = {
  ok: true,
  captureId: "12345678-1234-1234-1234-123456789ABC",
} as const;

type TestSeamSnapshot = {
  captureVisibleTabInvocationCount: number;
  nativeMessageInvocationCount: number;
};

type HandleCaptureRequest = (request: unknown) => Promise<void>;

export function installE2ETestSeam(
  handleCaptureRequest: HandleCaptureRequest,
): void {
  let captureVisibleTabInvocationCount = 0;
  let nativeMessageInvocationCount = 0;
  let nextNativeReply: unknown = DEFAULT_NATIVE_CAPTURE_REPLY;

  const snapshot = (): TestSeamSnapshot => ({
    captureVisibleTabInvocationCount,
    nativeMessageInvocationCount,
  });

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
    const reply = nextNativeReply;
    nextNativeReply = DEFAULT_NATIVE_CAPTURE_REPLY;
    return reply;
  });

  Object.defineProperty(globalThis, "__inkbeamE2E", {
    configurable: false,
    enumerable: false,
    writable: false,
    value: {
      async handleCaptureRequest(request: unknown): Promise<TestSeamSnapshot> {
        await handleCaptureRequest(request);
        return snapshot();
      },
      setNextNativeReply(reply: unknown): void {
        nextNativeReply = reply;
      },
      snapshot(): TestSeamSnapshot {
        return snapshot();
      },
    },
  });
}

function assertNativeMessage(
  hostName: string,
  message: CaptureMessage,
): void {
  if (
    hostName !== "dev.gihwan.inkbeam.capture"
    || message.protocolVersion !== 1
    || message.type !== "capture"
    || message.captureMode !== "visibleViewport"
    || message.mimeType !== "image/png"
  ) {
    throw new Error("E2E seam received an invalid native capture message");
  }
}
