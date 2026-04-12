/// Integration tests for the tree-sitter markdown parser.
///
/// These tests exercise `em_core::parser::parse()` and verify it returns a
/// typed AST (Rust enum variants), not a raw tree-sitter CST.

use em_core::ast::{CheckboxState, NodeKind, SyntaxNode, SyntaxTree};
use em_core::parser::parse;

// ── Helpers ──

fn find_kind<'a>(tree: &'a SyntaxTree, kind: &NodeKind) -> Option<&'a SyntaxNode> {
    tree.walk().find(|n| &n.kind == kind)
}

fn find_kind_match<'a>(
    tree: &'a SyntaxTree,
    pred: impl Fn(&NodeKind) -> bool,
) -> Option<&'a SyntaxNode> {
    tree.walk().find(|n| pred(&n.kind))
}

// ── typed_ast: prove parse() returns Rust enum variants ──

#[test]
fn typed_ast_heading() {
    let tree = parse("# Hello\n");
    let h = find_kind_match(&tree, |k| matches!(k, NodeKind::Heading { .. })).unwrap();
    assert_eq!(h.kind, NodeKind::Heading { level: 1 });
}

#[test]
fn typed_ast_paragraph() {
    let tree = parse("Just some text.\n");
    assert!(find_kind(&tree, &NodeKind::Paragraph).is_some());
}

#[test]
fn typed_ast_emphasis_and_strong() {
    let tree = parse("*em* **strong**\n");
    assert!(find_kind(&tree, &NodeKind::Emphasis).is_some());
    assert!(find_kind(&tree, &NodeKind::Strong).is_some());
}

// ── Block elements ──

#[test]
fn parse_headings_all_levels() {
    for level in 1u8..=6 {
        let md = format!("{} Heading {}\n", "#".repeat(level as usize), level);
        let tree = parse(&md);
        let h = find_kind_match(&tree, |k| matches!(k, NodeKind::Heading { .. })).unwrap();
        assert_eq!(h.kind, NodeKind::Heading { level });
    }
}

#[test]
fn parse_setext_headings() {
    let tree = parse("Level 1\n=======\n\nLevel 2\n-------\n");
    let headings: Vec<_> = tree
        .walk()
        .filter(|n| matches!(n.kind, NodeKind::Heading { .. }))
        .collect();
    assert_eq!(headings.len(), 2);
    assert_eq!(headings[0].kind, NodeKind::Heading { level: 1 });
    assert_eq!(headings[1].kind, NodeKind::Heading { level: 2 });
}

#[test]
fn parse_blockquote() {
    let tree = parse("> quoted text\n");
    assert!(find_kind(&tree, &NodeKind::BlockQuote).is_some());
}

#[test]
fn parse_unordered_list() {
    let tree = parse("- item one\n- item two\n");
    assert!(find_kind(&tree, &NodeKind::UnorderedList).is_some());
}

#[test]
fn parse_ordered_list() {
    let tree = parse("1. first\n2. second\n");
    assert!(find_kind(&tree, &NodeKind::OrderedList).is_some());
}

#[test]
fn parse_fenced_code_block() {
    let tree = parse("```rust\nfn main() {}\n```\n");
    assert!(find_kind_match(&tree, |k| matches!(k, NodeKind::FencedCodeBlock { .. })).is_some());
}

#[test]
fn parse_indented_code_block() {
    let tree = parse("    code line\n");
    assert!(find_kind(&tree, &NodeKind::IndentedCodeBlock).is_some());
}

#[test]
fn parse_thematic_break() {
    let tree = parse("text\n\n---\n");
    assert!(find_kind(&tree, &NodeKind::ThematicBreak).is_some());
}

// ── Inline elements ──

#[test]
fn parse_inline_code() {
    let tree = parse("Use `code` here.\n");
    assert!(find_kind(&tree, &NodeKind::InlineCode).is_some());
}

#[test]
fn parse_link() {
    let tree = parse("[click](https://example.com)\n");
    assert!(find_kind_match(&tree, |k| matches!(k, NodeKind::Link { .. })).is_some());
}

#[test]
fn parse_image() {
    let tree = parse("![alt](image.png)\n");
    assert!(find_kind_match(&tree, |k| matches!(k, NodeKind::Image { .. })).is_some());
}

// ── GFM extensions ──

#[test]
fn parse_table_gfm() {
    let md = "| A | B |\n|---|---|\n| 1 | 2 |\n";
    let tree = parse(md);
    assert!(find_kind(&tree, &NodeKind::Table).is_some());
    assert!(find_kind(&tree, &NodeKind::TableCell).is_some());
}

#[test]
fn parse_strikethrough() {
    let tree = parse("~~deleted~~\n");
    assert!(find_kind(&tree, &NodeKind::Strikethrough).is_some());
}

#[test]
fn parse_task_list() {
    let md = "- [x] done\n- [ ] todo\n";
    let tree = parse(md);
    let items: Vec<_> = tree
        .walk()
        .filter(|n| matches!(n.kind, NodeKind::ListItem { checkbox: Some(_) }))
        .collect();
    assert!(items.len() >= 2);
    assert!(items.iter().any(|n| n.kind
        == NodeKind::ListItem {
            checkbox: Some(CheckboxState::Checked)
        }));
    assert!(items.iter().any(|n| n.kind
        == NodeKind::ListItem {
            checkbox: Some(CheckboxState::Unchecked)
        }));
}

// ── Frontmatter ──

#[test]
fn parse_yaml_frontmatter() {
    let md = "---\ntitle: Hello\ndate: 2024-01-01\n---\n\n# Content\n";
    let tree = parse(md);
    let fm = find_kind(&tree, &NodeKind::FrontMatter).unwrap();
    assert!(fm.text.as_ref().unwrap().contains("title: Hello"));
}

// ── Structure ──

#[test]
fn empty_document() {
    let tree = parse("");
    assert!(matches!(tree.root.kind, NodeKind::Document));
}

#[test]
fn complex_document() {
    let md = "\
# Title

A paragraph with **bold** and *italic*.

- item one
- item two

> blockquote

```python
print('hi')
```

| Col A | Col B |
|-------|-------|
| 1     | 2     |
";
    let tree = parse(md);
    assert!(tree.walk().count() > 10);
    assert!(find_kind_match(&tree, |k| matches!(k, NodeKind::Heading { level: 1 })).is_some());
    assert!(find_kind(&tree, &NodeKind::Paragraph).is_some());
    assert!(find_kind(&tree, &NodeKind::Strong).is_some());
    assert!(find_kind(&tree, &NodeKind::Emphasis).is_some());
    assert!(find_kind(&tree, &NodeKind::UnorderedList).is_some());
    assert!(find_kind(&tree, &NodeKind::BlockQuote).is_some());
    assert!(find_kind_match(&tree, |k| matches!(k, NodeKind::FencedCodeBlock { .. })).is_some());
    assert!(find_kind(&tree, &NodeKind::Table).is_some());
}
