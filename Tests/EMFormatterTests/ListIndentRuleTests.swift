import Testing
import Foundation
@testable import EMFormatter
@testable import EMCore

@Suite("ListIndentRule")
struct ListIndentRuleTests {

    private let rule = ListIndentRule()

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
        return FormattingContext(text: text, cursorPosition: cursor, trigger: trigger)
    }

    // MARK: - Tab (Indent)

    @Test("Tab indents unordered list item by 2 spaces")
    func indentUnordered() {
        let text = "- Item"
        let ctx = context(text: text, cursorOffset: text.count, trigger: .tab)
        let mutation = rule.evaluate(ctx)

        #expect(mutation != nil)
        let (result, _) = apply(mutation!, to: text)
        #expect(result == "  - Item")
    }

    @Test("Tab indents already-indented item further")
    func indentNested() {
        let text = "  - Nested"
        let ctx = context(text: text, cursorOffset: text.count, trigger: .tab)
        let mutation = rule.evaluate(ctx)

        #expect(mutation != nil)
        let (result, _) = apply(mutation!, to: text)
        #expect(result == "    - Nested")
    }

    @Test("Tab indents ordered list item")
    func indentOrdered() {
        let text = "1. First"
        let ctx = context(text: text, cursorOffset: text.count, trigger: .tab)
        let mutation = rule.evaluate(ctx)

        #expect(mutation != nil)
        let (result, _) = apply(mutation!, to: text)
        #expect(result == "  1. First")
    }

    @Test("Tab moves cursor right by indent size")
    func indentCursorPosition() {
        let text = "- Item"
        let cursorPos = 4 // somewhere in "Item"
        let ctx = context(text: text, cursorOffset: cursorPos, trigger: .tab)
        let mutation = rule.evaluate(ctx)

        #expect(mutation != nil)
        let (_, cursorOffset) = apply(mutation!, to: text)
        #expect(cursorOffset == cursorPos + ListIndentRule.defaultIndentSize)
    }

    // MARK: - Shift-Tab (Outdent)

    @Test("Shift-Tab outdents indented list item")
    func outdentItem() {
        let text = "  - Item"
        let ctx = context(text: text, cursorOffset: text.count, trigger: .shiftTab)
        let mutation = rule.evaluate(ctx)

        #expect(mutation != nil)
        let (result, _) = apply(mutation!, to: text)
        #expect(result == "- Item")
    }

    @Test("Shift-Tab outdents deeply nested item by one level")
    func outdentDeeply() {
        let text = "    - Deep"
        let ctx = context(text: text, cursorOffset: text.count, trigger: .shiftTab)
        let mutation = rule.evaluate(ctx)

        #expect(mutation != nil)
        let (result, _) = apply(mutation!, to: text)
        #expect(result == "  - Deep")
    }

    @Test("Shift-Tab on non-indented item returns nil")
    func outdentNoIndent() {
        let text = "- Item"
        let ctx = context(text: text, cursorOffset: text.count, trigger: .shiftTab)
        let mutation = rule.evaluate(ctx)

        #expect(mutation == nil)
    }

    @Test("Shift-Tab moves cursor left by indent size")
    func outdentCursorPosition() {
        let text = "  - Item"
        let cursorPos = 6 // somewhere in "Item"
        let ctx = context(text: text, cursorOffset: cursorPos, trigger: .shiftTab)
        let mutation = rule.evaluate(ctx)

        #expect(mutation != nil)
        let (_, cursorOffset) = apply(mutation!, to: text)
        #expect(cursorOffset == cursorPos - ListIndentRule.defaultIndentSize)
    }

    @Test("Shift-Tab cursor doesn't go before line start")
    func outdentCursorClamp() {
        let text = "  - Item"
        let cursorPos = 1 // in the indentation area
        let ctx = context(text: text, cursorOffset: cursorPos, trigger: .shiftTab)
        let mutation = rule.evaluate(ctx)

        #expect(mutation != nil)
        let (_, cursorOffset) = apply(mutation!, to: text)
        // Cursor should not go before line start (0)
        #expect(cursorOffset >= 0)
    }

    // MARK: - Multiline Document

    @Test("Tab indents only the current list item line")
    func indentOnlyCurrentLine() {
        let text = "- First\n- Second\n- Third"
        // Cursor on "Second" line
        let ctx = context(text: text, cursorOffset: 12, trigger: .tab)
        let mutation = rule.evaluate(ctx)

        #expect(mutation != nil)
        let (result, _) = apply(mutation!, to: text)
        #expect(result == "- First\n  - Second\n- Third")
    }

    // MARK: - Code Block Suppression

    @Test("Tab does not fire inside code block")
    func codeBlockSuppression() {
        let text = "```\n- not a list\n```"
        let ctx = context(text: text, cursorOffset: 10, trigger: .tab)
        let mutation = rule.evaluate(ctx)

        #expect(mutation == nil)
    }

    // MARK: - Non-list Text

    @Test("Tab on non-list text returns nil")
    func nonListText() {
        let text = "Just a paragraph"
        let ctx = context(text: text, cursorOffset: 5, trigger: .tab)
        let mutation = rule.evaluate(ctx)

        #expect(mutation == nil)
    }

    @Test("Enter trigger returns nil from indent rule")
    func enterTrigger() {
        let text = "- Item"
        let ctx = context(text: text, cursorOffset: text.count, trigger: .enter)
        let mutation = rule.evaluate(ctx)

        #expect(mutation == nil)
    }

    // MARK: - Haptic Feedback

    @Test("Haptic style is listContinuation on indent")
    func hapticOnIndent() {
        let text = "- Item"
        let ctx = context(text: text, cursorOffset: text.count, trigger: .tab)
        let mutation = rule.evaluate(ctx)

        #expect(mutation?.hapticStyle == .listContinuation)
    }
}
