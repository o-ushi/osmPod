import SwiftUI
import SwiftData

struct EpisodeSearchRowView: View {
    @Environment(PlaybackChromeState.self) private var playbackChrome

    @AppStorage("dateFormat") private var dateFormatRaw: String = DateFormat.yyyyMMdd.rawValue

    let episode: Episode
    let isSelected: Bool
    let onTap: () -> Void

    private var dateFormat: DateFormat { DateFormat(rawValue: dateFormatRaw) ?? .yyyyMMdd }
    private let newEpisodeIndicatorColor = Color(red: 0.67, green: 0.9, blue: 0.25)

    var body: some View {
        Button(action: onTap) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundStyle(isSelected ? AnyShapeStyle(.tint) : AnyShapeStyle(.secondary))
                    .animation(.easeInOut(duration: 0.15), value: isSelected)

                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        if episode.isPlayed {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.caption)
                                .foregroundStyle(.green)
                        }
                        if episode.isNew {
                            Circle()
                                .fill(newEpisodeIndicatorColor)
                                .frame(width: 8, height: 8)
                        }
                        if episode.isFavorite {
                            Image(systemName: "star.fill")
                                .font(.caption)
                                .foregroundStyle(.yellow)
                        }
                        Text(episodeTitle)
                            .font(.subheadline)
                            .fontWeight(.medium)
                            .lineLimit(2)
                            .foregroundStyle(
                                isCurrentlyPlaying
                                    ? AnyShapeStyle(.tint)
                                    : AnyShapeStyle(.primary)
                            )
                            .episodePlayedStateLongPress(episode: episode)
                    }

                    Text(episode.show.title)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)

                    if let publishedAt = episode.publishedAt {
                        Text(publishedAt.compactDisplayString(format: dateFormat))
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }

                    if !episode.groups.isEmpty {
                        groupBadges
                    }
                }

                Spacer(minLength: 0)
            }
            .padding(.vertical, 4)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var episodeTitle: String {
        if let number = episode.number {
            return "#\(number) \(episode.title)"
        }
        return episode.title
    }

    private var isCurrentlyPlaying: Bool {
        guard playbackChrome.isPlaying,
              let id = playbackChrome.nowPlayingEpisodeID else { return false }
        return id == episode.persistentModelID
    }

    private var groupBadges: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 4) {
                ForEach(episode.groups) { group in
                    Text(group.name)
                        .font(.caption2)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(.tint.opacity(0.12))
                        .foregroundStyle(.tint)
                        .clipShape(Capsule())
                }
            }
        }
    }
}
