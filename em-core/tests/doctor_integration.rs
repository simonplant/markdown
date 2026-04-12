use std::fs;

use em_core::doctor::{check, DoctorContext, Severity};
use em_core::parser;

/// Integration test: a single fixture file triggers all three diagnostic rules.
#[test]
fn fixture_with_all_violation_types() {
    let dir = tempfile::tempdir().unwrap();

    // Create the fixture markdown with all three violation types:
    // 1. Broken link (./missing.md does not exist)
    // 2. Heading hierarchy violation (H1 -> H3)
    // 3. Duplicate heading ("Setup" appears twice at level 2)
    let fixture = "\
# Title

### Skipped to H3

## Setup

Some text with a [broken link](./missing.md).

## Setup

More text.
";

    let doc_path = dir.path().join("fixture.md");
    fs::write(&doc_path, fixture).unwrap();

    let tree = parser::parse(fixture);
    let ctx = DoctorContext {
        doc_path: doc_path.clone(),
        siblings: vec![],
    };

    let diags = check(&tree, fixture, Some(&ctx));

    // Verify we got at least one of each rule.
    let broken: Vec<_> = diags.iter().filter(|d| d.rule == "broken-link").collect();
    let hierarchy: Vec<_> = diags.iter().filter(|d| d.rule == "heading-hierarchy").collect();
    let duplicate: Vec<_> = diags.iter().filter(|d| d.rule == "duplicate-heading").collect();

    assert!(
        !broken.is_empty(),
        "Expected at least one broken-link diagnostic, got none. All diags: {:?}",
        diags
    );
    assert!(
        !hierarchy.is_empty(),
        "Expected at least one heading-hierarchy diagnostic, got none. All diags: {:?}",
        diags
    );
    assert!(
        !duplicate.is_empty(),
        "Expected at least one duplicate-heading diagnostic, got none. All diags: {:?}",
        diags
    );

    // Verify diagnostic structure.
    for d in &diags {
        assert!(d.span.0 < d.span.1, "Span must be non-empty: {:?}", d);
        assert!(!d.message.is_empty(), "Message must not be empty: {:?}", d);
        assert!(
            matches!(d.severity, Severity::Error | Severity::Warning | Severity::Hint),
            "Severity must be valid"
        );
    }
}

/// When no context is provided, broken-link diagnostics are skipped
/// but other rules still fire.
#[test]
fn no_context_skips_broken_links() {
    let fixture = "\
# Title

### Skipped to H3

## Setup

[broken](./missing.md)

## Setup
";

    let tree = parser::parse(fixture);
    let diags = check(&tree, fixture, None);

    let broken: Vec<_> = diags.iter().filter(|d| d.rule == "broken-link").collect();
    assert!(broken.is_empty(), "Broken-link should be skipped without context");

    // But other rules should still fire.
    let hierarchy: Vec<_> = diags.iter().filter(|d| d.rule == "heading-hierarchy").collect();
    let duplicate: Vec<_> = diags.iter().filter(|d| d.rule == "duplicate-heading").collect();
    assert!(!hierarchy.is_empty(), "Heading hierarchy should still fire");
    assert!(!duplicate.is_empty(), "Duplicate heading should still fire");
}

/// Broken-link resolves against the document's parent directory.
#[test]
fn broken_link_resolves_relative_to_doc() {
    let dir = tempfile::tempdir().unwrap();
    let sub = dir.path().join("sub");
    fs::create_dir_all(&sub).unwrap();

    // Create a sibling file in the subdirectory.
    let sibling = sub.join("other.md");
    fs::write(&sibling, "# Other").unwrap();

    let doc_path = sub.join("doc.md");

    let fixture = "[exists](./other.md)\n[missing](./nope.md)\n";
    let tree = parser::parse(fixture);
    let ctx = DoctorContext {
        doc_path,
        siblings: vec![],
    };

    let diags = check(&tree, fixture, Some(&ctx));
    let broken: Vec<_> = diags.iter().filter(|d| d.rule == "broken-link").collect();

    assert_eq!(broken.len(), 1, "Only the missing link should be flagged");
    assert!(broken[0].message.contains("nope.md"));
}
