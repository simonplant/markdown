# Markdown

The best free markdown editor on every platform. Apache 2.0. No vault, no account, no subscription.

Open any `.md` file from a local folder or cloud drive (iCloud Drive, Dropbox, Google Drive, OneDrive) on iOS, macOS, Web, Windows, Linux, and Android. Read it rendered beautifully; tap or click to edit in a polished, native-feeling author mode.

## Architecture

One shared engine, a native editor frontend on each platform. There is no cross-platform UI framework — the shared code is the engine, not the UI.

- **Rust core** (`markdown-core`) — tree-sitter-markdown parser, formatting engine, diagnostic doctor, `String`-backed document model, file I/O. Headless and identical on every platform. Compiles to a native library on Apple platforms and to WebAssembly for the web.
- **Native Apple frontend** — Swift on TextKit 2, for iOS and macOS. The lead frontend; iOS is the priority platform and sets the quality bar. Native text selection, keyboard, dictation, share sheet, and Files integration, with the Rust core bound in-process via `uniffi`.
- **Web frontend** — CodeMirror 6, for the Web, Windows, and Linux (and Android via PWA). WYSIWYM editing, themes, find/replace, word count, OS-native spell check, with the Rust core running as WebAssembly. Delivered as an installable, offline-capable PWA.

See [`docs/ARCHITECTURE.md`](docs/ARCHITECTURE.md) for the full treatment.

## Status

All three frontends are built and verified by running. This is **pre-release**: the web build runs in the browser and the Apple app is verified on the iOS Simulator and as a native macOS app — neither has shipped yet.

| Area | Status |
|------|--------|
| **Rust core** | Built and tested — tree-sitter parser, formatting engine, doctor, `String`-backed document model, file I/O, wikilinks, math span detection. Full test suite green. |
| **Web frontend (CodeMirror 6)** | Built — read mode, WYSIWYM decorations, themes following system preference, find/replace, word count, spell check, live preview, the read↔author transition. |
| **Core as WebAssembly + PWA** | Built — the core compiles to `wasm32-wasip1` and runs in the browser via a WASI shim; doctor and formatting call the WASM core; installable PWA shell. |
| **Native Apple frontend (iOS lead, then macOS)** | Built and verified — Swift + TextKit 2 (`UITextView` on iOS, `NSTextView` on macOS) over the core via `uniffi`. Read mode, WYSIWYM, doctor underlines, Format Document, BOM-preserving save, find, themes, outline, PDF export, inline math (SwiftMath) and images, Quick Open. Verified on the iOS Simulator and on macOS. |
| **CommonMark compliance** | Spec suite runs in CI with a documented skip-list; closing the reference-link gap is the top correctness task. |
| **Rich content** | Built on Apple, except **Mermaid** — blocks are detected and distinctly rendered, but full SVG diagram rendering is the one remaining piece. |
| **AI** | Deferred post-v1.0, parked behind the off-by-default `ai` cargo feature. See the roadmap. |

See [`docs/PRODUCT.md`](docs/PRODUCT.md) for the roadmap and [`backlog/backlog.json`](backlog/backlog.json) for the itemized backlog.

## Development

### Prerequisites

- [Rust](https://rustup.rs/) (stable)
- [Node.js](https://nodejs.org/) (LTS) — for the web frontend
- LLVM with a `wasm32-wasip1` sysroot (`brew install llvm`) — to compile the core to WebAssembly
- [Xcode](https://developer.apple.com/xcode/) and [XcodeGen](https://github.com/yonaskolb/XcodeGen) (`brew install xcodegen`) — for the native Apple frontend

### Rust core

```bash
cargo test -p markdown-core                                   # run the core test suite
cargo test -p markdown-core --test commonmark -- --nocapture  # CommonMark spec suite
```

### Web frontend

```bash
npm install        # install frontend dependencies
npm run build:wasm # compile the Rust core to wasm32-wasip1 (writes public/markdown_core.wasm)
npm run dev        # run the editor in development mode
npm run build      # build the production PWA assets
```

The core binds to the web frontend as WebAssembly — there is no separate process or server. `npm run build:wasm` runs `scripts/build-wasm.sh`; `npm run test:wasm` smoke-tests the module under Node.

### Native Apple frontend (iOS, macOS)

```bash
apple/scripts/build-rust.sh                    # build the staticlibs + uniffi Swift bindings → MarkdownCore.xcframework
cd apple && xcodegen generate                  # generate MarkdownEditor.xcodeproj from project.yml (re-run after adding files)
xcodebuild test -scheme MarkdownEditor \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro'   # build + run the iOS UI test suite
swift test --package-path apple/Packages/MarkdownCoreFFI     # core binding round-trip on macOS
```

The generated `.xcodeproj`, the `MarkdownCore.xcframework`, and `Info.plist` are gitignored build products; `project.yml` is the checked-in source of truth.

### Project Structure

```
markdown-core/     Rust core — parser, formatter, doctor, document model, wikilinks, math, uniffi + WASM bindings
src/               Web frontend — CodeMirror 6 editor, WYSIWYM, themes; core loaded as WebAssembly
apple/             Native iOS + macOS app — Swift/TextKit 2 over the core via uniffi (XcodeGen project)
scripts/           Build + baseline tooling (WASM build, baseline measurement)
docs/              Product vision, architecture, baseline metrics, CommonMark status, iOS build spec
backlog/           Sprint backlog and orchestration state
reference/         Earlier Apple-only Swift prototype (algorithm reference only, not built)
```

### Sprint Orchestration

This repo uses [aishore](./.aishore/) for agent-driven sprint execution.

```bash
.aishore/aishore status              # backlog overview
.aishore/aishore backlog list        # detailed list
.aishore/aishore run FEAT-XXX        # run a sprint
```

## Docs

- [`docs/PRODUCT.md`](docs/PRODUCT.md) — product vision, principles, decisions, feature scope, honest risks
- [`docs/ARCHITECTURE.md`](docs/ARCHITECTURE.md) — shared Rust core, native Apple frontend, CodeMirror 6 web frontend
- [`docs/IOS_BUILD_SPEC.md`](docs/IOS_BUILD_SPEC.md) — authoritative spec for the native iOS + macOS app
- [`CONTRIBUTING.md`](CONTRIBUTING.md) — how the project gets built: the agent-driven model, review loop, sustainability bet
- [`CLAUDE.md`](CLAUDE.md) — guidance for Claude Code and agent sprints
- [`PRIVACY.md`](PRIVACY.md) — no telemetry, no network, files stay local

## License

[Apache 2.0](LICENSE). The whole stack. Not open-core, not source-available.
