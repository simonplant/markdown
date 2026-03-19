import SwiftUI
import EMSettings

/// Root view with NavigationStack routing per [A-058].
public struct RootView: View {
    @State private var router = AppRouter()

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
        .environment(router)
    }
}
