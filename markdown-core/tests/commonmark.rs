/// CommonMark spec test suite runner.
///
/// Reads the official CommonMark spec.json (652 examples), parses each through
/// markdown-core's `parse()`, renders the AST to HTML, and compares against expected
/// output. A skip-list (commonmark_skip.json) documents known divergences.
///
/// CI contract:
/// - Any unskipped failure breaks the build.
/// - Any skip-listed test that now passes is flagged (signal to remove it).

use std::collections::HashMap;
use std::path::Path;

use serde::Deserialize;

use markdown_core::ast::{NodeKind, SyntaxNode, SyntaxTree};
use markdown_core::parser::parse;

// ── Spec JSON schema ──

#[derive(Deserialize)]
struct SpecExample {
    markdown: String,
    html: String,
    example: u32,
    section: String,
}

#[derive(Deserialize)]
struct SkipEntry {
    example: u32,
    #[allow(dead_code)]
    input_fragment: String,
    #[allow(dead_code)]
    reason: String,
}

// ── HTML renderer (test-only, minimal) ──
//
// tree-sitter-md maps `inline` nodes to `Paragraph` in our AST. The actual
// text content lives in gaps between child node spans in the source. This
// renderer extracts text from the source using span arithmetic.

fn render_html(tree: &SyntaxTree, source: &str) -> String {
    let mut out = String::new();
    render_block(&tree.root, source, &mut out, false);
    out
}

/// Check if a Paragraph child of a Heading or ListItem is a marker node
/// (e.g. "#", "- ") rather than content.
fn is_marker_paragraph(node: &SyntaxNode, parent: &SyntaxNode, source: &str) -> bool {
    if !matches!(node.kind, NodeKind::Paragraph) {
        return false;
    }
    match &parent.kind {
        NodeKind::Heading { .. } => {
            // Heading marker is the first child, containing just "#"s
            let text = &source[node.span.start..node.span.end];
            text.trim().chars().all(|c| c == '#')
        }
        NodeKind::ListItem { .. } => {
            // List marker is typically the first child ("- ", "* ", "1. ", etc.)
            let text = &source[node.span.start..node.span.end];
            let trimmed = text.trim();
            trimmed == "-"
                || trimmed == "*"
                || trimmed == "+"
                || trimmed.ends_with('.')
                    && trimmed[..trimmed.len() - 1]
                        .chars()
                        .all(|c| c.is_ascii_digit())
                || trimmed.ends_with(')')
                    && trimmed[..trimmed.len() - 1]
                        .chars()
                        .all(|c| c.is_ascii_digit())
        }
        _ => false,
    }
}

