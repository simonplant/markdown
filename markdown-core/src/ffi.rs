//! uniffi binding surface for the native Apple (iOS/macOS) frontend (EPIC-UNIFFI).
//!
//! Native-only (gated off wasm32 in `lib.rs`; the WASM build uses `wasm_api`).
//! Every type crossing the boundary is **owned** — the core's internal types
//! (`doctor::Diagnostic`, `ast::SyntaxNode`, `Document`, …) are left untouched
//! and converted here via `From`. iOS passes only text/bytes; the stateless
//! functions parse internally so Swift never threads a `SyntaxTree`. See
//! `docs/IOS_BUILD_SPEC.md` §2.
//!
//! Scope of this first cut: errors, value records/enums, the stateless
//! functions, and the `MarkdownDocument` object — exactly the M1 proof surface.
//! `FileWatcher` (a macOS/non-sandboxed fallback; iOS uses `UIDocument` state
//! changes) and the AI exports are deliberately deferred to their milestones.

use std::sync::{Arc, Mutex};

use crate::{ast, doctor, formatter, wikilinks, Document, EncodingError as CoreEncodingError};

// ---------------------------------------------------------------------------
// Errors
// ---------------------------------------------------------------------------

/// Open/decode failure — mirrors `crate::EncodingError`.
#[derive(Debug, thiserror::Error, uniffi::Error)]
pub enum EncodingError {
    #[error("File is UTF-16 LE; convert to UTF-8 and reopen.")]
    Utf16Le,
    #[error("File is UTF-16 BE; convert to UTF-8 and reopen.")]
    Utf16Be,
    #[error("File is not valid UTF-8.")]
    InvalidUtf8,
    #[error("Could not read file: {msg}")]
    Io { msg: String },
}

impl From<CoreEncodingError> for EncodingError {
    fn from(e: CoreEncodingError) -> Self {
        match e {
            CoreEncodingError::Utf16Le => EncodingError::Utf16Le,
            CoreEncodingError::Utf16Be => EncodingError::Utf16Be,
            CoreEncodingError::InvalidUtf8 => EncodingError::InvalidUtf8,
            CoreEncodingError::Io(msg) => EncodingError::Io { msg },
        }
    }
}

/// General engine failure surfaced to Swift.
#[derive(Debug, thiserror::Error, uniffi::Error)]
pub enum CoreError {
    #[error("I/O error: {msg}")]
    Io { msg: String },
    #[error("Wikilink error: {msg}")]
    Wikilink { msg: String },
}

// ---------------------------------------------------------------------------
// Value records / enums (owned mirrors of the core types)
// ---------------------------------------------------------------------------

/// Byte-offset range into the source text.
#[derive(uniffi::Record)]
pub struct Span {
    pub start: u64,
    pub end: u64,
}

/// 0-based row/column position.
#[derive(uniffi::Record)]
pub struct Position {
    pub row: u64,
    pub column: u64,
}

#[derive(uniffi::Enum)]
pub enum Severity {
    Error,
    Warning,
    Hint,
}

#[derive(uniffi::Record)]
pub struct Diagnostic {
    pub span: Span,
    pub severity: Severity,
    pub rule: String,
    pub message: String,
}

#[derive(uniffi::Record)]
pub struct Mutation {
    pub offset: u64,
    pub delete: u64,
    pub insert: String,
}

#[derive(uniffi::Record)]
pub struct Backlink {
    pub path: String,
    pub line: u64,
    pub context: String,
}

#[derive(uniffi::Enum)]
pub enum CheckboxState {
    Checked,
    Unchecked,
}

