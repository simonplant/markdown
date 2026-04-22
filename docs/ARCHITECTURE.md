# Markdown — Architecture

How the product is built. The *what* and *why* (user-facing) live in `PRODUCT.md`. This document owns everything `PRODUCT.md` does not: framework choices, library choices, engineering budgets, module boundaries, test infrastructure, and the engineering protocols that govern how changes are made and measured.

---

## Document scope

This document owns:

- The technical stack and why each piece was chosen
- Module boundaries and internal interfaces
- Concrete engineering budgets (millisecond targets, memory targets, binary size targets)
- The document model, parser, formatter, doctor, and AI integration at an implementation level
- Per-platform shell decisions and distribution mechanics
- The engineering discipline: walking skeleton, baseline measurement, regression gates
- Engineering risks and their mitigations

This document does **not** own:

- What the product is or who it serves (`PRODUCT.md`)
- The user-facing quality bar (`PRODUCT.md` §Performance, §User Experience)
- The contribution workflow (`CONTRIBUTING.md`)

**Decision IDs**: architecture decisions use `A-*` identifiers. Product decisions use `D-*` identifiers and live in `PRODUCT.md`. Every architecture decision must cite the product decision it implements; every product decision that depends on an architectural choice should reference the relevant `A-*` ID.

---

## 1. Overview

Markdown is a three-layer application. Each layer has a single codebase that runs everywhere.

```
+------------------------------------------------------------------+
|                       Platform Shells (thin)                      |
|   macOS   |   Linux   |  Windows  |    Web    |   iOS    | Android|
+-----+-----+-----+-----+-----+-----+-----+-----+----+-----+---+----+
      |           |           |           |          |         |
      +-----------+-----------+-----+-----+----------+---------+
                                    |
                                    v
                  +----------------------------------+
                  |         Editor Frontend          |
                  |  Read mode rendering             |
                  |  Author mode editing (WYSIWYM)   |
                  |  Mode transition                 |
                  |  Themes, accessibility           |
                  |  Hot-path formatting             |
                  +----------------+-----------------+
                                   |
                                   | IPC (JSON messages)
                                   v
                  +----------------------------------+
                  |         Core Engine (Rust)       |
                  |                                  |
                  |  Document model                  |
                  |  Parser + AST                    |
                  |  Formatting engine               |
                  |  Doctor engine                   |
                  |  Undo/redo                       |
                  |  File I/O, watching, auto-save   |
                  |  Plugin host (first-party only)  |
                  +----------------------------------+
```

The layers map to the product contracts in `PRODUCT.md`:

- **Core engine** makes the editor-is-smart contract (D-EDIT-1) viable at the performance bar (D-PERF-1). It owns the document, the AST, and the long-running intelligence.
- **Editor frontend** makes the platform-idiomatic contract (DP-4) and the accessibility contract (DP-10) viable — browser engines already solved CJK, RTL, IME, and screen reader integration.
- **Platform shells** make cross-platform day-one (D-PLAT-1) affordable. Each shell is thin enough to be rewritten if the underlying framework needs replacing.

### Decision [A-STACK-1]: The three-layer model

The product requirements fully determine the shape of the solution. Reading `PRODUCT.md`:

- D-PLAT-1 says every platform is first-class — ruling out Apple-only native UI.
- D-PERF-1 says nothing blocks typing and large documents remain usable — ruling out an interpreted-language core for the hot path.
- D-A11Y-1 says screen-reader support is a ship-blocker on every platform — ruling out a custom rendering engine that would have to reimplement accessibility per platform.
- D-AI-1 says on-device inference is the default — ruling out a thin client model.

The intersection of these constraints is: a compiled-language core for performance, a web-based editor for cross-platform UI with accessibility for free, and a thin shell per platform.

### Decision [A-STACK-2]: Rust + CodeMirror 6 + Tauri

- **Rust** for the core engine — compiled performance, memory safety, single codebase that runs everywhere the shells run, mature cross-platform filesystem and concurrency primitives.
- **CodeMirror 6** for the editor frontend — battle-tested, extensible, handles the hard problems (CJK, RTL, IME, accessibility, unicode edge cases) because browsers do.
- **Tauri 2.0** for the shells — webview hosting, Rust backend integration, file system access, native menus, auto-updater, and mobile support in one framework. MIT-licensed, well-funded, active. Alternative (building shells from scratch) costs a quarter per platform.

