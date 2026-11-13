import { defineConfig, devices } from "@playwright/test";

export default defineConfig({
  testDir: "./tests/observability",
  testMatch: "observability-privacy.e2e.ts",
  globalSetup: "./tests/observability/global-setup.ts",
  workers: 1,
  use: {
    baseURL: "http://127.0.0.1:4173",
    trace: "on-first-retry",
  },
  projects: [
    { name: "desktop-chromium", use: { ...devices["Desktop Chrome"] } },
  ],
});
