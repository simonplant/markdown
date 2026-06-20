#if os(macOS)
import AppKit
#else
import UIKit
#endif
import MarkdownCore

/// Renders markdown to a styled `NSAttributedString` for read mode (FEAT-049).
///
/// The core's `AstNode` gives reliable **byte-offset spans** and node kinds, but
/// not inline text (tree-sitter's inline text leaves are unnamed and dropped, so
/// `node.text` is nil) — like the doctor/formatter, which slice the *source* by
/// span. So this renderer slices the source bytes and strips markers (`#`, `**`,
/// `*`, backticks, `~~`, link brackets) using the styled nodes' spans.
/// Cross-platform (UIColor/NSColor via the Platform shims). IOS_BUILD_SPEC §4.3.
enum MarkdownRenderer {

  static func render(_ text: String) -> NSAttributedString {
    let bytes = Array(text.utf8)
    let root = parse(text: text)
    let out = NSMutableAttributedString()
    for block in blocks(of: root) {
      appendBlock(block, bytes: bytes, into: out)
    }
    while out.string.hasSuffix("\n") {
      out.deleteCharacters(in: NSRange(location: out.length - 1, length: 1))
    }
    return out
  }

  // MARK: Block structure

  private static func blocks(of node: AstNode) -> [AstNode] {
    if case .document = node.kind {
      return node.children.flatMap { blocks(of: $0) }
    }
    return [node]
  }

  private static func appendBlock(_ node: AstNode, bytes: [UInt8], into out: NSMutableAttributedString, indent: Int = 0) {
    switch node.kind {
    case .heading(let level):
      let start = headingContentStart(node, bytes: bytes)
      let end = trimWhitespace(start, Int(node.span.end), bytes: bytes, alsoHashes: true)
      let sizes: [CGFloat] = [30, 24, 20, 18, 16, 15]
      var style = Style()
      style.fontOverride = PlatformFont.systemFont(ofSize: sizes[min(max(Int(level) - 1, 0), 5)], weight: .bold)
      blockSpacing(out)
      appendInline(node, contentStart: start, contentEnd: end, bytes: bytes, base: style, into: out)

    case .paragraph:
      let start = Int(node.span.start)
      let end = trimWhitespace(start, Int(node.span.end), bytes: bytes, alsoHashes: false)
      blockSpacing(out)
      appendInline(node, contentStart: start, contentEnd: end, bytes: bytes, base: Style(), into: out)

    case .blockQuote:
      blockSpacing(out)
      out.append(NSAttributedString(string: "▏ ", attributes: [.foregroundColor: PlatformColor.tertiaryLabelCompat]))
      let inner = NSMutableAttributedString()
      for child in node.children { appendBlock(child, bytes: bytes, into: inner, indent: indent) }
      inner.addAttribute(.foregroundColor, value: PlatformColor.secondaryLabelCompat, range: NSRange(location: 0, length: inner.length))
      out.append(inner)

    case .unorderedList, .orderedList:
      var number = 1
      for child in node.children where isListItem(child) {
        blockSpacing(out)
        let marker = node.kind.isOrdered ? "\(number).  " : "•  "
        out.append(NSAttributedString(string: String(repeating: "    ", count: indent) + marker,
                                      attributes: [.foregroundColor: PlatformColor.secondaryLabelCompat,
                                                   .font: PlatformFont.bodyFont]))
        for sub in child.children {
          switch sub.kind {
          case .unorderedList, .orderedList:
            appendBlock(sub, bytes: bytes, into: out, indent: indent + 1)
          default:
            appendInline(sub, contentStart: Int(sub.span.start),
                         contentEnd: trimWhitespace(Int(sub.span.start), Int(sub.span.end), bytes: bytes, alsoHashes: false),
                         bytes: bytes, base: Style(), into: out)
          }
        }
        number += 1
      }

    case .fencedCodeBlock, .indentedCodeBlock:
      blockSpacing(out)
      out.append(NSAttributedString(string: codeBlockContent(node, bytes: bytes), attributes: [
        .font: PlatformFont.monospacedSystemFont(ofSize: 14, weight: .regular),
        .foregroundColor: PlatformColor.labelCompat,
        .backgroundColor: PlatformColor.secondaryFillCompat,
      ]))

    case .thematicBreak:
      blockSpacing(out)
      out.append(NSAttributedString(string: "—————", attributes: [.foregroundColor: PlatformColor.tertiaryLabelCompat]))

    case .table:
      blockSpacing(out)
      out.append(NSAttributedString(string: slice(bytes, Int(node.span.start), Int(node.span.end)),
                                    attributes: [.font: PlatformFont.monospacedSystemFont(ofSize: 13, weight: .regular)]))

    default:
      blockSpacing(out)
      appendInline(node, contentStart: Int(node.span.start),
                   contentEnd: trimWhitespace(Int(node.span.start), Int(node.span.end), bytes: bytes, alsoHashes: false),
                   bytes: bytes, base: Style(), into: out)
    }
  }

  // MARK: Inline (span overlay)

  private struct Style {
    var bold = false
    var italic = false
    var code = false
    var strike = false
    var link = false
    var fontOverride: PlatformFont?
  }

