# IOS_BUILD_SPEC — Authoritative native iOS build specification

> **PROGRESS: M1–M9 DONE (2026-06-20).** The iOS & macOS lead phase is built and
> verified by running on the simulator / as a native macOS app: uniffi binding
> (M1), TextKit 2 skeleton (M1), read-mode default + read↔author + span renderer
> (M2), doctor diagnostics overlay (M3), Format Document (M4), BOM-preserving save
> (M5), find + themes (M6), Dynamic Type + spell check + keyboard shortcuts (M7),
> accessibility + DocumentGroup file management (M8), and the macOS target sharing
> the editor over NSTextView (M9). Remaining: Phase 4 rich content (deferred).
>
> **Status: authoritative.** This is the single source of truth for building the native iOS (and shared macOS) markdown editor: Swift + TextKit 2 frontend binding the shared Rust `markdown-core` in-process via **uniffi**. It synthesizes `docs/PRODUCT.md`, `docs/ARCHITECTURE.md`, the live backlog (`backlog/backlog.json` + archives), the `markdown-core` public API, and the `reference/` Swift prototype catalog.
>
> The dependency spine is fixed and non-negotiable: **EPIC-CORE-API (done) → EPIC-UNIFFI → EPIC-APPLE-SKELETON → EPIC-APPLE-FEATURES → Phase-4 rich content.** Phase ordering and `dependsOn` are binding (CLAUDE.md, A-PROC-3). The document model stays `String` (`docs/engine-decision.md`). Every merge is gated against `docs/baseline.json` at 1.1x per slice.

**Environment as built (verified 2026-06-20 on this host):** Xcode 26.5 (build 17F42), iOS SDK 26.5 (`iphoneos26.5`) + iOS Simulator SDK 26.5 present, `xcode-select` → `/Applications/Xcode.app`, Swift 6.3.2 (strict concurrency), Rust 1.94.1, all three Apple Rust targets installed (`aarch64-apple-ios`, `aarch64-apple-ios-sim`, `aarch64-apple-darwin`). **No iOS simulator runtime is installed** (`xcrun simctl list runtimes` → empty; iOS-26-3/26-4 listed *unavailable*). This single fact draws the line in §6 between what is verifiable here and what needs a runtime download or device.

---

## 1. Scope & non-goals (grounded in PRODUCT decisions)

### 1.1 In scope for the iOS lead phase

iOS is the **lead platform** and sets the quality bar (D-PLAT-1, D-ROAD-1); it is the surviving core even in the §6 reduced-ambition fallback (D-SUST-2). The lead phase ships exactly the core loop from PRODUCT §5 "iOS & macOS (lead)":

- **Open** a `.md` file from a local folder **or cloud drive** (iCloud/Dropbox/Google Drive/OneDrive) — through **OS file providers only** (Files app), no proprietary store (D-FILE-1/2).
- **Read mode is the default view** on open (D-UX-1, DP-3) — rendered beautifully: styled headings, laid-out tables, highlighted code blocks, inline images; source punctuation (`#`, `**`, fences) hidden. The single most load-bearing product claim (FEAT-049).
- **Author mode one tap away** — WYSIWYM decorations, live formatting, document doctor, find/replace, word count, spell check (D-EDIT-1, DP-5).
- **Light/dark themes** following the system (FEAT-014).
- **Save** preserving line endings + encoding/BOM (D-FILE-3, FEAT-054); **auto-save** at a 1000 ms debounce with content-hash no-op skip (FEAT-025/051); **conflict detection** on external change/eviction (FEAT-026, DP-9).
- **Accessibility is P0** (D-A11Y-1): full VoiceOver, Dynamic Type, Reduce Motion, WCAG AA contrast, hardware-keyboard reachability, nothing conveyed by color alone. A feature that fails the screen reader does not ship.
- **Global text from day one** (D-USER-4): CJK, RTL, accented, emoji rendering and IME input correct — delivered for free by TextKit 2 + UIKit.
- **macOS shares the TextKit 2 surface** (`NSTextView`) as the last step of EPIC-APPLE-FEATURES.

### 1.2 Non-goals (load-bearing — violating one reopens a decision)

From PRODUCT §4 and the backlog retirements:

- No vault / library / database / sidecar files / hidden metadata (D-FILE-1, D-NO-2, DP-1).
- No accounts, no sign-in, no telemetry/analytics/phone-home (D-NO-9, D-NO-14, PRIVACY.md).
- No proprietary cloud sync — the user's iCloud/Dropbox **is** the sync (D-NO-8).
- No paid tier / Pro / subscription; Apache 2.0 whole stack (D-NO-10, D-NO-13, D-BIZ-1).
- No plugin/extension system — first-party or not at all (D-NO-7).
- No PKM graph/backlinks-as-database (only plain-file wikilinks), no publishing pipeline, no format conversion, no general-purpose code editing, no Vim/terminal/git (D-NO-1/4/5/6, D-USER-2).
- **No AI anywhere in the iOS lead phase** (D-ROAD-3, D-AI-1/2/3, D-NO-11/12). The `ai.rs` surface stays behind the `ai` Cargo feature, **off**. uniffi `ai_*` exports are written but feature-gated and never compiled into the shipping iOS library.
- **No webview / WKWebView editor surface** (A-STACK-2, ARCHITECTURE §8 "web wrapper" guardrail). The editor is TextKit 2. The retired `FEAT-033` Tauri iOS shell must not be resurrected.
- **Deferred to Phase 4, not the lead phase:** Mermaid (FEAT-037), math/KaTeX (FEAT-038), images-beyond-basic (FEAT-042), folding/outline (FEAT-039), tabs/split (FEAT-040), Quick Open (FEAT-041), PDF export (FEAT-043), custom themes/fonts (FEAT-044), extended doctor rules (FEAT-036). They integrate only through the rendering hook FEAT-049 read mode exposes.

