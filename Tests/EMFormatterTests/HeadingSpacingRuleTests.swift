import Testing
import Foundation
@testable import EMFormatter
@testable import EMCore

@Suite("HeadingSpacingRule")
struct HeadingSpacingRuleTests {

    private let rule = HeadingSpacingRule()

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
        trigger: FormattingTrigger
    ) -> FormattingContext {
        let cursor = text.index(text.startIndex, offsetBy: cursorOffset)
        return FormattingContext(
            text: text,
            cursorPosition: cursor,
            trigger: trigger
        )
    }

    // MARK: - AC-1: Typing ##Heading auto-corrects to ## Heading

    @Test("Typing after ## inserts space before character")
    func hashHashThenChar() {
        let text = "##"
        let ctx = context(text: text, cursorOffset: 2, trigger: .characterInput("H"))
        let mutation = rule.evaluate(ctx)

        #expect(mutation != nil)
        let (result, cursorOffset) = apply(mutation!, to: text)
        #expect(result == "## H")
        #expect(cursorOffset == 4)
    }

    @Test("Typing after # inserts space before character")
    func singleHashThenChar() {
        let text = "#"
        let ctx = context(text: text, cursorOffset: 1, trigger: .characterInput("T"))
        let mutation = rule.evaluate(ctx)

        #expect(mutation != nil)
        let (result, _) = apply(mutation!, to: text)
        #expect(result == "# T")
    }

    @Test("Typing after ### inserts space before character")
    func tripleHashThenChar() {
        let text = "###"
        let ctx = context(text: text, cursorOffset: 3, trigger: .characterInput("S"))
        let mutation = rule.evaluate(ctx)

        #expect(mutation != nil)
        let (result, _) = apply(mutation!, to: text)
        #expect(result == "### S")
    }

    @Test("Typing after ###### (h6) inserts space")
    func h6ThenChar() {
        let text = "######"
        let ctx = context(text: text, cursorOffset: 6, trigger: .characterInput("X"))
        let mutation = rule.evaluate(ctx)

        #expect(mutation != nil)
        let (result, _) = apply(mutation!, to: text)
        #expect(result == "###### X")
    }

    @Test("Does not fire for 7+ hashes (not a valid heading)")
    func sevenHashes() {
        let text = "#######"
        let ctx = context(text: text, cursorOffset: 7, trigger: .characterInput("X"))
        let mutation = rule.evaluate(ctx)

        #expect(mutation == nil)
    }

    // MARK: - Should not fire cases

    @Test("Does not fire when typing # (extending markers)")
    func typingHash() {
        let text = "##"
        let ctx = context(text: text, cursorOffset: 2, trigger: .characterInput("#"))
        let mutation = rule.evaluate(ctx)

        #expect(mutation == nil)
    }

    @Test("Does not fire when typing space (user adding space manually)")
    func typingSpace() {
        let text = "##"
        let ctx = context(text: text, cursorOffset: 2, trigger: .characterInput(" "))
        let mutation = rule.evaluate(ctx)

        #expect(mutation == nil)
    }

    @Test("Does not fire when space already exists after markers")
    func spaceAlreadyExists() {
        let text = "## "
        let ctx = context(text: text, cursorOffset: 2, trigger: .characterInput("H"))
        let mutation = rule.evaluate(ctx)

        #expect(mutation == nil)
    }

    @Test("Does not fire on multi-character paste")
    func multiCharPaste() {
        let text = "##"
        let ctx = context(text: text, cursorOffset: 2, trigger: .characterInput("Hello"))
        let mutation = rule.evaluate(ctx)

        #expect(mutation == nil)
    }

    @Test("Does not fire on Enter trigger")
    func enterTrigger() {
        let text = "##"
        let ctx = context(text: text, cursorOffset: 2, trigger: .enter)
        let mutation = rule.evaluate(ctx)

        #expect(mutation == nil)
    }

    @Test("Does not fire inside code block")
    func insideCodeBlock() {
        let text = "```\n##"
        let ctx = context(text: text, cursorOffset: 6, trigger: .characterInput("H"))
        let mutation = rule.evaluate(ctx)

        #expect(mutation == nil)
    }

    @Test("Does not fire when cursor is between hash characters")
    func cursorBetweenHashes() {
        // Text is "###", cursor at offset 1 (between first and second #)
        // After cursor is "#" so rule should not fire
        let text = "###"
        let ctx = context(text: text, cursorOffset: 1, trigger: .characterInput("H"))
        let mutation = rule.evaluate(ctx)

        #expect(mutation == nil)
    }

    @Test("Does not fire when line has non-hash content before cursor")
    func nonHashContentBeforeCursor() {
        let text = "## Heading"
        // Cursor at offset 10 (end of text), beforeCursor is "## Heading" — not all hashes
        let ctx = context(text: text, cursorOffset: 10, trigger: .characterInput("!"))
        let mutation = rule.evaluate(ctx)

        #expect(mutation == nil)
    }

    // MARK: - Multi-line context

    @Test("Works on second line of document")
    func secondLine() {
        let text = "First line\n##"
        let ctx = context(text: text, cursorOffset: 13, trigger: .characterInput("S"))
        let mutation = rule.evaluate(ctx)

        #expect(mutation != nil)
        let (result, _) = apply(mutation!, to: text)
        #expect(result == "First line\n## S")
    }

    @Test("Does not affect other lines")
    func otherLinesUnchanged() {
        let text = "# Title\n##"
        let ctx = context(text: text, cursorOffset: 10, trigger: .characterInput("S"))
        let mutation = rule.evaluate(ctx)

        #expect(mutation != nil)
        let (result, _) = apply(mutation!, to: text)
        #expect(result == "# Title\n## S")
    }
}
