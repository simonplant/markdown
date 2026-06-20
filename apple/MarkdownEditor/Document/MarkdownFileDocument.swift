import SwiftUI
import UniformTypeIdentifiers
import MarkdownCore

/// A `.md` document. Reference semantics so it can hold editor state across the
/// SwiftUI lifecycle. Loading goes through the Rust core (`MarkdownDocument`) so
/// encoding/BOM detection (FEAT-054) is exercised on the real binding; the
/// frontend owns the actual file write (ARCHITECTURE §3.7 buffer-out).
///
/// M1 skeleton scope: open/edit/save round-trip on a real TextKit 2 surface.
/// BOM-preserving save and conflict detection are M5.
final class MarkdownFileDocument: ReferenceFileDocument {
  typealias Snapshot = String

  static var readableContentTypes: [UTType] { [.markdownText, .plainText] }
  static var writableContentTypes: [UTType] { [.markdownText, .plainText] }

  @Published var text: String

  init() {
    self.text = ""
  }

  init(configuration: ReadConfiguration) throws {
    let data = configuration.file.regularFileContents ?? Data()
    // Decode through the core: rejects UTF-16 / invalid UTF-8, strips a UTF-8 BOM.
    let core = try MarkdownDocument.fromBytes(bytes: data)
    self.text = core.currentText()
  }

  func snapshot(contentType: UTType) throws -> String { text }

  func fileWrapper(snapshot: String, configuration: WriteConfiguration) throws -> FileWrapper {
    FileWrapper(regularFileWithContents: Data(snapshot.utf8))
  }
}

extension UTType {
  /// The markdown UTI. `net.daringfireball.markdown` is **system-declared**, so
  /// we look it up (no `importedAs:`, which would re-declare it and cause a
  /// "duplicate type identifier" error). Falls back to plain text if absent.
  static let markdownText = UTType("net.daringfireball.markdown") ?? .plainText
}
