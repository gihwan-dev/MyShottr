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
        myshottr?: {
          postMessage(message: unknown): void;
        };
      };
    };
  }
}

export type NativeBridge = {
  send<T extends EditorToNativeType>(type: T, payload: PayloadFor<T>): Promise<void>;
  subscribe(handler: (message: NativeToEditorEnvelope) => void): () => void;
};

const nativeMessageEvent = "myshottr:native-message";

export function createNativeBridge(): NativeBridge {
  return {
    async send<T extends EditorToNativeType>(type: T, payload: PayloadFor<T>): Promise<void> {
      const message = EditorToNativeEnvelopeSchema.parse({
        protocolVersion: PROTOCOL_VERSION,
        requestId: crypto.randomUUID(),
        type,
        payload,
      });
      const handler = window.webkit?.messageHandlers?.myshottr;
      if (!handler) throw new Error("MyShottr native bridge is unavailable");
      handler.postMessage(message);
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
          const code = typeof event.detail === "object" && event.detail !== null && "type" in event.detail
            && event.detail.type === "loadDocument"
            ? "INVALID_DOCUMENT"
            : "INVALID_MESSAGE";
          void this.send("bridgeError", {
            code,
            message: code === "INVALID_DOCUMENT"
              ? "Native attempted to load an invalid document"
              : "Native sent an invalid bridge message",
          });
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
