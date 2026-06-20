# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Working agreement

On a large multi-step build (a milestone roadmap, "complete the entire build", etc.), **keep going to the next milestone automatically** — build, verify, commit, repeat — until the whole task is genuinely done. Do **not** stop at "natural checkpoints" to report-and-ask after finishing one piece; that wastes turns and asks for permission already granted. Only stop for a real decision only the user can make, a hard blocker, or actual completion. Status updates are fine as a passing note while continuing — never as a turn-ending question.

## Project

**Markdown** — the free, final markdown editor for the AI age. Apache 2.0, no vault, no account, no subscription. Markdown is the document format of the AI age; the tool for working with it should be free, open source, and run on everything. Open any `.md` file from a local folder or cloud drive (iCloud, Dropbox, Google Drive, OneDrive) on macOS, Linux, Windows, Web, iOS, and Android.

This project is **not** a CLI, lint tool, or `jq`-for-markdown. Earlier drafts of this doc framed it that way and were wrong. If the product description here ever drifts back toward "unix tool," stop and check `docs/PRODUCT.md`.

Key docs:
- **`README.md`** — one-page project orientation
- **`docs/PRODUCT.md`** — product vision, principles, decisions, walking skeleton (§7.1), features, roadmap, honest risks
- **`docs/ARCHITECTURE.md`** — technical architecture (shared Rust core + native Apple frontend + CodeMirror 6 web frontend)
- **`PRIVACY.md`** — no telemetry, no network, files stay local

## Architecture

One shared engine, a native editor frontend per platform. No cross-platform UI framework. See `docs/ARCHITECTURE.md` for the full treatment.

- **Rust core** (`markdown-core`) — tree-sitter-markdown parsing, document model, formatting engine, doctor/diagnostics, file watching, auto-save. Headless, shared by every platform. Compiles to a native library on Apple platforms and to WebAssembly for the web.
- **Native Apple frontend** — Swift on TextKit 2, for iOS and macOS. The lead frontend; iOS is the priority platform and sets the quality bar. The Rust core binds in-process via `uniffi`. Native text selection, keyboard, dictation, share sheet, Files integration, and VoiceOver.
- **Web frontend** — CodeMirror 6 in TypeScript, for Web, Windows, and Linux (and Android via PWA). WYSIWYM via decorations; CJK/RTL/IME/accessibility handled because browsers handle them. The Rust core runs as WebAssembly in the same context. Delivered as an installable PWA.

**Why this shape:** a 9.5/10 native-feeling editor on iOS — the priority platform — cannot be met by a web-canvas text surface, so the editor goes native on Apple. The web, Windows, and Linux are well served by a browser-grade editor, so one web build covers all three. The shared code is the engine, not the UI.

**Explicitly not this stack:**
- Not a single cross-platform UI framework (no Tauri, Electron, or Flutter) — none clears the native-feel bar on iOS while keeping the editor maintainable.
- Not N hand-built native editors — only the Apple frontend is native; the web frontend covers everything else.
- Not a CLI-first architecture with the editor as an afterthought.

## How to find current priorities

**`backlog/backlog.json`** is the source of truth for what to work on next. Items are ordered by phase and priority. Do not hard-code feature lists in docs — check the backlog.

**Key constraints that don't change:**
- **Baseline regression gate is active.** `docs/baseline.json` contains 5-run median measurements. Every merge is checked against a 1.1x regression threshold via CI.
- **Document model is `String`.** The engine decision measured all three candidates against baseline; piece table and rope both regressed beyond threshold. See `docs/engine-decision.md`. Revisit only if large-file performance data demands it.
- **Phase ordering is not negotiable.** Dependencies in the backlog enforce this. Don't skip ahead.

## Reference Swift prototype

The `reference/` directory contains an older Apple-only Swift prototype. Its formatting, doctor, and parser algorithms were ported to Rust in `markdown-core/`; consult it for rule behavior only. The native Apple frontend (iOS/macOS) is a fresh build on TextKit 2 over the Rust core — not a continuation of this prototype. The prototype itself is read-only and is not built.

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

<!-- This section is managed by aishore and will be overwritten on `aishore update`. -->
<!-- Customizations here will be lost. Add project-specific instructions above this section. -->

<!-- This section is managed by aishore and will be overwritten on `aishore update`. -->
<!-- Customizations here will be lost. Add project-specific instructions above this section. -->

<!-- This section is managed by aishore and will be overwritten on `aishore update`. -->
<!-- Customizations here will be lost. Add project-specific instructions above this section. -->

<!-- This section is managed by aishore and will be overwritten on `aishore update`. -->
<!-- Customizations here will be lost. Add project-specific instructions above this section. -->
## Sprint Orchestration (aishore)

This project uses aishore for autonomous sprint execution. Backlog lives in `backlog/`, tool lives in `.aishore/`.

**Agent rules (mandatory):**
- **Core before features.** The working core — the primary end-to-end path — must pass before feature work proceeds. Check the item's `track` field: `core` items build the foundation; `feature` items decorate it.
- **Intent is the north star.** Every item has a commander's intent field. When steps or AC are ambiguous, follow intent.
- **Prove it runs.** Wire code to real entry points. If the build command exists, run it. If a verify command exists, execute it. Working code that's reachable beats tested code that's isolated.
- **No mocks or stubs** in production code unless the item explicitly requests them.
- **Stay in scope.** Implement only the assigned item. Don't fix unrelated code, add unrequested features, or refactor surrounding code.
- **Commit before signaling.** Always commit with a meaningful message before writing result.json.

**Typical flow:** `init` → `refine` (fill PRODUCT.md) → `backlog populate` → `groom` → `run`

```bash
.aishore/aishore run [N|ID|scope]    # Run sprints (scope: done, p0, p1, p2)
.aishore/aishore groom              # Groom backlog items (AI adds steps, AC, priority)
.aishore/aishore scaffold           # Establish working core, detect fragment risk
.aishore/aishore review             # Architecture review
.aishore/aishore status             # Backlog overview
```
