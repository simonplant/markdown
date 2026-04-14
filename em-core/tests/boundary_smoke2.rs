use em_core::Document;

#[test]
#[should_panic]
fn edit_beyond_document_length() {
    let mut doc = Document::from_content("hi".to_string());
    // offset 10 is way past the end of a 2-char doc
    doc.edit(10, 1, "X");
}

#[test]
fn edit_delete_beyond_end() {
    let mut doc = Document::from_content("hello".to_string());
    // Try to delete 100 chars starting at offset 3 (only 2 available)
    // This might panic or clamp — let's find out
    let result = std::panic::catch_unwind(std::panic::AssertUnwindSafe(|| {
        doc.edit(3, 100, "");
    }));
    if result.is_err() {
        // Panics — that's the current behavior, document it
        println!("edit beyond end panics (expected for String-backed doc)");
    } else {
        println!("edit beyond end clamped: '{}'", doc.current_text());
    }
}

#[test]
fn rapid_sequential_edits() {
    let mut doc = Document::from_content("".to_string());
    // Simulate fast typing: insert one char at a time
    for (i, ch) in "Hello, World!".chars().enumerate() {
        doc.edit(i, 0, &ch.to_string());
    }
    assert_eq!(doc.current_text(), "Hello, World!");
}

#[test]
fn very_long_lines_with_unicode() {
    let line = "é".repeat(50_000); // 50k multibyte chars
    let mut doc = Document::from_content(line.clone());
    // Edit in the middle of multibyte content
    doc.edit(25_000 * 2, 0, "INSERTED"); // byte offset for 'é' is 2 bytes each
    assert!(doc.current_text().contains("INSERTED"));
}

#[test]
fn newline_variations() {
    // Test \r\n, \r, \n
    let content = "line1\r\nline2\rline3\nline4";
    let doc = Document::from_content(content.to_string());
    assert_eq!(doc.current_text(), content); // Should preserve exactly
}

#[test]
fn null_bytes_in_content() {
    let content = "before\0after";
    let doc = Document::from_content(content.to_string());
    assert_eq!(doc.current_text(), content);
}

#[test]
fn formatter_on_empty() {
    let doc = em_core::Document::from_content("".to_string());
    let text = doc.current_text();
    let mutations = em_core::format(text);
    assert!(mutations.is_empty(), "No mutations for empty doc");
}

#[test]
fn parser_on_empty() {
    let ast = em_core::parse("");
    // Should return a valid AST with no children
    assert!(ast.children.is_empty() || ast.node_type == "document");
}

#[test]
fn doctor_on_empty() {
    let violations = em_core::doctor("", None);
    assert!(violations.is_empty());
}
