import Foundation
import SwiftData

@MainActor
enum LocalFileImportService {
    static let localShowFeedURL = "local://imported-files"

    struct ImportResult {
        let imported: Int
        let failed: Int
    }

    private static let audioExtensions: Set<String> = [
        "mp3", "m4a", "wav", "aac", "flac", "aiff", "aif"
    ]

    private static var bookmarkOptions: URL.BookmarkCreationOptions {
        #if os(macOS)
        .withSecurityScope
        #else
        []
        #endif
    }

    // Import individually selected files (each URL requires its own security-scoped access).
    static func importFiles(
        _ fileURLs: [URL],
        folder: Folder?,
        context: ModelContext
    ) throws -> ImportResult {
        let isNewShow = fetchLocalShow(context: context) == nil
        if isNewShow {
            try PlanStore.shared.validateCanRegisterShow(context: context)
        }

        let show = fetchOrCreateLocalShow(in: folder, context: context)
        let existingCount = show.episodes.count
        let destDir = try localStorageDirectory()
        let sortedURLs = fileURLs.sorted { $0.lastPathComponent < $1.lastPathComponent }

        var imported = 0
        var failed = 0

        for (index, sourceURL) in sortedURLs.enumerated() {
            let accessed = sourceURL.startAccessingSecurityScopedResource()
            defer { if accessed { sourceURL.stopAccessingSecurityScopedResource() } }
            do {
                try copyAndRegister(
                    sourceURL: sourceURL,
                    index: existingCount + index,
                    show: show,
                    destDir: destDir,
                    context: context
                )
                imported += 1
            } catch {
                failed += 1
            }
        }

        context.processPendingChanges()
        try context.save()
        NotificationCenter.default.post(name: .libraryContentDidChange, object: nil)
        return ImportResult(imported: imported, failed: failed)
    }

    // Register a folder picked directly from the Files picker.
    static func registerFolder(
        _ folderURL: URL,
        folder: Folder?,
        context: ModelContext
    ) throws -> ImportResult {
        try PlanStore.shared.validateCanRegisterShow(context: context)

        let accessed = folderURL.startAccessingSecurityScopedResource()
        defer { if accessed { folderURL.stopAccessingSecurityScopedResource() } }

        let bookmarkKey = UUID().uuidString
        guard let data = try? folderURL.bookmarkData(
            options: bookmarkOptions,
            includingResourceValuesForKeys: nil,
            relativeTo: nil
        ) else {
            return ImportResult(imported: 0, failed: 0)
        }
        try? LocalFolderBookmarkStore.save(data, for: bookmarkKey)

        let audioFiles = audioFilesInDirectory(folderURL)
        guard !audioFiles.isEmpty else {
            LocalFolderBookmarkStore.delete(for: bookmarkKey)
            return ImportResult(imported: 0, failed: 0)
        }

        try insertFolderBookmarkShow(
            bookmarkKey: bookmarkKey,
            displayName: folderDisplayName(for: folderURL),
            audioFiles: audioFiles,
            folder: folder,
            context: context
        )
        return ImportResult(imported: audioFiles.count, failed: 0)
    }

    // Register a folder as a show by picking any one audio file from it.
    // Works for local storage where the parent directory is listable.
    static func registerFolderFromFile(
        _ fileURL: URL,
        folder: Folder?,
        context: ModelContext
    ) throws -> ImportResult {
        try PlanStore.shared.validateCanRegisterShow(context: context)

        let accessed = fileURL.startAccessingSecurityScopedResource()
        defer { if accessed { fileURL.stopAccessingSecurityScopedResource() } }

        let folderURL = fileURL.deletingLastPathComponent()
        let bookmarkKey = UUID().uuidString
        if let data = try? folderURL.bookmarkData(
            options: bookmarkOptions,
            includingResourceValuesForKeys: nil,
            relativeTo: nil
        ) {
            try? LocalFolderBookmarkStore.save(data, for: bookmarkKey)
        }

        let audioFiles = audioFilesInDirectory(folderURL)
        if audioFiles.isEmpty {
            LocalFolderBookmarkStore.delete(for: bookmarkKey)
            // Cloud providers (Dropbox etc.) only grant access to the picked file.
            return try registerFolderFromFiles([fileURL], folder: folder, context: context)
        }

        try insertFolderBookmarkShow(
            bookmarkKey: bookmarkKey,
            displayName: folderDisplayName(for: folderURL),
            audioFiles: audioFiles,
            folder: folder,
            context: context
        )
        return ImportResult(imported: audioFiles.count, failed: 0)
    }

