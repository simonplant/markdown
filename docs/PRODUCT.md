# Markdown — Product

The single source of truth for *what* we are building, *who* it serves, and *what bar* it must clear. This document does not describe *how* it is built. That lives in `ARCHITECTURE.md`.

---

## Document scope

This document owns:

- What the product is and what it does
- Who it serves and what problems it solves
- What we refuse to build
- The user-facing quality bar
- The business model and licensing
- The sustainability bet (summary) and its risks
- The roadmap as user-visible outcomes

This document does **not** own:

- Framework, language, or library choices
- Internal module boundaries or engineering budgets
- Test infrastructure or build pipelines
- Measurement methodology or engineering protocols

When an edit to this document would name a specific technology, framework, library, file path, API, or millisecond budget, the edit belongs in `ARCHITECTURE.md`. If a product decision *implies* an architecture constraint, state the user-visible contract here and let `ARCHITECTURE.md` derive the implementation from it.

**Decision IDs**: product decisions use `D-*` identifiers. Architecture decisions use `A-*` identifiers and live in `ARCHITECTURE.md`. Cross-document references use the full ID.

---

## 1. Press Release

This is the Amazon "working backwards" press release. It describes the product as if it has already shipped. Every decision in this document should be traceable back to making this press release true.

> **FOR IMMEDIATE RELEASE**
>
> ### Markdown: the best way to open AI-generated `.md` files.
>
> *Free, open source, runs everywhere. No vault. No account. No subscription. Apache 2.0, forever.*
>
> **Every AI writes markdown.** LLMs, agents, copilots — they all output `.md`. Research reports, product briefs, architecture docs, meeting summaries, READMEs, prompts. The volume of AI-generated markdown in the world grew by orders of magnitude in two years, and the tools for reading it haven't caught up.
>
> **Today you open an AI-generated `.md` file and get one of three bad options.** You stare at raw markdown syntax in a text editor. You paste it into Obsidian and watch it create a vault you didn't ask for. You open it in VS Code, which was built for code, not prose. For a document format that is becoming as universal as plain text, the state of tooling is absurd.
>
> **Markdown fixes this.** Open any `.md` file from anywhere your OS can reach — a local folder, iCloud Drive, Dropbox, Google Drive, OneDrive, a git repo — and see it rendered beautifully. Tables, diagrams, code blocks, math, all inline. No import step. No vault. No sidecar files. Click to edit and you're in a polished author environment with live formatting and a document doctor catching issues as you work. Click back to read. Runs on macOS, Linux, Windows, Web, iOS, and Android.
>
> **AI assistance comes later, and comes right.** The AI tooling landscape is still settling. Rather than bolt on whichever model is loudest this quarter, we ship the reading and writing experience first — fast, polished, on every platform — and integrate AI once the ecosystem has shaken out. When it ships, it will be local-first, private, and user-controlled. No account. No relay. No paid tier.
>
> **A markdown editor should be a commodity.** It is infrastructure for knowledge work in the AI age — as essential as a web browser. It should be free, open source, and run on everything. That is what Markdown is. Apache 2.0, the whole stack, forever.
>
> Download. Open a file. Read. Write.

### What the press release locks in

| Claim | User-visible contract | Decision |
|-------|----------------------|----------|
| "The best way to open AI-generated `.md` files" | The primary job-to-be-done is consuming markdown, not authoring it. Read mode is the default; author mode is one click away. | D-MKT-1, D-UX-1 |
| "Free, open source, runs everywhere" | Free forever. No paid tier. No premium features. Apache 2.0, whole stack. | D-BIZ-1 |
| "Every AI writes markdown" | The product rides a secular trend; we don't need to create a category. | Positioning |
| "Open any `.md` file from anywhere your OS can reach" | File access through OS-level APIs only. No proprietary sync, no vault, no library. | D-FILE-1 |
| "No vault. No account. No sidecar files." | Zero-configuration first launch. Nothing proprietary touches the user's filesystem. | D-FILE-1, D-NO-9 |
| "See it rendered beautifully" | Rich content (tables, diagrams, code blocks, math) renders inline on open. No manual toggle to "preview mode." | D-UX-1, DP-3 |
| "Click to edit" | Author mode is a single gesture. Polished. Not a separate app. | D-UX-1 |
| "Runs on macOS, Linux, Windows, Web, iOS, Android" | Every platform first-class. iOS and macOS lead the ship order and set the native-feel bar; the rest follow. | D-PLAT-1 |
| "AI assistance comes later, and comes right" | No AI in the initial product. When it ships (after v1.0), local-first, private, no account, no relay, no paid tier. | D-AI-1, D-AI-2, D-ROAD-3 |
| "A markdown editor should be a commodity" | Apache 2.0, whole stack. Not open-core. Not source-available. Sustainability via community contributions (see §6). | D-BIZ-1, D-SUST-1 |

