//! WASI smoke binary (EPIC-WASM, BUILD_PLAN Phase 1).
//!
//! Proves the headless core runs *inside* WebAssembly, not just that it
//! compiles. Built for `wasm32-wasip1` and executed under wasmtime, it opens a
//! real `.md` file through the core, parses it with tree-sitter, runs the doctor
//! and the formatter, and prints the counts. If this runs, tree-sitter parsing,
//! the document model, diagnostics, and formatting all work in WASM.
//!
//! ```sh
//! cargo build -p markdown-core --bin wasm_smoke --target wasm32-wasip1
//! wasmtime run --dir=. target/wasm32-wasip1/debug/wasm_smoke.wasm \
//!     docs/baseline-corpus/medium.md
//! ```

fn main() {
    let path = std::env::args()
        .nth(1)
        .expect("usage: wasm_smoke <file.md>");

    let doc = markdown_core::Document::open_file(&path)
        .unwrap_or_else(|e| panic!("open {path}: {e}"));
    let text = doc.current_text();

    let tree = markdown_core::parser::parse(text);
    let diagnostics = markdown_core::doctor::check(&tree, text, None);
    let mutations = markdown_core::formatter::format(&tree, text);

    println!(
        "wasm_smoke OK: file={path} bytes={} diagnostics={} format_mutations={}",
        text.len(),
        diagnostics.len(),
        mutations.len()
    );
}
