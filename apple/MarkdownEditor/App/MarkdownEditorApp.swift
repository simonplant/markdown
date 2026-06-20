import SwiftUI

/// The iOS (and later macOS) app entry point. A document-based app: the OS file
/// providers (Files / iCloud / Dropbox / …) are the source of truth — no vault,
/// no library (PRODUCT D-FILE-1/2). EPIC-APPLE-SKELETON / IOS_BUILD_SPEC §3.2.
@main
struct MarkdownEditorApp: App {
  var body: some Scene {
    DocumentGroup(newDocument: { MarkdownFileDocument() }) { configuration in
      EditorView(document: configuration.document)
    }
  }
}