### Why now

The demand side and the supply side both changed. This product was not possible — or necessary — three years ago.

**Demand: AI-generated markdown became a consumption problem.**

1. **AI made markdown the default document format.** LLMs don't output LaTeX, DOCX, or HTML. They output markdown. Every research report, product brief, architecture doc, and meeting summary that an AI writes is a `.md` file. The volume of markdown in the world grew by orders of magnitude in two years.
2. **The consumption side is underserved.** Tools for *authoring* markdown are plentiful. Tools for *reading* AI-generated markdown — with its diagrams, tables, math, and code blocks — are either locked to an ecosystem (Obsidian), locked to a platform (iA Writer, Typora), or not really for prose at all (VS Code). The commodity tool doesn't exist.
3. **Obsidian proved the market and drew a line.** Millions of people want a markdown editor with craft and local files. Obsidian proved that. It also showed the limits: a proprietary vault, paid sync, paid publish, closed source, a plugin ecosystem that makes users afraid to leave. The opportunity is everything Obsidian is minus everything Obsidian takes.

**Supply: the cost of building a great cross-platform editor collapsed.**

4. **Cross-platform text editing got solved.** A decade of cross-platform editor attempts produced mostly Apple-only products. The hard multi-year problems — CJK, RTL, IME, accessibility — have tractable solutions today. The infrastructure is free.
5. **Cross-platform shells got cheap.** What used to cost a quarter per platform now costs a few hundred lines of glue code.
6. **AI coding agents decoupled OSS maintenance from human energy.** Every standalone free markdown editor died because one human ran out of energy: MarkText (54K stars, deprecated 2025), Remarkable, Haroopad, Abricotine — 100% mortality. AI coding agents don't burn out. When a project is agent-legible — clear intent documents, machine-verifiable acceptance criteria, good test suites — agents can land useful work against it. The cost of building collapsed; the cost of *maintaining* collapsed with it. See §6 for the sustainability model and §10 for the honest risks.

---

## 2. Problem Statement

### The market landscape

Markdown became universal infrastructure. The tools for it didn't.

| | Great UX | Mediocre UX |
|---|---|---|
| **Locked storage / vault** | Obsidian, Bear, Notion, Ulysses | Day One, Standard Notes |
| **Open files, cross-platform** | *empty — this is us* | VS Code (not an editor for prose), text editors, TextEdit, Notes |
| **Open files, Apple-only** | iA Writer ($50), Typora (desktop) | — |

Markdown occupies the empty cell: **great UX + open files + cross-platform + free**. No product in the market holds this position. It is the commodity tool that should exist for a commodity format.

**Decision [D-MKT-1]**: The primary job-to-be-done is **opening and reading AI-generated `.md` files** on any platform, with zero configuration, rendered beautifully. Authoring is an important secondary capability but is not the pitch. This framing matters because the competitive landscape looks different: tools for authoring markdown are plentiful; tools for consuming it are not.

**Decision [D-MKT-2]**: Markdown is the document format for most knowledge work in the AI age. The primary workflow — *open a file, read it, edit if needed, share* — is first-class. Rich content (tables, diagrams, code blocks, math) renders beautifully inline by default.

### Pain points we solve

