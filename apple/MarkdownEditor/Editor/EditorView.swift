import SwiftUI
import MarkdownCore

/// The document editor screen: the TextKit 2 surface plus a live status bar that
/// is computed **through the Rust core** — proving the uniffi binding runs inside
/// the app at runtime, not just at load. (Read/author modes, the doctor overlay,
/// and formatting arrive in M2–M4.)
struct EditorView: View {
  @ObservedObject var document: MarkdownFileDocument

  var body: some View {
    VStack(spacing: 0) {
      MarkdownTextView(text: $document.text)
      Divider()
      CoreStatusBar(text: document.text)
    }
    .navigationTitle("Markdown")
    .navigationBarTitleDisplayMode(.inline)
  }
}

/// Word count + doctor-issue count, recomputed via `markdown-core` (`diagnose`)
/// on the current text. Cheap at skeleton-document sizes; M3 moves diagnosis to a
/// debounced background pass so it never touches the keystroke path.
private struct CoreStatusBar: View {
  let text: String

  var body: some View {
    let issues = diagnose(text: text).count
    let words = text.split(whereSeparator: { $0 == " " || $0 == "\n" || $0 == "\t" }).count
    HStack {
      Text("\(words) word\(words == 1 ? "" : "s")")
      Spacer()
      Label("\(issues)", systemImage: issues == 0 ? "checkmark.circle" : "exclamationmark.triangle")
        .foregroundStyle(issues == 0 ? Color.secondary : Color.orange)
    }
    .font(.footnote)
    .padding(.horizontal, 12)
    .padding(.vertical, 8)
    .background(.ultraThinMaterial)
  }
}
