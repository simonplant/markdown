# Easy Markdown

[![License](https://img.shields.io/badge/License-Apache_2.0-blue.svg)](https://opensource.org/licenses/Apache-2.0)

A professional, AI-native markdown editor for Apple platforms. Open any `.md` file, write with AI as your co-author, and render everything beautifully -- rich text, tables, diagrams, and code blocks. No vault. No library. No lock-in.

## Why

Markdown is the primary language of AI. Every major AI agent -- Claude, ChatGPT, Cursor, Perplexity -- produces it. Developers write in it. Teams collaborate through it. For the vast majority of documents people create, markdown is all you need.

But current markdown editors are tied to vaults and proprietary storage ecosystems instead of focusing on what matters: maximum usability and polish. Obsidian requires a vault. Bear uses proprietary storage. Notion can't go offline. None of them treat markdown as the first-class document format of the AI age.

Easy Markdown changes that. It focuses on pure editing experience -- beautiful rendering, intelligent auto-formatting, on-device AI assistance, and the kind of craft you expect from the best Apple-native apps. Open files from anywhere your device can see them (iCloud, Dropbox, Git repos), edit them, and share them. That's it.

## Platform Support

| Platform | Minimum Version |
|----------|----------------|
| iOS      | 17+            |
| macOS    | 14+ (Sonoma)   |

Built with SwiftUI and Swift structured concurrency. Requires Xcode 15+ and Swift 5.9+.

## Architecture

Easy Markdown is structured as a modular Swift Package Manager workspace. Each module has a clear responsibility and enforced dependency boundaries.

```
Sources/
├── EMCore/         Shared types, errors, typography, theme system
├── EMParser/       Markdown parser (wraps Apple's swift-markdown)
├── EMFormatter/    Auto-formatting rules engine (lists, tables, headings)
├── EMDoctor/       Document diagnostics (broken links, structure issues)
├── EMEditor/       TextKit 2 text view, rendering pipeline, AI action bar
├── EMFile/         File coordination, bookmarks, auto-save
├── EMAI/           AI provider protocol, local + cloud inference
├── EMSettings/     Settings model, UserDefaults persistence
└── EMApp/          SwiftUI app shell, navigation, dependency wiring
```

**Dependency flow:** EMApp (composition root) depends on all modules. EMEditor depends on EMParser, EMFormatter, and EMDoctor. All modules depend on EMCore (the leaf). No circular dependencies -- the compiler enforces this.

Key technical choices:
- **TextKit 2** for the editing engine, targeting <16ms keystroke-to-render latency
- **Apple's swift-markdown** (cmark-gfm) for CommonMark + GFM parsing
- **`@Observable`** and unidirectional data flow for all state management
- **On-device AI** via MLX Swift / Core ML on A16+ and M1+ hardware
- **No database** -- UserDefaults only, no sidecar files, no proprietary formats

For full architectural details, see [`docs/ARCHITECTURE.md`](docs/ARCHITECTURE.md). For product decisions and rationale, see [`docs/PRODUCT.md`](docs/PRODUCT.md).

## Building

Easy Markdown uses Swift Package Manager.

```bash
# Build all targets
swift build

# Run unit tests
swift test
```

To build and run on a device, open `Package.swift` in Xcode, create an app target referencing the EMApp library, and add a `@main` entry point.

For iOS simulators and devices, use Xcode's standard build and run workflow (Cmd+R).

## Contributing

Contributions are welcome. Please open an issue to discuss significant changes before submitting a pull request.

When working on the codebase:

1. Read [`docs/ARCHITECTURE.md`](docs/ARCHITECTURE.md) before implementing features -- it specifies which module owns each feature and the rules that govern all code.
2. Place code in the correct SPM module per the feature-to-package mapping in the architecture doc.
3. Every `public` declaration needs a doc comment (`///`).
4. All UI elements must support VoiceOver, Dynamic Type, and Reduced Motion.
5. Run `swift test` before submitting.

## License

Licensed under the [Apache License 2.0](LICENSE).

```
Copyright 2025-2026 Simon Plant
```