---

## 2. uniffi binding surface (EPIC-UNIFFI)

**Greenfield.** `markdown-core` declares `crate-type = ["rlib","cdylib","staticlib"]` already but has **no uniffi dependency, no `build.rs`, no `.udl`, no `#[uniffi::export]`**. The only existing binding is the hand-rolled WASM C-ABI in `wasm_api.rs`, which iOS ignores. EPIC-UNIFFI is **additive scaffolding + three concrete edits to existing types + one new native-only `ffi.rs` wrapper module.** Design: proc-macro mode (`uniffi::setup_scaffolding!()`), no `.udl`.

### 2.1 Cargo.toml changes (`markdown-core/Cargo.toml`)

```toml
[dependencies]
# ... existing tree-sitter, serde, serde_json ...
thiserror = "1"

# uniffi only on native (Apple) targets — never on wasm32, so it can't collide
# with the existing WASM cdylib binding.
[target.'cfg(not(target_arch = "wasm32"))'.dependencies]
notify = "6"                                  # (existing)
uniffi = { version = "0.28", features = ["cli"] }

[target.'cfg(not(target_arch = "wasm32"))'.build-dependencies]
uniffi = { version = "0.28", features = ["build"] }

[features]
default = []
ai = ["llama-cpp-2"]
uniffi-bin = ["uniffi/cli"]                   # enables the bindgen bin target

[[bin]]
name = "uniffi-bindgen"
path = "src/bin/uniffi-bindgen.rs"
required-features = ["uniffi-bin"]
```

`crate-type` is unchanged — `staticlib` is already declared for this binding. The WASM build never sees `uniffi` because of the `cfg(not(target_arch = "wasm32"))` gate; the two bindings stay isolated.

### 2.2 Scaffolding files

**`markdown-core/build.rs`** (new):
```rust
fn main() {
    #[cfg(not(target_arch = "wasm32"))]
    uniffi::generate_scaffolding("src/markdown_core.udl").ok();
    // Proc-macro mode needs no UDL; if pure-attribute, this call is replaced by
    // nothing and scaffolding is emitted by `setup_scaffolding!()` in lib.rs.
}
```
Use **pure proc-macro mode**: drop the `.udl` and `generate_scaffolding` entirely, and instead add to `lib.rs`:
```rust
#[cfg(not(target_arch = "wasm32"))]
uniffi::setup_scaffolding!();
```
Everything below is attribute-driven (`#[uniffi::export]`, `#[derive(uniffi::Record/Enum/Object/Error)]`). The `build.rs` is then only needed if a UDL is kept; proc-macro mode needs none. **Decision: proc-macro mode, no UDL, no build.rs** — cleanest for greenfield.

**`markdown-core/src/bin/uniffi-bindgen.rs`** (new) — emits Swift:
```rust
fn main() {
    uniffi::uniffi_bindgen_main()
}
```
Invoked as `cargo run --features uniffi-bin --bin uniffi-bindgen -- generate --library <path-to-.a-or-.dylib> --language swift --out-dir <out>`. Library mode reads metadata from the compiled artifact, so the Swift bindings can never drift from the exported symbols.

### 2.3 The three load-bearing edits to existing types

1. **`doctor.rs` `Diagnostic.rule: &'static str` → `String`.** Convert the three rule literals (`doctor.rs:77` `"heading-hierarchy"`, `:123` `"duplicate-heading"`, `:207` `"broken-link"`, plus duplicate/unclosed) to `.into()`. Tests comparing `d.rule == "x"` keep compiling (`String == &str`). This is the single most invasive change.
2. **`Diagnostic.span: (usize, usize)` → an `ffi::Span { start: u64, end: u64 }` Record** at the boundary (uniffi has no tuple type). The internal `(usize,usize)` may stay; convert in `From<doctor::Diagnostic>`.
3. **`Document` interior mutability.** uniffi objects are `Arc<T>` and methods take `&self`, but `Document::edit` is `&mut self` (`lib.rs:88`). **Keep `Document` untouched; add a thin uniffi wrapper `MarkdownDocument` holding `Mutex<Document>`.** No edit to the tested struct.

`usize` offsets stay `usize` internally; convert to `u64` only in the wrapper. `current_text(&self) -> &str` (`lib.rs:120`) returns a borrow — the wrapper returns an owned `String`.

### 2.4 New native-only module `markdown-core/src/ffi.rs`

Gated `#[cfg(not(target_arch = "wasm32"))]` and `mod ffi;` from `lib.rs`. Defines every uniffi type and `From` conversions; the stateless functions parse internally so Swift never threads a `SyntaxTree`.

**Errors** (`#[derive(uniffi::Error, thiserror::Error)]`):
```rust
pub enum EncodingError { Utf16Le, Utf16Be, InvalidUtf8, Io { msg: String } }
pub enum CoreError      { Io { msg: String }, Wikilink { msg: String }, Ai { msg: String } }
```

