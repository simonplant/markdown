# Easy Markdown — Product Document

This document is the single source of truth for what we are building, why, and the decisions that constrain implementation. The backlog is derived from this document. If a decision isn't recorded here, it hasn't been made.

**How to read this document**: Section 1 is the north star (press release + why now). Sections 2–3 establish intent (who we serve, what problems we solve). Sections 4–6 establish constraints (principles, non-goals, and the decisions that bind us). Sections 7–9 define what gets built (features, roadmap, honest risks). Sections 10–11 define how we measure success.

**Ambition level**: The best free markdown editor on every platform. Not "a nice open-source alternative" — the one people reach for when they want to read, write, or refine a `.md` file. Obsidian's craft without Obsidian's vault. iA Writer's polish without the $50 and the Apple-only lock-in. VS Code's ubiquity without being a code editor. Every decision in this document should be evaluated against that bar.

**Document heritage**: The earlier version of this file (`PRODUCT_LEGACY.md`) was a commercial iOS-first product plan with a $9.99 purchase and a $3.99/mo Pro AI subscription. Most of the feature thinking and design principles transfer. The business model, platform sequencing, and "not open source" decision do not. Where legacy decisions are preserved below, they keep their IDs. Where they are reversed, the reversal is explicit.

---

## 1. Press Release (North Star)

This is the Amazon "working backwards" press release. It describes the product as if it has already shipped. Every decision in this document should be traceable back to making this press release true.

> **FOR IMMEDIATE RELEASE**
>
> ### Easy Markdown: the best free markdown editor on every platform.
>
> *Open any `.md` file, anywhere, on any device. No vault. No account. No subscription. Fully open source, Apache 2.0.*
>
> **2026** — Markdown is the universal format of the AI age. Every LLM reads and writes it. Every README, every note, every AI-generated report, every prompt — markdown. But the tools people use to open these files are locked-down vaults (Obsidian), premium purchases (iA Writer, Typora), Electron boat anchors, or TextEdit.
>
> **Easy Markdown is different.** Open any `.md` file from anywhere your OS can reach — a local folder, iCloud Drive, Dropbox, Google Drive, OneDrive, a cloned git repo — and edit it in a native-feeling editor that runs on macOS, Linux, Windows, Web, iOS, and Android. No import step. No "create a vault." Your files stay where you put them, in standard markdown, with no sidecar files and no proprietary metadata.
>
> **The experience is the point.** Intelligent auto-formatting cleans up your markdown as you type. A built-in document doctor catches broken links, inconsistent headings, and structural issues in the background. When you toggle between source and rich view, markdown *transforms* into its rendered form — a signature animation we call The Render. Tables, diagrams, code blocks, and math all render inline. The editor feels fast because it is fast: a Rust core does the heavy lifting and CodeMirror 6 handles the UI that browsers already solved (CJK, RTL, IME, accessibility).
>
> **AI is local-first and optional.** Core AI features — improve, summarize, continue, smart completions — run on-device with no account and no network. Users who want frontier-model capabilities can paste their own API key (OpenAI, Anthropic, Ollama, or any OpenAI-compatible endpoint); calls go directly from their machine to their chosen provider. We never proxy, relay, or store keys. There is no paid tier. There is no "Pro." There is no upsell.
>
> **It's free software, forever.** Apache 2.0, source on GitHub, built and maintained through autonomous agent-driven sprints. No one has to burn their evenings and weekends to keep it alive — the pattern that killed MarkText, Remarkable, Haroopad, and every other free markdown editor before it. Easy Markdown is an experiment in what happens when an open-source app is built by agents with a human at the helm: a free tool that sustains itself.
>
> "We built it because we were tired of choosing between a paywall and a vault," said the Easy Markdown team.
>
> Getting started is instant: download, open a file, write.

### What this press release locks in

| Claim | Implication | Constrains |
|-------|-------------|------------|
| "Best free markdown editor on every platform" | Cross-platform day one, not sequenced. No platform is a second-class citizen by design. | Architecture, tech stack |
| "Open any `.md` file from anywhere your OS can reach" | Must use OS file APIs. Cloud-drive files are accessed via OS mounts/providers, not reimplemented sync. | DP-1, file architecture |
| "No vault. No account. No sidecar files." | Zero-configuration first launch. Nothing proprietary touches the user's filesystem. | UX, file handling |
| "Native-feeling on every platform" | We use a webview-based stack (Tauri + CodeMirror 6), not per-platform native UI. The "native feeling" comes from platform conventions (menus, shortcuts, file pickers, typography), not from per-platform UI codebases. | Architecture, D-PLAT-2 reversal |
| "Fast because it is fast" | Rust core for parsing/formatting/diagnostics. Hot-path interactions duplicated in JS for zero-latency response. <50ms format of 10k-line docs, <1ms incremental reparse. | Engineering budget |
| "AI is local-first and optional" | On-device inference for core features. BYO API key for power users. No server infrastructure. No paid tier. | D-AI-1 (revised), D-AI-2 (replaced) |
| "Apache 2.0, free software forever" | The whole stack is open source. Not open-core. Not source-available. | D-NO-13 reversed |
| "Built and maintained through agent-driven sprints" | Sustainability bet: agents break the volunteer-burnout failure mode. Honestly named as a bet, not a slogan. | Section 9 Honest Risks |

### Why now

Six things make this product possible and necessary in 2026:

