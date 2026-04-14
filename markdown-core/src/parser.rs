/// Markdown parser that wraps tree-sitter-markdown and produces a typed AST.
///
/// This is the single parser for all operations in markdown-core. Every downstream
/// feature reads from the `SyntaxTree` returned by `parse()`.

use tree_sitter_md::{MarkdownCursor, MarkdownParser};

use crate::ast::{
    CheckboxState, NodeKind, PointRange, Position, Span, SyntaxNode, SyntaxTree,
};

/// Parse a markdown string into a typed `SyntaxTree`.
///
/// This is the primary entry point. The returned tree is an owned Rust struct
/// tree — not a raw tree-sitter cursor.
pub fn parse(text: &str) -> SyntaxTree {
    let mut parser = MarkdownParser::default();
    let md_tree = parser
        .parse(text.as_bytes(), None)
        .expect("tree-sitter parse should not fail without timeout/cancellation");

    let root = build_tree_from_cursor(&mut md_tree.walk(), text);
    let root = maybe_wrap_frontmatter(root, text);

    SyntaxTree { root }
}

/// Detect a leading YAML frontmatter block (`---` … `---`) and wrap it in a
/// `FrontMatter` node. tree-sitter-markdown does not natively produce a
/// frontmatter node, so we detect it ourselves.
fn maybe_wrap_frontmatter(mut root: SyntaxNode, text: &str) -> SyntaxNode {
    if !text.starts_with("---") {
        return root;
    }
    // Find closing `---` (must be on its own line after the opening).
    let after_open = &text[3..];
    let rest_start = if after_open.starts_with('\n') {
        4 // "---\n"
    } else if after_open.starts_with("\r\n") {
        5 // "---\r\n"
    } else {
        return root; // not valid frontmatter
    };
    let rest = &text[rest_start..];
    let close_pos = find_closing_frontmatter(rest);
    if close_pos.is_none() {
        return root;
    }
    let close_offset_in_rest = close_pos.unwrap();
    let fm_end = rest_start + close_offset_in_rest + 3; // include the closing "---"
    // Consume the newline after closing --- if present.
    let fm_end = if text[fm_end..].starts_with('\n') {
        fm_end + 1
    } else if text[fm_end..].starts_with("\r\n") {
        fm_end + 2
    } else {
        fm_end
    };

    let fm_text = &text[..fm_end];
    let end_row = fm_text.lines().count().saturating_sub(1);
    let last_line = fm_text.lines().last().unwrap_or("");
    let end_col = last_line.len();

    let fm_node = SyntaxNode {
        kind: NodeKind::FrontMatter,
        span: Span { start: 0, end: fm_end },
        point_range: PointRange {
            start: Position { row: 0, column: 0 },
            end: Position { row: end_row, column: end_col },
        },
        children: vec![],
        text: Some(text[rest_start..rest_start + close_offset_in_rest].trim().to_string()),
    };

    // Insert frontmatter as first child, shifting others.
    root.children.insert(0, fm_node);
    root
}

/// Find the byte offset of the closing `---` within `rest` (text after the
/// opening delimiter line). The closing delimiter must appear at the start of
/// a line.
fn find_closing_frontmatter(rest: &str) -> Option<usize> {
    let mut offset = 0;
    for line in rest.lines() {
        if line.trim_end() == "---" {
            return Some(offset);
        }
        offset += line.len() + 1; // +1 for '\n'
    }
    None
}

/// Build a `SyntaxNode` tree by walking the `MarkdownCursor` depth-first.
fn build_tree_from_cursor(cursor: &mut MarkdownCursor<'_>, source: &str) -> SyntaxNode {
    let node = cursor.node();
    let kind = map_node_kind(node.kind(), cursor, source);
    let span = Span {
        start: node.start_byte(),
        end: node.end_byte(),
    };
    let point_range = PointRange {
        start: Position {
            row: node.start_position().row,
            column: node.start_position().column,
        },
        end: Position {
            row: node.end_position().row,
            column: node.end_position().column,
        },
    };
    let text = extract_text(&kind, span, source);

    let mut children = Vec::new();
    if cursor.goto_first_child() {
        loop {
            let child_node = cursor.node();
            if child_node.is_named() {
                children.push(build_tree_from_cursor(cursor, source));
            }
            if !cursor.goto_next_sibling() {
                break;
            }
        }
        cursor.goto_parent();
    }

    SyntaxNode {
        kind,
        span,
        point_range,
        children,
        text,
    }
}

