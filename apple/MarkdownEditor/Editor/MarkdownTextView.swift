import SwiftUI
import UIKit
import MarkdownCore

/// The author-mode editing surface: a `UITextView` forced onto **TextKit 2**
/// (`usingTextLayoutManager: true`) so selection, caret, magnifier, dictation,
/// and the keyboard accessory are real platform behaviors (ARCHITECTURE §4.2).
///
/// M3 (FEAT-050): after edits, a 500 ms-debounced, off-main `core.diagnose` pass
/// underlines the offending ranges by severity. It never touches the keystroke
/// path (work runs on a background queue, results marshal back to the main actor).
/// Diagnostics are author-mode only — read mode is a separate view.
struct MarkdownTextView: UIViewRepresentable {
  @Binding var text: String

  func makeUIView(context: Context) -> UITextView {
    let textView = UITextView(usingTextLayoutManager: true) // TextKit 2
    textView.delegate = context.coordinator
    // Monospaced, but scaled for Dynamic Type (FEAT-020, M7).
    let editorFont = UIFontMetrics(forTextStyle: .body)
      .scaledFont(for: .monospacedSystemFont(ofSize: 16, weight: .regular))
    textView.font = editorFont
    textView.adjustsFontForContentSizeCategory = true
    textView.text = text
    textView.alwaysBounceVertical = true
    textView.autocorrectionType = .no       // markdown syntax, not prose autocorrect
    textView.autocapitalizationType = .none
    textView.smartQuotesType = .no
    textView.smartDashesType = .no
    textView.spellCheckingType = .yes       // spell check (FEAT-021, M7)
    textView.isFindInteractionEnabled = true // native find/replace, ⌘F (FEAT-016, M6)
    textView.textContainerInset = UIEdgeInsets(top: 12, left: 12, bottom: 12, right: 12)
    // New text must not inherit the diagnostic underline.
    textView.typingAttributes = [.font: editorFont, .foregroundColor: UIColor.label]
    context.coordinator.textView = textView
    context.coordinator.scheduleDiagnose()
    return textView
  }

  func updateUIView(_ textView: UITextView, context: Context) {
    if textView.text != text {
      textView.text = text
      context.coordinator.scheduleDiagnose()
    }
  }

  func makeCoordinator() -> Coordinator { Coordinator(text: $text) }

  final class Coordinator: NSObject, UITextViewDelegate {
    private let text: Binding<String>
    weak var textView: UITextView?
    private var pending: DispatchWorkItem?

    init(text: Binding<String>) { self.text = text }

    func textViewDidChange(_ textView: UITextView) {
      text.wrappedValue = textView.text
      scheduleDiagnose()
    }

    /// Debounced (500 ms) trigger; the diagnose itself runs off-main.
    func scheduleDiagnose() {
      pending?.cancel()
      let work = DispatchWorkItem { [weak self] in self?.runDiagnose() }
      pending = work
      DispatchQueue.main.asyncAfter(deadline: .now() + 0.5, execute: work)
    }

    private func runDiagnose() {
      guard let source = textView?.text else { return }
      DispatchQueue.global(qos: .userInitiated).async {
        let diagnostics = diagnose(text: source)
        DispatchQueue.main.async { [weak self] in
          guard let self, self.textView?.text == source else { return } // superseded
          self.apply(diagnostics, source: source)
        }
      }
    }

    private func apply(_ diagnostics: [Diagnostic], source: String) {
      guard let storage = textView?.textStorage else { return }
      let full = NSRange(location: 0, length: storage.length)
      let map = Utf16Map(source)
      storage.beginEditing()
      storage.removeAttribute(.underlineStyle, range: full)
      storage.removeAttribute(.underlineColor, range: full)
      for d in diagnostics {
        guard let r = map.range(byteStart: Int(d.span.start), byteEnd: Int(d.span.end)),
              NSMaxRange(r) <= storage.length, r.length > 0 else { continue }
        storage.addAttribute(.underlineStyle,
                             value: NSUnderlineStyle.thick.rawValue | NSUnderlineStyle.patternDot.rawValue,
                             range: r)
        storage.addAttribute(.underlineColor, value: color(for: d.severity), range: r)
      }
      storage.endEditing()
    }

    private func color(for severity: Severity) -> UIColor {
      switch severity {
      case .error: return .systemRed
      case .warning: return .systemOrange
      case .hint: return .systemGray
      }
    }
  }
}

/// Converts the core's UTF-8 byte offsets to `NSAttributedString` (UTF-16) ranges.
/// Built once per diagnose pass so the conversion is O(n), not O(n) per diagnostic.
private struct Utf16Map {
  private let bytes: [UInt8]
  private let scalars: String

  init(_ s: String) { self.scalars = s; self.bytes = Array(s.utf8) }

  func range(byteStart: Int, byteEnd: Int) -> NSRange? {
    guard byteStart >= 0, byteEnd <= bytes.count, byteStart <= byteEnd else { return nil }
    let start = utf16Index(byteStart)
    let end = utf16Index(byteEnd)
    return NSRange(location: start, length: end - start)
  }

  private func utf16Index(_ byteOffset: Int) -> Int {
    if byteOffset >= bytes.count { return scalars.utf16.count }
    return String(decoding: bytes[0..<byteOffset], as: UTF8.self).utf16.count
  }
}