/// Owned mirror of `ast::NodeKind` (Strings cloned; no borrows cross the FFI).
#[derive(uniffi::Enum)]
pub enum NodeKind {
    Document,
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
    Table,
    TableHead,
    TableRow,
    TableCell,
    TableDelimiterRow,
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

/// Owned, recursive mirror of `ast::SyntaxNode`. The frontend walks this to
/// render read mode / WYSIWYM without a live tree-sitter tree.
#[derive(uniffi::Record)]
pub struct AstNode {
    pub kind: NodeKind,
    pub span: Span,
    pub start: Position,
    pub end: Position,
    pub children: Vec<AstNode>,
    pub text: Option<String>,
}

// ---------------------------------------------------------------------------
// From conversions (core type -> owned FFI type)
// ---------------------------------------------------------------------------

impl From<ast::Span> for Span {
    fn from(s: ast::Span) -> Self {
        Span { start: s.start as u64, end: s.end as u64 }
    }
}

impl From<ast::Position> for Position {
    fn from(p: ast::Position) -> Self {
        Position { row: p.row as u64, column: p.column as u64 }
    }
}

impl From<doctor::Severity> for Severity {
    fn from(s: doctor::Severity) -> Self {
        match s {
            doctor::Severity::Error => Severity::Error,
            doctor::Severity::Warning => Severity::Warning,
            doctor::Severity::Hint => Severity::Hint,
        }
    }
}

impl From<doctor::Diagnostic> for Diagnostic {
    fn from(d: doctor::Diagnostic) -> Self {
        Diagnostic {
            span: Span { start: d.span.0 as u64, end: d.span.1 as u64 },
            severity: d.severity.into(),
            rule: d.rule.to_string(),
            message: d.message,
        }
    }
}

impl From<formatter::Mutation> for Mutation {
    fn from(m: formatter::Mutation) -> Self {
        Mutation { offset: m.offset as u64, delete: m.delete as u64, insert: m.insert }
    }
}

impl From<wikilinks::Backlink> for Backlink {
    fn from(b: wikilinks::Backlink) -> Self {
        Backlink { path: b.path, line: b.line as u64, context: b.context }
    }
}

impl From<ast::CheckboxState> for CheckboxState {
    fn from(c: ast::CheckboxState) -> Self {
        match c {
            ast::CheckboxState::Checked => CheckboxState::Checked,
            ast::CheckboxState::Unchecked => CheckboxState::Unchecked,
        }
    }
}

impl From<&ast::NodeKind> for NodeKind {
    fn from(k: &ast::NodeKind) -> Self {
        match k {
            ast::NodeKind::Document => NodeKind::Document,
            ast::NodeKind::Heading { level } => NodeKind::Heading { level: *level },
            ast::NodeKind::Paragraph => NodeKind::Paragraph,
            ast::NodeKind::BlockQuote => NodeKind::BlockQuote,
            ast::NodeKind::OrderedList => NodeKind::OrderedList,
            ast::NodeKind::UnorderedList => NodeKind::UnorderedList,
            ast::NodeKind::ListItem { checkbox } => {
                NodeKind::ListItem { checkbox: checkbox.map(Into::into) }
            }
            ast::NodeKind::FencedCodeBlock { language } => {
                NodeKind::FencedCodeBlock { language: language.clone() }
            }
            ast::NodeKind::IndentedCodeBlock => NodeKind::IndentedCodeBlock,
            ast::NodeKind::HtmlBlock => NodeKind::HtmlBlock,
            ast::NodeKind::ThematicBreak => NodeKind::ThematicBreak,
            ast::NodeKind::FrontMatter => NodeKind::FrontMatter,
            ast::NodeKind::Table => NodeKind::Table,
            ast::NodeKind::TableHead => NodeKind::TableHead,
            ast::NodeKind::TableRow => NodeKind::TableRow,
            ast::NodeKind::TableCell => NodeKind::TableCell,
            ast::NodeKind::TableDelimiterRow => NodeKind::TableDelimiterRow,
            ast::NodeKind::Text => NodeKind::Text,
            ast::NodeKind::Emphasis => NodeKind::Emphasis,
            ast::NodeKind::Strong => NodeKind::Strong,
            ast::NodeKind::Strikethrough => NodeKind::Strikethrough,
            ast::NodeKind::InlineCode => NodeKind::InlineCode,
            ast::NodeKind::Link { destination } => {
                NodeKind::Link { destination: destination.clone() }
            }
            ast::NodeKind::Image { source } => NodeKind::Image { source: source.clone() },
            ast::NodeKind::Autolink => NodeKind::Autolink,
            ast::NodeKind::InlineHtml => NodeKind::InlineHtml,
            ast::NodeKind::LineBreak => NodeKind::LineBreak,
            ast::NodeKind::SoftBreak => NodeKind::SoftBreak,
        }
    }
}

impl From<&ast::SyntaxNode> for AstNode {
    fn from(n: &ast::SyntaxNode) -> Self {
        AstNode {
            kind: (&n.kind).into(),
            span: n.span.into(),
            start: n.point_range.start.into(),
            end: n.point_range.end.into(),
            children: n.children.iter().map(Into::into).collect(),
            text: n.text.clone(),
        }
    }
}

// ---------------------------------------------------------------------------
// Stateless functions (parse internally; iOS passes only text)
// ---------------------------------------------------------------------------

/// Parse markdown into the typed AST root.
#[uniffi::export]
pub fn parse(text: String) -> AstNode {
    (&crate::parser::parse(&text).root).into()
}

/// Parse + run the document doctor (no filesystem context).
#[uniffi::export]
pub fn diagnose(text: String) -> Vec<Diagnostic> {
    let tree = crate::parser::parse(&text);
    crate::doctor::check(&tree, &text, None)
        .into_iter()
        .map(Into::into)
        .collect()
}

/// Parse + run the doctor WITH filesystem context (enables the broken-link rule).
#[uniffi::export]
pub fn diagnose_with_context(
    text: String,
    doc_path: String,
    siblings: Vec<String>,
) -> Vec<Diagnostic> {
    let tree = crate::parser::parse(&text);
    let ctx = doctor::DoctorContext {
        doc_path: doc_path.into(),
        siblings: siblings.into_iter().map(Into::into).collect(),
    };
    crate::doctor::check(&tree, &text, Some(&ctx))
        .into_iter()
        .map(Into::into)
        .collect()
}

/// Parse + run the formatter, returning the mutations to apply.
#[uniffi::export]
pub fn format(text: String) -> Vec<Mutation> {
    let tree = crate::parser::parse(&text);
    crate::formatter::format(&tree, &text)
        .into_iter()
        .map(Into::into)
        .collect()
}

/// Apply formatter mutations to `text` and return the result. Mutations are
/// applied offset-descending so earlier offsets stay valid; out-of-range or
/// non-char-boundary mutations are skipped rather than panicking.
#[uniffi::export]
pub fn apply_mutations(text: String, mutations: Vec<Mutation>) -> String {
    let mut out = text;
    let mut muts = mutations;
    muts.sort_by(|a, b| b.offset.cmp(&a.offset));
    for m in muts {
        let start = m.offset as usize;
        // `delete` is a caller-controlled u64; a plain `start + delete` can
        // overflow usize and wrap to an inverted range that slips past the
        // bounds check and panics in replace_range. checked_add rejects it.
        let Some(end) = start.checked_add(m.delete as usize) else {
            continue;
        };
        if end <= out.len() && out.is_char_boundary(start) && out.is_char_boundary(end) {
            out.replace_range(start..end, &m.insert);
        }
    }
    out
}

/// Resolve a `[[wikilink]]` target against the filesystem near `current_file_path`.
#[uniffi::export]
pub fn resolve_wikilink(link_text: String, current_file_path: String) -> Option<String> {
    crate::wikilinks::resolve(&link_text, &current_file_path)
}

/// Find every `.md` file that links to `file_path`.
#[uniffi::export]
pub fn backlinks(file_path: String) -> Result<Vec<Backlink>, CoreError> {
    crate::wikilinks::backlinks(&file_path)
        .map(|v| v.into_iter().map(Into::into).collect())
        .map_err(|msg| CoreError::Wikilink { msg })
}

/// Create a new `.md` file for a wikilink target that doesn't exist yet.
#[uniffi::export]
pub fn create_wikilink_target(
    link_text: String,
    current_file_path: String,
) -> Result<String, CoreError> {
    crate::wikilinks::create_target(&link_text, &current_file_path)
        .map_err(|msg| CoreError::Wikilink { msg })
}

/// A detected math region (byte offsets into the source). FEAT-038.
#[derive(uniffi::Record)]
pub struct MathSpan {
    pub start: u64,
    pub end: u64,
    pub display: bool,
    pub latex: String,
}

impl From<crate::math::MathSpan> for MathSpan {
    fn from(m: crate::math::MathSpan) -> Self {
        MathSpan {
            start: m.start as u64,
            end: m.end as u64,
            display: m.display,
            latex: m.latex,
        }
    }
}

/// Find the `$…$` / `$$…$$` math regions in `text` (rendering is the frontend's
/// job — SwiftMath on Apple, KaTeX on web).
#[uniffi::export]
pub fn math_spans(text: String) -> Vec<MathSpan> {
    crate::math::find_spans(&text)
        .into_iter()
        .map(Into::into)
        .collect()
}

// ---------------------------------------------------------------------------
// Stateful document object (Arc + interior Mutex; the core Document is untouched)
// ---------------------------------------------------------------------------

#[derive(uniffi::Object)]
pub struct MarkdownDocument {
    inner: Mutex<Document>,
}

#[uniffi::export]
impl MarkdownDocument {
    /// New in-memory document from a string.
    #[uniffi::constructor]
    pub fn from_content(content: String) -> Arc<Self> {
        Arc::new(Self { inner: Mutex::new(Document::from_content(content)) })
    }

