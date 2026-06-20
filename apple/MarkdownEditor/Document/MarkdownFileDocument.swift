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
  /// Whether the source file began with a UTF-8 BOM — re-emitted on save so
  /// round-trips preserve the original byte prefix (FEAT-054, D-FILE-3).
  private var hadUtf8Bom = false

  init() {
    self.text = ""
  }

  init(configuration: ReadConfiguration) throws {
    let data = configuration.file.regularFileContents ?? Data()
    // Decode through the core: rejects UTF-16 / invalid UTF-8, strips a UTF-8 BOM.
    let core = try MarkdownDocument.fromBytes(bytes: data)
    self.text = core.currentText()
    self.hadUtf8Bom = core.hasUtf8Bom()
  }

  func snapshot(contentType: UTType) throws -> String { text }

  func fileWrapper(snapshot: String, configuration: WriteConfiguration) throws -> FileWrapper {
    FileWrapper(regularFileWithContents: Self.encode(snapshot, withBom: hadUtf8Bom))
  }

  /// Encode `text` to bytes, re-emitting the UTF-8 BOM if the source had one
  /// (the frontend owns the write; ARCHITECTURE §3.7 buffer-out).
  static func encode(_ text: String, withBom: Bool) -> Data {
    var data = Data()
    if withBom { data.append(contentsOf: [0xEF, 0xBB, 0xBF]) }
    data.append(Data(text.utf8))
    return data
  }
}

extension UTType {
  /// The app's own exported markdown type (declared in Info.plist's
  /// UTExportedTypeDeclarations). A unique id avoids the "duplicate type
  /// identifier" collision with the system `net.daringfireball.markdown`, while
  /// owning the `.md`/`.markdown` extensions so new-document creation succeeds.
  static let markdownText = UTType(exportedAs: "com.markdown.editor.markdown")
}
