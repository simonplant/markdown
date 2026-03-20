import SwiftUI

/// Non-modal banner offering AI model download per [D-AI-9] and FEAT-044.
/// Appears on capable devices (A16+/M1+) after a brief delay on first launch.
/// Dismissable — user is asked again on next launch if dismissed.
struct ModelDownloadBannerView: View {
    let onDownload: () -> Void
    let onDismiss: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "arrow.down.circle.fill")
                .font(.title3.weight(.semibold))
                .foregroundStyle(.blue)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 2) {
                Text("Download AI assistant?")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.primary)

                Text("~3 GB, Wi-Fi recommended")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Button("Download") {
                onDownload()
            }
            .font(.subheadline.weight(.medium))
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
            .accessibilityHint("Starts downloading the AI model in the background")

            Button {
                onDismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.borderless)
            .accessibilityLabel("Dismiss")
            .accessibilityHint("Dismiss this prompt. You will be asked again next time.")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(Color.blue.opacity(0.3), lineWidth: 1)
        )
        .padding(.horizontal, 16)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Download AI assistant. About 3 gigabytes. Wi-Fi recommended.")
        .accessibilityAddTraits(.isStaticText)
    }
}
