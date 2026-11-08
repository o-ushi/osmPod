import SwiftUI
import SwiftData

struct PodcastShowPreviewSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Environment(LanguageSettings.self) private var lang
    @Environment(PlanStore.self) private var planStore
    @AppStorage("dateFormat") private var dateFormatRaw: String = DateFormat.yyyyMMdd.rawValue

    let result: PodcastSearchResult
    let initialFolder: Folder?
    let isAlreadyRegistered: Bool
    let knownFeedURLs: Set<String>
    let onSaved: () -> Void
    var onPreviewRelated: ((PodcastSearchResult) -> Void)?

    @Query(sort: [SortDescriptor(\Folder.sortOrder)]) private var allFolders: [Folder]

    @State private var parsedFeed: ParsedFeed?
    @State private var relatedResults: [PodcastSearchResult] = []
    @State private var isLoading = true
    @State private var isLoadingRelated = false
    @State private var isSaving = false
    @State private var errorMessage: String?
    @State private var targetFolder: Folder?

    private let relatedShowsService = RelatedShowsService()

    private var dateFormat: DateFormat { DateFormat(rawValue: dateFormatRaw) ?? .yyyyMMdd }

    var body: some View {
        let s = lang.strings
        NavigationStack {
            Group {
                if isLoading {
                    VStack(spacing: 16) {
                        ProgressView()
                        Text(s.discoverLoadingPreview)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 20) {
                            showHeader(strings: s)
                            episodeSection(strings: s)
                            relatedSection(strings: s)
                            if let errorMessage {
                                Text(errorMessage)
                                    .foregroundStyle(.red)
                                    .font(.subheadline)
                            }
                        }
                        .padding()
                    }
                }
            }
            .navigationTitle(s.discoverPreviewTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Group {
                        Button(s.close) { dismiss() }
                            .disabled(isSaving)
                    }
                    .tint(AppPalette.textOnSubpagePrimary)
                }
                .osmPlainBackground()
            }
            .safeAreaInset(edge: .bottom) {
                actionBar(strings: s)
            }
        }
        .task(id: result.id) {
            await loadPreview()
            await loadRelatedShows()
        }
        .onAppear {
            if targetFolder == nil {
                targetFolder = initialFolder ?? allFolders.first(where: \.isRoot)
            }
        }
        .onChange(of: allFolders) { _, newFolders in
            if targetFolder == nil {
                targetFolder = initialFolder ?? newFolders.first(where: \.isRoot)
            }
        }
    }

    @ViewBuilder
    private func relatedSection(strings s: LocalizedStrings) -> some View {
        if isLoadingRelated {
            VStack(alignment: .leading, spacing: 8) {
                Text(s.discoverRelatedShows)
                    .font(.headline)
                ProgressView()
                    .frame(maxWidth: .infinity)
            }
        } else if !relatedResults.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                Text(s.discoverRelatedShows)
                    .font(.headline)
                ForEach(relatedResults) { related in
                    Button {
                        onPreviewRelated?(related)
                    } label: {
                        PodcastResultRow(
                            result: related,
                            strings: s,
                            isRegistered: PodcastShowRegistration.isRegistered(
                                feedURL: related.feedUrl ?? "",
                                knownURLs: knownFeedURLs
                            )
                        )
                    }
                    .buttonStyle(.plain)
                    .disabled(related.feedUrl == nil)
                }
            }
        }
    }

    @ViewBuilder
    private func showHeader(strings s: LocalizedStrings) -> some View {
        HStack(spacing: 14) {
            artworkView
                .frame(width: 88, height: 88)
                .clipShape(RoundedRectangle(cornerRadius: 12))
            VStack(alignment: .leading, spacing: 4) {
                Text(result.collectionName ?? parsedFeed?.channel.title ?? s.searchPodcast)
                    .font(.title3.bold())
                Text(result.artistName ?? "")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                if let genre = result.primaryGenreName, !genre.isEmpty {
                    Text(genre)
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
            }
        }
    }

    @ViewBuilder
    private func episodeSection(strings s: LocalizedStrings) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(s.discoverLatestEpisode)
                .font(.headline)
            if let episode = parsedFeed?.latestEpisode {
                VStack(alignment: .leading, spacing: 6) {
                    Text(episode.title)
                        .font(.subheadline.weight(.semibold))
                    if let publishedAt = episode.publishedAt {
                        Text(publishedAt.compactDisplayString(format: dateFormat))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    if !episode.summary.isEmpty {
                        Text(episode.summary)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(5)
                    }
                }
                .padding()
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color(.secondarySystemGroupedBackground))
                .clipShape(RoundedRectangle(cornerRadius: 12))
            } else {
                Text(s.discoverNoEpisodePreview)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func actionBar(strings s: LocalizedStrings) -> some View {
        VStack(spacing: 0) {
            Divider()
            if isAlreadyRegistered {
                Text(s.discoverAlreadyRegistered)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
                    .padding()
            } else {
                HStack {
                    Text(s.saveToFolder)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Menu {
                        ForEach(allFolders.filter(\.isRoot)) { f in
                            Button(f.name) { targetFolder = f }
                        }
                    } label: {
                        HStack(spacing: 4) {
                            Text(targetFolder?.name ?? s.noFolderSelected)
                                .font(.subheadline)
                                .foregroundStyle(.tint)
                            Image(systemName: "chevron.up.chevron.down")
                                .font(.caption2)
                                .foregroundStyle(.tint)
                        }
                    }
                }
                .padding(.horizontal)
                .padding(.top, 10)

                Button {
                    Task { @MainActor in await saveShow(strings: s) }
                } label: {
                    Group {
                        if isSaving {
                            HStack(spacing: 8) {
                                ProgressView()
                                Text(s.discoverAddingShow)
                            }
                        } else {
                            Text(s.discoverAddShow)
                                .fontWeight(.semibold)
                        }
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .disabled(isSaving || result.feedUrl == nil || isLoading || targetFolder == nil)
                .padding(.horizontal)
                .padding(.vertical, 10)
            }
        }
        .background(.bar)
    }

    @ViewBuilder
    private var artworkView: some View {
        if let urlString = result.artworkUrl600 ?? parsedFeed?.channel.artworkURL,
           let url = URL(string: urlString) {
            AsyncImage(url: url) { image in
                image.resizable().aspectRatio(contentMode: .fill)
            } placeholder: {
                Color.gray.opacity(0.25)
            }
        } else {
            Color.gray.opacity(0.25)
        }
    }

    @MainActor
    private func loadPreview() async {
        guard let feedUrlString = result.feedUrl,
              let feedURL = URL(string: feedUrlString) else {
            isLoading = false
            return
        }
        isLoading = true
        defer { isLoading = false }
        do {
            parsedFeed = try await FeedParserService().parse(feedURL: feedURL)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    @MainActor
    private func loadRelatedShows() async {
        isLoadingRelated = true
        defer { isLoadingRelated = false }
        relatedResults = await relatedShowsService.relatedShows(
            to: result,
            country: lang.language.itunesCountryCode,
            excludingFeedURLs: knownFeedURLs
        )
    }

    @MainActor
    private func saveShow(strings s: LocalizedStrings) async {
        isSaving = true
        errorMessage = nil
        defer { isSaving = false }
        do {
            try await PodcastShowRegistration.register(
                result: result,
                parsedFeed: parsedFeed,
                folder: targetFolder,
                context: modelContext,
                planStore: planStore
            )
            HapticManager.shared.provideFeedback()
            onSaved()
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
