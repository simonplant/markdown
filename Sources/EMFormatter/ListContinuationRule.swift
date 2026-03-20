import EMCore
import EMParser

/// Handles Enter key in list items per FEAT-004.
///
/// Behaviors:
/// - **Continue**: If the current line is a list item with content, pressing Enter
///   inserts a new line with the correct marker and indentation. For ordered lists,
///   subsequent siblings are renumbered.
/// - **Terminate**: If the current line is an empty list item (marker only, no content),
///   pressing Enter removes the marker, ending the list.
/// - **Code block suppression**: Does not fire when cursor is inside a fenced code block.
public struct ListContinuationRule: FormattingRule, Sendable {

    public init() {}

    public func evaluate(_ context: FormattingContext) -> TextMutation? {
        guard context.trigger == .enter else { return nil }
        guard !isInsideCodeBlock(text: context.text, at: context.cursorPosition) else {
            return nil
        }

        let text = context.text
        let cursor = context.cursorPosition
        let currentLine = lineRange(in: text, at: cursor)
        let line = String(text[currentLine])

        guard let marker = parseListMarker(in: line) else { return nil }

        // Content after the marker prefix
        let prefixEndOffset = marker.fullPrefix.count
        let contentStart = line.index(line.startIndex, offsetBy: prefixEndOffset)
        let content = line[contentStart...]

        if content.allSatisfy({ $0 == " " || $0 == "\t" }) || content.isEmpty {
            return terminateList(
                text: text,
                lineRange: currentLine,
                marker: marker
            )
        } else {
            return continueList(
                text: text,
                cursor: cursor,
                lineRange: currentLine,
                marker: marker
            )
        }
    }

    // MARK: - Continue List

    private func continueList(
        text: String,
        cursor: String.Index,
        lineRange: Range<String.Index>,
        marker: ListMarkerMatch
    ) -> TextMutation {
        let lineEnd = lineRange.upperBound

        // Text after cursor on current line moves to the new line
        let textAfterCursor: String
        if cursor < lineEnd {
            textAfterCursor = String(text[cursor..<lineEnd])
        } else {
            textAfterCursor = ""
        }

        // Build the new line
        let nextMarker = marker.nextMarker
        let checkboxPart = marker.checkbox != nil ? "[ ] " : ""
        let newLinePrefix = "\(marker.indentation)\(nextMarker) \(checkboxPart)"
        let newLine = "\n\(newLinePrefix)\(textAfterCursor)"

        // Handle ordered list renumbering of subsequent siblings
        var replacement = newLine
        var endRange = lineEnd

        if marker.isOrdered, let num = marker.orderedNumber, let suffix = marker.orderedSuffix {
            let renumberStart = num + 2 // Current is num, new is num+1, next sibling becomes num+2
            if let renumbered = renumberOrderedSiblings(
                in: text,
                after: lineEnd,
                indentation: marker.indentation,
                startNumber: renumberStart,
                orderedSuffix: suffix
            ) {
                // Include the newline between current line end and renumbered content
                replacement = newLine + "\n" + renumbered.replacement
                endRange = renumbered.range.upperBound
            }
        }

        // Cursor should be at end of the new marker prefix (before textAfterCursor)
        let prefixLength = text.distance(from: text.startIndex, to: cursor)
        let cursorOffsetInResult = prefixLength + 1 + newLinePrefix.count // +1 for \n

        return makeMutation(
            text: text,
            range: cursor..<endRange,
            replacement: replacement,
            cursorOffsetInResult: cursorOffsetInResult,
            hapticStyle: .listContinuation
        )
    }

    // MARK: - Terminate List

    private func terminateList(
        text: String,
        lineRange: Range<String.Index>,
        marker: ListMarkerMatch
    ) -> TextMutation {
        let lineStart = lineRange.lowerBound
        let lineEnd = lineRange.upperBound

        // Remove the empty marker. Handle renumbering of subsequent ordered siblings.
        var endRange = lineEnd

        if marker.isOrdered, let suffix = marker.orderedSuffix {
            if let renumbered = renumberOrderedSiblings(
                in: text,
                after: lineEnd,
                indentation: marker.indentation,
                startNumber: marker.orderedNumber ?? 1,
                orderedSuffix: suffix
            ) {
                // Replace empty marker line + subsequent siblings
                endRange = renumbered.range.upperBound
                let replacement = renumbered.replacement
                let cursorOffset = text.distance(from: text.startIndex, to: lineStart)
                return makeMutation(
                    text: text,
                    range: lineStart..<endRange,
                    replacement: replacement,
                    cursorOffsetInResult: cursorOffset,
                    hapticStyle: .listContinuation
                )
            }
        }

        // Simple case: just remove the marker line content
        let cursorOffset = text.distance(from: text.startIndex, to: lineStart)
        return makeMutation(
            text: text,
            range: lineStart..<lineEnd,
            replacement: "",
            cursorOffsetInResult: cursorOffset,
            hapticStyle: .listContinuation
        )
    }
}
