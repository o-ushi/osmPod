import Foundation

@MainActor
@Observable
final class ShareImportCoordinator {
    var pendingURLs: [String] = []
    var isPresentingImport = false

    func handleIncomingURL(_ url: URL) {
        guard url.scheme?.lowercased() == "osmpod" else { return }
        guard url.host?.lowercased() == "import-shared-shows" else { return }
        presentConsumedURLs()
    }

    func presentConsumedURLs() {
        let urls = ShareImportStorage.consumePendingURLs()
        guard !urls.isEmpty else { return }
        pendingURLs = urls
        isPresentingImport = true
    }

    func clear() {
        pendingURLs = []
        isPresentingImport = false
    }
}
