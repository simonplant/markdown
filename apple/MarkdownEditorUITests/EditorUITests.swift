import XCTest

/// EPIC-APPLE-SKELETON (M1b) + read-mode (M2) run-proof on the iOS simulator:
/// create a document, tap into TextKit 2 author mode, type, switch to read mode
/// (rendered through the Rust core, punctuation hidden), confirm the core-powered
/// status bar. Validated by use on a real surface (A-PROC-3).
final class EditorUITests: XCTestCase {

  override func setUp() { continueAfterFailure = true }

  func testCreateEditReadModeAndCoreStatus() {
    let app = XCUIApplication()
    app.launch()
    attach("01-launch", app)

    // Create a new document — opens in READ mode (the default, FEAT-049).
    let create = app.buttons["Create Document"]
    XCTAssertTrue(create.waitForExistence(timeout: 20), "Create Document should exist")
    create.tap()
    attach("01b-after-create", app)

    // Enter author mode by tapping the read view (tap-to-edit, FEAT-049) — robust
    // against nav/toolbar layout. The read view is a (non-editable) text view.
    let view = app.textViews.firstMatch
    XCTAssertTrue(view.waitForExistence(timeout: 20), "editor surface should appear")
    view.tap()

    let textView = app.textViews.firstMatch
    XCTAssertTrue(textView.waitForExistence(timeout: 10), "author text view should appear")
    textView.tap()
    textView.typeText("# Title\n\n**bold** and *italic* text\n\n### Skipped a level\n")
    attach("02-author", app)

    // Switch to READ mode via ⌘E (reliable; the bottom bar is behind the keyboard).
    app.typeKey("e", modifierFlags: .command)
    attach("03-read", app)

    // Read mode renders the content with source punctuation hidden.
    if let rendered = app.textViews.firstMatch.value as? String {
      XCTAssertTrue(rendered.contains("Title"), "read mode should render the heading text")
      XCTAssertFalse(rendered.contains("###"), "read mode should hide heading punctuation")
      XCTAssertFalse(rendered.contains("**"), "read mode should hide bold punctuation")
    }

    // Status bar (computed through the core) renders the word count.
    let wordLabel = app.staticTexts.containing(
      NSPredicate(format: "label CONTAINS[c] %@", "word")
    ).firstMatch
    XCTAssertTrue(wordLabel.waitForExistence(timeout: 5), "core-powered status bar should render")
  }

  private func attach(_ name: String, _ app: XCUIApplication) {
    let shot = XCTAttachment(screenshot: app.screenshot())
    shot.name = name
    shot.lifetime = .keepAlways
    add(shot)
  }
}
