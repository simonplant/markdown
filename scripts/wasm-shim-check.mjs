// Validates the EXACT browser code path of src/core-wasm.ts — the
// @bjorn3/browser_wasi_shim instantiation + the mc_* C ABI — in Node, without a
// headless browser. The only thing this doesn't cover vs the browser is
// fetch()/compileStreaming and the DOM, which are not where the risk is.

import { WASI, OpenFile, File as WasiFile, ConsoleStdout } from "@bjorn3/browser_wasi_shim";
import { readFileSync } from "node:fs";
import { fileURLToPath } from "node:url";
import { dirname, join } from "node:path";

const root = join(dirname(fileURLToPath(import.meta.url)), "..");
const bytes = readFileSync(join(root, "public/markdown_core.wasm"));

const wasi = new WASI(
  [],
  [],
  [
    new OpenFile(new WasiFile([])),
    ConsoleStdout.lineBuffered((m) => console.log("[core]", m)),
    ConsoleStdout.lineBuffered((m) => console.warn("[core]", m)),
  ]
);
const module = await WebAssembly.compile(bytes);
const instance = await WebAssembly.instantiate(module, {
  wasi_snapshot_preview1: wasi.wasiImport,
});
wasi.initialize(instance);

const ex = instance.exports;
function callJson(fn, text) {
  const input = new TextEncoder().encode(text);
  const inPtr = ex.mc_alloc(input.length);
  new Uint8Array(ex.memory.buffer, inPtr, input.length).set(input);
  const resPtr = fn(inPtr, input.length);
  const len = new DataView(ex.memory.buffer).getUint32(resPtr, true);
  const out = new Uint8Array(ex.memory.buffer, resPtr + 4, len).slice();
  ex.mc_dealloc(inPtr, input.length);
  ex.mc_dealloc(resPtr, 4 + len);
  return JSON.parse(new TextDecoder().decode(out));
}

const diags = callJson(ex.mc_diagnose, "# A\n\n### C\n");
console.log("diagnose ->", JSON.stringify(diags));
const ok = Array.isArray(diags) && diags.some((d) => d.rule === "heading-hierarchy");
console.log(ok ? "SHIM CHECK (browser_wasi_shim): PASS" : "SHIM CHECK: FAIL");
process.exit(ok ? 0 : 1);
