import { describe, expect, it } from "vitest";
import { sendComposite } from "./sendComposite";

describe("sendComposite", () => {
  it("sends ordered 512 KiB base64 chunks followed by a correlated completion", async () => {
    const sent: Array<{ requestId: string; type: string; payload: unknown }> = [];
    const requestId = "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE";
    const blob = {
      arrayBuffer: async () => new Uint8Array(800 * 1024).buffer,
    } as Blob;

    await sendComposite({
      requestId,
      blob,
      sendCorrelated: async (id, type, payload) => { sent.push({ requestId: id, type, payload }); },
    });

    const chunks = sent.filter((message) => message.type === "compositeChunk");
    expect(chunks).toHaveLength(3);
    expect(chunks).toMatchObject([
      { requestId, payload: { requestId, index: 0, total: 3 } },
      { requestId, payload: { requestId, index: 1, total: 3 } },
      { requestId, payload: { requestId, index: 2, total: 3 } },
    ]);
    expect((chunks[0].payload as { dataBase64: string }).dataBase64).toHaveLength(512 * 1024);
    expect(sent.at(-1)).toEqual({ requestId, type: "compositeCompleted", payload: { requestId } });
  });
});
