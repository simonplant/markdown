import Testing
import Foundation
@testable import EMFormatter
@testable import EMCore

@Suite("WhitespaceCleanupRule")
struct WhitespaceCleanupRuleTests {

    private let rule = WhitespaceCleanupRule()

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

    // MARK: - AC-2: Trailing # markers on headings are auto-removed

    @Test("Removes trailing # from heading on Enter")
    func removesTrailingHash() {
        let text = "## Heading ##"
        let ctx = context(text: text, cursorOffset: 13, trigger: .enter)
        let mutation = rule.evaluate(ctx)

        #expect(mutation != nil)
        let (result, _) = apply(mutation!, to: text)
        #expect(result == "## Heading\n")
    }

    @Test("Removes trailing ### from heading on Enter")
    func removesMultipleTrailingHashes() {
        let text = "## Heading ###"
        let ctx = context(text: text, cursorOffset: 14, trigger: .enter)
        let mutation = rule.evaluate(ctx)

        #expect(mutation != nil)
        let (result, _) = apply(mutation!, to: text)
        #expect(result == "## Heading\n")
    }

    @Test("Removes trailing # and whitespace from heading")
    func removesTrailingHashAndWhitespace() {
        let text = "## Heading ##  "
        let ctx = context(text: text, cursorOffset: 15, trigger: .enter)
        let mutation = rule.evaluate(ctx)

        #expect(mutation != nil)
        let (result, _) = apply(mutation!, to: text)
        #expect(result == "## Heading\n")
    }

    @Test("Does not strip # that are part of heading content like C#")
    func preservesContentHashes() {
        // "# C#" — the # after C is NOT a closing sequence (no space before it)
        let text = "# C#"
        let ctx = context(text: text, cursorOffset: 4, trigger: .enter)
        let mutation = rule.evaluate(ctx)

        // No trailing # to remove (CommonMark requires space before closing #)
        // No whitespace to trim → nil
        #expect(mutation == nil)
    }

    @Test("Strips trailing # only when preceded by space (CommonMark)")
    func stripsWithSpaceBefore() {
        let text = "# C# #"
        let ctx = context(text: text, cursorOffset: 6, trigger: .enter)
        let mutation = rule.evaluate(ctx)

        #expect(mutation != nil)
        let (result, _) = apply(mutation!, to: text)
        // "# C# #" → trailing " #" is removed → "# C#"
        #expect(result == "# C#\n")
    }

    // MARK: - AC-3: Pressing Enter trims trailing whitespace

    @Test("Trims trailing spaces on Enter")
    func trimsTrailingSpaces() {
        let text = "Hello   "
        let ctx = context(text: text, cursorOffset: 8, trigger: .enter)
        let mutation = rule.evaluate(ctx)

        #expect(mutation != nil)
        let (result, _) = apply(mutation!, to: text)
        #expect(result == "Hello\n")
    }

    @Test("Trims trailing tabs on Enter")
    func trimsTrailingTabs() {
        let text = "Hello\t\t"
        let ctx = context(text: text, cursorOffset: 7, trigger: .enter)
        let mutation = rule.evaluate(ctx)

        #expect(mutation != nil)
        let (result, _) = apply(mutation!, to: text)
        #expect(result == "Hello\n")
    }

    @Test("Trims mixed trailing whitespace")
    func trimsMixedWhitespace() {
        let text = "Hello \t "
        let ctx = context(text: text, cursorOffset: 8, trigger: .enter)
        let mutation = rule.evaluate(ctx)

        #expect(mutation != nil)
        let (result, _) = apply(mutation!, to: text)
        #expect(result == "Hello\n")
    }

    @Test("No mutation when no trailing whitespace")
    func noMutationWithoutTrailingWhitespace() {
        let text = "Hello"
        let ctx = context(text: text, cursorOffset: 5, trigger: .enter)
        let mutation = rule.evaluate(ctx)

        #expect(mutation == nil)
    }

    @Test("Trims trailing whitespace in multi-line document")
    func trimsInMultiLineDoc() {
        let text = "Line 1\nLine 2   "
        let ctx = context(text: text, cursorOffset: 16, trigger: .enter)
        let mutation = rule.evaluate(ctx)

        #expect(mutation != nil)
        let (result, _) = apply(mutation!, to: text)
        #expect(result == "Line 1\nLine 2\n")
    }

    @Test("Cursor positioned on new line after trim")
    func cursorOnNewLine() {
        let text = "Hello   "
        let ctx = context(text: text, cursorOffset: 8, trigger: .enter)
        let mutation = rule.evaluate(ctx)

        #expect(mutation != nil)
        let (result, cursorOffset) = apply(mutation!, to: text)
        #expect(result == "Hello\n")
        #expect(cursorOffset == 6) // After "Hello\n" — on the new line
    }

    // MARK: - AC-4: Blank line between block elements

    @Test("Inserts blank line after heading when next line has content")
    func blankLineAfterHeading() {
        let text = "## Heading\nSome text"
        // Cursor at end of heading line (offset 10, which is the \n position)
        let ctx = context(text: text, cursorOffset: 10, trigger: .enter)
        let mutation = rule.evaluate(ctx)

        #expect(mutation != nil)
        let (result, _) = apply(mutation!, to: text)
        #expect(result == "## Heading\n\nSome text")
    }

