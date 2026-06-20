#!/usr/bin/env bash
# Build (and optionally run) markdown-core for wasm32-wasip1 — EPIC-WASM.
#
# Why this script exists: tree-sitter's C needs a WASI libc sysroot to compile
# for WebAssembly (wasm32-unknown-unknown is libc-less; see docs/wasm-spike.md).
# This points the `cc` crate at LLVM's wasm-capable clang plus the wasi-libc
# sysroot. Toolchain (macOS): `brew install llvm wasi-libc wasmtime` and
# `rustup target add wasm32-wasip1`.
#
# Paths are derived from `brew --prefix` but can be overridden via env
# (LLVM_PREFIX, WASI_SYSROOT) for CI / Linux where wasi-sdk lives elsewhere.
#
#   scripts/build-wasm.sh              # build the cdylib/staticlib + smoke bin
#   scripts/build-wasm.sh run          # build, then run wasm_smoke under wasmtime
set -euo pipefail

TARGET=wasm32-wasip1
LLVM_PREFIX="${LLVM_PREFIX:-$(brew --prefix llvm 2>/dev/null || echo /usr/local/opt/llvm)}"
WASI_SYSROOT="${WASI_SYSROOT:-$(brew --prefix wasi-libc 2>/dev/null)/share/wasi-sysroot}"

if [[ ! -x "$LLVM_PREFIX/bin/clang" ]]; then
  echo "error: no clang at $LLVM_PREFIX/bin/clang (brew install llvm, or set LLVM_PREFIX)" >&2
  exit 1
fi
if [[ ! -d "$WASI_SYSROOT" ]]; then
  echo "error: no wasi sysroot at $WASI_SYSROOT (brew install wasi-libc, or set WASI_SYSROOT)" >&2
  exit 1
fi

# cc-rs honours these per-target env vars when compiling tree-sitter's C.
export CC_wasm32_wasip1="$LLVM_PREFIX/bin/clang"
export AR_wasm32_wasip1="$LLVM_PREFIX/bin/llvm-ar"
export CFLAGS_wasm32_wasip1="--sysroot=$WASI_SYSROOT -I$WASI_SYSROOT/include/wasm32-wasip1 -Wno-error=incompatible-pointer-types -Wno-incompatible-pointer-types"

echo "==> building markdown-core for $TARGET"
cargo build -p markdown-core --target "$TARGET"
cargo build -p markdown-core --bin wasm_smoke --target "$TARGET"

if [[ "${1:-}" == "run" || "${1:-}" == "all" ]]; then
  echo "==> running wasm_smoke under wasmtime against the baseline corpus"
  for f in small medium large; do
    wasmtime run --dir=. "target/$TARGET/debug/wasm_smoke.wasm" "docs/baseline-corpus/$f.md"
  done
fi

if [[ "${1:-}" == "node" || "${1:-}" == "all" ]]; then
  echo "==> running the JS<->WASM boundary harness under node"
  node scripts/wasm-node-smoke.mjs
fi

echo "==> done"
