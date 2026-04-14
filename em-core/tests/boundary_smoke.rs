use em_core::Document;

#[test]
fn empty_file() {
    let tmp = std::env::temp_dir().join("em_bound_empty.md");
    std::fs::write(&tmp, "").unwrap();
    let doc = Document::open_file(tmp.to_str().unwrap()).unwrap();
    assert_eq!(doc.current_text(), "");
    std::fs::remove_file(&tmp).ok();
}

#[test]
fn whitespace_only() {
    let tmp = std::env::temp_dir().join("em_bound_ws.md");
    std::fs::write(&tmp, "   \n\n  \t\n").unwrap();
    let doc = Document::open_file(tmp.to_str().unwrap()).unwrap();
    assert_eq!(doc.current_text(), "   \n\n  \t\n");
    std::fs::remove_file(&tmp).ok();
}

#[test]
fn large_single_line_100kb() {
    let tmp = std::env::temp_dir().join("em_bound_big.md");
    let big = "x".repeat(100_000);
    std::fs::write(&tmp, &big).unwrap();
    let doc = Document::open_file(tmp.to_str().unwrap()).unwrap();
    assert_eq!(doc.current_text().len(), 100_000);
    std::fs::remove_file(&tmp).ok();
}

#[test]
fn unicode_cjk_emoji_rtl() {
    let tmp = std::env::temp_dir().join("em_bound_unicode.md");
    let content = "# 你好世界\n\nこんにちは 🎉🚀\n\nمرحبا بالعالم\n\n## Ñoño café";
    std::fs::write(&tmp, content).unwrap();
    let doc = Document::open_file(tmp.to_str().unwrap()).unwrap();
    assert_eq!(doc.current_text(), content);
    std::fs::remove_file(&tmp).ok();
}

#[test]
fn edit_at_offset_zero() {
    let mut doc = Document::from_content("hello".to_string());
    doc.edit(0, 0, "X");
    assert_eq!(doc.current_text(), "Xhello");
}

#[test]
fn edit_at_end() {
    let mut doc = Document::from_content("hello".to_string());
    doc.edit(5, 0, "Y");
    assert_eq!(doc.current_text(), "helloY");
}

#[test]
fn delete_all_content() {
    let mut doc = Document::from_content("hello".to_string());
    doc.edit(0, 5, "");
    assert_eq!(doc.current_text(), "");
}

#[test]
fn nonexistent_file_returns_error() {
    let result = Document::open_file("/tmp/this_does_not_exist_smoke_12345.md");
    assert!(result.is_err());
}

#[test]
fn save_to_readonly_location_errors() {
    let doc = Document::from_content("test".to_string());
    let result = doc.save_file("/root/readonly_test.md");
    assert!(result.is_err());
}

#[test]
fn binary_content() {
    let tmp = std::env::temp_dir().join("em_bound_binary.md");
    let binary = vec![0u8, 1, 2, 0xFF, 0xFE, 0x00, 0x80];
    std::fs::write(&tmp, &binary).unwrap();
    // Should either open (treating as lossy UTF-8) or error — either is acceptable
    let result = Document::open_file(tmp.to_str().unwrap());
    // Just assert it doesn't panic
    match result {
        Ok(doc) => { let _ = doc.current_text(); }
        Err(_) => {}
    }
    std::fs::remove_file(&tmp).ok();
}

#[test]
fn save_roundtrip_preserves_content() {
    let tmp = std::env::temp_dir().join("em_bound_roundtrip.md");
    let content = "# Test\n\n**bold** and *italic*\n\n- list\n";
    let doc = Document::from_content(content.to_string());
    doc.save_file(tmp.to_str().unwrap()).unwrap();
    let reopened = Document::open_file(tmp.to_str().unwrap()).unwrap();
    assert_eq!(reopened.current_text(), content);
    std::fs::remove_file(&tmp).ok();
}
