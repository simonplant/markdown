//! Math span detection (FEAT-038). Markdown's grammar (tree-sitter-md) does not
//! parse `$…$` / `$$…$$`, so math is found by scanning the source. The result is
//! byte-offset spans the frontends render with their own engine (SwiftMath on
//! Apple, KaTeX on web) — all detection stays in the shared core.
//!
//! Rules: `$$…$$` is display math (may span lines); `$…$` is inline math whose
//! content is non-empty, has no adjacent whitespace, and contains no newline
//! (so `$5 and $10` is not math). `\$` is a literal dollar. Math inside inline
//! code spans (backticks) and fenced code blocks is ignored.

/// A detected math region in the source.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct MathSpan {
    /// Byte offset of the opening delimiter.
    pub start: usize,
    /// Byte offset just past the closing delimiter.
    pub end: usize,
    /// True for display math (`$$…$$`), false for inline (`$…$`).
    pub display: bool,
    /// The LaTeX content between the delimiters.
    pub latex: String,
}

/// Find all math spans in `text`, in source order, non-overlapping.
pub fn find_spans(text: &str) -> Vec<MathSpan> {
    let b = text.as_bytes();
    let n = b.len();
    let mut spans = Vec::new();
    let mut i = 0;
    let mut at_line_start = true;
    let mut in_fence = false;

    while i < n {
        // Fenced code block toggling (``` or ~~~ at line start).
        if at_line_start && is_fence_marker(b, i) {
            in_fence = !in_fence;
            i = end_of_line(b, i);
            at_line_start = true;
            continue;
        }
        let c = b[i];
        if in_fence {
            at_line_start = c == b'\n';
            i += 1;
            continue;
        }
        match c {
            b'\\' => {
                // Skip the escaped character, but never skip across a newline or
                // past the end: a trailing `\` before '\n' must not swallow the
                // line break, or the next line's fence marker is missed and
                // `in_fence` desyncs for the rest of the document.
                if i + 1 >= n || b[i + 1] == b'\n' {
                    i += 1;
                } else {
                    i += 2;
                    at_line_start = false;
                }
                continue;
            }
            b'`' => {
                // Skip an inline code span: a run of N backticks closed by N backticks.
                let run = run_len(b, i, b'`');
                if let Some(close) = find_backtick_close(b, i + run, run) {
                    i = close + run;
                } else {
                    i += run;
                }
                at_line_start = false;
                continue;
            }
            b'$' => {
                if i + 1 < n && b[i + 1] == b'$' {
                    // Display math.
                    if let Some(close) = find_seq(b, i + 2, b"$$") {
                        spans.push(MathSpan {
                            start: i,
                            end: close + 2,
                            display: true,
                            latex: text[i + 2..close].to_string(),
                        });
                        i = close + 2;
                        at_line_start = false;
                        continue;
                    }
                } else if let Some(close) = find_inline_close(b, i + 1) {
                    let latex = &text[i + 1..close];
                    if valid_inline(latex) {
                        spans.push(MathSpan {
                            start: i,
                            end: close + 1,
                            display: false,
                            latex: latex.to_string(),
                        });
                        i = close + 1;
                        at_line_start = false;
                        continue;
                    }
                }
                at_line_start = false;
                i += 1;
            }
            b'\n' => {
                at_line_start = true;
                i += 1;
            }
            _ => {
                at_line_start = false;
                i += 1;
            }
        }
    }
    spans
}

fn run_len(b: &[u8], start: usize, ch: u8) -> usize {
    let mut i = start;
    while i < b.len() && b[i] == ch {
        i += 1;
    }
    i - start
}

fn is_fence_marker(b: &[u8], i: usize) -> bool {
    run_len(b, i, b'`') >= 3 || run_len(b, i, b'~') >= 3
}

fn end_of_line(b: &[u8], start: usize) -> usize {
    let mut i = start;
    while i < b.len() && b[i] != b'\n' {
        i += 1;
    }
    if i < b.len() {
        i + 1
    } else {
        i
    }
}