fn render_block(node: &SyntaxNode, source: &str, out: &mut String, in_tight_list: bool) {
    match &node.kind {
        NodeKind::Document => {
            for child in &node.children {
                render_block(child, source, out, false);
            }
        }

        NodeKind::Heading { level } => {
            out.push_str(&format!("<h{}>", level));
            render_heading_content(node, source, out);
            out.push_str(&format!("</h{}>\n", level));
        }

        NodeKind::Paragraph => {
            // Collect inline content from this paragraph and its inline children
            let content = render_inline_content(node, source);
            let content = content.trim_end_matches('\n');
            if content.is_empty() {
                return;
            }
            if in_tight_list {
                out.push_str(content);
            } else {
                out.push_str("<p>");
                out.push_str(content);
                out.push_str("</p>\n");
            }
        }

        NodeKind::BlockQuote => {
            out.push_str("<blockquote>\n");
            for child in &node.children {
                render_block(child, source, out, false);
            }
            out.push_str("</blockquote>\n");
        }

        NodeKind::UnorderedList => {
            let tight = is_tight_list(node);
            out.push_str("<ul>\n");
            for child in &node.children {
                render_list_item(child, source, out, tight);
            }
            out.push_str("</ul>\n");
        }

        NodeKind::OrderedList => {
            let tight = is_tight_list(node);
            let start = extract_ordered_list_start(source, node);
            if start != 1 {
                out.push_str(&format!("<ol start=\"{}\">\n", start));
            } else {
                out.push_str("<ol>\n");
            }
            for child in &node.children {
                render_list_item(child, source, out, tight);
            }
            out.push_str("</ol>\n");
        }

        NodeKind::ListItem { .. } => {
            // Should be handled by render_list_item, but handle standalone
            render_list_item(node, source, out, false);
        }

        NodeKind::FencedCodeBlock { language } => {
            if let Some(lang) = language {
                out.push_str(&format!(
                    "<pre><code class=\"language-{}\">",
                    html_escape(lang)
                ));
            } else {
                out.push_str("<pre><code>");
            }
            let code = extract_fenced_code_content(source, node);
            out.push_str(&html_escape(&code));
            out.push_str("</code></pre>\n");
        }

        NodeKind::IndentedCodeBlock => {
            out.push_str("<pre><code>");
            let code = extract_indented_code_content(source, node);
            out.push_str(&html_escape(&code));
            out.push_str("</code></pre>\n");
        }

        NodeKind::HtmlBlock => {
            let html = &source[node.span.start..node.span.end];
            out.push_str(html);
            if !html.ends_with('\n') {
                out.push('\n');
            }
        }

        NodeKind::ThematicBreak => {
            out.push_str("<hr />\n");
        }

        NodeKind::Table => {
            out.push_str("<table>\n");
            for child in &node.children {
                render_block(child, source, out, false);
            }
            out.push_str("</table>\n");
        }

        NodeKind::TableHead => {
            out.push_str("<thead>\n<tr>\n");
            for cell in &node.children {
                out.push_str("<th>");
                let content = render_inline_content(cell, source);
                out.push_str(content.trim());
                out.push_str("</th>\n");
            }
            out.push_str("</tr>\n</thead>\n");
        }

        NodeKind::TableRow => {
            out.push_str("<tr>\n");
            for cell in &node.children {
                out.push_str("<td>");
                let content = render_inline_content(cell, source);
                out.push_str(content.trim());
                out.push_str("</td>\n");
            }
            out.push_str("</tr>\n");
        }

        NodeKind::TableDelimiterRow | NodeKind::TableCell | NodeKind::FrontMatter => {}

        // Inline nodes at block level — wrap in paragraph
        _ => {
            let content = render_inline_from_node(node, source);
            if !content.is_empty() {
                out.push_str("<p>");
                out.push_str(&content);
                out.push_str("</p>\n");
            }
        }
    }
}

fn render_heading_content(heading: &SyntaxNode, source: &str, out: &mut String) {
    // Skip marker children (the "#" prefix), render content children
    for child in &heading.children {
        if is_marker_paragraph(child, heading, source) {
            continue;
        }
        let content = render_inline_content(child, source);
        out.push_str(content.trim());
    }
}

fn render_list_item(node: &SyntaxNode, source: &str, out: &mut String, tight: bool) {
    out.push_str("<li>");

    // Collect content children (skip marker paragraphs)
    let content_children: Vec<&SyntaxNode> = node
        .children
        .iter()
        .filter(|c| !is_marker_paragraph(c, node, source))
        .collect();

    // Check if this list item has block-level content (loose list item)
    let has_block_content = content_children.iter().any(|c| {
        matches!(
            c.kind,
            NodeKind::BlockQuote
                | NodeKind::UnorderedList
                | NodeKind::OrderedList
                | NodeKind::FencedCodeBlock { .. }
                | NodeKind::IndentedCodeBlock
                | NodeKind::HtmlBlock
                | NodeKind::ThematicBreak
        )
    });

    if has_block_content || !tight {
        // Loose list item — render children as blocks
        out.push('\n');
        for child in &content_children {
            render_block(child, source, out, false);
        }
    } else {
        // Tight list item — render content inline
        for child in &content_children {
            let content = render_inline_content(child, source);
            let content = content.trim_end_matches('\n');
            out.push_str(content);
        }
        out.push('\n');
    }

    out.push_str("</li>\n");
}

/// Render inline content from a node by walking the source and inserting
/// HTML tags at positions indicated by child nodes.
fn render_inline_content(node: &SyntaxNode, source: &str) -> String {
    let mut out = String::new();

    if node.children.is_empty() {
        // Leaf node — extract text from source
        let text = safe_slice(source, node.span.start, node.span.end);
        out.push_str(&html_escape(text));
        return out;
    }

    let mut pos = node.span.start;

    for child in &node.children {
        // Text gap before this child
        if child.span.start > pos {
            let gap = safe_slice(source, pos, child.span.start);
            out.push_str(&html_escape(gap));
        }

        // Render the child inline
        out.push_str(&render_inline_from_node(child, source));
        pos = child.span.end;
    }

    // Trailing text after last child
    if pos < node.span.end {
        let trail = safe_slice(source, pos, node.span.end);
        out.push_str(&html_escape(trail));
    }

    out
}

