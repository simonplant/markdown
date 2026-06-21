# BUILD_PLAN — current state → v1.0

> **Execution status (pre-release).** Phases 0–3′ are **done** and merged to `main`:
> the command surface lives in `markdown-core`, the Tauri→WASM cutover shipped (Tauri
> retired, web runs the core as `wasm32-wasip1`), the uniffi binding and the native
> iOS + macOS TextKit 2 app are built and verified by running. **Phase 4** is in
> progress — most rich content (outline, PDF export, math, inline images, extended
> doctor rules, custom themes, Quick Open) is built on Apple; **Mermaid SVG rendering
> and reference-link CommonMark compliance remain**. AI stays deferred post-v1.0.
> The sequencing below is kept as the historical plan and the remaining-work map.

This is the implementation sequencing plan that takes Markdown from where the code is **today** to **v1.0**. It is the bridge `docs/ARCHITECTURE.md` and `docs/PRODUCT.md` deliberately punt to "the backlog": the docs describe the destination architecture and the user-visible roadmap; this file orders the engineering work that gets there and says, for each step, what existing code is reused, rebuilt, or retired.

- **Destination architecture:** `docs/ARCHITECTURE.md` (A-STACK-1, A-STACK-2, §9 engineering phases)
- **User-visible roadmap:** `docs/PRODUCT.md` §5
- **Source of truth for what to work on next:** `backlog/backlog.json` (this plan defines the epics and ordering; the backlog tracks the items)

The discipline that governs every phase is the **walking skeleton** (`docs/ARCHITECTURE.md` §2): each phase is anchored on an end-to-end milestone proven with real running code, and each frontend writes/maintains its **baseline slice** (the committed baseline, 1.1× regression gate) before any feature work proceeds on it.

---

## 0. Why this plan exists — the mid-pivot

The project is **mid-pivot between two architectures**:

| | Origin (built) | Destination (docs) |
|---|---|---|
| Apple (iOS/macOS) | Tauri WKWebView shell wrapping CodeMirror | **Native Swift + TextKit 2**, core via **uniffi** |
| Windows / Linux / Android | Tauri desktop/mobile shells | **CodeMirror 6 web PWA** (the web build serves all three) |
| Core → frontend binding | Tauri IPC (`invoke`) | **WASM** (web) and **uniffi** (Apple), in-process |
| Cross-platform UI framework | Tauri | **None** — shared code is the engine, not the UI |

The **code on disk and the backlog are still the origin architecture**; the **docs are the destination**. This plan implements the docs: reuse what is good (`markdown-core`, the CodeMirror editor logic in `src/`), build the two real bindings, retire Tauri, and ship Apple native + everything-else-as-PWA. **AI stays deferred post-v1.0** (D-ROAD-3 / A-AI-DEFERRED) behind the off-by-default `ai` cargo feature.

### Starting state when this plan was written (`main` @ 05f1b14, pre-pivot — now historical; see the execution-status note at the top)

| Fact | Reality |
|---|---|
| `markdown-core/` Rust crate | Works (`parser`, `formatter`, `doctor`, `ast`, `watcher`). **`rlib` only** — no `cdylib`/`staticlib`. |
| Command-surface orchestration | Lives **inside `src-tauri/src/lib.rs`** (~40 `#[tauri::command]`s), **not** in the core. |
| `src/` CodeMirror 6 frontend | Substantial (read mode, WYSIWYM, themes, find/replace, word count, wikilinks, doctor gutter, completions). `src/main.ts` reaches the core **only via Tauri `invoke()`** (~15 sites). |
| `src/main-web.ts` | Separate **degraded** PWA entry that bypasses the core (`marked` + File System Access). `src/tauri-stub.ts` fakes Tauri for it. |
| WASM binding | **Does not exist** (no wasm-bindgen/wasm-pack/wasm32). |
| uniffi binding | **Does not exist.** |
| Native Apple frontend | **Does not exist** (no Swift/Xcode). |
| CI (`.github/workflows/build.yml`) | **Tauri-centric** (Tauri CLI, `.app`/MSI, WebKitGTK deps). Baseline gate (`measure_baseline.sh --check`) already wired. |
| Root `Cargo.toml` | Patches `glib` solely to work around a Tauri/gtk soundness bug — dies with Tauri. |

---

## 1. Critical path