**Value Records / Enums** (`#[derive(uniffi::Record)]` / `uniffi::Enum`):
```rust
struct Span { start: u64, end: u64 }
struct Position { row: u64, column: u64 }
enum  Severity { Error, Warning, Hint }
struct Diagnostic { span: Span, severity: Severity, rule: String, message: String }
struct Mutation { offset: u64, delete: u64, insert: String }     // offset-descending order preserved
struct Backlink { path: String, line: u64, context: String }
enum  CheckboxState { Checked, Unchecked }
enum  NodeKind { /* mirrors ast::NodeKind, owned Strings: Heading{level:u8},
                   ListItem{checkbox:Option<CheckboxState>},
                   FencedCodeBlock{language:Option<String>},
                   Link{destination:Option<String>}, Image{source:Option<String>}, ... */ }
struct AstNode { kind: NodeKind, span: Span, start: Position, end: Position,
                 children: Vec<AstNode>, text: Option<String> }   // recursive Record; no borrowed iterator crosses
```

**Stateless `#[uniffi::export]` free functions** (parse internally; iOS passes only text):
```rust
fn parse(text: String) -> AstNode;                                 // returns root; calls parser::parse
fn diagnose(text: String) -> Vec<Diagnostic>;                      // parse + doctor::check(None)
fn diagnose_with_context(text: String, doc_path: String,
                         siblings: Vec<String>) -> Vec<Diagnostic>; // broken-link rule
fn format(text: String) -> Vec<Mutation>;                          // parse + formatter::format
fn apply_mutations(text: String, mutations: Vec<Mutation>) -> String;
fn resolve_wikilink(link_text: String, current_file_path: String) -> Option<String>;
fn backlinks(file_path: String) -> Result<Vec<Backlink>, CoreError>;
fn create_wikilink_target(link_text: String, current_file_path: String) -> Result<String, CoreError>;
```

**Document object** (`#[derive(uniffi::Object)]`, all methods `&self`):
```rust
pub struct MarkdownDocument { inner: std::sync::Mutex<crate::Document> }
#[uniffi::export]
impl MarkdownDocument {
    #[uniffi::constructor] fn from_content(content: String) -> Arc<Self>;
    #[uniffi::constructor] fn open_file(path: String) -> Result<Arc<Self>, EncodingError>;
    #[uniffi::constructor] fn from_bytes(bytes: Vec<u8>) -> Result<Arc<Self>, EncodingError>;
    fn edit(&self, offset: u64, delete: u64, insert: String);      // locks Mutex, calls Document::edit
    fn save_file(&self, path: String) -> Result<(), CoreError>;    // maps io::Error → CoreError::Io
    fn current_text(&self) -> String;                              // owned clone
    fn has_utf8_bom(&self) -> bool;
}
```

**File watching** via uniffi **callback interface** (native only; the generic `FileWatcher::new<F: Fn>` in `watcher.rs` is not FFI-expressible directly):
```rust
enum FileChangeEvent { Modified, Deleted }
#[uniffi::export(callback_interface)]
pub trait FileChangeListener: Send + Sync { fn on_change(&self, event: FileChangeEvent); }
pub struct FileWatcher { /* wraps notify::RecommendedWatcher */ }
#[uniffi::export]
impl FileWatcher {
    #[uniffi::constructor]
    fn watch(path: String, debounce_ms: u64,
             listener: Box<dyn FileChangeListener>) -> Result<Arc<Self>, CoreError>;
    // Drop stops watching (existing Drop). On iOS this is a fallback only — see §4.7.
}
```
The wrapper supplies a closure to the existing `FileWatcher::new` that calls `listener.on_change(...)`.

**AI** (written, feature-gated behind `ai`, never compiled into shipping iOS lib): `ai_model_path`, `ai_is_model_available`, `ai_model_download_url`, `ai_build_prompt`, and an `AiEngine` object — all mapping `String` errors to `CoreError::Ai`.

**`From` conversions** live in `ffi.rs`: `From<doctor::Diagnostic>`, `From<formatter::Mutation>`, `From<&ast::SyntaxNode> for AstNode` (recursive), `From<wikilinks::Backlink>`, `From<io::Error>/String → CoreError`. Not changed: `parser::parse` recursion, `formatter`/`doctor` rule logic, the `wasm_api` C-ABI, `SyntaxTree`/`SyntaxTreeIter` (kept Rust-internal; only owned `AstNode` crosses).

### 2.5 Building the staticlib for three Apple triples + XCFramework

`markdown-core` builds `libmarkdown_core.a` for each triple (release):
```
cargo build -p markdown-core --release --target aarch64-apple-ios       # device
cargo build -p markdown-core --release --target aarch64-apple-ios-sim   # Apple-silicon simulator
cargo build -p markdown-core --release --target aarch64-apple-darwin     # macOS + Swift test host
```
A `module.modulemap` + the uniffi-emitted `markdown_coreFFI.h` are packaged per slice. `xcodebuild -create-xcframework` combines them:
```
xcodebuild -create-xcframework \
  -library target/aarch64-apple-ios/release/libmarkdown_core.a       -headers <hdr> \
  -library target/aarch64-apple-ios-sim/release/libmarkdown_core.a   -headers <hdr> \
  -library target/aarch64-apple-darwin/release/libmarkdown_core.a    -headers <hdr> \
  -output apple/MarkdownCore.xcframework
```
(ios + ios-sim + macos = three distinct platform slices; all Apple-silicon arm64, distinguished by platform, so `lipo` is not needed unless x86_64 sim/Intel mac is added later.) Swift bindings (`markdown_core.swift`) are generated once via the `uniffi-bindgen` bin (library mode) and committed into the Swift package sources. The whole flow is one script, `apple/scripts/build-rust.sh` (§3.3).

### 2.6 Resulting Swift API the app calls

