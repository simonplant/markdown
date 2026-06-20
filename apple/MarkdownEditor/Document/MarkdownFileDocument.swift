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

  // Read .md (our exported type + the system type) and plain text; create/save as
  // our exported markdown type (which owns the .md extension) so creation works.
  static var readableContentTypes: [UTType] {
    [.markdownText, UTType("net.daringfireball.markdown") ?? .plainText, .plainText]
  }
  static var writableContentTypes: [UTType] { [.markdownText] }

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
  /// The app's own exported markdown type (declared in Info.plist's
  /// UTExportedTypeDeclarations). A unique id avoids the "duplicate type
  /// identifier" collision with the system `net.daringfireball.markdown`, while
  /// owning the `.md`/`.markdown` extensions so new-document creation succeeds.
  static let markdownText = UTType(exportedAs: "com.markdown.editor.markdown")
}
