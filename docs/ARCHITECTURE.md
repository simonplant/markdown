# Markdown — Architecture

## Overview

Markdown is a cross-platform markdown editor. Three layers, one codebase per layer:

```
+------------------------------------------------------------------+
|                      Platform Shells (Tauri)                      |
|   macOS   |   Linux   |  Windows  |    Web    |   iOS    | Android|
| WKWebView | WebKitGTK | WebView2  |  Browser  | WKWebView| WebView|
+-----+-----+-----+-----+-----+-----+-----+-----+----+-----+---+----+
      |           |           |           |          |         |
      +-----------+-----------+-----+-----+----------+---------+
                                    |
                                    v
                  +----------------------------------+
                  |       CodeMirror 6 Editor        |
                  |  Markdown mode                   |
                  |  WYSIWYM decorations (HyperMD)   |
                  |  Themes, accessibility           |
                  |  Hot-path formatting (JS)        |
                  |  TypeScript                      |
                  +----------------+-----------------+
                                   |
                                   | Bridge (JSON over Tauri IPC)
                                   v
                  +----------------------------------+
                  |       Rust Core Engine           |
                  |                                  |
                  |  Document model (String)         |
                  |  tree-sitter-markdown parser     |
                  |  Formatting engine (5 rules)     |
                  |  Doctor engine (5 rules)         |
                  |  Undo/redo*                      |
                  |  File watching (notify)*         |
                  |  Auto-save, conflict detection*  |
                  +----------------------------------+
                  * not yet implemented; see backlog
```

The three layers map cleanly to the three decisions in `docs/PRODUCT.md`:

- **Rust core** makes DP-3 ("the editor should be smart") viable with a <1ms incremental reparse budget
- **CodeMirror 6** makes DP-4 ("platform-idiomatic, not platform-native") and DP-10 (accessibility) viable because browsers already solved CJK/RTL/IME/screen readers
- **Tauri shells** make cross-platform day one affordable for an agent-directed project with no commercial backing

A Rust CLI wrapper, a Rust crate, and an LSP server are all *possible* second-order outputs of the core engine, but they are **not** v1 deliverables and they do not shape the architecture. The editor is the product. See `docs/PRODUCT.md` for the history of why this doc used to lead with CLI concerns and no longer does.

## Core Engine (Rust)

The engine is the product. Everything else is a frontend.

### Document Model

**Decision (FEAT-008): keep `String`.** The `Document` struct uses a naive UTF-8 `String`. All three candidates (piece table, rope, String) were measured against `docs/baseline.json` with 5-run medians. Both piece table and rope regressed beyond the 10% threshold — piece table regressed keystroke latency by 1.33x and save by 1.28x; rope regressed open-10k by 2.91x and memory by 1.35x. String matched baseline within measurement noise.

See `docs/engine-comparison.json` for the full data and `docs/engine-decision.md` for the rationale. If large-file performance becomes a problem (FEAT-027), the decision can be revisited with new measurements.

### Parser: tree-sitter

Single parser for all operations.

**Why tree-sitter**: C library, runs everywhere (native + WASM). Incremental parsing — sub-millisecond reparse on keystroke. Concrete syntax tree preserves all whitespace/punctuation for round-trip fidelity.

**Grammar**: `tree-sitter-markdown` (split_parser branch) for block + inline structure.

**CommonMark compliance**: tree-sitter-markdown is not 100% CommonMark-compliant. Known divergences exist in lazy continuation lines, complex nested link references, and some edge cases.

**Mitigation**:
- CommonMark spec test suite runs in CI
- Explicit skip-list for known divergences, documented for users
- Contribute fixes upstream
- Accept 98%+ compliance — the remaining edge cases are rarely hit in practice

**Extensions**:
- GFM: tables, strikethrough, task lists, autolinks — supported by the grammar
- Frontmatter: YAML block detection in the grammar
- Math: `$inline$` and `$$display$$` — post-parse detection over code spans if not in grammar
- Mermaid: fenced code block with `mermaid` info string — rendering is a shell/webview concern

### Formatting Engine

