import type { EditorToNativeType, PayloadFor } from "../bridge/protocol";

const BASE64_CHUNK_BYTES = 512 * 1024;

type CompositeSender = {
  sendCorrelated<T extends EditorToNativeType>(requestId: string, type: T, payload: PayloadFor<T>): Promise<void>;
};

export async function sendComposite({ requestId, blob, sendCorrelated }: {
  requestId: string;
  blob: Blob;
  sendCorrelated: CompositeSender["sendCorrelated"];
}): Promise<void> {
  const base64 = base64Encode(new Uint8Array(await blob.arrayBuffer()));
  if (base64.length === 0) throw new Error("Composite PNG is empty");
  const total = Math.ceil(base64.length / BASE64_CHUNK_BYTES);
  for (let index = 0; index < total; index += 1) {
    await sendCorrelated(requestId, "compositeChunk", {
      requestId,
      index,
      total,
      dataBase64: base64.slice(index * BASE64_CHUNK_BYTES, (index + 1) * BASE64_CHUNK_BYTES),
    });
  }
  await sendCorrelated(requestId, "compositeCompleted", { requestId });
}

function base64Encode(bytes: Uint8Array): string {
  let binary = "";
  for (const byte of bytes) binary += String.fromCharCode(byte);
  return btoa(binary);
}
