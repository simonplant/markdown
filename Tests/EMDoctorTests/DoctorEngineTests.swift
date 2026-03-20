import Testing
import Foundation
@testable import EMDoctor
@testable import EMParser
@testable import EMCore

@Suite("DoctorEngine")
struct DoctorEngineTests {

    private let parser = MarkdownParser()

    private func context(for text: String, fileURL: URL? = nil) -> DoctorContext {
        let result = parser.parse(text)
        return DoctorContext(text: text, ast: result.ast, fileURL: fileURL)
    }

    // MARK: - Engine

    @Test("Engine runs all rules and returns sorted diagnostics")
    func engineRunsAllRules() {
        let text = """
        # Heading

        ### Skipped Level

        ### Skipped Level
        """
        let ctx = context(for: text)
        let engine = DoctorEngine()
        let diagnostics = engine.evaluate(ctx)

        // Should find heading hierarchy skip and duplicate heading
        #expect(diagnostics.count >= 2)
        // Should be sorted by line
        for i in 1..<diagnostics.count {
            #expect(diagnostics[i].line >= diagnostics[i - 1].line)
        }
    }

    @Test("Engine with no rules returns empty")
    func engineNoRules() {
        let ctx = context(for: "# Hello\n\nSome text")
        let engine = DoctorEngine(rules: [])
        let diagnostics = engine.evaluate(ctx)
        #expect(diagnostics.isEmpty)
    }

    @Test("Clean document produces no diagnostics")
    func cleanDocument() {
        let text = """
        # Title

        Some text here.

        ## Section

        More text.

        ### Subsection

        Content.
        """
        let ctx = context(for: text)
        let engine = DoctorEngine()
        let diagnostics = engine.evaluate(ctx)
        #expect(diagnostics.isEmpty)
    }
}

@Suite("HeadingHierarchyRule")
struct HeadingHierarchyRuleTests {

    private let parser = MarkdownParser()
    private let rule = HeadingHierarchyRule()

    private func context(for text: String) -> DoctorContext {
        let result = parser.parse(text)
        return DoctorContext(text: text, ast: result.ast, fileURL: nil)
    }

    @Test("Flags H1 to H3 skip")
    func flagsSkip() {
        let text = "# Title\n\n### Skipped"
        let diagnostics = rule.evaluate(context(for: text))
        #expect(diagnostics.count == 1)
        #expect(diagnostics[0].ruleID == "heading-hierarchy")
        #expect(diagnostics[0].message.contains("H3"))
        #expect(diagnostics[0].message.contains("H1"))
    }

    @Test("No flag for sequential headings")
    func noFlagSequential() {
        let text = "# Title\n\n## Section\n\n### Sub"
        let diagnostics = rule.evaluate(context(for: text))
        #expect(diagnostics.isEmpty)
    }

    @Test("No flag for going shallower")
    func noFlagShallower() {
        let text = "# Title\n\n## Section\n\n### Sub\n\n# Another Title"
        let diagnostics = rule.evaluate(context(for: text))
        #expect(diagnostics.isEmpty)
    }

    @Test("Single heading produces no diagnostic")
    func singleHeading() {
        let text = "## Just One"
        let diagnostics = rule.evaluate(context(for: text))
        #expect(diagnostics.isEmpty)
    }

    @Test("Multiple skips flagged independently")
    func multipleSkips() {
        let text = "# Title\n\n### Skip1\n\n###### Skip2"
        let diagnostics = rule.evaluate(context(for: text))
        #expect(diagnostics.count == 2)
    }
}

@Suite("DuplicateHeadingRule")
struct DuplicateHeadingRuleTests {

    private let parser = MarkdownParser()
    private let rule = DuplicateHeadingRule()

    private func context(for text: String) -> DoctorContext {
        let result = parser.parse(text)
        return DoctorContext(text: text, ast: result.ast, fileURL: nil)
    }

    @Test("Flags duplicate headings at same level")
    func flagsDuplicate() {
        let text = "## Features\n\nSome text\n\n## Features"
        let diagnostics = rule.evaluate(context(for: text))
        #expect(diagnostics.count == 1)
        #expect(diagnostics[0].ruleID == "duplicate-heading")
        #expect(diagnostics[0].message.contains("Features"))
    }

    @Test("Same text at different levels is not duplicate")
    func differentLevelsNotDuplicate() {
        let text = "# Title\n\n## Title"
        let diagnostics = rule.evaluate(context(for: text))
        #expect(diagnostics.isEmpty)
    }

    @Test("Case-insensitive duplicate detection")
    func caseInsensitive() {
        let text = "## Setup\n\nText\n\n## setup"
        let diagnostics = rule.evaluate(context(for: text))
        #expect(diagnostics.count == 1)
    }

    @Test("No duplicates in unique headings")
    func noDuplicates() {
        let text = "# Title\n\n## First\n\n## Second\n\n## Third"
        let diagnostics = rule.evaluate(context(for: text))
        #expect(diagnostics.isEmpty)
    }
}

@Suite("BrokenRelativeLinkRule")
struct BrokenRelativeLinkRuleTests {

    private let parser = MarkdownParser()
    private let rule = BrokenRelativeLinkRule()

    private func context(for text: String, fileURL: URL? = nil) -> DoctorContext {
        let result = parser.parse(text)
        return DoctorContext(text: text, ast: result.ast, fileURL: fileURL)
    }

