import Testing
import Foundation
@testable import EMFormatter
@testable import EMCore

@Suite("TableAlignmentRule")
struct TableAlignmentRuleTests {

    private let rule = TableAlignmentRule()

    private func apply(_ mutation: TextMutation, to text: String) -> (result: String, cursorOffset: Int) {
        let prefix = String(text[..<mutation.range.lowerBound])
        let suffix = String(text[mutation.range.upperBound...])
        let result = prefix + mutation.replacement + suffix
        let cursorOffset = result.distance(from: result.startIndex, to: mutation.cursorAfter)
        return (result, cursorOffset)
    }

    private func context(
        text: String,
        cursorOffset: Int,
        trigger: FormattingTrigger,
        replacementRange: NSRange? = nil
    ) -> FormattingContext {
        let cursor = text.index(text.startIndex, offsetBy: cursorOffset)
        let swiftRange: Range<String.Index>
        if let nsRange = replacementRange, let r = Range(nsRange, in: text) {
            swiftRange = r
        } else {
            swiftRange = cursor..<cursor
        }
        return FormattingContext(
            text: text,
            cursorPosition: swiftRange.lowerBound,
            trigger: trigger,
            replacementRange: swiftRange
        )
    }

    // MARK: - AC-1: Auto-align on character input

    @Test("Typing a character in a table cell re-aligns columns")
    func characterInputAligns() {
        let text = "| A | B |\n|---|---|\n| C | D |"
        // Cursor after "C" in last row (offset = "| A | B |\n|---|---|\n| C".count = 22)
        // Actually let's compute: "| A | B |\n" = 10, "|---|---|\n" = 10, "| C" = 3 → offset 23
        let lastRowStart = "| A | B |\n|---|---|\n".count
        let ctx = context(
            text: text,
            cursorOffset: lastRowStart + 3,  // after "| C"
            trigger: .characterInput("x")
        )
        let mutation = rule.evaluate(ctx)

        #expect(mutation != nil)
        let (result, _) = apply(mutation!, to: text)
        // The table should be aligned with "Cx" in the cell
        #expect(result.contains("Cx"))
        // All lines should have proper table formatting
        let lines = result.split(separator: "\n").map(String.init)
        for line in lines {
            #expect(line.hasPrefix("| "))
            #expect(line.hasSuffix(" |"))
        }
    }

    @Test("Typing aligns misaligned table with varying cell widths")
    func alignsMisalignedTable() {
        let text = "| Name | Age |\n|---|---|\n| Alice | 30 |"
        let lastRowStart = "| Name | Age |\n|---|---|\n".count
        // Cursor after "Alice" → type a character
        let ctx = context(
            text: text,
            cursorOffset: lastRowStart + 7, // after "| Alice"
            trigger: .characterInput("!")
        )
        let mutation = rule.evaluate(ctx)

        #expect(mutation != nil)
        let (result, _) = apply(mutation!, to: text)
        #expect(result.contains("Alice!"))
        // Columns should be aligned — all pipe positions should match across rows
        let lines = result.split(separator: "\n").map(String.init)
        let dataPipePositions = lines.filter { !$0.contains("---") }.map { line in
            line.enumerated().filter { $0.element == "|" }.map(\.offset)
        }
        if dataPipePositions.count > 1 {
            for i in 1..<dataPipePositions.count {
                #expect(dataPipePositions[i] == dataPipePositions[0])
            }
        }
    }

    @Test("Cursor is positioned after typed character in aligned table")
    func cursorAfterTypedCharacter() {
        let text = "| A | B |\n|---|---|\n| C | D |"
        let lastRowStart = "| A | B |\n|---|---|\n".count
        // Type "x" after "C"
        let ctx = context(
            text: text,
            cursorOffset: lastRowStart + 3, // after "| C"
            trigger: .characterInput("x")
        )
        let mutation = rule.evaluate(ctx)

        #expect(mutation != nil)
        let (result, cursorOffset) = apply(mutation!, to: text)
        // Cursor should be right after "x" in "Cx"
        let cursorChar = result.index(result.startIndex, offsetBy: cursorOffset)
        // The character before cursor should be "x"
        let charBefore = result[result.index(before: cursorChar)]
        #expect(charBefore == "x")
    }

    // MARK: - Deletion (backspace)

    @Test("Backspace in table cell re-aligns columns")
    func backspaceAligns() {
        let text = "| Alice | Bob |\n|-------|-----|\n| Carol | Dan |"
        let lastRowStart = "| Alice | Bob |\n|-------|-----|\n".count
        // Delete "l" from "Carol" — range is (lastRowStart + 5, 1) to delete the "o"
        let deleteOffset = lastRowStart + 5 // position of "o" in "Carol"
        let ctx = context(
            text: text,
            cursorOffset: deleteOffset,
            trigger: .delete,
            replacementRange: NSRange(location: deleteOffset, length: 1)
        )
        let mutation = rule.evaluate(ctx)

        #expect(mutation != nil)
        let (result, _) = apply(mutation!, to: text)
        #expect(result.contains("Carl"))
        // Table should still be aligned
        let lines = result.split(separator: "\n").map(String.init)
        for line in lines {
            #expect(line.hasPrefix("| "))
            #expect(line.hasSuffix(" |"))
        }
    }

    // MARK: - Non-firing cases

