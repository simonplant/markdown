# CORE-API — the transport-agnostic command surface

> **Status: stub.** This document names the contract; it is filled out during **EPIC-CORE-API** (BUILD_PLAN Phase 0). Until then, the live surface is the set of `#[tauri::command]`s in `src-tauri/src/lib.rs` — which is exactly the orchestration that EPIC-CORE-API relocates into `markdown-core`.

`docs/ARCHITECTURE.md` §3.8 requires a single command surface in the core:

> The same Rust functions are reached through `uniffi` on Apple and through WebAssembly bindings on the web — there is no separate API per platform, only a separate binding.

This file is that surface's contract. Both bindings — **WASM** (`EPIC-WASM`) and **uniffi** (`EPIC-UNIFFI`) — implement exactly these operations against `markdown-core`; nothing here is platform-specific. Platform glue (OS file dialogs, keychain, recent-files persistence, menu/shortcuts, AI cloud HTTP) lives in each frontend/shell, **not** in this surface.

## Design rules

- **Buffer-in / buffer-out.** The core operates on document *content* and returns mutations/diagnostics. It does **not** own OS file handles — the shell (PWA File System Access, or Apple Files) owns handles and hands content across the boundary.
- **One surface, two bindings.** Every operation below is one Rust function. The binding is generated, not hand-written per platform.
- **No drift.** Hot-path formatting rules duplicated into a frontend are kept identical to the core by the parity test (FEAT-053, A-CORE-3).

## Operations (to be finalized in EPIC-CORE-API)

Relocated from `src-tauri/src/lib.rs`; grouped by concern. Signatures are indicative and finalized during extraction.

| Group | Operation | Notes |
|---|---|---|
| Document | `open(content, path_hint) -> Session` | BOM/encoding detection (FEAT-054) on the way in |
| Document | `edit(session, change) -> ()` | applies an edit to the in-core buffer |
| Document | `save_buffer(session) -> bytes` | returns content to persist (shell writes the file) |
| Document | `close(session) -> ()` | releases per-document state |
| Formatting | `format(session) -> Vec<Mutation>` | full-document reformat (`formatter.rs`) |
| Diagnostics | `diagnose(session) -> Vec<Diagnostic>` | doctor rules (`doctor.rs`) |
| Editing | `undo / redo(session) -> ()` | core command history (§3.5) |
| Viewport | `viewport(session, range) -> Tokens` | tokenized range for lazy rendering on large files |
| Links | `resolve_wikilink(session, target) -> Option<Path>` | |
| Links | `compute_backlinks(session) -> Vec<Backlink>` | |
| Watching | `watch_start / watch_stop(session)` | external-change detection; conflict signal to the shell |

## What is NOT in this surface

OS file pickers, recent-files storage, keychain/secret storage, application menus and shortcuts, window management, and any AI network calls. Those are frontend/shell responsibilities. AI remains deferred post-v1.0 (D-ROAD-3); when it returns it is re-homed off the retired Tauri `cloud_request_*` path.
