# Progress report — Tauri removed, core runs as WASM

The pivot is done: **Tauri is gone, the codebase is clean, and everything builds.**
The web frontend now reaches the engine through `markdown-core` compiled to
WebAssembly. All on branch `build/phase0-core-extraction` (not yet merged to main).

## The codebase now

- **One Rust crate** (`markdown-core`) — the workspace has no `src-tauri`, no glib
  patch. Builds in ~1.6s.
- **One web frontend** — a CodeMirror 6 PWA (`src/`, single `main.ts` / `index.html`
  / `vite.config.ts`). No `@tauri-apps` anywhere.
- **The engine runs as WASM** — `markdown-core` → `wasm32-wasip1`
  (`public/markdown_core.wasm`, 1.1 MB), loaded in the browser via a WASI shim
  (`src/core-wasm.ts`). `doctor.ts` and `format.ts` call it directly.

## Verified green

| Check | Result |
|---|---|
| `cargo build --workspace` | ✅ core only, no Tauri/glib |
| `cargo test -p markdown-core` | ✅ 81 passed |
| `npm run build` (tsc + vite) | ✅ PWA bundle, zero `@tauri-apps` |
| `npm run test:wasm` (Node `node:wasi`) | ✅ JS↔WASM boundary PASS |
| `node scripts/wasm-shim-check.mjs` (the **browser** `@bjorn3/browser_wasi_shim` path) | ✅ PASS |

The only thing not machine-verified is the visual run in a real browser DOM (no
headless browser installed here). The exact browser code path *is* verified in
Node; to see it live: **`npm run dev`**.

## What changed (commits on the branch)

```
EPIC-CUTOVER + EPIC-RETIRE-TAURI: replace Tauri IPC with the WASM core; delete Tauri
EPIC-WASM: npm build:wasm/test:wasm scripts + progress report
EPIC-WASM: JS<->WASM binding — core diagnose/format callable from a JS host
EPIC-WASM: markdown-core runs in WebAssembly (wasm32-wasip1) — proven
EPIC-WASM spike: tree-sitter compiles to wasm; libc gate identified
EPIC-CORE-API: extract wikilink/backlink surface into markdown-core
docs: BUILD_PLAN + reconcile backlog
(+ CI repoint, backlog status)
```

## Honest gaps / deliberate degradations (early-dev, fine to revisit)

- **Wikilink navigation + backlinks are no-ops in the web build.** They need real
  filesystem *paths*; the browser has file *handles*. Rendering of `[[links]]`
  still works. The path-based engine logic is intact in `markdown-core::wikilinks`
  for the future native Apple frontend; the browser needs a directory-handle model.
- **AI front-end files deleted** (`ai/settings/completions.ts`) — they were
  orphaned and Tauri-coupled. AI stays parked behind the Rust `ai` cargo feature.
- **The generated wasm is gitignored** — rebuild with `npm run build:wasm`
  (needs `brew install llvm wasi-libc wasmtime` + `rustup target add wasm32-wasip1`).
- **CI `wasm` job is `continue-on-error`** until its wasi-sdk pin is validated on
  CI; the build is proven locally.

## To merge

```
git checkout main && git merge --ff-only build/phase0-core-extraction
npm run dev        # see the PWA with the WASM engine
```

Pre-existing uncommitted working-tree changes (`.aishore/*`, some `docs/*`,
`CLAUDE.md`) were left untouched.

## Next (separate tracks, not blocking)

- Browser directory-handle model → restore wikilinks/backlinks in the web build.
- Native Apple frontend (EPIC-UNIFFI → EPIC-APPLE-*): the uniffi binding over the
  same `markdown-core` command surface, then TextKit 2.
- Grow the WASM ABI to the rest of `docs/CORE-API.md` as features need it.
