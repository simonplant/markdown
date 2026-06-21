# Markdown — Architecture

How the product is built. The *what* and *why* (user-facing) live in `PRODUCT.md`. This document owns everything `PRODUCT.md` does not: framework choices, library choices, engineering budgets, module boundaries, test infrastructure, and the engineering protocols that govern how changes are made and measured.

---

## Document scope

This document owns:

- The technical stack and why each piece was chosen
- Module boundaries and internal interfaces
- Concrete engineering budgets (millisecond targets, memory targets, binary size targets)
- The document model, parser, formatter, doctor, and AI integration at an implementation level
- Per-platform frontend decisions and distribution mechanics
- The engineering discipline: walking skeleton, baseline measurement, regression gates
- Engineering risks and their mitigations

This document does **not** own:

- What the product is or who it serves (`PRODUCT.md`)
- The user-facing quality bar (`PRODUCT.md` §Performance, §User Experience)
- The contribution workflow (`CONTRIBUTING.md`)

**Decision IDs**: architecture decisions use `A-*` identifiers. Product decisions use `D-*` identifiers and live in `PRODUCT.md`. Every architecture decision cites the product decision it implements; every product decision that depends on an architectural choice references the relevant `A-*` ID.

---

## 1. Overview

Markdown is built from one shared engine and a native editor frontend on each platform. There is no cross-platform UI framework. The engine is the durable, shared asset; each frontend is built to the native standard of the platform it runs on.