Rule-based, ordered evaluation. Rules are implemented from scratch in Rust; the legacy Swift prototype in `reference/` is used as algorithm reference, not as source to port.

- List continuation (auto-bullet on Enter)
- Table alignment
- Heading spacing
- Blank line separation
- Trailing whitespace trim

**Critical split**: Hot-path rules (Enter, Tab, Backspace triggers) are duplicated in the CodeMirror JS layer for zero-latency response. Complex rules (full reformat, doctor) run in Rust. Accept the duplication — it's a small amount of JS for instant feedback.

### Doctor Engine

Diagnostic rules, also implemented in Rust from the legacy algorithms:

- Heading hierarchy violations
- Broken relative links
- Duplicate headings
- Unclosed formatting
- Passive voice detection (P1)

Runs asynchronously after edits. Results sent to CodeMirror as diagnostics (underlines, gutter markers).

### Undo/Redo

Command-based with coalescing. Each edit produces an `UndoCommand` (byte range + old content). Sequential single-character inserts within 300ms in the same word coalesce into one command. Unlimited depth.

### Selections

`Vec<(anchor: usize, head: usize)>` of byte offsets. Single selection is the common case. Multi-cursor support comes free from the data structure.

### File Operations

All in Rust core:
- **File watching**: `notify` crate (cross-platform inotify/FSEvents/ReadDirectoryChanges)
- **Auto-save**: Debounced write (1 second after last edit). Content hash comparison to skip no-op saves.
- **Conflict detection**: mtime + content hash on watch event. If external change detected while dirty, surface conflict to shell.
- **Line ending preservation**: Detect on open, preserve on save.

### Core API

Tauri integrates the Rust core directly as a Rust dependency — no FFI boundary, no separate process. Commands are exposed to the webview via Tauri's `#[tauri::command]` macro and IPC bridge.

**Current IPC commands (implemented):**

```rust
#[tauri::command] fn open_file(state, path: String) -> Result<String, Error>;     // returns file contents
#[tauri::command] fn edit(state, offset: usize, delete: usize, insert: String);   // mutates state-held Document
#[tauri::command] fn save_file(state, path: String, content: String) -> Result<(), Error>;
#[tauri::command] fn current_text(state) -> String;
#[tauri::command] fn create_window(app, path: Option<String>);                    // multi-window support
#[tauri::command] fn get_recent_files(state) -> Vec<String>;                      // recent files list
#[tauri::command] fn add_recent_file(state, path: String);                        // track opened files
```

State is held in a Tauri `AppState` struct with per-window document management (`HashMap<window_label, Document>`).

**Planned API additions (not yet implemented):**

```rust
#[tauri::command] fn document_viewport(h, start: usize, end: usize) -> Viewport;
#[tauri::command] fn document_diagnose(h) -> Vec<Diagnostic>;
#[tauri::command] fn document_format(h) -> Vec<Mutation>;
#[tauri::command] fn document_undo(h);
#[tauri::command] fn document_redo(h);
#[tauri::command] fn document_close(h);
```

These appear as the parser, doctor, formatter, and undo engines land. Each one is gated on its own backlog item and its own regression-check against `docs/baseline.json`.

A C FFI layer via `cbindgen` is possible as a second-order output for embedding the core in external tools, but it is **not** a v1 deliverable and does not drive the core's shape.

### Concurrency Model

The Rust core is single-threaded per document. Each document gets its own handle. The shell/bridge serializes access. No internal locking needed. tree-sitter parsing and formatting run synchronously within an edit call — they're fast enough (<1ms for incremental, <16ms for full reparse of large docs).

Background operations (doctor diagnostics, export) run on a separate thread and return results via callback.

## Rendering: CodeMirror 6

### Why CodeMirror 6

Write the editor UI once. Browser engines already solved:
- CJK input method composition
- RTL and bidirectional text
- Accessibility (ARIA, screen readers)
- Text selection, context menus, spell check
- Unicode edge cases (emoji, grapheme clusters, zero-width joiners)

These are multi-year, multi-team problems on native platforms. TextKit's bidi support is notoriously buggy. CodeMirror 6 handles all of this because browsers handle it.

### WYSIWYM via Decorations

