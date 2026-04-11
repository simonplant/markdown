# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project

**Easy Markdown** — the best free markdown editor on every platform. Apache 2.0, no vault, no account, no subscription. Open any `.md` file from a local folder or cloud drive (iCloud, Dropbox, Google Drive, OneDrive) on macOS, Linux, Windows, Web, iOS, and Android.

This project is **not** a CLI, lint tool, or `jq`-for-markdown. Earlier drafts of this doc framed it that way and were wrong. If the product description here ever drifts back toward "unix tool," stop and check `docs/PRODUCT.md`.

Key docs:
- **`docs/PRODUCT.md`** — Product vision, principles, decisions, features, roadmap, honest risks
- **`docs/ARCHITECTURE.md`** — Technical architecture (Rust core + CodeMirror 6 + Tauri shells)
- **`docs/PRODUCT_LEGACY.md`** — Archived earlier product doc (iOS-first, commercial). Preserved for traceability. Not authoritative.

## Architecture

Three layers, one codebase per layer:

- **Rust core** — tree-sitter-markdown parsing, document model, formatting engine, doctor/diagnostics, file watching, auto-save. Headless, shared by all frontends.
- **CodeMirror 6** — the editor UI. TypeScript. WYSIWYM via decorations (HyperMD-style). Themes, accessibility, CJK/RTL/IME all handled because browsers handle them.
- **Tauri shells** — thin per-platform wrappers around the webview hosting CodeMirror 6. Native menus, file pickers, platform integration. Desktop first (macOS, Linux, Windows, Web), mobile via Tauri mobile after desktop is stable.

**Why this stack:** See `docs/ARCHITECTURE.md`. The short version: per-platform native UI (SwiftUI, GTK, WinUI, Compose) multiplies scope by N and is incompatible with "every platform day one." Tauri+CM6 ships one editor everywhere. Obsidian and VS Code took the same path.

**Explicitly not this stack:**
- Not Electron (too heavy, no Rust core integration)
- Not per-platform native UI (per `docs/PRODUCT.md` D-PLAT-2, reversed from the legacy doc)
- Not a CLI-first architecture with the editor as an afterthought

## Current priorities

Phase 0 (foundations) — the backlog should reflect these before anything downstream:

1. Set up Rust workspace (`cargo init`)
2. Integrate `tree-sitter-markdown` (split_parser branch); port AST types
3. Implement the document model (piece table or rope — decide in ARCHITECTURE.md, don't re-debate in backlog)
4. Port formatting rule *algorithms* from the legacy Swift EMFormatter (reference only — no Swift code transfers)
5. Port doctor rule *algorithms* from the legacy Swift EMDoctor (reference only)
6. CommonMark spec test suite wired into CI with explicit skip-list for known tree-sitter divergences

Phase 1 (editor) begins only after Phase 0 parse/format/doctor are green.

## Legacy Swift prototype

The `reference/` directory contains an older Swift prototype (EMFormatter, EMDoctor, EMParser, TextMutation). **None of this code transfers** — TextKit, NSAttributedString, UIKit, and SwiftUI are Apple-only and would contradict the cross-platform mission.

What transfers is **algorithm logic as reference** when porting to Rust:
- Formatting rules (list continuation, table alignment, heading spacing, etc.)
- Doctor rules (broken links, heading hierarchy, duplicate headings)
- Tree-sitter node type mapping

Do not run Swift tooling on this repo. Do not add Swift targets. Do not write "port this Swift file" in the backlog — write "implement the heading-spacing rule in Rust; reference: `reference/EMFormatter/…`".

## Non-goals (reminders)

The full list lives in `docs/PRODUCT.md` §5. A short version for agents running sprints:

- No vault, library, database, or sidecar files — filesystem is the source of truth
- No accounts, no telemetry, no cloud sync, no AI relay
- No paid tier, no "Pro," no subscription
- No plugin system or extension API
- Not an IDE, not a PKM second brain, not a publishing pipeline
- Not closed-source, not open-core — Apache 2.0 whole stack

If a backlog item drifts toward any of these, flag it during grooming.

<!-- This section is managed by aishore and will be overwritten on `aishore update`. -->
<!-- Customizations here will be lost. Add project-specific instructions above this section. -->
## Sprint Orchestration (aishore)

This project uses aishore for autonomous sprint execution. Backlog lives in `backlog/`, tool lives in `.aishore/`.

**Agent rules (mandatory):**
- **Intent is the north star.** Every item has a commander's intent field. When steps or AC are ambiguous, follow intent.
- **Prove it runs.** Wire code to real entry points. If the build command exists, run it. If a verify command exists, execute it. Working code that's reachable beats tested code that's isolated.
- **No mocks or stubs** in production code unless the item explicitly requests them.
- **Stay in scope.** Implement only the assigned item. Don't fix unrelated code, add unrequested features, or refactor surrounding code.
- **Commit before signaling.** Always commit with a meaningful message before writing result.json.

```bash
.aishore/aishore run [N|ID|scope]    # Run sprints (scope: done, p0, p1, p2)
.aishore/aishore groom              # Groom backlog items
.aishore/aishore scaffold           # Detect fragment risk
.aishore/aishore review             # Architecture review
.aishore/aishore status             # Backlog overview
```
