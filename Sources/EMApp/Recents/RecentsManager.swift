import Foundation
import Observation
import EMCore
import EMFile
import EMSettings
import os

/// Manages the recents list and state restoration per [A-061].
///
/// Stores recent file entries in UserDefaults as a JSON array.
/// Uses BookmarkManager from EMFile for security-scoped bookmark operations.
/// Max 20 entries. Stale entries (deleted/moved files) are removed gracefully.
@MainActor
@Observable
public final class RecentsManager {
    private let defaults: UserDefaults
    private let bookmarkManager: BookmarkManager
    private let settings: SettingsManager
    private let recentsKey = "em_recentFiles"
    private let logger = Logger(subsystem: "com.easymarkdown.emapp", category: "recents")

    /// Maximum number of recent entries to keep.
    private let maxEntries = 20

    /// The current list of recent items, validated and sorted by last opened date.
    public private(set) var recentItems: [RecentItem] = []

    public init(
        defaults: UserDefaults = .standard,
        bookmarkManager: BookmarkManager = BookmarkManager(),
        settings: SettingsManager
    ) {
        self.defaults = defaults
        self.bookmarkManager = bookmarkManager
        self.settings = settings
        self.recentItems = loadRecents()
    }

    // MARK: - Public API

    /// Records a file open event. Adds or updates the file in the recents list.
    ///
    /// Also saves a bookmark for state restoration via SettingsManager.
    /// - Parameter url: The file URL being opened.
    public func recordFileOpen(url: URL) {
        do {
            let bookmarkData = try bookmarkManager.saveBookmark(for: url)
            let filename = url.lastPathComponent
            let parentFolder = url.deletingLastPathComponent().lastPathComponent
            let urlPath = url.path

            // Remove any existing entry for this file (deduplicate by path)
            recentItems.removeAll { $0.urlPath == urlPath }

            let item = RecentItem(
                filename: filename,
                parentFolder: parentFolder,
                urlPath: urlPath,
                lastOpenedDate: Date(),
                bookmarkData: bookmarkData
            )

            recentItems.insert(item, at: 0)

            // Enforce max entries
            if recentItems.count > maxEntries {
                recentItems = Array(recentItems.prefix(maxEntries))
            }

            saveRecents()

            // Save bookmark for state restoration
            settings.lastOpenFileBookmark = bookmarkData

            logger.info("Recorded file open: \(filename, privacy: .public)")
        } catch {
            logger.error("Failed to create bookmark for recents: \(error.localizedDescription, privacy: .public)")
        }
    }

    /// Resolves a recent item's bookmark back to a URL.
    ///
    /// If resolution fails (file deleted/moved), the entry is removed from recents.
    /// - Returns: The resolved URL, or nil if the bookmark is stale.
    public func resolveRecentItem(_ item: RecentItem) -> URL? {
        do {
            let url = try bookmarkManager.resolveBookmark(item.bookmarkData)
            return url
        } catch {
            // Bookmark is stale — remove the entry gracefully (AC-3)
            removeRecentItem(item)
            logger.info("Removed stale recent entry: \(item.filename, privacy: .public)")
            return nil
        }
    }

    /// Removes a specific recent item.
    public func removeRecentItem(_ item: RecentItem) {
        recentItems.removeAll { $0.id == item.id }
        saveRecents()
    }

    /// Validates all recent entries by attempting to resolve their bookmarks.
    /// Removes any entries whose files are no longer accessible.
    public func pruneStaleEntries() {
        let validItems = recentItems.filter { item in
            do {
                _ = try bookmarkManager.resolveBookmark(item.bookmarkData)
                return true
            } catch {
                logger.info("Pruning stale recent: \(item.filename, privacy: .public)")
                return false
            }
        }

        if validItems.count != recentItems.count {
            recentItems = validItems
            saveRecents()
        }
    }

    /// Attempts to restore the last open file from saved state.
    ///
    /// Per [A-061]: resolves bookmark, returns URL + cursor + view mode + scroll.
    /// If resolution fails, clears state restoration data and returns nil.
    public func restoreLastFile() -> RestoredState? {
        guard let bookmarkData = settings.lastOpenFileBookmark else {
            return nil
        }

        do {
            let url = try bookmarkManager.resolveBookmark(bookmarkData)
            return RestoredState(
                fileURL: url,
                cursorPosition: settings.lastCursorPosition,
                isSourceView: settings.lastViewModeIsSource,
                scrollFraction: settings.lastScrollFraction
            )
        } catch {
            // File no longer accessible — clear state, fall back to home/recents
            settings.clearStateRestoration()
            logger.info("Last file bookmark stale, cleared state restoration")
            return nil
        }
    }

    /// Saves the current editor state for restoration on next launch.
    /// Called on file open/close, view toggle, app background. Debounced by caller.
    public func saveEditorState(
        cursorPosition: Int,
        isSourceView: Bool,
        scrollFraction: Double
    ) {
        settings.lastCursorPosition = cursorPosition
        settings.lastViewModeIsSource = isSourceView
        settings.lastScrollFraction = scrollFraction
    }

    /// Clears state restoration (e.g., when user closes a file and returns home).
    public func clearLastFileState() {
        settings.clearStateRestoration()
    }

    // MARK: - Private

    private func loadRecents() -> [RecentItem] {
        guard let data = defaults.data(forKey: recentsKey) else { return [] }
        do {
            return try JSONDecoder().decode([RecentItem].self, from: data)
        } catch {
            logger.error("Failed to decode recents: \(error.localizedDescription, privacy: .public)")
            return []
        }
    }

    private func saveRecents() {
        do {
            let data = try JSONEncoder().encode(recentItems)
            defaults.set(data, forKey: recentsKey)
        } catch {
            logger.error("Failed to encode recents: \(error.localizedDescription, privacy: .public)")
        }
    }
}

/// Restored editor state from a previous session per [A-061].
public struct RestoredState: Sendable {
    /// The resolved file URL.
    public let fileURL: URL

    /// Character offset of the cursor in raw text.
    public let cursorPosition: Int

    /// Whether the editor was in source view mode.
    public let isSourceView: Bool

    /// Scroll position as a fraction (0.0–1.0) of document height.
    public let scrollFraction: Double
}
