# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project

easy-markdown — an AI-native markdown editor for iOS/macOS. SPM package structure with EMCore, EMSettings, EMApp modules. Key docs:

- **`docs/PRODUCT.md`** — Product decisions, features, and constraints. Defines *what* and *why*. Decision IDs: `[D-XXX]`.
- **`docs/ARCHITECTURE.md`** — Technical governance. Defines *how* and *with what*. Decision IDs: `[A-XXX]`. **Read this before implementing any backlog item** — it specifies the framework, package, patterns, and hard rules for every feature.

When implementing a backlog item: read ARCHITECTURE.md §2 (feature-to-package mapping) to find where code goes, §9 (conventions) for rules, and the relevant technology section for patterns.

When implementing a backlog item, add code to the correct SPM module per the feature-to-package mapping.

## Build

Swift Package Manager. Open `Package.swift` in Xcode or use CLI:

```bash
swift build                    # Build all targets (macOS host)
swift test                     # Run unit tests
```

For iOS: open in Xcode, create an app target referencing the EMApp library, add `@main` entry point.

### Package structure

```
Sources/EMCore/       — Shared types, errors, platform aliases
Sources/EMSettings/   — Settings model, UserDefaults persistence
Sources/EMApp/        — App shell, navigation, views
Tests/                — Unit tests per module
```

## Sprint Orchestration (aishore)

AI sprint runner. Backlog lives in `backlog/`, tool lives in `.aishore/`. Run `.aishore/aishore help` for full usage.

```bash
.aishore/aishore run [N|ID]         # Run sprints (branch, commit, merge, push per item)
.aishore/aishore groom [--backlog]  # Groom bugs or features
.aishore/aishore review             # Architecture review
.aishore/aishore status             # Backlog overview
```

After modifying `.aishore/` files, run `.aishore/aishore checksums` before committing.
