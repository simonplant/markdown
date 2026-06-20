import SwiftUI
import UIKit

/// The editing surface: a `UITextView` forced onto **TextKit 2**
/// (`usingTextLayoutManager: true`) so selection physics, the caret, the
/// magnifier, dictation, and the keyboard accessory are the real platform
/// behaviors (ARCHITECTURE §4.2 / IOS_BUILD_SPEC §4.2). M1 shows/edits plain
/// source; read mode + WYSIWYM decorations are M2.
struct MarkdownTextView: UIViewRepresentable {
  @Binding var text: String

  func makeUIView(context: Context) -> UITextView {
    let textView = UITextView(usingTextLayoutManager: true) // TextKit 2
    textView.delegate = context.coordinator
    textView.font = .monospacedSystemFont(ofSize: 16, weight: .regular)
    textView.text = text
    textView.alwaysBounceVertical = true
    textView.autocorrectionType = .no
    textView.autocapitalizationType = .none
    textView.smartQuotesType = .no
    textView.smartDashesType = .no
    textView.textContainerInset = UIEdgeInsets(top: 12, left: 12, bottom: 12, right: 12)
    return textView
  }

  func updateUIView(_ textView: UITextView, context: Context) {
    // Only push external changes (e.g. a programmatic edit); don't fight the user.
    if textView.text != text {
      textView.text = text
    }
  }

  func makeCoordinator() -> Coordinator { Coordinator(text: $text) }

  final class Coordinator: NSObject, UITextViewDelegate {
    private let text: Binding<String>
    init(text: Binding<String>) { self.text = text }
    func textViewDidChange(_ textView: UITextView) {
      text.wrappedValue = textView.text
    }
  }
}
