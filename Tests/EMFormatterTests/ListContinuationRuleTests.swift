import Testing
import Foundation
@testable import EMFormatter
@testable import EMCore

@Suite("ListContinuationRule")
struct ListContinuationRuleTests {

    private let rule = ListContinuationRule()

    /// Apply a mutation to text and return the result and cursor character offset.
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
        trigger: FormattingTrigger = .enter
    ) -> FormattingContext {
        let cursor = text.index(text.startIndex, offsetBy: cursorOffset)
        return FormattingContext(text: text, cursorPosition: cursor, trigger: trigger)
    }

    // MARK: - Unordered List Continuation

    @Test("Enter after unordered list item continues with dash")
    func continueDash() {
        let text = "- First item"
        let ctx = context(text: text, cursorOffset: text.count)
        let mutation = rule.evaluate(ctx)

        #expect(mutation != nil)
        let (result, cursorOffset) = apply(mutation!, to: text)
        #expect(result == "- First item\n- ")
        #expect(cursorOffset == result.count) // cursor at end
    }

    @Test("Enter after unordered list item continues with asterisk")
    func continueAsterisk() {
        let text = "* Item one"
        let ctx = context(text: text, cursorOffset: text.count)
        let mutation = rule.evaluate(ctx)

        #expect(mutation != nil)
        let (result, _) = apply(mutation!, to: text)
        #expect(result == "* Item one\n* ")
    }

    @Test("Enter after unordered list item continues with plus")
    func continuePlus() {
        let text = "+ Item one"
        let ctx = context(text: text, cursorOffset: text.count)
        let mutation = rule.evaluate(ctx)

        #expect(mutation != nil)
        let (result, _) = apply(mutation!, to: text)
        #expect(result == "+ Item one\n+ ")
    }

    @Test("Enter preserves indentation for nested list")
    func continueNested() {
        let text = "  - Nested item"
        let ctx = context(text: text, cursorOffset: text.count)
        let mutation = rule.evaluate(ctx)

        #expect(mutation != nil)
        let (result, _) = apply(mutation!, to: text)
        #expect(result == "  - Nested item\n  - ")
    }

    @Test("Enter in middle of list item splits content")
    func splitContent() {
        let text = "- Hello World"
        // Cursor after "Hello" (offset 7: "- Hello")
        let ctx = context(text: text, cursorOffset: 7)
        let mutation = rule.evaluate(ctx)

        #expect(mutation != nil)
        let (result, cursorOffset) = apply(mutation!, to: text)
        #expect(result == "- Hello\n-  World")
        // Cursor should be after "- " on the new line
        #expect(cursorOffset == "- Hello\n- ".count)
    }

    // MARK: - Ordered List Continuation

    @Test("Enter after ordered list item continues with next number")
    func continueOrdered() {
        let text = "1. First"
        let ctx = context(text: text, cursorOffset: text.count)
        let mutation = rule.evaluate(ctx)

        #expect(mutation != nil)
        let (result, _) = apply(mutation!, to: text)
        #expect(result == "1. First\n2. ")
    }

    @Test("Enter after second ordered item continues with 3")
    func continueOrderedSecond() {
        let text = "1. First\n2. Second"
        let ctx = context(text: text, cursorOffset: text.count)
        let mutation = rule.evaluate(ctx)

        #expect(mutation != nil)
        let (result, _) = apply(mutation!, to: text)
        #expect(result == "1. First\n2. Second\n3. ")
    }

    @Test("Ordered list with paren suffix continues correctly")
    func continueOrderedParen() {
        let text = "1) First"
        let ctx = context(text: text, cursorOffset: text.count)
        let mutation = rule.evaluate(ctx)

        #expect(mutation != nil)
        let (result, _) = apply(mutation!, to: text)
        #expect(result == "1) First\n2) ")
    }

    @Test("Ordered list renumbers subsequent siblings on continuation")
    func renumberOnContinuation() {
        let text = "1. First\n2. Second\n3. Third"
        // Cursor at end of "1. First" (offset 8)
        let ctx = context(text: text, cursorOffset: 8)
        let mutation = rule.evaluate(ctx)

        #expect(mutation != nil)
        let (result, _) = apply(mutation!, to: text)
        #expect(result == "1. First\n2. \n3. Second\n4. Third")
    }

    // MARK: - Task List Continuation

    @Test("Enter after task list item continues with unchecked checkbox")
    func continueTaskList() {
        let text = "- [ ] Task one"
        let ctx = context(text: text, cursorOffset: text.count)
        let mutation = rule.evaluate(ctx)

        #expect(mutation != nil)
        let (result, _) = apply(mutation!, to: text)
        #expect(result == "- [ ] Task one\n- [ ] ")
    }

    @Test("Enter after checked task list continues with unchecked")
    func continueCheckedTaskList() {
        let text = "- [x] Done task"
        let ctx = context(text: text, cursorOffset: text.count)
        let mutation = rule.evaluate(ctx)

        #expect(mutation != nil)
        let (result, _) = apply(mutation!, to: text)
        // New task item should be unchecked regardless of current state
        #expect(result == "- [x] Done task\n- [ ] ")
    }

    // MARK: - List Termination

    @Test("Enter on empty dash item terminates list")
    func terminateDash() {
        let text = "- First\n- "
        let ctx = context(text: text, cursorOffset: text.count)
        let mutation = rule.evaluate(ctx)

        #expect(mutation != nil)
        let (result, _) = apply(mutation!, to: text)
        #expect(result == "- First\n")
    }

    @Test("Enter on empty ordered item terminates list")
    func terminateOrdered() {
        let text = "1. First\n2. "
        let ctx = context(text: text, cursorOffset: text.count)
        let mutation = rule.evaluate(ctx)

        #expect(mutation != nil)
        let (result, _) = apply(mutation!, to: text)
        #expect(result == "1. First\n")
    }

    @Test("Enter on empty item with content after renumbers")
    func terminateWithRenumber() {
        let text = "1. First\n2. \n3. Third"
        // Cursor at end of "2. " (offset 12)
        let ctx = context(text: text, cursorOffset: 12)
        let mutation = rule.evaluate(ctx)

        #expect(mutation != nil)
        let (result, _) = apply(mutation!, to: text)
        #expect(result == "1. First\n2. Third")
    }

    @Test("Enter on empty nested item terminates at that level")
    func terminateNested() {
        let text = "- Parent\n  - "
        let ctx = context(text: text, cursorOffset: text.count)
        let mutation = rule.evaluate(ctx)

        #expect(mutation != nil)
        let (result, _) = apply(mutation!, to: text)
        #expect(result == "- Parent\n")
    }

    @Test("Enter on empty task list item terminates")
    func terminateTaskList() {
        let text = "- [ ] Done\n- [ ] "
        let ctx = context(text: text, cursorOffset: text.count)
        let mutation = rule.evaluate(ctx)

        #expect(mutation != nil)
        let (result, _) = apply(mutation!, to: text)
        #expect(result == "- [ ] Done\n")
    }

    // MARK: - Code Block Suppression

    @Test("Does not fire inside fenced code block")
    func codeBlockSuppression() {
        let text = "```\n- not a list\n```"
        let ctx = context(text: text, cursorOffset: 16) // inside code block
        let mutation = rule.evaluate(ctx)

        #expect(mutation == nil)
    }

    @Test("Does not fire inside tilde code block")
    func tildeCodeBlockSuppression() {
        let text = "~~~\n- not a list\n~~~"
        let ctx = context(text: text, cursorOffset: 16)
        let mutation = rule.evaluate(ctx)

        #expect(mutation == nil)
    }

    @Test("Fires outside code block normally")
    func outsideCodeBlock() {
        let text = "```\ncode\n```\n- Item"
        let ctx = context(text: text, cursorOffset: text.count)
        let mutation = rule.evaluate(ctx)

        #expect(mutation != nil)
    }

    // MARK: - Edge Cases

    @Test("Does not fire on non-list text")
    func nonListText() {
        let text = "Just a paragraph"
        let ctx = context(text: text, cursorOffset: text.count)
        let mutation = rule.evaluate(ctx)

        #expect(mutation == nil)
    }

    @Test("Does not fire on non-Enter trigger")
    func nonEnterTrigger() {
        let text = "- Item"
        let ctx = context(text: text, cursorOffset: text.count, trigger: .tab)
        let mutation = rule.evaluate(ctx)

        #expect(mutation == nil)
    }

    @Test("Haptic style is listContinuation")
    func hapticStyle() {
        let text = "- Item"
        let ctx = context(text: text, cursorOffset: text.count)
        let mutation = rule.evaluate(ctx)

        #expect(mutation?.hapticStyle == .listContinuation)
    }

    @Test("Empty document returns nil")
    func emptyDocument() {
        let text = ""
        let ctx = context(text: text, cursorOffset: 0)
        let mutation = rule.evaluate(ctx)

        #expect(mutation == nil)
    }

    @Test("Multi-digit ordered list continues correctly")
    func multiDigitOrdered() {
        let text = "10. Tenth item"
        let ctx = context(text: text, cursorOffset: text.count)
        let mutation = rule.evaluate(ctx)

        #expect(mutation != nil)
        let (result, _) = apply(mutation!, to: text)
        #expect(result == "10. Tenth item\n11. ")
    }
}
