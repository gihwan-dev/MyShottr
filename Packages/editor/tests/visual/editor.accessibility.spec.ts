import { expect, test, type Page } from "@playwright/test";

import type { NativeToEditorEnvelope } from "../../src/bridge/protocol";

const appearanceRequestId = "EEEEEEEE-EEEE-4EEE-8EEE-EEEEEEEEEEEE";
const saveRequestId = "FFFFFFFF-FFFF-4FFF-8FFF-FFFFFFFFFFFF";

const tools = [
  ["Selection", "V"],
  ["Rectangle", "R"],
  ["Arrow", "A"],
  ["Line", "L"],
  ["Text", "T"],
  ["Freehand", "P"],
  ["Highlighter", "H"],
  ["Blur", "B"],
  ["Redaction", "X"],
  ["Number Marker", "N"],
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

async function setAppearance(
  page: Page,
  colorScheme: "light" | "dark",
) {
  await sendNativeMessage(page, {
    protocolVersion: 1,
    requestId: appearanceRequestId,
    type: "setAppearance",
    payload: { colorScheme },
  });
  await expect(page.locator("html")).toHaveAttribute(
    "data-color-scheme",
    colorScheme,
  );
}

async function gotoFixture(
  page: Page,
  state: string,
  appearance: "light" | "dark" = "light",
) {
  await page.goto(`/tests/visual/visual.html?state=${state}`);
  await expect(
    page.getByRole("main", { name: "MyShottr editor" }),
  ).toBeVisible();
  await page.waitForFunction(
    (expected) => document.documentElement.dataset.visualFixtureReady === expected,
    state,
  );
  await setAppearance(page, appearance);
}

async function focusedControlGroup(page: Page): Promise<string> {
  return page.evaluate(() => {
    const active = document.activeElement;
    if (!(active instanceof HTMLElement)) return "none";
    if (active.closest(".floating-tool-palette")) return "palette";
    if (active.closest(".context-rail")) return "rail";
    if (active.closest(".zoom-controls")) return "zoom";
    return "other";
  });
}

async function expectVisibleFocusRing(
  locator: ReturnType<Page["getByRole"]>,
) {
  const ring = await locator.evaluate((element) => {
    const style = getComputedStyle(element);
    return {
      style: style.outlineStyle,
      width: Number.parseFloat(style.outlineWidth),
    };
  });
  expect(ring.style).not.toBe("none");
  expect(ring.width).toBeGreaterThanOrEqual(2);
}

for (const appearance of ["light", "dark"] as const) {
  test(`real focus order, focus rings, and tooltips in ${appearance}`, async ({ page }) => {
    await gotoFixture(page, "selected-rectangle", appearance);

    await expect(page.getByLabel("Annotation tools")).toBeVisible();
    await expect(page.getByLabel("Context Rail")).toBeVisible();
    await expect(page.getByLabel("Canvas zoom controls")).toBeVisible();

    for (const [label, shortcut] of tools) {
      const tool = page.getByRole("button", {
        name: `${label}, shortcut ${shortcut}`,
      });
      await tool.focus();
      await expect(tool).toBeFocused();
      await expectVisibleFocusRing(tool);
      await expect(page.locator(`#tool-tip-${label === "Number Marker" ? "numberMarker" : label.toLowerCase()}`))
        .toHaveCSS("opacity", "1");
      await expect(tool.locator("kbd")).toHaveAttribute("aria-hidden", "true");
      await expect(tool.locator("kbd")).toHaveText(shortcut);
    }

    const selection = page.getByRole("button", {
      name: "Selection, shortcut V",
    });
    await selection.hover();
    await expect(page.locator("#tool-tip-selection")).toHaveCSS("opacity", "1");

    await selection.focus();
    const groups = [await focusedControlGroup(page)];
    for (let index = 0; index < 64 && groups.at(-1) !== "zoom"; index += 1) {
      await page.keyboard.press("Tab");
      const group = await focusedControlGroup(page);
      if (group !== "other" && group !== groups.at(-1)) groups.push(group);
    }
    expect(groups).toEqual(["palette", "rail", "zoom"]);
  });

  test(`rail controls expose browser-native state in ${appearance}`, async ({ page }) => {
    await gotoFixture(page, "selected-rectangle", appearance);

    const color = page.getByRole("radiogroup", { name: "Color" });
    await expect(color.getByRole("radio", { name: "Red" })).toHaveAttribute(
      "aria-checked",
      "true",
    );
    const fill = page.getByRole("radiogroup", { name: "Fill" });
    await expect(fill.getByRole("radio", { name: "None" })).toHaveAttribute(
      "aria-checked",
      "true",
    );
    await expect(
      page.getByRole("radiogroup", { name: "Stroke width" })
        .getByRole("radio", { name: "4 px" }),
    ).toHaveAttribute("aria-checked", "true");
    const slider = page.getByRole("slider", { name: "Opacity" });
    await expect(slider).toHaveValue("100");
    await expect(slider).toHaveAttribute("aria-valuetext", "100%");

    await gotoFixture(page, "mixed-rectangle-text", appearance);
    await expect(page.getByLabel("Context Rail").getByText("Mixed").first())
      .toBeVisible();
    const mixedColor = page.getByRole("radiogroup", { name: "Color" });
    for (const radio of await mixedColor.getByRole("radio").all()) {
      await expect(radio).toHaveAttribute("aria-checked", "false");
    }
    await expect(page.getByRole("slider", { name: "Opacity" }))
      .toHaveAttribute("aria-valuetext", "Mixed");
  });
}

test("shortcut help traps focus and restores the invoking tool", async ({ page }) => {
  await gotoFixture(page, "selection-empty");
  const rectangle = page.getByRole("button", {
    name: "Rectangle, shortcut R",
  });
  await rectangle.focus();
  await page.keyboard.press("Shift+Slash");

  const dialog = page.getByRole("dialog", { name: "Keyboard Shortcuts" });
  const close = page.getByRole("button", { name: "Close keyboard shortcuts" });
  await expect(dialog).toBeVisible();
  await expect(close).toBeFocused();
  await page.keyboard.press("Tab");
  await expect(close).toBeFocused();
  await page.keyboard.press("Shift+Tab");
  await expect(close).toBeFocused();
  await page.keyboard.press("Escape");
  await expect(dialog).toBeHidden();
  await expect(rectangle).toBeFocused();
});

test("strict Save status renders one polite Saved live region", async ({ page }) => {
  await gotoFixture(page, "save-success");
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
  const feedback = page.locator("output.editor-feedback");
  await expect(feedback).toHaveAttribute("role", "status");
  await expect(feedback).toHaveAttribute("aria-live", "polite");
  await expect(feedback).toHaveText("Saved");
  await expect(page.locator("output.editor-feedback")).toHaveCount(1);
});

type Color = { r: number; g: number; b: number; a: number };

function parseColor(value: string): Color {
  const channels = value.match(/[\d.]+/g)?.map(Number);
  if (!channels || channels.length < 3) {
    throw new Error(`Cannot parse rendered color: ${value}`);
  }
  return {
    r: channels[0],
    g: channels[1],
    b: channels[2],
    a: channels[3] ?? 1,
  };
}

function composite(foreground: Color, background: Color): Color {
  const alpha = foreground.a + background.a * (1 - foreground.a);
  return {
    r: (foreground.r * foreground.a + background.r * background.a * (1 - foreground.a)) / alpha,
    g: (foreground.g * foreground.a + background.g * background.a * (1 - foreground.a)) / alpha,
    b: (foreground.b * foreground.a + background.b * background.a * (1 - foreground.a)) / alpha,
    a: alpha,
  };
}

function luminance(color: Color): number {
  const channels = [color.r, color.g, color.b].map((channel) => {
    const normalized = channel / 255;
    return normalized <= 0.04045
      ? normalized / 12.92
      : ((normalized + 0.055) / 1.055) ** 2.4;
  });
  return 0.2126 * channels[0] + 0.7152 * channels[1] + 0.0722 * channels[2];
}

function contrast(left: Color, right: Color): number {
  const values = [luminance(left), luminance(right)].sort((a, b) => b - a);
  return (values[0] + 0.05) / (values[1] + 0.05);
}

test("light and dark core tokens are distinct and meet rendered contrast", async ({ page }) => {
  const rendered: Record<string, {
    body: string;
    panel: string;
    controlSurface: string;
    textRatio: number;
    mutedTextRatio: number;
    controlTextRatio: number;
    boundaryRatio: number;
    activeRatio: number;
  }> = {};

  for (const appearance of ["light", "dark"] as const) {
    await gotoFixture(page, "selected-rectangle", appearance);
    const colors = await page.evaluate(() => {
      const body = getComputedStyle(document.body);
      const panel = getComputedStyle(document.querySelector(".context-rail")!);
      const heading = getComputedStyle(document.querySelector(".context-rail h2")!);
      const control = getComputedStyle(document.querySelector(".context-rail-option")!);
      const legend = getComputedStyle(document.querySelector(".context-rail-field legend")!);
      const active = getComputedStyle(document.querySelector(".floating-tool-palette [aria-pressed='true']")!);
      return {
        body: body.backgroundColor,
        panel: panel.backgroundColor,
        heading: heading.color,
        legend: legend.color,
        controlSurface: control.backgroundColor,
        controlText: control.color,
        controlBorder: control.borderColor,
        active: active.backgroundColor,
      };
    });
    const body = parseColor(colors.body);
    const panel = composite(parseColor(colors.panel), body);
    const text = composite(parseColor(colors.heading), panel);
    const mutedText = composite(parseColor(colors.legend), panel);
    const controlSurface = composite(parseColor(colors.controlSurface), panel);
    const controlText = composite(parseColor(colors.controlText), controlSurface);
    const boundary = composite(parseColor(colors.controlBorder), panel);
    const active = composite(parseColor(colors.active), panel);
    rendered[appearance] = {
      body: colors.body,
      panel: colors.panel,
      controlSurface: colors.controlSurface,
      textRatio: contrast(text, panel),
      mutedTextRatio: contrast(mutedText, panel),
      controlTextRatio: contrast(controlText, controlSurface),
      boundaryRatio: contrast(boundary, panel),
      activeRatio: contrast(active, panel),
    };
    expect(rendered[appearance].textRatio).toBeGreaterThanOrEqual(4.5);
    expect(rendered[appearance].mutedTextRatio).toBeGreaterThanOrEqual(4.5);
    expect(rendered[appearance].controlTextRatio).toBeGreaterThanOrEqual(4.5);
    expect(rendered[appearance].boundaryRatio).toBeGreaterThanOrEqual(3);
    expect(rendered[appearance].activeRatio).toBeGreaterThanOrEqual(3);
  }

  expect(rendered.light.body).not.toBe(rendered.dark.body);
  expect(rendered.light.panel).not.toBe(rendered.dark.panel);
  expect(rendered.light.controlSurface).not.toBe(rendered.dark.controlSurface);
});

type ViewportProbe = {
  transform: string;
  panX: number;
  panY: number;
  zoom: number;
  sourceCenterX: number;
  sourceCenterY: number;
};

async function readViewportProbe(page: Page): Promise<ViewportProbe> {
  return page.getByTestId("visual-fixture-viewport").evaluate((element) => ({
    transform: element.dataset.canvasTransform!,
    panX: Number(element.dataset.panX),
    panY: Number(element.dataset.panY),
    zoom: Number(element.dataset.zoom),
    sourceCenterX: Number(element.dataset.sourceCenterX),
    sourceCenterY: Number(element.dataset.sourceCenterY),
  }));
}

async function captureRailReflow(
  page: Page,
  reducedMotion: "reduce" | "no-preference",
) {
  await page.emulateMedia({ reducedMotion });
  await gotoFixture(page, "selection-empty");
  const before = await readViewportProbe(page);
  await page.evaluate(() => {
    const probe = document.querySelector<HTMLElement>(
      "[data-testid='visual-fixture-viewport']",
    );
    if (!probe) throw new Error("Viewport probe is unavailable");
    const target = window as typeof window & {
      __myShottrPanTrace?: string[];
      __myShottrPanObserver?: MutationObserver;
    };
    target.__myShottrPanTrace = [probe.dataset.canvasTransform!];
    target.__myShottrPanObserver = new MutationObserver(() => {
      target.__myShottrPanTrace!.push(probe.dataset.canvasTransform!);
    });
    target.__myShottrPanObserver.observe(probe, {
      attributes: true,
      attributeFilter: ["data-canvas-transform"],
    });
  });

  await page.getByRole("button", { name: "Rectangle, shortcut R" }).click();
  await expect(page.getByLabel("Context Rail")).toBeVisible();
  await page.waitForFunction(
    ({ minimumTraceLength }) => {
      const probe = document.querySelector<HTMLElement>(
        "[data-testid='visual-fixture-viewport']",
      );
      if (!probe) throw new Error("Viewport probe is unavailable");
      const target = window as typeof window & {
        __myShottrPanTrace?: string[];
        __myShottrLastStableTransform?: string;
        __myShottrStableTransformFrames?: number;
      };
      const transform = probe.dataset.canvasTransform!;
      if (target.__myShottrLastStableTransform === transform) {
        target.__myShottrStableTransformFrames =
          (target.__myShottrStableTransformFrames ?? 0) + 1;
      } else {
        target.__myShottrLastStableTransform = transform;
        target.__myShottrStableTransformFrames = 0;
      }
      const distinctTraceLength = new Set(
        target.__myShottrPanTrace ?? [],
      ).size;
      return distinctTraceLength >= minimumTraceLength
        && (target.__myShottrStableTransformFrames ?? 0) >= 2;
    },
    { minimumTraceLength: reducedMotion === "reduce" ? 2 : 3 },
    { polling: "raf" },
  );
  const after = await readViewportProbe(page);
  const trace = await page.evaluate(() => {
    const target = window as typeof window & {
      __myShottrPanTrace?: string[];
      __myShottrPanObserver?: MutationObserver;
    };
    target.__myShottrPanObserver?.disconnect();
    return target.__myShottrPanTrace ?? [];
  });
  return { before, after, trace: [...new Set(trace)] };
}

test("rail reflow interpolates normally and is immediate under reduced motion", async ({ page }) => {
  const normal = await captureRailReflow(page, "no-preference");
  expect(normal.trace[0]).toBe(normal.before.transform);
  expect(normal.trace.at(-1)).toBe(normal.after.transform);
  expect(normal.trace.length).toBeGreaterThanOrEqual(3);
  expect(normal.trace.slice(1, -1)).not.toContain(normal.before.transform);
  expect(normal.trace.slice(1, -1)).not.toContain(normal.after.transform);

  const reduced = await captureRailReflow(page, "reduce");
  expect(reduced.trace).toEqual([
    reduced.before.transform,
    reduced.after.transform,
  ]);
  expect(reduced.after.transform).toBe(normal.after.transform);
  expect(reduced.after.zoom).toBeCloseTo(reduced.before.zoom, 8);
  expect(reduced.after.sourceCenterX).toBeCloseTo(reduced.before.sourceCenterX, 6);
  expect(reduced.after.sourceCenterY).toBeCloseTo(reduced.before.sourceCenterY, 6);
});