/// Map a tree-sitter node type string to our typed `NodeKind`.
///
/// Reference: `reference/TreeSitterConversion.swift` treeSitterNodeType().
/// Adapted for tree-sitter-md (split_parser branch) which uses different
/// node names than the older tree-sitter-markdown crate.
fn map_node_kind(ts_kind: &str, cursor: &MarkdownCursor<'_>, source: &str) -> NodeKind {
    match ts_kind {
        // Structural
        "document" | "section" => NodeKind::Document,

        // Headings
        "atx_heading" => {
            let level = detect_heading_level(cursor, source);
            NodeKind::Heading { level }
        }
        "setext_heading" => {
            let level = detect_setext_level(cursor, source);
            NodeKind::Heading { level }
        }

        // Block elements
        "paragraph" | "inline" => NodeKind::Paragraph,
        "block_quote" => NodeKind::BlockQuote,

        // tree-sitter-md uses "list" for both ordered and unordered lists.
        // Distinguish by inspecting list marker children.
        "list" => detect_list_kind(cursor),

        "list_item" => NodeKind::ListItem { checkbox: None },
        "task_list_marker_checked" => NodeKind::ListItem {
            checkbox: Some(CheckboxState::Checked),
        },
        "task_list_marker_unchecked" => NodeKind::ListItem {
            checkbox: Some(CheckboxState::Unchecked),
        },
        "fenced_code_block" => {
            let lang = detect_code_language(cursor, source);
            NodeKind::FencedCodeBlock { language: lang }
        }
        "indented_code_block" | "code_block" => NodeKind::IndentedCodeBlock,
        "html_block" => NodeKind::HtmlBlock,
        "thematic_break" => NodeKind::ThematicBreak,

        // Table (GFM)
        "pipe_table" => NodeKind::Table,
        "pipe_table_header" => NodeKind::TableHead,
        "pipe_table_row" => NodeKind::TableRow,
        "pipe_table_cell" => NodeKind::TableCell,
        "pipe_table_delimiter_row" => NodeKind::TableDelimiterRow,

        // Inline elements
        "text" | "text_content" => NodeKind::Text,
        "emphasis" => NodeKind::Emphasis,
        "strong_emphasis" => NodeKind::Strong,
        "strikethrough" => NodeKind::Strikethrough,
        "code_span" => NodeKind::InlineCode,
        // tree-sitter-md inline grammar uses "inline_link" for [text](url)
        "link" | "inline_link" | "full_reference_link" | "collapsed_reference_link"
        | "shortcut_link" => {
            let dest = detect_link_destination(cursor, source);
            NodeKind::Link { destination: dest }
        }
        "image" | "inline_image" => {
            let src = detect_image_source(cursor, source);
            NodeKind::Image { source: src }
        }
        "uri_autolink" | "email_autolink" => NodeKind::Autolink,
        "html_tag" | "html_open_tag" | "html_close_tag" => NodeKind::InlineHtml,
        "hard_line_break" => NodeKind::LineBreak,
        "soft_line_break" => NodeKind::SoftBreak,

        // Fallback: treat unknown nodes as paragraphs (matches Swift reference).
        _ => NodeKind::Paragraph,
    }
}

