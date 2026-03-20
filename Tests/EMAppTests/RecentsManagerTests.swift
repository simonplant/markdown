import Testing
import Foundation
@testable import EMApp
@testable import EMSettings

@MainActor
@Suite("RecentsManager")
struct RecentsManagerTests {

    private func makeManager() -> (RecentsManager, UserDefaults, SettingsManager) {
        let suiteName = "test.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        let settings = SettingsManager(defaults: defaults)
        let manager = RecentsManager(defaults: defaults, settings: settings)
        return (manager, defaults, settings)
    }

    @Test("Initial state has empty recents")
    func initialState() {
        let (m, _, _) = makeManager()
        #expect(m.recentItems.isEmpty)
    }

    @Test("RecentItem encodes and decodes correctly")
    func recentItemCodable() throws {
        let item = RecentItem(
            filename: "test.md",
            parentFolder: "Documents",
            urlPath: "/Users/test/Documents/test.md",
            lastOpenedDate: Date(timeIntervalSince1970: 1000),
            bookmarkData: Data([0x01, 0x02])
        )

        let encoded = try JSONEncoder().encode(item)
        let decoded = try JSONDecoder().decode(RecentItem.self, from: encoded)

        #expect(decoded.filename == "test.md")
        #expect(decoded.parentFolder == "Documents")
        #expect(decoded.urlPath == "/Users/test/Documents/test.md")
        #expect(decoded.bookmarkData == Data([0x01, 0x02]))
        #expect(decoded.id == item.id)
    }

    @Test("saveEditorState persists cursor, view mode, and scroll to settings")
    func saveEditorState() {
        let (m, _, settings) = makeManager()
        m.saveEditorState(cursorPosition: 150, isSourceView: true, scrollFraction: 0.6)

        #expect(settings.lastCursorPosition == 150)
        #expect(settings.lastViewModeIsSource == true)
        #expect(settings.lastScrollFraction == 0.6)
    }

    @Test("clearLastFileState clears all restoration data")
    func clearLastFileState() {
        let (m, _, settings) = makeManager()

        settings.lastOpenFileBookmark = Data([0x01])
        settings.lastCursorPosition = 100
        settings.lastViewModeIsSource = true
        settings.lastScrollFraction = 0.5

        m.clearLastFileState()

        #expect(settings.lastOpenFileBookmark == nil)
        #expect(settings.lastCursorPosition == 0)
        #expect(settings.lastViewModeIsSource == false)
        #expect(settings.lastScrollFraction == 0.0)
    }

    @Test("restoreLastFile returns nil when no bookmark saved")
    func restoreLastFileNoBookmark() {
        let (m, _, _) = makeManager()
        #expect(m.restoreLastFile() == nil)
    }

    @Test("restoreLastFile returns nil and clears state when bookmark is stale")
    func restoreLastFileStaleBookmark() {
        let (m, _, settings) = makeManager()

        // Set bogus bookmark data that will fail resolution
        settings.lastOpenFileBookmark = Data([0xFF, 0xFE])
        settings.lastCursorPosition = 42

        let result = m.restoreLastFile()

        #expect(result == nil)
        // State should be cleared after stale bookmark
        #expect(settings.lastOpenFileBookmark == nil)
        #expect(settings.lastCursorPosition == 0)
    }

    @Test("RecentItem stores all required display fields")
    func recentItemDisplayFields() {
        let date = Date()
        let item = RecentItem(
            filename: "README.md",
            parentFolder: "project",
            urlPath: "/Users/test/project/README.md",
            lastOpenedDate: date,
            bookmarkData: Data()
        )

        // AC-4: Recents list shows filename, parent folder, and last opened date
        #expect(item.filename == "README.md")
        #expect(item.parentFolder == "project")
        #expect(item.lastOpenedDate == date)
    }

    @Test("Multiple RecentItems can be encoded as array")
    func multipleItemsCodable() throws {
        let items = [
            RecentItem(filename: "a.md", parentFolder: "docs", urlPath: "/docs/a.md", lastOpenedDate: Date(), bookmarkData: Data([0x01])),
            RecentItem(filename: "b.md", parentFolder: "notes", urlPath: "/notes/b.md", lastOpenedDate: Date(), bookmarkData: Data([0x02])),
        ]

        let encoded = try JSONEncoder().encode(items)
        let decoded = try JSONDecoder().decode([RecentItem].self, from: encoded)

        #expect(decoded.count == 2)
        #expect(decoded[0].filename == "a.md")
        #expect(decoded[1].filename == "b.md")
    }
}