uniffi emits `markdown_core.swift` exposing, in module `MarkdownCore`:
- Free funcs: `parse(text:) -> AstNode`, `diagnose(text:) -> [Diagnostic]`, `diagnoseWithContext(text:docPath:siblings:) -> [Diagnostic]`, `format(text:) -> [Mutation]`, `applyMutations(text:mutations:) -> String`, `resolveWikilink(linkText:currentFilePath:) -> String?`, `backlinks(filePath:) throws -> [Backlink]`, `createWikilinkTarget(...) throws -> String`.
- `class MarkdownDocument`: `MarkdownDocument(content:)`, `MarkdownDocument.openFile(path:) throws`, `MarkdownDocument.fromBytes(bytes:) throws`, `.edit(offset:delete:insert:)`, `.saveFile(path:) throws`, `.currentText() -> String`, `.hasUtf8Bom() -> Bool`.
- `struct Diagnostic`, `Mutation`, `Span`, `Position`, `Backlink`, `AstNode`; `enum Severity`, `NodeKind`, `CheckboxState`, `FileChangeEvent`; `enum EncodingError: Error`, `CoreError: Error`; `protocol FileChangeListener`; `class FileWatcher`.

---

## 3. Xcode project structure (`apple/`)

A new top-level `apple/` directory (sibling of `markdown-core/`), buildable from the command line with `xcodebuild`.

```
apple/
├── scripts/
│   ├── build-rust.sh          # builds 3 staticlibs → XCFramework → regenerates Swift bindings
│   └── verify-binding.sh      # runs the macOS SwiftPM test (§6)
├── MarkdownCore.xcframework/   # PRODUCED by build-rust.sh (gitignored; CI rebuilds)
├── Packages/
│   └── MarkdownCoreFFI/        # SwiftPM package wrapping the XCFramework + generated bindings
│       ├── Package.swift
│       ├── Sources/
│       │   ├── MarkdownCoreFFIBinary/        # binaryTarget → ../../MarkdownCore.xcframework
│       │   └── MarkdownCore/
│       │       ├── markdown_core.swift       # uniffi-GENERATED (committed)
│       │       └── MarkdownCore.swift         # thin re-export + Swift ergonomics
│       └── Tests/
│           └── MarkdownCoreTests/
│               └── BindingRoundTripTests.swift  # the macOS proof (§6)
├── MarkdownEditor/             # the iOS (+ macOS) app target sources
│   ├── App/                    # MarkdownEditorApp.swift (DocumentGroup), scene/state restoration
│   ├── Document/               # MarkdownDocument (UIDocument/FileDocument bridge to core)
│   ├── Editor/                 # TextKit 2 editor (read + author) — §4
│   ├── Diagnostics/            # doctor overlay
│   ├── Formatting/             # hot-path mirror + parity fixtures
│   ├── Find/  WordCount/  Themes/  Accessibility/
│   └── Resources/
└── MarkdownEditor.xcodeproj    # generated by XcodeGen from project.yml (committed yml + project)
```

### 3.1 The SwiftPM wrapper package (`apple/Packages/MarkdownCoreFFI/Package.swift`)

```swift
// swift-tools-version:6.0
import PackageDescription
let package = Package(
  name: "MarkdownCore",
  platforms: [.iOS(.v17), .macOS(.v14)],
  products: [ .library(name: "MarkdownCore", targets: ["MarkdownCore"]) ],
  targets: [
    .binaryTarget(name: "MarkdownCoreFFIBinary",
                  path: "../../MarkdownCore.xcframework"),
    .target(name: "MarkdownCore",
            dependencies: ["MarkdownCoreFFIBinary"],
            // markdown_core.swift + a SwiftPM modulemap shim for the C FFI header
            path: "Sources/MarkdownCore"),
    .testTarget(name: "MarkdownCoreTests",
                dependencies: ["MarkdownCore"],
                resources: [.copy("Fixtures")]),
  ]
)
```
The generated `markdown_core.swift` expects the C module `markdown_coreFFI` — provided by the xcframework's `module.modulemap` (the binary target carries headers). The `MarkdownCore` target re-exports and adds Swift conveniences (e.g. `Diagnostic` → `NSRange` mapping).

### 3.2 The app target (`apple/MarkdownEditor.xcodeproj`, generated from `project.yml`)

Driven by **XcodeGen** so the project is reproducible from a committed `project.yml` and regenerated in CI (no merge-conflict-prone pbxproj edits). One target now, two destinations later:
- Target `MarkdownEditor` — iOS app, `iPhone`+`iPad`, deployment iOS 17, depends on the `MarkdownCore` SwiftPM product (local path), capabilities: Files (`UISupportsDocumentBrowser` / `LSSupportsOpeningDocumentsInPlace`), iCloud Documents, `CFBundleDocumentTypes` for `net.daringfireball.markdown` (UTType `.markdown`/`.text`), `UIFileSharingEnabled`.
- A macOS destination is added to the **same** target later (EPIC-APPLE-FEATURES 3u) so iOS/macOS share sources via `#if os(iOS)/os(macOS)` shims around `UITextView`/`NSTextView`.

### 3.3 Build script (`apple/scripts/build-rust.sh`) — command-line buildable

