import { beforeEach, describe, expect, it, vi } from "vitest";

import type { CaptureMessage } from "../src/captureVisibleViewport";
import {
  sendCaptureToNativeHost,
  setSendNativeMessageForTesting,
  type NativeHostErrorCode,
} from "../src/nativeMessaging";

const sendNativeMessage = vi.fn();
const capture: CaptureMessage = {
  protocolVersion: 1,
  type: "capture",
  captureMode: "visibleViewport",
  mimeType: "image/png",
  dataBase64: "iVBORw0KGgo=",
};
const captureId = "12345678-1234-1234-1234-123456789ABC";

describe("sendCaptureToNativeHost", () => {
  beforeEach(() => {
    sendNativeMessage.mockReset();
    setSendNativeMessageForTesting(sendNativeMessage);
  });

  it("accepts the exact success reply", async () => {
    sendNativeMessage.mockResolvedValue({ ok: true, captureId });

    await expect(sendCaptureToNativeHost(capture)).resolves.toEqual({
      ok: true,
      captureId,
    });
    expect(sendNativeMessage).toHaveBeenCalledTimes(1);
    expect(sendNativeMessage).toHaveBeenCalledWith(
      "com.myshottr.capture",
      capture,
    );
  });

  it.each<NativeHostErrorCode>([
    "INVALID_MESSAGE",
    "UNSUPPORTED_CAPTURE_MODE",
    "INVALID_IMAGE",
    "IMAGE_TOO_LARGE",
    "STAGING_FAILED",
  ])("surfaces the bounded helper failure %s", async (code) => {
    sendNativeMessage.mockResolvedValue({ ok: false, code });

    await expect(sendCaptureToNativeHost(capture)).rejects.toMatchObject({
      code,
      message: code,
    });
    expect(sendNativeMessage).toHaveBeenCalledTimes(1);
  });

  it.each([
    ["the legacy accepted response", { accepted: true }],
    ["null", null],
    ["an array", [{ ok: true, captureId }]],
    ["missing success captureId", { ok: true }],
    ["a non-string success captureId", { ok: true, captureId: 123 }],
    ["a malformed UUID", { ok: true, captureId: "not-a-uuid" }],
    ["an extra success field", { ok: true, captureId, extra: true }],
    ["missing failure code", { ok: false }],
    ["a non-string failure code", { ok: false, code: 123 }],
    ["an unknown failure code", { ok: false, code: "UNKNOWN" }],
    [
      "an extra failure field",
      { ok: false, code: "INVALID_IMAGE", detail: "raw host detail" },
    ],
    [
      "mixed success and failure fields",
      { ok: true, captureId, code: "INVALID_IMAGE" },
    ],
    [
      "mixed failure and success fields",
      { ok: false, code: "INVALID_IMAGE", captureId },
    ],
    ["a non-boolean discriminator", { ok: "true", captureId }],
  ])("rejects %s as a sanitized protocol error", async (_name, reply) => {
    sendNativeMessage.mockResolvedValue(reply);

    await expect(sendCaptureToNativeHost(capture)).rejects.toMatchObject({
      code: "INVALID_HOST_RESPONSE",
      message: "INVALID_HOST_RESPONSE",
    });
  });

  it("sanitizes rejected native messaging errors", async () => {
    sendNativeMessage.mockRejectedValue(
      new Error("sensitive raw native-host diagnostic"),
    );

    const error = await sendCaptureToNativeHost(capture).catch(
      (caught: unknown) => caught,
    );

    expect(error).toMatchObject({
      code: "HOST_UNAVAILABLE",
      message: "HOST_UNAVAILABLE",
    });
    expect(JSON.stringify(error)).not.toContain("sensitive");
    expect(sendNativeMessage).toHaveBeenCalledTimes(1);
  });
});
