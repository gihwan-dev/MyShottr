import { describe, expect, it } from "vitest";
import { fixtureDocument } from "../test/fixtures";
import { createNativeBridge } from "./nativeBridge";
import { EditorToNativeEnvelopeSchema } from "./protocol";

const editorReadyFixture = {
  protocolVersion: 1,
  requestId: "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE",
  type: "editorReady",
  payload: {},
};

describe("EditorToNativeEnvelopeSchema", () => {
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
          sourceImageURL: "myshottr-resource://document/AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE/original.png",
          annotationDocument: fixtureDocument({
            elements: [{ ...fixtureDocument().elements[0], type: "video" } as never],
          }),
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
