import { fileURLToPath, URL } from "node:url";

import vue from "@vitejs/plugin-vue";
import { defineConfig } from "vitest/config";

export default defineConfig({
  plugins: [vue()],
  resolve: {
    alias: {
      "@": fileURLToPath(new URL("./src", import.meta.url)),
      "@ops": fileURLToPath(new URL("./src-ops", import.meta.url)),
      "@shared": fileURLToPath(new URL("./src-shared", import.meta.url)),
    },
  },
  test: {
    environment: "jsdom",
    setupFiles: ["./tests/setup.ts"],
    exclude: [
      "tests/database/**",
      "tests/e2e/**",
      "tests/visual/**",
      "tests/observability/**",
      "tests/observability/**",
      "node_modules/**",
      ".webcodex-managed-worktrees/**",
    ],
  },
});