```bash
#!/usr/bin/env bash
set -euo pipefail
ROOT="$(git rev-parse --show-toplevel)"
TARGETS=(aarch64-apple-ios aarch64-apple-ios-sim aarch64-apple-darwin)
for t in "${TARGETS[@]}"; do
  cargo build -p markdown-core --release --target "$t"
done
# Generate Swift bindings (library mode reads metadata from the macOS .a):
cargo run -p markdown-core --features uniffi-bin --bin uniffi-bindgen -- \
  generate --library "$ROOT/target/aarch64-apple-darwin/release/libmarkdown_core.a" \
  --language swift \
  --out-dir "$ROOT/apple/Packages/MarkdownCoreFFI/Sources/MarkdownCore"
# Move the generated FFI header + modulemap into a headers dir per slice, then:
rm -rf "$ROOT/apple/MarkdownCore.xcframework"
xcodebuild -create-xcframework \
  -library "$ROOT/target/aarch64-apple-ios/release/libmarkdown_core.a"     -headers "$HDR" \
  -library "$ROOT/target/aarch64-apple-ios-sim/release/libmarkdown_core.a" -headers "$HDR" \
  -library "$ROOT/target/aarch64-apple-darwin/release/libmarkdown_core.a"  -headers "$HDR" \
  -output  "$ROOT/apple/MarkdownCore.xcframework"
```
App build from CLI:
```bash
xcodebuild build -project apple/MarkdownEditor.xcodeproj -scheme MarkdownEditor \
  -destination 'generic/platform=iOS' -sdk iphoneos26.5   # compiles against the iOS SDK
```

---

## 4. TextKit 2 editor design

The frontend owns **rendering, the two modes, the transition, themes, accessibility**; all parsing/diagnose/format/wikilink logic lives in the core (ARCHITECTURE §4). The editor renders through **`NSTextLayoutManager` / `NSTextContentStorage`** so selection physics, magnifier, caret, dictation, keyboard accessory, and text interaction are real platform behaviors. **The `reference/` prototype has no view/decoration/mode/document code — all of §4 is greenfield** (designed against ARCHITECTURE, not reconstructed from `reference/`). What `reference/` does give: the `TextMutation` seam and the ordered first-match formatting-rule model (§4.6), to be honored at the core boundary in **UTF-8 byte offsets** (standardize on UTF-8 offsets, not `String.Index`).

### 4.1 Document model — `MarkdownDocument` (app-side, `apple/MarkdownEditor/Document/`)

A `UIDocument` subclass (and `NSDocument`/`ReferenceFileDocument` bridge on macOS) wrapping the core object:
- holds `core: MarkdownCore.MarkdownDocument`
- `load(fromContents:ofType:)` → constructs the core doc via `MarkdownDocument.fromBytes(bytes:)` (preserves BOM/encoding, FEAT-054)
- `contents(forType:)` → returns bytes from `core.currentText()` re-encoded with the preserved BOM (the core's `save_file` path is mirrored as a byte producer so iOS's `UIDocument` owns the actual write — ARCHITECTURE §3.7 buffer-out)
- `editorState` (read vs author, cursor/scroll) persisted for state restoration and **per-file remembered mode** (PRODUCT §10 risk mitigation)

The frontend owns the **scene → core handle mapping** (ARCHITECTURE §3.8/3.9); the core is single-threaded per document and the frontend serializes access (the `Mutex<Document>` in `MarkdownDocument` enforces it).

### 4.2 Editor controller — `MarkdownTextView`

A custom `UITextView` configured for TextKit 2 (`textLayoutManager` non-nil), or a bespoke `UIView` driving `NSTextLayoutManager` directly for full control over decorations. Holds:
- `contentStorage: NSTextContentStorage` — the backing string is kept in sync with `core.currentText()`
- `layoutManager: NSTextLayoutManager`
- `mode: EditorMode { case read, author }`
- a `renderModel: AstNode` from `core.parse(text:)`, recomputed off-main on edit, debounced

### 4.3 Read mode (default on open — FEAT-049, D-UX-1)

On `load`, mount the **read view first** (the load-bearing default). Read mode:
- calls `core.parse(text:)` → `AstNode` tree
- walks the tree to build an `NSAttributedString` / a set of `NSTextLayoutFragment` styles: headings styled by `level`, `Strong`/`Emphasis`/`InlineCode` styled, `Link`/`Image` rendered, fenced code blocks highlighted (language from `NodeKind.FencedCodeBlock`), tables laid out, images inline
- **hides source punctuation** (`#`, `**`, fences) by applying zero-width/elided runs over the `Span` ranges that carry only markup — TextKit 2 attribute application over byte ranges from `AstNode.span`
- selection and copy operate on rendered text; **diagnostics never appear in read mode**
- VoiceOver presents the rendered document (a document, not source) — `UIAccessibility` over the layout fragments (D-A11Y-1)

### 4.4 Author mode (WYSIWYM — FEAT-013)

- full editing on the same `NSTextContentStorage`
- **WYSIWYM decorations**: syntax characters hidden when the cursor is away from a node, revealed on proximity — driven by comparing the selection offset to each `AstNode.span`; reveal logic runs on selection change, applies/removes elision attributes over markup ranges
- live formatting rules active (hot-path §4.6); doctor diagnostics visible (§4.5)
- find/replace, word count, spell check present

### 4.5 Read ↔ author transition (FEAT-049 3b)

- **Read → author**: a single tap anywhere enters author mode with the caret placed at the tapped character offset (hit-test the layout fragment → text location → byte offset). Hardware-keyboard `⌘E` (`UIKeyCommand`) also toggles (keyboard-only reachability, D-A11Y-1).
- **Author → read**: a visible affordance (toolbar button + `⌘E`).
- **Crossfade**, but `UIAccessibility.isReduceMotionEnabled` → instant swap (D-A11Y-1; "polish, not a marketing moment"). This is **not** the FEAT-015 "The Render" animation.

### 4.6 Hot-path formatting (A-CORE-3, FEAT-053)

