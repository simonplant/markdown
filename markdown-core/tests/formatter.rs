/// Integration tests for the formatting engine.
///
/// Covers all five rules, idempotency, and semantic preservation.

use markdown_core::formatter::{apply_mutations, format, Mutation};
use markdown_core::parser::parse;

/// Helper: parse, format, apply mutations.
fn fmt(text: &str) -> String {
    let tree = parse(text);
    let mutations = format(&tree, text);
    apply_mutations(text, &mutations)
}

// ── Rule 1: List continuation ──────────────────────────────────────────────

#[test]
fn list_continuation_unordered() {
    let input = "- Hello\nworld\n";
    let result = fmt(input);
    assert_eq!(result, "- Hello\n  world\n");
}

#[test]
fn list_continuation_ordered() {
    let input = "1. First\nsecond line\n";
    let result = fmt(input);
    assert_eq!(result, "1. First\n   second line\n");
}

#[test]
fn list_continuation_already_correct() {
    let input = "- Hello\n  already indented\n";
    let result = fmt(input);
    assert_eq!(result, input);
}

#[test]
fn list_continuation_multiple_items() {
    let input = "- Item A\ncontinuation\n- Item B\nalso continues\n";
    let result = fmt(input);
    assert!(result.contains("- Item A\n  continuation"));
    assert!(result.contains("- Item B\n  also continues"));
}

// ── Rule 2: Table alignment ────────────────────────────────────────────────

#[test]
fn table_alignment_pads_columns() {
    let input = "| A | B |\n|---|---|\n| hello | x |\n";
    let result = fmt(input);
    let lines: Vec<&str> = result.lines().collect();
    // All lines should have equal length (properly aligned).
    assert_eq!(lines[0].len(), lines[1].len());
    assert_eq!(lines[0].len(), lines[2].len());
}

#[test]
fn table_alignment_short_separator() {
    let input = "| Name | Age |\n|-|-|\n| Alice | 30 |\n";
    let result = fmt(input);
    // Separator dashes should be at least as wide as the widest content.
    assert!(result.contains("-----"));
}

#[test]
fn table_alignment_already_aligned() {
    let input = "| A   | B   |\n| --- | --- |\n| 1   | 2   |\n";
    let result = fmt(input);
    assert_eq!(result, input);
}

#[test]
fn table_alignment_uneven_columns() {
    let input = "| Short | Very Long Header |\n|---|---|\n| a | b |\n";
    let result = fmt(input);
    let lines: Vec<&str> = result.lines().collect();
    assert_eq!(lines[0].len(), lines[2].len());
}

// ── Rule 3: Heading spacing ───────────────────────────────────────────────

#[test]
fn heading_spacing_inserts_blank_line() {
    let input = "Some text.\n# Heading\n";
    let result = fmt(input);
    assert!(
        result.contains("\n\n# Heading"),
        "Expected blank line before heading, got: {:?}",
        result
    );
}

#[test]
fn heading_spacing_preserves_existing() {
    let input = "Some text.\n\n# Heading\n";
    let result = fmt(input);
    // Should not add extra blank lines.
    assert!(!result.contains("\n\n\n"));
}

#[test]
fn heading_spacing_doc_start() {
    let input = "# First Heading\n\nContent.\n";
    let result = fmt(input);
    // No blank line inserted before doc-start heading.
    assert!(result.starts_with("# First Heading"));
}

#[test]
fn heading_spacing_multiple_headings() {
    let input = "# H1\nParagraph.\n## H2\nMore text.\n### H3\n";
    let result = fmt(input);
    assert!(result.contains("\n\n## H2"));
    assert!(result.contains("\n\n### H3"));
}

// ── Rule 4: Blank line separation ──────────────────────────────────────────

#[test]
fn blank_line_separation_code_after_paragraph() {
    let input = "Some text.\n\n```rust\nfn main() {}\n```\n";
    let result = fmt(input);
    // Already has blank line, should be preserved.
    assert!(result.contains("\n\n```rust"));
}

#[test]
fn blank_line_separation_list_after_paragraph() {
    let input = "Paragraph.\n\n- item one\n- item two\n";
    let result = fmt(input);
    assert!(result.contains("\n\n- item"));
}

