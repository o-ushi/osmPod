import AVFoundation
import Foundation
import os.log

private let prepLog = Logger(subsystem: "com.osamushikubo.osmPod", category: "CloudFilePrep")

/// Dropbox 等の File Provider 経由ファイルはプレースホルダーのままだと AVPlayer が読めない。
/// 再生前に NSFileCoordinator 経由で実体の取得を促し、AVAsset が playable になるまで待つ。
enum BookmarkedFilePlaybackPreparer {
    enum PreparationError: LocalizedError {
        case downloadTimeout
        case unreadable

        var errorDescription: String? {
            let s = LocalizedStrings.current
            switch self {
            case .downloadTimeout:
                return s.cloudFilePreparationTimeout
            case .unreadable:
                return s.cloudFilePreparationUnreadable
            }
        }
    }

    typealias ProgressHandler = @Sendable (Double?) -> Void

    private static let chunkSize = 256 * 1024

    /// 端末に実体があれば `false`（オーバーレイ不要）。
    static func needsPreparation(at fileURL: URL) async -> Bool {
        do {
            let asset = AVURLAsset(url: fileURL)
            return !(try await asset.load(.isPlayable))
        } catch {
            return true
        }
    }

    static func ensurePlayable(
        at fileURL: URL,
        timeout: TimeInterval = 120,
        onProgress: ProgressHandler? = nil
    ) async throws {
        if await !needsPreparation(at: fileURL) {
            onProgress?(1.0)
            return
        }

        onProgress?(nil)

        try await Task.detached(priority: .userInitiated) {
            try prepareSync(at: fileURL, timeout: timeout, onProgress: onProgress)
        }.value

        let asset = AVURLAsset(url: fileURL)
        guard try await asset.load(.isPlayable) else {
            throw PreparationError.unreadable
        }
        onProgress?(1.0)
    }

    private static func prepareSync(
        at fileURL: URL,
        timeout: TimeInterval,
        onProgress: ProgressHandler?
    ) throws {
        let fm = FileManager.default
        if fm.isUbiquitousItem(at: fileURL) {
            try? fm.startDownloadingUbiquitousItem(at: fileURL)
        }

        var coordinationError: NSError?
        var preparationError: Error?
        let coordinator = NSFileCoordinator()

        coordinator.coordinate(readingItemAt: fileURL, options: [], error: &coordinationError) { readingURL in
            do {
                try downloadChunks(
                    at: readingURL,
                    timeout: timeout,
                    onProgress: onProgress
                )
            } catch {
                preparationError = error
            }
        }

        if let coordinationError {
            prepLog.error("NSFileCoordinator failed: \(coordinationError.localizedDescription, privacy: .public)")
            throw coordinationError
        }
        if let preparationError {
            throw preparationError
        }
    }

    /// チャンク読み込みで File Provider のダウンロードを促す。進捗は実際の読み込み量のみ報告する。
    private static func downloadChunks(
        at url: URL,
        timeout: TimeInterval,
        onProgress: ProgressHandler?
    ) throws {
        let deadline = Date().addingTimeInterval(timeout)
        let totalSize = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
        var bytesRead = 0
        var lastError: Error?

        while Date() < deadline {
            if totalSize > 0, bytesRead >= totalSize {
                onProgress?(0.95)
                return
            }

            do {
                let read = try readNextChunk(from: url, bytesAlreadyRead: bytesRead)
                if read > 0 {
                    bytesRead += read
                    onProgress?(downloadProgress(bytesRead: bytesRead, totalSize: totalSize))
                } else {
                    onProgress?(downloadProgress(bytesRead: bytesRead, totalSize: totalSize))
                    Thread.sleep(forTimeInterval: 0.35)
                    let fm = FileManager.default
                    if fm.isUbiquitousItem(at: url) {
                        try? fm.startDownloadingUbiquitousItem(at: url)
                    }
                }
            } catch {
                lastError = error
                prepLog.debug("chunk read failed: \(error.localizedDescription, privacy: .public)")
                Thread.sleep(forTimeInterval: 0.35)
            }
        }

        prepLog.error("cloud file prep timed out: \(url.lastPathComponent, privacy: .public)")
        throw lastError ?? PreparationError.downloadTimeout
    }

    private static func readNextChunk(from url: URL, bytesAlreadyRead: Int) throws -> Int {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        if bytesAlreadyRead > 0 {
            try handle.seek(toOffset: UInt64(bytesAlreadyRead))
        }
        guard let chunk = try handle.read(upToCount: chunkSize), !chunk.isEmpty else {
            return 0
        }
        return chunk.count
    }

    /// メタデータの allocated size は File Provider で不正確なことがあるため、実際の読み込み量のみ使う。
    private static func downloadProgress(bytesRead: Int, totalSize: Int) -> Double? {
        guard totalSize > 0 else { return nil }
        return min(0.95, Double(bytesRead) / Double(totalSize))
    }
}
