import Foundation
import UIKit

/// メインアプリと Share Extension 間で RSS URL を受け渡す（App Group 不要・同一開発者の名前付きペーストボード）。
enum ShareImportStorage {
    private static let pasteboardName = UIPasteboard.Name("com.osamushikubo.osmPod.shareImport")

    private static var pasteboard: UIPasteboard? {
        UIPasteboard(name: pasteboardName, create: true)
    }

    static func savePendingURLs(_ urls: [String]) {
        guard !urls.isEmpty else { return }
        pasteboard?.string = urls.joined(separator: "\n")
    }

    static func consumePendingURLs() -> [String] {
        guard let text = pasteboard?.string?.trimmingCharacters(in: .whitespacesAndNewlines),
              !text.isEmpty else { return [] }
        pasteboard?.string = ""
        var seen = Set<String>()
        return text
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { url in
                guard !url.isEmpty,
                      let parsed = URL(string: url),
                      let scheme = parsed.scheme?.lowercased(),
                      scheme == "http" || scheme == "https" else { return false }
                return seen.insert(parsed.absoluteString).inserted
            }
    }

    static func clearPendingData() {
        pasteboard?.items = []
    }
}
