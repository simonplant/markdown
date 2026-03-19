import SwiftUI
#if canImport(UIKit)
import UIKit
#endif
import EMCore

/// Editor shell: toolbar at top, content area in center, format bar and status bar at bottom.
/// The actual text editor (EMEditor) will replace the placeholder content area.
struct EditorShellView: View {
    @Environment(AppRouter.self) private var router
    @State private var isSourceView = false
    @State private var text = ""
    @State private var wordCount = 0
    @State private var diagnosticCount = 0

    var body: some View {
        VStack(spacing: 0) {
            // Editor content area — placeholder until EMEditor is implemented (FEAT-039)
            TextEditor(text: $text)
                .scrollContentBackground(.hidden)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .accessibilityLabel("Document editor")
                .accessibilityHint("Edit your markdown document here")
                .onChange(of: text) { _, newValue in
                    updateWordCount(newValue)
                }

            Divider()
            FormatBar()
            Divider()
            StatusBar(wordCount: wordCount, diagnosticCount: diagnosticCount)
        }
        .navigationTitle("Untitled")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .toolbar {
            EditorToolbar(
                isSourceView: isSourceView,
                onToggleSource: toggleSourceView,
                onSettings: { router.showSettings() }
            )
        }
    }

    private func toggleSourceView() {
        isSourceView.toggle()
        #if canImport(UIKit)
        HapticFeedback.trigger(.toggleView)
        #endif
    }

    private func updateWordCount(_ text: String) {
        let words = text.split(omittingEmptySubsequences: true) { $0.isWhitespace || $0.isNewline }
        wordCount = words.count
    }
}
