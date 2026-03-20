import Foundation

/// A recently opened file entry per [A-061] and [D-UX-2].
///
/// Stored as a JSON array in UserDefaults. Max 20 entries.
/// Each entry contains the bookmark data needed to reopen the file
/// plus display metadata (filename, parent folder, last opened date).
public struct RecentItem: Codable, Identifiable, Sendable {
    /// Unique identifier for the entry.
    public let id: UUID

    /// The file's display name (e.g., "README.md").
    public let filename: String

    /// The parent folder name for display (e.g., "Documents").
    public let parentFolder: String

    /// The full file path for deduplication (not displayed).
    public let urlPath: String

    /// When the file was last opened.
    public let lastOpenedDate: Date

    /// Security-scoped bookmark data for reopening the file.
    public let bookmarkData: Data

    public init(
        id: UUID = UUID(),
        filename: String,
        parentFolder: String,
        urlPath: String,
        lastOpenedDate: Date,
        bookmarkData: Data
    ) {
        self.id = id
        self.filename = filename
        self.parentFolder = parentFolder
        self.urlPath = urlPath
        self.lastOpenedDate = lastOpenedDate
        self.bookmarkData = bookmarkData
    }
}
