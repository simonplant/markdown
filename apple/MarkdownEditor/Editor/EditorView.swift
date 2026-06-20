import SwiftUI
import UIKit
import MarkdownCore

enum EditorMode { case read, author }

/// The document editor: read mode by default (rendered, FEAT-049), one tap (or
/// the Edit/Done control, or ⌘E) into author mode (TextKit 2 editing). The status
/// bar is computed THROUGH the Rust core, proving the binding runs in-app.
/// IOS_BUILD_SPEC §4.
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
      CoreStatusBar(text: document.text, mode: mode) {
        setMode(mode == .read ? .author : .read)
      }
    }
    .navigationTitle("Markdown")
    .navigationBarTitleDisplayMode(.inline)
  }

  /// Crossfade unless Reduce Motion is on (D-A11Y-1 — polish, not the FEAT-015
  /// "Render" animation).
  private func setMode(_ next: EditorMode) {
    if UIAccessibility.isReduceMotionEnabled {
      mode = next
    } else {
      withAnimation(.easeInOut(duration: 0.2)) { mode = next }
    }
  }
}

/// Word count + doctor-issue count (both via `markdown-core`) and the read/author
/// toggle. Lives in a bottom bar we own, so the toggle never collapses into a
/// nav-bar overflow menu. M3 moves diagnosis to a debounced background pass.
private struct CoreStatusBar: View {
  let text: String
  let mode: EditorMode
  let toggle: () -> Void

  var body: some View {
    let issues = diagnose(text: text).count
    let words = text.split(whereSeparator: { $0 == " " || $0 == "\n" || $0 == "\t" }).count
    HStack(spacing: 12) {
      Text("\(words) word\(words == 1 ? "" : "s")")
      Label("\(issues)", systemImage: issues == 0 ? "checkmark.circle" : "exclamationmark.triangle")
        .foregroundStyle(issues == 0 ? Color.secondary : Color.orange)
      Spacer()
      Button(mode == .read ? "Edit" : "Done", action: toggle)
        .buttonStyle(.bordered)
        .keyboardShortcut("e", modifiers: .command)
    }
    .font(.footnote)
    .padding(.horizontal, 12)
    .padding(.vertical, 6)
    .background(.ultraThinMaterial)
  }
}
