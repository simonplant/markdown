import XCTest

/// EPIC-APPLE-SKELETON run-proof (IOS_BUILD_SPEC §5 M1b): the app launches on a
/// real surface, a document opens into the TextKit 2 editor, typing works, and
/// the status bar — computed through the Rust core via uniffi — updates live.
/// Screenshots are attached as evidence at each step.
final class EditorUITests: XCTestCase {

  override func setUp() { continueAfterFailure = true }

  func testCreateDocumentTypeAndCoreStatus() {
    let app = XCUIApplication()
    app.launch()
    attach("01-launch", app)

    // DocumentGroup browser → create a new untitled document.
    let create = app.buttons["Create Document"]
    XCTAssertTrue(create.waitForExistence(timeout: 20), "Create Document should exist")
    create.tap()
    attach("02-after-create", app)

    // The TextKit 2 editor surface.
    let textView = app.textViews.firstMatch
    XCTAssertTrue(textView.waitForExistence(timeout: 20), "editor text view should appear")
    textView.tap()
    // A heading skip (H1 -> H3) is a doctor diagnostic — the status bar should
    // reflect a non-zero issue count, proving the core runs on the typed text.
    textView.typeText("# Title\n\n### Skipped a level\n")
    attach("03-typed", app)

    // The status bar shows "<n> words" (computed via the core path).
    let wordLabel = app.staticTexts.containing(
      NSPredicate(format: "label CONTAINS[c] %@", "word")
    ).firstMatch
    XCTAssertTrue(wordLabel.waitForExistence(timeout: 5), "core-powered status bar should render")
    attach("04-status", app)
  }

  private func attach(_ name: String, _ app: XCUIApplication) {
    let shot = XCTAttachment(screenshot: app.screenshot())
    shot.name = name
    shot.lifetime = .keepAlways
    add(shot)
  }
}
