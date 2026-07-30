import { createHash } from "node:crypto";
import { expect, test } from "./fixtures";

type TestSeamSnapshot = {
  captureVisibleTabInvocationCount: number;
  nativeMessageInvocationCount: number;
};

type TestSeam = {
  runCaptureAction(): Promise<TestSeamSnapshot>;
};

test("loads the built MV3 extension with only approved permissions", async ({
  extensionId,
  serviceWorker,
}) => {
  const manifest = await serviceWorker.evaluate(() =>
    chrome.runtime.getManifest()
  );

  expect(extensionId).toMatch(/^[a-p]{32}$/);
  const key = manifest.key;
  expect(typeof key).toBe("string");
  expect(extensionId).toBe(extensionIdFromPublicKey(key!));
  expect(manifest.manifest_version).toBe(3);
  expect(manifest.permissions).toEqual(["activeTab", "nativeMessaging"]);
  expect(manifest).not.toHaveProperty("host_permissions");
  expect(manifest).not.toHaveProperty("content_scripts");
});

function extensionIdFromPublicKey(publicKeyBase64: string): string {
  const digest = createHash("sha256")
    .update(Buffer.from(publicKeyBase64, "base64"))
    .digest()
    .subarray(0, 16);
  return [...digest]
    .flatMap((byte) => [byte >> 4, byte & 0x0f])
    .map((nibble) => String.fromCharCode("a".charCodeAt(0) + nibble))
    .join("");
}

test("invokes the captureVisibleTab seam exactly once for each action", async ({
  serviceWorker,
}) => {
  await expect
    .poll(() =>
      serviceWorker.evaluate(
        () => "__myshottrE2E" in globalThis,
      )
    )
    .toBe(true);

  const first = await serviceWorker.evaluate(async () => {
    const seam = (
      globalThis as typeof globalThis & { __myshottrE2E: TestSeam }
    ).__myshottrE2E;
    return seam.runCaptureAction();
  });
  expect(first).toEqual({
    captureVisibleTabInvocationCount: 1,
    nativeMessageInvocationCount: 1,
  });

  const second = await serviceWorker.evaluate(async () => {
    const seam = (
      globalThis as typeof globalThis & { __myshottrE2E: TestSeam }
    ).__myshottrE2E;
    return seam.runCaptureAction();
  });
  expect(second).toEqual({
    captureVisibleTabInvocationCount: 2,
    nativeMessageInvocationCount: 2,
  });
});