This stack is not sacred. Each choice is defended by the decisions above and can be revisited if the defense stops holding. The three-layer *model* is more load-bearing than the specific tech.

---

## 2. Engineering Protocol

This section describes how we work. It is load-bearing: the protocol is what makes agent-driven development viable in an open-source project with one human reviewer.

### The Walking Skeleton discipline

Every major architectural claim in this project is proven with a *walking skeleton* — the smallest end-to-end instance of the architecture that executes real code against real infrastructure. Walking skeletons are deliberately ugly, deliberately minimal, and deliberately real: no mocks, no stubs, no "we'll wire it up later."

A walking skeleton passes when it runs, not when it compiles.

We use this discipline at three levels:

1. **Project-level (M0)**: the initial walking skeleton proved the three-layer model works end-to-end on at least one platform. It is described below and has shipped on macOS.
2. **Platform-level**: each new platform shell starts from its own walking skeleton that proves the platform-specific shell code works with the existing core and editor before any platform-specific features are added.
3. **Capability-level**: major new capabilities (AI integration, plugin host, large-file handling) start with a walking skeleton that proves the integration point before feature work begins.

### Baseline measurement and the regression gate

Every walking skeleton, on pass, writes a set of measured performance numbers to `docs/baseline.json`. These become the regression budget for every change that follows.

**Baseline environment**: measurements are captured on a GitHub Actions `ubuntu-latest` runner. This is the only environment whose numbers are committed and enforced. Local runs are for exploration. The reasons for standardizing on CI runners are: free, reproducible, available to every contributor (human or agent), and slower than most dev machines — which gives us headroom and makes regressions visible earlier.

**Methodology**: each metric captures N≥5 measurements and takes the median. The regression gate fires when a PR's median exceeds 110% of the committed baseline median. Single-run gates produce random failures because CI runners have 10–15% inherent variance on cold metrics.

**User-representative load distribution.** A single "typical document" baseline is insufficient — performance that looks healthy on a 5 KB test file can hide pathological behavior on documents users actually open. From the Foundation phase onward, `baseline.json` captures each core metric (open, keystroke latency, format, save, reopen) across a distribution that represents how real users load the product:

- **Small document** (≈1 KB, ~30 lines): a short note or brief AI response
- **Medium document** (≈25 KB, ~800 lines): a typical long-form document — a research report, a PRD, a meeting summary with tables
- **Large document** (≈250 KB, ~8,000 lines): a substantial architecture doc, a long-form article, or an AI-generated report with rich content
- **Synthetic session** (a scripted sequence of open → scroll → edit → format → save across several documents of mixed sizes): exercises steady-state behavior rather than just cold-start numbers

The regression gate fires on any of these slices independently — a 12% regression on the large-document open time blocks a merge even if small and medium documents are unchanged. The distribution is committed to the repository as `docs/baseline-corpus/` (representative `.md` fixtures) and is versioned alongside `baseline.json`. The distribution is extended, not replaced, as new usage patterns emerge (e.g., mobile load profiles when the mobile phase begins per A-PROC-3).

**The gate blocks merges.** A regression of more than 10% in any baseline metric blocks the PR until the regression is understood, named, and either fixed or explicitly accepted (which updates `baseline.json`).

### Decision [A-PROC-1]: Walking-skeleton discipline applies to every major architectural claim

No major architectural claim merges without a walking skeleton that exercises it end-to-end against real infrastructure. Forbidden acceptance criteria include `grep` checks for code existence, `test -f` checks for file existence, unit tests that mock the IPC bridge or the filesystem, and "component X compiles." Compilation is a precondition, not an eval.

### Decision [A-PROC-2]: Baseline-measured regression gate is permanent

Every change merges against `docs/baseline.json`. The gate fires at 110% of the committed median of any metric. This is the mechanism that keeps D-PERF-1 true over time.

### Decision [A-PROC-3]: Architectural claims require a documented walking skeleton

Each major subsystem (core engine, editor frontend, each platform shell, AI integration, plugin host) has or will have a named walking-skeleton milestone with its own baseline metrics. The table in §Phases below tracks which have shipped.

