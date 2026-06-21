use std::io::Write;
use tempfile::NamedTempFile;

use markdown_core::Document;

#[test]
fn open_edit_save_reopen_roundtrip() {
    let initial = "Hello, world!";

    let mut tmp = NamedTempFile::new().expect("failed to create temp file");
    write!(tmp, "{}", initial).expect("failed to write initial content");
    let path = tmp.path().to_str().unwrap().to_owned();

    let mut doc = Document::open_file(&path).expect("failed to open file");
    assert_eq!(doc.current_text(), initial);

    // Replace "world" (offset 7, delete 5) with "markdown"
    doc.edit(7, 5, "markdown");
    assert_eq!(doc.current_text(), "Hello, markdown!");

    doc.save_file(&path).expect("failed to save file");

    let reopened = Document::open_file(&path).expect("failed to reopen file");
    assert_eq!(reopened.current_text(), "Hello, markdown!");
}

#[cfg(not(debug_assertions))]
#[test]
fn edit_offset_past_end_clamps() {
    let mut doc = Document::from_content("hi".to_string());
    doc.edit(10, 0, "X");
    assert_eq!(doc.current_text(), "hiX");
}

#[cfg(not(debug_assertions))]
#[test]
fn edit_delete_past_end_clamps() {
    let mut doc = Document::from_content("hello".to_string());
    doc.edit(3, 100, "");
    assert_eq!(doc.current_text(), "hel");
}

#[test]
fn edit_offset_past_end_clamps() {
    // Out-of-range offsets clamp to the document end instead of panicking.
    let mut doc = Document::from_content("hi".to_string());
    doc.edit(10, 0, "X");
    assert_eq!(doc.current_text(), "hiX");
}

#[test]
fn edit_non_char_boundary_offset_is_ignored() {
    // Offset 1 lands inside the 2-byte 'é'; the edit must be skipped, not panic
    // (a panic here previously poisoned the document mutex across the FFI).
    let mut doc = Document::from_content("é".to_string());
    doc.edit(1, 0, "x");
    assert_eq!(doc.current_text(), "é");
}

#[test]
fn edit_huge_delete_does_not_overflow() {
    // offset + delete must not overflow usize and wrap into an inverted range.
    let mut doc = Document::from_content("hello".to_string());
    doc.edit(5, usize::MAX, "z");
    assert_eq!(doc.current_text(), "helloz");
}
