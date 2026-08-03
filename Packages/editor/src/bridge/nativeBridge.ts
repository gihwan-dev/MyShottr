import { createContext, createElement, useContext, type ReactNode } from "react";
import {
  EditorToNativeEnvelopeSchema,
  type EditorToNativeType,
  NativeToEditorEnvelopeSchema,
  type NativeToEditorEnvelope,
  PROTOCOL_VERSION,
  type PayloadFor,
} from "./protocol";

declare global {
  interface Window {
    webkit?: {
      messageHandlers?: {
        inkbeam?: {
          postMessage(message: unknown): void;
        };
      };
    };
  }
}

export type NativeBridge = {
  send<T extends EditorToNativeType>(type: T, payload: PayloadFor<T>): Promise<void>;
  sendCorrelated<T extends EditorToNativeType>(requestId: string, type: T, payload: PayloadFor<T>): Promise<void>;
  subscribe(handler: NativeBridgeMessageHandler): () => void;
};

export type NativeBridgeMessageHandler = (message: NativeToEditorEnvelope) => void;

const nativeMessageEvent = "inkbeam:native-message";
export const ANNOTATION_SNAPSHOT_REQUEST_EVENT = "inkbeam:request-annotation-snapshot";
const uuidPattern = /^[0-9A-F]{8}-[0-9A-F]{4}-[0-9A-F]{4}-[0-9A-F]{4}-[0-9A-F]{12}$/i;

export function createNativeBridge(): NativeBridge {
  const post = async <T extends EditorToNativeType>(requestId: string, type: T, payload: PayloadFor<T>): Promise<void> => {
    const message = EditorToNativeEnvelopeSchema.parse({
      protocolVersion: PROTOCOL_VERSION,
      requestId,
      type,
      payload,
    });
    const handler = window.webkit?.messageHandlers?.inkbeam;
    if (!handler) throw new Error("Inkbeam native bridge is unavailable");
    handler.postMessage(message);
  };
  return {
    async send<T extends EditorToNativeType>(type: T, payload: PayloadFor<T>): Promise<void> {
      await post(crypto.randomUUID(), type, payload);
    },
    async sendCorrelated<T extends EditorToNativeType>(requestId: string, type: T, payload: PayloadFor<T>): Promise<void> {
      await post(requestId, type, payload);
    },
    subscribe(handler: (message: NativeToEditorEnvelope) => void): () => void {
      const receive = (event: Event) => {
        if (!(event instanceof CustomEvent)) {
          void this.send("bridgeError", {
            code: "INVALID_MESSAGE",
            message: "Native sent a malformed bridge event",
          });
          return;
        }
        const message = NativeToEditorEnvelopeSchema.safeParse(event.detail);
        if (!message.success) {
          const loadRequestID = typeof event.detail === "object" && event.detail !== null
            && "type" in event.detail && event.detail.type === "loadDocument"
            && "requestId" in event.detail && typeof event.detail.requestId === "string"
            && uuidPattern.test(event.detail.requestId)
            ? event.detail.requestId
            : undefined;
          const code = loadRequestID ? "INVALID_DOCUMENT" : "INVALID_MESSAGE";
          const payload = {
            code,
            message: code === "INVALID_DOCUMENT"
              ? "Native attempted to load an invalid document"
              : "Native sent an invalid bridge message",
          } as const;
          if (loadRequestID) void this.sendCorrelated(loadRequestID, "bridgeError", payload);
          else void this.send("bridgeError", payload);
          return;
        }
        handler(message.data);
      };
      window.addEventListener(nativeMessageEvent, receive);
      return () => window.removeEventListener(nativeMessageEvent, receive);
    },
  };
}

const NativeBridgeContext = createContext<NativeBridge | undefined>(undefined);

export function NativeBridgeProvider({ bridge, children }: { bridge: NativeBridge; children: ReactNode }) {
  return createElement(NativeBridgeContext.Provider, { value: bridge }, children);
}

export function useNativeBridge(): NativeBridge {
  const bridge = useContext(NativeBridgeContext);
  if (!bridge) throw new Error("NativeBridgeProvider is required");
  return bridge;
}
