import { promises as fs } from "node:fs";
import { dirname, resolve } from "node:path";
import { fileURLToPath } from "node:url";
import { defineConfig, type Plugin } from "vite";

const packageDir = dirname(fileURLToPath(import.meta.url));
const repoRoot = resolve(packageDir, "../..");

function injectStableKey(): Plugin {
  return {
    name: "inject-stable-extension-key",
    async writeBundle() {
      const manifestPath = resolve(packageDir, "dist/manifest.json");
      const manifest = JSON.parse(await fs.readFile(manifestPath, "utf8"));
      manifest.key = (
        await fs.readFile(resolve(repoRoot, "Config/chrome-extension-key.b64"), "utf8")
      ).trim();
      await fs.writeFile(manifestPath, `${JSON.stringify(manifest, null, 2)}\n`);
    },
  };
}

export default defineConfig({
  publicDir: "public",
  plugins: [injectStableKey()],
  build: {
    outDir: "dist",
    emptyOutDir: true,
    rollupOptions: {
      input: resolve(packageDir, "src/service-worker.ts"),
      output: {
        entryFileNames: "service-worker.js",
      },
    },
  },
});