| # | Pain point | Our response | Decision |
|---|-----------|--------------|----------|
| P1 | **AI output is hard to consume.** AI agents emit `.md` files with diagrams, tables, code blocks, and math. Most tools show raw markdown or a mediocre preview. Users want to read the output as a document, not decode it. | Read mode is the default for opening a file. Rich content renders beautifully inline on open. | **[D-UX-1]** Read mode first. |
| P2 | **Ecosystem lock-in.** Obsidian requires a vault structure and builds an ecosystem (plugins, sync, publish) that makes leaving expensive — not because your files are trapped, but because your workflows are. Users invest in workflows they can't take elsewhere. | Use only OS-level file access. Never create a proprietary container or ecosystem dependency. | **[D-FILE-1]** No vault, library, or proprietary file store. Ever. |
| P3 | **Platform fragmentation.** The best-crafted markdown editors are Apple-only. Typora is desktop-only. 1Writer is iOS-only. There is no single tool that works well everywhere a user's files live. | Ship on every platform the user's files live on, with a native-grade experience on each. | **[D-PLAT-1]** All platforms are first-class. iOS and macOS lead and set the quality bar; the rest follow. |
| P4 | **Paywalls for basic features.** Obsidian charges $10/mo for sync that git does free, and $20/mo for publish that any static host does free. iA Writer is $50. Bear and Ulysses are subscriptions. | Free forever. Apache 2.0. No Pro tier. No sync subscription. No publish subscription. | **[D-BIZ-1]** The app is free. There is no commercial upgrade path. |
| P5 | **Formatting friction when you do edit.** Most editors are dumb text boxes. Users manually fix indentation, align tables, chase broken links. | Auto-formatting engine + document doctor as core features in author mode. | **[D-EDIT-1]** Intelligent editing is built-in and on by default in author mode. |
| P6 | **Bloat and complexity.** Obsidian's plugin system is powerful but overwhelming. Notion is a kitchen sink. | Focused feature set. No user-installable extensions. | **[D-NO-7]** No third-party extension ecosystem. |
| P7 | **AI features tie you to vendors and force subscriptions.** Notion AI, Craft AI, and every other AI writing tool sends your content to remote servers, requires an account, and charges a separate subscription — while the underlying models churn every six months. | AI is deferred until the landscape stabilizes. When it does ship, it will be local-first by default with optional user-provided API keys. No account, no relay, no paid tier. | **[D-AI-1]**, **[D-ROAD-3]** |
| P8 | **No purpose-built tool for non-IDE users.** Developers use Cursor/VS Code but have no great standalone tool for prose. Writers have no tool that combines open files + great UX + every platform. | Be the app developers open alongside their IDE, and the app writers open instead of one. | **[D-MKT-3]** Position as the complement to IDEs, not a competitor. |
| P9 | **Free markdown editors die.** MarkText, Remarkable, Haroopad, Abricotine. Volunteer maintainers burn out. | Agent-driven development with community contributions. The project provides architecture, intent, and review; contributors bring their own AI agent subscriptions. See §6 and `CONTRIBUTING.md`. | **[D-SUST-1]** We are running the experiment. |

---

## 3. Target Users

### Primary persona: The AI-Native Knowledge Worker

> *"Half my documents start as AI output — research reports, meeting summaries, first drafts. I need to read them, often tweak them, and move on. I shouldn't have to create a vault, pay a subscription, or be locked to one platform for that."*

- **Receives `.md` files from AI agents** (Claude, ChatGPT, Perplexity, Cursor, custom agents) and needs to read them as documents, not decode raw syntax. This is the primary job-to-be-done.
- Creates documents with AI as co-author: product briefs, reports, proposals, blog posts
- Refines content: tightens prose, fixes structure, adjusts tone
- Shares polished output: PDF export, `.md` share, print
- Needs rich content (tables, diagrams, code blocks) to render beautifully on open
- **Platforms**: mixes desktop and mobile; cross-platform matters
- **Scale**: tens of millions of knowledge workers who consume markdown daily

**Decision [D-USER-1]**: This is our primary user. When trade-offs arise, optimize for them. The read-first workflow is shaped around this persona.

### Secondary persona: The Builder

> *"I'm a product manager, engineer, or technical writer. I write PRDs, architecture docs, API docs, READMEs. AI co-authors everything. I want an editor that understands my content and helps me make it better — without being an IDE."*

- Product managers, engineers, technical writers
- AI is a co-author on everything
- Spends real time in author mode, not just read mode
- Rich content matters: diagrams, tables, code examples
- Cares where files live — git repos, iCloud, Dropbox, local folders
- Loudest referral channel — builders recommend tools to each other

**Decision [D-USER-2]**: Deep investment. Keyboard shortcuts, fast file switching, rich content rendering (code blocks, tables, diagrams) that respects the technical content these users write. We will not add Vim bindings, terminal integration, or git integration — Markdown is not an IDE.

### Tertiary persona: The Content Creator

> *"I'm a blogger, devrel person, or docs team member. Markdown is my source format. AI helps me draft, I refine, I publish."*

- Bloggers, developer relations, documentation teams
- Markdown is the source format for their publishing pipeline (Hugo, Jekyll, Docusaurus)
- Values typography and rendering — their content needs to look good in the editor too

**Decision [D-USER-3]**: Served naturally by the open-file model. We will not build publishing pipelines (D-NO-4).

### Who we explicitly do not serve

- **PKM enthusiasts building a second brain** → Obsidian owns this. We do not build graph views or daily-note generators. Wikilinks and backlinks against plain files are in scope because they work without a database — vaults are not.
- **Developers who want a code editor** → VS Code and Cursor own this.
- **Teams who need real-time collaboration** → Notion and Google Docs own this. Requires server infrastructure and accounts.
- **Academics who need citation management** → Zettlr owns this.

### Scale consideration

**Decision [D-USER-4]**: Global from day one. The product must work excellently for non-English writing (CJK, RTL, accented characters, emoji). Correct text rendering and input handling are Phase 1 requirements; UI localization is Phase 2.

---

## 4. Non-Goals and Boundaries

