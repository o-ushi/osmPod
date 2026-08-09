import Foundation

/// サムネイル画像をメモリ／ディスクに保持する軽量キャッシュ。
actor ThumbnailImageCache {
    static let shared = ThumbnailImageCache()

    private let memoryCache = NSCache<NSURL, NSData>()
    private let cacheDirectory: URL

    init() {
        // バックグラウンド中の jetsam kill 抑制のためメモリキャッシュに上限を設定する。
        // NSCache は低メモリ時に自動削除するが、上限なしでは削除前に OS が SIGKILL を送ることがある。
        memoryCache.countLimit = 200
        memoryCache.totalCostLimit = 40 * 1024 * 1024  // 40 MB

        let base = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        cacheDirectory = base.appendingPathComponent("osmPodThumbnailCache", isDirectory: true)
        try? FileManager.default.createDirectory(at: cacheDirectory, withIntermediateDirectories: true)
    }

    /// 低メモリ警告時などにメモリキャッシュだけを解放する（ディスクキャッシュは保持）。
    func purgeMemory() {
        memoryCache.removeAllObjects()
    }

    func deleteAll() {
        memoryCache.removeAllObjects()
        try? FileManager.default.removeItem(at: cacheDirectory)
        try? FileManager.default.createDirectory(at: cacheDirectory, withIntermediateDirectories: true)
    }

    func data(for url: URL) async -> Data? {
        let nsURL = url as NSURL
        if let cached = memoryCache.object(forKey: nsURL) {
            return Data(referencing: cached)
        }

        let path = cacheDirectory.appendingPathComponent(cacheFileName(for: url))
        if let diskData = try? Data(contentsOf: path), !diskData.isEmpty {
            memoryCache.setObject(diskData as NSData, forKey: nsURL, cost: diskData.count)
            return diskData
        }

        do {
            var request = URLRequest(url: url)
            request.timeoutInterval = 15
            let (data, response) = try await URLSession.shared.data(for: request)
            guard !data.isEmpty else { return nil }
            if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
                return nil
            }

            memoryCache.setObject(data as NSData, forKey: nsURL, cost: data.count)
            try? data.write(to: path, options: .atomic)
            return data
        } catch {
            return nil
        }
    }

    private func cacheFileName(for url: URL) -> String {
        let key = Data(url.absoluteString.utf8)
            .base64EncodedString()
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "=", with: "")
        return "\(key).img"
    }
}
