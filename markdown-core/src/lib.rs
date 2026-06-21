use std::fs;
use std::io;

pub mod ai;
pub mod ast;
pub mod doctor;
pub mod formatter;
pub mod math;
pub mod parser;
pub mod wasm_api;
pub mod wikilinks;

// File watching relies on the OS (`notify`); it has no WebAssembly equivalent,
// so it is excluded from the wasm32 build. The PWA shell observes files itself.
#[cfg(not(target_arch = "wasm32"))]
pub mod watcher;

// The uniffi binding for the native Apple (iOS/macOS) frontend (EPIC-UNIFFI).
// Native-only — never compiled for wasm32, where the WASM C-ABI in `wasm_api`
// is the binding instead. `setup_scaffolding!` registers the exported surface.
#[cfg(not(target_arch = "wasm32"))]
mod ffi;

#[cfg(not(target_arch = "wasm32"))]
uniffi::setup_scaffolding!();

/// Error surfaced when a file cannot be opened as UTF-8 markdown.
/// Today this covers UTF-16 (BE/LE BOM) and invalid-UTF-8 byte sequences;
/// other codepages are reported as `Other`.
#[derive(Debug, Clone, PartialEq, Eq)]
pub enum EncodingError {
    /// File begins with a UTF-16 little-endian BOM (0xFF 0xFE).
    Utf16Le,
    /// File begins with a UTF-16 big-endian BOM (0xFE 0xFF).
    Utf16Be,
    /// Bytes are not valid UTF-8 and no recognized BOM is present.
    InvalidUtf8,
    /// I/O failure reading the file.
    Io(String),
}

impl std::fmt::Display for EncodingError {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        match self {
            EncodingError::Utf16Le => write!(f, "File appears to be UTF-16 LE, which Markdown does not edit. Convert to UTF-8 and reopen."),
            EncodingError::Utf16Be => write!(f, "File appears to be UTF-16 BE, which Markdown does not edit. Convert to UTF-8 and reopen."),
            EncodingError::InvalidUtf8 => write!(f, "File is not valid UTF-8. Markdown edits UTF-8 documents only."),
            EncodingError::Io(msg) => write!(f, "Could not read file: {}", msg),
        }
    }
}

/// UTF-8 BOM bytes (EF BB BF).
const UTF8_BOM: &[u8] = &[0xEF, 0xBB, 0xBF];

pub struct Document {
    content: String,
    /// True when the source file began with a UTF-8 BOM; re-emitted on save.
    has_utf8_bom: bool,
}

impl Document {
    pub fn from_content(content: String) -> Document {
        Document { content, has_utf8_bom: false }
    }

    /// Open a file. Detects UTF-8 BOM (stripped from content, re-emitted on save);
    /// rejects UTF-16 and invalid UTF-8 with a specific [`EncodingError`] rather
    /// than silently mangling. ARCHITECTURE §3.7, FEAT-054.
    pub fn open_file(path: &str) -> Result<Document, EncodingError> {
        let bytes = fs::read(path).map_err(|e| EncodingError::Io(e.to_string()))?;
        Self::from_bytes(&bytes)
    }

    /// Parse raw file bytes into a Document, honoring BOM rules.
    pub fn from_bytes(bytes: &[u8]) -> Result<Document, EncodingError> {
        // UTF-16 BOM detection (2 bytes) — check before UTF-8 BOM (3 bytes).
        if bytes.starts_with(&[0xFF, 0xFE]) {
            return Err(EncodingError::Utf16Le);
        }
        if bytes.starts_with(&[0xFE, 0xFF]) {
            return Err(EncodingError::Utf16Be);
        }

        let (stripped, has_bom) = if bytes.starts_with(UTF8_BOM) {
            (&bytes[UTF8_BOM.len()..], true)
        } else {
            (bytes, false)
        };

        let content = std::str::from_utf8(stripped)
            .map(|s| s.to_string())
            .map_err(|_| EncodingError::InvalidUtf8)?;

        Ok(Document { content, has_utf8_bom: has_bom })
    }