Explicit decisions about what we will **not** build. These constrain the product scope and are load-bearing — violating any of them requires reopening the decision, not quietly adding the feature.

| Non-goal | Why | Decision |
|----------|-----|----------|
| **Personal knowledge management** (graph views, backlinks-as-database, daily-note generators) | Obsidian owns this. Wikilinks that resolve to plain files are in scope; a second-brain database is not. | **[D-NO-1]** No PKM features beyond plain-file wikilinks. |
| **Note-taking database** (tags DB, search index as source of truth) | Requires a proprietary data layer, violating DP-1 and DP-7. | **[D-NO-2]** No database. Files are the source of truth. |
| **Real-time collaboration** | Requires server infrastructure and accounts. | **[D-NO-3]** No collaboration in v1. Personal tool only. |
| **Publishing pipelines** (CMS integration, static site generation) | We render, print, and share beautifully — we don't publish. | **[D-NO-4]** No publishing pipelines. |
| **Proprietary document formats** (Word, Pages, RTF import/export) | Markdown is the format. PDF/print is a rendered view, not a conversion. | **[D-NO-5]** No proprietary format conversion. |
| **General-purpose code editing** (multi-language LSP, terminal) | We are a markdown editor, not an IDE. | **[D-NO-6]** Markdown-first. |
| **User-installable third-party extensions** | Complexity multiplier. Breaks the UX quality guarantee. Obsidian already won this. Features ship first-party or not at all. | **[D-NO-7]** No third-party extension ecosystem. |
| **Cloud sync built by us** | Users bring their own (iCloud, Dropbox, Google Drive, OneDrive, git). | **[D-NO-8]** No proprietary sync. |
| **User accounts** | The app works without any account. No sign-in, ever. | **[D-NO-9]** No account system. |
| **Paid features or tiers** | Free is the point. | **[D-NO-10]** No commercial model. |
| **Cloud AI relay or proxy** | User-key means direct user→provider. We never see keys or content. | **[D-NO-11]** No AI relay. No server-side AI. |
| **AI chat/conversational panel** | We're an editor with AI assistance, not a chatbot. AI is woven in, not bolted on. | **[D-NO-12]** No chat panel. |
| **Closed source or open-core** | Apache 2.0, whole stack. | **[D-NO-13]** Fully open source. |
| **Telemetry, analytics, phone-home** | Local-first means local-only. | **[D-NO-14]** No telemetry. |

---

## 5. Roadmap

Phases are defined by what users can *do* at the end of each phase, not by which internal components have landed. Implementation phases, engineering milestones, and the walking-skeleton discipline live in `ARCHITECTURE.md`. Phase ordering here is not soft — each phase gates on the previous phase being real, running, and measured against the committed baseline.

| Phase | What users can do |
|-------|-------------------|
| **Foundation** | The core loop — open a `.md` file, read it, edit it, save it — is proven end-to-end against a measured performance baseline. |
| **iOS & macOS (lead)** | On iPhone, iPad, and Mac: open a `.md` file from a local folder or cloud drive, see it rendered beautifully in read mode with tables, code blocks, and rich typography, and tap or click into a native-feeling author mode with live formatting, document doctor, WYSIWYM, find/replace, word count, and spell check. Light/dark themes. |
| **Web, Windows & Linux** | The same read-and-write experience in the browser and on Windows and Linux — installable, offline-capable, with auto-save, external file change detection, and conflict resolution. First public pre-release. |
| **Stabilization and v1.0** | Rich content expansion: Mermaid diagrams, math rendering, images inline, wikilinks against plain files, extended doctor rules, PDF export, custom themes. Performance and stability hardening across every platform. v1.0. |
| **AI (deferred)** | Local AI for improve, summarize, continue, smart completions — no account, no network. User-key mode for frontier models. **Gated on the AI tooling ecosystem stabilizing enough to identify durable winners.** Shipping AI before that point means betting on vendors and approaches that may not exist in 18 months. |

**Decision [D-ROAD-1]**: iOS and macOS lead. iOS is the primary day-to-day platform and the one most sensitive to native feel, so the Apple build sets the quality bar the others are held to. The web build follows and brings Windows and Linux with it.

**Decision [D-ROAD-2]**: Every phase gates on the previous phase having shipped *and* having its performance measured against a committed baseline. The engineering discipline behind this is documented in `ARCHITECTURE.md`. Phase throughput is bounded by reviewer capacity, not agent throughput — the roadmap is aspirational, not a schedule, and phases complete when they complete. See §10 for the review-bottleneck risk.

