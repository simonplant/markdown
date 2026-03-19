import SwiftUI

/// Bottom status bar showing word count and doctor indicator count per FEAT-037.
struct StatusBar: View {
    let wordCount: Int
    let diagnosticCount: Int

    var body: some View {
        HStack {
            Text(wordCountLabel)
                .accessibilityLabel(wordCountAccessibilityLabel)

            Spacer()

            if diagnosticCount > 0 {
                HStack(spacing: 4) {
                    Image(systemName: "stethoscope")
                        .imageScale(.small)
                    Text("\(diagnosticCount)")
                }
                .accessibilityElement(children: .combine)
                .accessibilityLabel(diagnosticAccessibilityLabel)
            }
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        .padding(.horizontal, 16)
        .padding(.vertical, 6)
        .background(.bar)
        .accessibilityElement(children: .contain)
    }

    private var wordCountLabel: String {
        "\(wordCount) \(wordCount == 1 ? "word" : "words")"
    }

    private var wordCountAccessibilityLabel: String {
        "\(wordCount) \(wordCount == 1 ? "word" : "words")"
    }

    private var diagnosticAccessibilityLabel: String {
        "\(diagnosticCount) document \(diagnosticCount == 1 ? "issue" : "issues")"
    }
}
