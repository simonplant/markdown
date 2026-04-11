import EMCore

// MARK: - List Marker Detection

/// A parsed list marker from a line of text.
struct ListMarkerMatch: Sendable {
    /// Leading whitespace before the marker.
    let indentation: String
    /// The marker character(s): "-", "*", "+", or "1.", "2)", etc.
    let marker: String
    /// Task list checkbox if present: "[ ] ", "[x] ", "[X] ".
    let checkbox: String?
    /// The full prefix including indentation, marker, space, and checkbox.
    let fullPrefix: String
    /// Whether this is an ordered list marker.
    let isOrdered: Bool
    /// The number for ordered list markers.
    let orderedNumber: Int?
    /// The separator style for ordered markers: "." or ")".
    let orderedSuffix: String?

    /// Builds the next marker for list continuation.
    var nextMarker: String {
        if isOrdered, let num = orderedNumber, let suffix = orderedSuffix {
            return "\(num + 1)\(suffix)"
        }
        return marker
    }

    /// Builds a marker with a specific number (for renumbering).
    func markerWithNumber(_ num: Int) -> String {
        guard isOrdered, let suffix = orderedSuffix else { return marker }
        return "\(num)\(suffix)"
    }
}

/// Parses a list marker from the beginning of a line.
/// Returns nil if the line does not start with a recognized list marker.
func parseListMarker(in line: String) -> ListMarkerMatch? {
    var idx = line.startIndex

    // Parse leading whitespace
    while idx < line.endIndex && (line[idx] == " " || line[idx] == "\t") {
        idx = line.index(after: idx)
    }
    let indentation = String(line[line.startIndex..<idx])

    guard idx < line.endIndex else { return nil }

    // Try unordered marker: -, *, +
    if line[idx] == "-" || line[idx] == "*" || line[idx] == "+" {
        let markerChar = String(line[idx])
        idx = line.index(after: idx)
        guard idx < line.endIndex && line[idx] == " " else { return nil }
        idx = line.index(after: idx)

        // Check for task list checkbox: [ ], [x], [X]
        let checkbox = parseCheckbox(in: line, at: &idx)

        let fullPrefix = String(line[line.startIndex..<idx])
        return ListMarkerMatch(
            indentation: indentation,
            marker: markerChar,
            checkbox: checkbox,
            fullPrefix: fullPrefix,
            isOrdered: false,
            orderedNumber: nil,
            orderedSuffix: nil
        )
    }

    // Try ordered marker: digits + (. or ))
    if line[idx].isNumber {
        let numStart = idx
        while idx < line.endIndex && line[idx].isNumber {
            idx = line.index(after: idx)
        }
        let numStr = String(line[numStart..<idx])
        guard !numStr.isEmpty, idx < line.endIndex else { return nil }

        let suffixChar = line[idx]
        guard suffixChar == "." || suffixChar == ")" else { return nil }
        let suffix = String(suffixChar)
        idx = line.index(after: idx)

        guard idx < line.endIndex && line[idx] == " " else { return nil }
        idx = line.index(after: idx)

        let fullPrefix = String(line[line.startIndex..<idx])
        return ListMarkerMatch(
            indentation: indentation,
            marker: numStr + suffix,
            checkbox: nil,
            fullPrefix: fullPrefix,
            isOrdered: true,
            orderedNumber: Int(numStr),
            orderedSuffix: suffix
        )
    }

    return nil
}

/// Parses a task list checkbox at the current position.
private func parseCheckbox(in line: String, at idx: inout String.Index) -> String? {
    guard idx < line.endIndex && line[idx] == "[" else { return nil }
    let checkStart = idx

    // Need: [ + (space|x|X) + ] + space
    let next1 = line.index(after: idx)
    guard next1 < line.endIndex else { return nil }
    let middle = line[next1]
    guard middle == " " || middle == "x" || middle == "X" else { return nil }

    let next2 = line.index(after: next1)
    guard next2 < line.endIndex && line[next2] == "]" else { return nil }

    let next3 = line.index(after: next2)
    guard next3 < line.endIndex && line[next3] == " " else { return nil }

    let afterCheckbox = line.index(after: next3)
    let checkbox = String(line[checkStart..<afterCheckbox])
    idx = afterCheckbox
    return checkbox
}

// MARK: - Line Utilities

/// Returns the range of the line containing the given index.
/// The range excludes the trailing newline character.
func lineRange(in text: String, at position: String.Index) -> Range<String.Index> {
    let lineStart = lineStartIndex(in: text, at: position)
    let lineEnd = lineEndIndex(in: text, at: position)
    return lineStart..<lineEnd
}