**Decision [D-ROAD-3]**: AI ships after v1.0, not before. The AI tooling landscape is evolving too fast to build durable integrations against. The discipline is: ship a world-class reading and writing experience on every platform first, let the AI ecosystem shake out, and integrate with winners once they're identifiable. "Free, universal, polished markdown editor" is a complete product without AI; AI is additive, not foundational.

**Decision [D-ROAD-4]**: If the sustainability experiment produces 3x rather than 10x force multiplication, the roadmap contracts to the reduced-ambition scope defined in D-SUST-2. Mobile and AI do not ship in that scenario.

---

## 6. Sustainability Model (summary)

This section is a summary. The full operational model — how contributions are scoped, how agent-legibility is maintained, how review works, why contributors show up — lives in `CONTRIBUTING.md`.

**The bet in one paragraph**: The project's cost structure is inverted from traditional OSS. The project itself has near-zero operating costs. Contributors run their own AI coding agent subscriptions against well-scoped issues in an agent-legible codebase. The project provides the architecture, the intent documents, the test suites, and the review. Contributor motivation is grounded in the subscription economics: agent subscriptions are priced with usage headroom, much of which sits idle; directing that spare capacity at a well-scoped issue in a daily-driver tool costs less cognitive load and time than any equivalent way to scratch the itch. No donations, no corporate sponsorship, no open-core bait-and-switch, no maintainer martyrdom.

**Decision [D-SUST-1]**: Sustainability via agent-driven development with community contributions. The project provides architecture, intent, and review; contributors bring their own AI agent subscriptions. This is a bet on a new model, not a proven pattern. See §10 for the honest risks.

**Reduced-ambition fallback**: If the sustainability experiment produces 3x rather than 10x force multiplication, the reduced-ambition scope is: iOS and macOS — the native Apple build, with the web build as the cross-platform reach — and the core loop (open, read, edit, format, doctor, save) done to craft quality. No Android, no Mermaid/math/PDF, no AI. That is still a product no one else ships.

**Decision [D-SUST-2]**: Reduced-ambition fallback defined. See §10 for the risk analysis and `CONTRIBUTING.md` for the operational model that determines which scenario we're in.

---

## 7. Design Principles

Reference material. Resolve ambiguity when the roadmap, non-goals, and decision log don't have a clear answer. Every principle is stated as a user-visible contract. New readers can skip this section on first pass and return to it when an edge case surfaces.

### DP-1: Open by default
The user's filesystem is the storage layer. Files are opened and saved through OS file pickers. There is no vault, no library, no proprietary container. If the user uninstalls Markdown, their files are untouched.

- No app-specific directory structure
- No sidecar files, no hidden metadata folders
- No proprietary index or database visible to the user
- Cloud-drive files (iCloud, Dropbox, Google Drive, OneDrive) are accessed through OS file providers — the user's existing sync is the sync

### DP-2: The experience is the moat
The UX — not just the UI — is the primary differentiator. What people can't go back from is the *experience*: opening a file and seeing it rendered beautifully in under a second, moving between read and author mode without friction, lists auto-continuing on Enter, tables aligning as you type, the doctor catching broken links without being asked, work saved before you think to save it, state restored exactly where you left off.

Our retention model is **experiential lock-in, not organizational lock-in**. You don't come back because your data is trapped; you come back because nothing else feels this good.

**Decision [D-UI-1]**: No feature ships unless the flow, latency, defaults, and error states have been explicitly designed and polished.

### DP-3: Read first, edit second
Opening a file means seeing the document, not its source. A reader who never edits gets a great experience without ever touching an edit affordance. A writer gets a single click or tap into author mode.

**Decision [D-UX-1]**: Read mode is the default view when a file is opened. Author mode is one gesture away.

### DP-4: Native where it counts
Each platform gets an editing experience built to its own highest standard, not the same surface painted everywhere. On the platforms where users are most sensitive to it, that means a genuinely native editor that feels indistinguishable from the best apps on the device — native text selection, keyboard, and gestures. Elsewhere it means a polished, browser-grade editor. Every build respects its platform's conventions for menus, keyboard shortcuts, file pickers, window management, system integration, and default typography.

- macOS: standard menu bar, ⌘-shortcuts, Services menu, Spotlight, Quick Look
- Linux: GTK file dialogs, XDG desktop integration, `.desktop` + AppStream metadata
- Windows: platform-idiomatic menu patterns, Explorer integration
- iOS: platform sheets, swipe gestures, Files app integration, share sheet
- Android: Material patterns, Storage Access Framework, intent filters
- Web: PWA, File System Access API where available

### DP-5: The editor should be smart (in author mode)
Auto-formatting and the document doctor are core to the author-mode value proposition, not secondary.

- Auto-formatting runs inline, in real time, as the user types
- Document doctor runs in the background and surfaces suggestions non-intrusively
- Both are on by default; individual rules can be disabled
- AI assistance, when it eventually ships (see DP-8 and D-ROAD-3), joins this set as a third core capability

