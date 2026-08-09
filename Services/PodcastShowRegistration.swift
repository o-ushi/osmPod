import Foundation
import SwiftData

extension Notification.Name {
    /// フォルダ内の番組・エピソード一覧キャッシュの再構築用。
    static let libraryContentDidChange = Notification.Name("osmPod.libraryContentDidChange")
    /// メイン ScrollView 内のエピソード行へスクロールする。
    static let scrollToEpisode = Notification.Name("osmPod.scrollToEpisode")
}

enum EpisodeScrollAnchor {
    static func id(for episode: Episode) -> String {
        id(audioURL: episode.audioURL)
    }

    static func id(audioURL: String) -> String {
        "episode-row-\(audioURL)"
    }

    static func postScroll(to episode: Episode) {
        postScroll(audioURL: episode.audioURL)
    }

    static func postScroll(audioURL: String) {
        NotificationCenter.default.post(
            name: .scrollToEpisode,
            object: nil,
            userInfo: ["audioURL": audioURL]
        )
    }
}

@Observable
@MainActor
final class EpisodeListJumpCoordinator {
    struct Context: Equatable {
        let id: String
        let topAudioURL: String
        let bottomAudioURL: String
    }

    private(set) var activeContext: Context?
    private var contexts: [Context] = []

    func register(_ context: Context) {
        contexts.removeAll { $0.id == context.id }
        contexts.append(context)
        activeContext = context
    }

    func unregister(id: String) {
        contexts.removeAll { $0.id == id }
        activeContext = contexts.last
    }
}

enum PodcastShowRegistration {

    /// 初回登録時に投入するエピソード数。残りは `FeedRefreshService` が後から取り込む。
    static let initialEpisodeImportLimit = 50

    @MainActor
    static func existingFeedURLs(in context: ModelContext) -> Set<String> {
        let shows = (try? context.fetch(FetchDescriptor<Show>())) ?? []
        return Set(shows.map(\.feedURL))
    }

    @MainActor
    static func isRegistered(feedURL: String, knownURLs: Set<String>) -> Bool {
        knownURLs.contains(feedURL)
    }

    @MainActor
    static func register(
        result: PodcastSearchResult,
        parsedFeed: ParsedFeed? = nil,
        folder: Folder?,
        context: ModelContext,
        planStore: PlanStore
    ) async throws {
        guard let feedUrlString = result.feedUrl,
              let feedURL = URL(string: feedUrlString) else {
            throw RegistrationError.missingFeedURL
        }
        let feed: ParsedFeed
        if let parsedFeed {
            feed = parsedFeed
        } else {
            feed = try await FeedParserService().parse(feedURL: feedURL)
        }
        try await register(
            feedURLString: feedUrlString,
            feed: feed,
            title: feed.channel.title.isEmpty ? (result.collectionName ?? LocalizedStrings.current.untitledShow) : feed.channel.title,
            artworkURL: result.artworkUrl600 ?? feed.channel.artworkURL,
            folder: folder,
            context: context,
            planStore: planStore
        )
    }

    @MainActor
    static func register(
        feedURLString: String,
        titleOverride: String?,
        artworkOverride: String?,
        folder: Folder?,
        context: ModelContext,
        planStore: PlanStore,
        parsedFeed: ParsedFeed? = nil
    ) async throws {
        guard let feedURL = URL(string: feedURLString.trimmingCharacters(in: .whitespacesAndNewlines)) else {
            throw RegistrationError.invalidURL
        }
        let feed: ParsedFeed
        if let parsedFeed {
            feed = parsedFeed
        } else {
            feed = try await FeedParserService().parse(feedURL: feedURL)
        }
        let title = titleOverride?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
            ?? feed.channel.title
        let artwork = artworkOverride?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
            ?? feed.channel.artworkURL
        try await register(
            feedURLString: feedURL.absoluteString,
            feed: feed,
            title: title.isEmpty ? LocalizedStrings.current.untitledShow : title,
            artworkURL: artwork,
            folder: folder,
            context: context,
            planStore: planStore
        )
    }

    // MARK: - Private

    @MainActor
    private static func register(
        feedURLString: String,
        feed: ParsedFeed,
        title: String,
        artworkURL: String?,
        folder: Folder?,
        context: ModelContext,
        planStore: PlanStore
    ) async throws {
        if let existing = fetchShow(feedURL: feedURLString, context: context) {
            linkShow(existing, to: folder)
            try persist(context: context)
            return
        }

        try planStore.validateCanRegisterShow(context: context)

        let show = Show(title: title, feedURL: feedURLString, artworkURL: artworkURL, isNew: true)
        context.insert(show)
        linkShow(show, to: folder)

        // フェーズ1: 番組をフォルダに即時反映する（エピソード取得より先にUIに表示させる）
        context.processPendingChanges()
        try context.save()
        NotificationCenter.default.post(name: .libraryContentDidChange, object: nil)

        // フェーズ2: エピソードを挿入して最終保存
        let parser = FeedParserService()
        for episode in parser.makeEpisodes(from: feed, show: show, maxCount: initialEpisodeImportLimit) {
            context.insert(episode)
        }
        try persist(context: context)
    }

    @MainActor
    private static func fetchShow(feedURL: String, context: ModelContext) -> Show? {
        let descriptor = FetchDescriptor<Show>(predicate: #Predicate { $0.feedURL == feedURL })
        return try? context.fetch(descriptor).first
    }

    @MainActor
    private static func linkShow(_ show: Show, to folder: Folder?) {
        guard let folder else { return }
        let alreadyInFolder = folder.shows.contains { $0.feedURL == show.feedURL }
            || show.groups.contains { $0.persistentModelID == folder.persistentModelID }
        guard !alreadyInFolder else { return }
        folder.shows.append(show)
        show.groups.append(folder)
    }

    @MainActor
    private static func persist(context: ModelContext) throws {
        context.processPendingChanges()
        try context.save()
        NewEpisodeIndicatorSync.refreshAll(in: context)
        NotificationCenter.default.post(name: .libraryContentDidChange, object: nil)
    }

    enum RegistrationError: LocalizedError {
        case missingFeedURL
        case invalidURL
        case alreadyRegistered

        var errorDescription: String? {
            LocalizedStrings.current.invalidURLError
        }
    }
}

private extension String {
    var nilIfEmpty: String? {
        isEmpty ? nil : self
    }
}

// MARK: - Feed preview

extension ParsedFeed {
    var latestEpisode: EpisodeItem? {
        episodes.max { lhs, rhs in
            let l = lhs.publishedAt ?? .distantPast
            let r = rhs.publishedAt ?? .distantPast
            return l < r
        } ?? episodes.first
    }
}
