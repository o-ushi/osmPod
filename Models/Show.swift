import Foundation
import SwiftData

@Model
final class Show {
    var title: String
    @Attribute(.unique) var feedURL: String
    var artworkURL: String?
    var createdAt: Date
    var isNewRaw: Bool?

    @Relationship(deleteRule: .cascade, inverse: \Episode.show)
    var episodes: [Episode]

    @Relationship(inverse: \Folder.shows)
    var groups: [Folder]

    init(
        title: String,
        feedURL: String,
        artworkURL: String? = nil,
        createdAt: Date = .now,
        isNew: Bool = false,
        episodes: [Episode] = [],
        groups: [Folder] = []
    ) {
        self.title = title
        self.feedURL = feedURL
        self.artworkURL = artworkURL
        self.createdAt = createdAt
        self.isNewRaw = isNew
        self.episodes = episodes
        self.groups = groups
    }

    var isNew: Bool {
        get { isNewRaw ?? false }
        set { isNewRaw = newValue }
    }
}