/// Detect whether a `list` node is ordered or unordered by inspecting the
/// first list marker child.
fn detect_list_kind(cursor: &MarkdownCursor<'_>) -> NodeKind {
    let node = cursor.node();
    let mut child_cursor = node.walk();
    if child_cursor.goto_first_child() {
        loop {
            let child = child_cursor.node();
            // Descend into list_item to find the marker.
            if child.kind() == "list_item" {
                let mut item_cursor = child.walk();
                if item_cursor.goto_first_child() {
                    loop {
                        let marker = item_cursor.node();
                        match marker.kind() {
                            "list_marker_minus" | "list_marker_plus" | "list_marker_star" => {
                                return NodeKind::UnorderedList;
                            }
                            "list_marker_dot" | "list_marker_parenthesis" => {
                                return NodeKind::OrderedList;
                            }
                            _ => {}
                        }
                        if !item_cursor.goto_next_sibling() {
                            break;
                        }
                    }
                }
            }
            if !child_cursor.goto_next_sibling() {
                break;
            }
        }
    }
    // Default to unordered if we can't determine.
    NodeKind::UnorderedList
}

/// Detect ATX heading level by counting '#' characters at the start.
fn detect_heading_level(cursor: &MarkdownCursor<'_>, source: &str) -> u8 {
    let node = cursor.node();
    let start = node.start_byte();
    let end = node.end_byte().min(source.len());
    let text = &source[start..end];
    let hashes = text.bytes().take_while(|&b| b == b'#').count();
    (hashes as u8).clamp(1, 6)
}

/// Detect setext heading level: `=` underline is level 1, `-` underline is level 2.
fn detect_setext_level(cursor: &MarkdownCursor<'_>, source: &str) -> u8 {
    let node = cursor.node();
    let start = node.start_byte();
    let end = node.end_byte().min(source.len());
    let text = &source[start..end];
    if let Some(last_line) = text.lines().last() {
        let trimmed = last_line.trim();
        if trimmed.starts_with('=') {
            return 1;
        }
    }
    2
}

/// Detect the info string (language) of a fenced code block.
fn detect_code_language(cursor: &MarkdownCursor<'_>, source: &str) -> Option<String> {
    let node = cursor.node();
    let mut child_cursor = node.walk();
    if child_cursor.goto_first_child() {
        loop {
            let child = child_cursor.node();
            if child.kind() == "info_string" || child.kind() == "language" {
                let start = child.start_byte();
                let end = child.end_byte().min(source.len());
                if start < end {
                    let t = source[start..end].trim();
                    if !t.is_empty() {
                        return Some(t.to_string());
                    }
                }
            }
            if !child_cursor.goto_next_sibling() {
                break;
            }
        }
    }
    None
}

/// Detect inline link destination by looking for a `link_destination` child.
fn detect_link_destination(cursor: &MarkdownCursor<'_>, source: &str) -> Option<String> {
    let node = cursor.node();
    let mut child_cursor = node.walk();
    if child_cursor.goto_first_child() {
        loop {
            let child = child_cursor.node();
            if child.kind() == "link_destination" {
                let start = child.start_byte();
                let end = child.end_byte().min(source.len());
                if start < end {
                    return Some(source[start..end].to_string());
                }
            }
            if !child_cursor.goto_next_sibling() {
                break;
            }
        }
    }
    None
}

/// Detect image source by looking for a `link_destination` child.
fn detect_image_source(cursor: &MarkdownCursor<'_>, source: &str) -> Option<String> {
    detect_link_destination(cursor, source)
}

