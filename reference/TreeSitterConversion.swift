/// Converts tree-sitter parse trees to EMParser's MarkdownAST/MarkdownNode types.
///
/// The tree-sitter-markdown grammar produces a different tree structure than
/// swift-markdown. This conversion maps between them so all downstream consumers
/// (EMEditor, EMFormatter, EMDoctor) see the same MarkdownNode types.

import Foundation
import SwiftTreeSitter
@preconcurrency import Markdown

// MARK: - MarkdownAST from tree-sitter

extension MarkdownAST {
    /// Creates a MarkdownAST from a tree-sitter root node.
    ///
    /// The resulting AST has the same MarkdownNode structure as swift-markdown
    /// would produce, allowing drop-in replacement for rendering and analysis.
    /// A swift-markdown Document is also parsed for round-trip formatting support.
    init(treeSitterRoot: SwiftTreeSitter.Node?, sourceText: String) {
        if let root = treeSitterRoot {
            self.root = MarkdownNode.fromTreeSitter(root, sourceText: sourceText)
        } else {
            self.root = MarkdownNode(type: .document, range: nil, children: [])
        }
        // Parse with swift-markdown for round-trip format() support.
        // This is a secondary parse — tree-sitter is primary for speed.
        self.markupDocument = Markdown.Document(
            parsing: sourceText,
            options: [.parseBlockDirectives]
        )
    }
}

// MARK: - MarkdownNode from tree-sitter

extension MarkdownNode {
    /// Recursively converts a tree-sitter node to a MarkdownNode.
    static func fromTreeSitter(_ node: SwiftTreeSitter.Node, sourceText: String) -> MarkdownNode {
        let type = treeSitterNodeType(node.nodeType ?? "")
        let range = treeSitterRange(node)

        var children: [MarkdownNode] = []
        for i in 0..<node.childCount {
            if let child = node.child(at: i) {
                // Skip anonymous nodes (punctuation, delimiters)
                if child.isNamed {
                    children.append(fromTreeSitter(child, sourceText: sourceText))
                }
            }
        }

        let literal = treeSitterLiteralText(node, type: type, sourceText: sourceText)

        return MarkdownNode(
            type: type,
            range: range,
            children: children,
            literalText: literal
        )
    }

    /// Maps tree-sitter node type strings to MarkdownNodeType.
    private static func treeSitterNodeType(_ nodeType: String) -> MarkdownNodeType {
        switch nodeType {
        // Block elements
        case "document":
            return .document
        case "atx_heading":
            return .heading(level: 1) // Refined by child inspection if needed
        case "setext_heading":
            return .heading(level: 1)
        case "paragraph", "inline":
            return .paragraph
        case "block_quote":
            return .blockQuote
        case "ordered_list", "list":
            return .orderedList
        case "bullet_list":
            return .unorderedList
        case "list_item":
            return .listItem(checkbox: nil)
        case "task_list_marker_checked":
            return .listItem(checkbox: .checked)
        case "task_list_marker_unchecked":
            return .listItem(checkbox: .unchecked)
        case "fenced_code_block", "indented_code_block", "code_block":
            return .codeBlock(language: nil)
        case "html_block":
            return .htmlBlock
        case "thematic_break":
            return .thematicBreak
        case "pipe_table":
            return .table
        case "pipe_table_header":
            return .tableHead
        case "pipe_table_row":
            return .tableRow
        case "pipe_table_cell":
            return .tableCell

        // Inline elements
        case "text_content", "text":
            return .text
        case "emphasis":
            return .emphasis
        case "strong_emphasis":
            return .strong
        case "strikethrough":
            return .strikethrough
        case "code_span":
            return .inlineCode
        case "link", "full_reference_link", "collapsed_reference_link", "shortcut_link":
            return .link(destination: nil)
        case "image":
            return .image(source: nil)
        case "html_tag", "html_open_tag", "html_close_tag":
            return .inlineHTML
        case "hard_line_break":
            return .lineBreak
        case "soft_line_break":
            return .softBreak

        // Section is a tree-sitter-markdown structural wrapper
        case "section":
            return .document

        default:
            return .paragraph
        }
    }

    /// Converts tree-sitter node range to EMParser SourceRange.
    private static func treeSitterRange(_ node: SwiftTreeSitter.Node) -> SourceRange {
        let points = node.pointRange
        return SourceRange(
            start: SourcePosition(
                line: Int(points.lowerBound.row) + 1,   // tree-sitter is 0-based
                column: Int(points.lowerBound.column) + 1
            ),
            end: SourcePosition(
                line: Int(points.upperBound.row) + 1,
                column: Int(points.upperBound.column) + 1
            )
        )
    }

    /// Extracts literal text for leaf nodes from the source text.
    private static func treeSitterLiteralText(
        _ node: SwiftTreeSitter.Node,
        type: MarkdownNodeType,
        sourceText: String
    ) -> String? {
        switch type {
        case .text, .inlineCode, .inlineHTML, .codeBlock:
            return extractText(from: node, in: sourceText)
        default:
            return nil
        }
    }

    /// Extracts the text content of a tree-sitter node from the source string.
    private static func extractText(from node: SwiftTreeSitter.Node, in source: String) -> String? {
        let bytes = node.byteRange
        let startByte = Int(bytes.lowerBound)
        let endByte = Int(bytes.upperBound)
        let utf8 = source.utf8
        guard startByte >= 0, endByte <= utf8.count, startByte < endByte else { return nil }
        let startIndex = utf8.index(utf8.startIndex, offsetBy: startByte)
        let endIndex = utf8.index(utf8.startIndex, offsetBy: endByte)
        return String(utf8[startIndex..<endIndex])
    }
}
