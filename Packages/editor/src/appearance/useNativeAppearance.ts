import { useEffect } from "react";

import { useNativeBridge } from "../bridge/nativeBridge";

export function useNativeAppearance(): void {
  const bridge = useNativeBridge();

  useEffect(
    () => bridge.subscribe((message) => {
      if (message.type !== "setAppearance") return;
      document.documentElement.dataset.colorScheme =
        message.payload.colorScheme;
      document.documentElement.style.colorScheme =
        message.payload.colorScheme;
    }),
    [bridge],
  );
}
