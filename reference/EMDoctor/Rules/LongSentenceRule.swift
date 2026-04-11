import EMCore
import EMParser
import Foundation
import NaturalLanguage

/// Flags sentences exceeding a word count threshold per FEAT-022.
///
/// Long sentences reduce readability. This rule uses `NLTokenizer` for
/// language-aware sentence and word segmentation, then flags any sentence
/// with more than `threshold` words (default: 50). Informational only —
/// the user navigates to the flagged line and edits manually.
struct LongSentenceRule: DoctorRule {
    let ruleID = "long-sentence"

    /// Word count threshold above which a sentence is flagged.
    let threshold: Int

    init(threshold: Int = 50) {
        self.threshold = threshold
    }

    func evaluate(_ context: DoctorContext) -> [Diagnostic] {
        let text = context.text
        guard !text.isEmpty else { return [] }

        // Pre-split on sentence-ending punctuation followed by whitespace.
        // NLTokenizer sometimes merges adjacent sentences with minimal whitespace.
        let sentences = splitSentences(text)

        let wordTokenizer = NLTokenizer(unit: .word)

        var diagnostics: [Diagnostic] = []

        for (sentenceStr, sentenceStartIndex) in sentences {
            wordTokenizer.string = sentenceStr
            var wordCount = 0
            wordTokenizer.enumerateTokens(in: sentenceStr.startIndex..<sentenceStr.endIndex) { _, _ in
                wordCount += 1
                return true
            }

            if wordCount > threshold {
                let line = lineNumber(for: sentenceStartIndex, in: text)

                diagnostics.append(Diagnostic(
                    ruleID: ruleID,
                    message: "Sentence has \(wordCount) words — consider breaking it up for readability.",
                    severity: .warning,
                    line: line
                ))
            }
        }

        return diagnostics
    }

    /// Splits text into sentences by splitting on sentence-ending punctuation
    /// followed by whitespace. Returns each sentence with its start index in the original text.
    private func splitSentences(_ text: String) -> [(String, String.Index)] {
        var results: [(String, String.Index)] = []
        var current = text.startIndex

        while current < text.endIndex {
            // Find next sentence-ending punctuation followed by whitespace
            var end = current
            var foundEnd = false
            while end < text.endIndex {
                let char = text[end]
                if char == "." || char == "!" || char == "?" {
                    let next = text.index(after: end)
                    if next >= text.endIndex || text[next].isWhitespace {
                        let sentenceEnd = text.index(after: end)
                        let sentence = String(text[current..<sentenceEnd]).trimmingCharacters(in: .whitespaces)
                        if !sentence.isEmpty {
                            results.append((sentence, current))
                        }
                        // Skip whitespace after punctuation
                        current = sentenceEnd
                        while current < text.endIndex && text[current].isWhitespace {
                            current = text.index(after: current)
                        }
                        foundEnd = true
                        break
                    }
                }
                end = text.index(after: end)
            }
            if !foundEnd {
                // Remaining text without sentence-ending punctuation
                let sentence = String(text[current...]).trimmingCharacters(in: .whitespaces)
                if !sentence.isEmpty {
                    results.append((sentence, current))
                }
                break
            }
        }
        return results
    }

    /// Returns the 1-based line number for a string index.
    private func lineNumber(for index: String.Index, in text: String) -> Int {
        var line = 1
        var pos = text.startIndex
        while pos < index {
            if text[pos] == "\n" {
                line += 1
            }
            pos = text.index(after: pos)
        }
        return line
    }
}
