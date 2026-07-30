import { CaptureActionError, toCaptureActionError } from "./status";

const MAX_CAPTURE_BYTES = 45 * 1024 * 1024;
const PNG_DATA_URL_PREFIX = "data:image/png;base64,";

export type CaptureMessage = {
  protocolVersion: 1;
  type: "capture";
  captureMode: "visibleViewport";
  mimeType: "image/png";
  dataBase64: string;
};

export async function captureVisibleViewport(): Promise<CaptureMessage> {
  let dataUrl: string;

  try {
    dataUrl = await chrome.tabs.captureVisibleTab({ format: "png" });
  } catch (error) {
    throw toCaptureActionError(error, "CAPTURE_FAILED");
  }

  if (!dataUrl.startsWith(PNG_DATA_URL_PREFIX)) {
    throw new CaptureActionError("INVALID_CAPTURE_DATA");
  }

  const dataBase64 = dataUrl.slice(PNG_DATA_URL_PREFIX.length);
  if (dataBase64.length === 0) {
    throw new CaptureActionError("INVALID_CAPTURE_DATA");
  }

  if (estimateDecodedByteCount(dataBase64) > MAX_CAPTURE_BYTES) {
    throw new CaptureActionError("CAPTURE_TOO_LARGE");
  }

  return {
    protocolVersion: 1,
    type: "capture",
    captureMode: "visibleViewport",
    mimeType: "image/png",
    dataBase64,
  };
}

function estimateDecodedByteCount(dataBase64: string): number {
  const paddingBytes = dataBase64.endsWith("==")
    ? 2
    : dataBase64.endsWith("=")
      ? 1
      : 0;
  return Math.floor((dataBase64.length * 3) / 4) - paddingBytes;
}