---

## 3. Core Engine (Rust)

The engine is the product's durable intelligence. Everything else is a frontend.

### 3.1 Document Model

**Decision [A-CORE-1]: naive UTF-8 `String`.** The `Document` struct uses a standard Rust `String`. All three candidates (piece table, rope, `String`) were measured against the M0 baseline with 5-run medians. Both piece table and rope regressed beyond the 10% threshold — piece table regressed keystroke latency by 1.33x and save by 1.28x; rope regressed open-10k by 2.91x and memory by 1.35x. `String` matched the baseline within measurement noise.

See `docs/engine-comparison.json` for the full data and `docs/engine-decision.md` for the rationale. If large-file performance becomes a product concern (implementing the "remain usable for tens of thousands of lines" clause of D-PERF-1), the decision revisits with new measurements.

### 3.2 Parser

**Decision [A-CORE-2]: tree-sitter with the `tree-sitter-markdown` grammar (split_parser branch).**

Why tree-sitter: C library, runs everywhere (native + WASM). Incremental parsing — sub-millisecond reparse on keystroke, which realizes the "nothing blocks typing" clause of D-PERF-1. Concrete syntax tree preserves all whitespace and punctuation for round-trip fidelity, which realizes the "standard markdown in, standard markdown out" clause of DP-7.

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
- Mermaid: fenced code block with `mermaid` info string — rendering is an editor-frontend concern

### 3.3 Formatting Engine

Rule-based, ordered evaluation. Rules are implemented in Rust. Current rules:

- List continuation (auto-bullet on Enter)
- Table alignment
- Heading spacing
- Blank line separation
- Trailing whitespace trim

**Decision [A-CORE-3]: hot-path duplication between core and editor frontend.** Rules that must respond within a single frame (Enter, Tab, Backspace triggers) are duplicated in the editor frontend for zero-latency response. Complex rules (full reformat, doctor) run only in the Rust core. The duplication is small, well-bounded, and covered by tests that ensure the two implementations produce identical output on the same input.

### 3.4 Doctor Engine

Diagnostic rules, also implemented in Rust:

- Heading hierarchy violations
- Broken relative links
- Duplicate headings
- Unclosed formatting
- Passive voice detection (later phase)

Runs asynchronously after edits on a background thread. Results sent to the editor as diagnostics (underlines, gutter markers).

### 3.5 Undo/Redo

Command-based with coalescing. Each edit produces an undo command (byte range + old content). Sequential single-character inserts within 300ms in the same word coalesce into one command. Unlimited depth.

### 3.6 Selections

`Vec<(anchor: usize, head: usize)>` of byte offsets. Single selection is the common case. Multi-cursor support comes free from the data structure.

### 3.7 File Operations

All in the Rust core:

- **File watching**: `notify` crate (cross-platform inotify/FSEvents/ReadDirectoryChanges).
- **Auto-save**: debounced write (1 second after last edit). Content hash comparison to skip no-op saves.
- **Conflict detection**: mtime + content hash on watch event. If external change detected while dirty, surface conflict to the shell.
- **Line ending preservation**: detect on open, preserve on save. Realizes D-FILE-3.
- **Encoding preservation**: UTF-8 is the default assumption; BOM detection handles UTF-8 with BOM and flags non-UTF-8 files to the user rather than silently mangling them.

### 3.8 Core API

The Rust core integrates directly as a dependency of the Tauri backend — no FFI boundary, no separate process. Commands are exposed to the editor frontend via Tauri's `#[tauri::command]` macro and IPC bridge.

**Current IPC commands (implemented):**

