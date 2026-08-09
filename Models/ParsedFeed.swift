import Foundation

struct ParsedFeed: Sendable {

    struct Channel: Sendable {
        var title: String
        var artworkURL: String?
    }

    struct EpisodeItem: Sendable {
        var title: String
        var audioURL: String
        var artworkURL: String?
        var publishedAt: Date?
        var summary: String
        var number: Int?
    }

    var channel: Channel
    var episodes: [EpisodeItem]
}