    @Test("Does not fire on non-table text")
    func nonTableText() {
        let text = "Just a paragraph"
        let ctx = context(text: text, cursorOffset: 5, trigger: .characterInput("x"))
        let mutation = rule.evaluate(ctx)
        #expect(mutation == nil)
    }

    @Test("Does not fire on Enter trigger")
    func enterTrigger() {
        let text = "| A | B |\n|---|---|\n| C | D |"
        let ctx = context(text: text, cursorOffset: 3, trigger: .enter)
        let mutation = rule.evaluate(ctx)
        #expect(mutation == nil)
    }

    @Test("Does not fire on Tab trigger")
    func tabTrigger() {
        let text = "| A | B |\n|---|---|\n| C | D |"
        let ctx = context(text: text, cursorOffset: 3, trigger: .tab)
        let mutation = rule.evaluate(ctx)
        #expect(mutation == nil)
    }

    @Test("Does not fire inside fenced code block")
    func codeBlockSuppression() {
        let text = "```\n| A | B |\n```"
        let ctx = context(text: text, cursorOffset: 6, trigger: .characterInput("x"))
        let mutation = rule.evaluate(ctx)
        #expect(mutation == nil)
    }

    @Test("Does not fire on separator row")
    func separatorRow() {
        let text = "| A | B |\n|---|---|\n| C | D |"
        let sepStart = "| A | B |\n".count
        let ctx = context(
            text: text,
            cursorOffset: sepStart + 2,
            trigger: .characterInput("x")
        )
        let mutation = rule.evaluate(ctx)
        #expect(mutation == nil)
    }

    @Test("Does not fire for multi-line paste")
    func multiLinePaste() {
        let text = "| A | B |\n|---|---|\n| C | D |"
        let ctx = context(
            text: text,
            cursorOffset: 3,
            trigger: .characterInput("line1\nline2")
        )
        let mutation = rule.evaluate(ctx)
        #expect(mutation == nil)
    }

    // MARK: - Undo (AC-5)

    @Test("Each alignment produces a single mutation for undo")
    func singleMutationForUndo() {
        let text = "| A | B |\n|---|---|\n| C | D |"
        let lastRowStart = "| A | B |\n|---|---|\n".count
        let ctx = context(
            text: text,
            cursorOffset: lastRowStart + 3,
            trigger: .characterInput("x")
        )
        let mutation = rule.evaluate(ctx)

        // A single TextMutation is returned — applied as one undo group
        #expect(mutation != nil)
    }

    @Test("No haptic for regular character input alignment")
    func noHaptic() {
        let text = "| A | B |\n|---|---|\n| C | D |"
        let lastRowStart = "| A | B |\n|---|---|\n".count
        let ctx = context(
            text: text,
            cursorOffset: lastRowStart + 3,
            trigger: .characterInput("x")
        )
        let mutation = rule.evaluate(ctx)
        #expect(mutation?.hapticStyle == nil)
    }

    // MARK: - AC-6: Performance with 20 columns

    @Test("20 columns aligns without crash")
    func twentyColumnsAlignment() {
        let cells = (1...20).map { "C\($0)" }
        let row = "| " + cells.joined(separator: " | ") + " |"
        let sep = "| " + cells.map { _ in "---" }.joined(separator: " | ") + " |"
        let text = row + "\n" + sep + "\n" + row
        let lastRowStart = (row + "\n" + sep + "\n").count
        let ctx = context(
            text: text,
            cursorOffset: lastRowStart + 3,
            trigger: .characterInput("X")
        )
        let mutation = rule.evaluate(ctx)

        #expect(mutation != nil)
        let (result, _) = apply(mutation!, to: text)
        let resultLines = result.split(separator: "\n")
        #expect(resultLines.count == 3)
    }

    // MARK: - Table without separator

    @Test("Aligns table without separator row")
    func noSeparatorRow() {
        let text = "| Foo | Bar |"
        let ctx = context(
            text: text,
            cursorOffset: 5, // after "| Foo"... actually "| Fo" is offset 4, so 5 is after "Foo"
            trigger: .characterInput("d")
        )
        let mutation = rule.evaluate(ctx)

        #expect(mutation != nil)
        let (result, _) = apply(mutation!, to: text)
        #expect(result.contains("Food"))
    }

    // MARK: - Engine integration

    @Test("Default engine handles characterInput in table")
    func engineIntegration() {
        let engine = FormattingEngine.defaultFormattingEngine()
        let text = "| A | B |\n|---|---|\n| C | D |"
        let lastRowStart = "| A | B |\n|---|---|\n".count
        let cursor = text.index(text.startIndex, offsetBy: lastRowStart + 3)
        let ctx = FormattingContext(
            text: text,
            cursorPosition: cursor,
            trigger: .characterInput("x")
        )
        let mutation = engine.evaluate(ctx)

        #expect(mutation != nil)
    }

    @Test("Default engine returns nil for characterInput outside table")
    func engineNonTable() {
        let engine = FormattingEngine.defaultFormattingEngine()
        let text = "Just a paragraph"
        let cursor = text.index(text.startIndex, offsetBy: 5)
        let ctx = FormattingContext(
            text: text,
            cursorPosition: cursor,
            trigger: .characterInput("x")
        )
        let mutation = engine.evaluate(ctx)

        #expect(mutation == nil)
    }
}
