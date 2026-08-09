import Foundation
import SwiftData

@Model
final class Episode {
    var number: Int?
    var title: String
    @Attribute(.unique) var audioURL: String
    var artworkURL: String?
    var publishedAt: Date?
    var summary: String
    var playbackPosition: TimeInterval
    var totalDuration: TimeInterval
    var sortOrder: Int
    var isPlayedRaw: Bool?
    var isFavoriteRaw: Bool?
    var isNewRaw: Bool?
    var downloadedAudioPath: String?

    var show: Show

    @Relationship(inverse: \Folder.episodes)
    var groups: [Folder]

    init(
        number: Int? = nil,
        title: String,
        audioURL: String,
        artworkURL: String? = nil,
        publishedAt: Date? = nil,
        summary: String = "",
        playbackPosition: TimeInterval = 0,
        totalDuration: TimeInterval = 0,
        sortOrder: Int = 0,
        isPlayed: Bool = false,
        isFavorite: Bool = false,
        isNew: Bool = false,
        downloadedAudioPath: String? = nil,
        show: Show,
        groups: [Folder] = []
    ) {
        self.number = number
        self.title = title
        self.audioURL = audioURL
        self.artworkURL = artworkURL
        self.publishedAt = publishedAt
        self.summary = summary
        self.playbackPosition = playbackPosition
        self.totalDuration = totalDuration
        self.sortOrder = sortOrder
        self.isPlayedRaw = isPlayed
        self.isFavoriteRaw = isFavorite
        self.isNewRaw = isNew
        self.downloadedAudioPath = downloadedAudioPath
        self.show = show
        self.groups = groups
    }

    var isPlayed: Bool {
        get { isPlayedRaw ?? false }
        set { isPlayedRaw = newValue }
    }

    var isFavorite: Bool {
        get { isFavoriteRaw ?? false }
        set { isFavoriteRaw = newValue }
    }

    var isNew: Bool {
        get { isNewRaw ?? false }
        set { isNewRaw = newValue }
    }
}

extension Date {
    func compactDisplayString(format: DateFormat) -> String {
        let calendar = Calendar.current
        let year = calendar.component(.year, from: self)
        let month = calendar.component(.month, from: self)
        let day = calendar.component(.day, from: self)
        switch format {
        case .yyyyMMdd:
            return String(format: "%04d/%02d/%02d", year, month, day)
        case .ddMMyyyy:
            return String(format: "%02d/%02d/%04d", day, month, year)
        }
    }
}