```
Phase 0  Foundation hardening + binding prep (core command surface, crate-types)
            │
            ├───────────────────────────────┐
            ▼                                ▼
Phase 1  Core → WASM walking skeleton     Phase 1′  Core → uniffi binding   (parallel)
            │                                │
            ▼                                ▼
Phase 2  Tauri→WASM cutover + PWA shell   Phase 2′  Apple TextKit 2 skeleton (iOS)
         → retire Tauri (first Tauri-free    │
            web build)                        ▼
            │                             Phase 3′  Apple feature build-out (iOS→macOS)
            ▼                                │
Phase 3  Web/Win/Linux public pre-release    │
            └────────────────┬───────────────┘
                             ▼
Phase 4  Stabilization & v1.0 (rich content, PDF, hardening, cross-platform parity)
                             │
                             ▼
                   AI — DEFERRED, parked behind cargo feature (not in v1.0)
```

**Hard dependencies:**
1. **One transport-agnostic command surface in `markdown-core`** must exist before either binding (today that orchestration lives in `src-tauri/src/lib.rs`; ARCHITECTURE §3.8 requires it in the core — "no separate API per platform, only a separate binding"). This extraction is the root of the critical path.
2. **WASM binding precedes any Tauri-free web build** — `src/main.ts` cannot drop `invoke()` until a WASM API replaces it.
3. **uniffi binding precedes the Apple walking skeleton** — no Swift can bind the core until the staticlib + uniffi scaffolding exists.
4. **Each frontend skeleton must pass and write its baseline slice before feature work on that frontend** (A-PROC-1, A-PROC-3).
5. **Tauri is deleted only after** the WASM web build reaches feature/quality parity with today's Tauri web experience — otherwise the cutover regresses the product.

### Note on ordering (Apple-lead vs web-first)

`PRODUCT.md` §5 lists Apple (iOS & macOS) as the **lead** ship and quality bar, while sequencing the web build to follow. This plan keeps Apple as the architectural lead frontend, but runs the **Tauri→WASM web cutover early and in parallel** with the Apple track, because it (a) unblocks the only currently-shippable public artifact, (b) retires the Tauri stack that actively constrains the workspace (the glib patch, the Tauri-centric CI), and (c) de-risks the in-process-binding claim on the faster-to-iterate target first. The two frontend tracks (Phase 1/2/3 web, Phase 1′/2′/3′ Apple) share only the Phase-0 core surface and otherwise proceed independently, so the order can be re-weighted toward Apple without restructuring any work item.

---

## 2. Phases

### Phase 0 — Foundation hardening & binding prep
**Goal:** make the core the single source of the command surface and able to produce both binding targets. No new frontend yet.
**Skeleton anchor:** the project-level loop (open → edit → save → reopen) proven **through a direct core API call**, not through Tauri IPC.

- **EPIC-CORE-API** — Extract the orchestration in `src-tauri/src/lib.rs` (doctor diagnose, format mutations, viewport, undo/redo, wikilink resolve/create, backlinks, watching lifecycle, content-level file I/O) **into `markdown-core`** as plain Rust functions over a `Session`/`Workspace` type. **Relocate, don't rewrite.** Tauri commands become thin pass-throughs temporarily. Platform glue (keychain, OS dialogs, recent-files persistence, AI HTTP) stays out of the core. Set `crate-type = ["rlib", "cdylib", "staticlib"]` in `markdown-core/Cargo.toml`. Write `docs/CORE-API.md` as the contract both bindings implement.
- **FEAT-047** — finish the four-slice baseline corpus (small/medium/large/session) + per-slice gate.
- **FEAT-053** — land the hot-path formatting parity-test harness (both frontends mirror hot-path rules; A-CORE-3).

**Exit:** core exposes the full surface; `cargo build` emits rlib+cdylib+staticlib; round-trip skeleton test passes via the core API (not Tauri); `measure_baseline.sh --check` green; four-slice corpus active.

### Phase 1 — Core → WASM walking skeleton *(reuses all of `markdown-core`)*
**Goal:** prove ARCHITECTURE §8 "core-to-WASM viability" end-to-end.

- **EPIC-WASM** — Add `wasm-bindgen`/`wasm-pack` targeting `wasm32`. **Spike tree-sitter-md in WASM first, fail fast** (highest-impact unknown). Define a JS-facing API mirroring the Phase-0 surface (buffer-in/buffer-out; file handles owned by the shell). A throwaway HTML harness exercises every entry point against the corpus. Capture an in-browser **web baseline slice** and extend the gate.

**Exit:** core (incl. parser) runs in WASM; the browser harness does open → edit → format → diagnose → save-buffer → reopen against the real WASM core on the corpus; web baseline committed.

### Phase 1′ — Core → uniffi binding *(parallel; gated on Phase 0)*
**Goal:** produce the Apple-side binding so the Apple skeleton can start.

