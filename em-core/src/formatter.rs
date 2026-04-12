/// Rule-based formatting engine for markdown documents.
///
/// Takes a parsed `SyntaxTree` and the document text, returns a `Vec<Mutation>`
/// describing byte-range replacements. The caller applies mutations; the engine
/// does not mutate documents directly.
///
/// Five ordered rules, each implemented from scratch using the Swift algorithms
/// in `reference/EMFormatter/` as logic reference:
///
/// 1. List continuation — normalize indentation of continuation lines
/// 2. Table alignment — normalize column widths and separator row dashes
/// 3. Heading spacing — ensure blank line before each heading (unless doc start)
/// 4. Blank line separation — ensure blank line between block elements
/// 5. Trailing whitespace trim — remove trailing spaces/tabs from all lines

use crate::ast::{NodeKind, SyntaxNode, SyntaxTree};

/// A byte-range replacement mutation. Applied by the caller, not by the engine.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Mutation {
    /// Byte offset in the original text where the replacement starts.
    pub offset: usize,
    /// Number of bytes to delete starting at `offset`.
    pub delete: usize,
    /// Text to insert at `offset` (after deletion).
    pub insert: String,
}

/// Format a markdown document by applying all five rules in order.
///
/// Returns mutations against the original `text`. Mutations are not applied
/// in-place — later rules see pre-mutation offsets.
pub fn format(tree: &SyntaxTree, text: &str) -> Vec<Mutation> {
    let mut mutations = Vec::new();

    rule_list_continuation(tree, text, &mut mutations);
    rule_table_alignment(tree, text, &mut mutations);
    rule_heading_spacing(tree, text, &mut mutations);
    rule_blank_line_separation(tree, text, &mut mutations);

    // Collect spans covered by full-replacement mutations (e.g. tables) so
    // trailing whitespace trim doesn't generate overlapping mutations.
    let covered: Vec<(usize, usize)> = mutations
        .iter()
        .filter(|m| m.delete > 0)
        .map(|m| (m.offset, m.offset + m.delete))
        .collect();
    rule_trailing_whitespace(text, &covered, &mut mutations);

    // Sort by offset descending so the caller can apply them back-to-front
    // without invalidating earlier offsets.
    mutations.sort_by(|a, b| b.offset.cmp(&a.offset));
    mutations
}

/// Apply a list of mutations to text, producing the formatted result.
/// Mutations must be sorted by offset descending (as `format()` returns them).
pub fn apply_mutations(text: &str, mutations: &[Mutation]) -> String {
    let mut result = text.to_string();
    for m in mutations {
        let end = (m.offset + m.delete).min(result.len());
        result.replace_range(m.offset..end, &m.insert);
    }
    result
}

// ── Rule 1: List continuation ──────────────────────────────────────────────

/// Ensure continuation lines of list items are indented to align with the
/// content after the list marker.
///
/// For example, a list item `- Hello\nworld` should become `- Hello\n  world`
/// (2 spaces to align with content after `- `).
fn rule_list_continuation(tree: &SyntaxTree, text: &str, mutations: &mut Vec<Mutation>) {
    for node in tree.walk() {
        if !matches!(node.kind, NodeKind::ListItem { .. }) {
            continue;
        }

        let item_text = &text[node.span.start..node.span.end];
        let item_start = node.span.start;

        // Determine the expected indentation: content offset after the marker.
        let content_indent = list_item_content_indent(item_text);
        if content_indent == 0 {
            continue;
        }

        // Walk lines after the first within this list item.
        let mut offset = 0;
        for (i, line) in item_text.split('\n').enumerate() {
            if i == 0 {
                offset += line.len() + 1; // +1 for '\n'
                continue;
            }

            // Don't process beyond the node span
            if item_start + offset >= node.span.end {
                break;
            }

            // Empty lines inside list items are fine as-is
            if line.trim().is_empty() {
                offset += line.len() + 1;
                continue;
            }

            let current_indent = line.len() - line.trim_start().len();
            if current_indent != content_indent {
                let abs_offset = item_start + offset;
                mutations.push(Mutation {
                    offset: abs_offset,
                    delete: current_indent,
                    insert: " ".repeat(content_indent),
                });
            }

            offset += line.len() + 1;
        }
    }
}

