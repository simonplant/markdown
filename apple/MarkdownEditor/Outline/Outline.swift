import Foundation
import MarkdownCore

/// One heading in the document outline (FEAT-039).
struct OutlineItem: Identifiable, Hashable {
  let id = UUID()
  let level: Int
  let title: String
  /// UTF-16 offset of the heading start (for `scrollRangeToVisible`).
  let utf16Offset: Int
}

enum Outline {
  /// Build the heading outline from the core's AST: title text (markers stripped)
  /// + the UTF-16 offset to scroll to. All parsing stays in the core.
  static func of(_ text: String) -> [OutlineItem] {
    let bytes = Array(text.utf8)
    let root = parse(text: text)
    var items: [OutlineItem] = []
    collect(root, bytes: bytes, into: &items)
    return items
  }

  private static func collect(_ node: AstNode, bytes: [UInt8], into items: inout [OutlineItem]) {
    if case .heading(let level) = node.kind {
      let start = headingContentStart(node, bytes: bytes)
      let end = trimTrailing(start, Int(node.span.end), bytes: bytes)
      let title = String(decoding: bytes[min(start, bytes.count)..<min(end, bytes.count)], as: UTF8.self)
        .trimmingCharacters(in: .whitespaces)
      if !title.isEmpty {
        items.append(OutlineItem(level: Int(level), title: title,
                                 utf16Offset: utf16Index(Int(node.span.start), bytes: bytes)))
      }
    }
    for child in node.children { collect(child, bytes: bytes, into: &items) }
  }

  private static func headingContentStart(_ node: AstNode, bytes: [UInt8]) -> Int {
    var i = Int(node.span.start)
    let e = min(Int(node.span.end), bytes.count)
    while i < e, bytes[i] == 0x23 { i += 1 }
    while i < e, bytes[i] == 0x20 || bytes[i] == 0x09 { i += 1 }
    return i
  }

  private static func trimTrailing(_ start: Int, _ end: Int, bytes: [UInt8]) -> Int {
    var e = min(end, bytes.count)
    // Trim trailing whitespace/newlines.
    while e > start {
      let b = bytes[e - 1]
      if b == 0x0A || b == 0x0D || b == 0x20 || b == 0x09 { e -= 1 } else { break }
    }
    // Strip an ATX closing '#' run only when it is separated from the heading
    // text by whitespace (`# Heading ###`). A '#' fused to the text — `# C#`,
    // `# F#`, `# C++ vs C#` — is content and must be kept.
    var h = e
    while h > start, bytes[h - 1] == 0x23 { h -= 1 }
    if h < e, h > start, bytes[h - 1] == 0x20 || bytes[h - 1] == 0x09 {
      e = h
      while e > start, bytes[e - 1] == 0x20 || bytes[e - 1] == 0x09 { e -= 1 }
    }
    return e
  }

  private static func utf16Index(_ byteOffset: Int, bytes: [UInt8]) -> Int {
    let clamped = min(byteOffset, bytes.count)
    return String(decoding: bytes[0..<clamped], as: UTF8.self).utf16.count
  }
}
