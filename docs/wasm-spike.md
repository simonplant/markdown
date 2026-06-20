# WASM spike findings (EPIC-WASM, BUILD_PLAN Phase 1)

**Date:** 2026-06-19. **Goal:** fail-fast check of the highest-impact unknown in
the build plan — can `markdown-core` (with tree-sitter) compile to WebAssembly?
**Status:** partial — the C compiles, but the bare `wasm32-unknown-unknown`
target's lack of a libc is a hard gate that forces a toolchain decision.

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

## The fork (decide in EPIC-WASM, don't hack)

Bare `wasm32-unknown-unknown` + the Rust tree-sitter crate's C is the wrong pairing
because of (4). The real options, in rough order of preference:

- **A. `wasm32-wasip1` + wasi-sdk sysroot.** WASI ships a libc, so `wchar.h` and
  the wide-char functions resolve and the existing Rust crate compiles unchanged.
  Cost: the browser needs a small WASI shim (e.g. the `@bjorn3/browser_wasi_shim`
  or wasmer-js) since tree-sitter only touches a handful of libc calls. Most
  faithful to "one Rust core in WASM."
- **B. Provide a libc sysroot to clang for `wasm32-unknown-unknown`** (point `CFLAGS`
  at a wasi-sdk `--sysroot` while keeping the unknown-unknown Rust target). Gets a
  browser-native module without a WASI runtime, but is the fiddliest to keep green.
- **C. `web-tree-sitter` (official prebuilt parser WASM) for parsing, Rust-WASM for
  the rest.** Avoids compiling tree-sitter's C ourselves, but splits the parser
  (JS-side) from `doctor`/`formatter` (which consume a tree-sitter `Tree` in Rust)
  — that boundary is awkward and partly defeats the shared-core design. Least
  preferred unless A and B both prove painful.

**Recommendation:** try **A** first. It keeps the single Rust core intact and only
adds a thin browser WASI shim. Validate with the same fail-fast loop: get
`cargo build --target wasm32-wasip1` green, then a Node/browser harness that parses
a corpus doc through the real module.

## Toolchain notes for whoever picks this up

- llvm clang: `/opt/homebrew/opt/llvm/bin/clang` (has wasm targets); `llvm-ar`
  alongside. `wasm-ld` was not in that bin dir but Rust links via bundled
  `rust-lld`, so cdylib linking didn't need it.
- The `incompatible-pointer-types` flag will still be needed for the tree-sitter
  shim under any of the options above.
- `notify`/`watcher` are already excluded from wasm32 (Cargo.toml
  `[target.'cfg(not(target_arch = "wasm32"))'.dependencies]`).
