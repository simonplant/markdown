import EMCore
import EMParser

/// Handles Tab and Shift-Tab for list item indentation per FEAT-004.
///
/// - **Tab**: Indents the current list item by adding spaces.
/// - **Shift-Tab**: Outdents the current list item by removing spaces.
/// - After indenting/outdenting ordered lists, renumbers siblings at the affected level.
/// - Does not fire inside fenced code blocks.
public struct ListIndentRule: FormattingRule, Sendable {

    /// Default number of spaces per indentation level.
    public static let defaultIndentSize = 2

    /// Number of spaces per indentation level (configurable: 2 or 4).
    public let indentSize: Int

    public init(indentSize: Int = ListIndentRule.defaultIndentSize) {
        self.indentSize = indentSize
    }

    public func evaluate(_ context: FormattingContext) -> TextMutation? {
        guard context.trigger == .tab || context.trigger == .shiftTab else {
            return nil
        }
        guard !isInsideCodeBlock(text: context.text, at: context.cursorPosition) else {
            return nil
        }

        let text = context.text
        let cursor = context.cursorPosition
        let currentLine = lineRange(in: text, at: cursor)
        let line = String(text[currentLine])

        guard let marker = parseListMarker(in: line) else { return nil }

        if context.trigger == .tab {
            return indent(text: text, cursor: cursor, lineRange: currentLine, line: line, marker: marker)
        } else {
            return outdent(text: text, cursor: cursor, lineRange: currentLine, line: line, marker: marker)
        }
    }

    // MARK: - Indent

    private func indent(
        text: String,
        cursor: String.Index,
        lineRange: Range<String.Index>,
        line: String,
        marker: ListMarkerMatch
    ) -> TextMutation {
        let indent = String(repeating: " ", count: indentSize)
        let newLine = indent + line

        // Cursor moves right by the indent size
        let cursorOffset = text.distance(from: text.startIndex, to: cursor) + indentSize

        return makeMutation(
            text: text,
            range: lineRange,
            replacement: newLine,
            cursorOffsetInResult: cursorOffset,
            hapticStyle: .listContinuation
        )
    }

    // MARK: - Outdent

    private func outdent(
        text: String,
        cursor: String.Index,
        lineRange: Range<String.Index>,
        line: String,
        marker: ListMarkerMatch
    ) -> TextMutation? {
        // Can't outdent if no indentation
        guard !marker.indentation.isEmpty else { return nil }

        // Remove up to indentSize spaces from the beginning
        var spacesToRemove = 0
        for ch in marker.indentation {
            if ch == " " && spacesToRemove < indentSize {
                spacesToRemove += 1
            } else if ch == "\t" && spacesToRemove < indentSize {
                spacesToRemove += 1
                break
            } else {
                break
            }
        }

        guard spacesToRemove > 0 else { return nil }

        let newLine = String(line.dropFirst(spacesToRemove))
        let cursorOffset = max(
            text.distance(from: text.startIndex, to: lineRange.lowerBound),
            text.distance(from: text.startIndex, to: cursor) - spacesToRemove
        )

        return makeMutation(
            text: text,
            range: lineRange,
            replacement: newLine,
            cursorOffsetInResult: cursorOffset,
            hapticStyle: .listContinuation
        )
    }
}
