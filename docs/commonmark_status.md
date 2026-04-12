# CommonMark Spec Compliance Status

Spec version: [CommonMark 0.31.2](https://spec.commonmark.org/0.31.2/)

## Summary

| Metric  | Count | Percentage |
|---------|------:|------------|
| Total   |   652 |            |
| Passed  |   305 | 46.8%      |
| Skipped |   347 | 53.2%      |
| Failed  |     0 | 0%         |

**Pass rate: 46.8%** (305 of 652 examples)

Zero unexplained failures. Every failing test is in the skip-list with a documented reason.

## How It Works

The test runner (`em-core/tests/commonmark.rs`) loads the official CommonMark spec examples from `em-core/tests/fixtures/spec.json`, parses each markdown input through `em_core::parser::parse()`, renders the AST to HTML via a test-only renderer, and compares against the expected HTML output.

A skip-list (`em-core/tests/commonmark_skip.json`) documents known divergences. The CI contract:
- Any test that fails without a skip-list entry **breaks the build**.
- Any skip-listed test that starts passing is flagged in test output (signal to remove it from the list).

## Skip-List Breakdown by Category

| Category | Count | Root Cause |
|----------|------:|------------|
| Links | 76 | tree-sitter link parsing divergence; reference link resolution not supported by AST |
| List items | 42 | tree-sitter list item parsing divergence (nesting, continuation, blank lines) |
| Link reference definitions | 27 | tree-sitter does not resolve reference links; AST lacks reference definitions |
| Block quotes | 24 | tree-sitter block quote nesting or lazy continuation divergence |
| Lists | 24 | tree-sitter list tightness detection or continuation divergence |
| Emphasis and strong emphasis | 22 | tree-sitter emphasis/strong parsing or test renderer inline extraction divergence |
| Setext headings | 21 | tree-sitter setext heading boundary detection divergence |
| Images | 21 | tree-sitter image parsing divergence; reference resolution not in AST |
| HTML blocks | 12 | tree-sitter HTML block boundary detection divergence |
| Entity/numeric character references | 11 | AST does not decode HTML entities; tree-sitter treats them as literal text |
| Fenced code blocks | 9 | tree-sitter fenced code block parsing or test renderer fence stripping divergence |
| ATX headings | 8 | tree-sitter ATX heading parsing or test renderer content extraction divergence |
| Code spans | 8 | tree-sitter code span boundary or test renderer backtick stripping divergence |
| Backslash escapes | 7 | tree-sitter backslash escape handling divergence |
| Tabs | 6 | tree-sitter tab handling divergence |
| Thematic breaks | 6 | tree-sitter thematic break detection divergence |
| Indented code blocks | 5 | tree-sitter indented code block boundary or indentation stripping divergence |
| Hard line breaks | 5 | tree-sitter hard break detection or trailing space handling divergence |
| Paragraphs | 4 | tree-sitter paragraph boundary detection divergence |
| Raw HTML (inline) | 4 | tree-sitter inline HTML parsing divergence |
| Autolinks | 3 | tree-sitter autolink parsing or URL encoding divergence |
| Precedence | 1 | tree-sitter block precedence divergence |
| Soft line breaks | 1 | test renderer soft break handling divergence |

## Key Divergence Areas

### Reference links (103 tests)
The largest category. tree-sitter-markdown does not resolve reference-style links (`[text][ref]` or `[text]` with a `[ref]: url` definition elsewhere). Our AST represents them as links with no destination. This is a known tree-sitter-markdown limitation.

### List handling (66 tests)
List item continuation, nesting depth, blank-line-induced looseness, and tight/loose detection differ between tree-sitter-markdown and the CommonMark spec. Many edge cases around lazy continuation lines.

### Block quotes (24 tests)
Lazy continuation lines inside block quotes and complex nesting of block quotes with other containers diverge.

### Emphasis/strong (22 tests)
Some edge cases in delimiter run matching (left-flanking vs right-flanking) differ.

### HTML entities (11 tests)
tree-sitter-markdown treats HTML entities as literal text; the CommonMark spec requires decoding them.

## Improving the Pass Rate

Two paths to improvement:
1. **Upstream contributions to tree-sitter-markdown** for parsing divergences.
2. **Improve the test renderer** — some failures are in the HTML rendering layer, not the parser. The test renderer (`em-core/tests/commonmark.rs`) is intentionally minimal; making it handle more edge cases would improve the pass rate without changing the parser.

The pass rate is expected to improve over time as both the parser and renderer mature.
