import { createHash } from "node:crypto";
import { promises as fs } from "node:fs";
import { dirname, extname, resolve } from "node:path";
import { fileURLToPath } from "node:url";
import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";

const captureVisibleTab = vi.fn();
const sendNativeMessage = vi.fn();
const setBadgeText = vi.fn();
const setTitle = vi.fn();
const onClickedAddListener = vi.fn();
const onCommandAddListener = vi.fn();
const captureId = "12345678-1234-1234-1234-123456789ABC";
const extensionPageCSP =
  "default-src 'none'; script-src 'self'; connect-src 'none'; "
  + "object-src 'none'; base-uri 'none'; frame-src 'none'; "
  + "img-src 'self'; style-src 'self'";

async function loadServiceWorker() {
  return import("../src/service-worker");
}

describe("runCaptureAction", () => {
  beforeEach(() => {
    vi.resetModules();
    vi.useFakeTimers();
    captureVisibleTab.mockReset();
    sendNativeMessage.mockReset();
    setBadgeText.mockReset().mockResolvedValue(undefined);
    setTitle.mockReset().mockResolvedValue(undefined);
    onClickedAddListener.mockReset();
    onCommandAddListener.mockReset();
    vi.stubGlobal("chrome", {
      action: {
        onClicked: { addListener: onClickedAddListener },
        setBadgeText,
        setTitle,
      },
      commands: {
        onCommand: { addListener: onCommandAddListener },
      },
      runtime: {
        sendNativeMessage,
      },
      tabs: {
        captureVisibleTab,
      },
    });
  });

  afterEach(() => {
    vi.useRealTimers();
    vi.unstubAllGlobals();
  });

  it("rejects full-page mode before taking a viewport capture", async () => {
    const { runCaptureAction } = await loadServiceWorker();

    await expect(runCaptureAction("fullPage")).rejects.toMatchObject({
      code: "UNSUPPORTED_CAPTURE_MODE",
    });
    expect(captureVisibleTab).not.toHaveBeenCalled();
    expect(sendNativeMessage).not.toHaveBeenCalled();
  });

  it("captures once and sends one native message", async () => {
    captureVisibleTab.mockResolvedValue("data:image/png;base64,iVBORw0KGgo=");
    sendNativeMessage.mockResolvedValue({ ok: true, captureId });
    const { runCaptureAction } = await loadServiceWorker();

    await runCaptureAction();

    expect(captureVisibleTab).toHaveBeenCalledTimes(1);
    expect(sendNativeMessage).toHaveBeenCalledTimes(1);
    expect(sendNativeMessage).toHaveBeenCalledWith(
      "dev.gihwan.inkbeam.capture",
      {
        protocolVersion: 1,
        type: "capture",
        captureMode: "visibleViewport",
        mimeType: "image/png",
        dataBase64: "iVBORw0KGgo=",
      },
    );
    expect(setBadgeText).toHaveBeenCalledWith({ text: "OK" });
    expect(setTitle).toHaveBeenCalledWith({
      title: "Captured visible viewport in Inkbeam",
    });

    await vi.advanceTimersByTimeAsync(3_000);
    expect(setBadgeText).toHaveBeenLastCalledWith({ text: "" });
  });

  it.each([
    ["INVALID_MESSAGE", "Inkbeam rejected the capture request."],
    [
      "UNSUPPORTED_CAPTURE_MODE",
      "Only visible viewport capture is supported.",
    ],
    ["INVALID_IMAGE", "Inkbeam could not read the captured PNG."],
    ["IMAGE_TOO_LARGE", "Capture is too large for Inkbeam."],
    ["STAGING_FAILED", "Inkbeam could not import the capture."],
    [
      "APP_ACTIVATION_FAILED",
      "Capture saved. Open Inkbeam to import.",
    ],
  ] as const)(
    "shows the bounded helper failure %s instead of reporting success",
    async (code, title) => {
      captureVisibleTab.mockResolvedValue("data:image/png;base64,iVBORw0KGgo=");
      sendNativeMessage.mockResolvedValue({
        ok: false,
        code,
      });
      const { runCaptureAction } = await loadServiceWorker();

      await expect(runCaptureAction()).rejects.toMatchObject({ code });
      expect(captureVisibleTab).toHaveBeenCalledTimes(1);
      expect(sendNativeMessage).toHaveBeenCalledTimes(1);
      expect(setBadgeText).toHaveBeenCalledWith({ text: "ERR" });
      expect(setBadgeText).not.toHaveBeenCalledWith({ text: "OK" });
      expect(setTitle).toHaveBeenCalledWith({ title });
    },
  );

  it("shows a sanitized bounded title for malformed host responses", async () => {
    captureVisibleTab.mockResolvedValue("data:image/png;base64,iVBORw0KGgo=");
    sendNativeMessage.mockResolvedValue({
      ok: false,
      code: "UNKNOWN",
      detail: "sensitive raw host detail",
    });
    const { runCaptureAction } = await loadServiceWorker();

    await expect(runCaptureAction()).rejects.toMatchObject({
      code: "INVALID_HOST_RESPONSE",
    });
    expect(captureVisibleTab).toHaveBeenCalledTimes(1);
    expect(sendNativeMessage).toHaveBeenCalledTimes(1);
    expect(setTitle).toHaveBeenCalledWith({
      title: "Inkbeam returned an invalid response.",
    });
    expect(JSON.stringify(setTitle.mock.calls)).not.toContain("sensitive");
  });

  it("does not send a fallback capture when native messaging fails", async () => {
    captureVisibleTab.mockResolvedValue("data:image/png;base64,iVBORw0KGgo=");
    sendNativeMessage.mockRejectedValue(new Error("host not found"));
    const { runCaptureAction } = await loadServiceWorker();

    await expect(runCaptureAction()).rejects.toMatchObject({
      code: "HOST_UNAVAILABLE",
    });
    expect(captureVisibleTab).toHaveBeenCalledTimes(1);
    expect(sendNativeMessage).toHaveBeenCalledTimes(1);
    expect(setBadgeText).toHaveBeenCalledWith({ text: "ERR" });
    expect(setTitle).toHaveBeenCalledWith({
      title: "Open Inkbeam once, then retry.",
    });
    expect(JSON.stringify(setTitle.mock.calls)).not.toContain("host not found");
  });

  it("consumes expected action-listener rejections after showing status", async () => {
    captureVisibleTab.mockResolvedValue("data:image/png;base64,iVBORw0KGgo=");
    sendNativeMessage.mockRejectedValue(new Error("host not found"));
    await loadServiceWorker();
    const onClicked = onClickedAddListener.mock.calls[0]?.[0] as
      | (() => void)
      | undefined;

    expect(onClicked).toBeTypeOf("function");
    expect(onClicked?.()).toBeUndefined();

    await vi.waitFor(() => {
      expect(setTitle).toHaveBeenCalledWith({
        title: "Open Inkbeam once, then retry.",
      });
    });
    expect(captureVisibleTab).toHaveBeenCalledTimes(1);
    expect(sendNativeMessage).toHaveBeenCalledTimes(1);
  });
});