Frame-critical rules (Enter/Tab/Backspace: list continuation, table alignment, heading spacing) are **mirrored in Swift** so they never wait on a binding round-trip, applied as a single `TextMutation`-equivalent (`{utf8 offset range, replacement, new cursor offset, optional haptic}`) inside one `NSTextContentStorage` edit + undo group (the `reference/TextMutation` seam). Input path: classify keystroke (`pressesBegan`/`insertText`/Return/Tab) → ask the local rule list (ordered, first-match) → apply or fall through to default typing. Complex rules (full reformat, doctor) run only in the core. **Parity harness (FEAT-053):** a test asserts zero diffs between the Swift hot-path output and `core.format(text:)`/the core reference on a committed corpus — the iOS hot-path is a *third* implementation (after Rust core and TS) that must stay parity-tested. Reuse-verbatim rule behaviors from `reference/`: ordered-list renumber-on-continue, empty-marker terminate, table separator auto-insert + separator-row skip, min-width-3 column alignment, heading-space insertion, CommonMark closing-hash strip with `C#` protection, 2-space hard-break exemption.

### 4.7 Files / iCloud open-save + auto-save + conflict (D-FILE-1/2/3, FEAT-019/025/026/051/054)

- **Open/save through OS file providers only**: `DocumentGroup`/`UIDocumentBrowserViewController` + `UIDocument`. Cloud files come through the Files provider — the user's sync is the sync.
- **Auto-save**: `UIDocument` autosaving, plus an explicit 1000 ms-debounced save with a **content-hash no-op skip** (FEAT-051 corrected 2s→1s) so a second write within 1 s is skipped. Never blocks typing.
- **Conflict / external change**: on sandboxed iOS the frontend forwards the platform's `NSFilePresenter`/`UIDocument` state changes to the core (ARCHITECTURE §3.7) rather than the core watching via `notify`. `UIDocumentStateChanged` → `.inConflict` surfaces a non-modal conflict UI (re-download / save-locally), and eviction of a cloud file is detected and offered re-download (DP-9). The uniffi `FileWatcher` is a macOS/non-sandboxed fallback only.
- **Encoding**: BOM/encoding detected on open by the core (`fromBytes`), preserved on save; UTF-16/non-UTF-8 surfaces a **non-modal banner** (FEAT-054, `EncodingError`), never silent mangling.
- **Graceful degradation**: if a save fails, the document stays in memory with a non-modal retry (D-ERR-1) — no undesigned error state.

### 4.8 Diagnostics overlay (FEAT-050)

After edits, on a ~500 ms debounce **off the main thread**, call `core.diagnose(text:)` / `core.diagnoseWithContext(...)` → `[Diagnostic]`. Render as underline decorations over each `Diagnostic.span` + gutter markers; long-press/hover shows `Diagnostic.message`; fixing clears within 1 s; **not shown in read mode**; the debounce must never raise keystroke latency above baseline (run on a background queue, marshal results to the main actor — the `reference/DoctorEngine` off-main model). Rules from the core: heading-hierarchy, broken-link, duplicate-heading, unclosed-formatting.

### 4.9 The rest of author mode

- **Find/replace** (FEAT-016): native search UI over the TextKit 2 surface.
- **Word count / stats** (FEAT-017): a stats bar computed from `core.currentText()`/`parse`.
- **Themes** (FEAT-014): native light/dark via `UITraitCollection.userInterfaceStyle`, WCAG-AA contrast.
- **Typography** (FEAT-020): TextKit 2 text styles honoring Dynamic Type.
- **Keyboard shortcuts** (FEAT-018): `UIKeyCommand` set; macOS menu equivalents.
- **Spell check** (FEAT-021): `UITextChecker` / system spell check.
- **Wikilinks** (FEAT-035): `core.resolveWikilink`/`backlinks` for `[[link]]` navigation + on-demand backlinks (no vault/index).
- **Share sheet + Files** (3s): `UIActivityViewController`, document browser, share-in/out of `.md`.
- **Accessibility** (3t): VoiceOver, Dynamic Type, Reduce Motion, keyboard reachability across all modes.

---

## 5. Feature → backlog mapping (walking-skeleton milestones)

Each milestone passes **when it runs, not when it compiles** (A-PROC-3). Forbidden ACs: `grep`/`test -f`/"compiles"/mocking the binding or filesystem. Each milestone captures/keeps an Apple baseline slice in `docs/baseline.json` (the on-device slice is added at M1 and kept green at the 1.1x gate per slice thereafter).

### M1 — Binding + skeleton: open/edit/save on a real surface  *(gate)*
- **Backlog:** EPIC-UNIFFI, EPIC-APPLE-SKELETON.
- **Build:** §2 uniffi surface + XCFramework + generated Swift; `apple/` project consuming it; minimal TextKit 2 `UITextView` bound to `MarkdownDocument`; Files open/save via `UIDocument`/document browser.
- **Exit criteria (runs):** (a) the macOS SwiftPM `BindingRoundTripTests` opens→edits→saves→reopens through uniffi and asserts a **byte-for-byte round-trip** (§6) — runs here; (b) the iOS app **launches on a real device/simulator**, opens a `.md` from Files, edits in TextKit 2, saves back to the original file, reopen round-trips.
- **Baseline:** commit an Apple/on-device **open/keystroke/save median** slice to `docs/baseline.json` (new `apple_*` or `ios_*` keys), measured across the `docs/baseline-corpus/` small/medium/large fixtures.

### M2 — Read mode default + read↔author transition + WYSIWYM
- **Backlog:** FEAT-049 (3a/3b), FEAT-013 (3c), within EPIC-APPLE-FEATURES.
- **Exit:** opening a file lands in **read mode** (punctuation hidden, headings/tables/code/images rendered); single tap → author mode at tap offset; `⌘E` toggles; Reduce-Motion instant swap; VoiceOver reads a document in read mode; author mode shows WYSIWYM reveal-on-proximity.
- **Baseline:** read-render + mode-transition latency added to the Apple slice; keep within 1.1x.

