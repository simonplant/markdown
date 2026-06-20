import SwiftUI
import MarkdownCore

/// Converts the core's UTF-8 byte offsets to `NSAttributedString` (UTF-16) ranges.
struct Utf16Map {
  private let bytes: [UInt8]
  private let scalars: String
  init(_ s: String) { self.scalars = s; self.bytes = Array(s.utf8) }
  func range(byteStart: Int, byteEnd: Int) -> NSRange? {
    guard byteStart >= 0, byteEnd <= bytes.count, byteStart <= byteEnd else { return nil }
    return NSRange(location: utf16Index(byteStart), length: utf16Index(byteEnd) - utf16Index(byteStart))
  }
  private func utf16Index(_ byteOffset: Int) -> Int {
    if byteOffset >= bytes.count { return scalars.utf16.count }
    return String(decoding: bytes[0..<byteOffset], as: UTF8.self).utf16.count
  }
}

#if os(macOS)
import AppKit

/// Author-mode editing surface on macOS — `NSTextView` over the same Rust core.
struct MarkdownTextView: NSViewRepresentable {
  @Binding var text: String
  @Binding var scrollTarget: Int?  // UTF-16 offset to scroll to (outline nav, FEAT-039)

  func makeNSView(context: Context) -> NSScrollView {
    let scroll = NSTextView.scrollableTextView()
    let textView = scroll.documentView as! NSTextView
    textView.delegate = context.coordinator
    textView.font = .monospacedSystemFont(ofSize: 14, weight: .regular)
    textView.string = text
    textView.isRichText = false
    textView.isAutomaticQuoteSubstitutionEnabled = false
    textView.isAutomaticDashSubstitutionEnabled = false
    textView.isContinuousSpellCheckingEnabled = true
    textView.allowsUndo = true
    textView.textContainerInset = NSSize(width: 8, height: 12)
    context.coordinator.textView = textView
    context.coordinator.scheduleDiagnose()
    return scroll
  }

  func updateNSView(_ scroll: NSScrollView, context: Context) {
    guard let textView = scroll.documentView as? NSTextView else { return }
    if textView.string != text {
      textView.string = text
      context.coordinator.scheduleDiagnose()
    }
    if let target = scrollTarget {
      let loc = max(0, min(target, (textView.string as NSString).length))
      textView.scrollRangeToVisible(NSRange(location: loc, length: 0))
      textView.setSelectedRange(NSRange(location: loc, length: 0))
      DispatchQueue.main.async { scrollTarget = nil }
    }
  }

  func makeCoordinator() -> Coordinator { Coordinator(text: $text) }

  final class Coordinator: NSObject, NSTextViewDelegate {
    private let text: Binding<String>
    weak var textView: NSTextView?
    private var pending: DispatchWorkItem?
    init(text: Binding<String>) { self.text = text }

    func textDidChange(_ notification: Notification) {
      guard let tv = notification.object as? NSTextView else { return }
      text.wrappedValue = tv.string
      scheduleDiagnose()
    }

    func scheduleDiagnose() {
      pending?.cancel()
      let work = DispatchWorkItem { [weak self] in self?.runDiagnose() }
      pending = work
      DispatchQueue.main.asyncAfter(deadline: .now() + 0.5, execute: work)
    }

    private func runDiagnose() {
      guard let source = textView?.string else { return }
      DispatchQueue.global(qos: .userInitiated).async {
        let diagnostics = diagnose(text: source)
        DispatchQueue.main.async { [weak self] in
          guard let self, self.textView?.string == source, let storage = self.textView?.textStorage else { return }
          let full = NSRange(location: 0, length: storage.length)
          let map = Utf16Map(source)
          storage.beginEditing()
          storage.removeAttribute(.underlineStyle, range: full)
          storage.removeAttribute(.underlineColor, range: full)
          for d in diagnostics {
            guard let r = map.range(byteStart: Int(d.span.start), byteEnd: Int(d.span.end)),
                  NSMaxRange(r) <= storage.length, r.length > 0 else { continue }
            storage.addAttribute(.underlineStyle,
                                 value: NSUnderlineStyle.thick.rawValue | NSUnderlineStyle.patternDot.rawValue, range: r)
            storage.addAttribute(.underlineColor, value: severityColor(d.severity), range: r)
          }
          storage.endEditing()
        }
      }
    }
  }
}

private func severityColor(_ s: Severity) -> NSColor {
  switch s { case .error: return .systemRed; case .warning: return .systemOrange; case .hint: return .systemGray }
}

#else
import UIKit

/// Author-mode editing surface on iOS — `UITextView` on TextKit 2.
struct MarkdownTextView: UIViewRepresentable {
  @Binding var text: String
  @Binding var scrollTarget: Int?  // UTF-16 offset to scroll to (outline nav, FEAT-039)

  func makeUIView(context: Context) -> UITextView {
    let textView = UITextView(usingTextLayoutManager: true) // TextKit 2
    textView.delegate = context.coordinator
    let editorFont = UIFontMetrics(forTextStyle: .body)
      .scaledFont(for: .monospacedSystemFont(ofSize: 16, weight: .regular))
    textView.font = editorFont
    textView.adjustsFontForContentSizeCategory = true
    textView.text = text
    textView.alwaysBounceVertical = true
    textView.autocorrectionType = .no
    textView.autocapitalizationType = .none
    textView.smartQuotesType = .no
    textView.smartDashesType = .no
    textView.spellCheckingType = .yes
    textView.isFindInteractionEnabled = true
    textView.textContainerInset = UIEdgeInsets(top: 12, left: 12, bottom: 12, right: 12)
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
    if let target = scrollTarget {
      let loc = max(0, min(target, (textView.text as NSString).length))
      textView.scrollRangeToVisible(NSRange(location: loc, length: 0))
      textView.selectedRange = NSRange(location: loc, length: 0)
      DispatchQueue.main.async { scrollTarget = nil }
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
          guard let self, self.textView?.text == source, let storage = self.textView?.textStorage else { return }
          let full = NSRange(location: 0, length: storage.length)
          let map = Utf16Map(source)
          storage.beginEditing()
          storage.removeAttribute(.underlineStyle, range: full)
          storage.removeAttribute(.underlineColor, range: full)
          for d in diagnostics {
            guard let r = map.range(byteStart: Int(d.span.start), byteEnd: Int(d.span.end)),
                  NSMaxRange(r) <= storage.length, r.length > 0 else { continue }
            storage.addAttribute(.underlineStyle,
                                 value: NSUnderlineStyle.thick.rawValue | NSUnderlineStyle.patternDot.rawValue, range: r)
            storage.addAttribute(.underlineColor, value: severityColor(d.severity), range: r)
          }
          storage.endEditing()
        }
      }
    }
  }
}

private func severityColor(_ s: Severity) -> UIColor {
  switch s { case .error: return .systemRed; case .warning: return .systemOrange; case .hint: return .systemGray }
}
#endif