  private static func appendInline(_ node: AstNode, contentStart: Int, contentEnd: Int,
                                   bytes: [UInt8], base: Style, into out: NSMutableAttributedString) {
    var styled: [AstNode] = []
    collectStyled(node, into: &styled)
    styled.sort { $0.span.start < $1.span.start }

    var cursor = contentStart
    for s in styled {
      let ss = Int(s.span.start), se = Int(s.span.end)
      if ss < cursor || se > contentEnd || se <= ss { continue }
      if ss > cursor {
        out.append(NSAttributedString(string: slice(bytes, cursor, ss), attributes: attributes(base)))
      }
      var st = base
      var innerStart = ss, innerEnd = se
      switch s.kind {
      case .strong: st.bold = true; innerStart = ss + 2; innerEnd = se - 2
      case .emphasis: st.italic = true; innerStart = ss + 1; innerEnd = se - 1
      case .strikethrough: st.strike = true; innerStart = ss + 2; innerEnd = se - 2
      case .inlineCode:
        st.code = true
        let ticks = leadingCount(0x60, from: ss, end: se, bytes: bytes)
        innerStart = ss + ticks; innerEnd = se - ticks
      case .link:
        st.link = true
        if let close = firstIndex(of: 0x5D, from: ss, end: se, bytes: bytes) {
          innerStart = ss + 1; innerEnd = close
        }
      default: break
      }
      if innerEnd >= innerStart {
        out.append(NSAttributedString(string: slice(bytes, innerStart, innerEnd), attributes: attributes(st)))
      }
      cursor = se
    }
    if cursor < contentEnd {
      out.append(NSAttributedString(string: slice(bytes, cursor, contentEnd), attributes: attributes(base)))
    }
  }

  private static func collectStyled(_ node: AstNode, into arr: inout [AstNode]) {
    for c in node.children {
      switch c.kind {
      case .strong, .emphasis, .strikethrough, .inlineCode, .link, .autolink:
        arr.append(c)
      default:
        collectStyled(c, into: &arr)
      }
    }
  }

  private static func attributes(_ style: Style) -> [NSAttributedString.Key: Any] {
    var attrs: [NSAttributedString.Key: Any] = [.foregroundColor: PlatformColor.labelCompat]
    if style.code {
      attrs[.font] = PlatformFont.monospacedSystemFont(ofSize: 16, weight: .regular)
      attrs[.backgroundColor] = PlatformColor.secondaryFillCompat
    } else if let override = style.fontOverride {
      attrs[.font] = override
    } else {
      attrs[.font] = styledFont(PlatformFont.bodyFont, bold: style.bold, italic: style.italic)
    }
    if style.strike { attrs[.strikethroughStyle] = NSUnderlineStyle.single.rawValue }
    if style.link {
      attrs[.foregroundColor] = PlatformColor.linkCompat
      attrs[.underlineStyle] = NSUnderlineStyle.single.rawValue
    }
    return attrs
  }

  // MARK: Byte helpers

  private static func slice(_ bytes: [UInt8], _ start: Int, _ end: Int) -> String {
    guard start >= 0, end <= bytes.count, start < end else { return "" }
    return String(decoding: bytes[start..<end], as: UTF8.self)
  }

  private static func headingContentStart(_ node: AstNode, bytes: [UInt8]) -> Int {
    var i = Int(node.span.start)
    let e = Int(node.span.end)
    while i < e, bytes[i] == 0x23 { i += 1 }
    while i < e, bytes[i] == 0x20 || bytes[i] == 0x09 { i += 1 }
    return i
  }

  private static func trimWhitespace(_ start: Int, _ end: Int, bytes: [UInt8], alsoHashes: Bool) -> Int {
    var e = end
    while e > start {
      let b = bytes[e - 1]
      if b == 0x0A || b == 0x0D || b == 0x20 || b == 0x09 || (alsoHashes && b == 0x23) { e -= 1 } else { break }
    }
    return e
  }

  private static func codeBlockContent(_ node: AstNode, bytes: [UInt8]) -> String {
    let raw = slice(bytes, Int(node.span.start), Int(node.span.end))
    var lines = raw.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
    if let first = lines.first, first.trimmingCharacters(in: .whitespaces).hasPrefix("```") { lines.removeFirst() }
    if let last = lines.last, last.trimmingCharacters(in: .whitespaces).hasPrefix("```") { lines.removeLast() }
    return lines.joined(separator: "\n")
  }

  private static func leadingCount(_ byte: UInt8, from start: Int, end: Int, bytes: [UInt8]) -> Int {
    var n = 0, i = start
    while i < end, bytes[i] == byte { n += 1; i += 1 }
    return max(n, 1)
  }

  private static func firstIndex(of byte: UInt8, from start: Int, end: Int, bytes: [UInt8]) -> Int? {
    var i = start
    while i < end { if bytes[i] == byte { return i }; i += 1 }
    return nil
  }

  private static func isListItem(_ node: AstNode) -> Bool {
    if case .listItem = node.kind { return true }
    return false
  }

  private static func blockSpacing(_ out: NSMutableAttributedString) {
    if out.length > 0 { out.append(NSAttributedString(string: "\n\n")) }
  }
}

private extension NodeKind {
  var isOrdered: Bool {
    if case .orderedList = self { return true }
    return false
  }
}
