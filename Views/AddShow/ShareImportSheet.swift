import SwiftUI
import SwiftData

struct ShareImportSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Environment(LanguageSettings.self) private var lang
    @Environment(PlanStore.self) private var planStore
    @Environment(ShareImportCoordinator.self) private var shareImport
    @Query(sort: \Folder.sortOrder) private var folders: [Folder]

    let urls: [String]

    @State private var feedPreviews: [String: ParsedFeed.Channel] = [:]
    @State private var selectedURLs: Set<String>
    @State private var selectedFolder: Folder?
    @State private var isLoadingPreviews = false
    @State private var isImporting = false
    @State private var errorMessage: String?
    @State private var showErrorAlert = false

    init(urls: [String]) {
        self.urls = urls
        _selectedURLs = State(initialValue: Set(urls))
    }

    var body: some View {
        let s = lang.strings
        NavigationStack {
            Form {
                Section {
                    if isLoadingPreviews {
                        HStack {
                            Spacer()
                            ProgressView(s.discoverLoadingFeeds)
                            Spacer()
                        }
                    } else {
                        ForEach(urls, id: \.self) { url in
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
                    }
                } header: {
                    Text(s.shareImportTitle)
                } footer: {
                    Text(s.shareImportFooter)
                }

                if !folders.isEmpty {
                    Section(s.targetFolder) {
                        CollapsibleFolderPickerRows(
                            roots: folders.filter(\.isRoot),
                            selectedFolder: $selectedFolder
                        )
                    }
                }
            }
            .navigationTitle(s.shareImportTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button(s.close) {
                        shareImport.clear()
                        dismiss()
                    }
                    .disabled(isImporting)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    if isImporting {
                        ProgressView()
                    } else {
                        Button(s.shareImportAdd) {
                            Task { @MainActor in await importSelected(strings: s) }
                        }
                        .disabled(selectedURLs.isEmpty)
                    }
                }
            }
            .alert(s.error, isPresented: $showErrorAlert, presenting: errorMessage) { _ in
                Button(s.ok, role: .cancel) {}
            } message: { message in
                Text(message)
            }
            .onAppear {
                if selectedFolder == nil {
                    selectedFolder = folders.first(where: \.isRoot)
                }
                Task { @MainActor in await loadFeedPreviews() }
            }
        }
    }

    private func toggleSelection(_ url: String) {
        if selectedURLs.contains(url) {
            selectedURLs.remove(url)
        } else {
            selectedURLs.insert(url)
        }
    }

    @MainActor
    private func loadFeedPreviews() async {
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
        let targets = urls.filter { selectedURLs.contains($0) }
        guard !targets.isEmpty else { return }

        isImporting = true
        errorMessage = nil
        defer { isImporting = false }

        var imported = 0
        var lastError: String?

        for urlString in targets {
            do {
                try await PodcastShowRegistration.register(
                    feedURLString: urlString,
                    titleOverride: feedPreviews[urlString]?.title,
                    artworkOverride: feedPreviews[urlString]?.artworkURL,
                    folder: selectedFolder,
                    context: modelContext,
                    planStore: planStore
                )
                imported += 1
            } catch {
                lastError = error.localizedDescription
            }
        }

        if imported > 0 {
            HapticManager.shared.provideFeedback()
            shareImport.clear()
            dismiss()
        } else if let lastError {
            errorMessage = lastError
            showErrorAlert = true
        }
    }
}
