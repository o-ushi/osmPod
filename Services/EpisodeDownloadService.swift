import Foundation
import SwiftData

@MainActor
@Observable
final class EpisodeDownloadService {
    enum DownloadError: LocalizedError {
        case invalidSourceURL

        var errorDescription: String? {
            LocalizedStrings.current.downloadInvalidSourceURL
        }
    }

    private(set) var downloadingEpisodeIDs: Set<PersistentIdentifier> = []

    func isDownloading(_ episode: Episode) -> Bool {
        downloadingEpisodeIDs.contains(episode.persistentModelID)
    }

    func isDownloaded(_ episode: Episode) -> Bool {
        guard let path = episode.downloadedAudioPath else { return false }
        return FileManager.default.fileExists(atPath: path)
    }

    func toggleDownload(for episode: Episode, context: ModelContext) async throws {
        if isDownloaded(episode) {
            try removeDownload(for: episode, context: context)
        } else {
            try await download(episode, context: context)
        }
    }

    func download(_ episode: Episode, context: ModelContext) async throws {
        guard let sourceURL = URL(string: episode.audioURL) else {
            throw DownloadError.invalidSourceURL
        }

        downloadingEpisodeIDs.insert(episode.persistentModelID)
        defer { downloadingEpisodeIDs.remove(episode.persistentModelID) }

        let destinationURL = try localStorageURL(for: episode.audioURL)
        let (temporaryURL, _) = try await URLSession.shared.download(from: sourceURL)

        let fm = FileManager.default
        if fm.fileExists(atPath: destinationURL.path) {
            try fm.removeItem(at: destinationURL)
        }
        try fm.moveItem(at: temporaryURL, to: destinationURL)

        episode.downloadedAudioPath = destinationURL.path
        try context.save()
    }

    func removeDownload(for episode: Episode, context: ModelContext) throws {
        if let path = episode.downloadedAudioPath {
            let localURL = URL(fileURLWithPath: path)
            if FileManager.default.fileExists(atPath: localURL.path) {
                try FileManager.default.removeItem(at: localURL)
            }
        }
        episode.downloadedAudioPath = nil
        try context.save()
    }

    private func localStorageURL(for sourceURLString: String) throws -> URL {
        let fm = FileManager.default
        let baseDir = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("EpisodeDownloads", isDirectory: true)
        try fm.createDirectory(at: baseDir, withIntermediateDirectories: true)

        let safeName = sourceURLString
            .replacingOccurrences(of: "https://", with: "")
            .replacingOccurrences(of: "http://", with: "")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "?", with: "_")
            .replacingOccurrences(of: "&", with: "_")
        return baseDir.appendingPathComponent(safeName)
    }
}