CodeMirror 6 decorations + the HyperMD approach (proven, not speculative):
- Syntax characters (`#`, `**`, `- `) replaced with zero-width decorations when cursor is outside the node
- Inline images rendered as widget decorations
- Mermaid diagrams rendered as DOM elements within the editor
- Code blocks with syntax highlighting via tree-sitter grammars

Cursor proximity detection: when the cursor enters a markdown node's range, decorations are removed to reveal raw syntax. When cursor leaves, decorations reapply. This is the WYSIWYM model.

### Bridge Protocol

Tauri's IPC bridge (`invoke()` from `@tauri-apps/api` in the webview, `#[tauri::command]` in Rust) handles the transport. We use it to send JSON-shaped messages in both directions:

**Editor → Core** (edit intents):
```json
{"type": "edit", "offset": 1024, "delete": 0, "insert": "hello"}
{"type": "undo"}
{"type": "save"}
{"type": "format"}
```

**Core → Editor** (state updates):
```json
{"type": "tokens", "ranges": [...]}
{"type": "diagnostics", "items": [...]}
{"type": "conflict", "path": "..."}
```

**Latency budget**: Keystroke → CodeMirror shows character instantly (optimistic). Rust core processes edit, re-parses (sub-ms), returns updated tokens. Total round-trip 10-15ms on desktop. Perceived latency <5ms because of optimistic rendering. Same model as VS Code.

### Accessibility

CodeMirror 6 provides:
- Hidden textarea for screen reader interaction
- ARIA live regions for content changes
- Screen reader cursor tracking
- Keyboard navigation

This is narrower than native UITextView VoiceOver but functional. Specific gaps must be tested with VoiceOver (macOS/iOS), NVDA (Windows), and Orca (Linux) and documented.

## Platform Shells: Tauri

### Why Tauri

Tauri 2.0 provides webview hosting, Rust backend IPC, file system access, native menus, auto-updater, and mobile support (iOS + Android) out of the box. It's MIT-licensed, well-funded, and active. Building this from scratch would cost 3-4 months per platform.

The Rust core integrates directly into the Tauri backend — no separate process, no additional IPC layer.

### Per-Platform Details

| Platform | Webview | Shell additions beyond Tauri |
|----------|---------|------------------------------|
| macOS | WKWebView | Spotlight indexing, Quick Look, Services menu |
| Linux | WebKitGTK | XDG desktop integration, D-Bus, `.desktop` file, AppStream metadata |
| Windows | WebView2 (pre-installed Win 10 21H2+) | Explorer integration, jump lists |
| iOS | WKWebView | Files app integration, share sheet, virtual keyboard handling |
| Android | Android WebView | Storage Access Framework, intent filters |
| Web | IS the browser | PWA manifest, service worker for offline, File System Access API |

**Shell size**: 500-2000 lines each. The Tauri boilerplate handles 80% of the work.

### WebKitGTK on Linux

WebKitGTK lags behind Chromium by 6-12 months and has known rendering quirks. For most of the editor the demands are modest and CodeMirror 6 runs reliably. The one area where WebKitGTK will visibly cost us is **DP-9 (The Render)** — the signature source-to-rich animation. Expect it to run at 60fps on Linux where it hits 120fps on modern Apple hardware. This is an accepted tradeoff: bundling Chromium/CEF would defeat the lightweight goal and add ~100MB to the binary. We ship with system WebKitGTK and tune the animation within its budget.

## Distribution

### Linux (most important for ubiquity)

1. Use system WebKitGTK — no bundled webview
2. Static Rust binary + JS/CSS/HTML assets
3. Standard `.desktop` file, AppStream metadata, MIME `text/markdown` registration
4. Flatpak first (dependency isolation), then AUR, COPR, PPA
5. Reproducible builds, no network during build, standard install paths
6. Fully open source — non-negotiable for distro inclusion

### All platforms

- **macOS**: Homebrew Cask, direct `.dmg` download, optionally Mac App Store
- **Linux**: Flatpak, AUR, COPR, PPA, nixpkgs
- **Windows**: Microsoft Store, WinGet, direct `.msi`/`.exe` download
- **iOS**: App Store
- **Android**: Google Play + F-Droid (full open source, no Play Services dependency)
- **Web**: Static hosting, PWA with service worker