- **EPIC-UNIFFI** — Add `uniffi` (or a thin `markdown-core-ffi` wrapper); build `staticlib` for `aarch64-apple-ios` + `aarch64-apple-darwin`; generate Swift bindings; package an XCFramework. A Swift unit test round-trips open → edit → save → reopen through uniffi. (Requires a macOS CI runner.)

**Exit:** XCFramework builds; Swift test exercises the core via uniffi end-to-end.

### Phase 2 — Tauri→WASM cutover & PWA shell *(the central migration)*
**Goal:** replace Tauri IPC with the WASM core + browser-native shell at parity, then retire Tauri.
**Skeleton anchor:** the full CodeMirror frontend running with **zero Tauri imports**, core via WASM, files via File System Access, installable as a PWA.

- **EPIC-CUTOVER** — Introduce one `core` adapter (the Phase-1 WASM API) and replace every `invoke()` site in `src/main.ts` (and the Tauri imports reached via `doctor.ts`, `settings.ts`, `wikilinks.ts`, `format.ts`, `ai.ts`). **Converge the two web entries:** promote `main.ts`'s full feature set onto the WASM backend, fold in `main-web.ts`'s File System Access logic, delete the degraded `marked`-based path and `tauri-stub.ts`. Build the **PWA shell** that replaces the Tauri shell: File System Access open/save (+ `<input>`/download fallback), recent files (IndexedDB), file-change/conflict detection (replacing `start_watching`), auto-save (1s, FEAT-051), service worker offline + install manifest.
- **EPIC-RETIRE-TAURI** — Remove the `src-tauri/` workspace member, the **glib `[patch.crates-io]`** in root `Cargo.toml`, `@tauri-apps/*` deps, and the `"tauri"` npm script.
- **EPIC-CI-REPOINT** — Re-point `.github/workflows/build.yml`: drop the Tauri CLI / `.app` / MSI / WebKitGTK jobs (added by FEAT-048); make `build-web` primary; add the Apple uniffi build job; keep core build, tests, CommonMark suite, baseline `--check`.

**Exit:** no `@tauri-apps` import and no `invoke()` in `src/`; `src-tauri/` removed; workspace builds without the glib patch; the PWA opens/edits/saves/reopens real files, installable + offline, at parity with the prior Tauri web experience; CI green with Tauri jobs gone.

### Phase 2′ — Apple TextKit 2 walking skeleton (iOS lead) *(parallel; gated on Phase 1′)*
**Goal:** prove the native Apple frontend binds the core via uniffi and edits real text in TextKit 2.
**Skeleton anchor (ARCHITECTURE §8 "native Apple editor effort"):** an iOS app on a **real device** doing the full core loop, deliberately minimal — no WYSIWYM polish yet.

- **EPIC-APPLE-SKELETON** — Xcode/SwiftPM project consuming the Phase-1′ XCFramework; iOS target first. Minimal TextKit 2 editor view bound to the core; Files-app open/save; on-device open → edit → save → reopen. Capture an **Apple baseline slice** on a real device.

**Exit:** iOS app runs the full core loop via uniffi on a real device; Apple baseline committed.

### Phase 3 — Web / Windows / Linux first public pre-release
**Goal:** the PWA *is* the Windows/Linux/Android delivery (no native shells). Harden to public-release quality.

- **EPIC-PWA-RELEASE** — PWA install/UX hardening on Chromium (Windows/Linux/Android) + graceful Firefox/Safari fallback; finalize conflict-detection UX; cross-browser parity QA against the web baseline. Distribution = static host + PWA install (**no Flatpak/MSI/WinGet** — they died with Tauri).

**Exit:** installable, offline public pre-release PWA on Chromium desktop + Android, functional fallback on FF/Safari, measured against the committed web baseline.

### Phase 3′ — Apple feature build-out (iOS → macOS) *(parallel)*
**Goal:** bring the Apple frontend to product parity, then share the TextKit 2 surface to macOS.

- **EPIC-APPLE-FEATURES** — Read mode, WYSIWYM on TextKit 2, mode transition, native file management, share sheet, accessibility, hot-path formatting mirrored from the core (parity-tested via the Phase-0 harness); macOS target sharing the `NSTextView` surface. Each lands against the Apple baseline.

**Exit:** iOS + macOS reach the web frontend's read/write feature bar; parity tests green; Apple baseline maintained.

### Phase 4 — Stabilization & v1.0
**Goal:** rich content, PDF export, extended doctor, custom themes, cross-platform hardening (ARCHITECTURE §9 + PRODUCT §5).

