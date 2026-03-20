import EMCore

/// Auto-adds a space after ATX heading markers (# through ######) when missing per FEAT-053.
///
/// Triggers on character input: when typing a non-# non-space character immediately after
/// a sequence of 1–6 `#` characters at the start of a line, inserts a space
/// between the markers and the typed character.
/// Does not fire inside fenced code blocks.
public struct HeadingSpacingRule: FormattingRule {

    public init() {}

    public func evaluate(_ context: FormattingContext) -> TextMutation? {
        // Only trigger on single-character input (not paste, not # or space)
        guard case .characterInput(let input) = context.trigger,
              input.count == 1,
              input != "#",
              input != " " else { return nil }

        // Don't fire inside code blocks
        guard !isInsideCodeBlock(text: context.text, at: context.cursorPosition) else { return nil }

        let text = context.text
        let cursor = context.cursorPosition
        let lineStart = lineStartIndex(in: text, at: cursor)
        let beforeCursor = text[lineStart..<cursor]

        // Must be 1–6 # chars only from line start to cursor
        guard !beforeCursor.isEmpty,
              beforeCursor.count <= 6,
              beforeCursor.allSatisfy({ $0 == "#" }) else { return nil }

        // If there are more # chars after cursor on the same line, user is still typing markers
        if cursor < text.endIndex && text[cursor] == "#" {
            return nil
        }

        // If there's already a space right after cursor, heading is already spaced
        if cursor < text.endIndex && text[cursor] == " " {
            return nil
        }

        // Insert space + the typed character
        let replacement = " " + input
        let prefixLength = text.distance(from: text.startIndex, to: cursor)
        return makeMutation(
            text: text,
            range: cursor..<cursor,
            replacement: replacement,
            cursorOffsetInResult: prefixLength + replacement.count,
            hapticStyle: .listContinuation
        )
    }
}