1. **AI made markdown universal.** LLMs don't output LaTeX, DOCX, or HTML. They output markdown. The volume of machine-generated markdown has grown by orders of magnitude and the tooling hasn't kept up.
2. **Obsidian proved the market and drew a line.** Obsidian showed that millions of people want a markdown editor with craft and local files. It also showed the limits of that model: a proprietary vault, a paid sync tier, a paid publish tier, closed source, and a plugin ecosystem that makes users fear leaving. The opportunity is everything Obsidian is minus everything Obsidian takes.
3. **CodeMirror 6 solved the cross-platform editor problem.** A decade of attempts to build cross-platform text editors using native frameworks produced mostly Apple-only products (iA Writer, Typora-on-macOS, Bear, Ulysses). CodeMirror 6 handles CJK, RTL, bidi, IME, and accessibility because browsers already do — the multi-year problems that sank every native attempt are free. This is the pragmatic path.
4. **Tauri made cross-platform shells cheap.** Tauri 2.0 provides webview hosting, Rust backend, file system access, menus, auto-updater, and mobile support out of the box. The per-platform shell is ~1,000 lines instead of ~10,000.
5. **On-device inference crossed the usability threshold.** llama.cpp, MLX, Core ML, and ONNX runtimes can run 1–4GB quantized models on commodity hardware with usable quality and sub-second latency. Local-first AI for prose is now viable without a GPU cluster.
6. **Agents broke the volunteer-burnout pattern.** Every standalone free markdown editor before this died because a single human maintainer ran out of energy: MarkText (54K stars, deprecated 2025), Remarkable, Haroopad, Abricotine — 100% mortality rate. Easy Markdown is an experiment in a different shape of open source: grooming and sprint execution run through autonomous agents (`aishore`), with a human directing intent and reviewing output. This does not eliminate the human bottleneck; it moves it from "write every line of code on evenings and weekends" to "review and steer." Whether this is enough to sustain a free editor category long-term is an open question. We are running the experiment.

---

## 2. Problem Statement

### The market landscape

| | Great UX | Mediocre UX |
|---|---|---|
| **Locked storage / vault** | Obsidian, Bear, Notion, Ulysses | Day One, Standard Notes |
| **Open files, cross-platform** | *empty — this is us* | VS Code (not an editor for prose), text editors, TextEdit, Notes |
| **Open files, Apple-only** | iA Writer ($50), Typora (desktop) | — |

Easy Markdown occupies the empty cell: **great UX + open files + cross-platform + free**. No product in the market holds this position.

**Decision [D-MKT-1]**: We are building at the intersection of four underserved positions: **craft-quality UX + open files + every platform + free**. We serve both directions of the AI-era markdown workflow: writing with AI as co-author and receiving/refining AI-generated output.

**Decision [D-MKT-3]**: Markdown is the document format for most knowledge work in the AI age. We are the tool that makes opening, reading, and editing any `.md` file a first-class experience on any device. The workflow — open, read, edit, render, share — is first-class. Rich content (tables, diagrams, code blocks, math) renders beautifully inline.

### Pain points we solve

| # | Pain point | Our response | Decision |
|---|-----------|--------------|----------|
| P1 | **Vault/library lock-in.** Obsidian requires a vault. Bear uses proprietary storage. Users don't realize they're locked in until they try to leave. | Use only OS-level file access. Never create a proprietary container. | **[D-FILE-1]** No vault, library, or proprietary file store. Ever. |
| P2 | **Platform fragmentation.** The best-crafted markdown editors are Apple-only. Typora is desktop-only. 1Writer is iOS-only. There is no single tool that works well everywhere a user's files live. | Cross-platform day one via Tauri + CodeMirror 6. | **[D-PLAT-1]** All platforms are first-class. Ship order is driven by engineering cost, not tier. |
| P3 | **Paywalls for basic features.** Obsidian charges $10/mo for sync that git does free, and $20/mo for publish that any static host does free. iA Writer is $50. Bear and Ulysses are subscriptions. | Free forever. Apache 2.0. No Pro tier. No sync subscription. No publish subscription. | **[D-BIZ-1]** The app is free. There is no commercial upgrade path. |
| P4 | **Formatting friction.** Most editors are dumb text boxes. Users manually fix indentation, align tables, chase broken links. | Auto-formatting engine + document doctor as core features, not plugins. | **[D-EDIT-1]** Intelligent editing is built-in and on by default. |
| P5 | **Bloat and complexity.** Obsidian's plugin system is powerful but overwhelming. Notion is a kitchen sink. | Focused feature set. No plugin system. | **[D-SCOPE-1]** No plugin/extension system. We ship what we ship. |
| P6 | **AI requires cloud and accounts.** Notion AI, Craft AI, and every other AI writing tool sends your content to remote servers, requires an account, and charges a separate subscription. | Core AI runs on-device with no account. Optional BYO-key mode calls the user's chosen provider directly. We never see the content or the key. | **[D-AI-1]** Local-first AI. No relay. No paid tier. |
| P7 | **No purpose-built markdown tool for non-IDE users.** Developers use Cursor/VS Code but have no great standalone tool for prose. Writers have no tool that combines AI + open files + great UX + every platform. | Be the app developers open alongside their IDE, and the app writers open instead of one. | **[D-MKT-2]** Position as the complement to IDEs, not a competitor. |
| P8 | **No AI-native document tool for markdown.** AI agents produce `.md` files daily — research reports, summaries, briefs, architecture docs — and there's no purpose-built tool for consuming, refining, and sharing them. | Open AI-generated `.md` files with diagrams/tables rendering beautifully on open. Refine with local AI or BYO-key AI. Share as polished PDF or the `.md` itself. | **[D-MKT-3]** Easy Markdown is the AI-era markdown tool. |
| P9 | **Free markdown editors die.** MarkText, Remarkable, Haroopad, Abricotine. Volunteer maintainers burn out. | Agent-driven grooming and sprint execution via aishore. Sustainability is a bet, not a promise — see §9. | **[D-SUST-1]** We are running the experiment. |

---

## 3. Target Users

### Primary persona: The AI-Native Knowledge Worker

> *"I write product briefs, review AI research reports, draft architecture docs — all in markdown, all with AI helping me. I need a tool that makes these documents look beautiful, helps me refine with AI, and lets me share polished output. I don't think of myself as 'a markdown user' — I'm someone who creates documents in the AI age."*