```rust
#[tauri::command] fn open_file(state, path: String) -> Result<String, Error>;
#[tauri::command] fn edit(state, offset: usize, delete: usize, insert: String);
#[tauri::command] fn save_file(state, path: String, content: String) -> Result<(), Error>;
#[tauri::command] fn current_text(state) -> String;
#[tauri::command] fn create_window(app, path: Option<String>);
#[tauri::command] fn get_recent_files(state) -> Vec<String>;
#[tauri::command] fn add_recent_file(state, path: String);
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

Each lands with the subsystem that needs it (doctor, formatter, undo) and carries its own regression-check against `docs/baseline.json`.

A C FFI layer via `cbindgen` is possible as a second-order output for embedding the core in external tools, but it is **not** a v1 deliverable and does not drive the core's shape.

### 3.9 Concurrency Model

The Rust core is single-threaded per document. Each document gets its own handle. The shell/bridge serializes access. No internal locking needed. Parsing and formatting run synchronously within an edit call — they're fast enough (sub-ms incremental, <16ms full reparse of large documents) to meet the "nothing blocks typing" clause of D-PERF-1.

Background operations (doctor diagnostics, export, AI calls) run on separate threads and return results via callback.

### 3.10 Plugin Host (first-party only)

**Decision [A-CORE-4]: internal plugin architecture, first-party plugins only.**

Features like Mermaid rendering, math rendering, wikilinks, image handling, and extended doctor rules are built as plugins against a stable internal plugin API. This gives us modularity and a clean way to feature-flag capabilities without bloating the core.

The plugin API is *not* exposed to users. D-NO-6 (no third-party extension ecosystem) is a product decision; this is the engineering mechanism that makes it maintainable without becoming a liability. Plugins ship compiled into the binary. There is no runtime plugin loading, no marketplace, no user-installable `.plugin` files.

The host provides: parser access, AST query, formatting rule registration, doctor rule registration, diagnostic emission, editor-side rendering hooks for widget decorations, and an AI-capability registration interface. Plugins cannot modify the core engine, touch the filesystem directly, or make network calls outside the AI-capability interface.

---

## 4. Editor Frontend (CodeMirror 6)

### 4.1 Why CodeMirror 6

Write the editor UI once. Browser engines already solved:

- CJK input method composition
- RTL and bidirectional text
- Accessibility (ARIA, screen readers)
- Text selection, context menus, spell check
- Unicode edge cases (emoji, grapheme clusters, zero-width joiners)

These are multi-year, multi-team problems on native platforms. CodeMirror 6 handles all of this because browsers handle it. This is the defense for DP-4 and DP-10 — the cross-platform polish and accessibility guarantees are grounded in infrastructure we don't have to build.

### 4.2 Two modes, one editor

Decision D-UX-1 commits the product to read mode by default with author mode one gesture away. The editor frontend implements this as two CodeMirror EditorView states over the same document, with a designed transition between them.

**Read mode**:
- Full rendering: headings styled, tables laid out, code blocks syntax-highlighted, Mermaid and math rendered inline, images inline
- Source characters (`#`, `**`, ` ``` `) are hidden via widget decorations
- Selection and copy work on rendered text
- Screen-reader users get a document, not source
- Single click / tap anywhere triggers the transition to author mode with the cursor placed at the click position

**Author mode**:
- Full CodeMirror 6 editing with HyperMD-style WYSIWYM decorations
- Syntax characters hidden when cursor is outside a node, revealed on proximity
- Live formatting rules (list continuation, table alignment, heading spacing) active
- Doctor diagnostics visible in the gutter
- Find/replace, word count, spell check, AI actions all available
- A visible affordance returns to read mode with the designed transition

**Mode transition**: D-UX-1 requires read mode as the default with author mode one gesture away. The transition is implemented via CodeMirror 6 decorations and CSS transitions; Reduced Motion users get an instant crossfade. The transition must be smooth (60fps minimum on every shell) but is not a named signature feature — it is expected polish, not a marketing moment.

### 4.3 Bridge Protocol

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

**Latency budget**: keystroke → editor shows character immediately (optimistic render). Core processes edit, reparses (sub-ms), returns updated tokens. Total round-trip 10-15ms on desktop; perceived latency <5ms because of optimistic rendering. Realizes the "edits feel instant" clause of D-PERF-1.

### 4.4 Accessibility

CodeMirror 6 provides:
- Hidden textarea for screen reader interaction
- ARIA live regions for content changes
- Screen reader cursor tracking
- Keyboard navigation

This is narrower than a hand-tuned native text view but functional on every platform. Specific gaps are tested with VoiceOver (macOS/iOS), NVDA (Windows), Orca (Linux), and TalkBack (Android) and documented per release. Read mode must pass screen-reader review separately — it is often *more* accessible than source view for document consumption, and the review enforces that.

