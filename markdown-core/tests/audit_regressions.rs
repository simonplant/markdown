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
