import Testing
import Foundation
@testable import EMFormatter

@Suite("SaveFormatting")
struct SaveFormattingTests {

    // MARK: - AC-5: File always ends with exactly one newline on save

    @Test("Adds newline to text without trailing newline")
    func addsNewline() {
        let result = ensureTrailingNewline("Hello")
        #expect(result == "Hello\n")
    }

    @Test("Preserves single trailing newline")
    func preservesSingleNewline() {
        let result = ensureTrailingNewline("Hello\n")
        #expect(result == "Hello\n")
    }

    @Test("Reduces multiple trailing newlines to one")
    func reducesMultipleNewlines() {
        let result = ensureTrailingNewline("Hello\n\n\n")
        #expect(result == "Hello\n")
    }

    @Test("Returns single newline for empty string")
    func emptyString() {
        let result = ensureTrailingNewline("")
        #expect(result == "\n")
    }

    @Test("Returns single newline for all-newline string")
    func allNewlines() {
        let result = ensureTrailingNewline("\n\n\n")
        #expect(result == "\n")
    }

    @Test("Preserves internal newlines")
    func preservesInternalNewlines() {
        let result = ensureTrailingNewline("Line 1\nLine 2\n\nLine 4")
        #expect(result == "Line 1\nLine 2\n\nLine 4\n")
    }

    @Test("Handles single character without newline")
    func singleChar() {
        let result = ensureTrailingNewline("x")
        #expect(result == "x\n")
    }

    @Test("Handles single newline")
    func singleNewline() {
        let result = ensureTrailingNewline("\n")
        #expect(result == "\n")
    }

    @Test("Handles multi-line document with trailing newlines")
    func multiLineWithTrailing() {
        let result = ensureTrailingNewline("# Title\n\nContent\n\n\n")
        #expect(result == "# Title\n\nContent\n")
    }
}
