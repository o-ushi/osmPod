import Foundation

struct RelatedShowsService: Sendable {
    private let searchService = ITunesPodcastSearchService()

    func relatedShows(
        to result: PodcastSearchResult,
        country: String,
        excludingFeedURLs: Set<String>,
        limit: Int = 6
    ) async -> [PodcastSearchResult] {
        var queries: [String] = []
        if let genre = result.primaryGenreName?.trimmingCharacters(in: .whitespacesAndNewlines), !genre.isEmpty {
            queries.append("\(genre) podcast")
        }
        if let artist = result.artistName?.trimmingCharacters(in: .whitespacesAndNewlines), !artist.isEmpty {
            queries.append("\(artist) podcast")
        }
        guard !queries.isEmpty else { return [] }

        let selfFeed = result.feedUrl
        var byID: [Int: PodcastSearchResult] = [:]

        for query in queries.prefix(2) {
            guard let batch = try? await searchService.search(term: query, country: country, limit: 15) else {
                continue
            }
            for candidate in batch {
                guard let feedURL = candidate.feedUrl else { continue }
                if feedURL == selfFeed { continue }
                if excludingFeedURLs.contains(feedURL) { continue }
                byID[candidate.id] = candidate
            }
        }

        return Array(byID.values.prefix(limit))
    }
}
