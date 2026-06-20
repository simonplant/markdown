// Node harness proving the JS <-> WASM boundary for markdown-core (EPIC-WASM).
//
// Instantiates the wasm32-wasip1 cdylib as a WASI reactor and calls the
// hand-rolled C ABI (mc_alloc / mc_diagnose / mc_format / mc_dealloc) the same
// way the browser PWA will: write a markdown string into linear memory, call
// the entry point, read the length-prefixed JSON result, free both buffers.
//
//   scripts/build-wasm.sh                 # produce the .wasm
//   node scripts/wasm-node-smoke.mjs      # run this harness
//
// This is the headless stand-in for "runs in a real browser": same module, same
// ABI, same WASI imports — only the host runtime differs.

import { WASI } from 'node:wasi';
import { readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { dirname, join } from 'node:path';

const root = join(dirname(fileURLToPath(import.meta.url)), '..');
const wasmPath = join(root, 'target/wasm32-wasip1/debug/markdown_core.wasm');

const wasi = new WASI({ version: 'preview1', args: [], env: {} });
const bytes = readFileSync(wasmPath);
const module = await WebAssembly.compile(bytes);
const instance = await WebAssembly.instantiate(module, wasi.getImportObject());
wasi.initialize(instance); // reactor module: runs _initialize, not _start

const { mc_alloc, mc_dealloc, mc_diagnose, mc_format, memory } = instance.exports;

// Call an mc_* entry point with a string; return the parsed JSON result.
function callJson(fn, text) {
  const input = new TextEncoder().encode(text);
  const inPtr = mc_alloc(input.length);
  new Uint8Array(memory.buffer, inPtr, input.length).set(input);

  const resPtr = fn(inPtr, input.length);
  // Re-read views after the call — allocation may have grown (detached) memory.
  const jsonLen = new DataView(memory.buffer).getUint32(resPtr, true);
  const jsonBytes = new Uint8Array(memory.buffer, resPtr + 4, jsonLen).slice();
  const json = new TextDecoder().decode(jsonBytes);

  mc_dealloc(inPtr, input.length);
  mc_dealloc(resPtr, 4 + jsonLen);
  return JSON.parse(json);
}

const sample = '# Title\n\n### Skipped a level\n\nA paragraph with a [broken](nope.md) link.\n';

const diagnostics = callJson(mc_diagnose, sample);
const mutations = callJson(mc_format, '# Heading\nNo blank line\n|a|b|\n|-|-|\n');

console.log('mc_diagnose ->', JSON.stringify(diagnostics));
console.log('mc_format   ->', JSON.stringify(mutations));

// Assertions: the boundary actually carried real engine output across.
let ok = true;
if (!Array.isArray(diagnostics) || diagnostics.length === 0) {
  console.error('FAIL: expected diagnostics for an h1->h3 skip / broken link');
  ok = false;
}
if (!diagnostics.some((d) => d.rule === 'heading-hierarchy')) {
  console.error('FAIL: expected a heading-hierarchy diagnostic');
  ok = false;
}
if (!Array.isArray(mutations)) {
  console.error('FAIL: format did not return an array');
  ok = false;
}
console.log(ok ? 'WASM NODE SMOKE: PASS' : 'WASM NODE SMOKE: FAIL');
process.exit(ok ? 0 : 1);