---

## 5. AI Integration (deferred, post-v1.0)

**Status: deferred.** Per D-ROAD-3 in `PRODUCT.md`, AI ships after v1.0. This section exists as an architectural placeholder: it names the constraints the eventual implementation must satisfy and the engineering protocol that will govern how it's designed, without pre-committing to specific runtimes or vendors that may not be the right answer when we actually start building.

> **Rollback note (FEAT-045).** An earlier sprint (FEAT-029/030/032) shipped a local llama.cpp inference engine, a BYO-key cloud mode, and inline smart completions, getting ahead of D-ROAD-3. That code is now gated off — the `ai` cargo feature is off by default in both `markdown-core` and `src-tauri`, the `ai_*` Tauri commands are cfg-gated, and the AI editor extensions and settings UI are unwired from the default build. The code remains in the tree so that when the AI phase formally begins, re-enabling is a feature-flag flip plus a proper walking skeleton (per §5.3) rather than a ground-up rewrite. Any API keys previously stored in the OS keychain are untouched.

### 5.1 Constraints (locked now)

These derive from product decisions D-AI-1, D-AI-2, D-AI-3 and do not depend on which runtime or vendor we eventually pick:

- **Local-first**: on-device inference is the default path for core capabilities. The product works fully without any network access to AI providers.
- **No relay**: user-key cloud requests go direct from the user's machine to the provider they chose. The project operates no server infrastructure that touches user content or API keys.
- **Keychain-stored credentials**: API keys live in the OS keychain, never in plaintext config files or project servers.
- **Plugin-hosted**: AI capabilities are built against the plugin host described in §3.10, not wired into the core. This means AI can be disabled, deferred, replaced, or reimplemented without touching the core engine.
- **Consent-gated**: AI never modifies the document without an explicit user action. Inline suggestions appear as ghosted text or diffs; acceptance is an explicit user action.
- **Degrades gracefully**: if AI is unavailable (no model, no network, API error, account issue), the editor works perfectly without it.

### 5.2 Deferred decisions

The following decisions are deferred until the AI tooling landscape is stable enough to choose durably:

- Which local inference runtime(s) to use per platform. Candidates today include Core ML, MLX, llama.cpp, ONNX Runtime (native and web), and others; the right answer in 18 months may be none of these.
- Which cloud providers to support at launch of the AI phase. The right set depends on which providers have durable OpenAI-compatible endpoints and which don't.
- Which AI capabilities to ship first and in what form. Today's candidates (improve, summarize, continue, smart completions) may not be what users want by the time we ship.

### 5.3 Engineering protocol for the AI phase

When the AI phase begins, it starts with its own walking skeleton (per A-PROC-3) that proves the plugin-host integration, the keychain-stored credentials path, the consent-gated UI pattern, and the graceful-degradation behavior — before any specific runtime or capability work begins. The constraints in §5.1 are the acceptance criteria for that walking skeleton.

**Decision [A-AI-DEFERRED]**: AI runtime and vendor decisions are deferred until the AI phase begins. The constraints in §5.1 are locked and inherited by any future implementation.

---

## 6. Platform Shells

### 6.1 Per-Platform Details

| Platform | Webview | Shell-specific work |
|----------|---------|---------------------|
| macOS | WKWebView | Spotlight indexing, Quick Look, Services menu, standard menu bar |
| Linux | WebKitGTK | XDG desktop integration, D-Bus, `.desktop` file, AppStream metadata |
| Windows | WebView2 (pre-installed Win 10 21H2+) | Explorer integration, jump lists |
| iOS | WKWebView | Files app integration, share sheet, virtual keyboard handling |
| Android | Android WebView | Storage Access Framework, intent filters |
| Web | IS the browser | PWA manifest, service worker for offline, File System Access API |

**Shell size target**: 500–2000 lines each. Tauri boilerplate handles ~80% of the work.

### 6.2 WebKitGTK on Linux

WebKitGTK lags Chromium by 6–12 months and has known rendering quirks. For most of the editor the demands are modest and CodeMirror 6 runs reliably.

