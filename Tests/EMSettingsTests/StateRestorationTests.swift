import Testing
import Foundation
@testable import EMSettings

@MainActor
@Suite("State Restoration Settings")
struct StateRestorationTests {

    private func makeManager() -> (SettingsManager, UserDefaults) {
        let suiteName = "test.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        let manager = SettingsManager(defaults: defaults)
        return (manager, defaults)
    }

    @Test("State restoration defaults are nil/zero when UserDefaults is empty")
    func defaultValues() {
        let (m, _) = makeManager()
        #expect(m.lastOpenFileBookmark == nil)
        #expect(m.lastCursorPosition == 0)
        #expect(m.lastViewModeIsSource == false)
        #expect(m.lastScrollFraction == 0.0)
    }

    @Test("Last open file bookmark persists to UserDefaults")
    func bookmarkPersists() {
        let (m, d) = makeManager()
        let data = Data([0x01, 0x02, 0x03])
        m.lastOpenFileBookmark = data
        #expect(d.data(forKey: "em_lastOpenFileBookmark") == data)
    }

    @Test("Cursor position persists to UserDefaults")
    func cursorPositionPersists() {
        let (m, d) = makeManager()
        m.lastCursorPosition = 42
        #expect(d.integer(forKey: "em_lastCursorPosition") == 42)
    }

    @Test("View mode persists to UserDefaults")
    func viewModePersists() {
        let (m, d) = makeManager()
        m.lastViewModeIsSource = true
        #expect(d.bool(forKey: "em_lastViewModeIsSource") == true)
    }

    @Test("Scroll fraction persists to UserDefaults")
    func scrollFractionPersists() {
        let (m, d) = makeManager()
        m.lastScrollFraction = 0.75
        #expect(d.double(forKey: "em_lastScrollFraction") == 0.75)
    }

    @Test("clearStateRestoration resets all state restoration values")
    func clearStateRestoration() {
        let (m, _) = makeManager()
        m.lastOpenFileBookmark = Data([0x01])
        m.lastCursorPosition = 100
        m.lastViewModeIsSource = true
        m.lastScrollFraction = 0.5

        m.clearStateRestoration()

        #expect(m.lastOpenFileBookmark == nil)
        #expect(m.lastCursorPosition == 0)
        #expect(m.lastViewModeIsSource == false)
        #expect(m.lastScrollFraction == 0.0)
    }

    @Test("State restoration values restore from UserDefaults on init")
    func restoresFromDefaults() {
        let suiteName = "test.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        let data = Data([0xAA, 0xBB])

        defaults.set(data, forKey: "em_lastOpenFileBookmark")
        defaults.set(55, forKey: "em_lastCursorPosition")
        defaults.set(true, forKey: "em_lastViewModeIsSource")
        defaults.set(0.33, forKey: "em_lastScrollFraction")

        let m = SettingsManager(defaults: defaults)

        #expect(m.lastOpenFileBookmark == data)
        #expect(m.lastCursorPosition == 55)
        #expect(m.lastViewModeIsSource == true)
        #expect(m.lastScrollFraction == 0.33)
    }
}