```
+------------------------------------------------------------------+
|                         Editor Frontends                          |
|                                                                   |
|   Native Apple frontend          |        Web frontend            |
|   (Swift + TextKit 2)            |        (CodeMirror 6)          |
|   iOS  ·  macOS                  |        Web · Windows · Linux    |
+-----------------+----------------+----------------+---------------+
                  |                                  |
       uniffi (in-process FFI)          WebAssembly (in-process)
                  |                                  |
                  +----------------+-----------------+
                                   |
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

- **Core engine** makes the editor-is-smart contract (D-EDIT-1) viable at the performance bar (D-PERF-1). It owns the document, the AST, and the long-running intelligence, and it is identical on every platform.
- **Editor frontends** make the platform-native feel (DP-4) and the accessibility contract (DP-10) viable. Each frontend is built to the highest standard of its platform rather than to a lowest common denominator.

### Decision [A-STACK-1]: One shared core, native frontends, no cross-platform UI framework

The product requirements determine the shape of the solution. Reading `PRODUCT.md`:

- D-PLAT-1 says every platform is first-class, with iOS and macOS leading — the editing experience must feel native on each.
- D-PERF-1 says nothing blocks typing and large documents remain usable — ruling out an interpreted-language core for the hot path.
- DP-2 sets the bar at an editing experience nothing else matches; on touch platforms in particular, a web-canvas text surface does not clear that bar.
- D-A11Y-1 says screen-reader support is a ship-blocker on every platform.

The intersection: a compiled-language core shared everywhere, and an editor frontend on each platform that uses that platform's own text system. On Apple platforms that is the native text stack; on the web and on desktops that already run web content well, that is a mature browser-grade editor. A single cross-platform UI toolkit was considered and rejected — every option either reintroduces the web-canvas feel that fails the bar on iOS, or forces rebuilding the editor on immature text tooling. The shared code is the engine, not the UI.

### Decision [A-STACK-2]: Rust core + native Apple frontend + CodeMirror 6 web frontend

- **Rust** for the core engine — compiled performance, memory safety, one codebase that runs everywhere, mature cross-platform filesystem and concurrency primitives. Compiles to a native library on Apple platforms and to WebAssembly for the web frontend.
- **Swift + TextKit 2** for the Apple frontend (iOS and macOS) — the native text system Apple's own best editors use. Native selection physics, keyboard, dictation, magnifier, share sheet, Files integration, and VoiceOver. iOS is the lead platform and sets the bar; macOS shares the bulk of this frontend through TextKit 2's common surface (`UITextView` / `NSTextView`).
- **CodeMirror 6** for the web frontend (Web, Windows, Linux) — a battle-tested editor that handles CJK, RTL, IME, accessibility, and unicode edge cases because browsers do. Runs as an installable PWA; the same build serves the web and packages for Windows and Linux.

This stack is not sacred. Each choice is defended by the decisions above and can be revisited if the defense stops holding. The layered *model* — one shared core, native frontends — is more load-bearing than any specific frontend technology.

### Decision [A-BIND-1]: The core binds in-process on every platform — no separate process, no network IPC

The Rust core is linked directly into each frontend and called in-process:

- **Apple frontend**: the core is compiled to a native static library and exposed to Swift through a `uniffi`-generated binding. Calls are direct function calls across the FFI boundary.
- **Web frontend**: the core is compiled to WebAssembly and loaded in the same context as the editor. Calls are direct WASM invocations.

There is no daemon, no localhost socket, and no JSON-over-network bridge. This keeps keystroke round-trips at function-call latency and removes a class of lifecycle and security problems that an out-of-process model would introduce.

---

## 2. Engineering Protocol

This section describes how we work. It is load-bearing: the protocol is what makes agent-driven development viable in an open-source project with one human reviewer.

### The Walking Skeleton discipline

Every major architectural claim in this project is proven with a *walking skeleton* — the smallest end-to-end instance of the architecture that executes real code against real infrastructure. Walking skeletons are deliberately ugly, deliberately minimal, and deliberately real: no mocks, no stubs, no "we'll wire it up later."

A walking skeleton passes when it runs, not when it compiles.

We use this discipline at three levels:

1. **Project-level**: the initial walking skeleton proves the layered model works end-to-end on at least one platform — open, edit, save, reopen against the real core.
2. **Frontend-level**: each editor frontend starts from its own walking skeleton that proves the frontend works with the existing core before any frontend-specific features are added.
3. **Capability-level**: major new capabilities (AI integration, plugin host, large-file handling) start with a walking skeleton that proves the integration point before feature work begins.

### Baseline measurement and the regression gate

Every walking skeleton, on pass, writes a set of measured performance numbers as the committed baseline. These become the regression budget for every change that follows.

**Methodology**: each metric captures N≥5 measurements and takes the median. The regression gate fires when a change's median exceeds 110% of the committed baseline median. Single-run gates produce random failures because runners have inherent variance on cold metrics.

**User-representative load distribution.** A single "typical document" baseline is insufficient — performance that looks healthy on a 5 KB test file can hide pathological behavior on documents users actually open. The committed baseline captures each core metric (open, keystroke latency, format, save, reopen) across a distribution that represents how real users load the product:

- **Small document** (≈1 KB, ~30 lines): a short note or brief AI response
- **Medium document** (≈25 KB, ~800 lines): a typical long-form document — a research report, a PRD, a meeting summary with tables
- **Large document** (≈250 KB, ~8,000 lines): a substantial architecture doc, a long-form article, or an AI-generated report with rich content
- **Synthetic session** (a scripted sequence of open → scroll → edit → format → save across several documents of mixed sizes): exercises steady-state behavior rather than just cold-start numbers

The regression gate fires on any of these slices independently. The distribution lives in `docs/baseline-corpus/` (representative `.md` fixtures) and is versioned alongside the committed baseline. It is extended, not replaced, as new usage patterns emerge — including per-platform load profiles as each frontend matures.

**The gate blocks merges.** A regression of more than 10% in any baseline metric blocks the change until the regression is understood, named, and either fixed or explicitly accepted (which updates the committed baseline).

### Decision [A-PROC-1]: Walking-skeleton discipline applies to every major architectural claim

No major architectural claim merges without a walking skeleton that exercises it end-to-end against real infrastructure. Forbidden acceptance criteria include `grep` checks for code existence, `test -f` checks for file existence, unit tests that mock the binding boundary or the filesystem, and "component X compiles." Compilation is a precondition, not an eval.

### Decision [A-PROC-2]: Baseline-measured regression gate is permanent

Every change merges against the committed performance baseline. The gate fires at 110% of the committed median of any metric. This is the mechanism that keeps D-PERF-1 true over time.

### Decision [A-PROC-3]: Each frontend has its own walking-skeleton milestone

Each editor frontend (native Apple, web) and each major subsystem (core engine, AI integration, plugin host) has a named walking-skeleton milestone with its own baseline metrics. The table in §9 tracks status.

---

## 3. Core Engine (Rust)

The engine is the product's durable intelligence. Everything else is a frontend. It is one crate, `markdown-core`, compiled to a native library for Apple platforms and to WebAssembly for the web frontend.

### 3.1 Document Model

**Decision [A-CORE-1]: naive UTF-8 `String`.** The `Document` struct uses a standard Rust `String`. All three candidates (piece table, rope, `String`) were measured against the committed baseline with 5-run medians. Both piece table and rope regressed beyond the 10% threshold; `String` matched the baseline within measurement noise at the document sizes the product targets. If large-file performance becomes a product concern, the decision revisits with new measurements.

### 3.2 Parser

**Decision [A-CORE-2]: tree-sitter with the `tree-sitter-markdown` grammar.**

Why tree-sitter: C library, runs everywhere (native and WASM). Incremental parsing — sub-millisecond reparse on keystroke, which realizes the "nothing blocks typing" clause of D-PERF-1. The concrete syntax tree preserves all whitespace and punctuation for round-trip fidelity, which realizes the "standard markdown in, standard markdown out" clause of DP-7.

**CommonMark compliance**: tree-sitter-markdown is not fully CommonMark-compliant. The largest current divergence is reference-style link resolution, which the grammar's syntax tree does not carry; other gaps exist in lazy continuation and some nested-construct edge cases. Closing the reference-link gap is the highest-priority correctness work on the core, because rendering AI-authored documents beautifully is the product's primary job (D-MKT-1).

**Mitigation**:
- The CommonMark spec test suite runs in CI; current pass/skip status is tracked by that suite
- An explicit, documented skip-list covers every known divergence; any skip-listed test that starts passing is flagged so the entry can be removed
- Fixes are contributed upstream where the grammar is the right place to fix them
- The target is high compliance on the constructs real documents use, with the reference-link gap closed first

**Extensions**:
- GFM: tables, strikethrough, task lists, autolinks — supported by the grammar
- Frontmatter: YAML block detection in the grammar
- Math: `$inline$` and `$$display$$` — post-parse detection over code spans
- Mermaid: fenced code block with a `mermaid` info string — rendering is a frontend concern

### 3.3 Formatting Engine

Rule-based, ordered evaluation. Rules are implemented in Rust:

- List continuation (auto-bullet on Enter)
- Table alignment
- Heading spacing
- Blank line separation
- Trailing whitespace trim

**Decision [A-CORE-3]: hot-path formatting is mirrored in each frontend.** Rules that must respond within a single frame (Enter, Tab, Backspace triggers) are duplicated in each editor frontend for zero-latency response; complex rules (full reformat, doctor) run only in the Rust core. The duplication is small, well-bounded, and covered by parity tests that ensure each frontend's hot-path implementation produces output identical to the core on the same input.

### 3.4 Doctor Engine

Diagnostic rules, also implemented in Rust:

- Heading hierarchy violations
- Broken relative links
- Duplicate headings
- Unclosed formatting
- Passive voice detection (later)

Runs asynchronously after edits on a background thread. Results are delivered to the frontend as diagnostics (underlines, gutter markers).

### 3.5 Undo/Redo

Command-based with coalescing. Each edit produces an undo command (byte range + old content). Sequential single-character inserts within 300ms in the same word coalesce into one command. Unlimited depth.

### 3.6 Selections

`Vec<(anchor: usize, head: usize)>` of byte offsets. Single selection is the common case; multi-cursor support comes free from the data structure.

### 3.7 File Operations

All in the Rust core:

- **File watching**: `notify` crate (cross-platform inotify/FSEvents/ReadDirectoryChanges) where the platform exposes filesystem watching to the process; on sandboxed platforms the frontend forwards the platform's own change notifications to the core.
- **Auto-save**: debounced write (1 second after last edit), with content-hash comparison to skip no-op saves.
- **Conflict detection**: mtime + content hash on watch event. If an external change is detected while the buffer is dirty, the conflict is surfaced to the frontend.
- **Line ending preservation**: detected on open, preserved on save. Realizes D-FILE-3.
- **Encoding preservation**: UTF-8 is the default assumption; BOM detection handles UTF-8 with BOM, and non-UTF-8 files are flagged to the user rather than silently mangled.

### 3.8 Core API

The core exposes a single, transport-agnostic command surface. The same Rust functions are reached through `uniffi` on Apple and through WebAssembly bindings on the web — there is no separate API per platform, only a separate binding.

**Current commands:**

```rust
fn open_file(path: String) -> Result<String, Error>;
fn edit(offset: usize, delete: usize, insert: String);
fn save_file(path: String, content: String) -> Result<(), Error>;
fn current_text() -> String;
fn get_recent_files() -> Vec<String>;
fn add_recent_file(path: String);
```

**Planned additions**, each landing with the subsystem that needs it and carrying its own regression check:

```rust
fn document_viewport(start: usize, end: usize) -> Viewport;
fn document_diagnose() -> Vec<Diagnostic>;
fn document_format() -> Vec<Mutation>;
fn document_undo();
fn document_redo();
```

Document state is held per open document inside the core; each frontend owns the mapping from its windows/scenes to core document handles.

### 3.9 Concurrency Model

The core is single-threaded per document; each document gets its own handle and the frontend serializes access, so no internal locking is needed. Parsing and formatting run synchronously within an edit call — they are fast enough (sub-ms incremental, <16ms full reparse of large documents) to meet the "nothing blocks typing" clause of D-PERF-1. Background operations (doctor diagnostics, export, future AI calls) run on separate threads and return results via callback.

### 3.10 Plugin Host (first-party only)

**Decision [A-CORE-4]: internal plugin architecture, first-party plugins only.**

Features like Mermaid rendering, math rendering, wikilinks, image handling, and extended doctor rules are built as plugins against a stable internal plugin API. This gives modularity and a clean way to feature-flag capabilities without bloating the core.

The plugin API is *not* exposed to users. D-NO-7 (no third-party extension ecosystem) is a product decision; this is the engineering mechanism that makes it maintainable. Plugins ship compiled into the binary — no runtime loading, no marketplace, no user-installable plugin files.

The host provides: parser access, AST query, formatting-rule registration, doctor-rule registration, diagnostic emission, frontend-side rendering hooks for widget decorations, and an AI-capability registration interface. Plugins cannot modify the core engine, touch the filesystem directly, or make network calls outside the AI-capability interface.

---

## 4. Editor Frontends

Two frontends share one core. Each is responsible for rendering read mode, editing in author mode, the transition between them, themes, and platform accessibility — using its platform's own text system.

### 4.1 Two modes, one document

Decision D-UX-1 commits the product to read mode by default with author mode one gesture away. Each frontend implements two views over the same core document, with a designed transition between them.

**Read mode**:
- Full rendering: headings styled, tables laid out, code blocks highlighted, Mermaid and math rendered inline, images inline
- Source characters (`#`, `**`, fences) are hidden
- Selection and copy work on rendered text
- Screen-reader users get a document, not source
- A single tap/click enters author mode with the cursor placed at the tap position

