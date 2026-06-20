import SwiftUI

/// Read mode — the default view on open (FEAT-049). A non-editable surface showing
/// the rendered markdown (`MarkdownRenderer`), source punctuation hidden. A tap /
/// click enters author mode. iOS uses TextKit 2 `UITextView`; macOS `NSTextView`.

#if os(macOS)
import AppKit

struct ReadModeView: NSViewRepresentable {
  let text: String
  let onEnterAuthor: () -> Void

  func makeNSView(context: Context) -> NSScrollView {
    let scroll = NSTextView.scrollableTextView()
    let textView = scroll.documentView as! NSTextView
    textView.isEditable = false
    textView.textContainerInset = NSSize(width: 12, height: 16)
    textView.textStorage?.setAttributedString(MarkdownRenderer.render(text))
    let click = NSClickGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handleClick))
    textView.addGestureRecognizer(click)
    context.coordinator.onEnterAuthor = onEnterAuthor
    return scroll
  }

  func updateNSView(_ scroll: NSScrollView, context: Context) {
    if let textView = scroll.documentView as? NSTextView {
      textView.textStorage?.setAttributedString(MarkdownRenderer.render(text))
    }
    context.coordinator.onEnterAuthor = onEnterAuthor
  }

  func makeCoordinator() -> Coordinator { Coordinator(onEnterAuthor: onEnterAuthor) }

  final class Coordinator: NSObject {
    var onEnterAuthor: () -> Void
    init(onEnterAuthor: @escaping () -> Void) { self.onEnterAuthor = onEnterAuthor }
    @objc func handleClick() { onEnterAuthor() }
  }
}

#else
import UIKit

struct ReadModeView: UIViewRepresentable {
  let text: String
  let onEnterAuthor: () -> Void

  func makeUIView(context: Context) -> UITextView {
    let textView = UITextView(usingTextLayoutManager: true) // TextKit 2
    textView.isEditable = false
    textView.isSelectable = true
    textView.isFindInteractionEnabled = true
    textView.alwaysBounceVertical = true
    textView.backgroundColor = .systemBackground
    textView.textContainerInset = UIEdgeInsets(top: 16, left: 16, bottom: 24, right: 16)
    textView.attributedText = MarkdownRenderer.render(text)
    let tap = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handleTap))
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
#endif
