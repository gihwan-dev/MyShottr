import { describe, expect, it } from "vitest";
// @ts-expect-error Vite resolves production source as text for this source-level contract test.
import appSource from "../App.tsx?raw";
import { fixtureDocument } from "../test/fixtures";
import { createNativeBridge } from "./nativeBridge";
import { EditorToNativeEnvelopeSchema, NativeToEditorEnvelopeSchema } from "./protocol";

const UUID = "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE";

const editorReadyFixture = {
  protocolVersion: 1,
  requestId: UUID,
  type: "editorReady",
  payload: {},
};

describe("EditorToNativeEnvelopeSchema", () => {
  it("accepts a validated editor preferences change", () => {
    const message = {
      protocolVersion: 1,
      requestId: "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE",
      type: "editorPreferencesChanged",
      payload: {
        tool: "arrow",
        defaults: fixtureDocument().defaults,
      },
    };

    expect(EditorToNativeEnvelopeSchema.parse(message)).toEqual(message);
  });

  it("accepts line as a persisted and loaded editor preference", () => {
    const preferencesMessage = {
      protocolVersion: 1,
      requestId: "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE",
      type: "editorPreferencesChanged",
      payload: {
        tool: "line",
        defaults: fixtureDocument().defaults,
      },
    };
    const loadMessage = {
      protocolVersion: 1,
      requestId: "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE",
      type: "loadDocument",
      payload: {
        documentId: "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE",
        sourceImageURL: "myshottr-editor://editor/document/AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE/original.png",
        annotationDocument: fixtureDocument(),
        initialTool: "line",
      },
    };

    expect(EditorToNativeEnvelopeSchema.parse(preferencesMessage)).toEqual(preferencesMessage);
    expect(NativeToEditorEnvelopeSchema.parse(loadMessage)).toEqual(loadMessage);
  });

  it.each([
    ["unknown tools", { tool: "unknown", defaults: fixtureDocument().defaults }],
    ["unknown colors", { tool: "arrow", defaults: { ...fixtureDocument().defaults, color: "#FFFFFF" } }],
    ["unknown widths", { tool: "arrow", defaults: { ...fixtureDocument().defaults, strokeWidth: 3 } }],
    ["unknown text sizes", { tool: "arrow", defaults: { ...fixtureDocument().defaults, textSize: 12 } }],
    ["unknown roughness", { tool: "arrow", defaults: { ...fixtureDocument().defaults, roughness: 3 } }],
    ["unknown opacity", { tool: "arrow", defaults: { ...fixtureDocument().defaults, opacity: 0.6 } }],
    ["missing rectangle fill colors", (() => {
      const { rectangleFillColor: _rectangleFillColor, ...defaults } = fixtureDocument().defaults;
      return { tool: "arrow", defaults };
    })()],
    ["invalid rectangle fill colors", { tool: "arrow", defaults: { ...fixtureDocument().defaults, rectangleFillColor: "#FFFFFF" } }],
    ["missing highlighter opacities", (() => {
      const { highlighterOpacity: _highlighterOpacity, ...defaults } = fixtureDocument().defaults;
      return { tool: "arrow", defaults };
    })()],
    ["invalid highlighter opacities", { tool: "arrow", defaults: { ...fixtureDocument().defaults, highlighterOpacity: 0.75 } }],
    ["extra defaults keys", { tool: "arrow", defaults: { ...fixtureDocument().defaults, future: true } }],
    ["extra keys", { tool: "arrow", defaults: fixtureDocument().defaults, extra: true }],
  ])("rejects preference changes with %s", (_description, payload) => {
    expect(() => EditorToNativeEnvelopeSchema.parse({
      protocolVersion: 1,
      requestId: "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE",
      type: "editorPreferencesChanged",
      payload,
    })).toThrow();
  });

  it("accepts the v1 editorReady fixture", () => {
    expect(EditorToNativeEnvelopeSchema.parse(editorReadyFixture)).toEqual(editorReadyFixture);
  });

  it("accepts an exact history state change", () => {
    const message = {
      protocolVersion: 1,
      requestId: UUID,
      type: "historyStateChanged",
      payload: { canUndo: true, canRedo: false },
    };

    expect(EditorToNativeEnvelopeSchema.parse(message)).toEqual(message);
  });

  it.each([
    ["a missing canUndo", { canRedo: false }],
    ["a missing canRedo", { canUndo: true }],
    ["a non-boolean canUndo", { canUndo: "true", canRedo: false }],
    ["a non-boolean canRedo", { canUndo: true, canRedo: 0 }],
    ["an extra key", { canUndo: true, canRedo: false, operationId: UUID }],
  ])("rejects a history state change with %s", (_description, payload) => {
    expect(() => EditorToNativeEnvelopeSchema.parse({
      protocolVersion: 1,
      requestId: UUID,
      type: "historyStateChanged",
      payload,
    })).toThrow();
  });

  it.each([
    ["a future protocol version", { ...editorReadyFixture, protocolVersion: 2 }],
    ["an unknown message type", { ...editorReadyFixture, type: "futureMessage" }],
    ["a missing request ID", { protocolVersion: 1, type: "editorReady", payload: {} }],
    ["a missing payload", { protocolVersion: 1, requestId: "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE", type: "editorReady" }],
  ])("rejects %s", (_description, message) => {
    expect(() => EditorToNativeEnvelopeSchema.parse(message)).toThrow();
  });

  it("rejects a payload larger than 8 MiB", () => {
    expect(() => EditorToNativeEnvelopeSchema.parse({
      ...editorReadyFixture,
      payload: { contents: "a".repeat((8 * 1024 * 1024) + 1) },
    })).toThrow();
  });

  it("rejects an annotation snapshot containing an unknown element type", () => {
    expect(() => EditorToNativeEnvelopeSchema.parse({
      protocolVersion: 1,
      requestId: "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE",
      type: "annotationSnapshot",
      payload: {
        document: fixtureDocument({
          elements: [{ ...fixtureDocument().elements[0], type: "video" } as never],
        }),
      },
    })).toThrow();
  });

  it("sends INVALID_DOCUMENT when native attempts to load an unknown element type", () => {
    const sent: unknown[] = [];
    window.webkit = { messageHandlers: { myshottr: { postMessage: (message) => sent.push(message) } } };
    const unsubscribe = createNativeBridge().subscribe(() => {});

    window.dispatchEvent(new CustomEvent("myshottr:native-message", {
      detail: {
        protocolVersion: 1,
        requestId: "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE",
        type: "loadDocument",
        payload: {
          documentId: "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE",
          sourceImageURL: "myshottr-editor://editor/document/AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE/original.png",
          annotationDocument: fixtureDocument({
            elements: [{ ...fixtureDocument().elements[0], type: "video" } as never],
          }),
          initialTool: "selection",
        },
      },
    }));

    expect(sent).toHaveLength(1);
    expect(EditorToNativeEnvelopeSchema.parse(sent[0])).toMatchObject({
      requestId: "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE",
      type: "bridgeError",
      payload: { code: "INVALID_DOCUMENT" },
    });
    unsubscribe();
  });
});

