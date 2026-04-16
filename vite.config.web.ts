import { defineConfig } from "vite";
import { resolve } from "path";

export default defineConfig({
  root: "src",
  publicDir: resolve(__dirname, "public"),
  build: {
    outDir: "../dist-web",
    emptyOutDir: true,
    rollupOptions: {
      input: {
        main: resolve(__dirname, "src/index-web.html"),
        sw: resolve(__dirname, "src/sw.ts"),
      },
      output: {
        entryFileNames: (chunkInfo) => {
          // Service worker must be at the root as sw.js (no hash)
          if (chunkInfo.name === "sw") return "sw.js";
          return "assets/[name]-[hash].js";
        },
      },
    },
  },
  resolve: {
    alias: {
      // Stub out Tauri APIs so shared modules that conditionally import them
      // do not break the web build.
      "@tauri-apps/api/core": "/tauri-stub.ts",
      "@tauri-apps/plugin-dialog": "/tauri-stub.ts",
      "@tauri-apps/api/event": "/tauri-stub.ts",
      "@tauri-apps/api/window": "/tauri-stub.ts",
    },
  },
});