**Author mode**:
- Full editing with WYSIWYM decorations — syntax characters hidden when the cursor is away from a node, revealed on proximity
- Live formatting rules (list continuation, table alignment, heading spacing) active
- Doctor diagnostics visible
- Find/replace, word count, spell check available
- A visible affordance returns to read mode

**Mode transition**: read mode is the default; author mode is one gesture away. Reduced-Motion users get an instant crossfade. The transition is expected polish, not a marketing moment.

### 4.2 Native Apple frontend (iOS, macOS)

The lead frontend, and the one that sets the product's quality bar. iOS is the priority platform.

- Built in Swift on **TextKit 2**. Read mode and author-mode WYSIWYM are rendered through the native text layout system, so selection physics, the magnifier, the caret, dictation, the keyboard accessory bar, and text interaction are the real platform behaviors rather than approximations.
- The Rust core is linked as a native library via `uniffi`; edits, parsing results, formatting mutations, and diagnostics cross a direct FFI boundary.
- Platform integration is native: the document browser and Files/iCloud access, the share sheet, multiple scenes/windows, and state restoration.
- Accessibility uses the native stack (`UIAccessibility` / `NSAccessibility`), giving VoiceOver behavior that meets D-A11Y-1 without reimplementation.
- macOS shares the large majority of this frontend through TextKit 2's common surface (`NSTextView`), plus AppKit shell work (standard menu bar, services, Quick Look).

