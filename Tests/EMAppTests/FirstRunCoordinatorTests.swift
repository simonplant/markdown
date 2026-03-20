import Testing
import Foundation
@testable import EMApp
@testable import EMSettings
@testable import EMCore

@MainActor
@Suite("FirstRunCoordinator")
struct FirstRunCoordinatorTests {

    private func makeSettings() -> SettingsManager {
        let suiteName = "test.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        return SettingsManager(defaults: defaults)
    }

    @Test("Banner not shown on unsupported device")
    func noPromptOnUnsupportedDevice() async {
        let settings = makeSettings()
        let coordinator = FirstRunCoordinator(settings: settings, capability: .noAI)
        await coordinator.evaluateFirstRunPrompt()
        #expect(coordinator.showModelDownloadBanner == false)
    }

    @Test("Banner shown on capable device when model not downloaded")
    func showsPromptOnCapableDevice() async {
        let settings = makeSettings()
        let coordinator = FirstRunCoordinator(settings: settings, capability: .fullAI)
        await coordinator.evaluateFirstRunPrompt()
        #expect(coordinator.showModelDownloadBanner == true)
    }

    @Test("Banner not shown when model already downloaded")
    func noPromptWhenAlreadyDownloaded() async {
        let settings = makeSettings()
        settings.modelDownloadState = .downloaded
        let coordinator = FirstRunCoordinator(settings: settings, capability: .fullAI)
        await coordinator.evaluateFirstRunPrompt()
        #expect(coordinator.showModelDownloadBanner == false)
    }

    @Test("Banner not shown when model is downloading")
    func noPromptWhenDownloading() async {
        let settings = makeSettings()
        settings.modelDownloadState = .downloading
        let coordinator = FirstRunCoordinator(settings: settings, capability: .fullAI)
        await coordinator.evaluateFirstRunPrompt()
        #expect(coordinator.showModelDownloadBanner == false)
    }

    @Test("Accept download updates state correctly")
    func acceptDownload() async {
        let settings = makeSettings()
        let coordinator = FirstRunCoordinator(settings: settings, capability: .fullAI)
        await coordinator.evaluateFirstRunPrompt()
        #expect(coordinator.showModelDownloadBanner == true)

        coordinator.acceptDownload()
        #expect(coordinator.showModelDownloadBanner == false)
        #expect(settings.modelDownloadState == .downloading)
        #expect(settings.hasSeenModelDownloadPrompt == true)
    }

    @Test("Dismiss download hides banner without marking as seen")
    func dismissDownload() async {
        let settings = makeSettings()
        let coordinator = FirstRunCoordinator(settings: settings, capability: .fullAI)
        await coordinator.evaluateFirstRunPrompt()
        #expect(coordinator.showModelDownloadBanner == true)

        coordinator.dismissDownload()
        #expect(coordinator.showModelDownloadBanner == false)
        // hasSeenModelDownloadPrompt stays false so it reappears next launch
        #expect(settings.hasSeenModelDownloadPrompt == false)
        #expect(settings.modelDownloadState == .notDownloaded)
    }
}