fn render_inline_from_node(node: &SyntaxNode, source: &str) -> String {
    let mut out = String::new();

    match &node.kind {
        NodeKind::Paragraph => {
            // Inline container — render its content without wrapping
            out.push_str(&render_inline_content(node, source));
        }

        NodeKind::Text => {
            let text = safe_slice(source, node.span.start, node.span.end);
            out.push_str(&html_escape(text));
        }

        NodeKind::Emphasis => {
            out.push_str("<em>");
            out.push_str(&render_emphasis_content(node, source));
            out.push_str("</em>");
        }

        NodeKind::Strong => {
            out.push_str("<strong>");
            out.push_str(&render_emphasis_content(node, source));
            out.push_str("</strong>");
        }

        NodeKind::Strikethrough => {
            out.push_str("<del>");
            out.push_str(&render_emphasis_content(node, source));
            out.push_str("</del>");
        }

        NodeKind::InlineCode => {
            out.push_str("<code>");
            let raw = safe_slice(source, node.span.start, node.span.end);
            let code = strip_backtick_delimiters(raw);
            let code = strip_code_span_space(code);
            out.push_str(&html_escape(code));
            out.push_str("</code>");
        }

        NodeKind::Link { destination } => {
            let dest = destination.as_deref().unwrap_or("");
            out.push_str(&format!("<a href=\"{}\">", html_escape_attr(dest)));
            out.push_str(&render_link_content(node, source));
            out.push_str("</a>");
        }

        NodeKind::Image { source: src } => {
            let src_val = src.as_deref().unwrap_or("");
            out.push_str(&format!("<img src=\"{}\" alt=\"", html_escape_attr(src_val)));
            out.push_str(&collect_alt_text(node, source));
            out.push_str("\" />");
        }

        NodeKind::Autolink => {
            let raw = safe_slice(source, node.span.start, node.span.end);
            let url = raw.trim_start_matches('<').trim_end_matches('>');
            if url.contains('@') && !url.starts_with("mailto:") {
                out.push_str(&format!(
                    "<a href=\"mailto:{}\">{}</a>",
                    html_escape_attr(url),
                    html_escape(url)
                ));
            } else {
                out.push_str(&format!(
                    "<a href=\"{}\">{}</a>",
                    html_escape_attr(url),
                    html_escape(url)
                ));
            }
        }

        NodeKind::InlineHtml => {
            let text = safe_slice(source, node.span.start, node.span.end);
            out.push_str(text); // raw HTML, no escaping
        }

        NodeKind::LineBreak => {
            out.push_str("<br />\n");
        }

        NodeKind::SoftBreak => {
            out.push('\n');
        }

        _ => {
            // Unknown inline — output raw text escaped
            let text = safe_slice(source, node.span.start, node.span.end);
            out.push_str(&html_escape(text));
        }
    }

    out
}

/// Render content inside emphasis/strong/strikethrough.
/// The child Paragraph nodes include the delimiter markers (* or ** etc.)
/// which we need to skip.
fn render_emphasis_content(node: &SyntaxNode, source: &str) -> String {
    if node.children.is_empty() {
        let text = safe_slice(source, node.span.start, node.span.end);
        return html_escape(text);
    }

    // Determine delimiter length from the first character
    let raw = safe_slice(source, node.span.start, node.span.end);
    let delim_char = raw.chars().next().unwrap_or('*');
    let delim_len = raw.chars().take_while(|&c| c == delim_char).count();

    // Content is between opening delimiter and closing delimiter
    let content_start = node.span.start + delim_len;
    let content_end = node.span.end.saturating_sub(delim_len);

    if content_start >= content_end {
        return String::new();
    }

    // Build a virtual content region and render inline children within it
    let mut out = String::new();
    let mut pos = content_start;

    for child in &node.children {
        // Skip children that are the delimiter markers themselves
        if child.span.end <= content_start || child.span.start >= content_end {
            continue;
        }

        if child.span.start > pos {
            let gap = safe_slice(source, pos, child.span.start);
            out.push_str(&html_escape(gap));
        }

        out.push_str(&render_inline_from_node(child, source));
        pos = child.span.end;
    }

    if pos < content_end {
        let trail = safe_slice(source, pos, content_end);
        out.push_str(&html_escape(trail));
    }

    out
}

