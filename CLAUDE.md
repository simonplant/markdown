# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project

easy-markdown — project is in early/initial stages. No source code, build system, or tests exist yet. Key docs (`docs/PRODUCT.md`, `docs/ARCHITECTURE.md`) are placeholder files.

Update this file as the project takes shape with build commands, architecture notes, and development workflows.

## Sprint Orchestration (aishore)

AI sprint runner. Backlog lives in `backlog/`, tool lives in `.aishore/`. Run `.aishore/aishore help` for full usage.

```bash
.aishore/aishore run [N|ID]         # Run sprints (branch, commit, merge, push per item)
.aishore/aishore groom [--backlog]  # Groom bugs or features
.aishore/aishore review             # Architecture review
.aishore/aishore status             # Backlog overview
```

After modifying `.aishore/` files, run `.aishore/aishore checksums` before committing.
