import SwiftUI
import SwiftData
import UniformTypeIdentifiers

private enum AddShowMethod: String, CaseIterable, Identifiable {
    case inAppSearch
    case googleAI
    case directRSS
    case localFiles

    var id: String { rawValue }

    func label(strings: LocalizedStrings) -> String {
        switch self {
        case .inAppSearch: strings.addShowMethodInApp
        case .googleAI: strings.addShowMethodGoogleAI
        case .directRSS: strings.addShowMethodDirectRSS
        case .localFiles: strings.addShowMethodLocalFiles
        }
    }
}

struct AddShowView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Environment(LanguageSettings.self) private var lang
    @Environment(PlanStore.self) private var planStore
    @Query(sort: \Folder.sortOrder) private var folders: [Folder]

    @State private var selectedMethod: AddShowMethod = .inAppSearch
    @State private var feedURLText = ""
    @State private var titleText = ""
    @State private var artworkURLText = ""
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var previewResult: PodcastSearchResult?
    @State private var knownFeedURLs: Set<String> = []
    @State private var isPresentingFilePicker = false
    @State private var isPresentingFolderPicker = false
    @State private var importResultMessage: String?
    @State private var selectedFolder: Folder?

    var body: some View {
        let s = lang.strings
        NavigationStack {
            Form {
                methodPickerSection(strings: s)
                methodContent(strings: s)
                if let errorMessage {
                    Section {
                        Text(errorMessage)
                            .foregroundStyle(.red)
                    }
                }
            }
            .disabled(isLoading)
            .navigationTitle(s.addShow)
            .onAppear {
                knownFeedURLs = PodcastShowRegistration.existingFeedURLs(in: modelContext)
                if selectedFolder == nil {
                    selectedFolder = FolderReorderService.orderedRootFolders(folders).first
                }
            }
            .fileImporter(
                isPresented: $isPresentingFilePicker,
                allowedContentTypes: [.audio],
                allowsMultipleSelection: true
            ) { result in
                Task { @MainActor in await handleFileImport(result: result, strings: s) }
            }
            .fileImporter(
                isPresented: $isPresentingFolderPicker,
                allowedContentTypes: [.folder, .audio],
                allowsMultipleSelection: true
            ) { result in
                Task { @MainActor in await handleFolderImport(result: result, strings: s) }
            }
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button { dismiss() } label: {
                        Image(systemName: "xmark")
                    }
                    .disabled(isLoading)
                }
                if selectedMethod == .directRSS {
                    ToolbarItem(placement: .topBarTrailing) {
                        if isLoading {
                            ProgressView()
                        } else {
                            Button {
                                Task { @MainActor in await registerShow(strings: s) }
                            } label: {
                                Image(systemName: "plus")
                            }
                            .disabled(feedURLText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        }
                    }
                }
            }
        }
        .sheet(item: $previewResult) { result in
            PodcastShowPreviewSheet(
                result: result,
                initialFolder: folders.first(where: \.isRoot),
                isAlreadyRegistered: knownFeedURLs.contains(result.feedUrl ?? ""),
                knownFeedURLs: knownFeedURLs,
                onSaved: {
                    knownFeedURLs = PodcastShowRegistration.existingFeedURLs(in: modelContext)
                    previewResult = nil
                    dismiss()
                },
                onPreviewRelated: { related in
                    previewResult = related
                }
            )
        }
    }

    // MARK: - Form Sections

    private func methodPickerSection(strings s: LocalizedStrings) -> some View {
        Section(s.addShowMethodSection) {
            Picker(s.addShowMethodSection, selection: $selectedMethod) {
                ForEach(AddShowMethod.allCases) { method in
                    Text(method.label(strings: s)).tag(method)
                }
            }
            .pickerStyle(.inline)
            .labelsHidden()
        }
    }

    @ViewBuilder
    private func methodContent(strings s: LocalizedStrings) -> some View {
        switch selectedMethod {
        case .inAppSearch:
            PodcastSearchView(
                knownFeedURLs: $knownFeedURLs,
                onSelectResult: { result in
                    previewResult = result
                }
            )
        case .googleAI:
            PodcastDiscoveryAIView(
                onImported: { dismiss() },
                onPasteURL: { url in
                    feedURLText = url
                    selectedMethod = .directRSS
                }
            )
        case .directRSS:
            feedURLSection(strings: s)
            metadataSection(strings: s)
        case .localFiles:
            localFilesSection(strings: s)
        }
    }

    private func localFilesSection(strings s: LocalizedStrings) -> some View {
        Group {
            if !folders.isEmpty {
                Section(s.targetFolder) {
                    CollapsibleFolderPickerRows(
                        roots: FolderReorderService.orderedRootFolders(folders),
                        selectedFolder: $selectedFolder
                    )
                }
            }
            Section {
                Button {
                    importResultMessage = nil
                    isPresentingFolderPicker = true
                } label: {
                    Label(s.localFilesFolderButton, systemImage: "folder")
                }
                Button {
                    importResultMessage = nil
                    isPresentingFilePicker = true
                } label: {
                    Label(s.localFilesPickerButton, systemImage: "music.note.list")
                }
                if let msg = importResultMessage {
                    Text(msg)
                        .foregroundStyle(.secondary)
                        .font(.footnote)
                }
            } footer: {
                Text(s.localFilesFooter)
            }
        }
    }

    private func feedURLSection(strings s: LocalizedStrings) -> some View {
        Section {
            TextField("https://example.com/feed.xml", text: $feedURLText)
                .keyboardType(.URL)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
        } header: {
            Text(s.rssFeed)
        } footer: {
            Text(s.addShowMethodDirectRSSFooter)
        }
    }

    private func metadataSection(strings s: LocalizedStrings) -> some View {
        Section {
            TextField(s.titlePlaceholder, text: $titleText)
            TextField(s.artworkURLPlaceholder, text: $artworkURLText)
                .keyboardType(.URL)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
        } header: {
            Text(s.showInfoOptional)
        } footer: {
            Text(s.showInfoFooter)
        }
    }

    // MARK: - Local File Import

    @MainActor
    private func handleFileImport(result: Result<[URL], Error>, strings s: LocalizedStrings) async {
        switch result {
        case .failure:
            return
        case .success(let urls):
            guard !urls.isEmpty else { return }
            isLoading = true
            errorMessage = nil
            defer { isLoading = false }
            do {
                let r = try LocalFileImportService.importFiles(
                    urls,
                    folder: selectedFolder,
                    context: modelContext
                )
                importResultMessage = s.localFilesImportedCount(r.imported, failed: r.failed)
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    @MainActor
    private func handleFolderImport(result: Result<[URL], Error>, strings s: LocalizedStrings) async {
        switch result {
        case .failure:
            return
        case .success(let urls):
            guard !urls.isEmpty else { return }
            isLoading = true
            errorMessage = nil
            defer { isLoading = false }
            do {
                let r: LocalFileImportService.ImportResult
                if urls.count == 1, isDirectoryURL(urls[0]) {
                    r = try LocalFileImportService.registerFolder(
                        urls[0],
                        folder: selectedFolder,
                        context: modelContext
                    )
                } else if urls.count == 1 {
                    r = try LocalFileImportService.registerFolderFromFile(
                        urls[0],
                        folder: selectedFolder,
                        context: modelContext
                    )
                } else {
                    r = try LocalFileImportService.registerFolderFromFiles(
                        urls,
                        folder: selectedFolder,
                        context: modelContext
                    )
                }
                if r.imported == 0 {
                    errorMessage = s.localFilesNoAudioFound
                } else {
                    importResultMessage = s.localFilesImportedCount(r.imported, failed: r.failed)
                    dismiss()
                }
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    private func isDirectoryURL(_ url: URL) -> Bool {
        (try? url.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true
    }

    // MARK: - Register

    @MainActor
    private func registerShow(strings s: LocalizedStrings) async {
        let trimmedFeed = feedURLText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard URL(string: trimmedFeed) != nil else {
            errorMessage = s.invalidURLError
            return
        }

        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        do {
            let trimmedTitle = titleText.trimmingCharacters(in: .whitespacesAndNewlines)
            let trimmedArtwork = artworkURLText.trimmingCharacters(in: .whitespacesAndNewlines)
            try await PodcastShowRegistration.register(
                feedURLString: trimmedFeed,
                titleOverride: trimmedTitle.isEmpty ? nil : trimmedTitle,
                artworkOverride: trimmedArtwork.isEmpty ? nil : trimmedArtwork,
                folder: folders.first(where: \.isRoot),
                context: modelContext,
                planStore: planStore
            )
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