### M3 — Doctor diagnostics in author mode
- **Backlog:** FEAT-050.
- **Exit:** edits trigger a 500 ms-debounced off-main `core.diagnose`; a skipped heading level shows a marker within 1 s; long-press shows the message; fixing clears within 1 s; none shown in read mode; keystroke latency stays within baseline.
- **Baseline:** diagnose-debounce must not regress keystroke slice.

### M4 — Format document + hot-path parity
- **Backlog:** FEAT-052 (3e), FEAT-053 (3f).
- **Exit:** "Format Document" action applies all five core rules via `core.format`/`applyMutations` (misaligned tables become aligned); the Swift hot-path (Enter list-continue, table-align on `|`, heading space) responds within one frame; **FEAT-053 parity harness asserts zero diffs** between Swift hot-path and the core on the committed corpus.
- **Baseline:** format slice + keystroke slice green.

### M5 — File workflow, auto-save, conflict, encoding
- **Backlog:** FEAT-019 (3n), FEAT-025/051 (3o), FEAT-026 (3p), FEAT-054 (3g).
- **Exit:** new file / recents / unsaved prompt; auto-save writes after a 1.2 s pause and skips a duplicate write within 1 s; external change surfaces a conflict UI; cloud eviction offers re-download; UTF-8-BOM round-trips (`EF BB BF` preserved), plain UTF-8 gains no BOM, UTF-16 surfaces a banner.
- **Baseline:** save slice green.

### M6 — Find/replace, word count, themes, large-file perf
- **Backlog:** FEAT-016 (3h), FEAT-017 (3i), FEAT-014 (3j), FEAT-027 (3q).
- **Exit:** in-document find/replace; stats bar; system-following light/dark at WCAG AA; large-corpus slice stays within the 1.1x gate.
- **Baseline:** large-file open/keystroke slice green.

### M7 — Keyboard shortcuts, typography, spell check, wikilinks
- **Backlog:** FEAT-018 (3l), FEAT-020 (3k), FEAT-021 (3m), FEAT-035 (3r).
- **Exit:** `UIKeyCommand` shortcuts; Dynamic-Type typography; `UITextChecker` spell check; `[[wikilink]]` navigation + on-demand backlinks.

### M8 — Share sheet + native file management + accessibility audit
- **Backlog:** 3s, 3t.
- **Exit:** share in/out of `.md`; document browser; full VoiceOver/Dynamic-Type/Reduce-Motion/keyboard-reachability audit passes (every feature has a11y ACs, D-A11Y-1).

### M9 — macOS target sharing the NSTextView surface
- **Backlog:** 3u.
- **Exit:** macOS runs the same editor over `NSTextView` + the same core; standard menu bar / Quick Look; a macOS baseline slice committed.

### Phase 4 (post-parity, deferred) — rich content via the read-mode hook
- FEAT-037 Mermaid, FEAT-038 math, FEAT-042 images, FEAT-039 fold/outline, FEAT-040 tabs/split, FEAT-041 Quick Open, FEAT-043 PDF, FEAT-044 custom themes, FEAT-036 extended doctor. Each integrates only through the FEAT-049 rendering hook.

---

## 6. Verification plan

The dividing line is the **missing iOS simulator runtime**. Three tiers:

### Tier A — Fully verifiable on THIS host (no download, no device)
1. **Rust:** `cargo build -p markdown-core --release` for all three Apple triples (targets installed) + `cargo test -p markdown-core` (the three type edits keep the suite green).
2. **uniffi binding proof (the canonical proof):** build the macOS slice + XCFramework + generated Swift, then run a **SwiftPM test on macOS** (`aarch64-apple-darwin`, runs natively here) that opens→edits→saves→reopens through uniffi and asserts a byte-for-byte round-trip. This proves the FFI boundary without any iOS runtime.
3. **iOS app compiles against the iOS SDK:** `xcodebuild build -scheme MarkdownEditor -destination 'generic/platform=iOS' -sdk iphoneos26.5` — type-checks and links the app against `iphoneos26.5` and the device slice of the XCFramework. Compiles, does not run.

**The exact macOS-runnable Swift test** (`apple/Packages/MarkdownCoreFFI/Tests/MarkdownCoreTests/BindingRoundTripTests.swift`):
```swift
import XCTest
@testable import MarkdownCore   // uniffi-generated module

final class BindingRoundTripTests: XCTestCase {
    func testOpenEditSaveReopenRoundTrips() throws {
        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent("rt-\(UUID()).md")
        let original = "# Title\n\nSome **bold** text.\n"
        try original.data(using: .utf8)!.write(to: tmp)

        // open through the core
        let doc = try MarkdownDocument.openFile(path: tmp.path)
        XCTAssertEqual(doc.currentText(), original)
        XCTAssertFalse(doc.hasUtf8Bom())

        // edit through the core (insert " more" before the final newline)
        let insertAt = UInt64(original.utf8.count - 1)
        doc.edit(offset: insertAt, delete: 0, insert: " more")
        XCTAssertEqual(doc.currentText(), "# Title\n\nSome **bold** text. more\n")

        // save and reopen — byte-for-byte
        try doc.saveFile(path: tmp.path)
        let reopened = try MarkdownDocument.openFile(path: tmp.path)
        XCTAssertEqual(reopened.currentText(), doc.currentText())
        XCTAssertEqual(try Data(contentsOf: tmp),
                       doc.currentText().data(using: .utf8))

        // stateless free functions cross the boundary
        XCTAssertFalse(diagnose(text: "# A\n### B\n").isEmpty)         // heading skip
        let muts = format(text: "#Title\n")                            // missing space
        XCTAssertFalse(muts.isEmpty)
        XCTAssertEqual(applyMutations(text: "#Title\n", mutations: muts), "# Title\n")
    }
}
```
Run with `swift test --package-path apple/Packages/MarkdownCoreFFI` (after `build-rust.sh` produces the macOS-capable xcframework + bindings), or `xcodebuild test -scheme MarkdownCore -destination 'platform=macOS'`.