App Store channels are not required for the product to work — they're one distribution path among many. Homebrew/Flatpak/direct-download are the primary channels for users who want software that isn't gated by a store review process.

## Reference: legacy Swift prototype

A Swift prototype in `reference/` contains algorithm work from an earlier Apple-only version of the product. **No Swift code transfers.** The Swift code was used as algorithm *reference* when implementing the Rust equivalents:

- Formatting rules — **ported** to `em-core/src/formatter.rs` (list continuation, table alignment, heading spacing, blank-line separation, trailing whitespace trim)
- Doctor rules — **ported** to `em-core/src/doctor.rs` (broken links, heading hierarchy, duplicate headings, unclosed formatting, passive voice)
- Tree-sitter node type → AST mapping — **ported** to `em-core/src/ast.rs` and `em-core/src/parser.rs`

Do not add Swift targets to this repo. Do not invoke `swift build` or `swift test`.

## Phases

These align with `docs/PRODUCT.md §7.1` (walking skeleton) and `§8` (post-M0 roadmap). Timelines are soft — agent-driven sprints run continuously. Ordering is not.

| Phase | Status | Deliverable |
|-------|--------|-------------|
| **M0 — Walking skeleton** | Done | Rust workspace + `em-core` (String-backed), Tauri 2.0 macOS shell, CodeMirror 6 editor, IPC bridge, end-to-end open → edit → save → reopen loop, baseline metrics in `docs/baseline.json` with CI regression gate |
| **0 — Foundations** | Done | tree-sitter-markdown parser and AST, engine decision (String — measured, not assumed), 5-rule formatting engine, 5-rule doctor engine, CommonMark spec suite in CI |
| **1 — Editor polish** | Done | WYSIWYM decorations, The Render animation, light/dark themes, keyboard shortcuts, typography, find/replace, word count, recent files, spell check |
| **2 — Platform expansion** | Next | Linux Tauri shell, Windows Tauri shell, Web (PWA), auto-save, file watching, conflict detection, Flatpak. First public pre-release |
| **3 — AI and file scale** | Planned | Local AI (llama.cpp/MLX/ONNX), BYO-key cloud AI, smart completions, large-file handling, v1.0 |
| **4 — Mobile** | Planned | iOS + Android via Tauri mobile |
| **5 — Expansion** | Planned | Wikilinks/backlinks against plain files, extended doctor rules, voice intent, Mermaid, math, custom themes |

**Every item in every phase measures against `docs/baseline.json` before merging.** See `PRODUCT.md §7.1.5` and `D-M0-2`. A regression of more than 10% in the median of the measurement run blocks the merge until the regression is understood, named, and accepted.

## Key Risks and Mitigations

| Risk | Impact | Mitigation |
|------|--------|------------|
| tree-sitter CommonMark divergence | Incorrect rendering of edge cases | Spec tests in CI, skip-list, upstream contributions |
| WebKitGTK rendering bugs | Visual glitches on Linux | Modest rendering demands, test on major distros, file upstream bugs |
| Webview memory on low-end mobile | OOM on 3GB devices | Memory pressure handling, release caches, warn user on large files |
| App Store rejection as "web wrapper" | Can't ship on iOS/macOS store | Substantial native shell (file management, share, Spotlight). Obsidian precedent. |
| Agent-driven sustainability bet fails | Project joins the MarkText graveyard | Keep human review fast and frequent. Keep backlog items agent-resolvable (commander's intent + concrete AC). Named honestly in `docs/PRODUCT.md` §9, not hidden. |
| Six platforms, one human reviewer | Review bottleneck, slow merges | Ship desktop first (macOS + Linux), add Windows/Web next, mobile last. Thin shells via Tauri keep per-platform surface area small. |
| Tauri project health | Dependency risk | MIT-licensed, can fork. Shell code is thin enough to rewrite if needed. |
| Bridge latency on slow devices | Perceived input lag | Optimistic rendering in CodeMirror. Hot-path formatting in JS. Benchmark on target devices. |