This frontend is what delivers the native-feel bar (DP-2, DP-4) on the platforms where users are most sensitive to it.

### 4.3 Web frontend (Web, Windows, Linux)

One frontend covers the platforms where a browser-grade editor already clears the bar and a web canvas is the pragmatic, high-quality choice.

- Built on **CodeMirror 6** in TypeScript. WYSIWYM via decorations; CJK, RTL, IME, spell check, and unicode handling come from the browser.
- The Rust core runs as **WebAssembly** loaded alongside the editor; edits and queries are direct WASM calls.
- Delivered as an installable **PWA**: a service worker caches the app shell for offline use, and the File System Access API provides open/save on browsers that support it, with an input/download fallback elsewhere. The same build is the web product and the Windows/Linux desktop product.
- Accessibility relies on CodeMirror 6's screen-reader support (hidden textarea, ARIA live regions, keyboard navigation), validated with NVDA and Orca.

### 4.4 Hot-path parity

Both frontends mirror the frame-critical formatting rules locally (A-CORE-3) so Enter/Tab/Backspace never wait on a binding round-trip. Parity tests assert that each frontend's hot-path output matches the core's reference implementation on the same input, so the two never drift.

---

## 5. AI Integration (deferred, post-v1.0)

**Status: deferred.** Per D-ROAD-3 in `PRODUCT.md`, AI ships after v1.0. This section names the constraints the eventual implementation must satisfy and the protocol that will govern it, without pre-committing to runtimes or vendors that may not be the right answer when work begins.