    pub fn edit(&mut self, offset: usize, delete: usize, insert: &str) {
        // Offsets cross the FFI as raw u64 from the host; clamp and validate
        // rather than asserting. `saturating_add` avoids overflow (which would
        // wrap and produce an inverted range), and the char-boundary guard keeps
        // `replace_range` from panicking on a mid-character index — a panic here
        // would poison the document mutex and brick the object for all later calls.
        let offset = offset.min(self.content.len());
        let end = offset.saturating_add(delete).min(self.content.len());
        if !self.content.is_char_boundary(offset) || !self.content.is_char_boundary(end) {
            return;
        }
        self.content.replace_range(offset..end, insert);
    }

    /// Save to disk. Re-emits the UTF-8 BOM if the source had one so
    /// round-trips preserve the original byte prefix (D-FILE-3, FEAT-054).
    pub fn save_file(&self, path: &str) -> Result<(), io::Error> {
        if self.has_utf8_bom {
            let mut bytes = Vec::with_capacity(UTF8_BOM.len() + self.content.len());
            bytes.extend_from_slice(UTF8_BOM);
            bytes.extend_from_slice(self.content.as_bytes());
            fs::write(path, bytes)
        } else {
            fs::write(path, &self.content)
        }
    }

    pub fn current_text(&self) -> &str {
        &self.content
    }

    /// Whether the source file had a UTF-8 BOM (stripped from `content` but
    /// re-emitted on save).
    pub fn has_utf8_bom(&self) -> bool {
        self.has_utf8_bom
    }
}

#[cfg(test)]
mod encoding_tests {
    use super::*;

    #[test]
    fn from_bytes_plain_utf8() {
        let doc = Document::from_bytes(b"# Hello\n").unwrap();
        assert_eq!(doc.current_text(), "# Hello\n");
        assert!(!doc.has_utf8_bom());
    }

    #[test]
    fn from_bytes_utf8_with_bom_strips_and_remembers() {
        let mut bytes = vec![0xEF, 0xBB, 0xBF];
        bytes.extend_from_slice(b"# Hello\n");
        let doc = Document::from_bytes(&bytes).unwrap();
        assert_eq!(doc.current_text(), "# Hello\n");
        assert!(doc.has_utf8_bom());
    }

    #[test]
    fn from_bytes_rejects_utf16_le() {
        let bytes = vec![0xFF, 0xFE, 0x23, 0x00];
        assert_eq!(Document::from_bytes(&bytes).err(), Some(EncodingError::Utf16Le));
    }

    #[test]
    fn from_bytes_rejects_utf16_be() {
        let bytes = vec![0xFE, 0xFF, 0x00, 0x23];
        assert_eq!(Document::from_bytes(&bytes).err(), Some(EncodingError::Utf16Be));
    }

    #[test]
    fn from_bytes_rejects_invalid_utf8() {
        let bytes = vec![0xC0, 0x80]; // overlong NUL, invalid in UTF-8
        assert_eq!(Document::from_bytes(&bytes).err(), Some(EncodingError::InvalidUtf8));
    }

    #[test]
    fn round_trip_preserves_bom() {
        let tmp = tempfile::NamedTempFile::new().unwrap();
        let mut bytes = vec![0xEF, 0xBB, 0xBF];
        bytes.extend_from_slice(b"hello");
        fs::write(tmp.path(), &bytes).unwrap();

        let doc = Document::open_file(tmp.path().to_str().unwrap()).unwrap();
        assert!(doc.has_utf8_bom());
        doc.save_file(tmp.path().to_str().unwrap()).unwrap();

        let round_tripped = fs::read(tmp.path()).unwrap();
        assert_eq!(&round_tripped[..3], UTF8_BOM, "BOM preserved");
        assert_eq!(&round_tripped[3..], b"hello");
    }

    #[test]
    fn round_trip_no_bom_stays_no_bom() {
        let tmp = tempfile::NamedTempFile::new().unwrap();
        fs::write(tmp.path(), b"hello").unwrap();

        let doc = Document::open_file(tmp.path().to_str().unwrap()).unwrap();
        assert!(!doc.has_utf8_bom());
        doc.save_file(tmp.path().to_str().unwrap()).unwrap();

        let round_tripped = fs::read(tmp.path()).unwrap();
        assert_eq!(round_tripped, b"hello", "no BOM added");
    }
}
