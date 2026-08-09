import SwiftUI
import SwiftData

struct PodcastDiscoveryAIView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(LanguageSettings.self) private var lang
    @Environment(PlanStore.self) private var planStore
    @Query(sort: \Folder.sortOrder) private var folders: [Folder]

    var onImported: (() -> Void)?
    var onPasteURL: (String) -> Void

    @State private var queryText = ""
    @State private var clipboardURLs: [String] = []
    @State private var feedPreviews: [String: ParsedFeed.Channel] = [:]
    @State private var selectedURLs: Set<String> = []
    @State private var isLoadingPreviews = false
    @State private var isImporting = false
    @State private var errorMessage: String?
    @State private var showErrorAlert = false
    @State private var showSendConfirmation = false
    @State private var pendingPreviewURLs: [String] = []
    @State private var showRSSFetchConfirmation = false

    var body: some View {
        let s = lang.strings
        Group {
            hintSection(strings: s)
            querySection(strings: s)
            actionSection(strings: s)
            clipboardImportSection(strings: s)
            pasteSection(strings: s)
        }
        .alert(s.error, isPresented: $showErrorAlert, presenting: errorMessage) { _ in
            Button(s.ok, role: .cancel) {}
        } message: { message in
            Text(message)
        }
        .alert(s.sendToGoogleConfirmTitle, isPresented: $showSendConfirmation) {
            Button(s.cancel, role: .cancel) {}
            Button(s.sendToGoogleConfirmSend) { openGoogleAI() }
        } message: {
            Text(s.sendToGoogleConfirmMessage(topic: queryText.trimmingCharacters(in: .whitespacesAndNewlines)))
        }
        .alert(s.discoverRSSFetchConfirmTitle, isPresented: $showRSSFetchConfirmation) {
            Button(s.cancel, role: .cancel) {
                pendingPreviewURLs = []
            }
            Button(s.discoverRSSFetchConfirmButton) {
                let urls = pendingPreviewURLs
                pendingPreviewURLs = []
                Task { @MainActor in await loadFeedPreviews(for: urls) }
            }
        } message: {
            Text(s.discoverRSSFetchConfirmMessage(urls: pendingPreviewURLs))
        }
    }

    // MARK: - Sections

    private func hintSection(strings s: LocalizedStrings) -> some View {
        Section {
            Label(s.discoverWithAIWelcome, systemImage: "sparkles")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }

    private func querySection(strings s: LocalizedStrings) -> some View {
        Section(s.discoverWithAIQueryLabel) {
            TextField(s.discoverWithAIPlaceholder, text: $queryText)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
        }
    }

    private func actionSection(strings s: LocalizedStrings) -> some View {
        Section {
            Button {
                showSendConfirmation = true
            } label: {
                HStack {
                    Spacer()
                    Label(s.discoverWithAIButton, systemImage: "safari")
                        .fontWeight(.semibold)
                    Spacer()
                }
            }
        } footer: {
            Text(s.discoverWithAIFooter)
        }
    }

    private func clipboardImportSection(strings s: LocalizedStrings) -> some View {
        Section {
            Button {
                scanClipboard()
            } label: {
                Label(s.discoverScanClipboard, systemImage: "doc.on.clipboard")
            }
            .disabled(isLoadingPreviews || isImporting)

            if isLoadingPreviews {
                HStack {
                    Spacer()
                    ProgressView(s.discoverLoadingFeeds)
                    Spacer()
                }
            } else if clipboardURLs.isEmpty {
                Text(s.discoverNoURLsInClipboard)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(clipboardURLs, id: \.self) { url in
                    Button {
                        toggleSelection(url)
                    } label: {
                        HStack(alignment: .top, spacing: 12) {
                            Image(systemName: selectedURLs.contains(url) ? "checkmark.circle.fill" : "circle")
                                .foregroundStyle(selectedURLs.contains(url) ? Color.accentColor : Color.secondary)
                            VStack(alignment: .leading, spacing: 4) {
                                Text(feedPreviews[url]?.title ?? url)
                                    .font(.subheadline.weight(.medium))
                                    .foregroundStyle(.primary)
                                    .lineLimit(2)
                                Text(url)
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                            }
                        }
                    }
                    .disabled(isImporting)
                }

                Button {
                    Task { @MainActor in await importSelected(strings: s) }
                } label: {
                    HStack {
                        Spacer()
                        if isImporting {
                            ProgressView()
                        } else {
                            Label(s.discoverImportSelected(selectedURLs.count), systemImage: "plus.circle.fill")
                                .fontWeight(.semibold)
                        }
                        Spacer()
                    }
                }
                .disabled(selectedURLs.isEmpty || isImporting)
            }
        } header: {
            Text(s.discoverBatchImportTitle)
        } footer: {
            Text(s.discoverBatchImportFooter)
        }
    }

    private func pasteSection(strings s: LocalizedStrings) -> some View {
        Section {
            Button {
                pasteSingleURL()
            } label: {
                Label(s.pasteToRSSInput, systemImage: "arrow.down.doc")
            }
            .disabled(isImporting)
        } footer: {
            Text(s.pasteToRSSInputFooter)
        }
    }

    // MARK: - Actions

    private func openGoogleAI() {
        var components = URLComponents(string: "https://www.google.com/search")!
        components.queryItems = [
            URLQueryItem(name: "q", value: buildQuery()),
            URLQueryItem(name: "udm", value: "50"),
        ]
        guard let url = components.url else { return }
        UIApplication.shared.open(url)
    }

    private func buildQuery() -> String {
        let topic = queryText.trimmingCharacters(in: .whitespacesAndNewlines)
        return lang.strings.discoverWithAIQuery(topic: topic)
    }

    private func pasteSingleURL() {
        guard let text = UIPasteboard.general.string else {
            errorMessage = lang.strings.discoverNoURLsInClipboard
            showErrorAlert = true
            return
        }
        let urls = RSSURLExtractor.extractURLs(from: text)
        guard let first = urls.first else {
            errorMessage = lang.strings.discoverNoURLsInClipboard
            showErrorAlert = true
            return
        }
        onPasteURL(first)
    }

    private func scanClipboard() {
        guard let text = UIPasteboard.general.string else {
            clipboardURLs = []
            selectedURLs = []
            feedPreviews = [:]
            return
        }
        let urls = RSSURLExtractor.extractURLs(from: text)
        clipboardURLs = urls
        selectedURLs = Set(urls)
        guard !urls.isEmpty else {
            feedPreviews = [:]
            return
        }
        feedPreviews = [:]
        pendingPreviewURLs = urls
        showRSSFetchConfirmation = true
    }

    private func toggleSelection(_ url: String) {
        if selectedURLs.contains(url) {
            selectedURLs.remove(url)
        } else {
            selectedURLs.insert(url)
        }
    }

    @MainActor
    private func loadFeedPreviews(for urls: [String]) async {
        isLoadingPreviews = true
        defer { isLoadingPreviews = false }
        var previews: [String: ParsedFeed.Channel] = [:]
        for urlString in urls {
            guard let url = URL(string: urlString) else { continue }
            if let feed = try? await FeedParserService().parse(feedURL: url) {
                previews[urlString] = feed.channel
            }
        }
        feedPreviews = previews
    }

    @MainActor
    private func importSelected(strings s: LocalizedStrings) async {
        let urls = clipboardURLs.filter { selectedURLs.contains($0) }
        guard !urls.isEmpty else { return }

        isImporting = true
        errorMessage = nil
        defer { isImporting = false }

        var imported = 0
        var lastError: String?

        for urlString in urls {
            do {
                try await PodcastShowRegistration.register(
                    feedURLString: urlString,
                    titleOverride: feedPreviews[urlString]?.title,
                    artworkOverride: feedPreviews[urlString]?.artworkURL,
                    folder: folders.first(where: \.isRoot),
                    context: modelContext,
                    planStore: planStore
                )
                imported += 1
            } catch {
                lastError = error.localizedDescription
            }
        }

        if imported > 0 {
            onImported?()
        } else if let lastError {
            errorMessage = lastError
            showErrorAlert = true
        }
    }
}
