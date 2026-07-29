import { StrictMode } from "react";
import { createRoot } from "react-dom/client";
import { App } from "./App";
import { createNativeBridge, NativeBridgeProvider } from "./bridge/nativeBridge";

const root = document.getElementById("root");
if (!root) throw new Error("Missing #root");

createRoot(root).render(
  <StrictMode>
    <NativeBridgeProvider bridge={createNativeBridge()}>
      <App />
    </NativeBridgeProvider>
  </StrictMode>,
);
