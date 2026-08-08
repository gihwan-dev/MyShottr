import type { NativeHostErrorCode } from "./nativeMessaging";

export type CaptureErrorCode =
  | NativeHostErrorCode
  | "CAPTURE_FAILED"
  | "CAPTURE_TOO_LARGE"
  | "HOST_UNAVAILABLE"
  | "INVALID_HOST_RESPONSE"
  | "INVALID_CAPTURE_DATA"
  | "UNSUPPORTED_CAPTURE_MODE";

const FAILURE_TITLES: Record<CaptureErrorCode, string> = {
  APP_ACTIVATION_FAILED: "Capture saved. Open Inkbeam to import.",
  CAPTURE_FAILED: "Inkbeam could not capture this page.",
  CAPTURE_TOO_LARGE: "Capture is too large for Inkbeam.",
  HOST_UNAVAILABLE: "Open Inkbeam once, then retry.",
  IMAGE_TOO_LARGE: "Capture is too large for Inkbeam.",
  INVALID_CAPTURE_DATA: "Chrome returned invalid capture data.",
  INVALID_HOST_RESPONSE: "Inkbeam returned an invalid response.",
  INVALID_IMAGE: "Inkbeam could not read the captured PNG.",
  INVALID_MESSAGE: "Inkbeam rejected the capture request.",
  STAGING_FAILED: "Inkbeam could not import the capture.",
  UNSUPPORTED_CAPTURE_MODE: "Only visible viewport capture is supported.",
};

export class CaptureActionError extends Error {
  readonly code: CaptureErrorCode;

  constructor(code: CaptureErrorCode) {
    super(code);
    this.name = "CaptureActionError";
    this.code = code;
  }
}

export function toCaptureActionError(
  error: unknown,
  fallbackCode: CaptureErrorCode,
): CaptureActionError {
  return error instanceof CaptureActionError
    ? error
    : new CaptureActionError(fallbackCode);
}

export async function showCaptureSuccess(): Promise<void> {
  await Promise.all([
    chrome.action.setBadgeText({ text: "OK" }),
    chrome.action.setTitle({ title: "Captured visible viewport in Inkbeam" }),
  ]);
  scheduleBadgeClear();
}

export async function showCaptureFailure(code: CaptureErrorCode): Promise<void> {
  await Promise.all([
    chrome.action.setBadgeText({ text: "ERR" }),
    chrome.action.setTitle({ title: FAILURE_TITLES[code] }),
  ]);
  scheduleBadgeClear();
}

function scheduleBadgeClear(): void {
  setTimeout(() => {
    void chrome.action.setBadgeText({ text: "" });
  }, 3_000);
}
