import EMCore
import EMParser

/// The keystroke that triggered the formatting check per [A-051].
public enum FormattingTrigger: Sendable, Equatable {
    /// Enter/Return key pressed.
    case enter
    /// Tab key pressed.
    case tab
    /// Shift-Tab key pressed.
    case shiftTab
}

/// Context passed to formatting rules for evaluation per [A-051].
///
/// Contains the document text, cursor position, triggering keystroke,
/// and optional AST for context-aware decisions (e.g., code block suppression).
public struct FormattingContext: Sendable {
    /// The full document text.
    public let text: String
    /// The cursor position within the text.
    public let cursorPosition: String.Index
    /// The keystroke that triggered this formatting check.
    public let trigger: FormattingTrigger
    /// The current AST, if available. May be nil between parses.
    public let ast: MarkdownAST?

    public init(
        text: String,
        cursorPosition: String.Index,
        trigger: FormattingTrigger,
        ast: MarkdownAST? = nil
    ) {
        self.text = text
        self.cursorPosition = cursorPosition
        self.trigger = trigger
        self.ast = ast
    }
}

/// A discrete formatting rule that may produce a text mutation per [A-051].
///
/// Each rule is individually toggleable via settings. Rules are invoked
/// by the keystroke interception pipeline in EMEditor.
public protocol FormattingRule: Sendable {
    /// Evaluate the context and return a mutation if this rule applies.
    /// Returns `nil` if the rule does not apply to the current context.
    func evaluate(_ context: FormattingContext) -> TextMutation?
}
