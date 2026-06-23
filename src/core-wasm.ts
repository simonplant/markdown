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
  // Memoize the load, but reset the cache if it *rejects* (a transient fetch /
  // compile failure) so a later call can retry — otherwise one flaky load
  // permanently breaks the doctor and Format for the whole page session.
  if (!exportsPromise) {
    exportsPromise = loadCore().catch((e) => {
      exportsPromise = null;
      throw e;
    });
  }
  return exportsPromise;
}

/** Call an `mc_*(ptr,len) -> ptr` entry point with `text`; parse the JSON result. */
function callJson<T>(ex: CoreExports, fn: (ptr: number, len: number) => number, text: string): T {
  const input = new TextEncoder().encode(text);
  const inPtr = ex.mc_alloc(input.length);
  new Uint8Array(ex.memory.buffer, inPtr, input.length).set(input);

  let resPtr = 0;
  let resLen = 0;
  try {
    resPtr = fn(inPtr, input.length);
    // A null result means the core's allocation failed; treat as empty rather
    // than reading a garbage length from offset 0.
    if (resPtr === 0) return JSON.parse("[]") as T;
    // Re-read views after the call: a grow() may have detached the old buffer.
    resLen = new DataView(ex.memory.buffer).getUint32(resPtr, true);
    const bytes = new Uint8Array(ex.memory.buffer, resPtr + 4, resLen).slice();
    return JSON.parse(new TextDecoder().decode(bytes)) as T;
  } finally {
    // Always free both buffers, even if the call traps or the read/parse throws,
    // so failures don't leak the WASM heap on every debounced edit.
    ex.mc_dealloc(inPtr, input.length);
    if (resPtr !== 0) ex.mc_dealloc(resPtr, 4 + resLen);
  }
}

/** UTF-8 byte length of a Unicode code point. */
function utf8Len(cp: number): number {
  if (cp <= 0x7f) return 1;
  if (cp <= 0x7ff) return 2;
  if (cp <= 0xffff) return 3;
  return 4;
}

/**
 * The core reports spans as UTF-8 *byte* offsets, but CodeMirror positions are
 * UTF-16 code units (JS string indices). For any document containing multi-byte
 * characters the two diverge, so format mutations and diagnostic spans must be
 * translated before they touch the editor. Returns a fast mapper over the text.
 */
function byteToCharMapper(text: string): (byteOffset: number) => number {
  // ASCII fast path: byte offset == char offset, no table needed.
  const encodedLen = new TextEncoder().encode(text).length;
  if (encodedLen === text.length) return (b) => b;

  // Breakpoints at each code-point boundary: parallel byte/char positions.
  const bytePoints: number[] = [0];
  const charPoints: number[] = [0];
  let bytePos = 0;
  let charPos = 0;
  for (const ch of text) {
    bytePos += utf8Len(ch.codePointAt(0)!);
    charPos += ch.length; // 1 for BMP, 2 for a surrogate pair
    bytePoints.push(bytePos);
    charPoints.push(charPos);
  }
  return (byteOffset: number): number => {
    if (byteOffset <= 0) return 0;
    // Largest breakpoint <= byteOffset (binary search).
    let lo = 0;
    let hi = bytePoints.length - 1;
    while (lo < hi) {
      const mid = (lo + hi + 1) >> 1;
      if (bytePoints[mid] <= byteOffset) lo = mid;
      else hi = mid - 1;
    }
    return charPoints[lo];
  };
}

/** Parse + run the document doctor, returning diagnostics with char offsets. */
export async function diagnose(text: string): Promise<Diagnostic[]> {
  const ex = await core();
  const diags = callJson<Diagnostic[]>(ex, ex.mc_diagnose.bind(ex), text);
  const toChar = byteToCharMapper(text);
  return diags.map((d) => ({ ...d, start: toChar(d.start), end: toChar(d.end) }));
}

/** Parse + run the formatter, returning mutations with char-based offsets. */
export async function format(text: string): Promise<Mutation[]> {
  const ex = await core();
  const muts = callJson<Mutation[]>(ex, ex.mc_format.bind(ex), text);
  const toChar = byteToCharMapper(text);
  return muts.map((m) => {
    const start = toChar(m.offset);
    const end = toChar(m.offset + m.delete);
    return { offset: start, delete: end - start, insert: m.insert };
  });
}
