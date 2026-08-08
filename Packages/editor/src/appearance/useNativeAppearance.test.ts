import { act, cleanup, render } from "@testing-library/react";
import { createElement } from "react";
import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";

import {
  createNativeBridge,
  NativeBridgeProvider,
} from "../bridge/nativeBridge";
import { useNativeAppearance } from "./useNativeAppearance";

const appearanceRequestId = "AAAAAAAA-AAAA-4AAA-8AAA-AAAAAAAAAAAA";
const operationRequestId = "BBBBBBBB-BBBB-4BBB-8BBB-BBBBBBBBBBBB";

function AppearanceHarness() {
  useNativeAppearance();
  return null;
}

function renderHarness() {
  return render(
    createElement(
      NativeBridgeProvider,
      {
        bridge: createNativeBridge(),
        children: createElement(AppearanceHarness),
      },
    ),
  );
}

function receive(detail: unknown) {
  act(() => {
    window.dispatchEvent(new CustomEvent("inkbeam:native-message", { detail }));
  });
}

beforeEach(() => {
  delete document.documentElement.dataset.colorScheme;
  document.documentElement.style.removeProperty("color-scheme");
  window.webkit = {
    messageHandlers: {
      inkbeam: {
        postMessage: vi.fn(),
      },
    },
  };
});

afterEach(() => {
  cleanup();
  delete window.webkit;
  delete document.documentElement.dataset.colorScheme;
  document.documentElement.style.removeProperty("color-scheme");
  vi.restoreAllMocks();
});

describe("useNativeAppearance", () => {
  it("applies strict native appearance messages to the root color scheme", () => {
    renderHarness();

    receive({
      protocolVersion: 1,
      requestId: appearanceRequestId,
      type: "setAppearance",
      payload: { colorScheme: "dark" },
    });

    expect(document.documentElement.dataset.colorScheme).toBe("dark");
    expect(document.documentElement.style.colorScheme).toBe("dark");

    receive({
      protocolVersion: 1,
      requestId: appearanceRequestId,
      type: "setAppearance",
      payload: { colorScheme: "light" },
    });

    expect(document.documentElement.dataset.colorScheme).toBe("light");
    expect(document.documentElement.style.colorScheme).toBe("light");
  });

  it("does not change appearance for other or malformed native messages", () => {
    renderHarness();

    receive({
      protocolVersion: 1,
      requestId: operationRequestId,
      type: "operationStatus",
      payload: { operation: "save", phase: "started" },
    });
    receive({
      protocolVersion: 1,
      requestId: appearanceRequestId,
      type: "setAppearance",
      payload: { colorScheme: "system" },
    });

    expect(document.documentElement.dataset.colorScheme).toBeUndefined();
    expect(document.documentElement.style.colorScheme).toBe("");
  });
});
