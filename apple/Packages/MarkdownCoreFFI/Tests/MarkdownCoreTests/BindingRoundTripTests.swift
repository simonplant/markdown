import XCTest
import MarkdownCore

/// EPIC-UNIFFI exit proof (IOS_BUILD_SPEC §6, Tier A): the Rust markdown-core
/// engine is reachable from Swift via uniffi and round-trips real documents.
/// Runs natively on macOS (aarch64-apple-darwin) — no iOS simulator needed.
final class BindingRoundTripTests: XCTestCase {

  func testOpenEditSaveReopenRoundTrips() throws {
    let tmp = FileManager.default.temporaryDirectory
      .appendingPathComponent("rt-\(UUID().uuidString).md")
    defer { try? FileManager.default.removeItem(at: tmp) }

    let original = "# Title\n\nSome **bold** text.\n"
    try original.data(using: .utf8)!.write(to: tmp)

    // open through the core
    let doc = try MarkdownDocument.openFile(path: tmp.path)
    XCTAssertEqual(doc.currentText(), original)
    XCTAssertFalse(doc.hasUtf8Bom())

    // edit through the core: insert " more" before the final newline
    let insertAt = UInt64(original.utf8.count - 1)
    doc.edit(offset: insertAt, delete: 0, insert: " more")
    XCTAssertEqual(doc.currentText(), "# Title\n\nSome **bold** text. more\n")

    // save and reopen — byte-for-byte
    try doc.saveFile(path: tmp.path)
    let reopened = try MarkdownDocument.openFile(path: tmp.path)
    XCTAssertEqual(reopened.currentText(), doc.currentText())
    XCTAssertEqual(try Data(contentsOf: tmp), doc.currentText().data(using: .utf8))
  }

  func testStatelessFunctionsCrossTheBoundary() throws {
    // doctor: H1 -> H3 skip is a heading-hierarchy diagnostic
    let diags = diagnose(text: "# A\n\n### B\n")
    XCTAssertFalse(diags.isEmpty)
    XCTAssertEqual(diags.first?.rule, "heading-hierarchy")

    // formatter: trailing whitespace is trimmed (the core's
    // `trailing_whitespace_removed` rule). `#Title` without a space is a
    // paragraph, not a heading, so use a guaranteed trigger.
    let messy = "Hello   \nWorld\t\t\n"
    let muts = format(text: messy)
    XCTAssertFalse(muts.isEmpty)
    XCTAssertEqual(applyMutations(text: messy, mutations: muts), "Hello\nWorld\n")

    // parser: root node is the Document
    let root = parse(text: "# Title\n")
    guard case .document = root.kind else {
      return XCTFail("expected Document root, got \(root.kind)")
    }
    XCTAssertFalse(root.children.isEmpty)
  }

  func testUtf8BomRoundTrips() throws {
    let tmp = FileManager.default.temporaryDirectory
      .appendingPathComponent("bom-\(UUID().uuidString).md")
    defer { try? FileManager.default.removeItem(at: tmp) }

    var bytes: [UInt8] = [0xEF, 0xBB, 0xBF] // UTF-8 BOM
    bytes.append(contentsOf: Array("# Hello\n".utf8))
    try Data(bytes).write(to: tmp)

    let doc = try MarkdownDocument.openFile(path: tmp.path)
    XCTAssertTrue(doc.hasUtf8Bom())
    XCTAssertEqual(doc.currentText(), "# Hello\n") // BOM stripped from content

    try doc.saveFile(path: tmp.path)
    let raw = try Data(contentsOf: tmp)
    XCTAssertEqual(Array(raw.prefix(3)), [0xEF, 0xBB, 0xBF]) // BOM re-emitted
  }

  func testInvalidEncodingSurfacesError() {
    let tmp = FileManager.default.temporaryDirectory
      .appendingPathComponent("utf16-\(UUID().uuidString).md")
    defer { try? FileManager.default.removeItem(at: tmp) }
    // UTF-16 LE BOM — the core must reject, not mangle.
    try? Data([0xFF, 0xFE, 0x23, 0x00]).write(to: tmp)
    XCTAssertThrowsError(try MarkdownDocument.openFile(path: tmp.path)) { error in
      XCTAssertTrue(error is EncodingError)
    }
  }
}