- Creates documents with AI as co-author: product briefs, reports, proposals, blog posts
- Receives `.md` files from AI agents (Claude, ChatGPT, Perplexity, Cursor, custom agents)
- Refines content: tightens prose, fixes structure, adjusts tone
- Shares polished output: PDF export, `.md` share, print
- Needs rich content (tables, diagrams, code blocks) to render beautifully
- **Platforms**: mixes desktop and mobile; cross-platform matters
- **Scale**: tens of millions of knowledge workers who create and consume markdown daily

**Decision [D-USER-1]**: This is our primary user. When trade-offs arise, optimize for them.

### Secondary persona: The Builder

> *"I'm a product manager / engineer / technical writer. I write PRDs, architecture docs, API docs, READMEs. AI co-authors everything. I want an editor that understands my content and helps me make it better — without being an IDE."*

- Product managers, engineers, technical writers
- AI is a co-author on everything
- Rich content matters: diagrams, tables, code examples
- Cares where files live — git repos, iCloud, Dropbox, local folders
- Loudest referral channel — builders recommend tools to each other

**Decision [D-USER-2]**: Deep investment. Keyboard shortcuts, fast file switching, AI that understands code-adjacent writing. We will not add Vim bindings, terminal integration, or git integration — Easy Markdown is not an IDE.

### Tertiary persona: The Content Creator

> *"I'm a blogger / devrel / docs team member. Markdown is my source format. AI helps me draft, I refine, I publish."*

- Bloggers, developer relations, documentation teams
- Markdown is the source format for their publishing pipeline (Hugo, Jekyll, Docusaurus)
- Values typography and rendering — their content needs to look good in the editor too

**Decision [D-USER-3]**: Served naturally by the open-file model. We will not build publishing pipelines ([D-NO-4]).

### Who we explicitly do not serve

- **PKM enthusiasts building a second brain** → Obsidian owns this. We do not build graph views or daily-note generators. Wikilinks and backlinks are in scope (see F-019) because they work with plain files — vaults are not.
- **Developers who want a code editor** → VS Code and Cursor own this.
- **Teams who need real-time collaboration** → Notion and Google Docs own this. Requires server infrastructure and accounts.
- **Academics who need citation management** → Zettlr owns this.

### Scale consideration

**Decision [D-USER-4]**: Global from day one. The product must work excellently for non-English writing (CJK, RTL, accented characters, emoji). This is free from CodeMirror 6 — it's why we chose it. UI localization is Phase 2; correct rendering is Phase 1.

---

## 4. Design Principles

Non-negotiable. Resolve ambiguity when the backlog doesn't have a clear answer.

### DP-1: Open by default
The file system is our storage layer. We use the OS file picker to open files and the OS file system to save them. We never create a vault, database, index, library, or proprietary container. If the user uninstalls Easy Markdown, their files are untouched.

**What this means in practice**:
- No app-specific directory structure
- No sidecar files, no hidden metadata folders
- No SQLite database for file indexing
- Search is file-system-based where possible; when an index is needed for speed, it's rebuildable, ephemeral, and stored outside the user's content tree
- Cloud-drive files (iCloud, Dropbox, Google Drive, OneDrive) are accessed through OS file providers, not through our own sync

### DP-2: The experience is the moat
The UX — not just the UI — is the primary differentiator. What people can't go back from is the *experience*: opening a file and editing in under a second, lists auto-continuing on Enter, tables aligning as you type, the doctor catching broken links without being asked, AI improving a paragraph with one gesture, work saved before you think to save it, state restored exactly where you left off, an AI-generated report with diagrams and tables rendering beautifully on open. Our retention model is **experiential lock-in, not organizational lock-in**. You don't come back because your data is trapped; you come back because nothing else feels this good.

**What this means in practice**:
- UX quality is a blocking criterion for every release
- Smart defaults over configuration
- Animations are designed: spring curves, durations, and easing specified per-interaction
- Typography and spacing are treated as carefully as feature logic

**Decision [D-UI-1]**: No feature ships unless the flow, latency, defaults, and error states have been explicitly designed and polished.

**Honest caveat**: Some things that are easy in native UI frameworks (SwiftUI Core Animation at 120fps on ProMotion displays, for example) are harder in a webview. We will get close, not identical. See §9.

### DP-3: The editor should be smart
Auto-formatting, document doctor, and local AI are core to the value proposition, not secondary.

- Auto-formatting runs inline, in real time, as the user types
- Document doctor runs in the background and surfaces suggestions non-intrusively
- Local AI is available with a single gesture/shortcut
- All three are on by default; individual rules can be disabled

### DP-4: Platform-idiomatic, not platform-native
Each platform build respects its platform's conventions for menus, keyboard shortcuts, file pickers, window management, system integration, and default typography. The editor UI inside the window is the same CodeMirror 6 codebase everywhere — the shell around it is platform-aware.

**What this means in practice**:
- macOS: standard menu bar, ⌘-shortcuts, Services menu, Spotlight, Quick Look
- Linux: GTK file dialogs, XDG desktop integration, `.desktop` + AppStream metadata
- Windows: WinUI menu patterns, Explorer integration, WebView2
- iOS: UIKit sheets, swipe gestures, Files app integration, share sheet
- Android: Material patterns, Storage Access Framework, intent filters
- Web: PWA, File System Access API where available

**Decision [D-PLAT-2]** *(reversed from legacy)*: We use **Tauri + CodeMirror 6**. The legacy doc required "native UI frameworks only, no Electron/RN/Flutter/Tauri" — that was written for an Apple-first premium product and is incompatible with the new mission. The current decision: one editor codebase across all platforms, thin native shells. See `ARCHITECTURE.md`.

### DP-5: Simplicity is a feature
We do fewer things extraordinarily well. The default answer to "should we add X?" is no.

- Features require a clear connection to a pain point in §2 or a claim in the press release
- "Other apps have it" is not a justification
- Removing a feature that isn't working is a valid product decision
- Settings are minimal; opinionated defaults over configuration

### DP-6: No lock-in, ever
Standard markdown in, standard markdown out. We support CommonMark + GFM and do not extend it with proprietary syntax.

