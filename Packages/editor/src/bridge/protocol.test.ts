import { describe, expect, it } from "vitest";
import { fixtureDocument } from "../test/fixtures";
import { createNativeBridge } from "./nativeBridge";
import { EditorToNativeEnvelopeSchema, NativeToEditorEnvelopeSchema } from "./protocol";

const editorReadyFixture = {
  protocolVersion: 1,
  requestId: "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE",
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
});