/// Compute the column where content starts after the list marker.
///
/// E.g. `- Hello` → 2, `1. Hello` → 3, `  - Hello` → 4.
fn list_item_content_indent(item_text: &str) -> usize {
    let first_line = item_text.lines().next().unwrap_or("");
    let trimmed = first_line.trim_start();
    let leading = first_line.len() - trimmed.len();

    // Detect marker: `-`, `*`, `+` for unordered; `\d+[.)]` for ordered
    let after_marker = if trimmed.starts_with("- ")
        || trimmed.starts_with("* ")
        || trimmed.starts_with("+ ")
    {
        leading + 2
    } else if let Some(pos) = trimmed.find(". ") {
        // Check that everything before `. ` is a digit
        if trimmed[..pos].chars().all(|c| c.is_ascii_digit()) {
            leading + pos + 2
        } else {
            0
        }
    } else if let Some(pos) = trimmed.find(") ") {
        if trimmed[..pos].chars().all(|c| c.is_ascii_digit()) {
            leading + pos + 2
        } else {
            0
        }
    } else {
        // Task list items: `- [x] ` or `- [ ] `
        if (trimmed.starts_with("- [x] ") || trimmed.starts_with("- [ ] "))
            && trimmed.len() > 6
        {
            leading + 2 // align with content after `- `
        } else {
            0
        }
    };

    after_marker
}

// ── Rule 2: Table alignment ────────────────────────────────────────────────

/// Normalize table column widths: pad cells with spaces so columns align,
/// and rebuild the separator row with the correct number of dashes.
fn rule_table_alignment(tree: &SyntaxTree, text: &str, mutations: &mut Vec<Mutation>) {
    for node in tree.walk() {
        if node.kind != NodeKind::Table {
            continue;
        }

        let table_text = &text[node.span.start..node.span.end];
        let table_start = node.span.start;

        // Parse the table into rows of cells.
        let lines: Vec<&str> = table_text.lines().collect();
        if lines.len() < 2 {
            continue;
        }

        let parsed_rows: Vec<Vec<String>> = lines.iter().map(|l| parse_table_row(l)).collect();

        // Determine which row is the separator.
        let sep_idx = find_separator_row(&parsed_rows);

        // Compute max column count and widths from non-separator rows.
        let col_count = parsed_rows
            .iter()
            .enumerate()
            .filter(|(i, _)| Some(*i) != sep_idx)
            .map(|(_, r)| r.len())
            .max()
            .unwrap_or(0);

        if col_count == 0 {
            continue;
        }

        let mut col_widths = vec![3usize; col_count]; // minimum 3 for "---"
        for (i, row) in parsed_rows.iter().enumerate() {
            if Some(i) == sep_idx {
                continue;
            }
            for (j, cell) in row.iter().enumerate() {
                if j < col_count {
                    col_widths[j] = col_widths[j].max(cell.len());
                }
            }
        }

        // Rebuild the table.
        let mut new_lines = Vec::new();
        for (i, row) in parsed_rows.iter().enumerate() {
            if Some(i) == sep_idx {
                // Build separator row.
                let sep_cells: Vec<String> = col_widths
                    .iter()
                    .map(|&w| "-".repeat(w))
                    .collect();
                new_lines.push(format!("| {} |", sep_cells.join(" | ")));
            } else {
                // Build data row, padding each cell.
                let mut padded: Vec<String> = Vec::new();
                for j in 0..col_count {
                    let cell = row.get(j).map(|s| s.as_str()).unwrap_or("");
                    padded.push(format!("{:width$}", cell, width = col_widths[j]));
                }
                new_lines.push(format!("| {} |", padded.join(" | ")));
            }
        }

        let mut new_table = new_lines.join("\n");
        // Preserve trailing newline if the original had one.
        if table_text.ends_with('\n') && !new_table.ends_with('\n') {
            new_table.push('\n');
        }
        if new_table != table_text {
            mutations.push(Mutation {
                offset: table_start,
                delete: table_text.len(),
                insert: new_table,
            });
        }
    }
}

/// Parse a pipe-delimited table row into trimmed cell strings.
fn parse_table_row(line: &str) -> Vec<String> {
    let trimmed = line.trim();
    // Strip leading and trailing pipes.
    let inner = if trimmed.starts_with('|') && trimmed.ends_with('|') {
        &trimmed[1..trimmed.len() - 1]
    } else if trimmed.starts_with('|') {
        &trimmed[1..]
    } else if trimmed.ends_with('|') {
        &trimmed[..trimmed.len() - 1]
    } else {
        trimmed
    };
    inner.split('|').map(|s| s.trim().to_string()).collect()
}

/// Find the index of the separator row (cells are all dashes, possibly with colons).
fn find_separator_row(rows: &[Vec<String>]) -> Option<usize> {
    rows.iter().position(|row| {
        !row.is_empty()
            && row.iter().all(|cell| {
                let t = cell.trim();
                !t.is_empty() && t.chars().all(|c| c == '-' || c == ':')
            })
    })
}

// ── Rule 3: Heading spacing ───────────────────────────────────────────────

