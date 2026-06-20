# Autonomous session progress — 2026-06-19

You asked me to loop on the build plan toward a "clean new codebase." Here's
exactly what happened, what's verified, and the one decision waiting for you.

## TL;DR

- All work is on branch **`build/phase0-core-extraction`** (4 commits), **not** on
  `main`. The workspace is **green**: `markdown-core` 76 tests pass; the Tauri
  shell still compiles. Nothing is broken.
- I did **not** delete Tauri. Doing so safely requires a working WASM build proven
  at browser parity, and the WASM build hit a real toolchain gate (below). Ripping
  out `src-tauri` blind would have left you a broken repo — the opposite of the goal.
- **One decision needs you:** which WASM toolchain (see "Decision needed").

## What landed (committed, verified)

1. **BUILD_PLAN.md + backlog reconciliation** (commit `3240851`) — the full plan
   current→v1.0 and the backlog cleaned to the native-Apple/PWA architecture
   (6 Tauri items retired to `backlog/archive/retired-tauri.json`, 9 new epics).

2. **EPIC-CORE-API: command-surface extraction** (commit `4a05a53`) — the real
   architectural cleanup, fully tested:
   - New `markdown-core/src/wikilinks.rs`: wikilink resolve, backlinks, target
     creation moved out of the Tauri shell into the core (so every binding reaches
     the same logic — ARCHITECTURE §3.8). **6 new tests.**
   - `src-tauri/src/lib.rs` shrank ~176 lines to thin pass-throughs.
   - `markdown-core` now declares `crate-type = [rlib, cdylib, staticlib]` (one
     crate → WASM module + Apple static lib + workspace rlib).
   - `notify`/`watcher` gated off wasm32 (no web equivalent).
   - **Bug fixed:** the relocated tree-walk was unbounded — an unresolved wikilink
     could trigger a near-full-disk scan (it hung a test from a temp dir). Added a
     4096-directory visit budget. This latent defect existed in the old shell code too.

3. **EPIC-WASM spike** (commit `c2fe8ef`, `docs/wasm-spike.md`) — the highest-risk
   unknown in the plan, run fail-fast. Result below.

## The WASM spike result (this is the gate)

Good news: **tree-sitter's C does compile to WebAssembly** with LLVM's clang
(`brew install llvm` — installed). I cleared two blockers (Apple clang lacks the
wasm target; clang 16+ rejects a tree-sitter pointer-type shim).

The wall: **`wasm32-unknown-unknown` has no libc**, and tree-sitter's `scanner.c`
needs `<wchar.h>`. That's not a flag fix — it's a toolchain choice.

## Decision needed (then EPIC-WASM can proceed)

Which WASM toolchain (full detail in `docs/wasm-spike.md`):

- **A — `wasm32-wasip1` + wasi-sdk** *(my recommendation)*: WASI ships a libc, so
  the existing Rust core compiles unchanged; the browser needs a thin WASI shim.
  Keeps the single shared Rust core intact.
- **B — libc sysroot for `wasm32-unknown-unknown`**: browser-native, no WASI
  runtime, but the fiddliest to keep green.
- **C — `web-tree-sitter` (prebuilt parser) + Rust-WASM for the rest**: avoids
  compiling tree-sitter's C, but splits the parser from doctor/formatter — awkward.

Once you pick, EPIC-WASM is unblocked, then EPIC-CUTOVER (replace Tauri IPC with
the WASM core) → EPIC-RETIRE-TAURI gives you the actual "no Tauri" codebase.

## To review / merge

```
git log --oneline main..build/phase0-core-extraction   # the 4 commits
git checkout main && git merge --ff-only build/phase0-core-extraction
```

(The pre-existing uncommitted changes in your working tree — `.aishore/*`, some
`docs/*`, `CLAUDE.md` etc. — I left untouched; they predate this session.)

## What I deliberately did NOT do

- Delete `src-tauri` / retire Tauri — needs verified browser parity first.
- Install wasi-sdk and force the WASM build through autonomously — that's the
  architecture decision above; better made deliberately than hacked overnight.
- Touch the Apple/uniffi track — gated on the WASM toolchain call and needs Xcode
  + on-device verification.
