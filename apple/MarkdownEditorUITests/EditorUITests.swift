import XCTest

/// Run-proofs on the iOS simulator (A-PROC-3): the native editor, the read/author
/// modes, the doctor overlay, and Format Document — each driven through the Rust
/// engine via uniffi.
final class EditorUITests: XCTestCase {

  override func setUp() { continueAfterFailure = true }

  // M1b + M2 (FEAT-049) + M3 (FEAT-050): create, edit in TextKit 2, doctor
  // diagnostics, read mode rendered with punctuation hidden.
  func testEditReadModeAndDiagnostics() {
    let app = XCUIApplication()
    app.launch()

    let view = openNewDocument(app)
    view.tap() // read → author (tap-to-edit, FEAT-049)

    let textView = app.textViews.firstMatch
    XCTAssertTrue(textView.waitForExistence(timeout: 10), "author text view should appear")
    textView.tap()
    textView.typeText("# Title\n\n**bold** and *italic* text\n\n### Skipped a level\n")
    Thread.sleep(forTimeInterval: 1.5) // let the 500ms doctor pass paint underlines (M3)
    attach("author-with-diagnostics", app)

    // Switch to READ mode via the bottom-bar Done (visible above the keyboard).
    let done = app.buttons["Done"]
    XCTAssertTrue(done.waitForExistence(timeout: 10), "Done should be reachable")
    done.tap()
    attach("read-mode", app)

    if let rendered = app.textViews.firstMatch.value as? String {
      XCTAssertTrue(rendered.contains("Title"), "read mode should render the heading text")
      XCTAssertFalse(rendered.contains("###"), "read mode should hide heading punctuation")
      XCTAssertFalse(rendered.contains("**"), "read mode should hide bold punctuation")
    }

    let wordLabel = app.staticTexts.containing(
      NSPredicate(format: "label CONTAINS[c] %@", "word")
    ).firstMatch
    XCTAssertTrue(wordLabel.waitForExistence(timeout: 5), "core-powered status bar should render")
  }

  // M4 (FEAT-052): Format Document runs the core formatter (trailing whitespace
  // trimmed here) and replaces the text.
  func testFormatDocument() {
    let app = XCUIApplication()
    app.launch()

    let view = openNewDocument(app)
    view.tap()

    let textView = app.textViews.firstMatch
    XCTAssertTrue(textView.waitForExistence(timeout: 10), "author text view should appear")
    textView.tap()
    textView.typeText("Hello   \nWorld\t\t\n") // trailing whitespace the formatter trims

    let format = app.buttons["Format"]
    XCTAssertTrue(format.waitForExistence(timeout: 10), "Format button should exist in author mode")
    format.tap()
    Thread.sleep(forTimeInterval: 0.5)
    attach("formatted", app)

    if let value = app.textViews.firstMatch.value as? String {
      XCTAssertFalse(value.contains("Hello   "), "Format should trim trailing whitespace")
      XCTAssertTrue(value.contains("Hello"), "content preserved")
      XCTAssertTrue(value.contains("World"), "content preserved")
    }
  }

  // MARK: helpers

  /// Create a new document, retrying past the occasional simulator
  /// "Unable to Import Document" dialog. Returns the editor surface element.
  private func openNewDocument(_ app: XCUIApplication) -> XCUIElement {
    let create = app.buttons["Create Document"]
    XCTAssertTrue(create.waitForExistence(timeout: 20), "Create Document should exist")
    create.tap()
    let ok = app.buttons["OK"]
    var attempts = 0
    while ok.waitForExistence(timeout: 3), attempts < 5 {
      ok.tap(); create.tap(); attempts += 1
    }
    let view = app.textViews.firstMatch
    XCTAssertTrue(view.waitForExistence(timeout: 20), "editor surface should appear")
    return view
  }

  private func attach(_ name: String, _ app: XCUIApplication) {
    let shot = XCTAttachment(screenshot: app.screenshot())
    shot.name = name
    shot.lifetime = .keepAlways
    add(shot)
  }
}