The area where WebKitGTK will visibly cost us is animation smoothness — the mode transition and other animated affordances will run at 60fps on Linux where modern Apple hardware hits 120fps. This is an accepted tradeoff: bundling Chromium/CEF would add ~100MB per install and defeat the lightweight goal. We ship with system WebKitGTK and tune animations within its budget.

### 6.3 Mobile shell notes

Tauri 2.0 mobile (iOS and Android) is behind desktop in maturity. The mobile shells will start from their own walking-skeleton milestones (per A-PROC-3) and will not ship user-visible until their baseline metrics are captured and the per-platform accessibility review passes.

---

## 7. Distribution

### 7.1 Linux (most important for ubiquity)

1. Use system WebKitGTK — no bundled webview.
2. Static Rust binary + JS/CSS/HTML assets.
3. Standard `.desktop` file, AppStream metadata, MIME `text/markdown` registration.
4. Flatpak first (dependency isolation), then AUR, COPR, PPA.
5. Reproducible builds, no network during build, standard install paths.
6. Fully open source — non-negotiable for distro inclusion.

### 7.2 All platforms

- **macOS**: Homebrew Cask, direct `.dmg` download, optionally Mac App Store.
- **Linux**: Flatpak, AUR, COPR, PPA, nixpkgs.
- **Windows**: Microsoft Store, WinGet, direct `.msi`/`.exe` download.
- **iOS**: App Store.
- **Android**: Google Play + F-Droid (full open source, no Play Services dependency).
- **Web**: static hosting, PWA with service worker.

App Store channels are not required for the product to work — they're one distribution path among many. Homebrew / Flatpak / direct-download are the primary channels for users who want software that isn't gated by a store review process.

---

## 8. Legacy Swift prototype (reference only)

A Swift prototype in `reference/` contains algorithm work from an earlier Apple-only version of the product. **No Swift code transfers.** The Swift code was used as algorithm *reference* when implementing the Rust equivalents:

- Formatting rules — **ported** to `em-core/src/formatter.rs`
- Doctor rules — **ported** to `em-core/src/doctor.rs`
- Tree-sitter node type → AST mapping — **ported** to `em-core/src/ast.rs` and `em-core/src/parser.rs`

Do not add Swift targets to this repo. Do not invoke `swift build` or `swift test`.

---

## 9. Engineering Phases

These align with the product roadmap in `PRODUCT.md §7`. The roadmap describes user-visible outcomes; this table describes the engineering work that delivers them and its current status.

**Current status is honestly mixed — some items have shipped on macOS, some are in flight, some haven't started. Rows marked `{{STATUS: confirm}}` are guesses that need a pass from the architect to set accurately.**

| Phase | Engineering deliverables | Status |
|-------|--------------------------|--------|
| **M0 — Walking skeleton** | Rust workspace + `em-core` crate (`String`-backed), Tauri 2.0 macOS shell, CodeMirror 6 editor in plain-text mode, IPC bridge with four commands (`open_file`, `edit`, `save_file`, `current_text`), end-to-end open → edit → save → reopen loop, baseline metrics committed to `docs/baseline.json`, CI regression gate | **Shipped (macOS)** |
| **Foundation (post-M0)** | tree-sitter-markdown parser and AST, engine decision locked to `String` (measured), 5-rule formatting engine, 5-rule doctor engine, CommonMark spec suite in CI with skip-list | **Shipped (macOS)** `{{STATUS: confirm per-item}}` |
| **Editor** | Read mode rendering, author mode with WYSIWYM decorations, mode transition animation, light/dark themes, keyboard shortcuts, typography, find/replace, word count, recent files, spell check, plugin host | **In flight (macOS)** `{{STATUS: confirm which items are done vs in flight}}` |
| **Platform expansion** | Linux shell (WebKitGTK), Windows shell (WebView2), Web shell (PWA), auto-save, file watching, conflict detection, Flatpak packaging, first public pre-release | Planned |
| **Mobile** | iOS shell, Android shell, mobile-specific walking skeleton per A-PROC-3 | Planned |
| **Stabilization and v1.0** | Rich content: Mermaid plugin, math plugin, image handling, wikilinks plugin, extended doctor rules, PDF export plugin, custom themes. Cross-platform performance and stability hardening. v1.0. | Planned |
| **AI (deferred, post-v1.0)** | Platform-appropriate local inference runtimes, user-key mode, smart completions, large-file handling. **Gated on ecosystem stabilization — see D-ROAD-3 in `PRODUCT.md`.** | Deferred |