### DP-6: Simplicity is a feature
We do fewer things extraordinarily well. The default answer to "should we add X?" is no.

- Features require a clear connection to a pain point in §2 or a claim in the press release
- "Other apps have it" is not a justification
- Removing a feature that isn't working is a valid product decision
- Settings are minimal; opinionated defaults over configuration

### DP-7: No lock-in, ever
Standard markdown in, standard markdown out. We support CommonMark + GFM and do not extend it with proprietary syntax.

- We do not invent custom markdown syntax
- We do not inject front matter into files
- We do not create sidecar files
- We render widely-adopted extended syntax (Mermaid, math) beautifully without requiring it

### DP-8: AI is deferred — and will be local-first when it ships
AI does not ship in the initial product (see D-ROAD-3). The AI tooling landscape is evolving too fast to build durable integrations against. This principle states the commitments that constrain the eventual implementation — so we don't bake in vendor dependencies or account requirements before we start.

When AI does ship:

- **Local by default**: on-device inference for core capabilities. Works offline. No account. No network required.
- **User-key for frontier models** (optional): the user pastes their own API key for the provider of their choice. Requests go directly from their machine to the provider. We never proxy, never see the content, never see the key. This is a single settings pane, not a product tier.
- **AI never modifies the document without explicit user consent.** Inline suggestions, never silent edits.
- **AI is integrated into the editing flow** (selection actions, inline suggestions) — not a chat panel bolted to the side.

**Decision [D-AI-1]**: When AI ships, it is local-first by default. User-key cloud is opt-in enhancement.
**Decision [D-AI-2]**: No paid tier. No AI relay. No server-side AI. Ever.
**Decision [D-AI-3]**: AI never modifies the document without explicit consent. Inline suggestions, not chat.

### DP-9: Graceful degradation
When things go wrong, the user should never lose work or feel confused.

- If auto-save fails, the document stays in memory and the user is notified non-modally with retry
- If a cloud-drive file is evicted from local storage while open, we detect it and offer to re-download or save locally
- If a file has an unexpected encoding or line-ending convention, we detect it and preserve it rather than silently mangling it
- Every error state is designed — not just coded

**Decision [D-ERR-1]**: No error state is undesigned. Every feature spec must include failure modes.

### DP-10: Accessible to everyone
Accessibility is P0, not P1.

- Full screen-reader support on every platform
- Dynamic Type / user font scaling
- Reduced Motion support
- WCAG AA contrast minimum
- All functionality reachable via keyboard
- No information conveyed by color alone
- Read mode must be fully usable by screen-reader users — it is often *more* accessible than source view for document consumption

**Decision [D-A11Y-1]**: Every feature spec must include accessibility acceptance criteria. A feature that doesn't work with the platform screen reader doesn't ship.

### DP-11: Agent-built, human-directed
Markdown is built by autonomous agents running grooming and sprint execution, with a small number of humans directing intent and reviewing output. This is a design principle because it shapes how work is planned, scoped, reviewed, and contributed to. The product-facing consequence is that the backlog discipline is visible in the product's quality bar: clear intent, verifiable acceptance, no hand-waving.

Operational details live in `CONTRIBUTING.md`.

**Decision [D-PROC-1]**: The process itself is part of the product. Improving the contribution loop is first-class work.

---

## 8. Decision Log (product decisions only)

### Market positioning
- **[D-MKT-1]** Primary job-to-be-done is opening and reading AI-generated `.md` files on any platform, with zero configuration, rendered beautifully. Authoring is secondary but important.
- **[D-MKT-2]** Markdown is the AI-era document tool. The workflow — open, read, edit, render, share — is first-class, with read as the default.
- **[D-MKT-3]** Position as the complement to IDEs, not a competitor.

### User experience
- **[D-UX-1]** Read mode is the default when a file is opened. Author mode is one gesture away.
- **[D-UI-1]** No feature ships unless the flow, latency, defaults, and error states have been explicitly designed and polished.
- **[D-ERR-1]** No error state is undesigned.

### Editor
- **[D-EDIT-1]** Auto-formatting + document doctor on by default in author mode.

### AI
- **[D-AI-1]** When AI ships, local-first AI. On-device inference is the default.
- **[D-AI-2]** No paid tier. User-key mode for frontier models; the user controls the key and the provider.
- **[D-AI-3]** AI never modifies the document without explicit consent. Inline suggestions, not chat.

### Platform
- **[D-PLAT-1]** All platforms are first-class. iOS and macOS lead the ship order and set the native-feel bar; the web build follows and serves Windows and Linux together.

