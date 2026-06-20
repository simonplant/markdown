# Autonomous session progress — 2026-06-19

You asked me to loop on the build plan toward a clean new codebase, then (later)
to pick **option A** for WASM and continue while you slept. Here's where it landed.

## TL;DR

- All work is on branch **`build/phase0-core-extraction`** (7 commits), not `main`.
  Everything is **green and verified**: `markdown-core` 81 tests pass; the core
  **runs in WebAssembly and is callable from JS**; the Tauri shell still compiles.
- **The two hardest, highest-risk milestones of the whole build plan are done:**
  EPIC-CORE-API (command-surface extraction) and EPIC-WASM (core in WASM, proven
  end-to-end). The remaining path to "no Tauri" is now mostly wiring, not unknowns.
- I did **not** delete Tauri or rewrite the web frontend — those need a real
  browser to verify, which I can't do well headlessly. Nothing is left half-done.

## What landed (committed, verified)

1. **BUILD_PLAN.md + backlog reconciliation** — plan current→v1.0; backlog cleaned
   to the native-Apple/PWA architecture (6 Tauri items retired, 9 epics added).

2. **EPIC-CORE-API — command-surface extraction** (tested). Wikilink/backlink/
   target-creation logic moved out of the Tauri shell into `markdown-core::wikilinks`
   (6 tests); shell shrank ~176 lines to thin wrappers. Crate-types set to
   `[rlib, cdylib, staticlib]`; `notify`/`watcher` gated off wasm32. Fixed a real
   latent bug (unbounded wikilink tree-walk → near-full-disk scan; added a budget).

3. **EPIC-WASM — the #1 risk, now RESOLVED and IMPLEMENTED** (`docs/wasm-spike.md`):
   - **Decision A confirmed & working:** `markdown-core` (incl. tree-sitter)
     compiles to `wasm32-wasip1` and **runs under wasmtime** over the full baseline
     corpus (large.md 202KB → 30 format mutations).
   - **JS↔WASM boundary built and proven:** `markdown-core/src/wasm_api.rs` is a
     hand-rolled C ABI (`mc_alloc`/`mc_dealloc`/`mc_diagnose`/`mc_format`,
     length-prefixed JSON out). `scripts/wasm-node-smoke.mjs` instantiates the
     module as a WASI reactor in Node — the headless stand-in for the browser PWA —
     and round-trips markdown → real diagnostics/mutations JSON. **PASS.**
   - Reproducible: `npm run build:wasm`, `npm run test:wasm`, or
     `scripts/build-wasm.sh {run|node|all}`. Toolchain: `brew install llvm
     wasi-libc wasmtime` + `rustup target add wasm32-wasip1`.

## Commits on the branch

```
c43f3fa EPIC-WASM: JS<->WASM binding — core diagnose/format callable from a JS host
51782b5 EPIC-WASM: markdown-core runs in WebAssembly (wasm32-wasip1) — proven
a1e3fc7 docs: autonomous session progress report
c2fe8ef EPIC-WASM spike: tree-sitter compiles to wasm; libc gate identified
4a05a53 EPIC-CORE-API: extract wikilink/backlink surface into markdown-core
3240851 docs: BUILD_PLAN (current→v1.0) + reconcile backlog to native-Apple/PWA architecture
(+ this report)
```

## What's next (no blockers, but needs a browser / your eyes)

1. **Browser instantiation** — wire a browser WASI shim (e.g.
   `@bjorn3/browser_wasi_shim`) + vite so the same module runs in-page. The Node
   harness already proves the boundary; this is wiring + a headless-browser check.
2. **Grow the ABI** to the rest of `docs/CORE-API.md` (open/edit/save-buffer/
   viewport/undo-redo) as EPIC-CUTOVER consumes each call. Note: wikilink/backlink
   currently touch the FS directly — in the browser the **shell** supplies file
   content/lists, so those get a content-in signature during cutover.
3. **EPIC-CUTOVER** — replace the ~15 `invoke()` sites in `src/main.ts` with the
   `core` adapter + PWA shell, then **EPIC-RETIRE-TAURI** gives the actual no-Tauri
   codebase. I held off because verifying parity needs the running PWA in a browser.

## To review / merge

```
git log --oneline main..build/phase0-core-extraction
git checkout main && git merge --ff-only build/phase0-core-extraction
npm run test:wasm        # see the core run in WASM from JS
cargo test -p markdown-core --lib   # 81 pass
```

Your pre-existing uncommitted working-tree changes (`.aishore/*`, some `docs/*`,
`CLAUDE.md`) I left untouched.
