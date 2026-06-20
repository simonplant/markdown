import SwiftUI
import UIKit

/// Read mode — the default view on open (FEAT-049, the most load-bearing product
/// claim). A non-editable TextKit 2 surface showing the rendered markdown
/// (`MarkdownRenderer`): source punctuation hidden, headings/emphasis/code styled.
/// A single tap enters author mode. IOS_BUILD_SPEC §4.3.
struct ReadModeView: UIViewRepresentable {
  let text: String
  let onEnterAuthor: () -> Void

  func makeUIView(context: Context) -> UITextView {
    let textView = UITextView(usingTextLayoutManager: true) // TextKit 2
    textView.isEditable = false
    textView.isSelectable = true
    textView.isFindInteractionEnabled = true // find in rendered text, ⌘F (FEAT-016)
    textView.alwaysBounceVertical = true
    textView.backgroundColor = .systemBackground
    textView.textContainerInset = UIEdgeInsets(top: 16, left: 16, bottom: 24, right: 16)
    textView.attributedText = MarkdownRenderer.render(text)

    let tap = UITapGestureRecognizer(target: context.coordinator,
                                     action: #selector(Coordinator.handleTap))
    tap.cancelsTouchesInView = false
    textView.addGestureRecognizer(tap)
    return textView
  }

  func updateUIView(_ textView: UITextView, context: Context) {
    context.coordinator.onEnterAuthor = onEnterAuthor
    textView.attributedText = MarkdownRenderer.render(text)
  }

  func makeCoordinator() -> Coordinator { Coordinator(onEnterAuthor: onEnterAuthor) }

  final class Coordinator: NSObject {
    var onEnterAuthor: () -> Void
    init(onEnterAuthor: @escaping () -> Void) { self.onEnterAuthor = onEnterAuthor }
    @objc func handleTap() { onEnterAuthor() }
  }
}
