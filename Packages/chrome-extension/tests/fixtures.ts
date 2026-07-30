import { execFileSync } from "node:child_process";
import { dirname, resolve } from "node:path";
import { fileURLToPath } from "node:url";
import {
  chromium,
  test as base,
  type BrowserContext,
  type Worker,
} from "@playwright/test";

const packageDirectory = resolve(
  dirname(fileURLToPath(import.meta.url)),
  "..",
);
const extensionPath = resolve(packageDirectory, "dist-e2e");

type ExtensionFixtures = {
  extensionContext: BrowserContext;
  extensionId: string;
  serviceWorker: Worker;
};

export const test = base.extend<ExtensionFixtures>({
  extensionContext: async ({}, use) => {
    execFileSync("pnpm", ["exec", "vite", "build", "--mode", "e2e"], {
      cwd: packageDirectory,
      stdio: "inherit",
    });

    const context = await chromium.launchPersistentContext("", {
      channel: "chromium",
      args: [
        `--disable-extensions-except=${extensionPath}`,
        `--load-extension=${extensionPath}`,
      ],
    });

    await use(context);
    await context.close();
  },

  serviceWorker: async ({ extensionContext }, use) => {
    const worker =
      extensionContext.serviceWorkers()[0]
      ?? (await extensionContext.waitForEvent("serviceworker"));
    await use(worker);
  },

  extensionId: async ({ serviceWorker }, use) => {
    const extensionId = new URL(serviceWorker.url()).host;
    await use(extensionId);
  },
});

export { expect } from "@playwright/test";