#[test]
fn blank_line_separation_preserves_existing() {
    let input = "Para one.\n\nPara two.\n\n- list\n";
    let result = fmt(input);
    // Should not add extra blank lines.
    assert!(!result.contains("\n\n\n"));
}

// ── Rule 5: Trailing whitespace ────────────────────────────────────────────

#[test]
fn trailing_whitespace_spaces() {
    let input = "Hello   \nWorld\n";
    let result = fmt(input);
    assert_eq!(result, "Hello\nWorld\n");
}

#[test]
fn trailing_whitespace_tabs() {
    let input = "Hello\t\t\nWorld\n";
    let result = fmt(input);
    assert_eq!(result, "Hello\nWorld\n");
}

#[test]
fn trailing_whitespace_mixed() {
    let input = "Hello \t \nWorld\n";
    let result = fmt(input);
    assert_eq!(result, "Hello\nWorld\n");
}

#[test]
fn trailing_whitespace_no_change() {
    let input = "Clean line\nAnother clean line\n";
    let result = fmt(input);
    assert_eq!(result, input);
}

// ── Cross-rule: idempotency ────────────────────────────────────────────────

#[test]
fn format_is_idempotent() {
    let inputs = [
        "# Heading\n\nParagraph.\n\n- list item\n  continuation\n\n| A | B |\n|---|---|\n| 1 | 2 |\n",
        "Some text.\n# Heading\n\nAnother paragraph.\n",
        "- item\nwrapped\n\n1. one\n2. two\n",
        "| Name | Age |\n|-|-|\n| Alice | 30 |\n",
        "Hello   \nWorld\t\n",
        "# Title\n\n## Section\n\nParagraph one.\n\nParagraph two.\n\n- a\n- b\n\n> quote\n",
    ];

    for input in &inputs {
        let first = fmt(input);
        let second = fmt(&first);
        assert_eq!(
            first, second,
            "Not idempotent.\nInput: {:?}\nFirst pass: {:?}\nSecond pass: {:?}",
            input, first, second
        );
    }
}

// ── Cross-rule: semantic preservation ──────────────────────────────────────

#[test]
fn format_preserves_semantics() {
    let inputs = [
        "# Heading\n\nSome **bold** and *italic* text.\n\n- list\n- items\n\n> quote\n\n```rust\nfn main() {}\n```\n",
        "1. First\n2. Second\n\n| A | B |\n|---|---|\n| x | y |\n",
        "Hello   \nWorld\t\nClean\n",
    ];

    for input in &inputs {
        let result = fmt(input);
        let original: String = input.chars().filter(|c| !c.is_whitespace()).collect();
        let formatted: String = result.chars().filter(|c| !c.is_whitespace()).collect();
        assert_eq!(
            original, formatted,
            "Semantic content changed.\nInput: {:?}\nResult: {:?}",
            input, result
        );
    }
}

// ── Mutation struct ────────────────────────────────────────────────────────

#[test]
fn mutation_struct_fields() {
    let m = Mutation {
        offset: 10,
        delete: 5,
        insert: "hello".to_string(),
    };
    assert_eq!(m.offset, 10);
    assert_eq!(m.delete, 5);
    assert_eq!(m.insert, "hello");
}

#[test]
fn format_returns_vec_mutation() {
    let text = "# Heading\n";
    let tree = parse(text);
    let mutations: Vec<Mutation> = format(&tree, text);
    // Clean input should produce no mutations.
    assert!(mutations.is_empty());
}

// ── Edge cases ─────────────────────────────────────────────────────────────

#[test]
fn empty_document() {
    let result = fmt("");
    assert_eq!(result, "");
}

#[test]
fn single_heading_no_trailing() {
    let result = fmt("# Title\n");
    assert_eq!(result, "# Title\n");
}

#[test]
fn complex_document_formats_cleanly() {
    let input = "\
# Title
Paragraph right after heading.
## Section
- list item
continuation

| A | B |
|-|-|
| hello | world |
";
    let result = fmt(input);
    let second = fmt(&result);
    assert_eq!(result, second, "Complex document not idempotent");
}
