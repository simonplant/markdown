# Easy Markdown

The best free markdown editor on every platform. Apache 2.0. No vault, no account, no subscription.

Open any `.md` file from a local folder or cloud drive (iCloud Drive, Dropbox, Google Drive, OneDrive) on macOS, Linux, Windows, Web, iOS, and Android. Built on a Rust core, CodeMirror 6 editor, and Tauri shells. Built by autonomous agents.

## Status

**Pre-M0.** There is no code yet — only docs and a backlog. The first milestone is a walking skeleton: open a file, edit it, save it back, measure the baseline. Everything else decorates that.

See [`docs/PRODUCT.md`](docs/PRODUCT.md) §7.1 for the walking-skeleton definition and [`backlog/backlog.json`](backlog/backlog.json) for the six M0 items (FEAT-001 through FEAT-006).

## Docs

- [`docs/PRODUCT.md`](docs/PRODUCT.md) — product vision, principles, decisions, feature scope, honest risks
- [`docs/ARCHITECTURE.md`](docs/ARCHITECTURE.md) — Rust core, CodeMirror 6, Tauri shells
- [`CLAUDE.md`](CLAUDE.md) — guidance for Claude Code and agent sprints
- [`PRIVACY.md`](PRIVACY.md) — no telemetry, no network, files stay local

## Development

This repo uses [aishore](./.aishore/) for agent-driven sprint orchestration. The backlog lives in [`backlog/`](backlog/).

```bash
.aishore/aishore status                # what's in the backlog
.aishore/aishore backlog list          # detailed list
.aishore/aishore run FEAT-001          # run the first sprint
```

Once M0 (FEAT-001..FEAT-006) lands, this section will include real build and run instructions.

## License

[Apache 2.0](LICENSE). The whole stack. Not open-core, not source-available.
