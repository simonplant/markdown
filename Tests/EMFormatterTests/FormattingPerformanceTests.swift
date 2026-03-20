import Testing
import Foundation
@testable import EMFormatter
@testable import EMCore

@Suite("Formatting Performance")
struct FormattingPerformanceTests {

    /// Generates a markdown list with the specified number of items.
    private func generateList(itemCount: Int) -> String {
        (1...itemCount).map { "- Item \($0)" }.joined(separator: "\n")
    }

    /// Generates an ordered markdown list with the specified number of items.
    private func generateOrderedList(itemCount: Int) -> String {
        (1...itemCount).map { "\($0). Item \($0)" }.joined(separator: "\n")
    }

    // MARK: - AC8: 500-item list frame budget

    @Test("Enter on 500-item unordered list completes within 16ms frame budget")
    func enterOn500ItemUnorderedList() {
        let engine = FormattingEngine.listFormattingEngine()
        let text = generateList(itemCount: 500)
        let cursor = text.endIndex

        let context = FormattingContext(
            text: text,
            cursorPosition: cursor,
            trigger: .enter
        )

        // Warm up
        _ = engine.evaluate(context)

        // Measure — must complete within 16ms (one frame at 60fps)
        let iterations = 100
        let start = CFAbsoluteTimeGetCurrent()
        for _ in 0..<iterations {
            _ = engine.evaluate(context)
        }
        let elapsed = CFAbsoluteTimeGetCurrent() - start
        let avgMs = (elapsed / Double(iterations)) * 1000.0

        #expect(avgMs < 16.0, "Auto-format on 500-item list took \(avgMs)ms avg, exceeds 16ms frame budget")
    }

    @Test("Enter on 500-item ordered list with renumbering completes within 16ms")
    func enterOn500ItemOrderedList() {
        let engine = FormattingEngine.listFormattingEngine()
        let text = generateOrderedList(itemCount: 500)
        // Insert after the first item to trigger maximum renumbering (499 siblings)
        let firstLineEnd = text.index(text.startIndex, offsetBy: "1. Item 1".count)

        let context = FormattingContext(
            text: text,
            cursorPosition: firstLineEnd,
            trigger: .enter
        )

        // Warm up
        _ = engine.evaluate(context)

        // Measure
        let iterations = 100
        let start = CFAbsoluteTimeGetCurrent()
        for _ in 0..<iterations {
            _ = engine.evaluate(context)
        }
        let elapsed = CFAbsoluteTimeGetCurrent() - start
        let avgMs = (elapsed / Double(iterations)) * 1000.0

        #expect(avgMs < 16.0, "Ordered list renumber on 500 items took \(avgMs)ms avg, exceeds 16ms frame budget")
    }

    @Test("Tab indent on 500-item list completes within 16ms")
    func tabOn500ItemList() {
        let engine = FormattingEngine.listFormattingEngine()
        let text = generateList(itemCount: 500)
        let cursor = text.endIndex

        let context = FormattingContext(
            text: text,
            cursorPosition: cursor,
            trigger: .tab
        )

        // Warm up
        _ = engine.evaluate(context)

        // Measure
        let iterations = 100
        let start = CFAbsoluteTimeGetCurrent()
        for _ in 0..<iterations {
            _ = engine.evaluate(context)
        }
        let elapsed = CFAbsoluteTimeGetCurrent() - start
        let avgMs = (elapsed / Double(iterations)) * 1000.0

        #expect(avgMs < 16.0, "Tab indent on 500-item list took \(avgMs)ms avg, exceeds 16ms frame budget")
    }

    @Test("Shift-Tab outdent on 500-item list completes within 16ms")
    func shiftTabOn500ItemList() {
        let engine = FormattingEngine.listFormattingEngine()
        // All items indented 2 spaces
        let text = (1...500).map { "  - Item \($0)" }.joined(separator: "\n")
        let cursor = text.endIndex

        let context = FormattingContext(
            text: text,
            cursorPosition: cursor,
            trigger: .shiftTab
        )

        // Warm up
        _ = engine.evaluate(context)

        // Measure
        let iterations = 100
        let start = CFAbsoluteTimeGetCurrent()
        for _ in 0..<iterations {
            _ = engine.evaluate(context)
        }
        let elapsed = CFAbsoluteTimeGetCurrent() - start
        let avgMs = (elapsed / Double(iterations)) * 1000.0

        #expect(avgMs < 16.0, "Shift-Tab on 500-item list took \(avgMs)ms avg, exceeds 16ms frame budget")
    }
}
