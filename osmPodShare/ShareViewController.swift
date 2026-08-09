import UIKit
import UniformTypeIdentifiers

final class ShareViewController: UIViewController {

    override func viewDidLoad() {
        super.viewDidLoad()
        view.isHidden = true
        Task { await processSharedContent() }
    }

    private func processSharedContent() async {
        guard let items = extensionContext?.inputItems as? [NSExtensionItem] else {
            await finishOnMainActor(openHost: false, urls: [])
            return
        }

        var collected: [String] = []
        for item in items {
            collected.append(contentsOf: await extractURLs(from: item))
        }

        let unique = Array(Set(collected))
        await finishOnMainActor(openHost: !unique.isEmpty, urls: unique)
    }

    private func finishOnMainActor(openHost: Bool, urls: [String]) async {
        await MainActor.run {
            if openHost {
                ShareImportStorage.savePendingURLs(urls)
                if let url = URL(string: "osmpod://import-shared-shows") {
                    extensionContext?.open(url, completionHandler: nil)
                }
            }
            extensionContext?.completeRequest(returningItems: nil, completionHandler: nil)
        }
    }

    private func extractURLs(from item: NSExtensionItem) async -> [String] {
        var urls: [String] = []
        var textChunks: [String] = []

        guard let attachments = item.attachments else { return [] }
        for provider in attachments {
            if provider.hasItemConformingToTypeIdentifier(UTType.url.identifier) {
                if let loaded = try? await provider.loadItem(forTypeIdentifier: UTType.url.identifier) {
                    if let url = loaded as? URL {
                        urls.append(url.absoluteString)
                    } else if let data = loaded as? Data, let url = URL(dataRepresentation: data, relativeTo: nil) {
                        urls.append(url.absoluteString)
                    }
                }
            }
            if provider.hasItemConformingToTypeIdentifier(UTType.plainText.identifier) {
                if let loaded = try? await provider.loadItem(forTypeIdentifier: UTType.plainText.identifier),
                   let text = loaded as? String {
                    textChunks.append(text)
                }
            }
        }

        if let title = item.attributedTitle?.string, !title.isEmpty {
            textChunks.append(title)
        }
        if let content = item.attributedContentText?.string, !content.isEmpty {
            textChunks.append(content)
        }

        let combined = textChunks.joined(separator: "\n")
        urls.append(contentsOf: RSSURLExtractor.extractURLs(from: combined))
        return urls
    }
}
