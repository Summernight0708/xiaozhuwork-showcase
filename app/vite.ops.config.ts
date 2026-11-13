import { fileURLToPath, URL } from "node:url";

import vue from "@vitejs/plugin-vue";
import { defineConfig } from "vite";

export default defineConfig({
  root: fileURLToPath(new URL("./src-ops", import.meta.url)),
  envDir: fileURLToPath(new URL(".", import.meta.url)),
  plugins: [vue()],
  resolve: {
    alias: {
      "@ops": fileURLToPath(new URL("./src-ops", import.meta.url)),
      "@shared": fileURLToPath(new URL("./src-shared", import.meta.url)),
    },
  },
  server: {
    host: "127.0.0.1",
    port: 5174,
    strictPort: true,
  },
  build: {
    outDir: fileURLToPath(new URL("./dist-ops", import.meta.url)),
    emptyOutDir: true,
  },
});
