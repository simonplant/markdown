use std::collections::HashMap;
use std::path::PathBuf;

use crate::ast::{NodeKind, SyntaxTree};

/// Severity of a diagnostic finding.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Severity {
    Error,
    Warning,
    Hint,
}

/// A single diagnostic finding from the doctor engine.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Diagnostic {
    /// Byte offset span (start, end) into the source text.
    pub span: (usize, usize),
    /// Severity level.
    pub severity: Severity,
    /// Machine-readable rule identifier.
    pub rule: &'static str,
    /// Human-readable diagnostic message.
    pub message: String,
}

/// File-system context needed to resolve relative links.
pub struct DoctorContext {
    /// Path of the document being checked.
    pub doc_path: PathBuf,
    /// Sibling file paths available for link resolution.
    pub siblings: Vec<PathBuf>,
}

/// Run all diagnostic rules against a parsed document.
///
/// When `ctx` is `None`, rules that require file-system context (broken-link)
/// are skipped gracefully.
pub fn check(tree: &SyntaxTree, text: &str, ctx: Option<&DoctorContext>) -> Vec<Diagnostic> {
    let mut diagnostics = Vec::new();
    check_heading_hierarchy(tree, text, &mut diagnostics);
    check_duplicate_headings(tree, text, &mut diagnostics);
    check_empty_sections(tree, text, &mut diagnostics);
    check_inconsistent_list_markers(tree, text, &mut diagnostics);
    if let Some(ctx) = ctx {
        check_broken_links(tree, text, ctx, &mut diagnostics);
    }
    diagnostics
}

/// Detect heading level jumps where the level increases by more than one
/// (e.g. H1 followed directly by H3, skipping H2).
fn check_heading_hierarchy(
    tree: &SyntaxTree,
    _text: &str,
    diagnostics: &mut Vec<Diagnostic>,
) {
    let headings: Vec<_> = tree
        .walk()
        .filter_map(|node| {
            if let NodeKind::Heading { level } = node.kind {
                Some((level, node.span.start, node.span.end))
            } else {
                None
            }
        })
        .collect();

    if headings.len() < 2 {
        return;
    }

    let mut prev_level = headings[0].0;
    for &(level, start, end) in &headings[1..] {
        if level > prev_level + 1 {
            diagnostics.push(Diagnostic {
                span: (start, end),
                severity: Severity::Warning,
                rule: "heading-hierarchy",
                message: format!(
                    "Heading level jumps from H{} to H{} (expected H{} or lower)",
                    prev_level,
                    level,
                    prev_level + 1,
                ),
            });
        }
        prev_level = level;
    }
}

/// Detect two or more headings with identical normalized text at the same level.
fn check_duplicate_headings(
    tree: &SyntaxTree,
    text: &str,
    diagnostics: &mut Vec<Diagnostic>,
) {
    // Collect (level, normalized_text, span) for every heading.
    let headings: Vec<_> = tree
        .walk()
        .filter_map(|node| {
            if let NodeKind::Heading { level } = node.kind {
                let heading_text = extract_heading_text(node, text);
                let normalized = heading_text.trim().to_lowercase();
                Some((level, normalized, node.span.start, node.span.end))
            } else {
                None
            }
        })
        .collect();

    // key = "level:normalized" -> first occurrence line span
    let mut seen: HashMap<String, (usize, usize)> = HashMap::new();

    for (level, normalized, start, end) in headings {
        if normalized.is_empty() {
            continue;
        }
        let key = format!("{}:{}", level, normalized);
        if let Some(first_span) = seen.get(&key) {
            let first_line = text[..first_span.0].matches('\n').count() + 1;
            diagnostics.push(Diagnostic {
                span: (start, end),
                severity: Severity::Warning,
                rule: "duplicate-heading",
                message: format!(
                    "Duplicate heading '{}' (first occurrence at line {})",
                    &text[start..end].lines().next().unwrap_or("").trim(),
                    first_line,
                ),
            });
        } else {
            seen.insert(key, (start, end));
        }
    }
}

/// Recursively extract all text content from a heading node's children.
fn extract_heading_text(node: &crate::ast::SyntaxNode, text: &str) -> String {
    let mut result = String::new();
    collect_text(node, text, &mut result);
    result
}

