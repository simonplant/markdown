/// Save-time formatting utilities per FEAT-053.
///
/// These functions are applied at save time (not on keystrokes) to normalize
/// file content before writing to disk.

/// Ensures text ends with exactly one newline character per FEAT-053 AC-5.
///
/// - Removes excess trailing newlines
/// - Adds a newline if missing
/// - Returns `"\n"` for empty input
///
/// Called from the file save pipeline when the trailing newline setting is enabled.
public func ensureTrailingNewline(_ text: String) -> String {
    if text.isEmpty { return "\n" }

    // Find the last non-newline character
    var end = text.endIndex
    while end > text.startIndex {
        let prev = text.index(before: end)
        if text[prev] != "\n" {
            break
        }
        end = prev
    }

    // If all newlines (no content), return single newline
    if end == text.startIndex {
        return "\n"
    }

    return String(text[..<end]) + "\n"
}