### File handling
- **[D-FILE-1]** No vault, library, or proprietary file store. OS filesystem is the storage layer.
- **[D-FILE-2]** Cloud-drive integration through OS file providers only.
- **[D-FILE-3]** Line ending and encoding are detected on open and preserved on save.

### Performance (as user-visible quality bars)
- **[D-PERF-1]** The user-facing performance contract:
  - Opening a typical document feels immediate — under a second from picker to rendered view
  - Editing feels instant — no visible lag between keystroke and character
  - Nothing blocks typing — the editor never freezes on parse, format, or diagnostics
  - Saving feels immediate — the user never waits on a save
  - Large documents (tens of thousands of lines) remain usable; they may not feel instant but they must not feel broken

Implementation budgets (millisecond targets) that realize this contract live in `ARCHITECTURE.md`.

### Accessibility
- **[D-A11Y-1]** Every feature spec must include accessibility acceptance criteria. A feature that doesn't work with the platform screen reader doesn't ship.

### Business
- **[D-BIZ-1]** The app is free. No commercial model. Apache 2.0.
- **[D-SUST-1]** Sustainability via agent-driven development with community contributions. See §6 and `CONTRIBUTING.md`.
- **[D-SUST-2]** Reduced-ambition fallback defined for the 3x-not-10x scenario: native iOS + macOS plus the web build for reach, core loop to craft quality.

### Roadmap
- **[D-ROAD-1]** iOS and macOS lead and set the quality bar; the web build follows with Windows and Linux.
- **[D-ROAD-2]** Every phase gates on the previous shipping and being baseline-measured. Throughput is reviewer-bounded.
- **[D-ROAD-3]** AI ships after v1.0, not before. Gated on AI ecosystem stabilization.
- **[D-ROAD-4]** Reduced-ambition fallback contracts the roadmap if sustainability produces 3x not 10x.

### Process
- **[D-PROC-1]** Agent-loop quality is first-class work. The process is part of the product.

---

## 9. Competitive Landscape

As of 2026. Read with the primary job-to-be-done in mind: *opening and reading AI-generated `.md` files*.

| Competitor | What they have | What they lack for our job-to-be-done | Our angle |
|-----------|----------------|---------------------------------------|-----------|
| **Obsidian** | Great UX, local files, huge plugin ecosystem | Wants you to build a vault before opening a file. Overkill for one-off AI output consumption. Not cross-platform in a free tier (paid sync). | Zero-config file opening. No vault, no ecosystem commitment. Runs everywhere for free. |
| **iA Writer** | Beautiful typography, open files | Apple-only, $50. Cannot consume AI output on Linux, Windows, Web, Android. | Same craft, every platform, free. |
| **Typora** | Live preview, open files | Desktop-only, closed source, paid. No mobile or web. | Every platform, free, open source. |
| **Bear** | Beautiful iOS/macOS UX | Apple-only, proprietary storage, subscription. Wants to ingest your file, not open it. | Every platform, open files as-is, free. |
| **Ulysses** | Writer-focused | Apple-only, subscription, proprietary library. Not a file-opener. | Every platform, open files, free. |
| **Notion** | Rich blocks, collab | Not actually markdown. Cloud-only. Accounts required. | Actually markdown, local-first, no account. |
| **VS Code / Cursor** | Ubiquitous, open source, free | Code editors. Markdown preview is an afterthought. Opening a `.md` feels like opening source. | Prose-first. Read mode is the default, not a toggle. |
| **MarkText** | Free, open source, WYSIWYM | Deprecated 2025 (maintainer burnout). | Same category, different sustainability model (see §6). |
| **TextEdit / Notes / default text viewer** | Installed on your device | Not markdown. Raw syntax, no rendering. | Purpose-built for `.md`. |

---

## 10. Honest Risks

The critiques that would come from a reviewer who doesn't buy the pitch. Kept here so we don't flinch from them.

**Sustainability risks** (the ones that kill the project):

