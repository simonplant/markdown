# Markdown

The best free markdown editor on every platform. Apache 2.0. No vault, no account, no subscription.

Open any `.md` file from a local folder or cloud drive (iCloud Drive, Dropbox, Google Drive, OneDrive) on macOS, Linux, Windows, Web, iOS, and Android. Built on a Rust core, CodeMirror 6 editor, and Tauri 2 shells.

## What's Working

The macOS desktop app is functional with:

- **Rust core** — tree-sitter-markdown parser, 5-rule formatting engine, 5-rule diagnostic doctor, String-backed document model (53 passing tests)
- **Tauri 2 shell** — multi-window support, native file dialogs, recent files menu, unsaved-changes prompts
- **CodeMirror 6 editor** — markdown syntax highlighting, WYSIWYM decorations (syntax markers hide when cursor moves away), light/dark themes following system preference, word count status bar, spell check (OS-native), bold/italic/delete-line shortcuts, find and replace
- **The Render** — source-to-rich toggle animation (Cmd+Shift+R) with reduced-motion support
- **CI** — macOS build + test, CommonMark spec suite (305 passing, 347 in documented skip-list), baseline performance regression gate

## Status

**Phase 1 complete. Entering Phase 2 (platform expansion).**

| Phase | Status | Scope |
|-------|--------|-------|
| M0 — Walking skeleton | Done | Rust workspace, Tauri macOS shell, CodeMirror 6 editor, IPC bridge, end-to-end file loop, baseline metrics |
| Phase 0 — Foundations | Done | tree-sitter parser, engine decision (keep String), formatting engine, doctor engine, CommonMark CI |
| Phase 1 — Editor polish | Done | WYSIWYM, The Render, themes, typography, keyboard shortcuts, word count, find/replace, recent files, spell check |
| Phase 2 — Platform expansion | Next | Linux shell, Windows shell, Web/PWA, auto-save, file watching, Flatpak |
| Phase 3 — AI | Planned | Local on-device AI, BYO-key cloud AI, smart completions |
| Phase 4 — Mobile | Planned | iOS and Android via Tauri mobile |
| Phase 5 — Rich editing | Planned | Wikilinks, Mermaid, math, folding, tabs, image handling, PDF export, custom themes |

See [`docs/PRODUCT.md`](docs/PRODUCT.md) for the full roadmap and [`backlog/backlog.json`](backlog/backlog.json) for the itemized backlog.

## Development

### Prerequisites

- [Rust](https://rustup.rs/) (stable)
- [Node.js](https://nodejs.org/) (LTS)
- [Tauri CLI](https://v2.tauri.app/start/prerequisites/) (`cargo install tauri-cli --version '^2'`)
- Platform dependencies for Tauri (see [Tauri prerequisites](https://v2.tauri.app/start/prerequisites/))

### Build and Run

```bash
npm install                          # install frontend dependencies
cargo tauri dev                      # run the app in development mode
cargo tauri build                    # build the release app bundle
```

### Test

```bash
cargo test --workspace               # run all Rust tests (em-core + src-tauri)
cargo test -p em-core --test commonmark -- --nocapture   # CommonMark spec suite
```

### Project Structure

```
em-core/           Rust core — parser, formatter, doctor, document model
src-tauri/         Tauri 2 shell — IPC bridge, menus, file dialogs, multi-window
src/               TypeScript frontend — CodeMirror 6 editor, WYSIWYM, themes
docs/              Product vision, architecture, baseline metrics
backlog/           Sprint backlog and orchestration state
reference/         Legacy Swift prototype (algorithm reference only)
```

### Sprint Orchestration

This repo uses [aishore](./.aishore/) for agent-driven sprint execution.

```bash
.aishore/aishore status              # backlog overview
.aishore/aishore backlog list        # detailed list
.aishore/aishore run FEAT-022        # run a sprint
```

## Docs

- [`docs/PRODUCT.md`](docs/PRODUCT.md) — product vision, principles, decisions, feature scope, honest risks
- [`docs/ARCHITECTURE.md`](docs/ARCHITECTURE.md) — Rust core, CodeMirror 6, Tauri shells
- [`docs/baseline.json`](docs/baseline.json) — performance baseline metrics and regression threshold
- [`docs/commonmark_status.md`](docs/commonmark_status.md) — tree-sitter-markdown CommonMark compliance
- [`CLAUDE.md`](CLAUDE.md) — guidance for Claude Code and agent sprints
- [`PRIVACY.md`](PRIVACY.md) — no telemetry, no network, files stay local

## License

[Apache 2.0](LICENSE). The whole stack. Not open-core, not source-available.