### 5.1 Constraints (locked now)

Derived from D-AI-1, D-AI-2, D-AI-3, independent of runtime or vendor:

- **Local-first**: on-device inference is the default path for core capabilities. The product works fully without any network access to AI providers.
- **No relay**: user-key cloud requests go directly from the user's machine to the provider they chose. The project operates no server infrastructure that touches user content or keys.
- **Keychain-stored credentials**: API keys live in the OS keychain, never in plaintext config or project servers.
- **Plugin-hosted**: AI capabilities are built against the plugin host (§3.10), not wired into the core, so AI can be disabled, deferred, replaced, or reimplemented without touching the engine.
- **Consent-gated**: AI never modifies the document without an explicit user action. Suggestions appear as ghosted text or diffs; acceptance is explicit.
- **Degrades gracefully**: if AI is unavailable, the editor works perfectly without it.

### 5.2 Deferred decisions

Deferred until the AI tooling landscape is stable enough to choose durably: which local inference runtime(s) to use per platform, which cloud providers to support at launch of the AI phase, and which capabilities to ship first.

### 5.3 Engineering protocol for the AI phase

When the AI phase begins, it starts with its own walking skeleton (per A-PROC-3) that proves plugin-host integration, the keychain-stored credentials path, the consent-gated UI pattern, and graceful degradation — before any runtime or capability work. The constraints in §5.1 are the acceptance criteria for that walking skeleton.

