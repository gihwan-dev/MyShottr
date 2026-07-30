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
  CAPTURE_FAILED: "MyShottr could not capture this page.",
  CAPTURE_TOO_LARGE: "Capture is too large for MyShottr.",
  HOST_UNAVAILABLE: "Open MyShottr once, then retry.",
  IMAGE_TOO_LARGE: "Capture is too large for MyShottr.",
  INVALID_CAPTURE_DATA: "Chrome returned invalid capture data.",
  INVALID_HOST_RESPONSE: "MyShottr returned an invalid response.",
  INVALID_IMAGE: "MyShottr could not read the captured PNG.",
  INVALID_MESSAGE: "MyShottr rejected the capture request.",
  STAGING_FAILED: "MyShottr could not import the capture.",
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
    chrome.action.setTitle({ title: "Captured visible viewport in MyShottr" }),
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
