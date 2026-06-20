import SwiftUI
import MarkdownCore

enum EditorMode { case read, author }

/// The document editor: read mode by default (rendered, FEAT-049), one tap (or
/// the Edit/Done control, or ⌘E) into TextKit 2 author mode. The status bar is
/// computed THROUGH the Rust core. Author mode also offers Format Document (M4).
struct EditorView: View {
  @ObservedObject var document: MarkdownFileDocument
  @State private var mode: EditorMode = .read

  var body: some View {
    VStack(spacing: 0) {
      Group {
        switch mode {
        case .read:
          ReadModeView(text: document.text) { setMode(.author) }
        case .author:
          MarkdownTextView(text: $document.text)
        }
      }
      Divider()
      CoreStatusBar(text: document.text, mode: mode,
                    onToggle: { setMode(mode == .read ? .author : .read) },
                    onFormat: formatDocument)
    }
    .navigationTitle("Markdown")
    #if os(iOS)
    .navigationBarTitleDisplayMode(.inline)
    #endif
  }

  /// Format Document (FEAT-052 / M4) — reformat the whole document through the
  /// core (all five formatter rules) and replace the text in one step.
  private func formatDocument() {
    if let formatted = FormatAction.formatted(document.text) {
      document.text = formatted
    }
  }

  /// Crossfade unless Reduce Motion is on (D-A11Y-1).
  private func setMode(_ next: EditorMode) {
    if reduceMotionEnabled {
      mode = next
    } else {
      withAnimation(.easeInOut(duration: 0.2)) { mode = next }
    }
  }
}

/// Word count + doctor-issue count (via `markdown-core`), Format Document (author
/// mode), and the read/author toggle. In our own bottom bar so controls never
/// collapse into a nav-bar overflow menu and stay above the keyboard.
private struct CoreStatusBar: View {
  let text: String
  let mode: EditorMode
  let onToggle: () -> Void
  let onFormat: () -> Void

  var body: some View {
    let issues = diagnose(text: text).count
    let words = text.split(whereSeparator: { $0 == " " || $0 == "\n" || $0 == "\t" }).count
    HStack(spacing: 10) {
      Text("\(words) word\(words == 1 ? "" : "s")")
      Label("\(issues)", systemImage: issues == 0 ? "checkmark.circle" : "exclamationmark.triangle")
        .foregroundStyle(issues == 0 ? Color.secondary : Color.orange)
        .accessibilityLabel(issues == 0 ? "No issues" : "\(issues) issue\(issues == 1 ? "" : "s")")
      Spacer()
      if mode == .author {
        Button("Format", action: onFormat)
          .buttonStyle(.bordered)
          .keyboardShortcut("f", modifiers: [.command, .shift])
      }
      Button(mode == .read ? "Edit" : "Done", action: onToggle)
        .buttonStyle(.borderedProminent)
        .keyboardShortcut("e", modifiers: .command)
    }
    .font(.footnote)
    .padding(.horizontal, 12)
    .padding(.vertical, 6)
    .background(.ultraThinMaterial)
  }
}