    /// Open a file (BOM/encoding detected and preserved; UTF-16/invalid rejected).
    #[uniffi::constructor]
    pub fn open_file(path: String) -> Result<Arc<Self>, EncodingError> {
        Document::open_file(&path)
            .map(|d| Arc::new(Self { inner: Mutex::new(d) }))
            .map_err(Into::into)
    }

    /// Construct from raw file bytes (the iOS `UIDocument` load path).
    #[uniffi::constructor]
    pub fn from_bytes(bytes: Vec<u8>) -> Result<Arc<Self>, EncodingError> {
        Document::from_bytes(&bytes)
            .map(|d| Arc::new(Self { inner: Mutex::new(d) }))
            .map_err(Into::into)
    }

    /// Apply an edit (byte offset, bytes to delete, text to insert).
    pub fn edit(&self, offset: u64, delete: u64, insert: String) {
        self.inner
            .lock()
            .expect("document mutex poisoned")
            .edit(offset as usize, delete as usize, &insert);
    }

    /// Write the document to disk, re-emitting the original BOM if present.
    pub fn save_file(&self, path: String) -> Result<(), CoreError> {
        self.inner
            .lock()
            .expect("document mutex poisoned")
            .save_file(&path)
            .map_err(|e| CoreError::Io { msg: e.to_string() })
    }

    /// The current document text (owned clone).
    pub fn current_text(&self) -> String {
        self.inner.lock().expect("document mutex poisoned").current_text().to_string()
    }

    /// Whether the source file began with a UTF-8 BOM (re-emitted on save).
    pub fn has_utf8_bom(&self) -> bool {
        self.inner.lock().expect("document mutex poisoned").has_utf8_bom()
    }
}