- We do not invent custom markdown syntax
- We do not inject front matter into files
- We do not create sidecar files
- We render widely-adopted extended syntax (Mermaid, math) beautifully without requiring it

### DP-7: AI is local-first, private, and BYO
AI is a core capability, not a bolted-on chatbot. Architecture:

- **Local AI** (default, included): on-device inference via llama.cpp / MLX / Core ML / ONNX depending on platform. Works offline. No account. No network. Covers: improve writing, summarize, continue writing, smart completions.
- **BYO-key AI** (optional power-user mode): the user pastes their own API key (OpenAI, Anthropic, Ollama, or any OpenAI-compatible endpoint) in settings. Requests go directly from their machine to their chosen provider. We never proxy, never see the content, never see the key beyond what's stored encrypted on-device. This is a single settings pane, not a product tier.
- AI never modifies the document without explicit user consent
- AI is integrated into the editing flow (selection actions, inline suggestions) — not a chat panel

**Decision [D-AI-1]** *(revised)*: Local-first AI architecture. BYO-key cloud is opt-in enhancement. **Decision [D-AI-2]** *(reversed from legacy)*: There is no paid Pro AI tier. The legacy $3.99/mo tier is replaced with BYO-key mode.

### DP-8: Graceful degradation
When things go wrong, the user should never lose work or feel confused.

- If AI model download fails, the editor works perfectly — AI features are absent
- If auto-save fails, the document stays in memory and the user is notified non-modally with retry
- If a cloud-drive file is evicted from local storage while open, we detect it and offer to re-download or save locally
- If a BYO-key request fails, we show the error inline and suggest retrying or using local AI
- Every error state is designed — not just coded

**Decision [D-ERR-1]**: No error state is undesigned. Every feature spec must include failure modes.

### DP-9: The Render — our signature interaction
When you toggle from source to rich view, the markdown doesn't swap — it *transforms*. Raw markdown characters gracefully animate into their rendered form: `#` markers shrink as the heading scales up, `**` markers dissolve as text boldfaces, list markers morph into styled bullets, code fences fade as the code block materializes. Target ~400ms, spring-animated.

This is the single most important "show someone" moment in the product.

**What this means in practice**:
- The transition is a designed animation, not a state swap
- It uses CodeMirror 6 decorations + CSS transitions / Web Animations API
- It has a Reduced Motion alternative (instant crossfade)
- It works on every platform

**Decision [D-UX-3]**: The Render is a named, protected design element.

**Honest caveat**: A webview-based animation will not match a native SwiftUI Core Animation pipeline on a 120Hz display. The gap is real. We will get it to 60fps solid and 120fps where possible. We are not claiming parity with a hypothetical SwiftUI implementation; we are claiming it is far better than anything else on Linux, Windows, Web, and Android — where no comparable competitor exists at all.

### DP-10: Accessible to everyone
Accessibility is P0, not P1.

- Full screen-reader support: VoiceOver (macOS/iOS), NVDA (Windows), Orca (Linux), TalkBack (Android)
- Dynamic Type / user font scaling
- Reduced Motion support
- WCAG AA contrast minimum
- All functionality reachable via keyboard
- No information conveyed by color alone

**Decision [D-A11Y-1]**: Every feature spec must include accessibility acceptance criteria. A feature that doesn't work with the platform screen reader doesn't ship.

### DP-11: Agent-built, human-directed
Easy Markdown is built by autonomous agents running grooming and sprint execution (`aishore`), with a human directing intent and reviewing output. This is a design principle because it shapes how work is planned, scoped, and reviewed — not just how code is written.

**What this means in practice**:
- Backlog items must carry explicit "commander's intent" fields so agents can resolve ambiguity without human intervention
- Every item has acceptance criteria concrete enough for an agent to verify
- Scope discipline is enforced by the process, not by human restraint mid-sprint
- Review is the human bottleneck, so review must be fast, focused, and frequent — not a batched end-of-sprint ritual

**Decision [D-PROC-1]**: The process itself is part of the product. Improving the agent loop (grooming quality, sprint success rate, review ergonomics) is first-class work, not meta-work.

---

## 5. Non-Goals and Boundaries

Explicit decisions about what we will **not** build.

| Non-goal | Why | Decision |
|----------|-----|----------|
| **Personal knowledge management** (graph views, backlinks-as-database, daily-note generators) | Obsidian owns this. Wikilinks that resolve to plain files are in scope (F-019); a second-brain database is not. | **[D-NO-1]** No PKM features beyond plain-file wikilinks. |
| **Note-taking database** (tags DB, search index as source of truth) | Requires a proprietary data layer, violating DP-1 and DP-6. | **[D-NO-2]** No database. Files are the source of truth. |
| **Real-time collaboration** | Requires server infrastructure and accounts. | **[D-NO-3]** No collaboration in v1. Personal tool only. |
| **Publishing pipelines** (CMS integration, static site generation) | We render, print, and share beautifully — we don't publish. | **[D-NO-4]** No publishing pipelines. |
| **Proprietary document formats** (Word, Pages, RTF import/export) | Markdown is the format. PDF/print is a rendered view, not a conversion. | **[D-NO-12]** No proprietary format conversion. |
| **General-purpose code editing** (multi-language LSP, terminal) | We are a markdown editor, not an IDE. | **[D-NO-5]** Markdown-first. |
| **Plugin/extension system** | Complexity multiplier. Breaks UX quality guarantee. Obsidian already won this. | **[D-NO-6]** No plugins. No extension API. |
| **Cloud sync built by us** | Users bring their own (iCloud, Dropbox, Google Drive, OneDrive, git). | **[D-NO-8]** No proprietary sync. |
| **User accounts** | The app works without any account. No sign-in, ever. | **[D-NO-9]** No account system. |
| **Paid features or tiers** | Free is the point. | **[D-NO-7]** *(reversed from legacy)*: No commercial model. |
| **Cloud AI relay or proxy** | BYO-key means direct user→provider. We never see keys or content. | **[D-NO-10]** No AI relay. No server-side AI. |
| **AI chat/conversational panel** | We're an editor with AI assistance, not a chatbot. AI is woven in, not bolted on. | **[D-NO-11]** No chat panel. |
| **Closed source or open-core** | Apache 2.0, whole stack. | **[D-NO-13]** *(reversed from legacy)*: Fully open source. |
| **Telemetry, analytics, phone-home** | Local-first means local-only. | **[D-NO-14]** No telemetry. |

