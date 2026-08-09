import Foundation

enum LocalFolderBookmarkStore {

    private static var bookmarkResolutionOptions: URL.BookmarkResolutionOptions {
        #if os(macOS)
        .withSecurityScope
        #else
        []
        #endif
    }

    static func save(_ bookmarkData: Data, for key: String) throws {
        try bookmarkData.write(to: fileURL(for: key))
    }

    /// Resolves bookmark data to a folder URL. Returns nil if the bookmark is missing or unresolvable.
    static func resolveURL(for key: String) -> URL? {
        guard let data = try? Data(contentsOf: fileURL(for: key)) else { return nil }
        var isStale = false
        return try? URL(
            resolvingBookmarkData: data,
            options: bookmarkResolutionOptions,
            relativeTo: nil,
            bookmarkDataIsStale: &isStale
        )
    }

    static func delete(for key: String) {
        try? FileManager.default.removeItem(at: fileURL(for: key))
    }

    static func deleteAll() {
        try? FileManager.default.removeItem(at: bookmarksDirectory)
    }

    private static var bookmarksDirectory: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("FolderBookmarks", isDirectory: true)
    }

    private static func fileURL(for key: String) -> URL {
        let dir = bookmarksDirectory
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("\(key).bookmark")
    }
}