**Decision [A-AI-DEFERRED]**: AI runtime and vendor decisions are deferred until the AI phase begins. The constraints in §5.1 are locked and inherited by any future implementation.

---

## 6. Platforms and Distribution

### 6.1 Per-platform summary

| Platform | Frontend | Text system | Core binding | Distribution |
|----------|----------|-------------|--------------|--------------|
| iOS | Native (Swift) | TextKit 2 | uniffi | App Store |
| macOS | Native (Swift/AppKit) | TextKit 2 (`NSTextView`) | uniffi | Homebrew Cask, direct `.dmg`, optionally Mac App Store |
| Web | CodeMirror 6 | Browser | WebAssembly | Static hosting, PWA |
| Windows | CodeMirror 6 | Browser | WebAssembly | PWA install, WinGet, Microsoft Store |
| Linux | CodeMirror 6 | Browser | WebAssembly | PWA install, packaged builds (Flatpak, AUR, COPR, nixpkgs) |
| Android | CodeMirror 6 | Browser | WebAssembly | PWA install, Google Play, F-Droid |

Android is served by the web frontend as an installable PWA. A native Android frontend is a later consideration, justified only if the platform's quality bar demands it the way iOS does. App Store channels are one distribution path among many. Homebrew, Flatpak, direct download, and PWA install are the primary channels for users who want software that isn't gated by a store review process. Full open source is non-negotiable for distro inclusion.

### 6.2 Why this split

iOS and macOS are where the native-feel bar is highest and where a native text system pays for itself; they share a frontend. The web, Windows, and Linux are where a browser-grade editor already clears the bar and where a single web build delivers all three at once. The split is along the line where native effort is justified by the platform, not arbitrary.

### 6.3 Binary size and footprint

Each frontend bundles only what it needs: the native library on Apple, the WASM module plus editor assets on the web. There is no bundled browser engine — the web frontend uses the platform's own webview where it is packaged as a desktop app, and is otherwise just a website.

---

## 7. Reference algorithms (read-only)

A Swift prototype in `reference/` contains algorithm work from an earlier Apple-only version of the product. Its formatting rules, doctor rules, and tree-sitter node-type → AST mapping were ported to the Rust core (`markdown-core/src/formatter.rs`, `doctor.rs`, `ast.rs`, `parser.rs`). The reference is consulted for rule behavior only; the native Apple frontend is a fresh build on TextKit 2, not a continuation of that prototype.

---

## 8. Engineering Risks and Mitigations

Architecture-level risks. Product-level risks (sustainability, market) live in `PRODUCT.md`.

| Risk | Impact | Mitigation |
|------|--------|------------|
| tree-sitter CommonMark divergence (reference links first) | Incorrect rendering of some constructs | Spec tests in CI, documented skip-list, reference-link gap prioritized, upstream contributions |
| Native Apple editor effort | TextKit 2 WYSIWYM is real work; the lead platform must clear a high bar | Frontend walking skeleton on a real device before feature work; the bar is validated by use, not by compile |
| Two editor frontends drift | Behavioral inconsistencies between Apple and web | Shared core owns all logic; frontends own only rendering and hot-path formatting, gated by parity tests (§4.4) |
| Core-to-WASM viability | Web frontend depends on the Rust core compiling to WASM | tree-sitter and the core are WASM-targetable; the web frontend's walking skeleton proves it end-to-end before features land |
| App Store rejection as "web wrapper" | Can't ship on iOS / Mac App Store | The Apple frontend is genuinely native (TextKit 2, native file management, share, Spotlight) — not a web wrapper |
| Webview memory on low-end devices | OOM pressure on the web frontend | Memory-pressure handling, release caches, warn on very large files |
| Large-document performance | `String` model may not scale | The decision is measured, not assumed; revisit with new measurements if large-file use cases regress user-facing performance |
| Six platforms, one reviewer | Review bottleneck | Lead with Apple, then web-for-three; the shared core keeps per-platform surface small — see `CONTRIBUTING.md` |
| AI runtime churn | Pre-committing to a runtime now wastes work | Defer per A-AI-DEFERRED; keep the §5.1 constraints locked |