describe("privacy boundary", () => {
  it("has no scripting, webRequest, content script, or network API source", async () => {
    const packageDirectory = resolve(
      dirname(fileURLToPath(import.meta.url)),
      "..",
    );
    const sourceDirectory = resolve(packageDirectory, "src");
    const sourcePaths = await productionSourcePaths(sourceDirectory);
    const sources = await Promise.all(
      sourcePaths.map(async (path) => ({
        path,
        source: await fs.readFile(path, "utf8"),
      })),
    );
    const manifest = JSON.parse(
      await fs.readFile(
        resolve(packageDirectory, "public", "manifest.json"),
        "utf8",
      ),
    ) as Record<string, unknown>;

    expect(manifest.permissions).toEqual(["activeTab", "nativeMessaging"]);
    expect(manifest.name).toBe("Inkbeam");
    expect(manifest.version).toBe("0.2.0");
    expect(manifest).not.toHaveProperty("optional_permissions");
    expect(manifest).not.toHaveProperty("host_permissions");
    expect(manifest).not.toHaveProperty("optional_host_permissions");
    expect(manifest).not.toHaveProperty("content_scripts");
    expect(manifest.content_security_policy).toEqual({
      extension_pages: extensionPageCSP,
    });

    for (const { path, source } of sources) {
      expect(source, path).not.toMatch(/\bchrome\s*\.\s*scripting\b/);
      expect(source, path).not.toMatch(/\bchrome\s*\.\s*webRequest\b/);
      expect(source, path).not.toMatch(
        /\b(?:fetch|XMLHttpRequest|WebSocket|EventSource)\s*\(/,
      );
      expect(source, path).not.toMatch(/\bnavigator\s*\.\s*sendBeacon\s*\(/);
      expect(source, path).not.toMatch(/\b(?:analytics|telemetry)\b/i);
    }

    const publicKey = await fs.readFile(
      resolve(
        repoRoot(packageDirectory),
        "Config",
        "chrome-extension-key.b64",
      ),
    );
    expect(createHash("sha256").update(publicKey).digest("hex")).toBe(
      "4c4f958fb19e9016d429e5335e1000ba90fa2bf8ac9e26fc8bcda22a361d08c3",
    );
  });
});

function repoRoot(packageDirectory: string): string {
  return resolve(packageDirectory, "../..");
}

async function productionSourcePaths(directory: string): Promise<string[]> {
  const entries = await fs.readdir(directory, { withFileTypes: true });
  const paths = await Promise.all(
    entries.map(async (entry) => {
      const path = resolve(directory, entry.name);
      if (entry.isDirectory()) return productionSourcePaths(path);
      if (!entry.isFile()) return [];
      if (![".ts", ".tsx"].includes(extname(entry.name))) return [];
      if (entry.name.endsWith(".test.ts") || entry.name.endsWith(".d.ts")) {
        return [];
      }
      return [path];
    }),
  );
  return paths.flat().sort();
}
