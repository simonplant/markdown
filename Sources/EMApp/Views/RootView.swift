import SwiftUI
import EMCore
import EMSettings

/// Root view with NavigationStack routing per [A-058].
/// Error banners and modal alerts are attached here so they cover all navigation destinations.
/// Handles state restoration on launch per [A-061].
public struct RootView: View {
    @State private var router = AppRouter()
    @Environment(ErrorPresenter.self) private var errorPresenter
    @Environment(RecentsManager.self) private var recentsManager
    @State private var hasAttemptedRestore = false

    public init() {}

    public var body: some View {
        NavigationStack(path: $router.path) {
            HomeView()
                .navigationDestination(for: AppRoute.self) { route in
                    switch route {
                    case .home:
                        HomeView()
                    case .editor:
                        EditorShellView()
                    }
                }
        }
        .sheet(item: $router.presentedSheet) { sheet in
            switch sheet {
            case .settings:
                SettingsView()
            case .subscriptionOffer:
                // Subscription screen — implemented with FEAT-062
                Text("Pro AI")
                    .presentationDetents([.medium])
            }
        }
        .overlay(alignment: .top) {
            if let banner = errorPresenter.currentBanner {
                ErrorBannerView(error: banner) {
                    errorPresenter.dismissBanner()
                }
                .transition(.move(edge: .top).combined(with: .opacity))
                .padding(.top, 8)
                .zIndex(1)
            }
        }
        .animation(.easeInOut(duration: 0.25), value: errorPresenter.currentBanner?.id)
        .errorAlert()
        .environment(router)
        .task {
            guard !hasAttemptedRestore else { return }
            hasAttemptedRestore = true
            attemptStateRestoration()
        }
    }

    /// Attempts to restore the last open file on launch per [A-061].
    ///
    /// If the last file's bookmark resolves successfully, navigates directly to the editor.
    /// If it fails (file deleted/moved), stays on home screen with recents list.
    private func attemptStateRestoration() {
        guard let restored = recentsManager.restoreLastFile() else {
            // No saved state or bookmark stale — show home screen with recents (AC-2)
            return
        }

        // Successfully resolved — navigate to editor (AC-1)
        // The restored state (cursor position, view mode, scroll) will be applied
        // by EditorShellView when full file coordination is wired (FEAT-001/FEAT-040).
        router.openEditor()
    }
}