/// Render the visible text content of a link (between [] and before ()).
fn render_link_content(node: &SyntaxNode, source: &str) -> String {
    // Find the text between [ and ]( in the source
    let raw = safe_slice(source, node.span.start, node.span.end);

    // For inline links [text](url), extract the text part
    if let Some(bracket_end) = raw.find("](") {
        let text = &raw[1..bracket_end]; // skip opening [
        return html_escape(text);
    }

    // For other link types, try to render children
    render_inline_content(node, source)
}

fn collect_alt_text(node: &SyntaxNode, source: &str) -> String {
    let mut out = String::new();
    for child in &node.children {
        match &child.kind {
            NodeKind::Text => {
                let text = safe_slice(source, child.span.start, child.span.end);
                out.push_str(&html_escape(text));
            }
            _ => out.push_str(&collect_alt_text(child, source)),
        }
    }
    out
}

// ── Helpers ──

fn safe_slice<'a>(source: &'a str, start: usize, end: usize) -> &'a str {
    let start = start.min(source.len());
    let end = end.min(source.len());
    if start > end {
        return "";
    }
    &source[start..end]
}

/// Determine if a list is "tight" (no blank lines between items).
fn is_tight_list(node: &SyntaxNode) -> bool {
    // Simple heuristic: if any list item has multiple block-level paragraphs,
    // the list is loose. We approximate by checking if list items contain
    // sub-block elements.
    for item in &node.children {
        if !matches!(item.kind, NodeKind::ListItem { .. }) {
            continue;
        }
        let paragraph_count = item
            .children
            .iter()
            .filter(|c| matches!(c.kind, NodeKind::Paragraph))
            .count();
        // More than 2 paragraphs (marker + content) suggests loose
        if paragraph_count > 2 {
            return false;
        }
    }
    true
}

fn html_escape(s: &str) -> String {
    s.replace('&', "&amp;")
        .replace('<', "&lt;")
        .replace('>', "&gt;")
        .replace('"', "&quot;")
}

fn html_escape_attr(s: &str) -> String {
    html_escape(s)
}

fn strip_backtick_delimiters(s: &str) -> &str {
    let backtick_count = s.chars().take_while(|&c| c == '`').count();
    if backtick_count == 0 || s.len() < backtick_count * 2 {
        return s;
    }
    &s[backtick_count..s.len() - backtick_count]
}

fn strip_code_span_space(s: &str) -> &str {
    if s.len() >= 2
        && s.starts_with(' ')
        && s.ends_with(' ')
        && s.chars().any(|c| c != ' ')
    {
        &s[1..s.len() - 1]
    } else {
        s
    }
}

fn extract_ordered_list_start(source: &str, node: &SyntaxNode) -> u32 {
    let text = safe_slice(source, node.span.start, node.span.end);
    let first_line = text.lines().next().unwrap_or("");
    let num_str: String = first_line
        .trim_start()
        .chars()
        .take_while(|c| c.is_ascii_digit())
        .collect();
    num_str.parse().unwrap_or(1)
}

fn extract_fenced_code_content(source: &str, node: &SyntaxNode) -> String {
    let raw = safe_slice(source, node.span.start, node.span.end);
    let lines: Vec<&str> = raw.lines().collect();
    if lines.len() < 2 {
        return String::new();
    }
    // Strip first line (opening fence) and last line if it's a closing fence
    let last_is_fence = lines.last().map_or(false, |l| {
        let t = l.trim();
        t.len() >= 3 && t.chars().all(|c| c == '`' || c == '~')
    });
    let content_lines = if last_is_fence {
        &lines[1..lines.len() - 1]
    } else {
        &lines[1..]
    };
    let mut result = content_lines.join("\n");
    if !result.is_empty() {
        result.push('\n');
    }
    result
}

fn extract_indented_code_content(source: &str, node: &SyntaxNode) -> String {
    let raw = safe_slice(source, node.span.start, node.span.end);
    let mut lines: Vec<String> = Vec::new();
    for line in raw.lines() {
        // Remove up to 4 leading spaces or 1 leading tab
        let stripped = if line.starts_with("    ") {
            &line[4..]
        } else if line.starts_with('\t') {
            &line[1..]
        } else {
            line
        };
        lines.push(stripped.to_string());
    }
    // Remove trailing blank lines
    while lines.last().map_or(false, |l| l.trim().is_empty()) {
        lines.pop();
    }
    let mut result = lines.join("\n");
    if !result.is_empty() {
        result.push('\n');
    }
    result
}

