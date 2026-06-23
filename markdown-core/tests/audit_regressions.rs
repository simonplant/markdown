//! Regression tests for bugs found in the deep code audit.
//! Each test pins a specific defect so it cannot silently return.

use std::fs;

use markdown_core::ast::NodeKind;
use markdown_core::doctor::{check, DoctorContext};
use markdown_core::formatter::{apply_mutations, format};
use markdown_core::parser::parse;

fn fmt(text: &str) -> String {
    let tree = parse(text);
    let mutations = format(&tree, text);
    apply_mutations(text, &mutations)
}

// ── parser: CRLF frontmatter offset drift (critical: panicked on non-ASCII) ──

#[test]
fn crlf_frontmatter_with_non_ascii_does_not_panic() {
    // CRLF line endings + multibyte UTF-8 in the body previously drifted the
    // byte offset into the middle of a char and panicked on slice.
    let input = "---\r\ntitle: Tést\r\nauthor: José\r\n---\r\n\r\nBody ćontent\r\n";
    let tree = parse(input); // must not panic
    let fm = tree
        .walk()
        .find(|n| matches!(n.kind, NodeKind::FrontMatter))
        .expect("frontmatter node should be detected");
    let body = fm.text.clone().unwrap_or_default();
    assert!(body.contains("title: Tést"), "frontmatter truncated: {body:?}");
    assert!(body.contains("author: José"), "frontmatter truncated: {body:?}");
}

// ── formatter: GFM column alignment markers must survive reformatting ──

#[test]
fn table_alignment_markers_preserved() {
    let input = "| h | h |\n| :-- | --: |\n| a | b |\n";
    let out = fmt(input);
    assert!(out.contains(":--"), "left alignment marker lost: {out:?}");
    assert!(out.contains("--:"), "right alignment marker lost: {out:?}");
}

// ── formatter: a backslash-escaped pipe must not split a cell ──

#[test]
fn table_escaped_pipe_not_split_into_columns() {
    let input = "| A | B |\n| --- | --- |\n| a\\|b | y |\n";
    let out = fmt(input);
    assert!(
        out.contains("a\\|b"),
        "escaped pipe was split into separate columns: {out:?}"
    );
}

// ── doctor: list-marker rule must ignore code blocks ──

#[test]
fn list_markers_inside_code_fence_not_flagged() {
    let input = "```\n- dash\n* star\n```\n";
    let tree = parse(input);
    let diags = check(&tree, input, None);
    assert!(
        diags.iter().all(|d| d.rule != "inconsistent-list-markers"),
        "bullet lines inside a code fence wrongly flagged: {diags:?}"
    );
}

#[test]
fn list_markers_genuine_mix_still_flagged() {
    // Positive control: a real mixed-marker list still triggers the rule.
    let input = "- one\n* two\n";
    let tree = parse(input);
    let diags = check(&tree, input, None);
    assert!(
        diags.iter().any(|d| d.rule == "inconsistent-list-markers"),
        "genuine mixed-marker list should still be flagged: {diags:?}"
    );
}

// ── doctor: percent-encoded and angle-bracket links resolve to real files ──

#[test]
fn percent_encoded_link_to_existing_file_is_not_broken() {
    let dir = tempfile::tempdir().unwrap();
    fs::write(dir.path().join("my file.md"), "x").unwrap();
    let text = "[x](./my%20file.md)\n";
    let tree = parse(text);
    let ctx = DoctorContext {
        doc_path: dir.path().join("doc.md"),
        siblings: vec![],
    };
    let diags = check(&tree, text, Some(&ctx));
    assert!(
        diags.iter().all(|d| d.rule != "broken-link"),
        "percent-encoded link to an existing file wrongly flagged: {diags:?}"
    );
}

#[test]
fn angle_bracket_link_to_existing_file_is_not_broken() {
    let dir = tempfile::tempdir().unwrap();
    fs::write(dir.path().join("file.md"), "x").unwrap();
    let text = "[x](<file.md>)\n";
    let tree = parse(text);
    let ctx = DoctorContext {
        doc_path: dir.path().join("doc.md"),
        siblings: vec![],
    };
    let diags = check(&tree, text, Some(&ctx));
    assert!(
        diags.iter().all(|d| d.rule != "broken-link"),
        "pointy-bracket link to an existing file wrongly flagged: {diags:?}"
    );
}

