/// Typed AST produced by parsing markdown with tree-sitter.
///
/// Every downstream feature (formatting, doctor, WYSIWYM decorations) reads
/// from this AST. No component parses markdown ad-hoc.

/// A byte-offset range within the source text.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct Span {
    pub start: usize,
    pub end: usize,
}

/// Row/column position (0-based).
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct Position {
    pub row: usize,
    pub column: usize,
}

/// Row/column range within the source text (0-based, matching tree-sitter).
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct PointRange {
    pub start: Position,
    pub end: Position,
}

/// Checkbox state for task list items.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum CheckboxState {
    Checked,
    Unchecked,
}

/// The kind of a node in the markdown AST.
#[derive(Debug, Clone, PartialEq, Eq)]
pub enum NodeKind {
    // Structural
    Document,

    // Block elements
    Heading { level: u8 },
    Paragraph,
    BlockQuote,
    OrderedList,
    UnorderedList,
    ListItem { checkbox: Option<CheckboxState> },
    FencedCodeBlock { language: Option<String> },
    IndentedCodeBlock,
    HtmlBlock,
    ThematicBreak,
    FrontMatter,

    // Table (GFM)
    Table,
    TableHead,
    TableRow,
    TableCell,
    TableDelimiterRow,

    // Inline elements
    Text,
    Emphasis,
    Strong,
    Strikethrough,
    InlineCode,
    Link { destination: Option<String> },
    Image { source: Option<String> },
    Autolink,
    InlineHtml,
    LineBreak,
    SoftBreak,
}

/// A single node in the typed markdown AST.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct SyntaxNode {
    pub kind: NodeKind,
    pub span: Span,
    pub point_range: PointRange,
    pub children: Vec<SyntaxNode>,
    pub text: Option<String>,
}

/// The root of a parsed markdown document.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct SyntaxTree {
    pub root: SyntaxNode,
}

impl SyntaxTree {
    /// Iterate all nodes depth-first.
    pub fn walk(&self) -> SyntaxTreeIter<'_> {
        SyntaxTreeIter {
            stack: vec![&self.root],
        }
    }
}

/// Depth-first iterator over all nodes in a `SyntaxTree`.
pub struct SyntaxTreeIter<'a> {
    stack: Vec<&'a SyntaxNode>,
}

impl<'a> Iterator for SyntaxTreeIter<'a> {
    type Item = &'a SyntaxNode;

    fn next(&mut self) -> Option<Self::Item> {
        let node = self.stack.pop()?;
        // Push children in reverse so leftmost is popped first.
        for child in node.children.iter().rev() {
            self.stack.push(child);
        }
        Some(node)
    }
}
