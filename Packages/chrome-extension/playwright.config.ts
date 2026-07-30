import { defineConfig } from "@playwright/test";

export default defineConfig({
  testDir: "./tests",
  testMatch: "**/*.e2e.ts",
  workers: 1,
  fullyParallel: false,
  use: {
    trace: "retain-on-failure",
  },
});