**Every item in every phase measures against `docs/baseline.json` before merging** (per A-PROC-2). A regression of more than 10% in the median of the measurement run blocks the merge until the regression is understood, named, and either fixed or explicitly accepted.

---

## 10. Engineering Risks and Mitigations

These are architecture-level risks. Product-level risks (sustainability, market) live in `PRODUCT.md §9`.

| Risk | Impact | Mitigation |
|------|--------|------------|
| tree-sitter CommonMark divergence | Incorrect rendering of edge cases | Spec tests in CI, skip-list, upstream contributions |
| WebKitGTK rendering quirks | Visual glitches on Linux, lower animation ceiling | Modest rendering demands, test on major distros, file upstream bugs, accept the animation ceiling (§6.2) |
| Webview memory on low-end mobile | OOM on 3GB devices | Memory pressure handling, release caches, warn user on large files |
| App Store rejection as "web wrapper" | Can't ship on iOS / macOS store | Substantial native shell work (file management, share, Spotlight integration). Obsidian precedent is relevant. |
| Tauri mobile immaturity | Phase slippage on iOS / Android | Walking skeleton per platform before any user-visible work; accept that mobile ships later |
| Six platforms, one human reviewer | Review bottleneck | Ship desktop first, add mobile last. Thin shells via Tauri keep per-platform surface area small. Review load is the binding constraint — see `CONTRIBUTING.md` |
| Tauri project health | Upstream dependency risk | MIT-licensed, can fork. Shell code is thin enough to rewrite against a different framework if needed. |
| Bridge latency on slow devices | Perceived input lag | Optimistic rendering in the editor. Hot-path formatting duplicated in editor. Benchmark on target devices. |
| Large-document performance | `String` model may not scale | The decision is measured, not assumed. Revisit (re-running the piece-table / rope comparison) if large-file use cases start regressing user-facing performance. |
| AI runtime churn | Pre-committing to a specific inference runtime now may waste work when the ecosystem shakes out | Defer per A-AI-DEFERRED. Keep the constraints (local-first, no relay, plugin-hosted, consent-gated) locked; defer the runtime choice until the AI phase begins. |

---

## 11. Architecture Decision Log

Consolidated reference. Each entry names the product decision it implements.

| ID | Decision | Implements |
|----|----------|-----------|
| A-STACK-1 | Three-layer model: Rust core, web-based editor, thin platform shells | D-PLAT-1, D-PERF-1, D-A11Y-1 |
| A-STACK-2 | Rust + CodeMirror 6 + Tauri 2.0 | A-STACK-1 |
| A-PROC-1 | Walking-skeleton discipline for every major architectural claim | D-PERF-1, D-PROC-1 |
| A-PROC-2 | Baseline-measured regression gate at 110% of committed median | D-PERF-1 |
| A-PROC-3 | Each major subsystem has its own walking-skeleton milestone | D-PROC-1 |
| A-CORE-1 | Document model is `String` (measured, not assumed) | D-PERF-1 |
| A-CORE-2 | tree-sitter with `tree-sitter-markdown` grammar | D-PERF-1, DP-7 |
| A-CORE-3 | Hot-path formatting duplicated between core and editor | D-PERF-1 |
| A-CORE-4 | Internal plugin architecture, first-party plugins only | D-NO-6 |
| A-AI-DEFERRED | AI runtime and vendor decisions deferred until the AI phase begins; constraints in §5.1 locked | D-AI-1, D-AI-2, D-AI-3, D-ROAD-3 |

---

## Appendix: Related documents

- `PRODUCT.md` — what the product is, who it serves, the user-facing contract. All product decisions (`D-*`) live there.
- `CONTRIBUTING.md` — how contributions work. The agent-driven development model, review loop, and agent-legibility maintenance.
- `docs/baseline.json` — the committed performance baseline enforced by the regression gate.
- `docs/engine-comparison.json` — the full measurement data behind A-CORE-1.
- `docs/engine-decision.md` — the rationale for A-CORE-1 written up for reviewers.
