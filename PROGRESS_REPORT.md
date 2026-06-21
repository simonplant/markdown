# Progress report — three frontends over one Rust core, built and running

The pivot is done and the build is well past it. **Tauri is gone, the codebase is
clean, and all three frontends run over a single shared `markdown-core`:** a
CodeMirror 6 web PWA with the core as WebAssembly, and a native iOS + macOS app
on TextKit 2 with the core bound in-process via uniffi. All merged to `main`.

## The codebase now

- **One Rust crate** (`markdown-core`) — `crate-type = ["rlib", "cdylib", "staticlib"]`.
  No `src-tauri`, no glib patch. Parser, formatter, doctor, `String` document model,
  wikilinks, math span detection. `ffi.rs` is the uniffi surface; `wasm_api.rs` is the
  hand-rolled C ABI for the browser. AI is parked behind the off-by-default `ai` feature.
- **Web frontend** (`src/`) — a CodeMirror 6 PWA (single `main.ts` / `index.html` /
  `vite.config.ts`, no `@tauri-apps` anywhere). The engine runs as WASM —
  `markdown-core` → `wasm32-wasip1` (`public/markdown_core.wasm`), loaded in the browser
  via a WASI shim (`src/core-wasm.ts`). `doctor.ts` and `format.ts` call it directly.
- **Native Apple frontend** (`apple/`) — a SwiftUI `DocumentGroup` app over TextKit 2
  (`UITextView` on iOS, `NSTextView` on macOS, shared sources via `#if os`), binding the
  core through uniffi (`MarkdownCore.xcframework`). Read mode renders via a span-based
  `MarkdownRenderer`. XcodeGen (`project.yml`) is the checked-in project source.

## Verified green (this host)

| Check | Result |
|---|---|
| `cargo test -p markdown-core` | ✅ 95 passed |
| `npm run build` (tsc + vite) | ✅ PWA bundle, zero `@tauri-apps` |
| `npm run test:wasm` (Node `node:wasi`) | ✅ JS↔WASM boundary PASS |
| `node scripts/wasm-shim-check.mjs` (browser `@bjorn3/browser_wasi_shim` path) | ✅ PASS |
| `swift test` (macOS binding round-trip) | ✅ 4/4 |
| `xcodebuild test -scheme MarkdownEditor` (iOS Simulator UI suite) | ✅ 3/3 |
| `xcodebuild build` (iOS + macOS targets) | ✅ BUILD SUCCEEDED |

Verified by running, with screenshots in `apple/docs/`. This is **pre-release**:
verified on the iOS Simulator and in the browser/Node, not yet shipped to any store
or host, and not yet exercised in a real browser DOM on this host (no headless
browser installed — `npm run dev` to see it live).

## Feature status

The iOS/macOS lead phase (M1–M9) and the Phase 4 rich-content work are **done**:
read mode, WYSIWYM, doctor underlines, Format Document, BOM-preserving save, find,
themes, Dynamic Type, accessibility, outline, PDF export (Core Text), inline math
(SwiftMath + core `math_spans`), inline images, multi-doc tabs, Quick Open.

## Honest gaps / deliberate degradations

- **Mermaid is partial** — blocks are detected and rendered distinctly, but full SVG
  diagram rendering (offscreen mermaid.js in a `WKWebView`) is the one remaining piece.
- **CommonMark compliance is partial** — the spec suite runs in CI with a documented
  skip-list; closing the reference-link gap is the top correctness task.
- **Wikilink navigation + backlinks are no-ops in the web build.** They need real
  filesystem *paths*; the browser has file *handles*. Rendering of `[[links]]` works,
  and the path-based engine logic is intact in `markdown-core::wikilinks` for Apple.
- **The generated wasm and the Apple build products are gitignored** — rebuild with
  `npm run build:wasm` and `apple/scripts/build-rust.sh` (see `README.md`).

## Next

- Mermaid full SVG rendering on Apple (FEAT-037, the one open Phase 4 item).
- Close reference-link CommonMark compliance against the skip-list.
- Browser directory-handle model → restore wikilinks/backlinks in the web build.
- Harden + ship: PWA distribution and the Apple release path.