- **Solo architect is a single point of failure.** The model requires one human holding architectural coherence in their head. If that human disengages — burnout, life change, new project, health — the project stops. Review is the bottleneck; the reviewer is the bottleneck on the bottleneck. No amount of agent throughput compensates for the absence of the architect. This is the most concentrated failure mode in the entire plan. Mitigation (named deputy reviewers, succession planning) is not an infancy-phase concern but must be addressed before the project becomes widely depended-on.
- **Why contributors will spend their agent subscriptions here is unproven.** The thesis (see §6 and `CONTRIBUTING.md`) is that agent subscriptions have idle capacity and that directing it at a daily-driver tool costs less cognitive overhead than starting one's own project from scratch. Plausible, but untested. If contributors don't materialize, the solo architect is also the solo coder, and throughput collapses to solo-maintainer speed regardless of how agent-legible the project is.
- **The review bottleneck may be harder than the writing bottleneck.** Agent-driven development moves the constraint from "write every line" to "review every PR." Review is cognitively expensive — the reviewer must hold the whole system in their head while evaluating choices they didn't make. Even with first-pass automated filters, human review capacity caps at roughly 3–5 substantive reviews per day per reviewer (empirically, this is what senior reviewers on Linux, Rust, and Chromium report). If agents produce 10x the PRs, throughput is reviewer-bounded, not agent-bounded, and the queue grows until the reviewer quits.
- **The sustainability model depends on vendors we don't control.** Contributors bring their own AI agent subscriptions. If providers raise prices, degrade quality, impose tighter rate limits, or pivot away from coding agents, the contributor pool shrinks and the project has no lever to pull. Structural dependency — acknowledged, not hidden.
- **Community contribution selects for privilege.** Agent subscriptions cost real money. Trivial for a senior developer at a U.S. tech company. Exclusionary for students, hobbyists, and developers in lower-cost-of-living countries. The model doesn't *worsen* OSS contribution demographics but it doesn't democratize them either.
- **"Free forever" is easy to say, hard to prove.** The legacy argument — that free editors can't sustain themselves — is still on the table. We are betting that agent-driven development breaks the pattern. If it doesn't, we fail honestly. The important question is not "will it work?" but "at what multiplier does it work?"
- **The roadmap assumes 10x. What if we get 3x?** The full roadmap is a funded-team backlog. If agent-driven development is 3x — still transformative, not miraculous — the later phases are a graveyard. Fallback in D-SUST-2.

**Product risks**:

- **Read-first may not be a universal win.** Our bet is that most users opening a `.md` file want to see it rendered, not edit it. If we're wrong — if a plurality of users want to land in source view — read-mode-by-default adds a click to their primary workflow. Mitigation: settings override, remembered per-file preference.
- **The AI-generated-markdown consumption job may be smaller than we think.** "Every AI writes markdown" is true; "everyone opens those `.md` files in a dedicated tool instead of the chat UI that produced them" is the load-bearing assumption. If users mostly read AI output in the chat UI (ChatGPT, Claude, Perplexity web apps) and only save `.md` as archive, our primary job-to-be-done is smaller than it looks.
- **No PKM will cost us some users.** Wikilinks-as-plain-files is not a full second-brain replacement. Some Obsidian users will bounce when they discover there's no graph view. Deliberate (D-NO-1), accepted.
- **Deferring AI may cost us positioning.** Every competitor is shipping AI features. By shipping without AI initially, we forfeit the "AI-native" narrative and some trial users. Our bet is that "free, universal, polished" is a stronger durable position than "AI-native" in a market where AI features rot as fast as the underlying models change. If this bet is wrong, we lose the near-term mindshare race and have to catch up later.

**Execution risks related to architecture decisions** live in `ARCHITECTURE.md` §Risks.

---

## 11. Success Metrics

No revenue metrics. Success for a free, open-source editor looks different.

**Year 1 (post-v1.0)**:
- Ships on the App Store (iOS), Homebrew (macOS), and as an installable PWA for the web, Windows, and Linux
- iOS, macOS, and the web build stable enough to use daily
- 10k GitHub stars
- Sustained download volume across channels (App Store, Homebrew analytics, PWA installs where the platform exposes counts) — not a specific target, but monotonic growth over the year
- CommonMark spec compliance above 98%, with reference-style links resolving correctly

**Year 2**:
- Windows and Linux packaged builds (Flatpak, AUR, WinGet) and Android, all stable
- At least one major Linux distribution packages it
- Included in at least one default desktop environment image
- Recognized in at least one "tools we recommend" list from a major publication or OSS project
- First external contributor merges
- The primary persona describes Markdown as "the one I use" without qualification

**Year 3**:
- When someone asks "how do I open this AI-generated `.md` file," the answer is Markdown — the way Firefox was the answer for browsers
- Markdown is the default way knowledge workers consume AI-generated markdown — the commodity tool for a commodity format
- The sustainability experiment is either demonstrably working or demonstrably failed — we have data either way

**Anti-metrics** (things we explicitly do not optimize for):
- MAU/DAU (no telemetry)
- Retention (no accounts)
- Conversion (no paid tier)
- Engagement time (we want people to get their work done and leave)

Operational metrics for the sustainability experiment live in `CONTRIBUTING.md`.

---

## Appendix A: Related documents

- `ARCHITECTURE.md` — how the product is built. All framework, library, and implementation decisions live there.
- `CONTRIBUTING.md` — how contributions work. The full sustainability model, contributor motivation thesis, agent-legibility maintenance, and review loop.
