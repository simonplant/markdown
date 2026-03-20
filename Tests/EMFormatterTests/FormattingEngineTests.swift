import Testing
import Foundation
@testable import EMFormatter
@testable import EMCore

@Suite("FormattingEngine")
struct FormattingEngineTests {

    private func apply(_ mutation: TextMutation, to text: String) -> String {
        let prefix = String(text[..<mutation.range.lowerBound])
        let suffix = String(text[mutation.range.upperBound...])
        return prefix + mutation.replacement + suffix
    }

    private func context(
        text: String,
        cursorOffset: Int,
        trigger: FormattingTrigger
    ) -> FormattingContext {
        let cursor = text.index(text.startIndex, offsetBy: cursorOffset)
        return FormattingContext(text: text, cursorPosition: cursor, trigger: trigger)
    }

    @Test("Default engine handles Enter on list item")
    func engineHandlesEnter() {
        let engine = FormattingEngine.listFormattingEngine()
        let text = "- Item"
        let ctx = context(text: text, cursorOffset: text.count, trigger: .enter)
        let mutation = engine.evaluate(ctx)

        #expect(mutation != nil)
        let result = apply(mutation!, to: text)
        #expect(result == "- Item\n- ")
    }

    @Test("Default engine handles Tab on list item")
    func engineHandlesTab() {
        let engine = FormattingEngine.listFormattingEngine()
        let text = "- Item"
        let ctx = context(text: text, cursorOffset: text.count, trigger: .tab)
        let mutation = engine.evaluate(ctx)

        #expect(mutation != nil)
        let result = apply(mutation!, to: text)
        #expect(result == "  - Item")
    }

    @Test("Engine returns nil for non-list text")
    func engineNonList() {
        let engine = FormattingEngine.listFormattingEngine()
        let text = "Just text"
        let ctx = context(text: text, cursorOffset: text.count, trigger: .enter)
        let mutation = engine.evaluate(ctx)

        #expect(mutation == nil)
    }

    @Test("Engine with no rules returns nil")
    func emptyEngine() {
        let engine = FormattingEngine(rules: [])
        let text = "- Item"
        let ctx = context(text: text, cursorOffset: text.count, trigger: .enter)
        let mutation = engine.evaluate(ctx)

        #expect(mutation == nil)
    }

    @Test("First matching rule wins")
    func firstRuleWins() {
        let engine = FormattingEngine.listFormattingEngine()
        let text = "- Item"
        let ctx = context(text: text, cursorOffset: text.count, trigger: .enter)
        let mutation = engine.evaluate(ctx)

        // ListContinuationRule should fire (first rule), not ListIndentRule
        #expect(mutation != nil)
        let result = apply(mutation!, to: text)
        #expect(result == "- Item\n- ") // continuation, not indentation
    }

    @Test("Engine handles ordered list with renumbering")
    func engineOrderedRenumber() {
        let engine = FormattingEngine.listFormattingEngine()
        let text = "1. First\n2. Second"
        // Enter at end of "1. First"
        let ctx = context(text: text, cursorOffset: 8, trigger: .enter)
        let mutation = engine.evaluate(ctx)

        #expect(mutation != nil)
        let result = apply(mutation!, to: text)
        #expect(result == "1. First\n2. \n3. Second")
    }
}