// ── Test runner ──

fn load_spec_examples() -> Vec<SpecExample> {
    let spec_path = Path::new(env!("CARGO_MANIFEST_DIR"))
        .join("tests")
        .join("fixtures")
        .join("spec.json");
    let data = std::fs::read_to_string(&spec_path)
        .unwrap_or_else(|e| panic!("Failed to read spec.json at {:?}: {}", spec_path, e));
    serde_json::from_str(&data).expect("Failed to parse spec.json")
}

fn load_skip_list() -> HashMap<u32, String> {
    let skip_path = Path::new(env!("CARGO_MANIFEST_DIR"))
        .join("tests")
        .join("commonmark_skip.json");
    let data = std::fs::read_to_string(&skip_path)
        .unwrap_or_else(|e| panic!("Failed to read commonmark_skip.json at {:?}: {}", skip_path, e));
    let entries: Vec<SkipEntry> =
        serde_json::from_str(&data).expect("Failed to parse commonmark_skip.json");
    entries.into_iter().map(|e| (e.example, e.reason)).collect()
}

fn normalize_html(html: &str) -> String {
    html.trim().to_string()
}

#[test]
fn commonmark_spec_suite() {
    let examples = load_spec_examples();
    let skip_list = load_skip_list();

    assert!(
        examples.len() > 600,
        "Expected 600+ spec examples, got {}",
        examples.len()
    );

    let mut passed = 0u32;
    let mut failed = 0u32;
    let mut skipped = 0u32;
    let mut skip_now_passing = Vec::new();
    let mut unskipped_failures = Vec::new();

    for ex in &examples {
        let is_skipped = skip_list.contains_key(&ex.example);

        let tree = parse(&ex.markdown);
        let actual_html = render_html(&tree, &ex.markdown);
        let matches = normalize_html(&actual_html) == normalize_html(&ex.html);

        if is_skipped {
            skipped += 1;
            if matches {
                skip_now_passing.push(ex.example);
            }
        } else if matches {
            passed += 1;
        } else {
            failed += 1;
            unskipped_failures.push((
                ex.example,
                ex.section.clone(),
                ex.markdown.clone(),
                ex.html.clone(),
                actual_html,
            ));
        }
    }

    // Report summary
    let total = examples.len() as u32;
    eprintln!();
    eprintln!("═══ CommonMark spec results ═══");
    eprintln!("Total:   {}", total);
    eprintln!(
        "Passed:  {} ({:.1}%)",
        passed,
        (passed as f64 / total as f64) * 100.0
    );
    eprintln!("Failed:  {} (unskipped)", failed);
    eprintln!("Skipped: {} (in skip-list)", skipped);
    eprintln!();

    // Report skip-listed tests that now pass
    if !skip_now_passing.is_empty() {
        eprintln!(
            "WARNING: {} skip-listed test(s) now PASS — consider removing from skip-list:",
            skip_now_passing.len()
        );
        for num in &skip_now_passing {
            eprintln!("  - Example {}", num);
        }
        eprintln!();
    }

    // Report unskipped failures (limit output for readability)
    if !unskipped_failures.is_empty() {
        eprintln!("UNSKIPPED FAILURES:");
        for (num, section, md, expected, actual) in unskipped_failures.iter().take(20) {
            eprintln!("  Example {} (§{}):", num, section);
            eprintln!("    Input:    {:?}", md);
            eprintln!("    Expected: {:?}", expected);
            eprintln!("    Actual:   {:?}", actual);
        }
        if unskipped_failures.len() > 20 {
            eprintln!("  ... and {} more", unskipped_failures.len() - 20);
        }
        eprintln!();
    }

    // CI contract: fail on any unskipped failure
    assert_eq!(
        failed, 0,
        "{} CommonMark spec test(s) failed without skip-list entry. \
         Add them to commonmark_skip.json or fix the renderer.",
        failed
    );

    // CI contract: fail if skip-listed tests now pass (keep the list clean)
    assert!(
        skip_now_passing.is_empty(),
        "{} skip-listed test(s) now pass — remove them from commonmark_skip.json: {:?}",
        skip_now_passing.len(),
        skip_now_passing
    );
}