describe("NativeToEditorEnvelopeSchema", () => {
  const loadDocumentFixture = {
    protocolVersion: 1,
    requestId: "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE",
    type: "loadDocument",
    payload: {
      documentId: "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE",
      sourceImageURL: "myshottr-editor://editor/document/AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE/original.png",
      annotationDocument: fixtureDocument(),
      initialTool: "selection",
    },
  };

  it("accepts the exact same-origin session PNG URL", () => {
    expect(NativeToEditorEnvelopeSchema.parse(loadDocumentFixture)).toEqual(loadDocumentFixture);
  });

  it.each([
    "myshottr-resource://document/AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE/original.png",
    "myshottr-editor://editor/document/FFFFFFFF-EEEE-DDDD-CCCC-BBBBBBBBBBBB/original.png",
    "myshottr-editor://editor/document/AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE/original.png/extra",
  ])("rejects a source PNG URL outside the exact document route: %s", (sourceImageURL) => {
    expect(() => NativeToEditorEnvelopeSchema.parse({
      ...loadDocumentFixture,
      payload: { ...loadDocumentFixture.payload, sourceImageURL },
    })).toThrow();
  });

  it.each(["undo", "redo"] as const)("accepts the %s history action", (action) => {
    const message = {
      protocolVersion: 1,
      requestId: UUID,
      type: "performHistoryAction",
      payload: { action },
    };

    expect(NativeToEditorEnvelopeSchema.parse(message)).toEqual(message);
  });

  it.each([
    ["a missing action", {}],
    ["an unknown action", { action: "revert" }],
    ["an extra key", { action: "undo", operationId: UUID }],
  ])("rejects a history action with %s", (_description, payload) => {
    expect(() => NativeToEditorEnvelopeSchema.parse({
      protocolVersion: 1,
      requestId: UUID,
      type: "performHistoryAction",
      payload,
    })).toThrow();
  });

  it.each([
    ["save started", { operation: "save", phase: "started" }],
    ["export started", { operation: "export", phase: "started" }],
    ["save completed", { operation: "save", phase: "completed" }],
    ["save superseded", { operation: "save", phase: "superseded" }],
    ["export completed", { operation: "export", phase: "completed", displayName: "Capture.png" }],
    ["save cancelled", { operation: "save", phase: "cancelled" }],
    ["export cancelled", { operation: "export", phase: "cancelled" }],
    ["save failed", { operation: "save", phase: "failed" }],
    ["export failed", { operation: "export", phase: "failed" }],
  ])("accepts operation status: %s", (_description, payload) => {
    const message = {
      protocolVersion: 1,
      requestId: UUID,
      type: "operationStatus",
      payload,
    };

    expect(NativeToEditorEnvelopeSchema.parse(message)).toEqual(message);
  });

  it.each([
    ["a missing operation", { phase: "started" }],
    ["a missing phase", { operation: "save" }],
    ["an unknown operation", { operation: "print", phase: "started" }],
    ["an unknown phase", { operation: "save", phase: "queued" }],
    ["export superseded", { operation: "export", phase: "superseded" }],
    ["save completed with displayName", { operation: "save", phase: "completed", displayName: "Capture.myshottr" }],
    ["export completed without displayName", { operation: "export", phase: "completed" }],
    ["export completed with a non-string displayName", { operation: "export", phase: "completed", displayName: 7 }],
    ["save started with displayName", { operation: "save", phase: "started", displayName: "Capture.myshottr" }],
    ["export started with displayName", { operation: "export", phase: "started", displayName: "Capture.png" }],
    ["save cancelled with displayName", { operation: "save", phase: "cancelled", displayName: "Capture.myshottr" }],
    ["export cancelled with displayName", { operation: "export", phase: "cancelled", displayName: "Capture.png" }],
    ["save failed with displayName", { operation: "save", phase: "failed", displayName: "Capture.myshottr" }],
    ["export failed with displayName", { operation: "export", phase: "failed", displayName: "Capture.png" }],
    ["a payload operation ID", { operation: "save", phase: "started", operationId: UUID }],
    ["an arbitrary extra key", { operation: "export", phase: "completed", displayName: "Capture.png", extra: true }],
  ])("rejects operation status with %s", (_description, payload) => {
    expect(() => NativeToEditorEnvelopeSchema.parse({
      protocolVersion: 1,
      requestId: UUID,
      type: "operationStatus",
      payload,
    })).toThrow();
  });

  it.each(["saveCompleted", "saveFailed"])(
    "keeps legacy %s declarations out of production App behavior",
    (legacyType) => {
      expect(appSource).not.toMatch(new RegExp(`\\b${legacyType}\\b`));
    },
  );
});
