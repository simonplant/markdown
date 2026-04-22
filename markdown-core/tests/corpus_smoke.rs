/// Smoke test that each baseline-corpus fixture opens, parses, and runs the
/// doctor without error. Gates against corpus rot — if the fixtures stop
/// representing real-user content (malformed frontmatter, missing headings,
/// etc.) this test flags it early.
///
/// Full per-slice timing metrics that gate merges live in scripts/measure_baseline.sh;
/// this test is the lightweight CI-friendly sanity check.

use markdown_core::{doctor, parser, Document};
use std::path::PathBuf;

fn corpus_dir() -> PathBuf {
    // CARGO_MANIFEST_DIR points at markdown-core/; corpus is at repo/docs/baseline-corpus.
    let mut dir = PathBuf::from(env!("CARGO_MANIFEST_DIR"));
    dir.pop(); // -> repo root
    dir.push("docs");
    dir.push("baseline-corpus");
    dir
}

fn check_fixture(name: &str, min_bytes: usize, max_bytes: usize) {
    let path = corpus_dir().join(name);
    let doc = Document::open_file(path.to_str().unwrap())
        .unwrap_or_else(|e| panic!("corpus fixture {} failed to open: {}", name, e));
    let text = doc.current_text();
    assert!(
        text.len() >= min_bytes,
        "{} is smaller than expected ({} < {})",
        name,
        text.len(),
        min_bytes
    );
    assert!(
        text.len() <= max_bytes,
        "{} is larger than expected ({} > {})",
        name,
        text.len(),
        max_bytes
    );
    let tree = parser::parse(text);
    // Parser must produce something; ensures tree-sitter doesn't choke on the
    // fixture. Doctor check is a secondary sanity pass.
    let _ = doctor::check(&tree, text, None);
}

#[test]
fn small_fixture() {
    // ~1 KB target; allow a generous range.
    check_fixture("small.md", 200, 4_000);
}

#[test]
fn medium_fixture() {
    // ~25 KB target; range 5 KB – 100 KB.
    check_fixture("medium.md", 5_000, 100_000);
}

#[test]
fn large_fixture() {
    // ~250 KB target; range 100 KB – 1 MB.
    check_fixture("large.md", 100_000, 1_024 * 1024);
}
