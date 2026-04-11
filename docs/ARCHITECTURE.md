# Easy Markdown — Architecture

## Overview

Easy Markdown is a cross-platform markdown editor. Three layers, one codebase per layer:

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
                  |  Document model (piece table)    |
                  |  tree-sitter-markdown parser     |
                  |  Formatting engine               |
                  |  Doctor engine                   |
                  |  Undo/redo                       |
                  |  File watching (notify)          |
                  |  Auto-save, conflict detection   |
                  +----------------------------------+
```

The three layers map cleanly to the three decisions in `docs/PRODUCT.md`:

- **Rust core** makes DP-3 ("the editor should be smart") viable with a <1ms incremental reparse budget
- **CodeMirror 6** makes DP-4 ("platform-idiomatic, not platform-native") and DP-10 (accessibility) viable because browsers already solved CJK/RTL/IME/screen readers
- **Tauri shells** make cross-platform day one affordable for an agent-directed project with no commercial backing

A Rust CLI wrapper, a Rust crate, and an LSP server are all *possible* second-order outputs of the core engine, but they are **not** v1 deliverables and they do not shape the architecture. The editor is the product. See `docs/PRODUCT.md` for the history of why this doc used to lead with CLI concerns and no longer does.

## Core Engine (Rust)

The engine is the product. Everything else is a frontend.

### Document Model: Piece Table

A piece table with UTF-8 byte storage and an incremental line-starts index.

**Why piece table**: Simpler than ropes (Xi used ropes and the complexity contributed to its abandonment). O(log n) edits via a balanced BST of pieces. Original file bytes are never mutated (trivial is-modified detection). The append-only add buffer makes undo straightforward.

**Structure**:
- Pieces stored in a red-black tree keyed by cumulative byte offset
- Each piece: `{ buffer_id: Original | Add, offset: usize, length: usize, line_count: u32 }`
- Line-starts index: sorted `Vec<usize>` of byte offsets, updated incrementally on edit
- UTF-8 throughout (matches tree-sitter, matches file encoding, no UTF-16 translation)

**Compaction**: After thousands of small edits, the piece tree fragments. Periodic compaction rewrites the logical sequence into a fresh buffer. Trigger: when piece count exceeds 10x line count, or on save.

**Scale**: 100MB file = mmap'd original buffer + line index (~4 bytes/line, ~8MB for 2M lines). Editing only allocates in the add buffer. Rendering reads only the visible viewport.

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

Tauri integrates the Rust core directly as a Rust dependency — no FFI boundary, no separate process. Commands exposed to the webview via Tauri's `#[tauri::command]` macro and IPC bridge:

```rust
#[tauri::command] fn document_open(path: String) -> Result<DocumentHandle, Error>;
#[tauri::command] fn document_edit(h: DocumentHandle, offset: usize, delete: usize, insert: String) -> EditResult;
#[tauri::command] fn document_viewport(h: DocumentHandle, start: usize, end: usize) -> Viewport;
#[tauri::command] fn document_diagnose(h: DocumentHandle) -> Vec<Diagnostic>;
#[tauri::command] fn document_format(h: DocumentHandle) -> Vec<Mutation>;
#[tauri::command] fn document_save(h: DocumentHandle, path: String) -> Result<(), Error>;
#[tauri::command] fn document_undo(h: DocumentHandle);
#[tauri::command] fn document_redo(h: DocumentHandle);
#[tauri::command] fn document_close(h: DocumentHandle);
```

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

A Swift prototype in `reference/` contains algorithm work from an earlier Apple-only version of the product. **No Swift code transfers.** What transfers is algorithm *reference* when porting to Rust:

- Formatting rules (list continuation, table alignment, heading spacing, blank-line separation, trailing whitespace)
- Doctor rules (broken links, heading hierarchy, duplicate headings, unclosed formatting)
- Tree-sitter node type → AST mapping

When implementing a Rust equivalent, read the Swift file as pseudocode, not as source. Do not add Swift targets to this repo. Do not invoke `swift build` or `swift test`.

## Phases

These align with `docs/PRODUCT.md` §8. Timelines are soft — agent-driven sprints run continuously.

| Phase | Deliverable |
|-------|-------------|
| **0 — Foundations** | Rust workspace, tree-sitter-markdown, document model, formatting engine, doctor engine, CommonMark spec suite in CI |
| **1 — Editor** | CodeMirror 6 markdown mode, WYSIWYM decorations, bridge protocol, The Render prototype, themes |
| **2 — First shells** | macOS + Linux Tauri shells, file open/save, auto-save, file watching, first public pre-release |
| **3 — Polish + AI + Web + Windows** | Local AI, BYO-key mode, PWA shell, Windows shell, v1.0 |
| **4 — Mobile** | iOS + Android via Tauri mobile |
| **5 — Expansion** | Wikilinks/backlinks, extended doctor, voice intent, Mermaid AI editing |

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