    @Test("No extra blank line when next line is already blank")
    func noExtraBlankLineWhenAlreadyBlank() {
        let text = "## Heading\n\nSome text"
        let ctx = context(text: text, cursorOffset: 10, trigger: .enter)
        let mutation = rule.evaluate(ctx)

        // Next line is blank → no blank line needed, no whitespace to trim → nil
        #expect(mutation == nil)
    }

    @Test("Inserts blank line after horizontal rule")
    func blankLineAfterHorizontalRule() {
        let text = "---\nSome text"
        let ctx = context(text: text, cursorOffset: 3, trigger: .enter)
        let mutation = rule.evaluate(ctx)

        #expect(mutation != nil)
        let (result, _) = apply(mutation!, to: text)
        #expect(result == "---\n\nSome text")
    }

    @Test("Inserts blank line after *** horizontal rule")
    func blankLineAfterStarRule() {
        let text = "***\nSome text"
        let ctx = context(text: text, cursorOffset: 3, trigger: .enter)
        let mutation = rule.evaluate(ctx)

        #expect(mutation != nil)
        let (result, _) = apply(mutation!, to: text)
        #expect(result == "***\n\nSome text")
    }

    @Test("No blank line for regular paragraph")
    func noBlankLineForParagraph() {
        let text = "Some text\nMore text"
        let ctx = context(text: text, cursorOffset: 9, trigger: .enter)
        let mutation = rule.evaluate(ctx)

        // "Some text" is not a block element → no blank line, no whitespace → nil
        #expect(mutation == nil)
    }

    @Test("Cursor on blank line between heading and content")
    func cursorPositionWithBlankLine() {
        let text = "## Heading\nContent"
        let ctx = context(text: text, cursorOffset: 10, trigger: .enter)
        let mutation = rule.evaluate(ctx)

        #expect(mutation != nil)
        let (result, cursorOffset) = apply(mutation!, to: text)
        #expect(result == "## Heading\n\nContent")
        #expect(cursorOffset == 11) // On the blank line
    }

    // MARK: - Combined: trailing # + whitespace + blank line

    @Test("Heading with trailing # and whitespace followed by content")
    func combinedCleanup() {
        let text = "## Heading ##  \nContent"
        let ctx = context(text: text, cursorOffset: 15, trigger: .enter)
        let mutation = rule.evaluate(ctx)

        #expect(mutation != nil)
        let (result, _) = apply(mutation!, to: text)
        #expect(result == "## Heading\n\nContent")
    }

    // MARK: - Code block suppression

    @Test("Does not fire inside code block")
    func insideCodeBlock() {
        let text = "```\nsome code   "
        let ctx = context(text: text, cursorOffset: 15, trigger: .enter)
        let mutation = rule.evaluate(ctx)

        #expect(mutation == nil)
    }

    // MARK: - Trigger guard

    @Test("Does not fire on character input")
    func noFireOnCharInput() {
        let text = "Hello   "
        let ctx = context(text: text, cursorOffset: 8, trigger: .characterInput("x"))
        let mutation = rule.evaluate(ctx)

        #expect(mutation == nil)
    }

    @Test("Does not fire on tab")
    func noFireOnTab() {
        let text = "Hello   "
        let ctx = context(text: text, cursorOffset: 8, trigger: .tab)
        let mutation = rule.evaluate(ctx)

        #expect(mutation == nil)
    }

    // MARK: - Configuration

    @Test("Respects trimTrailingWhitespace=false")
    func trimDisabled() {
        let noTrimRule = WhitespaceCleanupRule(
            trimTrailingWhitespace: false,
            removeTrailingHashes: true,
            insertBlankLineBetweenBlocks: true
        )
        let text = "Hello   "
        let ctx = context(text: text, cursorOffset: 8, trigger: .enter)
        let mutation = noTrimRule.evaluate(ctx)

        // No heading, no block element → nothing to do
        #expect(mutation == nil)
    }

    @Test("Respects removeTrailingHashes=false")
    func trailingHashDisabled() {
        let noHashRule = WhitespaceCleanupRule(
            trimTrailingWhitespace: true,
            removeTrailingHashes: false,
            insertBlankLineBetweenBlocks: true
        )
        let text = "## Heading ##"
        let ctx = context(text: text, cursorOffset: 13, trigger: .enter)
        let mutation = noHashRule.evaluate(ctx)

        // insertBlankLineBetweenBlocks is true but there's no next line → no blank line needed
        // trimTrailingWhitespace: no trailing whitespace to trim
        // removeTrailingHashes: disabled
        // The heading is "## Heading ##" which is a block element, but no next line content
        #expect(mutation == nil)
    }

    @Test("Respects insertBlankLineBetweenBlocks=false")
    func blankLineDisabled() {
        let noBlankRule = WhitespaceCleanupRule(
            trimTrailingWhitespace: true,
            removeTrailingHashes: true,
            insertBlankLineBetweenBlocks: false
        )
        let text = "## Heading\nContent"
        let ctx = context(text: text, cursorOffset: 10, trigger: .enter)
        let mutation = noBlankRule.evaluate(ctx)

        // No trailing whitespace on "## Heading", no trailing # → nil
        #expect(mutation == nil)
    }
}
