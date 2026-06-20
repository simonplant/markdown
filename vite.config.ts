import { defineConfig } from "vite";
import { resolve } from "path";

// Single frontend: the CodeMirror 6 PWA. The markdown-core engine runs as
// WebAssembly (public/markdown_core.wasm, loaded by src/core-wasm.ts). No Tauri.
export default defineConfig({
  root: "src",
  publicDir: resolve(__dirname, "public"),
  build: {
    outDir: "../dist",
    emptyOutDir: true,
    rollupOptions: {
      input: {
        main: resolve(__dirname, "src/index.html"),
        sw: resolve(__dirname, "src/sw.ts"),
      },
      output: {
        // Service worker must sit at the root as sw.js (no hash).
        entryFileNames: (chunkInfo) =>
          chunkInfo.name === "sw" ? "sw.js" : "assets/[name]-[hash].js",
      },
    },
  },
});