    @Test("Skips evaluation for unsaved documents")
    func skipsUnsaved() {
        let text = "[link](./missing.md)"
        let diagnostics = rule.evaluate(context(for: text, fileURL: nil))
        #expect(diagnostics.isEmpty)
    }

    @Test("Skips http/https URLs")
    func skipsHTTP() {
        let tmpDir = FileManager.default.temporaryDirectory
        let fileURL = tmpDir.appendingPathComponent("test.md")
        let text = "[link](https://example.com)"
        let diagnostics = rule.evaluate(context(for: text, fileURL: fileURL))
        #expect(diagnostics.isEmpty)
    }

    @Test("Skips anchor links")
    func skipsAnchors() {
        let tmpDir = FileManager.default.temporaryDirectory
        let fileURL = tmpDir.appendingPathComponent("test.md")
        let text = "[section](#heading)"
        let diagnostics = rule.evaluate(context(for: text, fileURL: fileURL))
        #expect(diagnostics.isEmpty)
    }

    @Test("Skips mailto links")
    func skipsMailto() {
        let tmpDir = FileManager.default.temporaryDirectory
        let fileURL = tmpDir.appendingPathComponent("test.md")
        let text = "[email](mailto:test@example.com)"
        let diagnostics = rule.evaluate(context(for: text, fileURL: fileURL))
        #expect(diagnostics.isEmpty)
    }

    @Test("Flags broken relative link")
    func flagsBrokenLink() {
        let tmpDir = FileManager.default.temporaryDirectory
        let fileURL = tmpDir.appendingPathComponent("test.md")
        let text = "[link](./definitely-nonexistent-file-abc123.md)"
        let diagnostics = rule.evaluate(context(for: text, fileURL: fileURL))
        #expect(diagnostics.count == 1)
        #expect(diagnostics[0].ruleID == "broken-relative-link")
    }

    @Test("Flags broken image source")
    func flagsBrokenImage() {
        let tmpDir = FileManager.default.temporaryDirectory
        let fileURL = tmpDir.appendingPathComponent("test.md")
        let text = "![alt](./nonexistent-image-xyz789.png)"
        let diagnostics = rule.evaluate(context(for: text, fileURL: fileURL))
        #expect(diagnostics.count == 1)
        #expect(diagnostics[0].message.contains("Image"))
    }
}

@Suite("TrailingWhitespaceRule")
struct TrailingWhitespaceRuleTests {

    private let parser = MarkdownParser()
    private let rule = TrailingWhitespaceRule()

    private func context(for text: String) -> DoctorContext {
        let result = parser.parse(text)
        return DoctorContext(text: text, ast: result.ast, fileURL: nil)
    }

    @Test("Flags trailing spaces")
    func flagsTrailingSpaces() {
        let text = "Hello   \nWorld"
        let diagnostics = rule.evaluate(context(for: text))
        #expect(diagnostics.count == 1)
        #expect(diagnostics[0].ruleID == "trailing-whitespace")
        #expect(diagnostics[0].fix != nil)
        #expect(diagnostics[0].fix?.replacement == "")
    }

    @Test("Flags trailing tabs")
    func flagsTrailingTabs() {
        let text = "Hello\t\nWorld"
        let diagnostics = rule.evaluate(context(for: text))
        #expect(diagnostics.count == 1)
    }

    @Test("Skips two trailing spaces (hard line break)")
    func skipsHardBreak() {
        let text = "Hello  \nWorld"
        let diagnostics = rule.evaluate(context(for: text))
        #expect(diagnostics.isEmpty)
    }

    @Test("No trailing whitespace is clean")
    func cleanLines() {
        let text = "Hello\nWorld\nTest"
        let diagnostics = rule.evaluate(context(for: text))
        #expect(diagnostics.isEmpty)
    }

    @Test("Multiple lines with trailing whitespace")
    func multipleLines() {
        let text = "Line 1   \nLine 2\nLine 3 "
        let diagnostics = rule.evaluate(context(for: text))
        #expect(diagnostics.count == 2)
    }
}

@Suite("MissingBlankLineRule")
struct MissingBlankLineRuleTests {

    private let parser = MarkdownParser()
    private let rule = MissingBlankLineRule()

    private func context(for text: String) -> DoctorContext {
        let result = parser.parse(text)
        return DoctorContext(text: text, ast: result.ast, fileURL: nil)
    }

    @Test("Flags heading followed directly by paragraph")
    func flagsHeadingParagraph() {
        let text = "# Title\nSome text"
        let diagnostics = rule.evaluate(context(for: text))
        #expect(diagnostics.count >= 1)
        #expect(diagnostics[0].ruleID == "missing-blank-line")
        #expect(diagnostics[0].fix != nil)
    }

    @Test("No flag when blank line exists")
    func noFlagWithBlankLine() {
        let text = "# Title\n\nSome text"
        let diagnostics = rule.evaluate(context(for: text))
        #expect(diagnostics.isEmpty)
    }

    @Test("Fix inserts blank line")
    func fixInsertsBlankLine() {
        let text = "# Title\nSome text"
        let diagnostics = rule.evaluate(context(for: text))
        if let fix = diagnostics.first?.fix {
            #expect(fix.replacement == "\n")
            #expect(fix.label == "Insert blank line")
        }
    }
}
