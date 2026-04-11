import EMCore

/// Cleans up whitespace and heading markers when pressing Enter per FEAT-053.
///
/// - Trims trailing whitespace from the completed line (AC-3)
/// - Removes trailing ATX heading markers, e.g. `## Heading ##` → `## Heading` (AC-2)
/// - Inserts a blank line after block elements like headings and horizontal rules (AC-4)
///
/// Each behavior is independently configurable. This rule is placed after table and list
/// rules in engine order so it only applies to non-list, non-table lines.
/// Does not fire inside fenced code blocks.
public struct WhitespaceCleanupRule: FormattingRule {

    /// Whether to trim trailing whitespace from the completed line.
    public let trimTrailingWhitespace: Bool

    /// Whether to remove trailing # markers from heading lines.
    public let removeTrailingHashes: Bool

    /// Whether to insert a blank line after block elements.
    public let insertBlankLineBetweenBlocks: Bool

    public init(
        trimTrailingWhitespace: Bool = true,
        removeTrailingHashes: Bool = true,
        insertBlankLineBetweenBlocks: Bool = true
    ) {
        self.trimTrailingWhitespace = trimTrailingWhitespace
        self.removeTrailingHashes = removeTrailingHashes
        self.insertBlankLineBetweenBlocks = insertBlankLineBetweenBlocks
    }

    public func evaluate(_ context: FormattingContext) -> TextMutation? {
        guard context.trigger == .enter else { return nil }
        guard !isInsideCodeBlock(text: context.text, at: context.cursorPosition) else { return nil }

        let text = context.text
        let cursor = context.cursorPosition
        let lineStart = lineStartIndex(in: text, at: cursor)
        let lineEnd = lineEndIndex(in: text, at: cursor)

        // Content before cursor on this line
        let beforeCursor = String(text[lineStart..<cursor])
        var cleaned = beforeCursor

        // 1. Remove trailing # from headings
        if removeTrailingHashes {
            cleaned = stripTrailingHashes(from: cleaned)
        }

        // 2. Trim trailing whitespace
        if trimTrailingWhitespace {
            while cleaned.hasSuffix(" ") || cleaned.hasSuffix("\t") {
                cleaned = String(cleaned.dropLast())
            }
        }

        // 3. Determine if blank line separation is needed
        let afterCursorOnLine = text[cursor..<lineEnd]
        let isAtEndOfLine = afterCursorOnLine.allSatisfy { $0 == " " || $0 == "\t" }
        var needsBlankLine = false

        if insertBlankLineBetweenBlocks && isAtEndOfLine && isBlockElement(cleaned) {
            // Check if next line exists and has non-blank content
            if lineEnd < text.endIndex {
                let nextLineStart = text.index(after: lineEnd)
                if nextLineStart < text.endIndex {
                    let nextLineEnd = lineEndIndex(in: text, at: nextLineStart)
                    let nextLine = text[nextLineStart..<nextLineEnd]
                    if !nextLine.allSatisfy({ $0 == " " || $0 == "\t" }) {
                        needsBlankLine = true
                    }
                }
            }
        }

        let contentChanged = cleaned != beforeCursor
        guard contentChanged || needsBlankLine else { return nil }

        // Compute the range to replace:
        // From end of cleaned content to cursor (the trimmed suffix),
        // plus any trailing whitespace after cursor on the same line,
        // plus the existing newline if we need a blank line (to avoid triple \n).
        let trimmedCount = beforeCursor.count - cleaned.count
        let trimStart = text.index(cursor, offsetBy: -trimmedCount)
        var rangeEnd = cursor

        // Include trailing whitespace after cursor (if cursor is at end of meaningful content)
        if isAtEndOfLine && !afterCursorOnLine.isEmpty {
            rangeEnd = lineEnd
        }

        // Include existing newline when inserting blank line to avoid triple newline
        if needsBlankLine && rangeEnd < text.endIndex && text[rangeEnd] == "\n" {
            rangeEnd = text.index(after: rangeEnd)
        }

        let newline = needsBlankLine ? "\n\n" : "\n"
        let cursorOffset = text.distance(from: text.startIndex, to: trimStart) + 1

        return makeMutation(
            text: text,
            range: trimStart..<rangeEnd,
            replacement: newline,
            cursorOffsetInResult: cursorOffset,
            hapticStyle: .listContinuation
        )
    }

    // MARK: - Heading Detection

    /// Strips trailing ATX heading markers from a line per CommonMark.
    /// E.g., `## Heading ##` → `## Heading`, `## Heading ###  ` → `## Heading`.
    /// Only strips trailing `#` preceded by a space (protects content like `C#`).
    private func stripTrailingHashes(from line: String) -> String {
        guard isHeading(line) else { return line }

        // Parse heading structure: leading whitespace + #{1,6} + " " + content
        let indent = line.prefix(while: { $0 == " " || $0 == "\t" })
        let afterIndent = line.dropFirst(indent.count)
        let hashes = afterIndent.prefix(while: { $0 == "#" })
        guard hashes.count >= 1, hashes.count <= 6 else { return line }

        let prefixLength = indent.count + hashes.count
        guard prefixLength < line.count else { return line }

        let afterHashes = line.dropFirst(prefixLength)
        guard afterHashes.first == " " else { return line }

        let contentStartIdx = line.index(line.startIndex, offsetBy: prefixLength + 1)
        let prefix = String(line[..<contentStartIdx])
        var content = String(line[contentStartIdx...])

        // Strip trailing whitespace from content
        while content.hasSuffix(" ") || content.hasSuffix("\t") {
            content = String(content.dropLast())
        }

        // Find trailing # sequence
        var trailingHashStart = content.endIndex
        while trailingHashStart > content.startIndex {
            let prev = content.index(before: trailingHashStart)
            if content[prev] == "#" {
                trailingHashStart = prev
            } else {
                break
            }
        }

        if trailingHashStart < content.endIndex {
            if trailingHashStart == content.startIndex {
                // Content is entirely # characters (e.g., "## ##" → content was "##")
                content = ""
            } else if content[content.index(before: trailingHashStart)] == " " {
                // Space before trailing hashes → CommonMark closing sequence
                content = String(content[..<trailingHashStart])
                while content.hasSuffix(" ") || content.hasSuffix("\t") {
                    content = String(content.dropLast())
                }
            }
            // No space before trailing # → leave them (protects e.g. "C#")
        }

        if content.isEmpty {
            return String(indent) + String(hashes)
        }
        return prefix + content
    }

    // MARK: - Block Element Detection

    /// Checks if a line is a heading (starts with #{1,6} followed by space or is just hashes).
    func isHeading(_ line: String) -> Bool {
        let trimmed = line.drop(while: { $0 == " " || $0 == "\t" })
        var hashCount = 0
        for char in trimmed {
            if char == "#" {
                hashCount += 1
            } else {
                break
            }
        }
        guard hashCount >= 1 && hashCount <= 6 else { return false }
        // Valid heading: just hashes, or hashes followed by space
        return trimmed.count == hashCount || trimmed.dropFirst(hashCount).first == " "
    }

    /// Checks if a line is a horizontal rule (---, ***, ___) per CommonMark.
    func isHorizontalRule(_ line: String) -> Bool {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        let stripped = trimmed.filter { $0 != " " }
        guard stripped.count >= 3 else { return false }
        let chars = Set(stripped)
        return chars.count == 1 && (chars.first == "-" || chars.first == "*" || chars.first == "_")
    }

    /// Checks if a line represents a block element that should have blank line separation.
    func isBlockElement(_ line: String) -> Bool {
        isHeading(line) || isHorizontalRule(line)
    }
}