fn collect_text(node: &crate::ast::SyntaxNode, text: &str, result: &mut String) {
    if let Some(ref t) = node.text {
        result.push_str(t);
    } else if node.children.is_empty() {
        // Leaf node without stored text — extract from source span.
        // Skip marker nodes like `#` for headings.
        let slice = &text[node.span.start..node.span.end];
        if !slice.chars().all(|c| c == '#' || c.is_whitespace()) {
            result.push_str(slice);
        }
    } else {
        for child in &node.children {
            collect_text(child, text, result);
        }
    }
}

/// Detect empty/orphaned sections: a heading immediately followed by a sibling
/// or shallower heading with no content between. A heading followed by a *deeper*
/// heading (a subsection) is not empty. (FEAT-036 extended doctor rule.)
fn check_empty_sections(tree: &SyntaxTree, text: &str, diagnostics: &mut Vec<Diagnostic>) {
    let mut headings: Vec<(u8, usize, usize)> = tree
        .walk()
        .filter_map(|node| match node.kind {
            NodeKind::Heading { level } => Some((level, node.span.start, node.span.end)),
            _ => None,
        })
        .collect();
    headings.sort_by_key(|h| h.1);

    for pair in headings.windows(2) {
        let (level, start, end) = pair[0];
        let (next_level, next_start, _) = pair[1];
        if next_level <= level && end <= next_start && text[end..next_start].trim().is_empty() {
            diagnostics.push(Diagnostic {
                span: (start, end),
                severity: Severity::Hint,
                rule: "empty-section",
                message: "Heading has no content before the next heading".to_string(),
            });
        }
    }
}

/// Detect a contiguous run of bullet-list lines that mixes `-`, `*`, and `+`
/// markers. CommonMark splits a marker change into separate lists, so this scans
/// the source lines (matching user intent) rather than the AST. (FEAT-036.)
fn check_inconsistent_list_markers(_tree: &SyntaxTree, text: &str, diagnostics: &mut Vec<Diagnostic>) {
    let mut byte = 0usize;
    let mut run_start: Option<usize> = None;
    let mut run_end = 0usize;
    let mut markers: Vec<char> = Vec::new();
    let mut items = 0u32;

    for line in text.split_inclusive('\n') {
        let start = byte;
        byte += line.len();
        let t = line.trim_start();
        let is_item = matches!(t.chars().next(), Some('-') | Some('*') | Some('+'))
            && matches!(t.chars().nth(1), Some(' ') | Some('\t'));
        if is_item {
            if run_start.is_none() {
                run_start = Some(start);
                markers.clear();
                items = 0;
            }
            run_end = byte;
            let m = t.chars().next().unwrap();
            if !markers.contains(&m) {
                markers.push(m);
            }
            items += 1;
        } else if t.trim().is_empty() {
            // Blank line — keep a loose list's run open.
        } else {
            flush_list_run(&mut run_start, run_end, &markers, items, diagnostics);
            markers.clear();
            items = 0;
        }
    }
    flush_list_run(&mut run_start, run_end, &markers, items, diagnostics);
}

fn flush_list_run(
    run_start: &mut Option<usize>,
    run_end: usize,
    markers: &[char],
    items: u32,
    diagnostics: &mut Vec<Diagnostic>,
) {
    if let Some(start) = run_start.take() {
        if markers.len() > 1 && items >= 2 {
            diagnostics.push(Diagnostic {
                span: (start, run_end),
                severity: Severity::Hint,
                rule: "inconsistent-list-markers",
                message: format!(
                    "List mixes markers ({}) — pick one of -, *, or +",
                    markers.iter().collect::<String>()
                ),
            });
        }
    }
}

