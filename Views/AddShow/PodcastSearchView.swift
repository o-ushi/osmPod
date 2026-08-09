import SwiftUI
import SwiftData

// MARK: - Podcast Discovery View

struct PodcastSearchView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(LanguageSettings.self) private var lang
    @Environment(PlanStore.self) private var planStore

    @Binding var knownFeedURLs: Set<String>
    let onSelectResult: (PodcastSearchResult) -> Void

    @State private var searchText = ""
    @State private var searchResults: [PodcastSearchResult] = []
    @State private var isSearching = false
    @State private var errorMessage: String?
    @State private var showErrorAlert = false
    @State private var selectedMood: DiscoveryMood?

    @State private var todayPick: PodcastSearchResult?
    @State private var topChartPool: [PodcastSearchResult] = []
    @State private var isLoadingTodayPick = false

    private let searchService = ITunesPodcastSearchService()

    init(
        knownFeedURLs: Binding<Set<String>>,
        onSelectResult: @escaping (PodcastSearchResult) -> Void
    ) {
        _knownFeedURLs = knownFeedURLs
        self.onSelectResult = onSelectResult
    }

    var body: some View {
        let s = lang.strings
        Group {
            todayPickSection(strings: s)
            moodSection(strings: s)
            searchInputSection(strings: s)
            resultsSection(strings: s)
        }
        .alert(s.error, isPresented: $showErrorAlert, presenting: errorMessage) { _ in
            Button(s.ok, role: .cancel) {}
        } message: { message in
            Text(message)
        }
        .onAppear {
            refreshKnownURLs()
            Task { await loadTodayPick() }
        }
    }

    // MARK: - Sections

    private func todayPickSection(strings s: LocalizedStrings) -> some View {
        Section {
            if isLoadingTodayPick {
                HStack {
                    Spacer()
                    ProgressView()
                    Spacer()
                }
            } else if let pick = todayPick {
                VStack(alignment: .leading, spacing: 12) {
                    PodcastResultRow(
                        result: pick,
                        strings: s,
                        isRegistered: isRegistered(pick)
                    )
                    HStack(spacing: 12) {
                        Button {
                            onSelectResult(pick)
                        } label: {
                            Label(s.discoverPreviewShow, systemImage: "play.circle")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.bordered)
                        .disabled(pick.feedUrl == nil)

                        Button {
                            Task { await shuffleTodayPick() }
                        } label: {
                            Label(s.discoverAnotherPick, systemImage: "shuffle")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.bordered)
                    }
                }
                .padding(.vertical, 4)
            }
        } header: {
            Label(s.discoverTodayPick, systemImage: "sparkle")
        } footer: {
            Text(s.discoverShowsFooter)
        }
    }

    private func moodSection(strings s: LocalizedStrings) -> some View {
        Section {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(DiscoveryMood.allCases) { mood in
                        Button {
                            Task { await searchMood(mood) }
                        } label: {
                            Label(mood.label(strings: s), systemImage: mood.icon)
                                .font(.subheadline)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 8)
                                .background(
                                    selectedMood == mood
                                        ? AnyShapeStyle(Color.accentColor.opacity(0.2))
                                        : AnyShapeStyle(Color(.secondarySystemGroupedBackground))
                                )
                                .clipShape(Capsule())
                        }
                        .buttonStyle(.plain)
                        .disabled(isSearching)
                    }
                }
                .padding(.vertical, 4)
            }
            .listRowInsets(EdgeInsets(top: 8, leading: 0, bottom: 8, trailing: 0))
        } header: {
            Text(s.discoverMoodsSection)
        }
    }

    private func searchInputSection(strings s: LocalizedStrings) -> some View {
        Section {
            HStack {
                TextField(s.discoverSearchPlaceholder, text: $searchText)
                    .onSubmit { Task { await searchPodcasts() } }
                    .disabled(isSearching)

                if isSearching {
                    ProgressView()
                        .padding(.leading, 4)
                } else {
                    Button(s.search) {
                        Task { await searchPodcasts() }
                    }
                    .disabled(searchText.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        } footer: {
            Text(s.discoverSearchFooter)
        }
    }

    private func resultsSection(strings s: LocalizedStrings) -> some View {
        Section {
            if !searchResults.isEmpty {
                ForEach(searchResults) { result in
                    Button {
                        onSelectResult(result)
                    } label: {
                        PodcastResultRow(
                            result: result,
                            strings: s,
                            isRegistered: isRegistered(result)
                        )
                    }
                    .disabled(result.feedUrl == nil)
                }
            } else if !isSearching && (!searchText.isEmpty || selectedMood != nil) {
                Text(s.noSearchResults)
                    .foregroundStyle(.secondary)
            }
        } header: {
            if !searchResults.isEmpty {
                Text(s.searchResultsCount(searchResults.count))
            }
        }
    }

    // MARK: - Helpers

    private func isRegistered(_ result: PodcastSearchResult) -> Bool {
        guard let url = result.feedUrl else { return false }
        return PodcastShowRegistration.isRegistered(feedURL: url, knownURLs: knownFeedURLs)
    }

    @MainActor
    private func refreshKnownURLs() {
        knownFeedURLs = PodcastShowRegistration.existingFeedURLs(in: modelContext)
    }

    // MARK: - Search

    @MainActor
    private func searchPodcasts() async {
        selectedMood = nil
        let query = searchText.trimmingCharacters(in: .whitespaces)
        guard !query.isEmpty else { return }
        await performSearch(term: query)
    }

    @MainActor
    private func searchMood(_ mood: DiscoveryMood) async {
        selectedMood = mood
        searchText = mood.label(strings: lang.strings)
        let term = mood.searchTerm(language: lang.language)
        await performSearch(term: term)
    }

    @MainActor
    private func performSearch(term: String) async {
        isSearching = true
        searchResults = []
        errorMessage = nil
        defer { isSearching = false }

        do {
            searchResults = try await searchService.search(
                term: term,
                country: lang.language.itunesCountryCode
            )
        } catch {
            errorMessage = error.localizedDescription
            showErrorAlert = true
        }
    }

    // MARK: - Today's Pick

    @MainActor
    private func loadTodayPick() async {
        isLoadingTodayPick = true
        defer { isLoadingTodayPick = false }
        do {
            let pool = try await searchService.fetchTopPodcasts(
                country: lang.language.itunesCountryCode,
                limit: 50
            )
            topChartPool = pool
            todayPick = pickRandom(from: pool)
        } catch {
            todayPick = nil
        }
    }

    @MainActor
    private func shuffleTodayPick() async {
        guard !topChartPool.isEmpty else {
            await loadTodayPick()
            return
        }
        todayPick = pickRandom(from: topChartPool)
    }

    @MainActor
    private func pickRandom(from pool: [PodcastSearchResult]) -> PodcastSearchResult? {
        let candidates = pool.filter { result in
            guard let url = result.feedUrl else { return false }
            return !knownFeedURLs.contains(url)
        }
        let source = candidates.isEmpty ? pool : candidates
        return source.randomElement()
    }
}

// MARK: - Result Row

struct PodcastResultRow: View {
    let result: PodcastSearchResult
    let strings: LocalizedStrings
    var isRegistered: Bool = false

    var body: some View {
        HStack(spacing: 12) {
            Group {
                if let urlString = result.artworkUrl600, let url = URL(string: urlString) {
                    AsyncImage(url: url) { image in
                        image.resizable().aspectRatio(contentMode: .fill)
                    } placeholder: {
                        Color.gray.opacity(0.3)
                    }
                } else {
                    Color.gray.opacity(0.3)
                }
            }
            .frame(width: 60, height: 60)
            .clipShape(RoundedRectangle(cornerRadius: 8))

            VStack(alignment: .leading, spacing: 4) {
                Text(result.collectionName ?? strings.searchPodcast)
                    .font(.headline)
                    .foregroundStyle(.primary)
                    .lineLimit(2)

                Text(result.artistName ?? "")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)

                if isRegistered {
                    Text(strings.discoverAlreadyRegistered)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else if result.feedUrl == nil {
                    Text(strings.invalidURLError)
                        .font(.caption)
                        .foregroundStyle(.red)
                }
            }

            Spacer(minLength: 0)

            if !isRegistered && result.feedUrl != nil {
                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.vertical, 2)
    }
}
