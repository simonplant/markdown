/**
 * Browser binding to the markdown-core WebAssembly module (EPIC-WASM / EPIC-CUTOVER).
 *
 * The core is compiled to wasm32-wasip1 (so tree-sitter's C gets a libc — see
 * docs/wasm-spike.md), instantiated here as a WASI *reactor* via a browser WASI
 * shim, and called over the hand-rolled C ABI in markdown-core/src/wasm_api.rs:
 * write the markdown into linear memory, call mc_diagnose / mc_format, read the
 * length-prefixed (u32 LE) JSON result, free both buffers.
 *
 * This replaces the Tauri `invoke("document_diagnose" | "document_format")` path.
 * The module is loaded lazily on first use and cached.
 */

import { WASI, OpenFile, File as WasiFile, ConsoleStdout } from "@bjorn3/browser_wasi_shim";

export interface Diagnostic {
  rule: string;
  severity: "error" | "warning" | "hint";
  start: number;
  end: number;
  message: string;
}

export interface Mutation {
  offset: number;
  delete: number;
  insert: string;
}

interface CoreExports {
  memory: WebAssembly.Memory;
  mc_alloc(len: number): number;
  mc_dealloc(ptr: number, len: number): void;
  mc_diagnose(ptr: number, len: number): number;
  mc_format(ptr: number, len: number): number;
}

let exportsPromise: Promise<CoreExports> | null = null;

/** Location of the compiled core. Served from `public/` (see scripts/build-wasm.sh). */
const WASM_URL = "/markdown_core.wasm";

async function loadCore(): Promise<CoreExports> {
  const wasi = new WASI(
    [],
    [],
    [
      new OpenFile(new WasiFile([])), // fd 0: stdin
      ConsoleStdout.lineBuffered((m) => console.log("[core]", m)), // fd 1
      ConsoleStdout.lineBuffered((m) => console.warn("[core]", m)), // fd 2
    ]
  );
  const wasm = await WebAssembly.compileStreaming(fetch(WASM_URL));
  const instance = await WebAssembly.instantiate(wasm, {
    wasi_snapshot_preview1: wasi.wasiImport,
  });
  // Reactor module: run _initialize (not _start) so the exports stay callable.
  wasi.initialize(instance as { exports: { memory: WebAssembly.Memory; _initialize?: () => void } });
  return instance.exports as unknown as CoreExports;
}

function core(): Promise<CoreExports> {
  if (!exportsPromise) exportsPromise = loadCore();
  return exportsPromise;
}

/** Call an `mc_*(ptr,len) -> ptr` entry point with `text`; parse the JSON result. */
function callJson<T>(ex: CoreExports, fn: (ptr: number, len: number) => number, text: string): T {
  const input = new TextEncoder().encode(text);
  const inPtr = ex.mc_alloc(input.length);
  new Uint8Array(ex.memory.buffer, inPtr, input.length).set(input);

  const resPtr = fn(inPtr, input.length);
  // Re-read views after the call: a grow() may have detached the old buffer.
  const len = new DataView(ex.memory.buffer).getUint32(resPtr, true);
  const bytes = new Uint8Array(ex.memory.buffer, resPtr + 4, len).slice();

  ex.mc_dealloc(inPtr, input.length);
  ex.mc_dealloc(resPtr, 4 + len);
  return JSON.parse(new TextDecoder().decode(bytes)) as T;
}

/** Parse + run the document doctor, returning diagnostics. */
export async function diagnose(text: string): Promise<Diagnostic[]> {
  const ex = await core();
  return callJson<Diagnostic[]>(ex, ex.mc_diagnose.bind(ex), text);
}

/** Parse + run the formatter, returning the mutations to apply. */
export async function format(text: string): Promise<Mutation[]> {
  const ex = await core();
  return callJson<Mutation[]>(ex, ex.mc_format.bind(ex), text);
}
