import { createHash } from "node:crypto";
import { readFileSync } from "node:fs";
import { dirname, resolve } from "node:path";
import { fileURLToPath } from "node:url";
import { expect, test } from "./fixtures";

type TestSeamSnapshot = {
  captureVisibleTabInvocationCount: number;
  nativeMessageInvocationCount: number;
};

type TestSeam = {
  handleCaptureRequest(request: unknown): Promise<TestSeamSnapshot>;
  setNextNativeReply(reply: unknown): void;
  snapshot(): TestSeamSnapshot;
};

const extensionPageCSP =
  "default-src 'none'; script-src 'self'; connect-src 'none'; "
  + "object-src 'none'; base-uri 'none'; frame-src 'none'; "
  + "img-src 'self'; style-src 'self'";
const packageDirectory = resolve(dirname(fileURLToPath(import.meta.url)), "..");
const committedPublicKey = readFileSync(
  resolve(packageDirectory, "../../Config/chrome-extension-key.b64"),
  "utf8",
).trim();
const fixedExtensionId = "mcpmeggdbafgeemngbfniplmcjmigfbh";

test("loads the built MV3 extension with only approved permissions", async ({
  extensionId,
  serviceWorker,
}) => {
  const manifest = await serviceWorker.evaluate(() =>
    chrome.runtime.getManifest()
  );

  expect(extensionId).toBe(fixedExtensionId);
  const key = manifest.key;
  expect(typeof key).toBe("string");
  expect(key).toBe(committedPublicKey);
  expect(extensionId).toBe(extensionIdFromPublicKey(key!));
  expect(manifest.manifest_version).toBe(3);
  expect(manifest.permissions).toEqual(["activeTab", "nativeMessaging"]);
  expect(manifest).not.toHaveProperty("optional_permissions");
  expect(manifest).not.toHaveProperty("host_permissions");
  expect(manifest).not.toHaveProperty("optional_host_permissions");
  expect(manifest).not.toHaveProperty("content_scripts");
  expect(manifest.content_security_policy).toEqual({
    extension_pages: extensionPageCSP,
  });
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
        () => "__inkbeamE2E" in globalThis,
      )
    )
    .toBe(true);

  const first = await serviceWorker.evaluate(async () => {
    const seam = (
      globalThis as typeof globalThis & { __inkbeamE2E: TestSeam }
    ).__inkbeamE2E;
    return seam.handleCaptureRequest({ mode: "visibleViewport" });
  });
  expect(first).toEqual({
    captureVisibleTabInvocationCount: 1,
    nativeMessageInvocationCount: 1,
  });

  const second = await serviceWorker.evaluate(async () => {
    const seam = (
      globalThis as typeof globalThis & { __inkbeamE2E: TestSeam }
    ).__inkbeamE2E;
    return seam.handleCaptureRequest({ mode: "visibleViewport" });
  });
  expect(second).toEqual({
    captureVisibleTabInvocationCount: 2,
    nativeMessageInvocationCount: 2,
  });
});

test("rejects full-page mode before capture or native messaging", async ({
  serviceWorker,
}) => {
  await expect
    .poll(() => serviceWorker.evaluate(() => "__inkbeamE2E" in globalThis))
    .toBe(true);

  const result = await serviceWorker.evaluate(async () => {
    const seam = (
      globalThis as typeof globalThis & { __inkbeamE2E: TestSeam }
    ).__inkbeamE2E;
    let code: string | undefined;
    try {
      await seam.handleCaptureRequest({ mode: "fullPage" });
    } catch (error) {
      if (
        typeof error === "object"
        && error !== null
        && "code" in error
        && typeof error.code === "string"
      ) {
        code = error.code;
      }
    }
    return { code, snapshot: seam.snapshot() };
  });

  expect(result).toEqual({
    code: "UNSUPPORTED_CAPTURE_MODE",
    snapshot: {
      captureVisibleTabInvocationCount: 0,
      nativeMessageInvocationCount: 0,
    },
  });
});

test("rejects inherited, changing-getter, and no-argument requests", async ({
  serviceWorker,
}) => {
  await expect
    .poll(() => serviceWorker.evaluate(() => "__inkbeamE2E" in globalThis))
    .toBe(true);

  const result = await serviceWorker.evaluate(async () => {
    const seam = (
      globalThis as typeof globalThis & { __inkbeamE2E: TestSeam }
    ).__inkbeamE2E;
    const inheritedRequest = Object.assign(
      Object.create({ mode: "visibleViewport" }) as object,
      { extra: true },
    );
    let modeReads = 0;
    const changingGetterRequest = {
      get mode() {
        modeReads += 1;
        return modeReads === 1 ? "visibleViewport" : "futureMode";
      },
    };
    const attempts = [
      () => seam.handleCaptureRequest(inheritedRequest),
      () => seam.handleCaptureRequest(changingGetterRequest),
      () => Reflect.apply(seam.handleCaptureRequest, seam, []),
    ];
    const codes: Array<string | undefined> = [];

    for (const attempt of attempts) {
      try {
        await attempt();
        codes.push(undefined);
      } catch (error) {
        codes.push(
          typeof error === "object"
            && error !== null
            && "code" in error
            && typeof error.code === "string"
            ? error.code
            : undefined,
        );
      }
    }

    return { codes, snapshot: seam.snapshot() };
  });

  expect(result).toEqual({
    codes: [
      "UNSUPPORTED_CAPTURE_MODE",
      "UNSUPPORTED_CAPTURE_MODE",
      "UNSUPPORTED_CAPTURE_MODE",
    ],
    snapshot: {
      captureVisibleTabInvocationCount: 0,
      nativeMessageInvocationCount: 0,
    },
  });
});

test("shows the actionable durable-capture activation failure", async ({
  serviceWorker,
}) => {
  await expect
    .poll(() =>
      serviceWorker.evaluate(
        () => "__inkbeamE2E" in globalThis,
      )
    )
    .toBe(true);

  const result = await serviceWorker.evaluate(async () => {
    const seam = (
      globalThis as typeof globalThis & { __inkbeamE2E: TestSeam }
    ).__inkbeamE2E;
    seam.setNextNativeReply({
      ok: false,
      code: "APP_ACTIVATION_FAILED",
    });

    let code: string | undefined;
    try {
      await seam.handleCaptureRequest({ mode: "visibleViewport" });
    } catch (error) {
      if (
        typeof error === "object"
        && error !== null
        && "code" in error
        && typeof error.code === "string"
      ) {
        code = error.code;
      }
    }

    return {
      code,
      title: await chrome.action.getTitle({}),
      snapshot: seam.snapshot(),
    };
  });

  expect(result).toEqual({
    code: "APP_ACTIVATION_FAILED",
    title: "Capture saved. Open Inkbeam to import.",
    snapshot: {
      captureVisibleTabInvocationCount: 1,
      nativeMessageInvocationCount: 1,
    },
  });
});