---

## 6. Decision Log

Key decisions in one place. IDs with *(revised)* or *(reversed)* indicate changes from `PRODUCT_LEGACY.md`.

### Markdown
- **[D-MD-1]** CommonMark + GFM baseline. Extensions: frontmatter detection, math (`$`/`$$`), Mermaid fenced blocks. No proprietary syntax.
- **[D-MD-2]** Parser: tree-sitter-markdown (split_parser branch). Known CommonMark divergences documented; spec tests run in CI; fixes contributed upstream.

### Editor
- **[D-EDIT-1]** Auto-formatting + document doctor on by default.
- **[D-EDIT-2]** WYSIWYM via CodeMirror 6 decorations (HyperMD-style). Syntax characters hide when cursor is away, reveal on proximity.
- **[D-EDIT-3]** The Render is a protected design element (see DP-9).

### AI
- **[D-AI-1]** *(revised)* Local-first AI architecture. On-device inference via llama.cpp/MLX/Core ML/ONNX depending on platform.
- **[D-AI-2]** *(reversed)* No paid Pro tier. BYO-key mode replaces the legacy $3.99/mo subscription.
- **[D-AI-3]** AI never modifies the document without explicit consent. Inline suggestions, not chat.

### Platform
- **[D-PLAT-1]** *(revised)* All platforms are first-class. Ship order is driven by engineering cost (desktop before mobile because Tauri mobile is younger), not by market tier.
- **[D-PLAT-2]** *(reversed)* Tauri + CodeMirror 6. Single editor codebase across macOS, Linux, Windows, Web, iOS, Android.

### File handling
- **[D-FILE-1]** No vault, library, or proprietary file store.
- **[D-FILE-2]** Cloud-drive integration through OS file providers, not custom sync.
- **[D-FILE-3]** Line ending and encoding preservation on save.

### Business
- **[D-BIZ-1]** *(reversed)* The app is free. No commercial model. Apache 2.0.
- **[D-NO-13]** *(reversed)* Fully open source, not open-core.
- **[D-SUST-1]** Sustainability is maintained via agent-driven development (see DP-11). This is a bet; see §9.

### Performance
- **[D-PERF-1]** Formatting a 10k-line document: <50ms. Incremental reparse on keystroke: <1ms. Full diagnostic pass: <100ms. Perceived input latency: <5ms.

### Quality / process
- **[D-QA-1]** CommonMark spec suite runs in CI. Divergences tracked in an explicit skip-list.
- **[D-QA-2]** Accessibility is a blocking criterion (D-A11Y-1).
- **[D-PROC-1]** Agent loop quality (grooming, sprint success, review ergonomics) is first-class work.

---

## 7. Feature Specifications

**This section has two parts.** §7.1 is the **walking skeleton** — the smallest end-to-end version of Easy Markdown that proves the architecture actually works. Nothing else ships until the walking skeleton is real, running, and measured. §7.2 onward are **features** that decorate the skeleton and are gated on regression budgets set during §7.1.

If you are populating the backlog from this doc, read §7.1 carefully: the walking skeleton must be the first milestone, and feature items in §7.2+ must not be marked ready for sprint until the skeleton has landed and baseline metrics exist.

### 7.1 The Walking Skeleton (milestone M0)

The walking skeleton is the atomic loop. It is deliberately ugly, deliberately minimal, and deliberately *real* — no mocks, no stubs, no "we'll wire it up later." When it passes, we have proof that the Rust core, the CodeMirror 6 editor, the Tauri IPC bridge, and the OS file system all work together on at least one platform. Every feature after this is an increment on top of a running system.

#### 7.1.1 The primary user journey (M0)

```
1. User launches Easy Markdown          (Tauri shell runs, window opens)
2. User clicks "Open"                    (native file dialog)
3. User picks a .md file                 (Rust reads bytes from disk)
4. File contents appear in the editor    (bytes → IPC → CodeMirror 6)
5. User types a character                (keystroke → CodeMirror → IPC → Rust buffer)
6. Character appears on screen           (optimistic render in CodeMirror)
7. User presses ⌘S (or ctrl+S)           (save command → Rust writes bytes)
8. File on disk contains the edit        (verified by reopening the file)
9. User closes the window                (Tauri quits cleanly)
```

That is the entire M0 scope. If any of these nine steps cannot be demonstrated in a real running binary on at least one desktop platform, M0 is not done.

#### 7.1.2 What the walking skeleton MUST contain

Every item in this list is **real running code wired to real infrastructure**. Not mocked. Not stubbed. Not "behind a feature flag." Real.

