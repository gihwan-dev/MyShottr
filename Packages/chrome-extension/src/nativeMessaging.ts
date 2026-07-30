import type { CaptureMessage } from "./captureVisibleViewport";
import { CaptureActionError } from "./status";

const NATIVE_HOST_NAME = "com.myshottr.capture";
const CANONICAL_UUID =
  /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

export const NATIVE_HOST_ERROR_CODES = [
  "INVALID_MESSAGE",
  "UNSUPPORTED_CAPTURE_MODE",
  "INVALID_IMAGE",
  "IMAGE_TOO_LARGE",
  "STAGING_FAILED",
  "APP_ACTIVATION_FAILED",
] as const;

export type NativeHostErrorCode = (typeof NATIVE_HOST_ERROR_CODES)[number];

export type NativeCaptureReply =
  | { ok: true; captureId: string }
  | { ok: false; code: NativeHostErrorCode };

export type NativeCaptureSuccessReply = Extract<
  NativeCaptureReply,
  { ok: true }
>;

type SendNativeMessageOperation = (
  hostName: string,
  message: CaptureMessage,
) => Promise<unknown>;

let sendNativeMessage: SendNativeMessageOperation = (hostName, message) =>
  chrome.runtime.sendNativeMessage(hostName, message);

export async function sendCaptureToNativeHost(
  message: CaptureMessage,
): Promise<NativeCaptureSuccessReply> {
  let untrustedReply: unknown;
  try {
    untrustedReply = await sendNativeMessage(NATIVE_HOST_NAME, message);
  } catch {
    throw new CaptureActionError("HOST_UNAVAILABLE");
  }

  const reply = parseNativeCaptureReply(untrustedReply);
  if (!reply.ok) {
    throw new CaptureActionError(reply.code);
  }
  return reply;
}

export function setSendNativeMessageForTesting(
  operation: SendNativeMessageOperation,
): void {
  sendNativeMessage = operation;
}

function parseNativeCaptureReply(value: unknown): NativeCaptureReply {
  if (!isRecord(value)) {
    throw new CaptureActionError("INVALID_HOST_RESPONSE");
  }

  const keys = Object.keys(value);
  if (
    value.ok === true
    && keys.length === 2
    && keys.includes("ok")
    && keys.includes("captureId")
    && typeof value.captureId === "string"
    && CANONICAL_UUID.test(value.captureId)
  ) {
    return {
      ok: true,
      captureId: value.captureId,
    };
  }

  if (
    value.ok === false
    && keys.length === 2
    && keys.includes("ok")
    && keys.includes("code")
    && typeof value.code === "string"
    && isNativeHostErrorCode(value.code)
  ) {
    return {
      ok: false,
      code: value.code,
    };
  }

  throw new CaptureActionError("INVALID_HOST_RESPONSE");
}

function isRecord(value: unknown): value is Record<string, unknown> {
  return typeof value === "object" && value !== null && !Array.isArray(value);
}

function isNativeHostErrorCode(value: string): value is NativeHostErrorCode {
  return (NATIVE_HOST_ERROR_CODES as readonly string[]).includes(value);
}
