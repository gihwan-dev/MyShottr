export type CaptureErrorCode =
  | "CAPTURE_FAILED"
  | "CAPTURE_TOO_LARGE"
  | "HOST_UNAVAILABLE"
  | "INVALID_CAPTURE_DATA"
  | "UNSUPPORTED_CAPTURE_MODE";

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
    chrome.action.setTitle({ title: `MyShottr capture failed: ${code}` }),
  ]);
  scheduleBadgeClear();
}

function scheduleBadgeClear(): void {
  setTimeout(() => {
    void chrome.action.setBadgeText({ text: "" });
  }, 3_000);
}