- A Tauri 2.0 project that builds and runs on macOS producing a window
- A webview hosting a real CodeMirror 6 editor instance with a text buffer
- A Rust core crate (`em-core`) exposing at minimum: `open_file`, `edit`, `save_file`, `current_text`
- A real Tauri IPC bridge calling those four functions via `#[tauri::command]`
- Real file I/O through `std::fs` — no in-memory fake filesystem
- A native OS file dialog (Tauri's `dialog` plugin) for open and save
- Keyboard shortcut wiring for ⌘S / ctrl+S
- CI that builds the Tauri app on macOS (at minimum) and runs the skeleton's integration test

#### 7.1.3 What the walking skeleton MUST NOT contain

This list is load-bearing. Anything on it that sneaks into M0 is scope creep and the M0 item is wrong.

- **No piece table, no rope, no optimized document model.** Use a `String` in Rust. The v1 engine model decision is deferred until we have a measured baseline to compare against.
- **No formatting engine.** No list continuation, no table alignment, no heading spacing, no trailing whitespace trim, no auto-format on save.
- **No doctor / diagnostics.** No broken-link checking, no heading hierarchy validation, no anything.
- **No syntax highlighting.** Plain text in the editor. Raw markdown is fine — we are proving the loop, not the look.
- **No WYSIWYM decorations.** No hiding of `#` or `**`. Raw source only.
- **No "The Render" animation.** DP-9 is a Phase 1 feature, not M0.
- **No auto-save.** Only explicit save via ⌘S.
- **No file watching or conflict detection.** If the file changes under us, it changes — M0 does not handle it.
- **No themes.** One hardcoded light theme.
- **No tabs, no split view, no file tree sidebar, no recent files.** One window, one file at a time.
- **No AI.** Not local, not BYO-key, not anything.
- **No Linux, Windows, Web, iOS, Android shells.** macOS only for M0. (Linux follows immediately after in M0.1, but blocks on M0 passing.)
- **No cloud drive integration.** OS file dialog only.
- **No wikilinks, no Mermaid, no math, no images.** Text in, text out.

If any of these feel essential to have in M0, the answer is "no, they belong in a post-M0 feature item that can be measured against the M0 baseline."

#### 7.1.4 M0 acceptance criteria — real evals, not greps

Every M0 acceptance criterion must exercise the running system end to end. The only acceptable verify commands:

- `cargo test --workspace` passing integration tests that open, edit, and save real files on a real filesystem
- `tauri-driver` (Tauri's WebDriver bridge) or a headless smoke test that launches the app, scripts the nine-step journey, and asserts on observable state
- A shell script that opens the app, sends synthetic input, and compares on-disk file contents before and after

**Explicitly forbidden as M0 acceptance criteria:**

- `grep -q 'function_name' src/file.rs` — tests that code exists, not that it runs
- `test -f src/path/to/file.rs` — same
- Unit tests that mock the IPC bridge, the file system, or CodeMirror
- "Component X compiles" — compilation is a precondition, not a passing eval

The groomer and the sprint runner must reject any M0 item whose acceptance criteria do not execute the actual end-to-end behavior.

#### 7.1.5 Baseline performance gates (locked during M0, enforced forever)

When M0 passes, the skeleton runs a measurement pass and writes the results to `docs/baseline.json`. These become the regression budgets for every feature item that follows. A feature that regresses any baseline metric by more than 10% does not merge until the regression is understood, named, and accepted.

Metrics to capture (values are set *by measurement*, not by prediction):

- **Cold startup to editable**: time from `cargo tauri dev` binary launch to an editable cursor in the editor
- **Open a small file (100 lines)**: time from file-dialog-accept to text visible on screen
- **Open a medium file (10k lines)**: same, for a larger file
- **Keystroke to on-screen**: time from keyDown event to character visible in the editor
- **Save round-trip**: time from ⌘S press to file-on-disk contains the edit
- **Memory footprint editing a 10k-line file**: RSS after 1 minute of editing

**Canonical baseline environment**: the metrics are captured on a GitHub Actions `ubuntu-latest` runner. This is the only environment whose numbers are committed to `docs/baseline.json` and enforced by the CI regression gate. Local runs on any other machine are for exploration; they are not comparable and do not count.

Why GitHub Actions `ubuntu-latest`: free, reproducible, available to any contributor or agent, and slower than most development machines, which gives us headroom. Other options (a physical benchmark machine, macOS runners, pinned cloud VMs) are long-tail and can be revisited once we have evidence the default is insufficient.

**Measurement methodology**: each metric is captured by running N≥5 measurements and taking the median. The regression gate fires when the median of a PR's measurement run exceeds 110% of the committed baseline median. Single runs are not acceptable because CI runners have 10–15% inherent variance on cold-startup metrics, and a single-run gate produces random failures.

The machine metadata committed to `docs/baseline.json` must include: the runner OS image version, `uname -a` output, `/proc/cpuinfo` CPU model, and `free -m` memory. This metadata is reference-only — the gate compares against the committed medians, not against the metadata.

**Decision [D-M0-1]**: Until M0 passes with a committed `docs/baseline.json`, no §7.2+ feature item may be marked `readyForSprint: true`.

**Decision [D-M0-2]**: After M0 passes, every feature item's CI gate must include a re-measurement pass that compares against `docs/baseline.json`. Regressions >10% block the merge.

#### 7.1.6 The M0 backlog shape

When populating the backlog from this doc, M0 should decompose into roughly these items (exact IDs to be assigned by the groomer):

1. **M0-workspace**: Rust workspace + `em-core` crate with a `String`-backed document struct exposing `open_file`, `edit`, `save_file`, `current_text`. Integration test that round-trips a file through the four functions on disk. Explicitly no parser, no formatter.
2. **M0-tauri-shell**: Tauri 2.0 project scaffolded for macOS, producing a running window. Builds in CI. `em-core` wired as a Rust dependency.
3. **M0-bridge**: Four `#[tauri::command]` wrappers around the `em-core` functions. Integration test that calls each command from the webview side and verifies the result.
4. **M0-editor**: CodeMirror 6 mounted in the webview configured as a plain-text editor — explicitly **without** the `@codemirror/lang-markdown` extension and **without** any decorations or WYSIWYM behavior. This is not "markdown mode with decorations disabled" — it is plain text. Markdown syntax highlighting, `@codemirror/lang-markdown`, and WYSIWYM all come in post-M0 editor-polish items. Keystrokes update a local buffer. No IPC yet.
5. **M0-open-save-loop**: Wire the Open button, the Save shortcut, and the editor's keystrokes to the bridge. End-to-end test: launch app, open file, type, save, reopen file, assert new content.
6. **M0-baseline**: Capture the six baseline metrics from §7.1.5 on a documented reference machine. Commit `docs/baseline.json`. Add a CI job that fails if any subsequent commit regresses a metric by >10%.

M0 is done when all six items above pass their real evals and `docs/baseline.json` is committed.

### 7.2 Features (populated post-M0)

The §7.2 feature items are **deliberately not yet listed with IDs**. They will be generated into the backlog by running `.aishore/aishore backlog populate` (or `.aishore/aishore refine` + `populate`) after FEAT-006 lands and `docs/baseline.json` exists. IDs will be assigned at that time, continuing the `FEAT-NNN` sequence from the M0 items. No feature uses a legacy `F-NNN` identifier.

This is a deliberate reset. The pre-pivot version of this doc carried ~30 feature IDs (`F-001` through `F-037`) that did not map cleanly to the Rust + CodeMirror 6 + Tauri architecture. Carrying them forward would create confusion between the M0 `FEAT-001..FEAT-010` backlog and the `F-NNN` legacy list. Better to start clean.

Until that populate runs, the authoritative list of *scopes* (not items) that must exist in the post-M0 backlog is below. The groomer reads this when generating the next batch. **Every scope below is subordinate to D-M0-1 and D-M0-2 and must measure against `docs/baseline.json`.**

**Post-M0 Phase 0 foundations** (already in the backlog as FEAT-007..FEAT-010):

- Tree-sitter-markdown parser + AST types
- Document-model engine decision + implementation (see ARCHITECTURE.md §Document Model — candidates A/B/C)
- Formatting engine with first rules
- Doctor engine with first rules
- CommonMark spec suite in CI with skip-list for known tree-sitter divergences

**Phase 1 — Editor polish** (must ship before the first public pre-release):

- Native file open, create, and save with OS file dialogs (extends M0 open-save-loop with recent files, multiple-document handling, untitled-buffer workflow)
- `@codemirror/lang-markdown` + syntax highlighting (the full markdown extension, after the M0 plain-text baseline)
- WYSIWYM decorations — syntax characters fade when cursor leaves the node, reveal on proximity (HyperMD-style)
- The Render (DP-9) — source-to-rich toggle animation at 60fps+ on every shell
- Dark and light theme with system follow
- Typography and font handling (designed, not system default)
- Keyboard shortcuts (platform-idiomatic — ⌘ on macOS, ctrl elsewhere)
- Find and replace in current document
- Word count and document stats
- Spell check via OS APIs

**Phase 2 — Second shells and file scale**:

- Linux Tauri shell with WebKitGTK, `.desktop` + AppStream, Flatpak manifest
- Windows Tauri shell with WebView2, MSI + WinGet
- Web / PWA shell with File System Access API
- Auto-save with content-hash skip
- External file change detection and conflict resolution
- Large-file handling (informed by the post-M0 document-model decision)
- First public pre-release

**Phase 3 — AI**:

- Local AI (llama.cpp / MLX / ONNX depending on platform). First actions: improve, summarize, continue writing
- BYO-key mode — settings pane to paste an OpenAI / Anthropic / Ollama / OpenAI-compatible endpoint key; all requests go directly from the user's machine to their chosen provider; key stored in OS keychain
- Voice-intent command input (platform speech APIs)
- Smart completions (local, inline)

**Phase 4 — Mobile**:

- iOS Tauri mobile shell
- Android Tauri mobile shell

**Phase 5 — Expansion**:

- Wikilinks and on-demand backlinks against plain files (not a vault)
- Extended doctor rules (passive voice, orphaned sections, inconsistent list markers)
- Mermaid diagram rendering and AI-assisted Mermaid editing
- Math rendering (KaTeX)
- Folding and outline view
- Multi-document tabs and split view
- Quick Open (fuzzy file search across the current folder tree)
- Image handling (inline rendering, drag-drop, paste)
- Render, print, and share as polished PDF
- Custom themes and fonts

This is a list of *scopes*, not commitments to ship order within each phase. The groomer will decompose each scope into concrete `FEAT-NNN` items during the post-M0 populate, with real acceptance criteria that measure against `docs/baseline.json`.

---

## 8. Roadmap

Seven phases, starting with M0 (the walking skeleton). Timelines are soft — agent-driven sprints run continuously, so "phase" is about what's unlocked, not a calendar promise. Ordering is not soft: every phase gates on the previous one being real, running, and measured against `docs/baseline.json`.

| Phase | Unlocks |
|-------|---------|
| **M0 — Walking skeleton** | Running Tauri app on macOS that opens a file, edits it, saves it, reopens it. `String`-backed `em-core`. Baseline metrics committed to `docs/baseline.json` and enforced by the CI regression gate. See §7.1 for the full spec. |
| **Phase 0 — Post-M0 foundations** | tree-sitter-markdown parser + AST, document-model engine decision (measured against baseline), formatting engine first rules, doctor engine first rules, CommonMark spec suite in CI |
| **Phase 1 — Editor polish** | `@codemirror/lang-markdown`, WYSIWYM decorations, The Render transition, themes, typography, keyboard shortcuts, find/replace, word count, spell check |
| **Phase 2 — Second shells + file scale** | Linux (WebKitGTK), Windows (WebView2), Web (PWA). Auto-save, file watching, conflict detection. First public pre-release |
| **Phase 3 — AI** | Local AI (llama.cpp/MLX/ONNX), BYO-key cloud AI, voice intent, smart completions |
| **Phase 4 — Mobile** | iOS + Android via Tauri mobile |
| **Phase 5 — Expansion** | Wikilinks/backlinks against plain files, extended doctor, Mermaid, math, folding, multi-doc tabs, images, PDF export, custom themes |

**Decision [D-ROAD-1]**: Desktop before mobile. Not because mobile is less important (the primary persona lives on mobile) but because Tauri mobile is younger and higher-risk. Ship something solid on desktop first so mobile has a tested core to wrap.

**Decision [D-ROAD-2]**: M0 blocks everything. Until the walking skeleton runs end-to-end and `docs/baseline.json` is committed, no Phase 0+ item can be marked `readyForSprint: true`. See `D-M0-1`.

---

## 9. Honest Risks

The critiques that would come from a reviewer who doesn't buy the pitch. Kept here so we don't flinch from them.

- **The sustainability bet may fail.** Agent-driven development does not eliminate the human bottleneck — it moves it to review and direction. If the human at the helm runs out of time or interest, Easy Markdown joins the MarkText graveyard. The bet is that "review and steer" is a lower-energy activity than "write every line," not that it is zero-energy. We do not know how long this lasts.
- **Webview animations won't match native.** DP-9 (The Render) is a signature interaction. A CodeMirror 6 + CSS animation pipeline cannot match SwiftUI Core Animation on a 120Hz ProMotion display. The gap is small but real. On every *other* platform, there is no comparable competitor at all — Linux, Windows, Web, Android have no native 120fps markdown editor for us to lose to.
- **Tauri mobile is young.** Tauri 2.0 mobile support (iOS and Android) is behind its desktop support. Phase 4 carries real platform-risk.
- **WebKitGTK lags.** Linux shells use WebKitGTK, which is 6–12 months behind Chromium on CSS and Web APIs. We will hit rendering quirks. The alternative (bundling Chromium/CEF) costs ~100MB per install and defeats the lightweight goal.
- **tree-sitter-markdown is not 100% CommonMark compliant.** Known divergences in lazy continuation lines and some nested link references. We run the spec suite in CI, ship an explicit skip-list, and upstream fixes. Users who hit an edge case will notice.
- **No PKM may cost us users.** Wikilinks-as-plain-files (F-019) is not a full second-brain replacement. Some Obsidian users will bounce when they discover there's no graph view. This is deliberate ([D-NO-1]) and we accept the cost.
- **Local AI quality ceiling.** On-device quantized models are meaningfully weaker than frontier cloud models. Power users who need frontier quality will use BYO-key; users without an API key will see a quality floor we do not control.
- **"Free forever" is easy to say, hard to prove.** The legacy argument — that free editors can't sustain themselves — is still on the table. We are betting agents break the pattern. If they don't, we fail honestly.

---

## 10. Competitive Landscape

As of 2026:

| Competitor | What they have | What they lack | Our angle |
|-----------|----------------|----------------|-----------|
| **Obsidian** | Great UX, local files (sort of), huge plugin ecosystem | Vault lock-in, Electron, paid sync, paid publish, closed source | Same craft, no vault, no subscriptions, open source, every platform |
| **iA Writer** | Beautiful typography, open files | Apple-only, $50, no AI, no cross-platform | Same craft, every platform, free, AI-native |
| **Typora** | Live preview, open files | Desktop-only, closed source, paid, no AI | Every platform, free, open source, AI-native |
| **Bear** | Beautiful iOS/macOS UX | Apple-only, proprietary storage, subscription | Every platform, open files, free |
| **Ulysses** | Writer-focused | Apple-only, subscription, proprietary library | Every platform, open files, free |
| **Notion** | Rich blocks, collab | Not markdown, cloud-only, accounts | Actually markdown, local-first |
| **VS Code** | Ubiquitous, open source, free | Code editor, not a prose experience | Prose-first, not an IDE |
| **MarkText** | Free, open source, WYSIWYM | Deprecated 2025 (maintainer burnout) | Same category, different sustainability model |
| **TextEdit / Notes** | Installed on your Mac | Not markdown, no rendering, no AI | Purpose-built for `.md` |

---

## 11. Success Metrics

No revenue metrics. Success for a free, open-source editor looks different.

**Year 1 (post-v1.0)**:
- Ships on Homebrew, Flatpak, Snap, Microsoft Store, and as a PWA
- macOS, Linux, Windows, and Web shells stable enough to use daily
- 10k GitHub stars, 1k active users (self-reported, no telemetry)
- At least one major Linux distribution packages it
- CommonMark spec suite >98% green

**Year 2**:
- iOS and Android shells stable
- Included in at least one default desktop environment image
- Recognized in at least one "tools we recommend" list from a major publication or OSS project
- First external contributor merges (human or agent)
- The primary persona (AI-Native Knowledge Worker) describes Easy Markdown as "the one I use" without qualification

**Year 3**:
- When someone asks "what's a good free markdown editor on Linux/Windows/Web," the answer is Easy Markdown
- Easy Markdown is the default way knowledge workers open AI-generated `.md` files
- The sustainability experiment (DP-11, D-SUST-1) is either demonstrably working or demonstrably failed — we have data either way

**Anti-metrics** (things we explicitly do not optimize for):
- MAU/DAU (no telemetry)
- Retention (no accounts)
- Conversion (no paid tier)
- Engagement time (we want people to get their work done and leave)

---

## Appendix A: Decisions that were reversed from PRODUCT_LEGACY.md

For traceability. If you find legacy behavior in the codebase or backlog, check this list first.

| ID | Legacy position | New position | Reason |
|----|-----------------|--------------|--------|
| D-PLAT-1 | iOS first, then macOS, then Linux | All platforms first-class; desktop before mobile only due to Tauri mobile maturity | Mission changed from "premium Apple product" to "best free on every platform" |
| D-PLAT-2 | Native UI only (SwiftUI); no Electron/RN/Flutter/Tauri | Tauri + CodeMirror 6 | Cross-platform day one is incompatible with per-platform native UI |
| D-BIZ-1 | $9.99 one-time purchase | Free forever, Apache 2.0 | Mission is free software |
| D-AI-2 | Pro AI $3.99/mo subscription | BYO-key mode | No paid tier |
| D-NO-7 | Paid only | Free only | — |
| D-NO-13 | "We are not open source" | Apache 2.0, fully open source | Mission is free software |
| Why Now #6 | "Free editors can't sustain themselves, so we charge" | "Agents break the volunteer-burnout pattern, so we don't need to charge" | New sustainability thesis (see DP-11, §9) |

Sections of the legacy doc that were stripped entirely: §11 Business Model, §12 Growth Strategy, pricing messaging in §1 and §4, the tertiary persona footnote wishing open-source users well.