/// Detect relative links that point to non-existent files.
fn check_broken_links(
    tree: &SyntaxTree,
    _text: &str,
    ctx: &DoctorContext,
    diagnostics: &mut Vec<Diagnostic>,
) {
    let doc_dir = ctx.doc_path.parent().unwrap_or_else(|| std::path::Path::new("."));

    for node in tree.walk() {
        let dest = match &node.kind {
            NodeKind::Link { destination } => destination.as_deref(),
            NodeKind::Image { source } => source.as_deref(),
            _ => None,
        };

        let dest = match dest {
            Some(d) if !d.is_empty() => d,
            _ => continue,
        };

        // Skip non-file destinations.
        if dest.starts_with('#')
            || dest.starts_with("http://")
            || dest.starts_with("https://")
            || dest.starts_with("mailto:")
            || dest.starts_with("tel:")
            || dest.starts_with("data:")
        {
            continue;
        }

        // Strip anchor fragment for file existence check.
        let file_part = dest.split('#').next().unwrap_or(dest);
        if file_part.is_empty() {
            continue;
        }

        let resolved = doc_dir.join(file_part);

        // Check against siblings list first, then fall back to filesystem.
        let exists = ctx.siblings.iter().any(|s| s == &resolved) || resolved.exists();

        if !exists {
            diagnostics.push(Diagnostic {
                span: (node.span.start, node.span.end),
                severity: Severity::Warning,
                rule: "broken-link",
                message: format!("Link target '{}' does not exist", dest),
            });
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::parser;

    // ── heading-hierarchy ──────────────────────────────────────────

    #[test]
    fn heading_hierarchy_clean() {
        let text = "# H1\n## H2\n### H3\n## H2 again\n# H1 again\n";
        let tree = parser::parse(text);
        let diags = check(&tree, text, None);
        let hier: Vec<_> = diags.iter().filter(|d| d.rule == "heading-hierarchy").collect();
        assert!(hier.is_empty(), "No violations expected: {:?}", hier);
    }

    #[test]
    fn heading_hierarchy_single_violation() {
        let text = "# H1\n### H3\n";
        let tree = parser::parse(text);
        let diags = check(&tree, text, None);
        let hier: Vec<_> = diags.iter().filter(|d| d.rule == "heading-hierarchy").collect();
        assert_eq!(hier.len(), 1);
        assert!(hier[0].message.contains("H1"));
        assert!(hier[0].message.contains("H3"));
    }

    #[test]
    fn heading_hierarchy_multiple_violations() {
        let text = "# H1\n### H3\n###### H6\n";
        let tree = parser::parse(text);
        let diags = check(&tree, text, None);
        let hier: Vec<_> = diags.iter().filter(|d| d.rule == "heading-hierarchy").collect();
        assert_eq!(hier.len(), 2);
    }

    #[test]
    fn heading_hierarchy_decrease_allowed() {
        // Jumping from H3 back to H1 is not a violation.
        let text = "### H3\n# H1\n";
        let tree = parser::parse(text);
        let diags = check(&tree, text, None);
        let hier: Vec<_> = diags.iter().filter(|d| d.rule == "heading-hierarchy").collect();
        assert!(hier.is_empty());
    }

    // ── duplicate-heading ──────────────────────────────────────────

    #[test]
    fn duplicate_heading_clean() {
        let text = "# Intro\n## Setup\n## Usage\n";
        let tree = parser::parse(text);
        let diags = check(&tree, text, None);
        let dups: Vec<_> = diags.iter().filter(|d| d.rule == "duplicate-heading").collect();
        assert!(dups.is_empty());
    }

    #[test]
    fn duplicate_heading_single() {
        let text = "## Setup\n## Setup\n";
        let tree = parser::parse(text);
        let diags = check(&tree, text, None);
        let dups: Vec<_> = diags.iter().filter(|d| d.rule == "duplicate-heading").collect();
        assert_eq!(dups.len(), 1);
        assert!(dups[0].message.contains("Duplicate heading"));
    }

    #[test]
    fn duplicate_heading_multiple() {
        let text = "## Setup\n## Setup\n## Setup\n";
        let tree = parser::parse(text);
        let diags = check(&tree, text, None);
        let dups: Vec<_> = diags.iter().filter(|d| d.rule == "duplicate-heading").collect();
        assert_eq!(dups.len(), 2, "Second and third are duplicates");
    }

    #[test]
    fn duplicate_heading_case_insensitive() {
        let text = "## Setup\n## setup\n";
        let tree = parser::parse(text);
        let diags = check(&tree, text, None);
        let dups: Vec<_> = diags.iter().filter(|d| d.rule == "duplicate-heading").collect();
        assert_eq!(dups.len(), 1, "Case-insensitive match");
    }

    #[test]
    fn duplicate_heading_different_levels_ok() {
        // Same text at different levels should NOT be flagged.
        let text = "# Setup\n## Setup\n";
        let tree = parser::parse(text);
        let diags = check(&tree, text, None);
        let dups: Vec<_> = diags.iter().filter(|d| d.rule == "duplicate-heading").collect();
        assert!(dups.is_empty(), "Different levels are not duplicates");
    }

    // ── broken-link ────────────────────────────────────────────────

    #[test]
    fn broken_link_clean() {
        let dir = tempfile::tempdir().unwrap();
        let doc_path = dir.path().join("doc.md");
        let sibling = dir.path().join("exists.md");
        std::fs::write(&sibling, "").unwrap();

        let text = "[link](./exists.md)\n";
        let tree = parser::parse(text);
        let ctx = DoctorContext {
            doc_path,
            siblings: vec![sibling],
        };
        let diags = check(&tree, text, Some(&ctx));
        let broken: Vec<_> = diags.iter().filter(|d| d.rule == "broken-link").collect();
        assert!(broken.is_empty());
    }

    #[test]
    fn broken_link_single() {
        let dir = tempfile::tempdir().unwrap();
        let doc_path = dir.path().join("doc.md");

        let text = "[link](./missing.md)\n";
        let tree = parser::parse(text);
        let ctx = DoctorContext {
            doc_path,
            siblings: vec![],
        };
        let diags = check(&tree, text, Some(&ctx));
        let broken: Vec<_> = diags.iter().filter(|d| d.rule == "broken-link").collect();
        assert_eq!(broken.len(), 1);
        assert!(broken[0].message.contains("missing.md"));
    }

    #[test]
    fn broken_link_multiple() {
        let dir = tempfile::tempdir().unwrap();
        let doc_path = dir.path().join("doc.md");

        let text = "[a](./missing1.md)\n[b](./missing2.md)\n";
        let tree = parser::parse(text);
        let ctx = DoctorContext {
            doc_path,
            siblings: vec![],
        };
        let diags = check(&tree, text, Some(&ctx));
        let broken: Vec<_> = diags.iter().filter(|d| d.rule == "broken-link").collect();
        assert_eq!(broken.len(), 2);
    }

    #[test]
    fn broken_link_skips_urls() {
        let dir = tempfile::tempdir().unwrap();
        let doc_path = dir.path().join("doc.md");

        let text = "[a](https://example.com)\n[b](http://example.com)\n[c](mailto:a@b.com)\n[d](#anchor)\n";
        let tree = parser::parse(text);
        let ctx = DoctorContext {
            doc_path,
            siblings: vec![],
        };
        let diags = check(&tree, text, Some(&ctx));
        let broken: Vec<_> = diags.iter().filter(|d| d.rule == "broken-link").collect();
        assert!(broken.is_empty(), "URLs and anchors should be skipped");
    }

    #[test]
    fn broken_link_skipped_without_context() {
        let text = "[link](./missing.md)\n";
        let tree = parser::parse(text);
        let diags = check(&tree, text, None);
        let broken: Vec<_> = diags.iter().filter(|d| d.rule == "broken-link").collect();
        assert!(broken.is_empty(), "No context means broken-link is skipped");
    }

    // ── clean document ─────────────────────────────────────────────

    #[test]
    fn clean_document() {
        let text = "# Title\n\n## Section 1\n\nSome text.\n\n## Section 2\n\nMore text.\n";
        let tree = parser::parse(text);
        let diags = check(&tree, text, None);
        assert!(diags.is_empty(), "Clean document should have no diagnostics: {:?}", diags);
    }

    #[test]
    fn empty_section_flagged() {
        let text = "# Title\n\n## Empty\n\n## Has content\n\nText.\n";
        let tree = parser::parse(text);
        let diags = check(&tree, text, None);
        assert!(
            diags.iter().any(|d| d.rule == "empty-section"),
            "expected empty-section: {:?}",
            diags
        );
    }

    #[test]
    fn non_empty_sections_not_flagged() {
        let text = "# Title\n\nIntro.\n\n## Section\n\nBody.\n";
        let tree = parser::parse(text);
        let diags = check(&tree, text, None);
        assert!(!diags.iter().any(|d| d.rule == "empty-section"), "{:?}", diags);
    }

    #[test]
    fn inconsistent_list_markers_flagged() {
        let text = "- one\n* two\n+ three\n";
        let tree = parser::parse(text);
        let diags = check(&tree, text, None);
        assert!(
            diags.iter().any(|d| d.rule == "inconsistent-list-markers"),
            "expected inconsistent-list-markers: {:?}",
            diags
        );
    }

    #[test]
    fn consistent_list_markers_not_flagged() {
        let text = "- one\n- two\n- three\n";
        let tree = parser::parse(text);
        let diags = check(&tree, text, None);
        assert!(
            !diags.iter().any(|d| d.rule == "inconsistent-list-markers"),
            "{:?}",
            diags
        );
    }
}