- Kept backlog items, scoped per-frontend where needed, each measured against baseline: **FEAT-036** extended doctor, **FEAT-037** Mermaid (render-only for v1.0; AI-assist is post-v1.0), **FEAT-038** math, **FEAT-039** folding/outline, **FEAT-040** multi-doc, **FEAT-041** quick open, **FEAT-042** images, **FEAT-043** PDF export, **FEAT-044** custom themes. Close reference-link CommonMark compliance (the CI skip-list driven to target).

**Exit:** v1.0 — rich content on web + Apple, PDF export, hardened, baselines green, CommonMark skip-list at target.

### Post-v1.0 — AI (deferred, parked)
AI stays behind the off-by-default `ai` cargo feature (FEAT-045 done). When unparked, it begins with its own walking skeleton (plugin host + keychain + consent-gated UI + graceful degradation). The Tauri-era AI cloud HTTP (`cloud_request_*` in `src-tauri/src/lib.rs`) is **not** carried forward as-is — it is re-homed into the post-Tauri architecture. No AI work is on the v1.0 path. (FEAT-031 voice-intent is parked here too — AI-dependent.)

---

## 3. Risks & mitigations

| Risk | Mitigation |
|---|---|
| **tree-sitter won't compile to WASM** (the whole web track depends on it) | Phase 1 leads with a WASM compile spike of the parser as the *first* skeleton step — fail fast before any feature port. |
| **Cutover regresses the web product** | Tauri is **not deleted until Phase 2 reaches parity**; the `invoke()` call-site list makes "what must be replaced" explicit; the degraded `main-web.ts` is folded in, not shipped. |
| **WASM core slower than native IPC** | Phase-1 in-browser web baseline slice + the 1.1× gate block merges that degrade it. |
| **WASM and uniffi surfaces drift** | Phase 0 extracts one core surface + `docs/CORE-API.md`; both bindings target it; the hot-path parity test (FEAT-053) enforces formatting parity (A-CORE-3). |
| **TextKit 2 WYSIWYM is hard** | The Apple skeleton runs on a **real device** before any feature work (A-PROC-3); the bar is validated by use, not by compile. |
| **Apple / web tracks diverge** | Shared core + parity tests + per-platform baseline slices keep behavior aligned. |
| **Review-bottleneck** (D-ROAD-2) | The parallel tracks (1/1′, 2/2′, 3/3′) let the architect sequence reviews; phases gate on "real, running, measured," not on agent throughput. |

---

## 4. Backlog reconciliation

Applied to `backlog/backlog.json` (retired items moved to `backlog/archive/retired-tauri.json`):

- **Retired (rejected Tauri / cross-platform-UI approach):** FEAT-022 (Linux Tauri), FEAT-023 (Windows Tauri), FEAT-028 (Flatpak-on-Tauri), FEAT-033 (iOS Tauri), FEAT-034 (Android Tauri), FEAT-031 (voice-intent — AI-dependent, parked with AI).
- **Amended:** FEAT-048 (done) added the Tauri CI jobs — superseded in part by **EPIC-CI-REPOINT**. FEAT-037 descoped to render-only for v1.0 (AI-assist → post-v1.0). FEAT-041/042 file-walk/IO scope moved from `src-tauri` to `markdown-core` (reached via the binding).
- **Kept, re-tagged** to the new phase model (`phase`/`epic` fields; `Phase5-` title prefixes → `Phase4-`): FEAT-036–044 → Phase 4; FEAT-047, FEAT-053 → Phase 0. Done items stay done.
- **Added epics:** EPIC-CORE-API (P0), EPIC-WASM (P1), EPIC-UNIFFI (P1′), EPIC-CUTOVER (P2), EPIC-RETIRE-TAURI (P2), EPIC-CI-REPOINT (P2), EPIC-APPLE-SKELETON (P2′), EPIC-PWA-RELEASE (P3), EPIC-APPLE-FEATURES (P3′). Walking-skeleton ACs exercise real infra (real browser/device, real core), not `test -f`/grep checks.

---

## 5. Key files

- `markdown-core/Cargo.toml` — add `crate-type`; later wasm-bindgen + uniffi deps (the binding root).
- `src-tauri/src/lib.rs` — command-surface logic to relocate into the core, then the dir to retire.
- `src/main.ts` — Tauri-coupled frontend; ~15 `invoke()` sites to cut over.
- `src/main-web.ts`, `src/tauri-stub.ts` — fold File System Access logic into the unified entry; delete the stub.
- `.github/workflows/build.yml` — re-point from Tauri to PWA + Apple builds; keep the baseline gate.
- root `Cargo.toml` — remove the glib `[patch.crates-io]` and the `src-tauri` workspace member.
- `backlog/backlog.json` — reconciliation above.
- `docs/CORE-API.md` — the transport-agnostic command surface contract (stub created; filled in EPIC-CORE-API).
