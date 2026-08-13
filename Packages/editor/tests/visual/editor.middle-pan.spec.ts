import { expect, test, type Page } from "@playwright/test";

type ViewportProbe = {
  panX: number;
  panY: number;
  zoom: number;
};

async function gotoFixture(page: Page, state: string): Promise<void> {
  await page.goto(`/tests/visual/visual.html?state=${state}`);
  await expect(page.getByRole("main", { name: "Inkbeam editor" }))
    .toBeVisible();
  await page.waitForFunction(
    (expected) =>
      document.documentElement.dataset.visualFixtureReady === expected,
    state,
  );
}

async function readViewport(page: Page): Promise<ViewportProbe> {
  return page.getByTestId("visual-fixture-viewport").evaluate((element) => ({
    panX: Number(element.dataset.panX),
    panY: Number(element.dataset.panY),
    zoom: Number(element.dataset.zoom),
  }));
}

async function zoomUntilPannable(page: Page): Promise<void> {
  const zoomIn = page.getByRole("button", { name: "Zoom in" });
  for (let index = 0; index < 8; index += 1) {
    await zoomIn.evaluate((button) => (button as HTMLButtonElement).click());
  }
  await expect.poll(async () => (await readViewport(page)).zoom)
    .toBeGreaterThan(1.1);
}

async function middleDrag(
  page: Page,
  start: { x: number; y: number },
  delta: { x: number; y: number },
): Promise<void> {
  await page.mouse.move(start.x, start.y);
  await page.mouse.down({ button: "middle" });
  await page.mouse.move(start.x + delta.x, start.y + delta.y, { steps: 5 });
  await page.mouse.up({ button: "middle" });
}

test("middle-button pan wins over a real Transformer handle", async ({ page }) => {
  await gotoFixture(page, "selected-rectangle");
  await zoomUntilPannable(page);
  await page.getByRole("button", { name: "Fit Selection" }).click();
  const beforeViewport = await readViewport(page);
  const before = await page.evaluate(() => {
    const target = window as typeof window & {
      __inkbeamVisualCanvasProbe?: () => {
        handle: { x: number; y: number };
        geometry: Record<string, number>;
      };
    };
    if (!target.__inkbeamVisualCanvasProbe) {
      throw new Error("Inkbeam visual canvas probe is unavailable");
    }
    return target.__inkbeamVisualCanvasProbe();
  });

  await middleDrag(page, before.handle, { x: -70, y: -55 });

  const afterViewport = await readViewport(page);
  const after = await page.evaluate(() => {
    const target = window as typeof window & {
      __inkbeamVisualCanvasProbe?: () => {
        handle: { x: number; y: number };
        geometry: Record<string, number>;
      };
    };
    return target.__inkbeamVisualCanvasProbe!();
  });
  const state = page.getByTestId("visual-fixture-editor-state");

  expect([afterViewport.panX, afterViewport.panY])
    .not.toEqual([beforeViewport.panX, beforeViewport.panY]);
  expect(afterViewport.zoom).toBe(beforeViewport.zoom);
  expect(after.geometry).toEqual(before.geometry);
  await expect(state).toHaveAttribute("data-selected-ids", "rect-1");
  await expect(state).toHaveAttribute("data-command-count", "0");
});

test("middle-button pan wins over the live text textarea", async ({ page }) => {
  await gotoFixture(page, "editing-text");
  await zoomUntilPannable(page);
  const textarea = page.getByRole("textbox", { name: "Edit annotation text" });
  await expect(textarea).toBeFocused();
  const beforeViewport = await readViewport(page);
  const beforeText = await textarea.evaluate((element) => {
    const input = element as HTMLTextAreaElement;
    return {
      value: input.value,
      selectionStart: input.selectionStart,
      selectionEnd: input.selectionEnd,
    };
  });
  const bounds = await textarea.boundingBox();
  if (!bounds) throw new Error("Text editor bounds are unavailable");

  await middleDrag(page, {
    x: bounds.x + bounds.width / 2,
    y: bounds.y + bounds.height / 2,
  }, { x: -60, y: -50 });

  const afterViewport = await readViewport(page);
  const afterText = await textarea.evaluate((element) => {
    const input = element as HTMLTextAreaElement;
    return {
      value: input.value,
      selectionStart: input.selectionStart,
      selectionEnd: input.selectionEnd,
    };
  });
  const state = page.getByTestId("visual-fixture-editor-state");

  expect([afterViewport.panX, afterViewport.panY])
    .not.toEqual([beforeViewport.panX, beforeViewport.panY]);
  expect(afterText).toEqual(beforeText);
  await expect(textarea).toBeFocused();
  await expect(state).toHaveAttribute("data-text-edit-active", "true");
  await expect(state).toHaveAttribute("data-text-result-count", "0");
  await expect(state).toHaveAttribute("data-command-count", "0");
});