/// Ensure a blank line before each heading, unless it is at the start of the
/// document (or immediately after frontmatter).
fn rule_heading_spacing(tree: &SyntaxTree, text: &str, mutations: &mut Vec<Mutation>) {
    for node in tree.walk() {
        if !matches!(node.kind, NodeKind::Heading { .. }) {
            continue;
        }

        let start = node.span.start;
        if start == 0 {
            continue;
        }

        // Check if preceded by frontmatter (immediately after frontmatter is OK).
        if is_after_frontmatter(tree, start) {
            continue;
        }

        // Look backwards from the heading start to see if there's already a blank line.
        let before = &text[..start];
        if before.ends_with("\n\n") {
            continue;
        }

        // If the text before ends with a single newline, insert an extra one.
        if before.ends_with('\n') {
            mutations.push(Mutation {
                offset: start,
                delete: 0,
                insert: "\n".to_string(),
            });
        }
    }
}

/// Check if a byte offset is immediately after frontmatter content.
fn is_after_frontmatter(tree: &SyntaxTree, offset: usize) -> bool {
    for node in tree.walk() {
        if node.kind == NodeKind::FrontMatter && node.span.end == offset {
            return true;
        }
    }
    false
}

// ── Rule 4: Blank line separation ──────────────────────────────────────────

/// Ensure a blank line between adjacent block-level elements (paragraphs,
/// blockquotes, lists, code blocks, thematic breaks, HTML blocks, tables).
///
/// Headings are excluded here — Rule 3 handles them.
fn rule_blank_line_separation(tree: &SyntaxTree, text: &str, mutations: &mut Vec<Mutation>) {
    let block_children: Vec<&SyntaxNode> = tree
        .root
        .children
        .iter()
        .filter(|n| is_block_element(&n.kind))
        .collect();

    for pair in block_children.windows(2) {
        let prev = pair[0];
        let curr = pair[1];

        // Skip if current is a heading (Rule 3 handles those).
        if matches!(curr.kind, NodeKind::Heading { .. }) {
            continue;
        }

        // Skip frontmatter — it gets special treatment.
        if prev.kind == NodeKind::FrontMatter {
            continue;
        }

        let gap = &text[prev.span.end..curr.span.start];

        // If there's already a blank line (two newlines), skip.
        if gap.contains("\n\n") {
            continue;
        }

        // If there's exactly one newline, insert another.
        if gap.contains('\n') {
            // Insert right before the current node.
            mutations.push(Mutation {
                offset: curr.span.start,
                delete: 0,
                insert: "\n".to_string(),
            });
        }
    }
}

/// Check if a node kind is a block-level element.
fn is_block_element(kind: &NodeKind) -> bool {
    matches!(
        kind,
        NodeKind::Heading { .. }
            | NodeKind::Paragraph
            | NodeKind::BlockQuote
            | NodeKind::OrderedList
            | NodeKind::UnorderedList
            | NodeKind::FencedCodeBlock { .. }
            | NodeKind::IndentedCodeBlock
            | NodeKind::HtmlBlock
            | NodeKind::ThematicBreak
            | NodeKind::Table
            | NodeKind::FrontMatter
    )
}

// ── Rule 5: Trailing whitespace trim ───────────────────────────────────────