/// Extract literal text for leaf-like nodes.
fn extract_text(kind: &NodeKind, span: Span, source: &str) -> Option<String> {
    match kind {
        NodeKind::Text | NodeKind::InlineCode | NodeKind::InlineHtml | NodeKind::Autolink => {
            if span.start < source.len() && span.end <= source.len() {
                Some(source[span.start..span.end].to_string())
            } else {
                None
            }
        }
        _ => None,
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::ast::NodeKind;

    // ── Helpers ──

    /// Find the first node of a given kind in a depth-first walk.
    fn find_kind<'a>(tree: &'a SyntaxTree, kind: &NodeKind) -> Option<&'a SyntaxNode> {
        tree.walk().find(|n| &n.kind == kind)
    }

    fn find_kind_match<'a>(
        tree: &'a SyntaxTree,
        pred: impl Fn(&NodeKind) -> bool,
    ) -> Option<&'a SyntaxNode> {
        tree.walk().find(|n| pred(&n.kind))
    }

    // ── typed_ast: prove parse() returns Rust enum variants, not raw CST ──

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

    // ── Major node kind coverage ──

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
        let items: Vec<_> = tree
            .walk()
            .filter(|n| matches!(n.kind, NodeKind::ListItem { .. }))
            .collect();
        assert!(items.len() >= 2);
    }

    #[test]
    fn parse_ordered_list() {
        let tree = parse("1. first\n2. second\n");
        assert!(find_kind(&tree, &NodeKind::OrderedList).is_some());
    }

    #[test]
    fn parse_fenced_code_block() {
        let tree = parse("```rust\nfn main() {}\n```\n");
        let cb = find_kind_match(&tree, |k| matches!(k, NodeKind::FencedCodeBlock { .. }));
        assert!(cb.is_some());
    }

    #[test]
    fn parse_fenced_code_block_language() {
        let tree = parse("```python\nprint('hi')\n```\n");
        let cb = find_kind_match(&tree, |k| matches!(k, NodeKind::FencedCodeBlock { .. })).unwrap();
        assert_eq!(
            cb.kind,
            NodeKind::FencedCodeBlock {
                language: Some("python".to_string())
            }
        );
    }

    #[test]
    fn parse_indented_code_block() {
        let tree = parse("    code line one\n    code line two\n");
        assert!(find_kind(&tree, &NodeKind::IndentedCodeBlock).is_some());
    }

    #[test]
    fn parse_thematic_break() {
        let tree = parse("text\n\n---\n");
        assert!(find_kind(&tree, &NodeKind::ThematicBreak).is_some());
    }

    #[test]
    fn parse_inline_code() {
        let tree = parse("Use `code` here.\n");
        assert!(find_kind(&tree, &NodeKind::InlineCode).is_some());
    }

    #[test]
    fn parse_link() {
        let tree = parse("[click](https://example.com)\n");
        let link = find_kind_match(&tree, |k| matches!(k, NodeKind::Link { .. }));
        assert!(link.is_some());
    }

    #[test]
    fn parse_link_destination() {
        let tree = parse("[click](https://example.com)\n");
        let link = find_kind_match(&tree, |k| matches!(k, NodeKind::Link { .. })).unwrap();
        assert_eq!(
            link.kind,
            NodeKind::Link {
                destination: Some("https://example.com".to_string())
            }
        );
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
        assert!(find_kind(&tree, &NodeKind::TableHead).is_some());
        assert!(find_kind(&tree, &NodeKind::TableRow).is_some());
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
        assert!(find_kind(&tree, &NodeKind::FrontMatter).is_some());
        let fm = find_kind(&tree, &NodeKind::FrontMatter).unwrap();
        assert!(fm.text.as_ref().unwrap().contains("title: Hello"));
    }

    #[test]
    fn no_frontmatter_for_mid_document_break() {
        // `---` that doesn't start the document is a thematic break, not frontmatter.
        let tree = parse("Some text\n\n---\n");
        assert!(find_kind(&tree, &NodeKind::FrontMatter).is_none());
    }

    // ── Spans and structure ──

    #[test]
    fn spans_are_correct() {
        let md = "hello\n";
        let tree = parse(md);
        assert_eq!(tree.root.span.start, 0);
        assert_eq!(tree.root.span.end, 6);
    }

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
        // Verify we got a rich tree, not a flat list.
        assert!(tree.walk().count() > 10);
        assert!(find_kind_match(&tree, |k| matches!(k, NodeKind::Heading { level: 1 })).is_some());
        assert!(find_kind(&tree, &NodeKind::Paragraph).is_some());
        assert!(find_kind(&tree, &NodeKind::Strong).is_some());
        assert!(find_kind(&tree, &NodeKind::Emphasis).is_some());
        assert!(find_kind(&tree, &NodeKind::UnorderedList).is_some());
        assert!(find_kind(&tree, &NodeKind::BlockQuote).is_some());
        assert!(
            find_kind_match(&tree, |k| matches!(k, NodeKind::FencedCodeBlock { .. })).is_some()
        );
        assert!(find_kind(&tree, &NodeKind::Table).is_some());
    }
}