---

## 9. Engineering Phases

These align with the product roadmap in `PRODUCT.md`. The roadmap describes user-visible outcomes; this table describes the engineering work that delivers them and its status.

| Phase | Engineering deliverables | Status |
|-------|--------------------------|--------|
| **Core engine** | `markdown-core` crate (`String`-backed), tree-sitter parser and AST, formatting engine, doctor engine, file I/O, CommonMark spec suite in CI with skip-list, baseline metrics and regression gate | Built and measured |
| **Web frontend** | CodeMirror 6 editor (read mode, WYSIWYM, themes, find/replace, word count, spell check), core compiled to WebAssembly, PWA shell with offline and File System Access, auto-save, file watching, conflict detection | Built — editor plus the core running as `wasm32-wasip1` in the browser via a WASI shim; PWA shell. Verified in the browser, not yet shipped |
| **Apple frontend (lead)** | Swift + TextKit 2 editor (read mode, WYSIWYM, mode transition), core via uniffi, native file management, share sheet, accessibility; iOS first, macOS sharing the TextKit 2 surface | Built — `UITextView`/`NSTextView` over the core via uniffi; read mode, WYSIWYM, doctor, Format, find, themes, accessibility. Verified on the iOS Simulator and on macOS, not yet shipped |
| **Stabilization and v1.0** | Reference-link compliance closed, rich content (Mermaid, math, images, wikilinks), extended doctor rules, PDF export, custom themes, cross-platform hardening | In progress — outline, PDF export, math, inline images, extended doctor rules, custom themes, Quick Open built on Apple; Mermaid SVG rendering and reference-link compliance remain |
| **AI (deferred, post-v1.0)** | Local inference, user-key mode, smart completions — gated on ecosystem stabilization (D-ROAD-3) | Deferred |

Every item in every phase measures against the committed baseline before merging (A-PROC-2).

---

## 10. Architecture Decision Log

| ID | Decision | Implements |
|----|----------|-----------|
| A-STACK-1 | One shared Rust core, native frontends per platform, no cross-platform UI framework | D-PLAT-1, D-PERF-1, D-A11Y-1 |
| A-STACK-2 | Rust core + native Apple frontend (Swift/TextKit 2) + CodeMirror 6 web frontend | A-STACK-1 |
| A-BIND-1 | Core binds in-process (uniffi on Apple, WebAssembly on web); no separate process or network IPC | D-PERF-1 |
| A-PROC-1 | Walking-skeleton discipline for every major architectural claim | D-PERF-1, D-PROC-1 |
| A-PROC-2 | Baseline-measured regression gate at 110% of committed median | D-PERF-1 |
| A-PROC-3 | Each frontend and subsystem has its own walking-skeleton milestone | D-PROC-1 |
| A-CORE-1 | Document model is `String` (measured, not assumed) | D-PERF-1 |
| A-CORE-2 | tree-sitter with `tree-sitter-markdown` grammar | D-PERF-1, DP-7 |
| A-CORE-3 | Hot-path formatting mirrored in each frontend, gated by parity tests | D-PERF-1 |
| A-CORE-4 | Internal plugin architecture, first-party plugins only | D-NO-7 |
| A-AI-DEFERRED | AI runtime and vendor decisions deferred; §5.1 constraints locked | D-AI-1, D-AI-2, D-AI-3, D-ROAD-3 |

---

## Appendix: Related documents

- `PRODUCT.md` — what the product is, who it serves, the user-facing contract. All product decisions (`D-*`) live there.
- `CONTRIBUTING.md` — how contributions work: the agent-driven development model, review loop, and agent-legibility maintenance.
- `docs/baseline-corpus/` — representative `.md` fixtures the regression gate measures against.