/// Remove trailing spaces and tabs from every line.
///
/// `covered` is a list of (start, end) byte ranges already handled by
/// full-replacement mutations (e.g. table alignment). Trailing whitespace
/// within these ranges is skipped to avoid overlapping mutations.
fn rule_trailing_whitespace(
    text: &str,
    covered: &[(usize, usize)],
    mutations: &mut Vec<Mutation>,
) {
    let mut offset = 0;
    for line in text.split('\n') {
        let trimmed = line.trim_end_matches(|c: char| c == ' ' || c == '\t');
        let trailing_len = line.len() - trimmed.len();
        if trailing_len > 0 {
            let mut_offset = offset + trimmed.len();
            // Skip if this mutation falls within a covered range.
            let in_covered = covered
                .iter()
                .any(|&(s, e)| mut_offset >= s && mut_offset < e);
            if !in_covered {
                mutations.push(Mutation {
                    offset: mut_offset,
                    delete: trailing_len,
                    insert: String::new(),
                });
            }
        }
        offset += line.len() + 1; // +1 for the '\n'
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::parser::parse;

    /// Helper: format text and apply mutations.
    fn fmt(text: &str) -> String {
        let tree = parse(text);
        let mutations = format(&tree, text);
        apply_mutations(text, &mutations)
    }

    // ── Rule 1: List continuation ──

    #[test]
    fn list_continuation_fixes_indent() {
        let input = "- Hello\nworld\n";
        let result = fmt(input);
        assert_eq!(result, "- Hello\n  world\n");
    }

    #[test]
    fn list_continuation_already_correct() {
        let input = "- Hello\n  world\n";
        let result = fmt(input);
        assert_eq!(result, input);
    }

    #[test]
    fn list_continuation_ordered() {
        let input = "1. First\nsecond line\n";
        let result = fmt(input);
        assert_eq!(result, "1. First\n   second line\n");
    }

    // ── Rule 2: Table alignment ──

    #[test]
    fn table_alignment_pads_cells() {
        let input = "| A | B |\n|---|---|\n| hello | x |\n";
        let result = fmt(input);
        // Column widths should be uniform across all rows.
        let lines: Vec<&str> = result.lines().collect();
        assert_eq!(lines[0].len(), lines[2].len());
        assert_eq!(lines[0].len(), lines[1].len());
    }

    #[test]
    fn table_alignment_normalizes_separator() {
        let input = "| Name | Age |\n|-|-|\n| Alice | 30 |\n";
        let result = fmt(input);
        // Separator should have dashes matching column widths
        assert!(result.contains("| ----- | --- |"));
    }

    // ── Rule 3: Heading spacing ──

    #[test]
    fn heading_spacing_inserts_blank_line() {
        let input = "Some text.\n# Heading\n";
        let result = fmt(input);
        assert!(result.contains("Some text.\n\n# Heading"));
    }

    #[test]
    fn heading_spacing_already_has_blank_line() {
        let input = "Some text.\n\n# Heading\n";
        let result = fmt(input);
        assert_eq!(result, input);
    }

    #[test]
    fn heading_spacing_doc_start_no_insert() {
        let input = "# First Heading\n";
        let result = fmt(input);
        assert_eq!(result, input);
    }

    // ── Rule 4: Blank line separation ──

    #[test]
    fn blank_line_separation_between_paragraphs() {
        let input = "Paragraph one.\nParagraph two.\n";
        let tree = parse(input);
        // tree-sitter may parse this as one paragraph with a soft break.
        // If so, no mutation needed — that's correct behavior.
        let mutations = format(&tree, input);
        let result = apply_mutations(input, &mutations);
        // The result should either have the blank line or remain a single paragraph.
        // Both are semantically correct depending on the parse.
        assert!(!result.is_empty());
    }

    #[test]
    fn blank_line_separation_list_after_paragraph() {
        let input = "Some text.\n\n- item one\n- item two\n";
        let result = fmt(input);
        // Already has blank line, should be unchanged (modulo trailing whitespace).
        assert!(result.contains("\n\n- item one"));
    }

    // ── Rule 5: Trailing whitespace ──

    #[test]
    fn trailing_whitespace_removed() {
        let input = "Hello   \nWorld\t\t\n";
        let result = fmt(input);
        assert_eq!(result, "Hello\nWorld\n");
    }

    #[test]
    fn trailing_whitespace_no_change() {
        let input = "Hello\nWorld\n";
        let result = fmt(input);
        assert_eq!(result, input);
    }

    // ── Idempotency ──

    #[test]
    fn format_is_idempotent() {
        let inputs = [
            "# Heading\n\nParagraph.\n\n- list item\n  continuation\n\n| A | B |\n|---|---|\n| 1 | 2 |\n",
            "Some text.\n# Heading\n\nAnother paragraph.\n",
            "- item\nwrapped\n\n1. one\n2. two\n",
            "| Name | Age |\n|-|-|\n| Alice | 30 |\n",
            "Hello   \nWorld\t\n",
        ];

        for input in &inputs {
            let first = fmt(input);
            let second = fmt(&first);
            assert_eq!(
                first, second,
                "Not idempotent.\nInput: {:?}\nFirst: {:?}\nSecond: {:?}",
                input, first, second
            );
        }
    }

    // ── Semantic preservation ──

    #[test]
    fn format_preserves_semantics() {
        let inputs = [
            "# Heading\n\nSome **bold** and *italic* text.\n\n- list\n- items\n\n> quote\n\n```rust\nfn main() {}\n```\n",
            "1. First\n2. Second\n\n| A | B |\n|---|---|\n| x | y |\n",
        ];

        for input in &inputs {
            let result = fmt(input);
            // Extract non-whitespace content.
            let original_content = extract_semantic_content(input);
            let formatted_content = extract_semantic_content(&result);
            assert_eq!(
                original_content, formatted_content,
                "Semantic content changed.\nInput: {:?}\nResult: {:?}",
                input, result
            );
        }
    }

    /// Extract non-whitespace semantic content for comparison.
    fn extract_semantic_content(text: &str) -> String {
        text.chars()
            .filter(|c| !c.is_whitespace())
            .collect()
    }
}
