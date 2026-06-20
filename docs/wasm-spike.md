# WASM spike findings (EPIC-WASM, BUILD_PLAN Phase 1)

**Date:** 2026-06-19. **Goal:** fail-fast check of the highest-impact unknown in
the build plan — can `markdown-core` (with tree-sitter) compile to and run as
WebAssembly?

**Status: RESOLVED — option A works, proven end-to-end.** `markdown-core` (incl.
tree-sitter) compiles to `wasm32-wasip1` and **runs under wasmtime**: it opens,
parses, diagnoses, and formats the full baseline corpus (large.md = 202 KB → 30
format mutations) inside WASM. Reproduce with `scripts/build-wasm.sh run`.

```
$ scripts/build-wasm.sh run
wasm_smoke OK: file=docs/baseline-corpus/small.md  bytes=465    diagnostics=0 format_mutations=0
wasm_smoke OK: file=docs/baseline-corpus/medium.md bytes=16006  diagnostics=0 format_mutations=1
wasm_smoke OK: file=docs/baseline-corpus/large.md  bytes=202552 diagnostics=0 format_mutations=30
```

The toolchain decision (below) is settled: **`wasm32-wasip1` + wasi-libc sysroot.**
The rest of this doc records how we got there.

---

**Original question / first attempt:** could the core compile to the bare
`wasm32-unknown-unknown` target? No — that target has no libc and tree-sitter's
`scanner.c` needs `<wchar.h>`. That dead end is what pointed us at WASI.

## What was tried

```
rustup target add wasm32-unknown-unknown            # added
brew install llvm                                   # clang with the wasm32 target
CC_wasm32_unknown_unknown=/opt/homebrew/opt/llvm/bin/clang \
AR_wasm32_unknown_unknown=/opt/homebrew/opt/llvm/bin/llvm-ar \
CFLAGS_wasm32_unknown_unknown="-Wno-error=incompatible-pointer-types" \
cargo build -p markdown-core --target wasm32-unknown-unknown
```

(`markdown-core` already declares `crate-type = [rlib, cdylib, staticlib]` and
gates `notify`/`watcher` off wasm32 — both committed in EPIC-CORE-API.)

## What we learned (in order)

1. **Apple's system clang cannot target wasm32** ("No available targets are
   compatible with triple wasm32-unknown-unknown"). Need LLVM's clang →
   `brew install llvm` provides one with `wasm32`/`wasm64` targets. ✅ cleared.
2. **tree-sitter's C *does* compile for wasm32 with llvm clang.** `parser.c` and
   the `tree-sitter-language` wasm shim (`stdio.c`, `stdlib.c`) compile. ✅
3. **clang 16+ promotes `incompatible-pointer-types` to a hard error**, which the
   tree-sitter `stdlib.c` wasm shim trips. Fixed with
   `-Wno-error=incompatible-pointer-types`. ✅ cleared.
4. **The real gate: no libc.** `tree-sitter-markdown/src/scanner.c` does
   `#include <wchar.h>` → `fatal error: 'wchar.h' file not found`.
   `wasm32-unknown-unknown` is a bare target with no system headers and no libc.
   The tree-sitter wasm `include/` shims `stdio.h`/`stdlib.h` but not `wchar.h`,
   and even a header shim wouldn't link the wide-char functions the scanner uses
   (`iswspace`/`iswalnum`-style) — those need real implementations.

## The fork — CHOSEN: option A (`wasm32-wasip1` + wasi-libc)

The options that were on the table (bare `wasm32-unknown-unknown` is ruled out by
the no-libc finding above):

- **A. `wasm32-wasip1` + wasi sysroot — CHOSEN, and proven (2026-06-19).** WASI
  ships a libc, so `wchar.h` and the wide-char functions resolve and the existing
  Rust crate compiles unchanged. Builds and runs (see top of doc). Cost going
  forward: the browser needs a small WASI shim (e.g. `@bjorn3/browser_wasi_shim`)
  since tree-sitter touches only a handful of libc calls. Most faithful to "one
  Rust core in WASM."
- **B. libc sysroot for `wasm32-unknown-unknown`.** Not pursued — A worked.
- **C. `web-tree-sitter` (prebuilt parser WASM) + Rust-WASM for the rest.** Not
  pursued — it splits the parser from `doctor`/`formatter` (which consume a
  tree-sitter `Tree` in Rust) and partly defeats the shared-core design.

## The working recipe (reproducible)

`scripts/build-wasm.sh` encodes this; run `scripts/build-wasm.sh run` to build and
execute the corpus smoke test under wasmtime.

Toolchain (macOS): `brew install llvm wasi-libc wasmtime` and
`rustup target add wasm32-wasip1`. The `cc` crate compiles tree-sitter's C when
pointed at LLVM's clang plus the wasi sysroot:

```
CC_wasm32_wasip1=$(brew --prefix llvm)/bin/clang
AR_wasm32_wasip1=$(brew --prefix llvm)/bin/llvm-ar
CFLAGS_wasm32_wasip1="--sysroot=$(brew --prefix wasi-libc)/share/wasi-sysroot \
  -I$(brew --prefix wasi-libc)/share/wasi-sysroot/include/wasm32-wasip1 \
  -Wno-error=incompatible-pointer-types"
cargo build -p markdown-core --target wasm32-wasip1
```

The proof binary is `markdown-core/src/bin/wasm_smoke.rs`, run under wasmtime with
`--dir=.` for file access.

## Next for EPIC-WASM (now unblocked)

1. Replace the WASI smoke binary's argv/stdout interface with a real JS-callable
   surface: `#[no_mangle] extern "C"` entry points over wasm memory (alloc/free +
   pointer/len for the markdown string in, a serialized result out) — the buffer-in
   / buffer-out shape from `docs/CORE-API.md`. wasm-bindgen targets
   `wasm32-unknown-unknown`, so under WASI we hand-roll this thin layer.
2. Instantiate in the browser with a WASI shim; the PWA shell owns the file handle
   and passes content as bytes (the core never touches the FS in the browser).
3. Capture an in-browser web baseline slice; extend the regression gate.

## Toolchain notes for whoever picks this up

- llvm clang: `/opt/homebrew/opt/llvm/bin/clang` (has wasm targets); `llvm-ar`
  alongside. `wasm-ld` was not in that bin dir but Rust links via bundled
  `rust-lld`, so cdylib linking didn't need it.
- The `incompatible-pointer-types` flag will still be needed for the tree-sitter
  shim under any of the options above.
- `notify`/`watcher` are already excluded from wasm32 (Cargo.toml
  `[target.'cfg(not(target_arch = "wasm32"))'.dependencies]`).