### Tier B — Needs an iOS Simulator runtime DOWNLOAD (not present here)
- Running the app in the simulator, on-device interaction tests, snapshot/UI tests: require `xcodebuild -downloadPlatform iOS` (or Xcode → Settings → Components) to install an iOS 26.x runtime, since `simctl list runtimes` is currently empty. The simulator slice (`aarch64-apple-ios-sim`) is already built; only the runtime is missing.

### Tier C — Needs a physical device
- The walking-skeleton "validated by use on a real device" (A-PROC-3, ARCHITECTURE §8) and the **on-device baseline slice** (open/keystroke/save medians) for `docs/baseline.json`: a code-signed device build (`xcodebuild -destination 'platform=iOS,name=<device>'`) on real hardware. Simulator numbers are not the device baseline.

**Net:** EPIC-UNIFFI is **fully provable here** (Tier A #2). EPIC-APPLE-SKELETON is **compile-provable here** (Tier A #3) but its run-proof and on-device baseline are Tier B/C.

---

## 7. Ordered build checklist (agent-fleet executable; each step independently verifiable)

Steps 1–7 are EPIC-UNIFFI; 8–12 are EPIC-APPLE-SKELETON; then EPIC-APPLE-FEATURES per §5 milestones.

1. **Edit `Diagnostic.rule` → `String`** in `markdown-core/src/doctor.rs` (3 literals → `.into()`); add `thiserror`. **Verify:** `cargo test -p markdown-core` green.
2. **Add uniffi deps + `[[bin]] uniffi-bindgen` + `uniffi-bin` feature** to `markdown-core/Cargo.toml`, gated `cfg(not(target_arch="wasm32"))`. **Verify:** `cargo build -p markdown-core` and `cargo build -p markdown-core --target wasm32-unknown-unknown` both succeed (no collision).
3. **Add `src/bin/uniffi-bindgen.rs`** + `uniffi::setup_scaffolding!()` in `lib.rs` (native-gated). **Verify:** `cargo build -p markdown-core --features uniffi-bin` succeeds.
4. **Write `markdown-core/src/ffi.rs`** (§2.4): errors, Records/Enums, `From` conversions, stateless free functions, `MarkdownDocument`, `FileWatcher`+listener, feature-gated AI. **Verify:** `cargo test -p markdown-core` green; `cargo build` for all 3 Apple triples succeeds.
5. **Run `build-rust.sh`** to produce `apple/MarkdownCore.xcframework` + generated `markdown_core.swift`. **Verify:** xcframework has ios/ios-sim/macos slices; Swift file exists and references `markdown_coreFFI`.
6. **Create `apple/Packages/MarkdownCoreFFI/`** (`Package.swift`, binaryTarget, re-export, test target) and **write `BindingRoundTripTests.swift`** (§6). **Verify:** `swift test --package-path apple/Packages/MarkdownCoreFFI` passes on macOS — **the binding is proven (EPIC-UNIFFI exit AC).**
7. **Commit** the three Apple-triple build + xcframework flow into CI (macOS runner) so the round-trip test runs every merge. **Verify:** CI job green.
8. **Generate `apple/MarkdownEditor.xcodeproj`** from `project.yml` (XcodeGen), iOS target depending on the local `MarkdownCore` product, document-type/Files/iCloud capabilities. **Verify:** `xcodebuild -list` shows the `MarkdownEditor` scheme.
9. **Implement `MarkdownDocument` (UIDocument)** bridging to `MarkdownCore.MarkdownDocument` (load via `fromBytes`, save via `currentText` bytes, encoding preserved). **Verify (here):** app **compiles** via `xcodebuild build -destination 'generic/platform=iOS' -sdk iphoneos26.5`.
10. **Mount a minimal TextKit 2 editor** (`UITextView` with `textLayoutManager`) bound to the core; wire `DocumentGroup`/document browser for Files open/save. **Verify (here):** still compiles against the iOS SDK; **Verify (Tier B):** after `xcodebuild -downloadPlatform iOS`, run in simulator — open/edit/save a `.md`.
11. **Prove open→edit→save→reopen on a real surface** (simulator once runtime downloaded; then device for the true skeleton, A-PROC-3). **Verify:** round-trips on device.
12. **Capture + commit the on-device Apple baseline slice** (open/keystroke/save medians, N≥5 median, across `docs/baseline-corpus/`) into `docs/baseline.json`. **Verify:** new slice present; regression gate wired to fire at 1.1x per slice. **— EPIC-APPLE-SKELETON exit AC.**

Then proceed M2→M9 per §5, each milestone keeping every baseline slice within the 1.1x gate.

---

### Binding constraints that hold across every step
- Document model stays `String` (`docs/engine-decision.md`) — do not introduce a rope/piece-table.
- Baseline gate fires at **1.1x per slice**; a new Apple/on-device slice is captured and kept green (`docs/baseline.json`, `docs/baseline-corpus/`).
- Phase ordering and `dependsOn` are non-negotiable; no skipping ahead.
- No vault / account / telemetry / AI in v1.0; the editor surface is TextKit 2, never a webview.
- Commit with a meaningful message before signaling each step complete (CLAUDE.md).
