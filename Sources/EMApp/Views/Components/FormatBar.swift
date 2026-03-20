import SwiftUI

/// Inline format action bar displayed above the status bar.
/// Format buttons are always visible per FEAT-037 acceptance criteria.
/// Trackpad hover states per FEAT-015 AC-4.
struct FormatBar: View {
    var body: some View {
        HStack(spacing: 16) {
            FormatButton(icon: "bold", label: "Bold")
            FormatButton(icon: "italic", label: "Italic")
            FormatButton(icon: "strikethrough", label: "Strikethrough")
            FormatButton(icon: "link", label: "Insert link")
            FormatButton(icon: "list.bullet", label: "List")
            FormatButton(icon: "number", label: "Heading")
        }
        .disabled(true) // Enabled when EMEditor is implemented
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Formatting toolbar")
    }
}

private struct FormatButton: View {
    let icon: String
    let label: String

    var body: some View {
        Button(action: {}) {
            Image(systemName: icon)
                .imageScale(.medium)
        }
        .accessibilityLabel(label)
        #if os(iOS)
        .hoverEffect(.highlight)
        #endif
    }
}