/// Find a closing run of exactly `run` backticks starting at/after `from`.
fn find_backtick_close(b: &[u8], from: usize, run: usize) -> Option<usize> {
    let mut i = from;
    while i < b.len() {
        if b[i] == b'`' {
            let r = run_len(b, i, b'`');
            if r == run {
                return Some(i);
            }
            i += r;
        } else {
            i += 1;
        }
    }
    None
}

/// Find the byte index of `needle` at/after `from`.
fn find_seq(b: &[u8], from: usize, needle: &[u8]) -> Option<usize> {
    if needle.is_empty() || from >= b.len() {
        return None;
    }
    let mut i = from;
    while i + needle.len() <= b.len() {
        if &b[i..i + needle.len()] == needle {
            return Some(i);
        }
        // honour escapes so `\$` doesn't close
        if b[i] == b'\\' {
            i += 2;
        } else {
            i += 1;
        }
    }
    None
}

/// Find the closing `$` for inline math, on the same line, honouring `\$`.
fn find_inline_close(b: &[u8], from: usize) -> Option<usize> {
    let mut i = from;
    while i < b.len() {
        match b[i] {
            b'\\' => i += 2,
            b'\n' => return None,
            b'$' => return Some(i),
            _ => i += 1,
        }
    }
    None
}

/// Inline math content must be non-empty, not whitespace-padded, single-line.
fn valid_inline(latex: &str) -> bool {
    !latex.is_empty()
        && !latex.starts_with(|c: char| c.is_whitespace())
        && !latex.ends_with(|c: char| c.is_whitespace())
        && !latex.contains('\n')
}

#[cfg(test)]
mod tests {
    use super::*;

    fn spans(text: &str) -> Vec<(usize, usize, bool, String)> {
        find_spans(text)
            .into_iter()
            .map(|s| (s.start, s.end, s.display, s.latex))
            .collect()
    }

    #[test]
    fn inline_math() {
        let s = spans("see $x^2$ here");
        assert_eq!(s, vec![(4, 9, false, "x^2".into())]);
    }

    #[test]
    fn display_math() {
        let s = spans("$$\\sum_{i=1}^n i$$");
        assert_eq!(s, vec![(0, 18, true, "\\sum_{i=1}^n i".into())]);
    }

    #[test]
    fn display_across_lines() {
        let s = spans("$$\na + b\n$$");
        assert_eq!(s.len(), 1);
        assert!(s[0].2);
        assert_eq!(s[0].3, "\na + b\n");
    }

    #[test]
    fn currency_is_not_math() {
        // "$5 and $10" — closing $ preceded by digit run with a space inside;
        // content "5 and " ends with space → invalid; the pair $5...$1 has a
        // space-adjacent boundary so it must not be treated as inline math.
        assert!(find_spans("it costs $5 and $10 today").is_empty());
    }

    #[test]
    fn escaped_dollar_is_literal() {
        assert!(find_spans("price is \\$5 only").is_empty());
    }

    #[test]
    fn math_in_inline_code_ignored() {
        assert!(find_spans("`$x$` is code").is_empty());
    }

    #[test]
    fn math_in_fenced_block_ignored() {
        assert!(find_spans("```\n$x$\n```\n").is_empty());
    }

    #[test]
    fn empty_inline_not_math() {
        assert!(find_spans("a $$ b").is_empty() || find_spans("a $ $ b").is_empty());
    }

    #[test]
    fn two_inline_spans() {
        let s = spans("$a$ and $b$");
        assert_eq!(s.len(), 2);
        assert_eq!(s[0].3, "a");
        assert_eq!(s[1].3, "b");
    }

    #[test]
    fn real_text_around_math() {
        let s = spans("The formula $E = mc^2$ is famous.");
        assert_eq!(s.len(), 1);
        assert_eq!(s[0].3, "E = mc^2");
    }
}
