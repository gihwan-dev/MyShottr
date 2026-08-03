import { expect, test, type Page } from "@playwright/test";

import type { NativeToEditorEnvelope } from "../../src/bridge/protocol";

const appearanceRequestId = "DDDDDDDD-DDDD-4DDD-8DDD-DDDDDDDDDDDD";
const saveRequestId = "CCCCCCCC-CCCC-4CCC-8CCC-CCCCCCCCCCCC";

const states = [
  "selection-empty",
  "new-rectangle",
  "selected-rectangle",
  "mixed-rectangle-text",
  "shortcut-help",
  "save-success",
  "rail-reduced-motion",
] as const;

async function sendNativeMessage(
  page: Page,
  message: NativeToEditorEnvelope,
): Promise<void> {
  await page.evaluate((detail) => {
    window.dispatchEvent(
      new CustomEvent("inkbeam:native-message", { detail }),
    );
  }, message);
}

for (const appearance of ["light", "dark"] as const) {
  for (const state of states) {
    test(`${state} in ${appearance}`, async ({ page }) => {
      await page.emulateMedia({
        reducedMotion:
          state === "rail-reduced-motion" ? "reduce" : "no-preference",
      });
      await page.goto(`/tests/visual/visual.html?state=${state}`);
      await expect(
        page.getByRole("main", { name: "MyShottr editor" }),
      ).toBeVisible();
      await page.waitForFunction(
        (expected) => document.documentElement.dataset.visualFixtureReady === expected,
        state,
      );
      await sendNativeMessage(page, {
        protocolVersion: 1,
        requestId: appearanceRequestId,
        type: "setAppearance",
        payload: { colorScheme: appearance },
      });
      await expect(page.locator("html")).toHaveAttribute(
        "data-color-scheme",
        appearance,
      );
      if (state === "save-success") {
        await sendNativeMessage(page, {
          protocolVersion: 1,
          requestId: saveRequestId,
          type: "operationStatus",
          payload: { operation: "save", phase: "started" },
        });
        await sendNativeMessage(page, {
          protocolVersion: 1,
          requestId: saveRequestId,
          type: "operationStatus",
          payload: { operation: "save", phase: "completed" },
        });
        await expect(page.locator("output.editor-feedback")).toHaveText("Saved");
      }
      await expect(page).toHaveScreenshot(`${state}-${appearance}.png`, {
        animations: "disabled",
        caret: "hide",
        scale: "css",
      });
    });
  }
}
