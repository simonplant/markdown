import EMCore
import EMParser

/// Auto-aligns table columns with space padding as the user types per FEAT-052 AC-1.
///
/// Fires on regular character input and deletion when the cursor is inside
/// a markdown table. Re-aligns all columns after each keystroke so that
/// pipes stay vertically aligned.
/// Does not fire inside fenced code blocks or on the separator row.
public struct TableAlignmentRule: FormattingRule, Sendable {

    public init() {}

    public func evaluate(_ context: FormattingContext) -> TextMutation? {
        let insertedText: String
        switch context.trigger {
        case .characterInput(let chars):
            // Don't intercept multi-line paste — too complex for table alignment
            if chars.contains("\n") { return nil }
            insertedText = chars
        case .delete:
            insertedText = ""
        default:
            return nil
        }

        let text = context.text
        let cursor = context.cursorPosition

        // Find table at cursor position in the original text
        guard let table = findTable(in: text, at: cursor) else { return nil }
        guard let rowIdx = tableRowIndex(cursor: cursor, lineRanges: table.lineRanges) else {
            return nil
        }

        // Don't auto-align on the separator row
        if table.separatorLineIndex == rowIdx { return nil }

        // Apply the edit to get the post-edit text
        let editRange = context.replacementRange
        let prefixStr = String(text[..<editRange.lowerBound])
        let editedText = prefixStr + insertedText + String(text[editRange.upperBound...])

        // Cursor position after the edit (character offset from start)
        let cursorCharOffset = prefixStr.count + insertedText.count
        let cursorAfterEdit = editedText.index(
            editedText.startIndex,
            offsetBy: cursorCharOffset
        )

        // Find the table in the edited text
        guard let editedTable = findTable(in: editedText, at: cursorAfterEdit) else {
            return nil
        }
        guard let editedRowIdx = tableRowIndex(
            cursor: cursorAfterEdit, lineRanges: editedTable.lineRanges
        ) else {
            return nil
        }

        // Don't align if cursor landed on separator after edit
        if editedTable.separatorLineIndex == editedRowIdx { return nil }

        // Determine cursor's cell and offset within the cell content
        let editedRow = editedTable.lines[editedRowIdx]
        let cursorInLine = editedText.distance(
            from: editedTable.lineRanges[editedRowIdx].lowerBound,
            to: cursorAfterEdit
        )
        let cellIdx = tableCellIndex(in: editedRow, cursorOffsetInLine: cursorInLine)
        let cursorInContent = cellContentCursorOffset(
            in: editedRow, cellIndex: cellIdx, cursorInRow: cursorInLine
        )

        // Parse cells and align
        let rows = normalizeRows(
            editedTable.lines.map { splitTableCells($0) },
            columnCount: editedTable.columnCount
        )

        let aligned = alignTable(
            rows: rows,
            separatorIndex: editedTable.separatorLineIndex,
            columnCount: editedTable.columnCount
        )

        // Compute cursor position in the aligned table
        let alignedLines = aligned.split(
            separator: "\n", omittingEmptySubsequences: false
        ).map(String.init)
        guard editedRowIdx < alignedLines.count else { return nil }
        let alignedRow = alignedLines[editedRowIdx]
        let alignedCellStart = cursorOffsetForCell(
            in: alignedRow, cellIndex: cellIdx
        )

        // Clamp cursor to cell content length in the aligned version
        let cellContent = cellIdx < rows[editedRowIdx].count
            ? rows[editedRowIdx][cellIdx] : ""
        let clampedCursor = min(cursorInContent, cellContent.count)

        let cursorInAlignedRow = alignedCellStart + clampedCursor

        // Compute absolute offset in the result text
        var absoluteOffset = 0
        for i in 0..<editedRowIdx {
            absoluteOffset += alignedLines[i].count + 1 // +1 for newline
        }
        absoluteOffset += cursorInAlignedRow

        let prefixOffset = text.distance(
            from: text.startIndex, to: table.range.lowerBound
        )

        return makeMutation(
            text: text,
            range: table.range,
            replacement: aligned,
            cursorOffsetInResult: prefixOffset + absoluteOffset
        )
    }
}