// ── math: a trailing backslash must not swallow the newline / fence opener ──

#[test]
fn math_inside_fence_after_trailing_backslash_not_detected() {
    let spans = markdown_core::math::find_spans("a\\\n~~~\n$x$\n~~~\n");
    assert!(
        spans.is_empty(),
        "math leaked out of a code fence after a trailing backslash: {spans:?}"
    );
}

#[test]
fn math_plain_inline_still_detected() {
    // Positive control: ordinary inline math still parses.
    let spans = markdown_core::math::find_spans("see $x+1$ here\n");
    assert_eq!(spans.len(), 1, "inline math should still be detected: {spans:?}");
}

// ── round 2 ──────────────────────────────────────────────────────────────

// formatter: nested lists must be idempotent and never delete content (critical).

#[test]
fn nested_list_format_is_idempotent_and_lossless() {
    for input in ["- outer\n  - inner\nlazy\n", "- a\nx\n  - b\ny\n", "- a\n  - b\nc\n"] {
        let once = fmt(input);
        let twice = fmt(&once);
        assert_eq!(once, twice, "format not idempotent for {input:?}: {once:?} -> {twice:?}");
        // every original content char survives the round trip
        for token in input.split(|c: char| c.is_whitespace()).filter(|s| !s.is_empty()) {
            if token != "-" {
                assert!(twice.contains(token), "lost {token:?} from {input:?}: got {twice:?}");
            }
        }
    }
}

// parser: a ~300-deep blockquote must not abort the process (tree-sitter scanner
// assert -> SIGABRT / WASM trap). This test crashes the runner if unguarded.

#[test]
fn deeply_nested_blockquotes_do_not_abort() {
    let input = format!("{} x\n", ">".repeat(300));
    let tree = parse(&input);
    let _ = format(&tree, &input);
    let _ = check(&tree, &input, None);
}

// parser: frontmatter bytes represented exactly once (no phantom paragraph).

#[test]
fn frontmatter_is_not_duplicated_in_ast() {
    let input = "---\ntitle: Doc\ndate: 2024\n---\n\n# Body\n";
    let tree = parse(input);
    let covering = tree.root.children.iter().filter(|c| c.span.start == 0).count();
    assert_eq!(covering, 1, "frontmatter bytes covered by >1 node: {:?}",
        tree.root.children.iter().map(|c| (c.span.start, c.span.end)).collect::<Vec<_>>());
    assert!(matches!(tree.root.children[0].kind, NodeKind::FrontMatter));
}

// parser: frontmatter span.end and point_range.end name the same location.

#[test]
fn frontmatter_span_and_point_range_agree() {
    let input = "---\nk: v\n---\n";
    let tree = parse(input);
    let fm = &tree.root.children[0];
    assert!(matches!(fm.kind, NodeKind::FrontMatter));
    assert_eq!(fm.span.end, input.len());
    assert_eq!(fm.point_range.end.row, 3);
    assert_eq!(fm.point_range.end.column, 0);
}

// doctor: a nested sublist using a different marker per depth is valid, not mixed.

#[test]
fn nested_sublist_different_markers_not_flagged() {
    for input in ["- a\n  * b\n- c\n", "- a\n  * b\n  * d\n- c\n"] {
        let tree = parse(input);
        let diags = check(&tree, input, None);
        assert!(
            diags.iter().all(|d| d.rule != "inconsistent-list-markers"),
            "nested per-depth markers wrongly flagged for {input:?}: {diags:?}"
        );
    }
}

// doctor: a heading inside a blockquote is quoted material, not part of the outline.

#[test]
fn heading_inside_blockquote_not_flagged_for_hierarchy() {
    let input = "# Title\n\n> ### Quoted deep heading\n";
    let tree = parse(input);
    let diags = check(&tree, input, None);
    assert!(
        diags.iter().all(|d| d.rule != "heading-hierarchy"),
        "quoted heading wrongly flagged: {diags:?}"
    );
}