    // Register multiple audio files as one show without copying.
    // Each file gets its own security-scoped bookmark for Dropbox / cloud access.
    static func registerFolderFromFiles(
        _ fileURLs: [URL],
        folder: Folder?,
        context: ModelContext
    ) throws -> ImportResult {
        try PlanStore.shared.validateCanRegisterShow(context: context)

        let sortedURLs = fileURLs
            .filter { audioExtensions.contains($0.pathExtension.lowercased()) }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
        guard !sortedURLs.isEmpty else {
            return ImportResult(imported: 0, failed: 0)
        }

        let parentURL = sortedURLs[0].deletingLastPathComponent()
        let sameParent = sortedURLs.allSatisfy { $0.deletingLastPathComponent() == parentURL }
        let displayName = sameParent
            ? folderDisplayName(for: parentURL)
            : LocalizedStrings.current.localFilesShowTitle

        let showKey = UUID().uuidString
        let show = Show(
            title: displayName,
            feedURL: "localfile://show/\(showKey)"
        )
        context.insert(show)
        linkShow(show, to: folder)

        var imported = 0
        var failed = 0

        for (index, sourceURL) in sortedURLs.enumerated() {
            let accessed = sourceURL.startAccessingSecurityScopedResource()
            defer { if accessed { sourceURL.stopAccessingSecurityScopedResource() } }

            let bookmarkKey = UUID().uuidString
            guard let data = try? sourceURL.bookmarkData(
                options: bookmarkOptions,
                includingResourceValuesForKeys: nil,
                relativeTo: nil
            ) else {
                failed += 1
                continue
            }
            do {
                try LocalFolderBookmarkStore.save(data, for: bookmarkKey)
            } catch {
                failed += 1
                continue
            }

            let rawTitle = sourceURL.deletingPathExtension().lastPathComponent
            let title = rawTitle.isEmpty ? LocalizedStrings.current.untitledEpisode : rawTitle
            let publishedAt = Date.now.addingTimeInterval(Double(index))
            let episode = Episode(
                title: title,
                audioURL: "localfile://\(bookmarkKey)",
                publishedAt: publishedAt,
                sortOrder: index,
                show: show
            )
            context.insert(episode)
            imported += 1
        }

        guard imported > 0 else {
            context.delete(show)
            return ImportResult(imported: 0, failed: failed)
        }

        context.processPendingChanges()
        try context.save()
        NotificationCenter.default.post(name: .libraryContentDidChange, object: nil)
        return ImportResult(imported: imported, failed: failed)
    }

    // MARK: - Private

    private static func audioFilesInDirectory(_ directoryURL: URL) -> [URL] {
        let contents = (try? FileManager.default.contentsOfDirectory(
            at: directoryURL,
            includingPropertiesForKeys: nil
        )) ?? []
        return contents
            .filter { audioExtensions.contains($0.pathExtension.lowercased()) }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
    }

    private static func folderDisplayName(for folderURL: URL) -> String {
        let folderName = folderURL.lastPathComponent
        return folderName.isEmpty ? LocalizedStrings.current.localFilesShowTitle : folderName
    }

    private static func insertFolderBookmarkShow(
        bookmarkKey: String,
        displayName: String,
        audioFiles: [URL],
        folder: Folder?,
        context: ModelContext
    ) throws {
        let show = Show(title: displayName, feedURL: "localfolder://\(bookmarkKey)")
        context.insert(show)
        linkShow(show, to: folder)

        for (index, audioFileURL) in audioFiles.enumerated() {
            let rawTitle = audioFileURL.deletingPathExtension().lastPathComponent
            let title = rawTitle.isEmpty ? LocalizedStrings.current.untitledEpisode : rawTitle
            let publishedAt = Date.now.addingTimeInterval(Double(index))
            let episode = Episode(
                title: title,
                audioURL: "localfolder://\(bookmarkKey)/\(audioFileURL.lastPathComponent)",
                publishedAt: publishedAt,
                sortOrder: index,
                show: show
            )
            context.insert(episode)
        }

        context.processPendingChanges()
        try context.save()
        NotificationCenter.default.post(name: .libraryContentDidChange, object: nil)
    }

    private static func linkShow(_ show: Show, to folder: Folder?) {
        guard let folder else { return }
        folder.shows.append(show)
        show.groups.append(folder)
    }

    private static func copyAndRegister(
        sourceURL: URL,
        index: Int,
        show: Show,
        destDir: URL,
        context: ModelContext
    ) throws {
        let uuid = UUID().uuidString
        let ext = sourceURL.pathExtension.isEmpty ? "mp3" : sourceURL.pathExtension
        let destURL = destDir.appendingPathComponent("\(uuid).\(ext)")
        try FileManager.default.copyItem(at: sourceURL, to: destURL)

        let audioURL = "local://\(uuid)"
        let rawTitle = sourceURL.deletingPathExtension().lastPathComponent
        let title = rawTitle.isEmpty ? LocalizedStrings.current.untitledEpisode : rawTitle
        // Sequential offsets preserve filename-sorted playback order via nextEpisodeToAutoPlay.
        let publishedAt = Date.now.addingTimeInterval(Double(index))
        let episode = Episode(
            title: title,
            audioURL: audioURL,
            publishedAt: publishedAt,
            sortOrder: index,
            show: show
        )
        episode.downloadedAudioPath = destURL.path
        context.insert(episode)
    }

    private static func fetchLocalShow(context: ModelContext) -> Show? {
        let feedURL = localShowFeedURL
        let descriptor = FetchDescriptor<Show>(predicate: #Predicate { $0.feedURL == feedURL })
        return try? context.fetch(descriptor).first
    }

    private static func fetchOrCreateLocalShow(in folder: Folder?, context: ModelContext) -> Show {
        if let existing = fetchLocalShow(context: context) { return existing }
        let show = Show(
            title: LocalizedStrings.current.localFilesShowTitle,
            feedURL: localShowFeedURL
        )
        context.insert(show)
        linkShow(show, to: folder)
        return show
    }

    private static func localStorageDirectory() throws -> URL {
        let fm = FileManager.default
        let dir = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("LocalFileImports", isDirectory: true)
        try fm.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }
}
