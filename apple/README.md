# Markdown — native Apple frontend (iOS, macOS)

The **lead** frontend: a SwiftUI app on **TextKit 2** (`UITextView` on iOS,
`NSTextView` on macOS) over the shared Rust `markdown-core`, bound in-process via
**uniffi**. iOS is the priority platform and sets the quality bar.

Authoritative spec: [`../docs/IOS_BUILD_SPEC.md`](../docs/IOS_BUILD_SPEC.md).
Architecture rationale: [`../docs/ARCHITECTURE.md`](../docs/ARCHITECTURE.md) §4.2.

## Build & run

```bash
scripts/build-rust.sh          # build staticlibs (iOS, iOS-sim, macOS) + uniffi Swift
                               # bindings → MarkdownCore.xcframework
xcodegen generate              # generate MarkdownEditor.xcodeproj from project.yml
                               # (re-run after ADDING source files — XcodeGen snapshots the file list)
xcodebuild test -scheme MarkdownEditor \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro'   # build + run the iOS UI suite
swift test --package-path Packages/MarkdownCoreFFI           # core binding round-trip on macOS
```

`project.yml` is the checked-in source of truth. The generated
`MarkdownEditor.xcodeproj`, `MarkdownCore.xcframework`, and `Info.plist` are
**gitignored build products** — regenerate them with the commands above.

## Layout

| Path | What |
|------|------|
| `project.yml` | XcodeGen spec — targets `MarkdownEditor` (iOS), `MarkdownEditorMac` (macOS), `MarkdownEditorUITests`; packages `MarkdownCore` (local) + `SwiftMath`. |
| `MarkdownEditor/` | App sources: `App/`, `Document/` (`ReferenceFileDocument`, BOM-preserving encode), `Editor/` (TextKit 2 view, read mode, span-based `MarkdownRenderer`), `Platform/` (`#if os` shims), `Math/`, `Formatting/`, `Outline/`, `Export/` (PDF), `Settings/`, `QuickOpen/`. |
| `MarkdownEditorMac/` | macOS target `Info.plist` (sources shared with the iOS target via `#if os`). |
| `MarkdownEditorUITests/` | Simulator UI tests + screenshots. |
| `Packages/MarkdownCoreFFI/` | SwiftPM package wrapping the generated uniffi bindings + the xcframework. `swiftLanguageModes: [.v5]`. |
| `scripts/build-rust.sh` | Builds the three Apple-triple staticlibs and assembles the xcframework. |
| `docs/` | Verification screenshots. |

## Gotchas

- **uniffi-generated Swift needs Swift-5 language mode** (`swiftLanguageModes: [.v5]`
  in `Package.swift`) — Swift 6 strict concurrency rejects uniffi's global
  `var initializationResult`.
- **Don't re-declare the system UTI `net.daringfireball.markdown`** ("duplicate type
  identifier"). The app **exports** its own `com.markdown.editor.markdown` UTI so `.md`
  creation works.
- The span-based renderer slices source by AST byte-offset spans and strips markers —
  the AST gives reliable spans but not inline leaf text (same pattern as doctor/formatter).

## Status

The M1–M9 lead phase and Phase 4 rich content are **built and verified by running**
on the iOS Simulator and as a native macOS app. The one open item is **FEAT-037
Mermaid** — blocks are detected and distinctly rendered; full SVG via an offscreen
mermaid.js `WKWebView` remains.
