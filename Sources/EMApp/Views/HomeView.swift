import SwiftUI

/// Home screen per [D-UX-1]: no onboarding, no tutorial, no account creation.
/// Shows Open File and New File buttons. That's it.
struct HomeView: View {
    @Environment(AppRouter.self) private var router

    var body: some View {
        VStack(spacing: 32) {
            Spacer()

            Text("easy-markdown")
                .font(.largeTitle.weight(.semibold))
                .accessibilityAddTraits(.isHeader)

            VStack(spacing: 16) {
                Button(action: openFile) {
                    Label("Open File", systemImage: "doc")
                        .frame(maxWidth: 240)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .accessibilityHint("Opens the file picker to choose a markdown file")

                Button(action: newFile) {
                    Label("New File", systemImage: "doc.badge.plus")
                        .frame(maxWidth: 240)
                }
                .buttonStyle(.bordered)
                .controlSize(.large)
                .accessibilityHint("Creates a new empty markdown document")
            }

            Spacer()
        }
        .frame(maxWidth: .infinity)
        .navigationTitle("Home")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .toolbar {
            ToolbarItem(placement: .automatic) {
                Button(action: { router.showSettings() }) {
                    Image(systemName: "gearshape")
                }
                .accessibilityLabel("Settings")
            }
        }
    }

    private func openFile() {
        // File picker integration will come with FEAT-001.
        // For the shell, navigate to the editor to demonstrate navigation.
        router.openEditor()
    }

    private func newFile() {
        // File creation will come with FEAT-002.
        router.openEditor()
    }
}