/// Returns the start index of the line containing the given position.
func lineStartIndex(in text: String, at position: String.Index) -> String.Index {
    if position == text.startIndex { return text.startIndex }
    // Search backward for newline
    var idx = position
    if idx > text.startIndex {
        idx = text.index(before: idx)
    }
    while idx > text.startIndex {
        if text[idx] == "\n" {
            return text.index(after: idx)
        }
        idx = text.index(before: idx)
    }
    // Check the first character
    if text[idx] == "\n" {
        return text.index(after: idx)
    }
    return text.startIndex
}

/// Returns the end index of the line containing the given position (before newline).
func lineEndIndex(in text: String, at position: String.Index) -> String.Index {
    var idx = position
    while idx < text.endIndex {
        if text[idx] == "\n" {
            return idx
        }
        idx = text.index(after: idx)
    }
    return text.endIndex
}

// MARK: - Code Block Detection

/// Checks if the cursor is inside a fenced code block.
/// Uses text-based fence counting for reliability (works without AST).
func isInsideCodeBlock(text: String, at cursor: String.Index) -> Bool {
    var fenceCount = 0
    var lineStart = text.startIndex

    while lineStart < cursor && lineStart < text.endIndex {
        // Find end of this line
        var lineEnd = lineStart
        while lineEnd < text.endIndex && text[lineEnd] != "\n" {
            lineEnd = text.index(after: lineEnd)
        }

        // Only check lines that start before the cursor
        if lineStart < cursor || lineStart == text.startIndex {
            let line = text[lineStart..<lineEnd]
            let trimmed = line.drop(while: { $0 == " " || $0 == "\t" })
            if trimmed.hasPrefix("```") || trimmed.hasPrefix("~~~") {
                fenceCount += 1
            }
        }

        // Move to next line
        if lineEnd < text.endIndex {
            lineStart = text.index(after: lineEnd)
        } else {
            break
        }
    }

    return fenceCount % 2 == 1
}

// MARK: - Ordered List Renumbering

/// Scans forward from a position and finds consecutive ordered list lines
/// at the same indentation level, returning the range and renumbered text.
///
/// - Parameters:
///   - text: The full document text.
///   - afterPosition: Start scanning from this position (typically end of a line).
///   - indentation: The indentation level to match.
///   - startNumber: The number to assign to the first sibling found.
///   - orderedSuffix: The separator style ("." or ")").
/// - Returns: The range of text that was renumbered and the replacement, or nil if nothing to renumber.
func renumberOrderedSiblings(
    in text: String,
    after afterPosition: String.Index,
    indentation: String,
    startNumber: Int,
    orderedSuffix: String
) -> (range: Range<String.Index>, replacement: String)? {
    guard afterPosition < text.endIndex else { return nil }

    // Skip the newline at afterPosition if present
    var scanStart = afterPosition
    if scanStart < text.endIndex && text[scanStart] == "\n" {
        scanStart = text.index(after: scanStart)
    }

    var currentNumber = startNumber
    var renumberedLines: [String] = []
    var rangeEnd = scanStart
    var foundAny = false

    var lineStart = scanStart
    while lineStart < text.endIndex {
        let lineEnd = lineEndIndex(in: text, at: lineStart)
        let line = String(text[lineStart..<lineEnd])

        // Check if this line is an ordered list item at the same indentation
        guard let marker = parseListMarker(in: line),
              marker.isOrdered,
              marker.indentation == indentation else {
            break
        }

        // Renumber this line
        let newMarker = "\(currentNumber)\(orderedSuffix)"
        let contentAfterPrefix = String(line[line.index(line.startIndex, offsetBy: marker.fullPrefix.count)...])
        let renumbered = "\(indentation)\(newMarker) \(contentAfterPrefix)"
        renumberedLines.append(renumbered)
        currentNumber += 1
        rangeEnd = lineEnd
        foundAny = true

        // Move to next line
        if lineEnd < text.endIndex {
            lineStart = text.index(after: lineEnd)
        } else {
            break
        }
    }

    guard foundAny else { return nil }
    let range = scanStart..<rangeEnd
    let replacement = renumberedLines.joined(separator: "\n")
    return (range, replacement)
}

// MARK: - Mutation Helper

/// Creates a TextMutation with a correctly computed cursor position.
///
/// The cursor position is computed by building the result text and indexing
/// at the specified offset within the replacement.
func makeMutation(
    text: String,
    range: Range<String.Index>,
    replacement: String,
    cursorOffsetInResult: Int,
    hapticStyle: HapticStyle? = nil
) -> TextMutation {
    let resultText = String(text[..<range.lowerBound]) + replacement + String(text[range.upperBound...])
    let clampedOffset = min(cursorOffsetInResult, resultText.count)
    let cursorIndex = resultText.index(resultText.startIndex, offsetBy: clampedOffset)
    return TextMutation(
        range: range,
        replacement: replacement,
        cursorAfter: cursorIndex,
        hapticStyle: hapticStyle
    )
}
