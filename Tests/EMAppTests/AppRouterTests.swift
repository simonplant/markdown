import Testing
@testable import EMApp

@Suite("AppRouter")
struct AppRouterTests {

    @Test("Initial state is empty path with no sheet")
    @MainActor
    func initialState() {
        let router = AppRouter()
        #expect(router.path.count == 0)
        #expect(router.presentedSheet == nil)
    }

    @Test("openEditor pushes to path")
    @MainActor
    func openEditor() {
        let router = AppRouter()
        router.openEditor()
        #expect(router.path.count == 1)
    }

    @Test("popToHome clears path")
    @MainActor
    func popToHome() {
        let router = AppRouter()
        router.openEditor()
        router.popToHome()
        #expect(router.path.count == 0)
    }

    @Test("showSettings presents sheet")
    @MainActor
    func showSettings() {
        let router = AppRouter()
        router.showSettings()
        #expect(router.presentedSheet == .settings)
    }

    @Test("dismissSheet clears presented sheet")
    @MainActor
    func dismissSheet() {
        let router = AppRouter()
        router.showSettings()
        router.dismissSheet()
        #expect(router.presentedSheet == nil)
    }

    @Test("showSubscriptionOffer presents sheet")
    @MainActor
    func showSubscriptionOffer() {
        let router = AppRouter()
        router.showSubscriptionOffer()
        #expect(router.presentedSheet == .subscriptionOffer)
    }
}
