import { promises as fs } from "node:fs";
import { dirname, resolve } from "node:path";
import { fileURLToPath } from "node:url";
import { defineConfig, type Plugin } from "vite";

const packageDir = dirname(fileURLToPath(import.meta.url));
const repoRoot = resolve(packageDir, "../..");

function injectStableKey(outputDirectory: string): Plugin {
  return {
    name: "inject-stable-extension-key",
    async writeBundle() {
      const manifestPath = resolve(
        packageDir,
        outputDirectory,
        "manifest.json",
      );
      const manifest = JSON.parse(await fs.readFile(manifestPath, "utf8"));
      manifest.key = (
        await fs.readFile(resolve(repoRoot, "Config/chrome-extension-key.b64"), "utf8")
      ).trim();
      await fs.writeFile(manifestPath, `${JSON.stringify(manifest, null, 2)}\n`);
    },
  };
}

export default defineConfig(({ mode }) => {
  const isE2EBuild = mode === "e2e";
  const outputDirectory = isE2EBuild ? "dist-e2e" : "dist";

  return {
    publicDir: "public",
    define: {
      __INKBEAM_E2E__: JSON.stringify(isE2EBuild),
    },
    plugins: [injectStableKey(outputDirectory)],
    build: {
      outDir: outputDirectory,
      emptyOutDir: true,
      rollupOptions: {
        input: resolve(packageDir, "src/service-worker.ts"),
        output: {
          entryFileNames: "service-worker.js",
        },
      },
    },
  };
});
