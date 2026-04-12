use std::io::Write;
use tempfile::NamedTempFile;

use em_core::Document;

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
