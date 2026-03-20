import Testing
import Foundation
#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif
@testable import EMEditor
@testable import EMParser
@testable import EMCore

@MainActor
@Suite("SyntaxHighlighter")
struct SyntaxHighlighterTests {

    private let renderer = MarkdownRenderer()
    private let parser = MarkdownParser()

    private var lightConfig: RenderConfiguration {
        RenderConfiguration(
            typeScale: .default,
            colors: .defaultLight,
            isSourceView: false
        )
    }

    private var darkConfig: RenderConfiguration {
        RenderConfiguration(
            typeScale: .default,
            colors: .defaultDark,
            isSourceView: false
        )
    }

    private var sourceConfig: RenderConfiguration {
        RenderConfiguration(
            typeScale: .default,
            colors: .defaultLight,
            isSourceView: true
        )
    }

    // MARK: - AC-1: Language tag produces syntax highlighting

    @Test("Swift code block with language tag gets keyword highlighting")
    func swiftKeywordHighlighting() {
        let source = "```swift\nlet x = 1\n```"
        let parseResult = parser.parse(source)
        let attrStr = NSMutableAttributedString(string: source)

        renderer.render(
            into: attrStr,
            ast: parseResult.ast,
            sourceText: source,
            config: lightConfig
        )

        // "let" should be highlighted as a keyword
        let letStart = (source as NSString).range(of: "let").location
        let color = attrStr.attribute(.foregroundColor, at: letStart, effectiveRange: nil) as? PlatformColor

        // Keyword color should differ from base code foreground
        #expect(color != nil)
        #expect(color != lightConfig.colors.codeForeground,
                "Keyword 'let' should be syntax-highlighted, not plain code foreground")
    }

    @Test("Python code block highlights keywords and strings")
    func pythonHighlighting() {
        let source = "```python\ndef hello():\n    print(\"world\")\n```"
        let parseResult = parser.parse(source)
        let attrStr = NSMutableAttributedString(string: source)

        renderer.render(
            into: attrStr,
            ast: parseResult.ast,
            sourceText: source,
            config: lightConfig
        )

        // "def" should be keyword color
        let defStart = (source as NSString).range(of: "def").location
        let defColor = attrStr.attribute(.foregroundColor, at: defStart, effectiveRange: nil) as? PlatformColor
        #expect(defColor == lightConfig.colors.syntaxKeyword,
                "Python 'def' should be keyword color")

        // "\"world\"" should be string color
        let worldStart = (source as NSString).range(of: "\"world\"").location
        let strColor = attrStr.attribute(.foregroundColor, at: worldStart, effectiveRange: nil) as? PlatformColor
        #expect(strColor == lightConfig.colors.syntaxString,
                "Python string should be string color")
    }

    @Test("JavaScript code block highlights keywords")
    func javascriptHighlighting() {
        let source = "```javascript\nconst foo = () => { return 42; };\n```"
        let parseResult = parser.parse(source)
        let attrStr = NSMutableAttributedString(string: source)

        renderer.render(
            into: attrStr,
            ast: parseResult.ast,
            sourceText: source,
            config: lightConfig
        )

        let constStart = (source as NSString).range(of: "const").location
        let color = attrStr.attribute(.foregroundColor, at: constStart, effectiveRange: nil) as? PlatformColor
        #expect(color == lightConfig.colors.syntaxKeyword)
    }

    @Test("Go code block highlights keywords")
    func goHighlighting() {
        let source = "```go\nfunc main() {\n\tfmt.Println(\"hello\")\n}\n```"
        let parseResult = parser.parse(source)
        let attrStr = NSMutableAttributedString(string: source)

        renderer.render(
            into: attrStr,
            ast: parseResult.ast,
            sourceText: source,
            config: lightConfig
        )

        let funcStart = (source as NSString).range(of: "func").location
        let color = attrStr.attribute(.foregroundColor, at: funcStart, effectiveRange: nil) as? PlatformColor
        #expect(color == lightConfig.colors.syntaxKeyword)
    }

    @Test("Rust code block highlights keywords")
    func rustHighlighting() {
        let source = "```rust\nfn main() {\n    let x: i32 = 5;\n}\n```"
        let parseResult = parser.parse(source)
        let attrStr = NSMutableAttributedString(string: source)

        renderer.render(
            into: attrStr,
            ast: parseResult.ast,
            sourceText: source,
            config: lightConfig
        )

        let fnStart = (source as NSString).range(of: "fn").location
        let color = attrStr.attribute(.foregroundColor, at: fnStart, effectiveRange: nil) as? PlatformColor
        #expect(color == lightConfig.colors.syntaxKeyword)
    }

    @Test("SQL highlighting is case insensitive")
    func sqlHighlighting() {
        let source = "```sql\nSELECT name FROM users WHERE id = 1;\n```"
        let parseResult = parser.parse(source)
        let attrStr = NSMutableAttributedString(string: source)

        renderer.render(
            into: attrStr,
            ast: parseResult.ast,
            sourceText: source,
            config: lightConfig
        )

        let selectStart = (source as NSString).range(of: "SELECT").location
        let color = attrStr.attribute(.foregroundColor, at: selectStart, effectiveRange: nil) as? PlatformColor
        #expect(color == lightConfig.colors.syntaxKeyword)
    }

    @Test("Bash code block highlights variables")
    func bashHighlighting() {
        let source = "```bash\necho $HOME\n```"
        let parseResult = parser.parse(source)
        let attrStr = NSMutableAttributedString(string: source)

        renderer.render(
            into: attrStr,
            ast: parseResult.ast,
            sourceText: source,
            config: lightConfig
        )

        let varStart = (source as NSString).range(of: "$HOME").location
        let color = attrStr.attribute(.foregroundColor, at: varStart, effectiveRange: nil) as? PlatformColor
        #expect(color == lightConfig.colors.syntaxType,
                "Bash variable should be type color")
    }

    @Test("Language aliases are normalized correctly")
    func languageAliases() {
        let aliases = [
            ("```py\ndef x():\n    pass\n```", "def"),
            ("```js\nconst x = 1;\n```", "const"),
            ("```ts\nlet x: number = 1;\n```", "let"),
            ("```sh\necho hello\n```", "echo"),
            ("```rb\ndef foo; end\n```", "def"),
            ("```kt\nfun main() {}\n```", "fun"),
            ("```c++\nint main() {}\n```", "int"),
            ("```yml\nkey: value\n```", "key"),
            ("```golang\nfunc main() {}\n```", "func"),
            ("```rs\nfn main() {}\n```", "fn"),
        ]

        for (source, expectedKeyword) in aliases {
            let parseResult = parser.parse(source)
            let attrStr = NSMutableAttributedString(string: source)

            renderer.render(
                into: attrStr,
                ast: parseResult.ast,
                sourceText: source,
                config: lightConfig
            )

            let kwStart = (source as NSString).range(of: expectedKeyword).location
            let color = attrStr.attribute(.foregroundColor, at: kwStart, effectiveRange: nil) as? PlatformColor
            #expect(color != lightConfig.colors.codeForeground,
                    "Alias should produce highlighting for: \(source.prefix(10))")
        }
    }

    // MARK: - AC-2: Light and dark mode adaptation

    @Test("Syntax colors differ between light and dark themes")
    func lightDarkAdaptation() {
        let source = "```swift\nlet x = 1\n```"
        let parseResult = parser.parse(source)

        let lightAttr = NSMutableAttributedString(string: source)
        renderer.render(into: lightAttr, ast: parseResult.ast, sourceText: source, config: lightConfig)

        let darkAttr = NSMutableAttributedString(string: source)
        renderer.render(into: darkAttr, ast: parseResult.ast, sourceText: source, config: darkConfig)

        let letStart = (source as NSString).range(of: "let").location
        let lightColor = lightAttr.attribute(.foregroundColor, at: letStart, effectiveRange: nil) as? PlatformColor
        let darkColor = darkAttr.attribute(.foregroundColor, at: letStart, effectiveRange: nil) as? PlatformColor

        #expect(lightColor != nil)
        #expect(darkColor != nil)
        #expect(lightColor != darkColor,
                "Syntax colors should differ between light and dark themes")
    }

    // MARK: - AC-3: Unknown language fallback

    @Test("Unknown language falls back to plain monospace, no broken rendering")
    func unknownLanguageFallback() {
        let source = "```brainfuck\n++++++++[>++++[>++>+++>+++>+<<<<-]>+>+>->>+[<]<-]>>.\n```"
        let parseResult = parser.parse(source)
        let attrStr = NSMutableAttributedString(string: source)

        renderer.render(
            into: attrStr,
            ast: parseResult.ast,
            sourceText: source,
            config: lightConfig
        )

        // Should still have code font and background (monospace fallback)
        let contentStart = (source as NSString).range(of: "+++++").location
        let font = attrStr.attribute(.font, at: contentStart, effectiveRange: nil) as? PlatformFont
        let bg = attrStr.attribute(.backgroundColor, at: contentStart, effectiveRange: nil) as? PlatformColor

        #expect(font != nil, "Unknown language should still have code font")
        #expect(bg != nil, "Unknown language should still have code background")

        // Content should use the base code foreground (no syntax colors applied)
        let color = attrStr.attribute(.foregroundColor, at: contentStart, effectiveRange: nil) as? PlatformColor
        #expect(color == lightConfig.colors.codeForeground,
                "Unknown language should use plain code foreground color")

        // Text must be preserved
        #expect(attrStr.string == source)
    }

    @Test("No language tag falls back to plain monospace")
    func noLanguageTag() {
        let source = "```\nplain code\n```"
        let parseResult = parser.parse(source)
        let attrStr = NSMutableAttributedString(string: source)

        renderer.render(
            into: attrStr,
            ast: parseResult.ast,
            sourceText: source,
            config: lightConfig
        )

        let contentStart = (source as NSString).range(of: "plain").location
        let color = attrStr.attribute(.foregroundColor, at: contentStart, effectiveRange: nil) as? PlatformColor
        #expect(color == lightConfig.colors.codeForeground,
                "No language tag should use plain code foreground")
    }

    // MARK: - AC-4: Empty code block

    @Test("Empty code block renders with background but no content crash")
    func emptyCodeBlock() {
        let source = "```swift\n```"
        let parseResult = parser.parse(source)
        let attrStr = NSMutableAttributedString(string: source)

        // Should not crash
        renderer.render(
            into: attrStr,
            ast: parseResult.ast,
            sourceText: source,
            config: lightConfig
        )

        // Background should be applied to the code block range
        let bg = attrStr.attribute(.backgroundColor, at: 0, effectiveRange: nil) as? PlatformColor
        #expect(bg != nil, "Empty code block should have background")
        #expect(attrStr.string == source, "Text must be preserved")
    }

    @Test("Code block with only whitespace content renders correctly")
    func whitespaceOnlyCodeBlock() {
        let source = "```\n   \n```"
        let parseResult = parser.parse(source)
        let attrStr = NSMutableAttributedString(string: source)

        renderer.render(
            into: attrStr,
            ast: parseResult.ast,
            sourceText: source,
            config: lightConfig
        )

        #expect(attrStr.string == source, "Text must be preserved")
    }

    // MARK: - AC-5: Code block inside blockquote

    @Test("Code block inside blockquote has both border and code background")
    func codeBlockInBlockquote() {
        let source = "> ```python\n> def foo():\n>     pass\n> ```"
        let parseResult = parser.parse(source)
        let attrStr = NSMutableAttributedString(string: source)

        renderer.render(
            into: attrStr,
            ast: parseResult.ast,
            sourceText: source,
            config: lightConfig
        )

        // The blockquote should have the border attribute
        let borderAttr = attrStr.attribute(.blockquoteBorder, at: 0, effectiveRange: nil)
        #expect(borderAttr != nil, "Blockquote containing code should have border attribute")

        // Text must be preserved
        #expect(attrStr.string == source)
    }

    // MARK: - Source View

    @Test("Source view applies syntax highlighting to code blocks")
    func sourceViewSyntaxHighlighting() {
        let source = "```swift\nlet x = 1\n```"
        let parseResult = parser.parse(source)
        let attrStr = NSMutableAttributedString(string: source)

        renderer.render(
            into: attrStr,
            ast: parseResult.ast,
            sourceText: source,
            config: sourceConfig
        )

        // "let" should be highlighted even in source view
        let letStart = (source as NSString).range(of: "let").location
        let color = attrStr.attribute(.foregroundColor, at: letStart, effectiveRange: nil) as? PlatformColor
        #expect(color != nil)
        #expect(color != lightConfig.colors.codeForeground,
                "Source view should also apply syntax highlighting to code blocks")
    }

    // MARK: - Comments priority over keywords

    @Test("Comments take priority over keywords within them")
    func commentPriority() {
        let source = "```swift\n// let x = 1\nlet y = 2\n```"
        let parseResult = parser.parse(source)
        let attrStr = NSMutableAttributedString(string: source)

        renderer.render(
            into: attrStr,
            ast: parseResult.ast,
            sourceText: source,
            config: lightConfig
        )

        // The "let" inside the comment should be comment color, not keyword color
        let commentLetStart = (source as NSString).range(of: "// let").location
        let commentColor = attrStr.attribute(.foregroundColor, at: commentLetStart, effectiveRange: nil) as? PlatformColor
        #expect(commentColor == lightConfig.colors.syntaxComment,
                "Keyword inside comment should have comment color")

        // The "let" outside the comment should be keyword color
        let codeLetStart = (source as NSString).range(of: "\nlet").location + 1
        let keywordColor = attrStr.attribute(.foregroundColor, at: codeLetStart, effectiveRange: nil) as? PlatformColor
        #expect(keywordColor == lightConfig.colors.syntaxKeyword,
                "Keyword outside comment should have keyword color")
    }

    // MARK: - Number highlighting

    @Test("Numbers are highlighted in code blocks")
    func numberHighlighting() {
        let source = "```swift\nlet x = 42\n```"
        let parseResult = parser.parse(source)
        let attrStr = NSMutableAttributedString(string: source)

        renderer.render(
            into: attrStr,
            ast: parseResult.ast,
            sourceText: source,
            config: lightConfig
        )

        let numStart = (source as NSString).range(of: "42").location
        let color = attrStr.attribute(.foregroundColor, at: numStart, effectiveRange: nil) as? PlatformColor
        #expect(color == lightConfig.colors.syntaxNumber,
                "Numbers should be highlighted with number color")
    }

    // MARK: - Text preservation

    @Test("Syntax highlighting preserves text content exactly")
    func textPreservation() {
        let sources = [
            "```swift\nlet x: Int = 42\nvar name = \"hello\"\n// comment\nfunc foo() -> Bool { return true }\n```",
            "```python\ndef hello():\n    '''docstring'''\n    x = 3.14\n    # comment\n```",
            "```json\n{\"key\": \"value\", \"num\": 42, \"bool\": true}\n```",
        ]

        for source in sources {
            let parseResult = parser.parse(source)
            let attrStr = NSMutableAttributedString(string: source)

            renderer.render(
                into: attrStr,
                ast: parseResult.ast,
                sourceText: source,
                config: lightConfig
            )

            #expect(attrStr.string == source,
                    "Syntax highlighting must not alter text content")
        }
    }
}
